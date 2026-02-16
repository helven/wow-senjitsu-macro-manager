# Senjitsu Macro Manager — Manual Test Cases

> **Version**: 1.0  
> **Last Updated**: 2026-02-17  
> **Tester**: _______________  
> **Build/Commit**: _______________  

---

## How to Use This Document

- **Precondition**: State the game/addon must be in before the test.
- **Steps**: Numbered actions the tester performs.
- **Expected Outcome**: Observable, verifiable result.
- **Status**: ✅ Pass | ❌ Fail | ⏭️ Skipped
- **Notes**: Freeform — record actual behavior on failure.

---

## 1. Addon Lifecycle & Initialization

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 1.1 | Load message | Addon installed, `/reload` | 1. `/reload` the UI | Chat prints green message: `SenjitsuMacroManager loaded. Type /smm to toggle.` | | |
| 1.2 | Hidden on load | Addon installed | 1. Log in or `/reload` | Main frame is **not** visible on screen. | | |
| 1.3 | Toggle open | Frame hidden | 1. Type `/smm` in chat and press Enter | Main frame appears centered on screen. Macro list is populated. | | |
| 1.4 | Toggle close | Frame visible | 1. Type `/smm` in chat and press Enter | Main frame hides. | | |
| 1.5 | Close button | Frame visible | 1. Click the ✕ button (top-right of main frame) | Main frame hides. | | |

---

## 2. Main Frame — Layout & Interaction

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 2.1 | Frame size | Frame visible | 1. Observe frame dimensions | Frame is max 800×600 or 80% of screen (whichever is smaller). No overflow past screen edges. | | |
| 2.2 | Draggable | Frame visible | 1. Left-click and hold the title bar area 2. Drag to another position 3. Release | Frame moves with cursor. Stays at new position after release. | | |
| 2.3 | Title text | Frame visible | 1. Look at the top-center of the frame | Displays "Senjitsu Macro Manager". | | |
| 2.4 | Left/Right split | Frame visible | 1. Observe layout | List view on the left (~35% width). Detail view on the right (~55% width). No overlap. | | |

---

## 3. List View — Display & Grouping

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 3.1 | Headers shown | ≥1 global and ≥1 char macro exist | 1. Open SMM (`/smm`) | Two collapsible headers visible: `General Macros (X/120)` and `Character Macros (Y/18)`. Counts match game state. | | |
| 3.2 | Collapse group | Both groups expanded | 1. Click the "General Macros" header | General group collapses. Expand icon changes to ➕. Character macros shift up. | | |
| 3.3 | Expand group | General group collapsed | 1. Click the "General Macros" header | General group expands. Expand icon changes to ➖. Macros are listed below. | | |
| 3.4 | Macro item display | ≥1 macro exists | 1. Observe a macro item in the list | Shows 18×18 icon on the left and white macro name to its right. | | |
| 3.5 | List scrolling | More macros than list height allows | 1. Hover over the list 2. Scroll mouse wheel down 3. Scroll mouse wheel up | List scrolls smoothly. Scrollbar track reflects position. Cannot scroll past top or bottom bounds. | | |
| 3.6 | Empty state — no macros | Delete all macros | 1. Open SMM | Both headers display `(0/120)` and `(0/18)`. No macro items. No Lua errors. | | |

---

## 4. Search / Filter

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 4.1 | Filter by name | ≥3 macros with distinct names | 1. Click the Search box 2. Type a substring that matches exactly 1 macro | Only the matching macro is shown. Non-matching macros are hidden. Headers still visible for context. | | |
| 4.2 | Case-insensitive | Macro named "MyBurst" exists | 1. Type `myburst` in the search box | "MyBurst" appears in the list. | | |
| 4.3 | Auto-expand on filter | One or both groups collapsed | 1. Type a search term that matches macros in collapsed groups | Collapsed groups auto-expand to reveal matching results. | | |
| 4.4 | Clear filter | Filter active | 1. Select all text in search box 2. Delete it | Full macro list is restored. Groups return to their prior expand/collapse state. | | |
| 4.5 | No results | No macro matches search | 1. Type `xyznonexistent123` | No macro items displayed. Headers still visible with counts. No Lua errors. | | |
| 4.6 | Escape clears focus | Search box focused | 1. Press `Escape` | Search box loses focus. Text remains. Frame does **not** close. | | |

---

