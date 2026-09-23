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
- "Side button tap" setting: a quick press toggles pencil/eraser (upstream
  default) or finger/pen mode.
- A side-button press held longer than 500 ms no longer counts as a tap, in
  either mode.
- `spec/side_button_spec.lua` covers the tap/hold decision and mode switching.

## Planned

- Blank note canvas for pen notes, attachable per highlight, per page, or per
  chapter.
