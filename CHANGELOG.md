# Changelog

Fork of [mysticknits/pencil.koplugin](https://github.com/mysticknits/pencil.koplugin).
`main` tracks upstream; `dev` is the integration branch deployed to the Kobo.

## 2026-09-23

- Forked upstream at 0.5.0. Rebased the edits previously living only on the
  device (sticky highlight state across side-button release, pcall-guarded key
  parsing) onto it.
- Added `deploy.py` to copy the plugin and patched `input.lua` to a mounted Kobo.

## 2026-09-23 (feat/finger-mode)

- Finger mode: the bare pen tip is passed through to KOReader as a finger.
  The eraser end still erases and holding the side button still highlights.
  Menu checkbox under Pencil, and a "Pencil: toggle finger/pen mode" gesture
  action. The mode persists across books.
- "Side button tap" setting: holding the side button and tapping the page
  toggles pencil/eraser (upstream default) or finger/pen mode. The tap is a
  contact under 500 ms that moves under 10 px; anything else is a highlight
  drag. The tap cancels the highlight it would otherwise have created.
- Found while testing: the Kobo Libra Colour reports the stylus only while
  the tip touches the screen, so a bare side-button press never reaches
  KOReader. The release-based quick-press toggle is kept for hardware that
  does report it, and now requires the press to last under 500 ms.
- `spec/side_button_spec.lua` covers the tap/hold decision and mode switching.

## 2026-09-23 (feat/note-canvas)

- Pen notes: a full-screen blank canvas (`lib/notecanvas.lua`) for handwritten
  notes attached to the current page, the current chapter, the whole book or a
  highlight. The stylus callback is routed to the canvas while it is the
  topmost widget, so pen, side-button highlighter and eraser end behave as on
  a page; the title bar has an X to close and a menu with undo, clear and
  delete.
- Entry points: "Pen note…" in the Pencil menu and the "Pencil: pen note…"
  gesture action open a chooser (page / chapter / book) that says whether a
  note exists; "Pen note" in the highlight menu opens the note of a highlight
  (highlighting a fresh selection first).
- Storage in the sidecar as `pencil_notes.lua` (`lib/notes.lua`, pure and
  tested). Anchors: page by page number, re-derived from an xpointer in
  rolling documents; chapter by the TOC entry's xpointer or page; highlight
  by the annotation's datetime; book as a singleton. Empty notes are dropped
  on close and on load; a store that failed to load is never overwritten.
- `spec/notes_spec.lua` and `spec/notecanvas_spec.lua` (KOReader widgets
  stubbed) cover the store and the canvas input handling.

## Planned

- Browsing all pen notes of a book (list, open, go to location).
- Exporting pen notes as images or a PDF.
- A marker on pages that have a pen note.
