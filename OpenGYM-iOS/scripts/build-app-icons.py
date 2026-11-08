#!/usr/bin/env python3
"""Build explicit iOS/watchOS AppIcon sizes with macOS sips; no dependencies.

Run from any directory: python3 OpenGYM-iOS/scripts/build-app-icons.py [--check]
One shared AppIcon contains every platform slot. Regenerate after changing the 1024px artwork.
Explicit slots provide a compatibility fallback for Health/Fitness icon consumers.
"""

import argparse
import json
from pathlib import Path
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def image(size, scale, idiom, **attributes):
    return {
        "filename": f"AppIcon-{int(float(size) * scale)}.png",
        "idiom": idiom,
        "scale": f"{scale}x",
        "size": f"{size}x{size}",
        **attributes,
    }


def catalogs():
    ios = [image(size, scale, "iphone") for size in (20, 29, 40, 60) for scale in (2, 3)]
    ios += [image(size, scale, "ipad") for size in (20, 29, 40, 76) for scale in (1, 2)]
    ios.append(image(83.5, 2, "ipad"))
    ios.append({"filename": "AppIcon-512@2x.png", "idiom": "ios-marketing", "size": "1024x1024", "scale": "1x"})

    watch = [
        image(24, 2, "watch", role="notificationCenter", subtype="38mm"),
        image(27.5, 2, "watch", role="notificationCenter", subtype="42mm"),
        image(33, 2, "watch", role="notificationCenter", subtype="45mm"),
        image(29, 2, "watch", role="companionSettings"),
        image(29, 3, "watch", role="companionSettings"),
    ]
    watch += [image(size, 2, "watch", role="appLauncher", subtype=subtype) for size, subtype in (
        (40, "38mm"), (44, "40mm"), (46, "41mm"), (50, "44mm"), (51, "45mm"), (54, "49mm"),
    )]
    watch += [image(size, 2, "watch", role="quickLook", subtype=subtype) for size, subtype in (
        (86, "38mm"), (98, "42mm"), (108, "44mm"), (117, "45mm"), (129, "49mm"),
    )]
    watch.append({"filename": "AppIcon-512@2x.png", "idiom": "watch-marketing", "size": "1024x1024", "scale": "1x"})
    return ((ROOT / "Resources/Assets.xcassets/AppIcon.appiconset", "AppIcon-512@2x.png", ios + watch),)


def check_png(path, pixels):
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"Not a PNG: {path}")
    if struct.unpack(">II", data[16:24]) != (pixels, pixels) or data[25] not in (0, 2):
        raise ValueError(f"Expected an opaque {pixels}x{pixels} PNG: {path}")
    offset = 8
    while offset < len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        if data[offset + 4:offset + 8] == b"tRNS":
            raise ValueError(f"Transparent app icon: {path}")
        offset += length + 12


def process(check):
    for directory, original, images in catalogs():
        check_png(directory / original, 1024)
        sizes = {entry["filename"]: int(float(entry["size"].split("x")[0]) * int(entry["scale"][0])) for entry in images}
        contents = {"images": images, "info": {"author": "xcode", "version": 1}}
        if check:
            if json.loads((directory / "Contents.json").read_text()) != contents:
                raise ValueError(f"Icon slots are out of date: {directory}; rerun without --check")
        else:
            # Validate every resized PNG before replacing the generated catalog files.
            with tempfile.TemporaryDirectory() as temporary:
                for filename, pixels in sizes.items():
                    if filename == original:
                        continue
                    output = Path(temporary) / filename
                    subprocess.run(["/usr/bin/sips", "-z", str(pixels), str(pixels), str(directory / original), "--out", str(output)],
                                   check=True, stdout=subprocess.DEVNULL)
                    check_png(output, pixels)
                for output in Path(temporary).iterdir():
                    (directory / output.name).write_bytes(output.read_bytes())
            (directory / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")
        for filename, pixels in sizes.items():
            check_png(directory / filename, pixels)
        print(f"{'Checked' if check else 'Generated'} {len(images)} slots / {len(sizes)} PNGs: {directory.relative_to(ROOT)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check icon slots, pixel sizes and opacity without writing files")
    process(parser.parse_args().check)
