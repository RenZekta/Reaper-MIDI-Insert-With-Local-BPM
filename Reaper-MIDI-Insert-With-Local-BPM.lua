-- PHYSICAL MIDI IMPORT — FINAL SINGLE-SCRIPT
-- SMF injection (TPQN 960) -> in-project flatten -> native Glue rebuilds
-- the source extent to the item bounds -> looping ON, boundary at block end.
-- No ghost notes, no notches, no second step.

reaper.Undo_BeginBlock()

local PPQ = 960

local track = reaper.GetSelectedTrack(0, 0)
local time_start, time_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)

if track and (time_start ~= time_end) then
  local item_len = time_end - time_start

  -- 1. Local tempo / time signature at selection start
  local marker_idx = reaper.FindTempoTimeSigMarker(0, time_start)
  local local_bpm, local_bpi, local_denom
  if marker_idx >= 0 then
    _, _, _, _, local_bpm, local_bpi, local_denom = reaper.GetTempoTimeSigMarker(0, marker_idx)
  else
    local_bpm = reaper.Master_GetTempo()
    local_bpi = 4
    local_denom = 4
  end

  -- 2. Tempo meta bytes (strict integer casting)
  local us_per_qn = math.floor((60000000 / local_bpm) + 0.5) // 1
  local t1 = string.char((us_per_qn >> 16) & 0xFF)
  local t2 = string.char((us_per_qn >> 8) & 0xFF)
  local t3 = string.char(us_per_qn & 0xFF)

  -- 3. Time signature meta bytes (denominator as power of two)
  local denom_int = math.floor(local_denom)
  local denom_pow = 2
  if denom_int == 1 then denom_pow = 0
  elseif denom_int == 2 then denom_pow = 1
  elseif denom_int == 4 then denom_pow = 2
  elseif denom_int == 8 then denom_pow = 3
  elseif denom_int == 16 then denom_pow = 4
  elseif denom_int == 32 then denom_pow = 5
  end
  local ts1 = string.char(math.floor(local_bpi) // 1 & 0xFF)
  local ts2 = string.char(denom_pow // 1 & 0xFF)

  -- 4. Block length in ticks + VLQ delta encoder
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

  -- 5. SMF Type 0 binary, division = 960 (mirrors native items)
  local header = "MThd\000\000\000\006\000\000\000\001" .. string.char((PPQ >> 8) & 0xFF, PPQ & 0xFF)
  local meta_ts    = "\000\255\088\004" .. ts1 .. ts2 .. "\024\008"
  local meta_tempo = "\000\255\081\003" .. t1 .. t2 .. t3
  local meta_end   = vlq(total_ticks) .. "\255\047\000"

  local track_data  = meta_ts .. meta_tempo .. meta_end
  local track_chunk = "MTrk" .. string.pack(">I4", #track_data) .. track_data

  local temp_path = reaper.GetResourcePath() .. "/temp_physical_import.mid"
  local file = io.open(temp_path, "wb")
  if file then
    file:write(header .. track_chunk)
    file:close()

    local original_cursor = reaper.GetCursorPosition()
    reaper.SetEditCurPos(time_start, false, false)
    reaper.Main_OnCommand(40289, 0) -- unselect all items

    reaper.InsertMedia(temp_path, 0)

    local imported_item = reaper.GetSelectedMediaItem(0, 0)
    if imported_item then
      reaper.SetMediaItemInfo_Value(imported_item, "C_BEATATTACHMODE", 0)
      reaper.SetMediaItemInfo_Value(imported_item, "B_LOOPSRC", 0)
      reaper.SetMediaItemInfo_Value(imported_item, "D_LENGTH", item_len)

      local sws = reaper.NamedCommandLookup("_BR_ME_TOGGLE_IGNORE_TEMPO_PO_START")
      if sws ~= 0 then reaper.Main_OnCommand(sws, 0) end

      -- Flatten external reference to in-project
      reaper.Main_OnCommand(40401, 0)

      -- Native glue: rebuilds the in-project source with extent == item
      -- bounds. The stub extent is discarded; notches cannot exist.
      reaper.Main_OnCommand(41588, 0) -- Item: Glue items, ignoring time selection

      -- Glue replaced the item object; re-fetch the glued result.
      local final_item = reaper.GetSelectedMediaItem(0, 0) or imported_item
      reaper.SetMediaItemInfo_Value(final_item, "C_BEATATTACHMODE", 0)
      reaper.SetMediaItemInfo_Value(final_item, "D_LENGTH", item_len)
      reaper.SetMediaItemInfo_Value(final_item, "B_LOOPSRC", 1) -- looping ON, boundary at end
    end

    reaper.SetEditCurPos(original_cursor, false, false)
    os.remove(temp_path)
  end
end

reaper.UpdateArrange()
reaper.Undo_EndBlock("Physical MIDI Import (Glue Final)", -1)