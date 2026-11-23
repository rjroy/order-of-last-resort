"""Reopen, validate, and render a saved bandit master. No source writes.

Blender arguments after --: MODE ABSOLUTE_OUTPUT_DIRECTORY
MODE is check, proof (key views), or motion (12 fps frames).
"""
import hashlib
import json
import sys
from pathlib import Path

import bpy
import bmesh
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

MODEL_DIR = Path(__file__).resolve().parent
REPO = next(p for p in MODEL_DIR.parents if (p / "games/company-of-unlikely-heroes/tools/cast/bake_actor.py").is_file())
sys.path.insert(0, str(REPO / "games/company-of-unlikely-heroes/tools/cast"))
from bake_actor import setup as cast_camera

MODE, DEST = sys.argv[sys.argv.index("--") + 1:]
OUT = Path(DEST)
assert OUT.is_absolute()
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = Path(bpy.data.filepath)
SOURCE_SHA = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
SCENE = bpy.context.scene
RIG, = (o for o in SCENE.objects if o.type == "ARMATURE")
ROLE = RIG["Role ID"]
TITLE = RIG.name.removesuffix("_Rig").replace("_", " ")
FEATURE = {"bandit_damage": ("Harder Strike", 17, 12),
           "bandit_guard": ("Brace", 8, 10),
           "bandit_swift": ("Quick Step", 6, 7)}[ROLE]
POSES = {"rest": ("Neutral T", 1), "ready": ("Ready", 1),
         "move": ("Move", {"bandit_damage": 14, "bandit_guard": 5, "bandit_swift": 12}[ROLE]),
         "melee": ("Melee", FEATURE[2]), "feature": FEATURE[:2], "hit": ("Hit", 4),
         "defeat": ("Defeat", 25)}
PIGMENT_OBS = [o for o in SCENE.objects if o.type in {"MESH", "CURVE"}]


def action(name):
    return bpy.data.actions[f"{TITLE} | {name}"]


def pose(name, frame):
    RIG.animation_data.action = action(name)
    start = int(frame)
    SCENE.frame_set(start, subframe=frame - start)
    bpy.context.view_layer.update()


def vertices(objects):
    graph = bpy.context.evaluated_depsgraph_get()
    for ob in objects:
        evaluated = ob.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        try:
            for v in mesh.vertices:
                yield evaluated.matrix_world @ v.co
        finally:
            evaluated.to_mesh_clear()


def bounds(objects):
    minimum, maximum = [float("inf")]*3, [float("-inf")]*3
    for p in vertices(objects):
        for axis in range(3):
            minimum[axis] = min(minimum[axis], p[axis])
            maximum[axis] = max(maximum[axis], p[axis])
    return minimum, maximum


def pose_difference(a, b):
    return max(abs(x-y) for name in a for ra, rb in zip(a[name],b[name]) for x,y in zip(ra,rb))


def snapshot():
    return {bone.name: bone.matrix.copy() for bone in RIG.pose.bones}


