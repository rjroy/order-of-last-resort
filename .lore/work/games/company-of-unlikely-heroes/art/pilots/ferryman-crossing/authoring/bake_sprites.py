"""From the pilot directory: blender -b -t 8 --python-exit-code 1 -P authoring/bake_sprites.py
Requires Blender 5.2.2 LTS and ImageMagick 7. No source file is written.
"""

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT.parents[1] / "models"
ASSETS = ROOT / "assets"
SIZE = 256
ANCHOR = [128, 216]
TAKES = {
    "knight_guard": (
        [8, 14, 20, 25, 31, 35, 39, 44, 51, 65],
        [250, 250, 208, 250, 167, 167, 208, 292, 583, 542],
    ),
    "healer_ally_heal": (
        [1, 4, 7, 10, 13, 17, 20, 23, 26, 28],
        [125, 125, 125, 125, 167, 125, 125, 125, 83, 208],
    ),
    "crate": ([1], [1000]),
}
SOURCES = {
    "knight_guard": (
        "knight/knight-guard-blockout.blend",
        "0bdf470f4472f2ee269337e458b605bf53be0f36f700e9ebbf8156147e10b45b",
    ),
    "healer_ally_heal": (
        "healer/healer-blockout.blend",
        "3a0b8427c788a26b511a6f6262c6debeb3fbcea78fa2c44fd867b32e5010aaa5",
    ),
}


