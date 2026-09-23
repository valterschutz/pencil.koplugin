# pencil.koplugin

## Information

This has been tested on:

- Kobo Libra Colour/Kobo Stylus 2/Epub format

**This will currently only work on Kobo devices! I will attempt to add other device support by request and at a later date**

If you resize your book while reading it, your annotations will be WONKY. This is something I will eventually address but for now, get your book set before you start writing.

### Compatible with Koreader - Snowflake

## Features

- **Pen tip**: Draw annotations on your ebooks
- **Eraser end**: Flip your stylus over to erase strokes instantly
- **Highlighter**: Hold the stylus side button and drag to highlight; hold the side button and tap the page to toggle pencil/eraser; hold it and double-tap to open the pen note menu
- **Finger mode**: Treat the pen tip as a finger so taps, swipes and long-presses go to KOReader instead of drawing. The eraser end still erases and holding the side button still highlights. Set **Side button tap** to *finger/pen mode* to switch modes by holding the side button and tapping the page. A light-gray triangle in the bottom-right corner of the page, and of an open pen note, shows that finger mode is on
- **Pen notes**: Open a blank canvas for handwritten notes attached to the current page, the current chapter, the whole book, or a highlight. A note can span several pages: swipe to turn them, swipe past the last one to add a page. Pen, side-button highlighter and eraser end work on the canvas as on a page. Close it with the X in the corner
- **Swap Eraser/Highlighter**: Reassign which side button acts as eraser vs. highlighter from the menu
- **Undo**: Undo your last stroke or eraser action
- **Clear strokes**: Clear annotations for the current page or the entire document
- **Annotation grouping**: Strokes are automatically grouped into logical annotations based on timing and proximity
- **Enable/disable toggle**: Turn the plugin on or off via the menu or a mapped gesture
- **Per-document storage**: Annotations are saved with each book
- **Input debug mode**: Log raw stylus events to help diagnose detection issues

## Instructions for Installation

1. Download both the `pencil.koplugin` directory and the `input.lua` file from this repository.
2. Replace the `/frontend/device/input.lua` with the downloaded file. This enables the plugin to intercept the stylus input, separate it from touch inputs, and detect the eraser end.
3. Copy the `pencil.koplugin` directory into the `/plugins` directory of KOReader.

## Configuring the Pencil Plugin

1. Enable the plugin from the Pencil menu (Top menu > More tools > Pencil > Enabled)
2. If your stylus's side button mapping is reversed, toggle **Swap Eraser and Highlighter** in the Pencil menu
3. Choose what holding the side button and tapping the page does under **Side button tap**: toggle pencil/eraser (default) or toggle finger/pen mode. The stylus is only reported while it touches the screen, so a press of the button on its own cannot be detected
4. Optionally map actions to gestures in Gesture Manager:
   - **Pencil: toggle on/off** — enable or disable the plugin
   - **Pencil: toggle pencil/eraser** — switch between tools
   - **Pencil: toggle finger/pen mode** — pass the pen tip through as a finger, or draw with it
   - **Pencil: select pencil** — switch to pencil
   - **Pencil: select eraser** — switch to eraser
   - **Pencil: undo** — undo last stroke or eraser action
   - **Pencil: pen note…** — choose a page, chapter or book note and open its canvas
   - **Pencil: browse pen notes** — list every pen note of the book
   - **Pencil: scratchpad** — open the scratchpad, the pen note shared by every book

## Pen notes

Pen notes are blank canvases stored next to the book in `pencil_notes.lua`, separate from the on-page strokes.

