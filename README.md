# Senjitsu Macro Manager (SMM) - Specification & Technical Reference

## Overview
**Senjitsu Macro Manager** is a standalone World of Warcraft addon that provides a custom CRUD (Create, Read, Update, Delete) interface for managing player macros. It bridges the gap between the default WoW macro interface and advanced user needs by offering a cleaner, more responsive UI.

## Core Philosophy
- **Pure Lua**: No XML files are used for frame definition. All UI elements are created programmatically.
- **Taint-Free**: Does **not** use `SecureActionButtonTemplate`. It uses standard API calls (`EditMacro`, `CreateMacro`) to manage macros safely out of combat.
- **Event-Driven**: Relies on WoW's `UPDATE_MACROS` event to sync the UI with the game state.

## Architecture

### Main Components
1.  **Main Frame (`SMM`)**:
    -   The root window of the addon.
    -   Movable, high-strata frame utilizing `BackdropTemplate`.
    -   Dimensions are dynamically calculated based on screen size (max 80% screen width/height).
    -   Command to toggle: `/smm`.

2.  **List View (`SMM:CreateListView`)**:
    -   A scrollable list on the left side.
    -   **Search/Filter**: A text input at the top filters the list in real-time.
    -   **Grouping**:
        -   Macros are divided into **General** and **Character** collapsible sections.
        -   Headers show counts (e.g., `General Macros (5/120)`).
        -   State is persisted in `SMM.Groups` (Auto-expands on search).
    -   **List Items**: 
        -   Displays macro icon (18x18) and name (White text).
        -   Visual separation (3px gap) between items.
        -   Recyclable button pool (`SMM.FramePool`) and header pool (`SMM.HeaderPool`).

3.  **Detail View (`SMM:CreateDetailView`)**:
    -   The editing pane on the right side.
    -   **Mode Selection**: Radio buttons to toggle between "General" (Global) and "Character" scope.
    -   **Name Input**: Text field for the macro name.
        -   **Limit**: 16 characters max.
        -   **Feedback**: Real-time counter `(x/16) characters used`.
    -   **Icon Selection**: 
        -   36x36 icon preview texture.
        -   **Select Icon**: Opens the Icon Browser (Size: 120x25).
        -   **Reset Icon**: Resets icon to default question mark (Size: 120x25). Disabled if already default.
    -   **Body Input**: Large multi-line box for the macro script.
        -   **Limit**: 255 characters max.
        -   **Feedback**: Real-time counter `(x/255) characters used`.
    -   **Actions**:
        -   **New**: Clears inputs to start a fresh macro. (Yellow text)
        -   **Save**: Creates a new macro or updates the selected one. (Yellow text)
        -   **Cancel**: (Yellow text)
            -   *Edit Mode*: Resets form to last saved state.
            -   *Create Mode*: Clears form. Disabled if form is empty.
        -   **Delete**: Removes the currently selected macro. (White text)

4.  **Icon Browser (`SMM:CreateIconBrowser`)**:
    -   A secondary frame anchored to the **Top-Right** of the Main Frame.
    -   **Sticky Positioning**: It is physically attached to the main window and moves with it; it cannot be moved independently.
    -   **Features**:
        -   **Grid View**: Scrollable grid of available icons (Spells/Items).
        -   **Category Filter**: Dropdown to switch between "All", "Spells", and "Items".
        -   **Selection**: Clicking an icon updates the current macro's icon.

### Data Flow
1.  **Initialization**: `SMM:RunAddonLifeCycle()` bootstraps the UI layout and registers events.
2.  **Loading**: On `UPDATE_MACROS`, `SMM:RefreshList()` fetches all macros via `GetNumMacros()` and `GetMacroInfo()`.
3.  **Interaction**: 
    -   Clicking a list item populates the Detail View.
    -   Dragging a list item picks up the macro for placement on Action Bars.
    -   Clicking "Save" calls `EditMacro` (if updating) or `CreateMacro` (if new).
    -   **Type Swap**: If a macro's type is changed (General ↔ Character) on save, `SwapMacro` creates the macro under the new type and deletes the old one. This is a create-then-delete operation.
    -   Search box input triggers a list refresh with a string matching filter.
4.  **Safety**:
    -   Both `NewMacro` and `SwapMacro` validate macro counts against `MAX_ACCOUNT_MACROS` (120) and `MAX_CHARACTER_MACROS` before creating. If the limit is reached, the operation is aborted with an error message in chat.

## Technical Implementation