def ink_light(mat):
    """Reuse the model's actual base pigment maps; break up light in object space.
    All lighting is deterministic and attached to surface geometry, not screen grain.
    """
    t = mat.node_tree
    p = next(n for n in t.nodes if n.type == "BSDF_PRINCIPLED")
    nodes, link = t.nodes.new, t.links.new
    color = p.inputs["Base Color"]
    src = color.links[0].from_socket if color.is_linked else None
    n = nodes("ShaderNodeNewGeometry")
    dot = nodes("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    link(n.outputs["Normal"], dot.inputs[0])
    dot.inputs[1].default_value = Vector((-0.62, -0.64, 0.77)).normalized()
    tex = nodes("ShaderNodeTexNoise")
    tex.inputs["Scale"].default_value = 5
    tex.inputs["Detail"].default_value = 1.4
    coords = nodes("ShaderNodeTexCoord")
    link(coords.outputs["Generated"], tex.inputs[0])
    small = nodes("ShaderNodeMath")
    small.operation = "MULTIPLY_ADD"
    link(tex.outputs["Fac"], small.inputs[0])
    small.inputs[1].default_value = 0.32
    small.inputs[2].default_value = -0.16
    plus = nodes("ShaderNodeMath")
    plus.operation = "ADD"
    link(dot.outputs["Value"], plus.inputs[0])
    link(small.outputs[0], plus.inputs[1])
    ramp = nodes("ShaderNodeValToRGB")
    link(plus.outputs[0], ramp.inputs[0])
    cr = ramp.color_ramp
    cr.interpolation = "EASE"
    cr.elements.remove(cr.elements[1])
    cr.elements[0].color = (0.48, 0.47, 0.53, 1)
    for at, col in [
        (0.19, (0.55, 0.52, 0.55)),
        (0.28, (0.89, 0.83, 0.77)),
        (0.55, (0.91, 0.85, 0.80)),
        (0.68, (1.16, 1.07, 0.96)),
        (0.93, (1.42, 1.31, 1.15)),
    ]:
        cr.elements.new(at).color = (*col, 1)
    mix = nodes("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1
    if src is not None:
        link(src, mix.inputs[1])
    else:
        mix.inputs[1].default_value = color.default_value
    link(ramp.outputs[0], mix.inputs[2])
    em = nodes("ShaderNodeEmission")
    link(mix.outputs[0], em.inputs[0])
    em.inputs[1].default_value = 1.25
    link(
        em.outputs[0],
        next(n for n in t.nodes if n.type == "OUTPUT_MATERIAL").inputs["Surface"],
    )


def create_crate():
    woods = []
    for name, rgb in [
        ("Tarred seams", (0.058, 0.031, 0.018)),
        ("Honey larch", (0.38, 0.19, 0.067)),
        ("Ferry oak", (0.29, 0.135, 0.046)),
        ("Pale battens", (0.44, 0.24, 0.098)),
        ("Iron pegs", (0.068, 0.058, 0.045)),
    ]:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (
            *rgb,
            1,
        )
        woods.append(m)

    def board(pos, dim, role, rotation=0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
        o = bpy.context.object
        o.dimensions = dim
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        o.rotation_euler.y = rotation
        o.data.materials.append(woods[role])
        b = o.modifiers.new("Adzed edges", "BEVEL")
        b.width = 0.007
        b.segments = 1

    board((0, 0, 0.31), (0.84, 0.65, 0.61), 0)
    for i in range(5):
        x = (i - 2) * 0.164
        board((x, 0, 0.628), (0.155, 0.65, 0.025), 1 + i % 2)
        board((x, -0.331, 0.31), (0.155, 0.022, 0.60), 1 + i % 2)
    for s in (-1, 1):
        for i in range(3):
            board((s * 0.426, 0, 0.12 + i * 0.185), (0.024, 0.63, 0.172), 1 + i % 2)
        for z in (0.062, 0.568):
            board((s * 0.44, 0, z), (0.028, 0.67, 0.087), 3)
        board((s * 0.351, -0.353, 0.314), (0.085, 0.038, 0.60), 3)
    for z in (0.065, 0.562):
        board((0, -0.363, z), (0.835, 0.032, 0.083), 3)
        for x in (-0.35, 0.35):
            board((x, -0.384, z), (0.029, 0.015, 0.029), 4)
    board((0, -0.356, 0.31), (0.079, 0.043, 0.754), 3, 0.96)


def scene_for(key):
    if key in SOURCES:
        rel, sha = SOURCES[key]
        file = MODELS / rel
        assert hashlib.sha256(file.read_bytes()).hexdigest() == sha
        bpy.ops.wm.open_mainfile(filepath=str(file))
        s = bpy.context.scene
        for o in s.objects:
            if not o.parent and o.type in {"MESH", "LIGHT"}:
                o.hide_render = True
        if key == "healer_ally_heal":
            bpy.data.objects["Healer_Rig"].animation_data.action = bpy.data.actions[
                "Healer | Ally Heal"
            ]
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        s = bpy.context.scene
        create_crate()
    for mat in bpy.data.materials:
        if mat.node_tree and any(
            n.type == "BSDF_PRINCIPLED" for n in mat.node_tree.nodes
        ):
            ink_light(mat)
    cam = bpy.data.cameras.new("Pilot common orthographic")
    c = bpy.data.objects.new("Registration camera", cam)
    s.collection.objects.link(c)
    s.camera = c
    c.rotation_euler = (1.150829196, 0, -0.435386419)
    cam.type = "ORTHO"
    cam.ortho_scale = 2.44
    c.location = c.rotation_euler.to_matrix() @ Vector(
        (0, cam.ortho_scale * (ANCHOR[1] / SIZE - 0.5), 6)
    )
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = 12
    s.cycles.use_denoising = False
    s.cycles.use_adaptive_sampling = False
    s.cycles.use_animated_seed = False
    s.cycles.seed = 14
    s.render.resolution_x = s.render.resolution_y = SIZE
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGBA"
    s.render.image_settings.color_depth = "8"
    s.view_settings.view_transform = "Standard"
    s.view_settings.look = "None"
    s.view_settings.exposure = 0
    s.render.dither_intensity = 0
    return s


def magick(*args):
    subprocess.run(["magick", *map(str, args)], check=True)


def bake():
    ASSETS.mkdir(exist_ok=True)
    meta = {
        "version": 1,
        "display_scale": 0.375,
        "registration_size": [SIZE, SIZE],
        "facing": "front three-quarter, one facing",
        "camera": {
            "orthographic_width_m": 2.44,
            "euler_xyz_radians": [1.150829196, 0, -0.435386419],
        },
        "sprites": {},
    }
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp)
        for key, (frames, times) in TAKES.items():
            scene = scene_for(key)
            packed = []
            for i, frame in enumerate(frames):
                scene.frame_set(frame)
                raw = scratch / "raw.png"
                scene.render.filepath = str(raw)
                bpy.ops.render.render(write_still=True)
                out = scratch / f"{key}-{i}.png"
                # A warm contour strictly derived from the current solid silhouette.
                magick(
                    raw,
                    "-alpha",
                    "extract",
                    "-morphology",
                    "Dilate",
                    "Disk:2",
                    "-write",
                    "mpr:mask",
                    "+delete",
                    "-size",
                    "256x256",
                    "xc:#352b28",
                    "mpr:mask",
                    "-compose",
                    "CopyOpacity",
                    "-composite",
                    raw,
                    "-compose",
                    "Over",
                    "-composite",
                    f"PNG32:{out}",
                )
                packed.append(out)
            magick(*packed, "+append", "-strip", f"PNG32:{ASSETS / key}.png")
            meta["sprites"][key] = {
                "texture": f"assets/{key}.png",
                "anchor": ANCHOR,
                "loop": False,
                "frames": [
                    {
                        "rect": [i * SIZE, 0, SIZE, SIZE],
                        "duration_ms": ms,
                        "source_frame": f,
                    }
                    for i, (f, ms) in enumerate(zip(frames, times))
                ],
            }
        (ASSETS / "sprites.json").write_text(json.dumps(meta, indent=2) + "\n")
    for rel, sha in SOURCES.values():
        assert hashlib.sha256((MODELS / rel).read_bytes()).hexdigest() == sha


if __name__ == "__main__":
    bake()