## 5. Detail View — Selection & Population

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 5.1 | Select macro | ≥1 macro exists | 1. Click a macro in the list | Detail view populates: Name, Body, Icon, and correct Type radio (General/Character) are filled in. Delete button enables. | | |
| 5.2 | Radio button state — Global | Select a General macro | 1. Click a General macro | "General" radio checked. "Character" radio unchecked. | | |
| 5.3 | Radio button state — Character | Select a Character macro | 1. Click a Character macro | "Character" radio checked. "General" radio unchecked. | | |
| 5.4 | Radio mutual exclusion | Detail view populated | 1. Click "Character" radio 2. Click "General" radio | Only one radio is checked at a time. They are mutually exclusive. | | |
| 5.5 | Clickable radio labels | Detail view populated | 1. Click the "General" text label 2. Click the "Character" text label | Clicking the label text also toggles the corresponding radio button. | | |
| 5.6 | Icon preview | Select a macro with a known icon | 1. Click the macro | 36×36 icon preview displays the correct macro icon. | | |
| 5.7 | Disabled state on load | Open SMM fresh | 1. Open SMM without selecting a macro | Name and Body fields are empty. Delete button is disabled. Type defaults to General. Icon is QuestionMark (134400). | | |

---

## 6. Create Macro (New)

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 6.1 | Create Global macro | Under global limit | 1. Click "New" button 2. Enter name: `TestGlobal` 3. Enter body: `/say Hello` 4. Leave "General" selected 5. Click "Save" | Macro created. Appears in General list. Name/Body/Icon fields reset. QuestionMark icon shown. | | |
| 6.2 | Create Character macro | Under char limit | 1. Click "New" 2. Enter name: `TestChar` 3. Enter body: `/dance` 4. Select "Character" radio 5. Click "Save" | Macro created. Appears in Character list. Fields reset. | | |
| 6.3 | Create with custom icon | Icon Browser functional | 1. Click "New" 2. Enter name and body 3. Click "Select Icon" 4. Choose an icon from the browser 5. Click "Save" | Macro is created with the selected icon (not QuestionMark). | | |
| 6.4 | Empty name guard | Detail view in create mode | 1. Leave Name field empty 2. Enter body text 3. Click "Save" | Nothing happens. No macro created. No Lua error. | | |
| 6.5 | Global limit reached | 120 global macros exist | 1. Click "New" 2. Enter name/body, leave "General" 3. Click "Save" | Chat prints red error: `SMM Error: Global Macro Limit Reached (120/120). Cannot create.` No macro created. | | |
| 6.6 | Character limit reached | Max character macros exist | 1. Click "New" 2. Enter name/body, select "Character" 3. Click "Save" | Chat prints red error: `SMM Error: Character Macro Limit Reached (X/X). Cannot create.` No macro created. | | |

---

## 7. Update Macro (Edit)

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 7.1 | Edit name | Existing macro selected | 1. Change the Name field to `RenamedMacro` 2. Click "Save" | Macro name updates in the list. Detail view reflects the new name. | | |
| 7.2 | Edit body | Existing macro selected | 1. Change the Body field to `/yell Updated!` 2. Click "Save" | Macro body updates. Verify by re-selecting the macro — body shows `/yell Updated!`. | | |
| 7.3 | Edit icon | Existing macro selected | 1. Click "Select Icon" 2. Pick a different icon 3. Click "Save" | Macro icon changes in the list and in the icon preview. | | |
| 7.4 | No-op save | Existing macro selected, no changes | 1. Click "Save" without changing anything | Macro remains unchanged. No Lua error. | | |

---

## 8. Swap Macro Type (General ↔ Character)

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 8.1 | Global → Character | General macro selected, char limit not reached | 1. Select a General macro 2. Change radio to "Character" 3. Click "Save" | Macro disappears from General list. Appears in Character list with same name, body, icon. Detail view resets. | | |
| 8.2 | Character → Global | Character macro selected, global limit not reached | 1. Select a Character macro 2. Change radio to "General" 3. Click "Save" | Macro disappears from Character list. Appears in General list. Detail view resets. | | |
| 8.3 | Swap blocked — target limit full | 120 global macros, have a char macro | 1. Select Character macro 2. Switch radio to "General" 3. Click "Save" | Error printed in chat: `Global Macro Limit Reached`. Original macro is **not** deleted. | | |
| 8.4 | Swap blocked — char limit full | Max char macros, have a global macro | 1. Select General macro 2. Switch radio to "Character" 3. Click "Save" | Error printed in chat: `Character Macro Limit Reached`. Original macro is **not** deleted. | | |

---

## 9. Delete Macro

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 9.1 | Delete selected macro | Macro selected in detail view | 1. Click "Delete" button | Macro removed from list. Detail view resets to disabled/empty state. Delete button disables. | | |
| 9.2 | Delete disabled when nothing selected | No macro selected | 1. Observe the "Delete" button | Button is visually disabled. Clicking does nothing. | | |

---

## 10. New Button (Reset)

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 10.1 | Reset after selection | Macro selected | 1. Click "New" button | Name clears. Body clears. Icon resets to QuestionMark. Type resets to General. Delete button disables. `SelectedMacroIndex` = nil. | | |
| 10.2 | New then Save | After clicking "New" | 1. Click "New" 2. Enter name/body 3. Click "Save" | A **new** macro is created (not an edit of the previously selected one). | | |

