"""Reopen, sample and optionally render the saved Wizard without modifying the file."""

import argparse
import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector


PREFIX = "Wizard | "
SIDES = ("R", "L")
VIEWS = (
    ("rest", "Neutral T", 1, "Camera_Neutral_Front"),
    ("ready", "Ready", 1, "Camera_Tactical_3Q"),
    ("blast", "Blast", 14, "Camera_Tactical_3Q"),
    ("tug", "Pull", 13, "Camera_Tactical_3Q"),
    ("slip", "Pull", 19, "Camera_Tactical_3Q"),
    ("seated", "Pull", 24, "Camera_Tactical_3Q"),
)


def select_action(scene, rig, name, frame):
    rig.animation_data.action = bpy.data.actions[PREFIX + name]
    scene.frame_set(frame)


def actor_vertices(actors):
    dg = bpy.context.evaluated_depsgraph_get()
    for obj in actors:
        if obj.type not in {"MESH", "CURVE"}:
            continue
        ev = obj.evaluated_get(dg)
        # Legacy Curve bounds can be an unevaluated ±1 m cube after a background reopen.
        geom = ev.to_mesh() if obj.type == "CURVE" else ev.data
        try:
            yield from (ev.matrix_world @ v.co for v in geom.vertices)
        finally:
            if obj.type == "CURVE":
                ev.to_mesh_clear()


def matrix_error(a, b):
    return max(abs(a[r][c] - b[r][c]) for c in range(4) for r in range(4))


def sole_low(side):
    obj = bpy.data.objects["Ground sole " + side]
    ev = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return min((ev.matrix_world @ v.co).z for v in ev.data.vertices)


def points_matching(actors, prefix):
    dg = bpy.context.evaluated_depsgraph_get()
    for obj in actors:
        if obj.type == "MESH" and obj.name.startswith(prefix):
            ev = obj.evaluated_get(dg)
            yield from (ev.matrix_world @ v.co for v in ev.data.vertices)


def chest_distance(bones, side):
    chest = bones["chest"]
    chest_surface = chest.matrix @ chest.bone.matrix_local.inverted() @ Vector((0, -.1, 1.32))
    return (bones["hand." + side].tail - chest_surface).length