### Dynamic Layout System
The addon uses a responsive layout calculated in `SMM:InitializeLayout()` to adapt to different screen resolutions.

| Variable | Calculation / Value | Description |
| :--- | :--- | :--- |
| `SMM.FinalWidth` | `min(800, ScreenWidth * 0.8)` | Max 800px or 80% of screen |
| `SMM.FinalHeight` | `min(600, ScreenHeight * 0.8)` | Max 600px or 80% of screen |
| `SMM.ListWidth` | `FinalWidth * 0.35` | List takes up ~35% of width |
| `SMM.DetailWidth` | `FinalWidth * 0.55` | Details take up ~55% of width |

The remaining ~10% width is used for padding and scrollbars.

**Frame Anchoring Strategy:**
-   **Top-Left Origin**: Most elements are anchored relative to `TOPLEFT`.
-   **Relative Stacking**: 
    -   Headers and list items are stacked vertically using `yOffset`.
    -   Detail view elements (Name, Body) are anchored to the element immediately above them (`TOPLEFT` of `NameEditHitBox` to `BOTTOMLEFT` of `NameLabel`).

### Global Variables & State
The `SMM` table acts as the namespace and state container.

| Key | Type | Description |
| :--- | :--- | :--- |
| `SMM.SelectedMacroIndex` | `number \| nil` | The WoW API index of the active macro. |
| `SMM.SelectedMacroIsLocal` | `boolean` | `true` if character-specific, `false` if global. |
| `SMM.MacroList` | `table` | Array of currently displayed macro list buttons. |
| `SMM.ActiveHeaders` | `table` | Array of currently displayed group headers. |
| `SMM.Groups` | `table` | Expansion state: `{ Global = bool, Char = bool }`. |
| `SMM.FramePool` | `table` | Object pool for list buttons (recycling). |
| `SMM.HeaderPool` | `table` | Object pool for header buttons (recycling). |
| `SMM.WorkIcon` | `number` | Currently selected icon ID (default: `134400` = QuestionMark). |
| `SMM.CurrentCategory` | `string` | Active Icon Browser filter: `"ALL"`, `"SPELLS"`, or `"ITEMS"`. |
| `SMM.CurrentIconList` | `table` | Array of icon IDs for the current browser filter. |
| `SMM.IconButtons` | `table` | Pool of icon grid buttons in the Icon Browser. |
| `SMM.IconBrowserTargetIconX` | `number` | Icon grid columns (default: `12`). |
| `SMM.IconBrowserTargetIconY` | `number` | Icon grid rows (default: `10`). |

### Form Mode Management
**`SMM:SetFormMode(mode)`**  
Controls the Detail View state for creating or editing macros.

| Mode | Description |
| :--- | :--- |
| `"create"` | Clears the form for creating a new macro. Disables Delete button. Cancel enabled if form has content. |
| `"edit"` | Enables all buttons for editing an existing selected macro. |


### UI Component Hierarchy
```text
SMM (Main Frame)
├── Title (FontString)
├── CloseButton (Button)
├── SearchLabel & SearchBox
├── ListScroll (ScrollFrame)
│   └── ListContent (Frame)
│       ├── [Group Header]
│       └── [Macro Button]
└── DetailFrame (Frame)
    ├── TypeGlobal / TypeChar (CheckButton)
    ├── NameLabel & NameEdit
    ├── NameCountLabel (FontString)
    ├── IconLabel, IconPreview (Texture)
    ├── SelectIconButton (Button)
    ├── ResetIconButton (Button)
    ├── BodyBackdrop (Frame)
    │   └── BodyScroll (ScrollFrame)
    │       └── BodyEdit (EditBox)
    └── BodyCountLabel (FontString)
    └── Buttons (New, Save, Cancel, Delete)
└── IconBrowser (Frame) [Hidden by default]
    ├── CategoryDropdown (UIDropDownMenu)
    └── GridScroll (ScrollFrame)
        └── [Icon Buttons]
```

## Visual Standards
- **Buttons**:
  - `Select Icon` and `Reset Icon`: Size 120x25.
  - Text Colors:
    - **Save, New, Cancel**: Yellow (`1, 1, 0`)
    - **Delete**: White (`1, 1, 1`)
    - **Disabled**: Grey (`0.5, 0.5, 0.5`)

## Future Context for AI
When extending this addon, remember:
-   **No specialized libraries**: It relies on standard WoW API widgets.
-   **Security**: Do not attempt to use restricted frames that require hardware events unless necessary. The current implementation is safe for logic operations.
