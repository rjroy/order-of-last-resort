#!/usr/bin/env python3
"""Export Smith petition PNGs and editable OpenRaster documents from the native atlas."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
from xml.etree import ElementTree as ET
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo


HERE = Path(__file__).resolve().parent
SIDE = 627
MIME = b"image/openraster"


def magick(*args):
    return subprocess.check_output(["magick", *map(str, args)])


def signature(path):
    return magick("identify", "-format", "%#", path)


def write_ora(path, label, png, thumb):
    # Generated art is a single raster painting, not separated figures or strokes.
    image = ET.Element("image", version="0.0.3", w=str(SIDE), h=str(SIDE), name=label)
    stack = ET.SubElement(image, "stack")
    ET.SubElement(stack, "layer", {
        "name": "Editable petition painting",
        "src": "data/layer0.png",
        "x": "0", "y": "0", "opacity": "1.0", "visibility": "visible",
        "composite-op": "svg:src-over",
    })
    with ZipFile(path, "x") as archive:
        # Fixed ZIP timestamps, with mimetype as the first uncompressed file.
        entries = (
            ("mimetype", MIME, ZIP_STORED),
            ("stack.xml", ET.tostring(image, encoding="utf-8"), ZIP_DEFLATED),
            ("data/layer0.png", png, ZIP_STORED),
            ("mergedimage.png", png, ZIP_STORED),
            ("Thumbnails/thumbnail.png", thumb, ZIP_STORED),
        )
        for name, payload, compression in entries:
            archive.writestr(ZipInfo(name, (1980, 1, 1, 0, 0, 0)), payload, compress_type=compression)


def verify_ora(path, png, scratch):
    with ZipFile(path) as archive:
        assert archive.testzip() is None
        mime = archive.infolist()[0]
        assert mime.filename == "mimetype" and mime.compress_type == ZIP_STORED
        assert archive.read("mimetype") == MIME
        image = ET.fromstring(archive.read("stack.xml"))
        assert (image.attrib["w"], image.attrib["h"]) == (str(SIDE), str(SIDE))
        layer = image.find("./stack/layer")
        assert layer is not None and layer.attrib["visibility"] == "visible"
        assert archive.read(layer.attrib["src"]) == archive.read("mergedimage.png") == png.read_bytes()
        # Read through a real OpenRaster decoder, not just ZIP extraction.
        magick(path, f"PNG24:{scratch}")
        assert signature(scratch) == signature(png), f"{path}: decoded pixels differ"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Fresh directory for candidate masters and plates")
    args = parser.parse_args()
    recipe = json.loads((HERE / "recipe.json").read_text())
    atlas = HERE / recipe["source"]
    if hashlib.sha256(atlas.read_bytes()).hexdigest() != recipe["source_sha256"]:
        raise ValueError("Unexpected native atlas hash")
    if magick("identify", "-format", "%m %w %h %[colorspace] %[opaque] %z", atlas) != b"PNG 1254 1254 sRGB True 8":
        raise ValueError("Native atlas is not the expected opaque 1254 square RGB")
    if recipe["edge_feather_px"] != 0:
        raise ValueError("Numbered-stock convention has no alpha feather")
    if {tuple(row["offset"]) for row in recipe["plates"].values()} != {(0, 0), (SIDE, 0), (0, SIDE)}:
        raise ValueError("Expected the three populated native quadrants")

    args.output.mkdir()
    masters, plates = args.output / "masters", args.output / "plates"
    masters.mkdir()
    plates.mkdir()
    signatures = set()
    with TemporaryDirectory(dir=args.output) as temp:
        scratch = Path(temp)
        for key, row in recipe["plates"].items():
            x, y = row["offset"]
            crop = [atlas, "-crop", f"{SIDE}x{SIDE}+{x}+{y}", "+repage"]
            plate = plates / f"{key}.png"
            magick(*crop, "-strip", "-define", "png:exclude-chunk=date,time", f"PNG24:{plate}")
            info = magick("identify", "-format", "%m %w %h %[colorspace] %[opaque] %z %[channels]", plate)
            assert info == b"PNG 627 627 sRGB True 8 srgb  3.0", (key, info)
            pixels = signature(plate)
            assert pixels == magick(*crop, "-format", "%#", "info:"), f"{key}: source pixels changed"
            assert pixels not in signatures, f"{key}: duplicate plate"
            signatures.add(pixels)
            thumb = magick(plate, "-filter", "Lanczos", "-resize", "256x256", "-strip",
                           "-define", "png:exclude-chunk=date,time", "PNG24:-")
            master = masters / f"{key}.ora"
            write_ora(master, row["label"], plate.read_bytes(), thumb)
            verify_ora(master, plate, scratch / "decoded.png")
            print(f"{key}: unresized opaque 627 x 627 PNG and editable OpenRaster verified")


if __name__ == "__main__":
    main()
