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

## 2026-09-23 (feat/note-marker)

- Pages that have a page note show a light-gray triangle (48 px) in the
  top-right corner. It is painted with the on-page strokes, so it needs no
  extra refresh; the lookup is cached per page and dropped on navigation and
  whenever a note canvas closes.

## 2026-09-23 (feat/highlight-header)

- A highlight note shows the highlighted text under the title bar on its
  first page, wrapped and cut with an ellipsis past a third of the screen.
  The pen draws below it; a contact that starts on the header goes to
  gesture detection like one on the title bar. The title bar of a
  highlight note now reads "Highlight note" instead of repeating a snippet
  of the text.
- "Pen note" is also a button next to "Note" in the dialog that a long-press
  on a highlight opens. It is injected while ReaderHighlight builds that
  dialog (ButtonDialog.new is intercepted for the duration of the call),
  because the ZenOS build on the Kobo replaces the "…" menu with its own
  icon row and hides other plugins' buttons unless its "Show other items"
  setting is on.
- A highlight that has a pen note gets a small pencil glyph (the one
  KOReader uses for its own note side mark) in the margin beside its first
  line, right next to KOReader's side line or side mark when the highlight
  also has a text note, and where that mark would be otherwise. Boxes come
  from the list ReaderView recorded for the frame; the set of noted
  highlights is cached with the page marker and dropped with it.

## 2026-09-23 (feat/finger-mode-indicator)

- While finger mode is on, the reader shows a light-gray triangle in the
  bottom-right corner, the mirror image of the page-note marker in the
  top-right corner. Switching modes refreshes just that corner, so the
  triangle appears and disappears together with the "Finger mode" toast.
  An open note canvas paints the same triangle, and a mode switch from its
  menu or by side button hold + tap refreshes its corner the same way.

## 2026-09-23 (feat/note-browser)

- Note browser: "Browse pen notes" in the Pencil menu, "Browse all pen notes"
  at the bottom of the pen note chooser, and a "Pencil: browse pen notes"
  gesture action open a full-screen list of every pen note of the book. The
  book note comes first, then the notes in reading order with the page number
  on the right; highlight notes show the highlighted text, multi-page notes
  their page count. Tapping a row opens the note, and closing the canvas
  brings the list back at the same place; long-pressing offers "Go to
  location", which pushes the current position so the back gesture returns,
  and "Delete note".
- `Notes.browseOrder` (pure, in `lib/notes.lua`) does the ordering and is
  covered by `spec/notes_spec.lua`.

## 2026-09-23 (feat/note-export)

- Exporting pen notes: "Export pen notes" in the Pencil menu writes every
  note of the book, in browser order, as one PDF or as one PNG per note
  page; a single note is exported from the browser's long-press dialog or
  from "Export note…" in the canvas menu (blank pages are pruned first).
  Each page is painted by a NoteCanvas in export mode (`for_export`: title
  bar without icons, no mode marker, colors as drawn even in night mode)
  into a screen-size RGB24 blitbuffer. PNGs go through `ffi/png`; the PDF
  is written by `lib/export.lua`'s pure `PdfWriter`, one FlateDecode
  (zlib via `ffi/zlib`, raw if unavailable) DeviceRGB image per page at
  the screen's DPI, streamed to the file page by page. Files land in
  `<notes root>/<book name>/`, the root being "notes" at the top of the device's
  storage (`Device.home_dir`, `/mnt/onboard` on Kobo) or the folder chosen
  under "Notes folder"
  (`pencil_note_export_dir`); they are named after the note ("All notes"
  for the whole book) with a ` - p01` suffix per page for images; repeated
  labels get ` (2)`, ` (3)`.
- `spec/export_spec.lua` covers the names and the PDF structure (offsets
  in the xref table, page tree, filters); the writer's output was also
  checked with pdfinfo and mutool.

## 2026-09-23 (feat/export-api)

- The notes root setting is now `notes_export_dir`, shared with
  [notesexport.koplugin](https://github.com/valterschutz/notesexport.koplugin)
  so either plugin's "Notes folder" row configures both. A folder chosen
  under the old `pencil_note_export_dir` key has to be chosen again.
- For that plugin's "export everything" action: `Pencil:writeAllNoteImages(dir)`
  writes every pen note as PNGs into a folder and returns the count, and
  `Pencil:highlightNoteImageNames()` gives the file names each highlight's
  pen note exports to, by annotation datetime, so the Markdown can link
  them. `noteExportPlan` (ordered notes + unique labels) backs both and the
  menu exports.

## Planned

- Nothing queued.
