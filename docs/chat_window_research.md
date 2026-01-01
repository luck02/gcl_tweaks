# Avorion Chat Window Scrolling & Alternative Display Methods

*Research Date: 2025-12-28*
*Updated: 2025-12-29 - Added AzimuthLib dependency and implementation plan*

## 1. Chat Window Scrolling: NOT Modifiable via API

After deep examination of the Avorion API documentation and game scripts, **the built-in chat window scrolling behavior cannot be modified through the scripting API**.

### `displayChatMessage(message, sender, type)`

A global client-side function that:
- Takes a message, sender name, and type (0=Normal, 1=Error, 2=Warning, 3=Info)
- Has **no return value and no configurable options** for scroll behavior
- The chat window is engine-level; its implementation is hardcoded in the C++ game engine

### `ChatMessageType` Enum

Provides message styling only, nothing related to scrolling:
- `ChatMessageType.Normal`
- `ChatMessageType.Error`
- `ChatMessageType.Warning`
- `ChatMessageType.Information`
- `ChatMessageType.Chatter`
- `ChatMessageType.ServerInfo`
- `ChatMessageType.Notification`

---

## 2. Solution: Custom Client-Side Output Window

### Approach: AzimuthLib + ListBox Window

We will create a **client-side scrollable output window** using:
- **AzimuthLib** - Library dependency for config management and potential UI extensions
- **ListBox** widget in a custom `Hud():createWindow()` for scrollable output

### Why AzimuthLib?

[AzimuthLib](https://steamcommunity.com/sharedfiles/filedetails/?id=1722652757) ([GitHub](https://github.com/rinart73/AzimuthLib)) provides:

| Module | Purpose |
|--------|---------|
| `azimuthlib-basic.lua` | Config loading/saving, structured logging, validation |
| `azimuthlib-customtabbedwindow.lua` | Workaround for bugged TabbedWindows in HUD (future expansion) |
| UI utilities | Color picker, splitters, rectangles for polish |

**Note**: AzimuthLib is archived (read-only since Aug 2023) but stable and widely used.

### Key API for ListBox Scrolling

`ListBox` has a **read/write `scrollPosition` property** and `clampScrollPosition()` function:

```lua
-- Create scrollable output window
local window = Hud():createWindow(Rect(100, 100, 500, 400))
local listBox = window:createListBox(Rect(vec2(10, 10), vec2(380, 280)))
listBox.entriesSelectable = false
listBox.rowHeight = 20

-- Add entries and auto-scroll to bottom
listBox:addEntry("Line 1")
listBox:addEntry("Line 2")
listBox.scrollPosition = listBox.rows
```

**Key ListBox Properties:**
- `scrollPosition` (int, read/write) - current scroll position
- `rows` (int, read-only) - total number of rows  
- `clampScrollPosition()` - ensures scroll position is valid

---

## 3. Implementation Plan

### Goal
Display command output (e.g., `/gcl_tweak showdroptables`) in a **scrollable client-side window** instead of the cramped chat window.

### Architecture

```
┌─────────────────────────────────────────────────────┐
│  GCL Output Console                            [X]  │
├─────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────┐│
│  │  ListBox (scrollable output)                    ││
│  │                                                 ││
│  │  === System Upgrade Drop Weights ===            ││
│  │  12.5% (50): arbitrarytcs.lua                   ││
│  │  10.0% (40): militarytcs.lua                    ││
│  │  8.3% (33): tradingsubsystem.lua                ││
│  │  ...                                            ││
│  │                                                 ││
│  └─────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────┘
```

### Components

1. **Client Script** (`data/scripts/player/gcl_console.lua`)
   - Creates the HUD window with ListBox
   - Registers callback to receive output from server
   - Auto-scrolls to bottom on new content

2. **Server Integration** (modify `gcl_tweak.lua` commands)
   - After executing command, send output to client via `invokeClientFunction`
   - Client script receives and displays in ListBox

3. **AzimuthLib Usage**
   - `loadConfig`/`saveConfig` for window position/size persistence
   - `logs()` for structured debug logging during development

### Files to Create/Modify

| File | Action |
|------|--------|
| `data/scripts/player/gcl_console.lua` | NEW - Client-side output window |
| `data/scripts/commands/gcl_tweak.lua` | MODIFY - Send output to client window |
| `modinfo.lua` | MODIFY - Add AzimuthLib as dependency |

---

## 4. Other Display Methods (Reference)

### Hud Notifications (Non-scrolling, temporary)

```lua
Hud():displayNotification(text, textColor, iconPath, iconColor, isAlliance, height, iconPadding)
```
- Appears on the right side of screen
- Good for quick alerts, not for large data

### Speech Bubbles

```lua
displaySpeechBubble(entity, text)
```
- Appears next to an entity in 3D space
- Text is truncated if too long

### Hints

```lua
Hud():displayHint(text, highlightObjects...)
```
- For tutorial/guidance style messages with optional object highlighting

---

## 5. API Documentation References

Key documentation files in `Avorion/Documentation/`:
- `Functions.html` - Global functions including `displayChatMessage`
- `Hud.html` - HUD creation and notifications
- `ListBox.html` - ListBox with `scrollPosition`
- `ListBoxEx.html` - Extended ListBox (also has `scrollPosition`)
- `ScrollFrame.html` - Only has `scrollSpeed` (write-only), no position control
- `Window.html` - Window creation
- `Enums.html` - `ChatMessageType` enum values
- `Player [Client].html` - `sendChatMessage(content, channel)` for executing commands
