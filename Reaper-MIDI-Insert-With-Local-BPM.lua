-- ============================================================================
-- Script: Reaper-MIDI-Insert-With-Local-BPM.lua
-- Repository: https://github.com/RenZekta/Reaper-MIDI-Insert-With-Local-BPM
-- Description: Inserts a blank MIDI item matching the local BPM and Time 
--              Signature within a Time project timebase environment, 
--              rebuilding loop extents without ghost notes. Matches user PPQ 
--              and CC interpolation preferences, prevents automatic empty 
--              track renaming, enforces two-digit lane naming conventions,
--              preserves track automation modes post-glue, and dynamically
--              reads global default track settings on empty space fallbacks.
-- ============================================================================

reaper.Undo_BeginBlock()

-- 1. Read user preferences for Ticks Per Quarter Note
local PPQ = reaper.SNM_GetIntConfigVar("miditicksperqn", 960)
if PPQ <= 0 then PPQ = 960 end

-- 2. Read user preferences for CC Segment Interpolation Resolution
local CC_RES = reaper.SNM_GetIntConfigVar("midiccinterpres", 32)
if CC_RES <= 0 then CC_RES = 32 end

-- 3. Read global preference for Default Track Automation Mode
local DEFAULT_AUTO_MODE = reaper.SNM_GetIntConfigVar("launchnewtrkmode", 0)
if DEFAULT_AUTO_MODE < 0 then DEFAULT_AUTO_MODE = 0 end

-- 4. Locate active track and current timeline time-selection bounds
local track = reaper.GetSelectedTrack(0, 0)
local time_start, time_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

