# Reaper MIDI Insert with Local BPM

A ReaScript for Cockos REAPER that resolves a native MIDI initialization issue when working within projects configured with a "Time" timebase.

## The Problem

When a REAPER project timebase is set to **Time**, drawing or inserting a new MIDI item natively via `Insert > New MIDI item` or mouse modifiers causes the item to ignore the local tempo and time signature markers at its physical timeline position. Instead, the item initializes using the project's global default statistics (typically found at Bar 1, Beat 1). 

While SWS extension actions can manually force an item to "Ignore project tempo," applying this to an unedited, blank project-native container is unstable. With default settings Attions make no effect, and if (Preferences -> MIDI) `Create new MIDI items as:` `.MID files` , is enabled, closing the MIDI piano roll editor without explicitly saving causes the item boundaries to shrink, notes to offset, or the layout engine to render a repetitive wall of frequent loop notches across the block. Unusable.

## The Solution

This script automates a stable workaround by bypassing blank internal MIDI item initialization:
1. **Binary Asset Generation:** Compiles a compliant SMF Type 0 binary block in the system cache with local BPM/time signature parameters, matching the active TPQN and PPQ user preference.
2. **External File Import:** Injects the cache file via `reaper.InsertMedia` to be evaluated as an isolated external asset.
3. **Database Reconstruction:** Forces a timebase override (`C_BEATATTACHMODE = 0`), converts the asset to an internal take, and glues it (`41588`) to match selection limits.
4. **Adaptive Integration & Renaming:** Formats the take using two-digit track lane indicators (e.g., `01`, `02`) and automated naming (`XX-TrackName-MIDI` or `XX-MIDI`), while preventing unnamed tracks from inheriting temporary file names.

The resulting MIDI block features a clean timeline grid matching local arrangement, zero loop-notches, and complete structural stability if closed without saving. No ghost notes are added.

## Installation

### Prerequisites
* **REAPER v6.0 or newer** (configured with Lua 5.3+ support)
* **SWS / S&M Extension** installed (required for the metadata isolation command)

### Setup Steps
1. Open REAPER.
2. Open the Action List by pressing `?` or navigating to `Actions > Show action list`.
3. In the bottom right corner, click **ReaScript: New...**.
4. Set the file name to `Reaper-MIDI-Insert-With-Local-BPM` (or any other) and click **Save**.
5. Copy the full source code from the `.lua` file in this repository and paste it into the built-in development environment editor.
6. Press `Ctrl + S` (Windows) or `Cmd + S` (macOS) to save, then close the script window.

## Usage

### Hotkey Mapping
Locate the registered script in your Action List, select it, and assign it to a custom keyboard shortcut or layout button.

### Mouse Modifier Mapping (Recommended)
Because REAPER strictly limits drag behaviors (`left drag` or `right drag`) to hardcoded internal marquee functions, custom actions and scripts cannot be mapped directly to a drag gesture. Instead, the script can be assigned to a modifier click that reads your active time selection for quick use.

To configure this workflow:
1. Navigate to `Options > Preferences > Editing Behavior > Mouse Modifiers`.
2. Set the **Context** dropdowns to `Track` and `left click`.
3. Double-click your desired modifier row (e.g., `Shift`).
4. Select `Action list...` from the very bottom of the pop-up menu.
5. Search for `Script: Reaper-MIDI-Insert-With-Local-BPM.lua`, select it, and click **Select/Close**.
6. Click **Apply** and close the preferences menu.

### Working Method
1. Draw your standard **Time Selection** bounding box across the timeline over the target grid region (e.g., using `Ctrl + Right-Drag` or your default arrangement tool).
2. Release the mouse drag, hold your mapped modifier (e.g., `Ctrl`), and **Left-Click** once anywhere inside the target track lane.
3. The script fires instantly, reading the boundaries of your selection and populating it with the stabilized local MIDI pattern block.


Now, dragging a time selection box with your chosen right-click modifier will instantly populate the timeline with a perfectly scaled, grid-accurate local MIDI pattern block.

## License

This project is licensed under the Mozilla Public License 2.0 (MPL-2.0). See the LICENSE file for details.
