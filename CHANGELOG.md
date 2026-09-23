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
  (highlighting a fresh selection first). Holding the side button and
  double-tapping the page also opens the chooser; a single hold + tap now
  waits 250 ms for a second tap before it toggles.
- Storage in the sidecar as `pencil_notes.lua` (`lib/notes.lua`, pure and
  tested). Anchors: page by page number, re-derived from an xpointer in
  rolling documents; chapter by the TOC entry's xpointer or page; highlight
  by the annotation's datetime; book as a singleton. Empty notes are dropped
  on close and on load; a store that failed to load is never overwritten.
- `spec/notes_spec.lua` and `spec/notecanvas_spec.lua` (KOReader widgets
  stubbed) cover the store and the canvas input handling.

## 2026-09-23 (feat/note-pages)

- Multi-page pen notes: a note is now a list of pages, each with its own
  strokes (store version 2; version 1 notes load as one page). On the canvas
  a swipe west (or the forward page button) turns to the next page and adds
  a blank one past the last, a swipe east (or the back page button) goes
  back, as in the reader. The title bar shows "Page x of y" next to the note name. Undo
  and clear act on the current page; "Delete page" in the menu removes the
  current page, asking first if it has strokes. Blank pages are dropped when
  the canvas closes and are never written to disk.
- Finger mode on the canvas: holding the side button and tapping the canvas
  toggles finger/pen mode (independent of the "Side button tap" setting, since
  the canvas has no pencil/eraser tool to toggle), and the canvas menu has a
  "Switch to finger/pen mode" entry. In finger mode the bare tip is handed to
  gesture detection, so it swipes between pages and taps the title bar; the
  side button and the eraser end keep working.

## Planned

- Browsing all pen notes of a book (list, open, go to location).
- Exporting pen notes as images or a PDF.
- A marker on pages that have a pen note.