if track and (time_start ~= time_end) then
  local item_len = time_end - time_start

  -- 5. CACHE TRACK AUTOMATION MODE: Prevents native action 41588 from forcing "Read" mode
  local original_automation_mode = reaper.GetTrackAutomationMode(track)

  -- 6. Inspect original track label state to mitigate native renaming bugs
  local _, track_name_orig = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  local is_track_name_originally_empty = (track_name_orig == "")

  -- 7. Fetch precise local tempo and time signature markers at selection start
  local marker_idx = reaper.FindTempoTimeSigMarker(0, time_start)
  local local_bpm, local_bpi, local_denom
  if marker_idx >= 0 then
    _, _, _, _, local_bpm, local_bpi, local_denom = reaper.GetTempoTimeSigMarker(0, marker_idx)
  else
    local_bpm = reaper.Master_GetTempo()
    local_bpi = 4
    local_denom = 4
  end

  -- 8. Compile Tempo Meta events with strict integer casting
  local us_per_qn = math.floor((60000000 / local_bpm) + 0.5) // 1
  local t1 = string.char((us_per_qn >> 16) & 0xFF)
  local t2 = string.char((us_per_qn >> 8) & 0xFF)
  local t3 = string.char(us_per_qn & 0xFF)

  -- 9. Compile Time Signature Meta events (denominator as a power of two)
  local denom_int = math.floor(local_denom)
  local denom_pow = 2 -- Default fallback to 4 (2^2)
  if denom_int == 1 then denom_pow = 0
  elseif denom_int == 2 then denom_pow = 1
  elseif denom_int == 4 then denom_pow = 2
  elseif denom_int == 8 then denom_pow = 3
  elseif denom_int == 16 then denom_pow = 4
  elseif denom_int == 32 then denom_pow = 5
  end
  local ts1 = string.char(math.floor(local_bpi) // 1 & 0xFF)
  local ts2 = string.char(denom_pow // 1 & 0xFF)

  -- 10. Calculate total clock ticks using user preferred PPQ resolution
  local total_ticks = math.ceil(item_len * (local_bpm / 60.0) * PPQ) // 1
  if total_ticks < 1 then total_ticks = 1 end

  local function vlq(n)
    local s = string.char(n & 0x7F)
    n = n >> 7
    while n > 0 do
      s = string.char((n & 0x7F) | 0x80) .. s
      n = n >> 7
    end
    return s
  end

  -- 11. Construct a fully compliant binary Standard MIDI File (SMF Type 0) layout string
  local header = "MThd\000\000\000\006\000\000\000\001" .. string.char((PPQ >> 8) & 0xFF, PPQ & 0xFF)
  local meta_ts    = "\000\255\088\004" .. ts1 .. ts2 .. "\024\008"
  local meta_tempo = "\000\255\081\003" .. t1 .. t2 .. t3
  local meta_end   = vlq(total_ticks) .. "\255\047\000"

  local track_data  = meta_ts .. meta_tempo .. meta_end
  local track_chunk = "MTrk" .. string.pack(">I4", #track_data) .. track_data

  -- 12. Write binary string payload to a temporary file disk cache
  local temp_path = reaper.GetResourcePath() .. "/temp_physical_import.mid"
  local file = io.open(temp_path, "wb")
  if file then
    file:write(header .. track_chunk)
    file:close()

    -- Cache view positions and clear item selection matrix to target the imported asset safely
    local original_cursor = reaper.GetCursorPosition()
    reaper.SetEditCurPos(time_start, false, false)
    reaper.Main_OnCommand(40289, 0) -- Item: Unselect all items

    -- 13. Execute programmatic file parsing via native asset import routine
    reaper.InsertMedia(temp_path, 0)

    local imported_item = reaper.GetSelectedMediaItem(0, 0)
    if imported_item then
      -- DYNAMIC CONTEXT ROUTING: Identify the actual parent track of the inserted block
      -- This catches if REAPER spawned a brand new track in empty workspace zones
      local actual_track = reaper.GetMediaItemTrack(imported_item)
      local is_new_fallback_track = (actual_track ~= track)

      -- Lock the container's physical layout bounds to absolute Time coordinates
      reaper.SetMediaItemInfo_Value(imported_item, "C_BEATATTACHMODE", 0)
      reaper.SetMediaItemInfo_Value(imported_item, "D_LENGTH", item_len)

      -- Fire SWS metadata compiler to detach the item map from the master clock track
      local sws = reaper.NamedCommandLookup("_BR_ME_TOGGLE_IGNORE_TEMPO_PO_START")
      if sws ~= 0 then reaper.Main_OnCommand(sws, 0) end

      -- Flatten external hard drive asset pointer to an internal in-project take type
      reaper.Main_OnCommand(40401, 0) -- Item: Convert active take MIDI to in-project

      -- Native Glue Rebuild: Discards old structure boundaries and maps the new 
      -- database source extent precisely to the item's current physical boundaries.
      reaper.Main_OnCommand(41588, 0) -- Item: Glue items, ignoring time selection

      -- Re-fetch the newly instantiated glued item object handle to lock its properties
      local final_item = reaper.GetSelectedMediaItem(0, 0) or imported_item
      reaper.SetMediaItemInfo_Value(final_item, "C_BEATATTACHMODE", 0)
      reaper.SetMediaItemInfo_Value(final_item, "D_LENGTH", item_len)
      reaper.SetMediaItemInfo_Value(final_item, "B_LOOPSRC", 1) -- Ensure edge-drag looping is active
      
      -- 14. Seamless Two-Digit Lane Naming & Erase Mitigation Logic
      local final_take = reaper.GetActiveTake(final_item)
      if final_take then
        -- Format top-to-bottom lane number index string using the verified parent track lane
        local track_idx = math.floor(reaper.GetMediaTrackInfo_Value(actual_track, "IP_TRACKNUMBER"))
        local track_idx_str = string.format("%02d", track_idx)
        
        local custom_take_name
        if is_new_fallback_track then
          -- Fallback track state: Cleanly name item to lane index and reset track name leak
          custom_take_name = string.format("%s-MIDI", track_idx_str)
          reaper.GetSetMediaTrackInfo_String(actual_track, "P_NAME", "", true)
          reaper.SetTrackAutomationMode(actual_track, DEFAULT_AUTO_MODE) -- Apply user's custom preference default
        elseif is_track_name_originally_empty then
          -- Existing blank track state: Format item and erase file name leak from header
          custom_take_name = string.format("%s-MIDI", track_idx_str)
          reaper.GetSetMediaTrackInfo_String(actual_track, "P_NAME", "", true)
          reaper.SetTrackAutomationMode(actual_track, original_automation_mode)
        else
          -- Existing labeled track state: Format item mapping cleanly with cached label
          custom_take_name = string.format("%s-%s-MIDI", track_idx_str, track_name_orig)
          reaper.SetTrackAutomationMode(actual_track, original_automation_mode)
        end
        
        -- Flash finalized name parameters cleanly into the active take metadata string
        reaper.GetSetMediaItemTakeInfo_String(final_take, "P_NAME", custom_take_name, true)
      end
      
      -- If fallback routing didn't trigger, double check original track safety bounds
      if not is_new_fallback_track then
        reaper.SetTrackAutomationMode(track, original_automation_mode)
      end
    else
      -- Absolute safety fallback if no item structure parsed cleanly
      reaper.SetTrackAutomationMode(track, original_automation_mode)
    end

    -- Clean environment states and purge hard drive file cache
    reaper.SetEditCurPos(original_cursor, false, false)
    os.remove(temp_path)
  end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Physical MIDI Import (Clean Two-Digit Naming)", -1)