def check(scene, rig, strict):
    assert bpy.data.is_saved
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert scene.camera.name == "Camera_Tactical_3Q" and scene.camera.data.type == "ORTHO"
    assert math.isclose(scene.camera.data.ortho_scale, 2.47, abs_tol=.00001)
    assert max(abs(a-b) for a,b in zip(scene.camera.rotation_euler, (1.150829196, 0, -.435386419))) < .00001
    assert scene.render.fps == 24 and (scene.frame_start,scene.frame_end,scene.frame_current) == (1,40,1)
    assert not bpy.data.libraries
    assert not any(im.source in {"FILE","SEQUENCE","MOVIE","TILED"} and not im.packed_files
                   for im in bpy.data.images)
    assert rig.animation_data.action.name == PREFIX + "Blast"
    assert not rig.animation_data.nla_tracks
    assert all(bpy.data.actions[PREFIX + a].use_fake_user for a in ("Neutral T","Ready","Blast","Pull"))
    assert all(bpy.data.actions[PREFIX + a].slots for a in ("Neutral T","Ready","Blast","Pull"))
    for name, beats in (
        ("Blast", {"Lead foot plants":11, "Blast | palm out":14, "Ready restored":34}),
        ("Pull", {"Tug | both feet grounded":13, "Both soles slip":19, "Seat lands":24, "End | stay down":40}),
    ):
        markers = bpy.data.actions[PREFIX+name].pose_markers
        assert all(markers[beat].frame == frame for beat,frame in beats.items())
    ledger = bpy.data.objects["Ledger_R_Detachable"]
    assert (ledger.parent, ledger.parent_type, ledger.parent_bone) == (rig, "BONE", "ledger_mount")
    assert rig.data.bones["ledger_mount"].parent.name == "pelvis" and len(ledger.children) >= 15
    actors = [o for o in scene.objects if not any(c.name.startswith("07") for c in o.users_collection)]
    bones = rig.pose.bones
    select_action(scene, rig, "Neutral T", 1)
    assert all(matrix_error(p.matrix, p.bone.matrix_local) < .00001 for p in bones)
    for side, sign in (("R",-1),("L",1)):
        for prefix in ("upper_arm.","forearm.","hand."):
            arm = bones[prefix+side]
            assert (arm.tail-arm.head).normalized().dot(Vector((sign,0,0))) > .9999
    rest = list(actor_vertices(actors))
    dim = tuple(max(p[i] for p in rest) - min(p[i] for p in rest) for i in range(3))
    assert 1.95 < dim[2] < 2.20, dim
    print("Neutral character box including the hat and mounted book, m:", tuple(round(d, 3) for d in dim))
    print("Bones:", len(bones), "editable mesh/curve objects:", sum(o.type in {"MESH","CURVE"} for o in actors),
          "ledger objects:", len(ledger.children))

    select_action(scene, rig, "Ready", 1)
    ready = {p.name:p.matrix.copy() for p in bones}
    foot0 = {s:bones["foot."+s].head.copy() for s in SIDES}
    mount_offset = bones["ledger_mount"].matrix.inverted() @ ledger.matrix_world
    heights = []
    mount_error = 0.
    blast_plant_error = 0.
    pull_plant_error = 0.
    reach = {}
    seat = {}
    clearance = {}
    for move in ("Ready","Blast","Pull"):
        select_action(scene, rig, move, 1)
        action = rig.animation_data.action
        assert action.pose_markers and action.pose_markers[0].frame == 1
        end = int(action.frame_end)
        assert all(matrix_error(p.matrix, ready[p.name]) < .0001 for p in bones)
        left_plant = None
        for frame in range(1, end + 1):
            scene.frame_set(frame)
            feet = {s:bones["foot."+s].head.copy() for s in SIDES}
            levels = {s:sole_low(s) for s in SIDES}
            heights.extend(levels.values())
            mount_error = max(mount_error, matrix_error(ledger.matrix_world,
                                                       bones["ledger_mount"].matrix @ mount_offset))
            reach[(move,frame)] = [chest_distance(bones,s) for s in SIDES]
            if move == "Blast":
                if frame == 11:
                    left_plant = feet["L"].copy()
                if 11 <= frame <= 24:
                    blast_plant_error = max(blast_plant_error, (feet["L"]-left_plant).length)
                blast_plant_error = max(blast_plant_error, (feet["R"]-foot0["R"]).length)
                if frame == 14:
                    hand = bones["hand.L"]
                    palm = (hand.matrix @ hand.bone.matrix_local.inverted()).to_3x3() @ Vector((0,-1,0))
                    assert palm.normalized().dot(Vector((0,-1,0))) > .65, palm
                    assert all(abs(c-1) < .001 for c in bones["index.01.L"].rotation_quaternion[:1])
            elif move == "Pull":
                if frame <= 13:
                    pull_plant_error = max(pull_plant_error, *((feet[s]-foot0[s]).length for s in SIDES))
                seat[frame] = (bones["pelvis"].head.copy(), feet, levels)
                if frame >= 14:
                    for prefix in ("Coat, ", "Ledger •", "Pelvis •"):
                        z = min(p.z for p in points_matching(actors,prefix))
                        old_z, _ = clearance.get(prefix,(math.inf,0))
                        if z < old_z:
                            clearance[prefix]=(z,frame)
        if move in ("Ready", "Blast"):
            assert all(matrix_error(p.matrix,ready[p.name]) < .0001 for p in bones)

    print("Blast plant / Pull pre-slip foot drift, mm:", tuple(round(1000*x,4)
          for x in (blast_plant_error,pull_plant_error)))
    print("Minimum sole z, mm:", round(min(heights)*1000, 2))
    print("Maximum book mount matrix error, mm-equivalent:", round(mount_error*1000,4))
    print("Blast left wrist/palm from torso, m:", [round(reach[("Blast",f)][1],3) for f in (1,14,40)])
    print("Pull palm reach then tug, m:", [[round(x,3) for x in reach[("Pull",f)]] for f in (8,13)])
    print("Pull slip foot positions and pose heights, m:",
          [(f,round(seat[f][0].z,3),[round(seat[f][1][s].y,3) for s in SIDES],
            [round(seat[f][2][s],3) for s in SIDES]) for f in (13,16,19,24,40)])
    print("Minimum sampled ground clearance (m, frame):", clearance)
    assert blast_plant_error < .002 and pull_plant_error < .002
    assert mount_error < .0001 and min(heights) > -.001
    assert reach[("Blast",14)][1] > .54
    assert all(a-b > .15 and b < .39 for a,b in zip(reach[("Pull",8)],reach[("Pull",13)]))
    assert all(seat[19][1][s].y - seat[13][1][s].y < -.32 and seat[19][2][s] > .075 for s in SIDES)
    assert .125 < seat[24][0].z < .19 and .125 < seat[40][0].z < .19
    assert abs(seat[24][0].y - seat[40][0].y) < .01
    if strict:
        assert all(z > -.013 for z,_ in clearance.values()), clearance
    for label, action, frame, camera_name in VIEWS:
        select_action(scene, rig, action, frame)
        cam = bpy.data.objects[camera_name]
        camera_projection = cam.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),
            x=scene.render.resolution_x, y=scene.render.resolution_y) @ cam.matrix_world.inverted()
        ndc = [camera_projection @ p for p in actor_vertices(actors)]
        limits = tuple(c*.5+.5 for c in (min(p.x for p in ndc), max(p.x for p in ndc),
                                        min(p.y for p in ndc), max(p.y for p in ndc)))
        print(label, "image occupancy:", tuple(round(d,3) for d in limits))
        if strict:
            assert .015 < limits[0] < limits[1] < .985 and .015 < limits[2] < limits[3] < .985, (label, limits)

    # Actual detach behavior, in memory only: the whole book stays put while the rig moves.
    select_action(scene,rig,"Pull",13)
    mounted = ledger.matrix_world.copy()
    first_cover = ledger.children[0]
    cover_pose = first_cover.matrix_world.copy()
    ledger.parent = None
    ledger.matrix_world = mounted
    scene.frame_set(24)
    assert matrix_error(ledger.matrix_world,mounted) < .00001
    assert matrix_error(first_cover.matrix_world,cover_pose) < .00001
    ledger.parent,ledger.parent_type,ledger.parent_bone = rig,"BONE","ledger_mount"
    bpy.context.view_layer.update()
    ledger.matrix_world = bones["ledger_mount"].matrix @ mount_offset
    bpy.context.view_layer.update()


