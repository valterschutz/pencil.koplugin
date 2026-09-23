# AGENTS.md

Fork of [mysticknits/pencil.koplugin](https://github.com/mysticknits/pencil.koplugin),
a KOReader stylus plugin, run on a Kobo Libra Colour (Kobo_monza) with the Kobo Stylus 2.

## Branches

- `upstream` remote is mysticknits; `main` tracks it and carries no local edits.
- `dev` is the integration branch and is what gets deployed to the device.
- Feature branches are cut from `dev` and merged back into `dev`.
- Finger mode may become an upstream PR; keep it separable.

## Workflow

- Keep `CHANGELOG.md` updated with every feature or fix.
- Tests: `nix shell nixpkgs#lua51Packages.busted -c busted`. The specs are
  mock-based and never load `main.lua`, so a green suite says nothing about the
  device. Every change must be verified on the Kobo before it is considered done.
- Deploy: the Kobo needs "Connect" tapped on-device first. Then run the whole
  sequence in one step so the device can be unplugged straight afterwards:

  ```sh
  udisksctl mount -b /dev/sda && ./deploy.py && udisksctl unmount -b /dev/sda && udisksctl power-off -b /dev/sda
  ```

  Unmount alone leaves the block device attached, so Thunar keeps showing it
  and the Kobo stays in USB mode. `power-off` is what detaches it.

## Hardware constraints

- The Libra Colour digitizer reports the pen only while the tip touches the
  screen. A side-button press without contact produces no input event at all
  (confirmed via the plugin's input debug log). Any button gesture must
  therefore involve a tap on the page. Upstream's "tap side button to toggle"
  never worked on this device.

## Compatibility

- The device runs a ZenOS build of KOReader (v2026.03 at the time of writing,
  see `.adds/koreader/git-rev`), with `zenos.koplugin` installed.
- ZenOS's "Zen highlight menu" (`zenos.koplugin/modules/reader/patches/highlight_menu.lua`)
  replaces `ReaderHighlight:onShowHighlightMenu`, the "…" menu of a highlight
  and the menu of a fresh text selection, with an icon row. Buttons that
  plugins register via `addToHighlightDialog` only appear there when the ZenOS
  setting "Show other items" (Highlight / Lookup) is on, and it is off by
  default. That is why "Pen note" is also injected into the long-press
  edit-highlight dialog, which ZenOS leaves alone (see
  `Pencil:installEditHighlightDialogButton`). When something is missing from a
  highlight menu, check that patch before debugging the plugin.
- The device also runs `coloronhighlight.koplugin`, which wraps Pencil's
  `finishTextHighlight` and `ReaderHighlight.onShowHighlightMenu`. Keep that
  function name and signature stable.
- Debugging on the device: `.adds/koreader/crash.log` has the plugin's
  `logger.info` lines and the traceback of a crash. Read it over USB before
  guessing.

## Planned features

- Browsing all canvas notes.
- Exporting notes as images or PDF.