---

## 11. Icon Browser

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 11.1 | Open browser | Detail view visible | 1. Click "Select Icon" button | Icon Browser frame appears anchored to the top-right of the main frame. | | |
| 11.2 | Sticky positioning | Icon Browser open | 1. Drag the main frame to a new position | Icon Browser moves with the main frame. Cannot be moved independently. | | |
| 11.3 | Grid display | Icon Browser open, "All Icons" selected | 1. Observe the grid | 12×10 grid of 36×36 icons displayed. | | |
| 11.4 | Scroll grid | More icons than 1 page | 1. Scroll mouse wheel in the icon grid | Grid scrolls. New icons appear. Scrollbar updates. | | |
| 11.5 | Select icon | Icon Browser open | 1. Click any icon in the grid | Icon Browser closes. Detail view's icon preview updates to the selected icon. `SMM.WorkIcon` updates. | | |
| 11.6 | Category — All | Icon Browser open | 1. Select "All Icons" from dropdown | Grid shows all available icons (spells + items). | | |
| 11.7 | Category — Spells | Icon Browser open | 1. Select "Spells" from dropdown | Grid filters to spell icons only. | | |
| 11.8 | Category — Items | Icon Browser open | 1. Select "Items" from dropdown | Grid filters to item icons only. | | |
| 11.9 | Close browser | Icon Browser open | 1. Click the ✕ button on the Icon Browser | Icon Browser hides. Main frame remains. | | |
| 11.10 | Reopen browser | Previously opened and closed | 1. Click "Select Icon" again | Same browser instance reopens (not recreated). Defaults to "All Icons". | | |

---

## 12. Drag & Drop

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 12.1 | Drag macro to action bar | ≥1 macro in list, action bar visible | 1. Left-click and drag a macro item from the list 2. Drop onto an action bar slot | Macro icon appears on the action bar slot. Usable as normal macro. | | |

---

## 13. Edge Cases & Error Handling

| ID | Criteria | Precondition | Test Steps | Expected Outcome | Status | Notes |
|---|---|---|---|---|---|---|
| 13.1 | Rapid open/close | Frame in any state | 1. Type `/smm` rapidly 5+ times | Frame toggles correctly each time. No Lua errors. No frame duplication. | | |
| 13.2 | Search while empty | 0 macros exist | 1. Type text in the search box | No Lua errors. Empty list with headers showing `(0/X)`. | | |
| 13.3 | Select macro → delete externally | Macro selected in SMM | 1. Open default WoW macro UI 2. Delete the same macro 3. Return to SMM | SMM list refreshes via `UPDATE_MACROS` event. Detail view does **not** reference stale index. | | |
| 13.4 | Very long macro name | None | 1. Create a macro with a 16-character name (WoW max) 2. Select it | Name displays without truncation in the list and detail view. | | |
| 13.5 | Max body length | None | 1. Create a macro body at 255 chars (WoW max) 2. Save and re-select | Body is preserved in full. ScrollFrame handles the content. | | |
| 13.6 | Special characters in name | None | 1. Create macro named with symbols, e.g., `[Test]` 2. Search for `[Test]` | Macro appears. Search uses plain-text matching (`string.find` with `plain=true`), so brackets are literal. | | |
| 13.7 | Icon Browser with no icons | Unlikely, but: empty icon list | 1. Somehow trigger empty icon list | All grid buttons hide. No Lua errors. No crash. | | |

---

## 14. Regression Checklist

Quick sanity pass after any code change:

| # | Check | Status |
|---|---|---|
| R1 | `/smm` opens and closes without error | |
| R2 | Macro list populates with correct counts | |
| R3 | Selecting a macro populates detail view | |
| R4 | Create → Save → appears in list | |
| R5 | Edit → Save → updates in list | |
| R6 | Delete removes macro and resets view | |
| R7 | Search filters correctly | |
| R8 | Icon Browser opens, selects, closes | |
| R9 | Swap type works both directions | |
| R10 | No Lua errors in `/console scriptErrors 1` mode | |

---

## Appendix: Suggested Improvements to This Test Plan

These are areas currently **not covered** that should be added as the addon evolves:

| Gap | Why It Matters |
|---|---|
| **Undo / Confirmation dialogs** | No delete confirmation exists — accidental deletes are permanent. Add a test when implemented. |
| **Combat lockdown** | WoW restricts macro API during combat. Test that Save/Delete/New gracefully fail or disable during combat. |
| **Multi-character testing** | Character macros are per-character. Verify switching characters shows correct char macros. |
| **Resolution / scaling** | Test at 1080p, 1440p, 4K, and UI Scale 0.64–1.0 to verify dynamic layout. |
| **Accessibility** | Keyboard-only navigation (Tab between fields, Enter to save) is not implemented. |
| **Performance** | With 120 global + 18 character macros, measure refresh time and frame pool recycling efficiency. |