def render(scene, rig, output, quick, motion):
    output.mkdir(parents=True,exist_ok=True)
    dims = (324,348) if quick else (432,464)
    scene.cycles.samples = 8 if quick else 20
    scene.render.resolution_x, scene.render.resolution_y = dims
    for title, action, frame, camera in VIEWS:
        select_action(scene, rig, action, frame)
        scene.camera = bpy.data.objects[camera]
        scene.render.filepath = str(output / (title + ".png"))
        bpy.ops.render.render(write_still=True)
    if motion:
        scene.camera = bpy.data.objects["Camera_Tactical_3Q"]
        scene.cycles.samples = 8
        scene.render.resolution_x, scene.render.resolution_y = (288, 310)
        for name in ("Blast","Pull"):
            folder = output / name.lower()
            folder.mkdir(exist_ok=True)
            for i,f in enumerate(range(1,40,2)):
                select_action(scene,rig,name,f)
                scene.render.filepath = str(folder / f"{i:03}.png")
                bpy.ops.render.render(write_still=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--render-only", action="store_true")
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--motion", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    scene = bpy.context.scene
    rig = bpy.data.objects["Wizard_Rig"]
    if not args.render_only:
        check(scene,rig,strict=True)
    if not args.check_only:
        if args.output is None:
            parser.error("supply a review render output directory")
        render(scene,rig,args.output.resolve(),args.quick,args.motion)


if __name__ == "__main__":
    main()
