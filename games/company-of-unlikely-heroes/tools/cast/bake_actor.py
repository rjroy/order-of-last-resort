"""Blender-side renderer. Invoked by bake_cast.py; never saves the open master."""

import hashlib
import json
import argparse
import subprocess
import sys
from contextlib import contextmanager
from math import radians
from pathlib import Path
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from takes import DERIVED_TAKES, PILOT, RELEASES, TAKES
from recipe import action_name, capture_config, load_fragment, load_registered, release_prop_hidden, rig_name

ART = HERE.parents[3] / ".lore/work/games/company-of-unlikely-heroes/art"
# Pilot's exact pixels/metre, enlarged symmetrically to protect tall/extending poses.
SIZE = 320
ANCHOR = [160, 248]


def ink_light(mat, bottle_glass=False):
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
    surface = em.outputs[0]
    if bottle_glass:
        # Opaque ink would cover the dyed liquid. Use a soft tint with stronger
        # grazing edges so the vessel and its color both read in a flat sprite.
        facing = nodes("ShaderNodeLayerWeight")
        opacity = nodes("ShaderNodeMath")
        opacity.operation = "MULTIPLY_ADD"
        link(facing.outputs["Fresnel"], opacity.inputs[0])
        opacity.inputs[1].default_value = 0.34
        opacity.inputs[2].default_value = 0.15
        glass = nodes("ShaderNodeMixShader")
        link(opacity.outputs[0], glass.inputs[0])
        link(nodes("ShaderNodeBsdfTransparent").outputs[0], glass.inputs[1])
        link(surface, glass.inputs[2])
        surface = glass.outputs[0]
    link(
        surface,
        next(n for n in t.nodes if n.type == "OUTPUT_MATERIAL").inputs["Surface"],
    )


def setup(scene, role, anchor, size=SIZE):
    s = scene
    for mat in bpy.data.materials:
        if mat.node_tree and any(
            n.type == "BSDF_PRINCIPLED" for n in mat.node_tree.nodes
        ):
            ink_light(
                mat, bottle_glass=role == "alchemist" and mat.name.startswith("Bottle glass")
            )
    cam = bpy.data.cameras.new("Pilot common orthographic")
    c = bpy.data.objects.new("Registration camera", cam)
    s.collection.objects.link(c)
    s.camera = c
    c.rotation_euler = (1.150829196, 0, -0.435386419)
    cam.type = "ORTHO"
    cam.ortho_scale = 2.44 * size / 256
    # Off-axis framing preserves the common projection and ground anchor;
    # it only reallocates transparent capture space toward a long prop.
    c.location = c.rotation_euler.to_matrix() @ Vector(
        (
            cam.ortho_scale * (0.5 - anchor[0] / size),
            cam.ortho_scale * (anchor[1] / size - 0.5),
            6,
        )
    )
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = 12
    s.cycles.use_denoising = False
    s.cycles.use_adaptive_sampling = False
    s.cycles.use_animated_seed = False
    s.cycles.seed = 14
    s.render.resolution_x = s.render.resolution_y = size
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


@contextmanager
def ready_turns(rig, turns, carried=None):
    """Turn bones in a sampled pose without keying the native take."""
    if not turns and carried is None:
        yield
        return
    # A still render evaluates animation again. Hold the sampled FK channels
    # without the native action assigned so that evaluation cannot undo edits.
    channels = [
        (bone, bone.location.copy(), bone.rotation_quaternion.copy(), bone.scale.copy())
        for bone in rig.pose.bones
    ]
    offsets = {}
    for name, angles in turns:
        axes = rig.pose.bones[name].matrix.to_quaternion()
        turn = Euler(tuple(map(radians, angles))).to_quaternion()
        offsets[name] = axes.inverted() @ turn @ axes
    animation = rig.animation_data
    native, slot = animation.action, animation.action_slot
    if carried:
        prop, grip = (rig.pose.bones[name] for name in carried)
        grip_space = grip.matrix.inverted() @ prop.matrix
        prop_basis = prop.matrix_basis.copy()
    animation.action = None
    edited_rotations = []
    try:
        for bone, location, rotation, scale in channels:
            assert bone.rotation_mode == "QUATERNION"
            bone.location = location
            turn = offsets.get(bone.name)
            if turn is not None:
                edited_rotations.append((bone, rotation))
            bone.rotation_quaternion = rotation @ turn if turn is not None else rotation
            bone.scale = scale
        bpy.context.view_layer.update()
        if carried:
            prop.matrix = grip.matrix @ grip_space
            bpy.context.view_layer.update()
        yield
    finally:
        if carried:
            prop.matrix_basis = prop_basis
        for bone, rotation in edited_rotations:
            bone.rotation_quaternion = rotation
        animation.action = native
        animation.action_slot = slot


