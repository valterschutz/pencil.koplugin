# Changelog

Fork of [mysticknits/pencil.koplugin](https://github.com/mysticknits/pencil.koplugin).
`main` tracks upstream; `dev` is the integration branch deployed to the Kobo.

## 2026-09-23

- Forked upstream at 0.5.0. Rebased the edits previously living only on the
  device (sticky highlight state across side-button release, pcall-guarded key
  parsing) onto it.
- Added `deploy.py` to copy the plugin and patched `input.lua` to a mounted Kobo.

## Planned

- Quick side-button tap toggles finger mode / pen mode instead of pen / eraser.
  In finger mode stylus events fall through to normal touch handling and
  holding the button does nothing. In pen mode holding the button highlights.
- Blank note canvas for pen notes, attachable per highlight, per page, or per
  chapter.
