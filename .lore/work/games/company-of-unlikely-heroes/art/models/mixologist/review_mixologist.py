"""Read-only review of the saved Mixologist. Run with Blender in background mode."""
import argparse
import math
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree

PREFIX = "Mixologist | "
HANDOFF, TOSS = "Healing Potion", "Acid Toss"
RIG = bpy.data.objects["Mixologist_Rig"]
SCENE = bpy.context.scene
OBJECTS = bpy.data.objects
B = RIG.pose.bones
OFFER_FRAME = 17
RELEASE_FRAME = 18
SCENE_CAMERA = "Camera_Tactical_3Q"
MOUNTS = (
    ("Hip_Rack_Detachable", "rack"),
    ("Amber_Potion_Detachable", "prop.potion"),
    ("Acid_Flask_Detachable", "prop.acid"),
)


def pose(action, frame=1):
    RIG.animation_data.action = bpy.data.actions[PREFIX + action]
    SCENE.frame_set(math.floor(frame), subframe=frame % 1)
    bpy.context.view_layer.update()


def matrix_error(first, second):
    return max(abs(first[i][j] - second[i][j]) for i in range(4) for j in range(4))


def center(name):
    return OBJECTS[name].matrix_world.translation


def evaluated_vertices(obj, graph):
    eo = obj.evaluated_get(graph)
    mesh = eo.to_mesh()
    try:
        return tuple(eo.matrix_world @ v.co for v in mesh.vertices)
    finally:
        eo.to_mesh_clear()


def verify_structure():
    assert SCENE.camera.name == SCENE_CAMERA
    assert math.isclose(SCENE.camera.data.ortho_scale, 2.47, abs_tol=1e-5)
    assert tuple(round(v, 5) for v in SCENE.camera.rotation_euler) == (1.15083, 0, -.43539)
    assert SCENE.frame_current == 1 and RIG.animation_data.action.name == PREFIX + "Ready"
    assert SCENE.unit_settings.system == "METRIC" and SCENE.unit_settings.scale_length == 1
    assert SCENE.render.fps == 24 and not bpy.data.libraries and not bpy.data.images
    assert tuple(o.name for o in SCENE.objects if o.type == "ARMATURE") == (RIG.name,)
    assert not any("recipient" in o.name.lower() for o in SCENE.objects)
    assert not RIG.animation_data.nla_tracks
    assert {a.name for a in bpy.data.actions} == {PREFIX+s for s in ("Neutral T", "Ready", HANDOFF, TOSS)}
    for obj, mount in MOUNTS:
        o = OBJECTS[obj]
        assert (o.parent, o.parent_type, o.parent_bone) == (RIG, "BONE", mount)
        assert o.children
    pose("Neutral T")
    for bone in B:
        if not bone.name.startswith("prop."):
            assert matrix_error(bone.matrix, bone.bone.matrix_local) < 1e-5, bone.name
    for side, direction in (("R", -1), ("L", 1)):
        for prefix in ("upper", "fore", "hand"):
            b = B[f"{prefix}.{side}"]
            assert (b.tail-b.head).normalized().dot(Vector((direction, 0, 0))) > .9999
    graph = bpy.context.evaluated_depsgraph_get()
    shapes = [o for o in SCENE.objects if o.type in {"MESH", "CURVE"} and
              any(c.name.startswith(("01", "02", "03")) for c in o.users_collection)]
    points = [v for o in shapes for v in evaluated_vertices(o, graph)]
    extent = tuple(max(p[i] for p in points)-min(p[i] for p in points) for i in range(3))
    assert 1.93 < extent[2] < 2.16, extent
    print(f"True T rest, one armature, {len(B)} bones, {len(shapes)} editable actor pieces. Neutral bounds m:", extent)


def verify_endpoints():
    pose("Ready")
    ready = {p.name: p.matrix.copy() for p in B}
    for name, last in ((HANDOFF,36),(TOSS,32)):
        for frame in (1,last):
            pose(name, frame)
            for b in B:
                assert matrix_error(ready[b.name], b.matrix) < 1e-5, (name, frame, b.name)
    print("Both takes match the Ready pose at the start and finish; no NLA.")


