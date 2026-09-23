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

- The device also runs `coloronhighlight.koplugin`, which wraps Pencil's
  `finishTextHighlight`. Keep that function name and signature stable.

## Planned features

- Browsing all canvas notes.
- Exporting notes as images or PDF.