- **Page, chapter or book note**: open the chooser from the Pencil menu (**Pen note…**), the **Pencil: pen note…** gesture action, or by holding the side button and double-tapping the page with the pen. It tells you whether a note already exists for the current page, the current chapter (the nearest table-of-contents entry) and the book
- **Scratchpad**: the last row of the chooser opens the scratchpad, one note shared by every book and kept in KOReader's settings folder as `pencil_scratchpad.lua`. It is not listed with the book's notes and never exported
- **Browsing**: **Browse pen notes** in the Pencil menu, **Browse all pen notes** in the chooser, or the **Pencil: browse pen notes** gesture action list every pen note of the book in reading order, book note first, with the page number on the right. Tap a note to open it and closing the canvas returns to the list; long-press a note to go to its place in the book, to export it or to delete it
- **Exporting**: **Export pen notes** in the Pencil menu writes every note of the book as one PDF (one page per note page) or as one PNG image per page. A single note is exported from the browser's long-press menu or from **Export note…** in the canvas menu. Pages are rendered as they look on the canvas, title line and highlighted text included, at the screen's physical size. Files go to `notes/<book>/` at the top of the device's storage (`/mnt/onboard/notes/` on a Kobo) unless **Notes folder** in that submenu points the root elsewhere, and are named after the note: `All notes.pdf`, `Page 12.pdf`, `Chapter - Title - p01.png`
- **Highlight note**: long-press a highlight and tap **Pen note** next to **Note**; it is also in the **…** menu. On a fresh text selection, **Pen note** in the selection menu highlights the text first and then opens the canvas. The highlighted text is shown at the top of the note's first page, and a highlight that has a pen note shows a small pencil glyph in the margin, next to KOReader's own note mark. On ZenOS the selection menu shows plugin buttons only with *Show other items* enabled under *Highlight / Lookup*
- On the canvas the pen draws with the current pen colour and width, holding the side button draws with the highlighter and the eraser end erases. The menu icon offers undo, clear page, delete page, the finger/pen mode switch, export note and delete note; the X closes the canvas and saves it. A note that is closed empty is discarded
- A note has as many pages as you need. The title bar shows the note name and **Page x of y** on one line. Turn the page as in the reader: swipe left (or press the forward page button) to go to the next page; on the last page this adds a blank one. Swipe right (or press the back page button) to go back. **Delete page** in the menu removes the current page (after confirmation if it has strokes); blank pages are also dropped when the note is closed
- Holding the side button and tapping the canvas switches between finger and pen mode, as does the menu. In finger mode the bare pen tip swipes between pages and taps the title bar like a finger, while the side button still highlights and the eraser end still erases
- A page that has a page note shows a small light-gray triangle in its top-right corner
- Page notes in EPUBs follow the text when the layout changes, chapter notes follow their table-of-contents entry, and highlight notes are keyed to the highlight itself

## Questions or Issues with the Plugin

If you have any questions or a feature request, please submit an issue in this repo.
If you're experiencing issues with the plugin, please enable input debug mode in the Pencil menu, reproduce the issue, and include the debug log file in your issue report.

## Experimental Features

Some features are still in development and are hidden behind an experimental toggle. You can find them under **Pencil menu > Experimental**.

### Color picker

When enabled, holding the pen still on the page opens a picker with 10 color options. When disabled, the pen stays on its last-saved color.

**To enable:** Pencil menu > Experimental > Color picker

### Pen width picker

When enabled, the picker also shows pen width options (3, 5, 7, 9), rendered as black bars whose height previews the stroke thickness. **Requires the color picker to also be enabled.**

**To enable:** Pencil menu > Experimental > Pen width picker

### Bookmark Sync

When enabled, the plugin automatically groups your pencil strokes into logical annotations (based on timing and proximity) and creates KOReader bookmarks for each one. This means annotated pages show up in the **Bookmarks menu**, so you can quickly navigate back to pages you've written on.

**To enable:** Pencil menu > Experimental > Bookmark sync

**What happens when you turn it on:**
- Existing pencil annotations are grouped and bookmarks are created immediately
- New strokes are grouped and bookmarked as you draw
- Bookmarks appear in KOReader's Bookmarks menu as "Pencil annotation on page X"
- Erasing or undoing strokes updates the bookmarks automatically

**What happens when you turn it off:**
- All pencil bookmarks are removed from the Bookmarks menu
- Your pencil strokes and drawings are not affected — only the bookmarks are removed
- Annotation groups are still tracked internally, so you won't lose any grouping data if you turn it back on

## Features In the Pipeline

1. Export of annotations
2. Handling changing canvas size

## Acknowledgements

Eraser end detection based on techniques from [eraser.koplugin](https://github.com/SimonLiu423/eraser.koplugin) by SimonLiu.

xoxo