def surface(obj, graph):
    evaluated = obj.evaluated_get(graph)
    mesh = evaluated.to_mesh()
    try:
        return BVHTree.FromPolygons(
            [evaluated.matrix_world @ v.co for v in mesh.vertices],
            [tuple(p.vertices) for p in mesh.polygons],
        )
    finally:
        evaluated.to_mesh_clear()


def probe_distance(anchor, group, side):
    graph = bpy.context.evaluated_depsgraph_get()
    return min(surface(OBJECTS[f"Mixologist {part} {side}"], graph).find_nearest(anchor)[3]
               for part in group)


def grip_diagnostics():
    hand_parts = ("palm", "index", "middle", "ring", "little", "thumb")
    acid_offsets = []
    handoff_bases = []
    handoff_necks = []
    for sample in range(12, 33):
        pose(TOSS, sample/2)
        p = center("Acid neck grip point")
        acid_offsets.append(B["hand.L"].matrix.inverted() @ p)
    max_acid_drift = max((x-acid_offsets[0]).length for x in acid_offsets)
    assert max_acid_drift < .00015, max_acid_drift
    for sample in range(14, 48):
        pose(HANDOFF, sample/2)
        handoff_necks.append((B["hand.R"].matrix @ Vector((-.001,.105,-.030)) -
                              center("Potion neck steady point")).length)
        if sample >= 26:
            handoff_bases.append((B["hand.L"].matrix @ Vector((.003,.076,-.016)) -
                                  center("Potion base cradle")).length)
    max_base, max_neck = max(handoff_bases), max(handoff_necks)
    assert max_base < .013 and max_neck < .035, (max_base, max_neck)
    pose(HANDOFF, OFFER_FRAME)
    offer_base = probe_distance(center("Potion base cradle"), hand_parts, "L")
    offer_neck = probe_distance(center("Potion neck steady point"), hand_parts, "R")
    print(f"Max tracked hold offset: base {max_base*1000:.1f} mm, right grip to neck center {max_neck*1000:.1f} mm."
          f"\nOffer landmarks: base {offer_base*1000:.1f} mm from left hand, "
          f"neck center {offer_neck*1000:.1f} mm from right hand.")
    assert offer_base < .015 and offer_neck < .032, (offer_base, offer_neck)
    pose(TOSS, 13)
    load_neck = probe_distance(center("Acid neck grip point"), hand_parts, "L")
    print(f"Loaded acid neck center {load_neck*1000:.1f} mm from hand; "
          f"max held-acid landmark drift {max_acid_drift*1000:.3f} mm.")
    assert load_neck < .033, load_neck
    pose(TOSS, 16)
    at_release = center("Acid neck grip point").copy()
    pose(TOSS, RELEASE_FRAME)
    in_flight = center("Acid neck grip point")
    sep = probe_distance(in_flight, hand_parts, "L")
    assert in_flight.x > at_release.x + .18 and sep > .100, (at_release, in_flight, sep)
    rack_distance = probe_distance(OBJECTS["Hip_Rack_Detachable"].matrix_world @
                                  Vector((-.334,-.183,.904)), hand_parts, "R")
    assert rack_distance < .032, rack_distance
    print(f"Frame {RELEASE_FRAME}: projectile neck {sep:.3f} m from release hand; "
          f"other hand {rack_distance*1000:.1f} mm from bracing landmark.")


def check_detachable_roots():
    for name, _ in MOUNTS:
        action, frame = (HANDOFF, OFFER_FRAME) if name.startswith("Amber") else (TOSS, 13)
        pose(action, frame)
        root = OBJECTS[name]
        mount = root.parent_bone
        parent_inverse = root.matrix_parent_inverse.copy()
        basis = root.matrix_basis.copy()
        probe = root.children[0]
        before = root.matrix_world.copy()
        child_world = probe.matrix_world.copy()
        root.parent = None
        root.matrix_world = before
        pose(action, frame + 3)
        assert matrix_error(root.matrix_world, before) < .0001, name
        assert matrix_error(probe.matrix_world, child_world) < .0001, probe.name
        root.parent, root.parent_type, root.parent_bone = RIG, "BONE", mount
        root.matrix_parent_inverse, root.matrix_basis = parent_inverse, basis
        bpy.context.view_layer.update()
    print("All three detachable assemblies preserve a child’s world transform when unparented in memory.")


