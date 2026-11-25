"""Reopen the saved Actions on the unchanged donor, check fit, and render proof."""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, str(Path(__file__).resolve().parent))
from knight_fitted import DONOR, DONOR_SHA, GUARD, RIG, SHIELD, TAKES, digest, require_donor, select

ROOT = DONOR.parents[7]
CAST_TOOLS = ROOT / "games/company-of-unlikely-heroes/tools/cast"
sys.path.insert(0, str(CAST_TOOLS))
from bake_actor import ANCHOR, SIZE, render_ink, setup


def load_actions(library):
    names = {take.name for take in TAKES.values()}
    with bpy.data.libraries.load(str(library), link=False) as (source, target):
        assert set(source.actions) == names
        assert not (source.meshes or source.armatures or source.objects or source.materials
                    or source.images or source.collections or source.scenes), "Library includes donor content"
        target.actions = sorted(names)
    return {action.name: action for action in target.actions}


def surface(obj):
    return BVHTree.FromPolygons(
        [obj.matrix_world @ v.co for v in obj.data.vertices],
        [tuple(p.vertices) for p in obj.data.polygons],
    )


BODY = (
    "Face • cheeks, sockets and chin", "Neck • scarf bridge", "Chest • creased fitted gambeson",
    "Quilted sleeve L", "Rerebrace L", "Elbow articulation L",
    "Couter • pointed elbow L", "Vambrace • ridged L", "Wrapped wrist L",
    "Quilted sleeve R", "Vambrace • ridged R", "Wrapped wrist R",
    *(f"Glove • tapered palm {side}" for side in ("R", "L")),
    *(f"Glove • stitched digit {side} {digit}" for side in ("R", "L") for digit in range(1, 5)),
)
PAULDRONS = {
    "R": ("Right pauldron • raised bowl", "Right pauldron • first sliding lame"),
    "L": ("Left pauldron • cutback cap", "Left pauldron • short lame"),
}


def geometry_check(scene, rig, take, action, ready):
    select(rig, action)
    assert action["donor_sha256"] == DONOR_SHA and action["fps"] == 24
    assert (action.frame_range.x, action.frame_range.y) == (1, take.last)
    assert [(m.name, m.frame) for m in action.pose_markers] == [(take.marker, take.key_frame)]
    objects = bpy.data.objects
    collision = {}
    soles = []
    drift = []
    bones = rig.pose.bones
    oak = objects["Shield • curved oak outer skin"]
    for frame in range(1, take.last + 1):
        scene.frame_set(frame)
        assert all(math.isfinite(v) for bone in bones for row in bone.matrix for v in row)
        if frame in (1, take.last):
            assert all(abs(v) < .00002 for b in bones for row in (b.matrix - ready[b.name]) for v in row)
        for side in ("R", "L"):
            foot = bones[f"boot.{side}"].matrix.translation
            drift.append((foot - ready[f"boot.{side}"].translation).length)
            boot = objects[f"Boot • bent leather {side}"]
            soles.append(min((boot.matrix_world @ vertex.co).z for vertex in boot.data.vertices))
        head_parts = [surface(objects[name]) for name in BODY[:2]]
        for side, plates in PAULDRONS.items():
            skin = [*head_parts, surface(objects[f"Ear {side}"])]
            for plate in plates:
                shell = surface(objects[plate])
                if any(shell.overlap(part) for part in skin):
                    collision.setdefault(f"{plate} / head-neck", []).append(frame)
        if frame < action.get("prop_release_frame", take.last + 1):
            shield = surface(oak)
            for name in BODY:
                if shield.overlap(surface(objects[name])):
                    collision.setdefault(f"shield face / {name}", []).append(frame)
    print(f"{take.label}: foot drift {max(drift)*1000:.2f} mm; soles "
          f"{min(soles)*1000:.2f} to {max(soles)*1000:.2f} mm", flush=True)
    issues = [f"{take.label}, {part}: frames {frames}" for part, frames in collision.items()]
    if not (max(drift) < .001 and .003 <= min(soles) and max(soles) <= .005):
        issues.append(f"{take.label}: foot drift or sole heights outside bounds")
    return issues


def projection(scene, point):
    uv = world_to_camera_view(scene, scene.camera, point)
    return [round(uv.x * SIZE, 3), round((1 - uv.y) * SIZE, 3)]


def render(scene, rig, actions, out):
    for obj in bpy.data.collections["06 • Review studio"].objects:
        obj.hide_render = True
    setup(scene, "knight", ANCHOR)
    scene.render.use_file_extension = True
    bpy.context.view_layer.update()
    assert projection(scene, Vector((0, 0, 0))) == ANCHOR
    shield = bpy.data.objects[SHIELD]
    prop = set(shield.children_recursive)
    actor = {o for o in scene.objects if o.type in {"MESH", "CURVE"} and not o.hide_render} - prop
    assert actor and prop
    data = {"anchor": ANCHOR, "capture_size": SIZE, "fps": 24, "takes": {}}

    def draw(name, held=True, prop_only=False):
        for obj in actor:
            obj.hide_render = prop_only
        for obj in prop:
            obj.hide_render = not held
        rendered = out / f"{name}.png"
        render_ink(scene, out / "raw.png", rendered, SIZE)
        return rendered.name

    for clip, take in TAKES.items():
        action = actions[take.name]
        select(rig, action)
        release = action.get("prop_release_frame")
        frames = sorted({1, 5, 9, 12, 16, 21, 25, take.last, *take.proof, take.key_frame}
                        | ({release - 1} if release else set()))
        entry = {"label": take.label, "key_frame": take.key_frame, "last": take.last,
                 "proof": take.proof, "control": take.control, "frames": {}}
        for frame in frames:
            scene.frame_set(frame)
            entry["frames"][frame] = draw(f"{clip}-{frame:02}", release is None or frame < release)
        if clip in {"fitted_pull", "safety_distance"}:
            scene.frame_set(take.key_frame)
            entry["unshielded"] = draw(f"{clip}-unshielded", held=False)
        if release:
            scene.frame_set(release)
            anchor = projection(scene, shield.matrix_world.translation)
            entry["release"] = {
                "anchor": anchor, "offset": [round(a-b, 3) for a, b in zip(anchor, ANCHOR)],
                "prop": draw("lend_a_shield-prop", prop_only=True),
            }
        data["takes"][clip] = entry
    (out / "proof.json").write_text(json.dumps(data, indent=2) + "\n")


def run(library, output):
    require_donor()
    before = digest(library)
    actions = load_actions(library)
    scene = bpy.context.scene
    rig = bpy.data.objects[RIG]
    select(rig, bpy.data.actions[GUARD])
    scene.frame_set(8)
    ready = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
    shield = bpy.data.objects[SHIELD]
    assert shield.parent == rig and shield.parent_bone == "shield_mount.L"
    issues = [issue for take in TAKES.values()
              for issue in geometry_check(scene, rig, take, actions[take.name], ready)]
    if issues:
        print("\n".join(issues), flush=True)
    if output:
        output.mkdir(parents=True, exist_ok=True)
        render(scene, rig, actions, output)
    assert digest(DONOR) == DONOR_SHA and digest(library) == before
    assert not issues, f"{len(issues)} fit checks failed"
    print("Passed: action-only library reopen, Ready seams, planted feet and sampled geometry fit.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("library", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    run(args.library.resolve(), args.output.resolve() if args.output else None)
