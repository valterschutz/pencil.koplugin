#!/usr/bin/env python3
"""Copy the plugin (and the patched input.lua) onto a mounted Kobo.

Usage: ./deploy.py [KOBO_MOUNT]
KOBO_MOUNT defaults to /run/media/$USER/KOBOeReader.
"""

import filecmp
import os
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent
PLUGIN_SRC = REPO / "pencil.koplugin"
INPUT_SRC = REPO / "input.lua"


def main() -> None:
    assert len(sys.argv) <= 2, "usage: deploy.py [KOBO_MOUNT]"
    mount = Path(sys.argv[1]) if len(sys.argv) == 2 else Path(f"/run/media/{os.environ['USER']}/KOBOeReader")
    koreader = mount / ".adds" / "koreader"
    assert koreader.is_dir(), f"KOReader not found at {koreader}; is the Kobo mounted?"
    assert (PLUGIN_SRC / "main.lua").is_file(), f"plugin source missing at {PLUGIN_SRC}"
    assert INPUT_SRC.is_file(), f"patched input.lua missing at {INPUT_SRC}"

    plugin_dst = koreader / "plugins" / "pencil.koplugin"
    if plugin_dst.exists():
        shutil.rmtree(plugin_dst)
    shutil.copytree(PLUGIN_SRC, plugin_dst)
    print(f"plugin  -> {plugin_dst}")

    input_dst = koreader / "frontend" / "device" / "input.lua"
    assert input_dst.is_file(), f"expected KOReader input.lua at {input_dst}"
    if filecmp.cmp(INPUT_SRC, input_dst, shallow=False):
        print(f"input   == {input_dst} (unchanged)")
    else:
        shutil.copy2(INPUT_SRC, input_dst)
        print(f"input   -> {input_dst}")

    os.sync()
    print("done; restart KOReader on the device")


if __name__ == "__main__":
    main()
