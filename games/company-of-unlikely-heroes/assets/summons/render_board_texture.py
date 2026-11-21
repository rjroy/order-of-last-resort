"""Render a Company summon board texture from its open Blender master.

Usage: blender -b --disable-autoexec source/skeleton.blend \
  --python-exit-code 1 --python render_board_texture.py -- /path/to/output
"""

import argparse
import re
import subprocess
import sys
from math import cos, radians, sin
from pathlib import Path
from tempfile import TemporaryDirectory

import bpy
from mathutils import Vector


REVIEW_COLLECTIONS = {
    "skeleton": "REVIEW | Cameras, lights and floor",
    "zombie": "90  Review stage (not part of character)",
}
RENDER_SIZE = 576
TEXTURE_FRAME_SIZE = 288
VIEW_WIDTH = 2.4
ALPHA_MARGIN = 3
INK = "#42382d"


def aim(obj, target):
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def light(collection, label, location, energy, color, size):
    data = bpy.data.lights.new(label, "AREA")
    data.energy, data.color, data.size = energy, color, size
    obj = bpy.data.objects.new(label, data)
    collection.objects.link(obj)
    obj.location = location
    aim(obj, Vector((0, 0, 1)))


def setup_scene(scene, asset, render_file):
    # The source collections, pose, geometry and materials remain as authored.
    bpy.data.collections[REVIEW_COLLECTIONS[asset]].hide_render = True
    rig = bpy.data.collections.new("Board texture rig (in memory only)")
    scene.collection.children.link(rig)

    camera_data = bpy.data.cameras.new("Board orthographic")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = VIEW_WIDTH
    camera = bpy.data.objects.new(camera_data.name, camera_data)
    rig.objects.link(camera)
    target = Vector((0, 0, 1))
    yaw, elevation = radians(20), radians(22)
    toward_camera = Vector((-sin(yaw) * cos(elevation), -cos(yaw) * cos(elevation), sin(elevation)))
    camera.location = target + 8 * toward_camera
    aim(camera, target)
    scene.camera = camera

    light(rig, "Warm key", (-3, -4, 5), 410, (1.0, 0.91, 0.78), 3.15)
    light(rig, "Cool fill", (3, -3, 2.8), 200, (0.82, 0.91, 1.0), 3.4)
    light(rig, "Daylight rim", (1.8, 2.5, 4), 300, (0.96, 0.98, 1.0), 2.8)
    scene.world = bpy.data.worlds.new("Soft ambient")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.35, 0.35, 0.35, 1.0)
    background.inputs["Strength"].default_value = 0.32

    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0
    render = scene.render
    render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.use_denoising = True
    scene.cycles.seed = 0
    render.resolution_x = render.resolution_y = RENDER_SIZE
    render.resolution_percentage = 100
    render.pixel_aspect_x = render.pixel_aspect_y = 1.0
    render.film_transparent = True
    render.use_border = False
    render.use_compositing = False
    render.use_sequencer = False
    render.image_settings.file_format = "PNG"
    render.image_settings.color_mode = "RGBA"
    render.image_settings.color_depth = "8"
    render.filepath = str(render_file)


def magick(*args):
    return subprocess.run(["magick", *map(str, args)], check=True, capture_output=True, text=True).stdout


def crop_texture(render_file, resized_file, texture_file):
    magick(render_file, "-filter", "Mitchell", "-resize", f"{TEXTURE_FRAME_SIZE}x{TEXTURE_FRAME_SIZE}", resized_file)
    bounds = magick(resized_file, "-alpha", "extract", "-threshold", "0", "-format", "%@", "info:")
    match = re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", bounds)
    if match is None:
        raise ValueError(f"Unexpected alpha bounds: {bounds}")
    width, height, x, y = map(int, match.groups())
    margin = ALPHA_MARGIN
    if min(width, height) <= 1 or min(x, y, TEXTURE_FRAME_SIZE - x - width, TEXTURE_FRAME_SIZE - y - height) < margin:
        raise ValueError(f"Empty or clipped render: {bounds}")

    crop = f"{width + 2 * margin}x{height + 2 * margin}+{x - margin}+{y - margin}"
    outlined_file = resized_file.with_name("outlined.png")
    # Expand the alpha onto a soft dark backing. Keep the original render on top.
    magick(
        "-size", f"{TEXTURE_FRAME_SIZE}x{TEXTURE_FRAME_SIZE}", f"xc:{INK}",
        "(", resized_file, "-alpha", "extract", "-morphology", "Dilate", "Disk:2",
        "-evaluate", "Multiply", "0.86", ")",
        "-compose", "CopyAlpha", "-composite", resized_file,
        "-compose", "Over", "-composite", outlined_file,
    )
    magick(outlined_file, "-crop", crop, "+repage", "-strip", f"PNG32:{texture_file}")
    # Projected ground origin in X, bottom of the visible soles in Y.
    anchor_x = TEXTURE_FRAME_SIZE // 2 - x + margin
    anchor_y = height + margin
    print(f"{texture_file.name}: crop {crop}, alpha {width}x{height}, foot pivot ({anchor_x}, {anchor_y})")


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("output_directory", type=Path)
    output = args.parse_args(sys.argv[sys.argv.index("--") + 1 :]).output_directory.resolve()
    asset = Path(bpy.data.filepath).stem
    if asset not in REVIEW_COLLECTIONS:
        args.error("Open source/skeleton.blend or source/zombie.blend")

    output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix=f"{asset}-", dir=output) as temp:
        render_file = Path(temp) / "full.png"
        setup_scene(bpy.context.scene, asset, render_file)
        if "FINISHED" not in bpy.ops.render.render(write_still=True):
            raise RuntimeError(f"Blender did not finish rendering {asset}")
        crop_texture(render_file, Path(temp) / "half.png", output / f"{asset}.png")


if __name__ == "__main__":
    main()