def render_ink(scene, raw, out, size):
    scene.render.filepath = str(raw)
    bpy.ops.render.render(write_still=True)
    magick(
        raw, "-alpha", "extract", "-morphology", "Dilate", "Disk:2",
        "-write", "mpr:mask", "+delete", "-size", f"{size}x{size}", "xc:#352b28",
        "mpr:mask", "-compose", "CopyOpacity", "-composite", raw, "-compose",
        "Over", "-composite", "-strip", f"PNG32:{out}",
    )


def bake(role, work, recipe=None):
    masters, takes, releases = load_registered(
        HERE / "actors", json.loads((HERE / "masters.json").read_text()), TAKES, RELEASES, [role]
    )
    masters, takes, releases = load_fragment(recipe, masters, takes, releases)
    master = masters[role]
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
    size, anchor = capture_config(master)
    if role in PILOT and size != SIZE:
        raise ValueError("pilot strip reuse requires the original 320px canvas")
    setup(s, role, anchor, size)
    rig = bpy.data.objects[rig_name(role, master)]
    release = releases.get(role)
    if release:
        actor_clip, prop_clip, prop_name, release_frame, marker = release
        root = bpy.data.objects[prop_name]
        prop = {root, *root.children_recursive}
        visibility = {
            o: o.hide_render
            for o in s.objects
            if o.type in {"MESH", "CURVE", "SURFACE", "FONT"}
        }
    cache = {}
    data = {}
    pilot_clip = {"knight": "guard", "healer": "ally_heal"}.get(role)
    shield_draw = {}
    if role == "knight":
        shield_draw = {
            part: part.hide_render
            for part in bpy.data.objects["Shield_L_Detachable"].children_recursive
        }
    for clip, (action, frames, end, loop) in takes[role].items():
        performance = DERIVED_TAKES.get((role, clip))
        native_action = performance.source_action if performance else action
        take = bpy.data.actions[action_name(role, master, native_action)]
        rig.animation_data.action = take
        data[clip] = {
            "frames": [], "loop": loop, "anchor": anchor,
            "action": action_name(role, master, action),
        }
        for i, f in enumerate(frames):
            pose = performance.poses[i] if performance else None
            native_frame = pose.source if pose else f
            s.frame_set(int(native_frame), subframe=native_frame % 1)
            variant = ""
            without_shield = role == "knight" and clip in ("shield_away", "rescue_line_unshielded")
            if without_shield:
                variant = "without_shield"
            for part, hidden in shield_draw.items():
                part.hide_render = without_shield or hidden
            if release:
                prop_only = clip == prop_clip
                empty_hand = clip == actor_clip and f >= release_frame
                window = master.get("release_visible_frames")
                hidden_prop = empty_hand or (window is not None and release_prop_hidden(window, clip, f))
                for o, hidden in visibility.items():
                    o.hide_render = (
                        hidden or (prop_only and o not in prop) or (not prop_only and hidden_prop and o in prop)
                    )
                if prop_only:
                    variant = "prop_only"
                elif empty_hand:
                    variant = "empty_hand"
                elif hidden_prop:
                    variant = "hidden_prop"
                if (prop_only or empty_hand) and f == release_frame:
                    if marker:
                        assert take.pose_markers[marker].frame == f
                    uv = world_to_camera_view(
                        s, s.camera, root.matrix_world.translation
                    )
                    px = [round(uv.x * size, 3), round((1 - uv.y) * size, 3)]
                    if prop_only:
                        data[clip]["anchor"] = px
                    else:
                        data[clip]["release"] = {
                            "time_ms": round((f - frames[0]) * 1000 / 24),
                            "offset": [round(a - b, 3) for a, b in zip(px, anchor)],
                            "clip": prop_clip,
                        }
            turns = pose.turns if pose else ()
            carried = pose.carried if pose else None
            # A neutral start or reset can reuse the exact pilot drawing.
            # Keep the original full-canvas renders for later ready samples.
            use_pilot = pilot_clip is not None and (
                clip == pilot_clip or (
                    performance is not None and not turns and carried is None
                    and not without_shield and (clip != "ready" or i == 0)
                    and native_frame in takes[role][pilot_clip][1]
                )
            )
            key = (native_action, native_frame, variant, turns, carried, use_pilot)
            if key not in cache:
                out = work / f"{role}-{len(cache):03d}.png"
                cache[key] = out
                if use_pilot:
                    name = f"{role}_{pilot_clip}"
                    index = takes[role][pilot_clip][1].index(native_frame)
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
                    with ready_turns(rig, turns, carried):
                        render_ink(s, work / f"{role}-raw.png", out, size)
            start = frames[0]
            stop = frames[i + 1] if i + 1 < len(frames) else end
            ms = round((stop - start) * 1000 / 24) - round((f - start) * 1000 / 24)
            data[clip]["frames"].append(
                {"source_frame": f, "duration_ms": ms, "file": cache[key].name}
            )
    verify()
    (work / f"{role}.json").write_text(json.dumps(data))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("role")
    parser.add_argument("work", type=Path)
    parser.add_argument("--recipe", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1 :])
    bake(args.role, args.work, args.recipe)
