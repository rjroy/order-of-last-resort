"""Blender-side renderer. Invoked by bake_cast.py; never saves the open master."""

import hashlib
import json
import subprocess
import sys
from pathlib import Path
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from takes import TAKES, PILOT

ART = HERE.parents[3] / ".lore/work/games/company-of-unlikely-heroes/art"
# Pilot's exact pixels/metre, enlarged symmetrically to protect tall/extending poses.
SIZE = 320
ANCHOR = [160, 248]


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


def setup(scene):
    s = scene
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
    cam.ortho_scale = 2.44 * SIZE / 256
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


def bake(role, work):
    master = json.loads((HERE / "masters.json").read_text())[role]
    path = ART / master["source"]

    def verify():
        assert hashlib.sha256(path.read_bytes()).hexdigest() == master["sha256"], path

    verify()
    bpy.ops.wm.open_mainfile(filepath=str(path))
    s = bpy.context.scene
    assert bpy.app.version[:3] == (5, 2, 2) and not bpy.data.libraries
    for o in s.objects:
        if o.type == "LIGHT" or (
            o.type == "MESH"
            and any(
                word in o.name.lower()
                for word in (
                    "review ground",
                    "review floor",
                    "studio floor",
                    "ground • review",
                    "paper ground",
                    "shadow ground",
                )
            )
        ):
            o.hide_render = True
    setup(s)
    rig = bpy.data.objects[role.title() + "_Rig"]
    cache = {}
    data = {}
    for clip, (action, frames, end, loop) in TAKES[role].items():
        take = bpy.data.actions[f"{role.title()} | {action}"]
        rig.animation_data.action = take
        data[clip] = {"frames": [], "loop": loop, "anchor": ANCHOR, "action": take.name}
        for i, f in enumerate(frames):
            s.frame_set(f)
            variant = ""
            if role == "knight" and clip == "shield_away":
                variant = "without_shield"
                for o in bpy.data.objects["Shield_L_Detachable"].children_recursive:
                    o.hide_render = True
            if role == "zombie" and clip in ("offer_flower", "gift") and f >= 22:
                root = bpy.data.objects["Daisy & fieldstone"]
                prop = set(root.children_recursive)
                if f == 22:
                    assert take.pose_markers["Gift Release"].frame == f
                    uv = world_to_camera_view(
                        s, s.camera, root.matrix_world.translation
                    )
                    px = [round(uv.x * SIZE, 3), round((1 - uv.y) * SIZE, 3)]
                    if clip == "gift":
                        data[clip]["anchor"] = px
                    else:
                        data[clip]["release"] = {
                            "time_ms": 875,
                            "offset": [round(a - b, 3) for a, b in zip(px, ANCHOR)],
                            "clip": "gift",
                        }
                variant = "gift_only" if clip == "gift" else "empty_hand"
                for o in s.objects:
                    if o.type in {"MESH", "CURVE", "SURFACE", "FONT"}:
                        if clip == "gift":
                            o.hide_render = o not in prop
                        elif o in prop:
                            o.hide_render = True
            key = (action, f, variant)
            if key not in cache:
                out = work / f"{role}-{len(cache):03d}.png"
                cache[key] = out
                if role in PILOT and (clip in ("guard", "ally_heal", "ready")):
                    pilot_clip = "guard" if role == "knight" else "ally_heal"
                    name = f"{role}_{pilot_clip}"
                    index = TAKES[role][pilot_clip][1].index(f)
                    src = ART / "pilots/ferryman-crossing/assets" / f"{name}.png"
                    assert hashlib.sha256(src.read_bytes()).hexdigest() == PILOT[role]
                    magick(
                        src,
                        "-crop",
                        f"256x256+{256 * index}+0",
                        "+repage",
                        "-bordercolor",
                        "none",
                        "-border",
                        32,
                        "-strip",
                        f"PNG32:{out}",
                    )
                else:
                    raw = work / f"{role}-raw.png"
                    s.render.filepath = str(raw)
                    bpy.ops.render.render(write_still=True)
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
                        f"{SIZE}x{SIZE}",
                        "xc:#352b28",
                        "mpr:mask",
                        "-compose",
                        "CopyOpacity",
                        "-composite",
                        raw,
                        "-compose",
                        "Over",
                        "-composite",
                        "-strip",
                        f"PNG32:{out}",
                    )
            start = frames[0]
            stop = frames[i + 1] if i + 1 < len(frames) else end
            ms = round((stop - start) * 1000 / 24) - round((f - start) * 1000 / 24)
            data[clip]["frames"].append(
                {"source_frame": f, "duration_ms": ms, "file": cache[key].name}
            )
    verify()
    (work / f"{role}.json").write_text(json.dumps(data))


if __name__ == "__main__":
    role, work = sys.argv[sys.argv.index("--") + 1 :]
    bake(role, Path(work))