def check_release_feet():
    pose(TOSS, RELEASE_FRAME)
    graph = bpy.context.evaluated_depsgraph_get()
    rear = evaluated_vertices(OBJECTS["Boot sole R"], graph)
    front = evaluated_vertices(OBJECTS["Boot sole L"], graph)
    rear_lowest, front_lowest = (min(p.z for p in sole) for sole in (rear, front))
    rear_toe, rear_heel = min(rear, key=lambda p:p.y), max(rear, key=lambda p:p.y)
    heel_rise = rear_heel.z-rear_toe.z
    assert .001 < rear_lowest < .015 and .001 < front_lowest < .015, (rear_lowest, front_lowest)
    assert heel_rise>.05, heel_rise
    print(f"Release sole heights: rear {rear_lowest*1000:.1f} mm, front {front_lowest*1000:.1f} mm. "
          f"Rear heel {heel_rise*1000:.0f} mm above the toe.")


def write_view(out, name, action, frame, camera, size):
    pose(action, frame)
    SCENE.camera = OBJECTS[camera]
    SCENE.render.resolution_x, SCENE.render.resolution_y = size
    SCENE.render.filepath = str(out / (name + ".png"))
    bpy.ops.render.render(write_still=True)


def check_tactical_crops(frame, action, prop):
    pose(action, frame)
    graph = bpy.context.evaluated_depsgraph_get()
    items = [OBJECTS[f"Boot sole {side}"] for side in ("L","R")]
    if prop:
        items.extend(o for o in OBJECTS[prop].children if o.type=="MESH")
    for obj in items:
        for point in evaluated_vertices(obj,graph):
            xy=world_to_camera_view(SCENE,SCENE.camera,point)
            assert .010 < xy.x < .990 and .010 < xy.y < .990, (obj.name, frame, xy)


def main():
    cli = argparse.ArgumentParser()
    cli.add_argument("out", type=Path)
    cli.add_argument("--check-only", action="store_true")
    cli.add_argument("--draft", action="store_true")
    cli.add_argument("--motion", action="store_true", help="Render the two takes at 12 preview fps instead of stills.")
    args = cli.parse_args(sys.argv[sys.argv.index("--")+1:])
    verify_structure()
    verify_endpoints()
    grip_diagnostics()
    check_detachable_roots()
    check_release_feet()
    if args.check_only:
        return
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    if args.motion:
        SCENE.cycles.samples = 12
        for folder, action, last_frame in (("handoff",HANDOFF,36),("toss",TOSS,32)):
            dest=out/folder
            dest.mkdir(exist_ok=True)
            for i,frame in enumerate(range(1,37,2)):
                write_view(dest, f"{i:03}", action, min(frame,last_frame), SCENE_CAMERA, (230, 240))
        return
    size = (340, 360) if args.draft else (480,500)
    SCENE.cycles.samples = 12 if args.draft else 32
    SCENE.render.resolution_x,SCENE.render.resolution_y = size
    for frame,action,prop in ((1,"Ready",None),(OFFER_FRAME,HANDOFF,"Amber_Potion_Detachable"),
                              (RELEASE_FRAME,TOSS,"Acid_Flask_Detachable")):
        check_tactical_crops(frame,action,prop)
    for name, action, frame, cam in (
        ("neutral","Neutral T",1,"Camera_Neutral_Front"),
        ("ready","Ready",1,SCENE_CAMERA),
        ("handoff",HANDOFF,OFFER_FRAME,SCENE_CAMERA),
        ("release",TOSS,RELEASE_FRAME,SCENE_CAMERA),
        ("handoff-detail",HANDOFF,OFFER_FRAME,"Camera_Offer_Detail"),
        ("release-detail",TOSS,RELEASE_FRAME,"Camera_Release_Detail"),
        ("load",TOSS,13,SCENE_CAMERA),
        ("rear","Ready",1,"Camera_Rear_3Q"),
    ):
        write_view(out, name, action, frame, cam, size)


if __name__ == "__main__":
    main()