def check():
    assert bpy.app.version[:3] == (5,2,2) and not bpy.data.libraries and not bpy.data.images
    assert len(RIG.data.bones) == 24
    assert SCENE.render.fps == 24 and SCENE.unit_settings.system == "METRIC"
    assert SCENE["Concept SHA-256"] == "f71417d10728115de4c5a7d0c7793224e92bc2e2a347edc3469eedd2cbef4843"
    assert set(bpy.data.actions.keys()) == {f"{TITLE} | {name}" for name in
        ("Neutral T", "Ready", "Move", "Melee", FEATURE[0], "Hit", "Defeat")}
    assert len(PIGMENT_OBS) >= 100
    open_meshes = []
    for ob in PIGMENT_OBS:
        assert ob.parent == RIG and ob.data.materials, ob.name
        if ob.parent_type == "BONE":
            assert ob.parent_bone in RIG.data.bones, ob.name
        else:
            assert any(m.type == "ARMATURE" and m.object == RIG for m in ob.modifiers), ob.name
        if ob.type == "MESH":
            topology = bmesh.new()
            topology.from_mesh(ob.data)
            try:
                assert all(f.calc_area()>1e-10 for f in topology.faces), ob.name
                if any(not e.is_manifold for e in topology.edges):
                    assert any(m.type == "SOLIDIFY" for m in ob.modifiers), ob.name
                    assert all(e.is_manifold or e.is_boundary for e in topology.edges), ob.name
                    open_meshes.append(ob.name)
                else:
                    assert topology.calc_volume(signed=True)>0, ob.name
            finally:
                topology.free()
    pose("Neutral T", 1)
    neutral = snapshot()
    assert pose_difference(neutral, {b.name: b.matrix_local for b in RIG.data.bones}) < .00002
    rest = bounds([o for o in PIGMENT_OBS if not o.parent_bone.startswith("grip.")])
    for sign,s in ((-1,"R"),(1,"L")):
        b = RIG.data.bones["hand."+s]
        assert (b.tail_local - b.head_local).normalized().dot(Vector((sign,0,0))) > .999
    pose("Ready", 1)
    ready = snapshot()
    soles = [o for o in PIGMENT_OBS if o.name.startswith("Grouped sole and heel")]
    assert len(soles) == 2
    floor_clearance, grip_spread, count = float("inf"), 0, 0
    feature_right = FEATURE[0] == "Brace"
    for name in ("Ready", "Move", "Melee", FEATURE[0], "Hit", "Defeat"):
        last = round(action(name).frame_range[1])
        assert action(name).frame_range[0] == 1 and last >= 15
        pose(name,1)
        assert pose_difference(snapshot(),ready) < .00002
        for sample in range(2, last*2+1):
            count += 1
            pose(name,sample/2)
            assert (RIG.pose.bones["root"].head).length < .00002
            floor_clearance = min(floor_clearance,bounds(soles)[0][2])
            if ROLE == "bandit_damage":
                right,left = (RIG.pose.bones["grip."+s].matrix for s in ("R","L"))
                axis = right.to_3x3() @ Vector((0,1,0))
                grip_spread=max(grip_spread,(left.translation-(right.translation+.287*axis)).length)
            if feature_right and name == "Brace":
                assert all((RIG.pose.bones[n].head - ready[n].translation).length < .00004 for n in ("foot.R","foot.L"))
        if name != "Defeat":
            assert pose_difference(snapshot(),ready) < .00002, name
        else:
            down = snapshot()
            assert down["head"].translation.z < ready["head"].translation.z - .45
            pose(name,20)
            assert pose_difference(snapshot(),down) < .00002
    assert floor_clearance >= -.0008, floor_clearance
    assert grip_spread < .003, grip_spread
    assert rest[1][2] < 2.30
    pose(*POSES["feature"])
    if ROLE == "bandit_guard":
        assert RIG.pose.bones["grip.R"].head.x - ready["grip.R"].translation.x > .15
    elif ROLE == "bandit_swift":
        posed = snapshot()
        foot_gap = lambda matrices: (matrices["foot.R"].translation - matrices["foot.L"].translation).length
        assert foot_gap(posed) > 1.2*foot_gap(ready)
        assert all(posed["foot."+side].translation.z - ready["foot."+side].translation.z > .08 for side in "RL")
    else:
        assert RIG.pose.bones["pelvis"].head.y < ready["pelvis"].translation.y-.15
    report = {"source_sha256": SOURCE_SHA, "role": ROLE, "blender": bpy.app.version_string,
              "bone_count": len(neutral),"mesh_count": sum(o.type == "MESH" for o in PIGMENT_OBS),
              "curve_count": sum(o.type == "CURVE" for o in PIGMENT_OBS), "metres_rest_bounds": rest,
              "actions": {a.name: list(a.frame_range) for a in bpy.data.actions},
              "tested_half_frame_samples": count, "minimum_sole_clearance_m": floor_clearance,
              "open_source_meshes_with_solidify": open_meshes}
    if ROLE == "bandit_damage":
        report["maximum_second_hand_mount_drift_m"] = grip_spread
    (OUT/"validation.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))


def render(out):
    SCENE.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    assert out.stat().st_size > 500, out


def beauty_setup():
    camera = SCENE.camera
    SCENE.render.engine = "CYCLES"
    SCENE.cycles.device = "CPU"
    SCENE.cycles.samples = 16
    SCENE.cycles.use_denoising = True
    SCENE.render.resolution_x = SCENE.render.resolution_y = 420
    SCENE.render.resolution_percentage = 100
    SCENE.render.film_transparent = True
    SCENE.render.image_settings.color_mode = "RGBA"
    SCENE.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("Soft slate studio")
    world.use_nodes = True
    world.node_tree.nodes.get("Background").inputs[0].default_value = (.32,.30,.35,1)
    world.node_tree.nodes.get("Background").inputs[1].default_value = .34
    SCENE.world = world
    for name,position,power,size,color in (
        ("Warm broad key",(-3.3,-4,5),480,3.2,(1,.88,.73)),
        ("Cool face fill",(3,-2.7,2.8),225,3.0,(.76,.85,1)),
        ("Shoulder bounce",(1,3.4,4),545,2.8,(1,.81,.71))):
        light = bpy.data.lights.new(name,"AREA")
        light.energy,light.shape,light.size,light.color = power,"DISK",size,color
        obj = bpy.data.objects.new(name,light)
        SCENE.collection.objects.link(obj)
        obj.location = position
        obj.rotation_euler = (Vector((0,0,1))-obj.location).to_track_quat("-Z","Y").to_euler()
    camera.data.ortho_scale = 2.73
    camera.location = camera.rotation_euler.to_matrix() @ Vector((.02,.87,6))


def proof():
    beauty_setup()
    for slug,(name,frame) in POSES.items():
        pose(name,frame)
        render(OUT/f"{slug}.png")
    pose("Ready",1)
    SCENE.camera.rotation_euler.z += 2.89
    SCENE.camera.location = SCENE.camera.rotation_euler.to_matrix() @ Vector((0,.87,6))
    render(OUT/"rear.png")
    for o in tuple(SCENE.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o,do_unlink=True)
    cast_camera(SCENE, ROLE, [160,248])
    SCENE.cycles.samples = 8
    bpy.context.view_layer.update()
    uv = world_to_camera_view(SCENE,SCENE.camera,Vector((0,0,0)))
    assert abs(uv.x*320-160) < .001 and abs((1-uv.y)*320-248) < .001, uv
    for slug in ("ready","move","melee","feature"):
        pose(*POSES[slug])
        render(OUT/f"tactical-{slug}.png")


def motion():
    cast_camera(SCENE, ROLE, [160,248])
    SCENE.cycles.samples = 5
    count = 0
    rows = []
    for name in ("Ready","Move","Melee",FEATURE[0],"Hit","Defeat"):
        end = 13 if name=="Ready" else round(action(name).frame_range[1])
        frames = list(range(1,end+1,2))
        if frames[-1] != end:
            frames.append(end)
        if name == "Defeat":
            frames += [end]*4
        index = count
        for frame in frames:
            pose(name,frame)
            render(OUT/f"motion-{count:03d}.png")
            count += 1
        rows.append({"action": name, "first_display_frame": index,"last_display_frame":count-1,
                     "source_frames_24_fps": frames})
    (OUT/"motion-index.json").write_text(json.dumps(rows,indent=2)+"\n")


def draft():
    cast_camera(SCENE,ROLE,[160,248])
    SCENE.cycles.samples = 4
    for slug in ("ready","melee","feature","defeat"):
        pose(*POSES[slug])
        render(OUT/f"{slug}.png")


try:
    {"check":check,"proof":proof,"motion":motion,"draft":draft}[MODE]()
finally:
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == SOURCE_SHA, "The source unexpectedly changed."
