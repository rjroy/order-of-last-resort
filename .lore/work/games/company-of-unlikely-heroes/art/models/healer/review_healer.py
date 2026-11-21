"""Check the saved Healer and optionally render a read-only review set."""

import argparse
import math
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree


PREFIX = "Healer | "
NEUTRAL = "Neutral T"
VIEWS = (
    ("ready", "Ally Heal", 1),
    ("ally", "Ally Heal", 17),
    ("self", "Self Heal", 17),
    ("wind-up", "Adjacent Bonk", 10),
    ("knock", "Adjacent Bonk", 15),
    ("rebound", "Adjacent Bonk", 18),
)
ACTIONS = ("Ally Heal", "Self Heal", "Adjacent Bonk")
SIDES = ("R", "L")
CLEARANCE_PARTS = (
    "Puffed working sleeve", "Face •", "Field coat • open bodice", "Linen wrapped forearm",
    "Saddle satchel", "Waistcoat • shaped", "Hair cap",
)


def set_pose(scene, rig, name, frame):
    rig.animation_data.action = bpy.data.actions[PREFIX + name]
    scene.frame_set(frame)


def position(obj):
    return obj.matrix_world.translation.copy()


def palm_end(rig):
    return rig.pose.bones["hand.L"].tail.copy()


def chest_point(rig):
    chest = rig.pose.bones["chest"]
    return chest.matrix @ chest.bone.matrix_local.inverted() @ Vector((.015,-.142,1.35))


def base_surface(obj):
    return BVHTree.FromPolygons([obj.matrix_world @ v.co for v in obj.data.vertices],
                                [p.vertices[:] for p in obj.data.polygons])


def check_rest(scene, rig, staff):
    set_pose(scene, rig, NEUTRAL, 1)
    for pose in rig.pose.bones:
        rest = pose.bone.matrix_local
        assert (pose.matrix.translation - rest.translation).length < .00001, pose.name
        assert pose.matrix.to_quaternion().rotation_difference(rest.to_quaternion()).angle < .0005, pose.name
    for side, sign in (("R", -1), ("L", 1)):
        for name in ("upper_arm.", "forearm.", "hand."):
            joint = rig.pose.bones[name+side]
            assert (joint.tail-joint.head).normalized().dot(Vector((sign,0,0))) > .9999, joint.name

    actor = [o for o in scene.objects if o.parent == rig and o.type in {"MESH","CURVE"}]
    corners = [o.matrix_world @ Vector(p) for o in actor for p in o.bound_box]
    dimensions = tuple(max(p[i] for p in corners)-min(p[i] for p in corners) for i in range(3))
    assert 1.8 < dimensions[2] < 2.06, dimensions
    print("Neutral actor (without staff), width/depth/height m:", tuple(round(d,3) for d in dimensions))
    print(f"Editable body/clothing objects: {len(actor)}; staff child objects: {len(staff.children)};"
          f" bones: {len(rig.pose.bones)}")


def check_actions(scene, rig, staff):
    marker_names = ("Staff_Grip", "Staff_Butt", "Staff_Knock_Contact")
    markers = {name: bpy.data.objects[name] for name in marker_names}
    feet = {s: bpy.data.objects["Planted sole "+s] for s in SIDES}
    crook = bpy.data.objects["Crook • oak with rounded knocking head"]
    clearance_parts = [obj for obj in scene.objects if obj.name.startswith(CLEARANCE_PARTS)]
    ready = None
    max_drift, max_grip_error = 0., 0.
    min_sole, max_sole = math.inf, -math.inf
    min_butt = math.inf
    max_heal_plant_drift = 0.
    knock = {}
    heal = {}
    for action in ACTIONS:
        set_pose(scene, rig, action, 1)
        local_staff = (rig.matrix_world @ rig.pose.bones["staff_mount.R"].matrix).inverted() @ staff.matrix_world
        if ready is None:
            ready = {p.name: p.matrix.copy() for p in rig.pose.bones}
        foot_starts = {s: rig.pose.bones["foot."+s].matrix.copy() for s in SIDES}
        plant_start = position(markers["Staff_Butt"])
        for frame in range(1,33):
            scene.frame_set(frame)
            if frame in (1, 32):
                for p in rig.pose.bones:
                    assert max(abs(p.matrix[i][j]-ready[p.name][i][j]) for i in range(4) for j in range(4)) < .0001, (action,frame,p.name)
            mounted = rig.matrix_world @ rig.pose.bones["staff_mount.R"].matrix @ local_staff
            max_grip_error = max(max_grip_error,(position(markers["Staff_Grip"])-mounted.translation).length)
            assert mounted.to_quaternion().rotation_difference(staff.matrix_world.to_quaternion()).angle < .001, (action,frame)
            for s in SIDES:
                foot = rig.pose.bones["foot."+s].matrix
                max_drift = max(max_drift,(foot.translation-foot_starts[s].translation).length)
                assert foot.to_quaternion().rotation_difference(foot_starts[s].to_quaternion()).angle < .001, (action,frame,s)
                z = min((feet[s].matrix_world @ v.co).z for v in feet[s].data.vertices)
                min_sole, max_sole = min(min_sole,z), max(max_sole,z)
            min_butt = min(min_butt,position(markers["Staff_Butt"]).z)
            staff_surface = base_surface(crook)
            for obj in clearance_parts:
                assert not staff_surface.overlap(base_surface(obj)), (action,frame,obj.name)
            if action == "Adjacent Bonk":
                knock[frame] = position(markers["Staff_Knock_Contact"])
            else:
                max_heal_plant_drift = max(max_heal_plant_drift,(position(markers["Staff_Butt"])-plant_start).length)
                if frame in (1,17):
                    heal[(action,frame)] = (palm_end(rig),chest_point(rig))

    assert max_drift < .001 and .001 < min_sole <= max_sole < .008
    assert max_grip_error < .001 and min_butt > -.01
    assert max_heal_plant_drift < .001
    print("Maximum foot-anchor displacement mm:", round(1000*max_drift,3),
          "sole height mm:", round(1000*min_sole,2), "to", round(1000*max_sole,2))
    print("Maximum staff grip mount error mm:", round(1000*max_grip_error,3),
          "heal butt drift mm:", round(1000*max_heal_plant_drift,3),
          "lowest butt point anywhere m:", round(min_butt,3))
    print("Staff base surface clear across all 96 integer frames from",
          len(clearance_parts),"selected body/clothing objects")
    for action in ACTIONS[:2]:
        p0,c0 = heal[(action,1)]
        p1,c1 = heal[(action,17)]
        print(action, "palm from chest m:", round((p0-c0).length,3), "to", round((p1-c1).length,3))
    assert (heal[("Ally Heal",17)][0]-heal[("Ally Heal",17)][1]).length > .42
    assert (heal[("Self Heal",17)][0]-heal[("Self Heal",17)][1]).length < .125
    for f in (10,11,13,14,15,16,18):
        xy = (knock[f].x,knock[f].y)
        print(f"Bonk f{f}: crook pad x/y/z m:", tuple(round(v,3) for v in (*xy,knock[f].z)))
    drop = knock[11]-knock[15]
    assert 1.48 < knock[15].z < 1.86 and knock[15].y < -.62 and knock[15].x < -.75
    assert drop.z > .25 and drop.z > 1.15*drop.xy.length
    assert knock[18].z-knock[15].z > .085
    set_pose(scene,rig,"Adjacent Bonk",15)
    assert min((crook.matrix_world @ v.co - knock[15]).length for v in crook.data.vertices) < .001
    assert position(markers["Staff_Butt"]).z > .7
    scene.frame_set(32)
    # In-memory detach probe. Nothing from this script is saved.
    before = staff.matrix_world.copy()
    staff.parent = None
    staff.matrix_world = before
    scene.frame_set(10)
    assert (staff.matrix_world.translation-before.translation).length < .00001
    grip_motion = (position(markers["Staff_Grip"])-before.translation).length
    assert grip_motion < .00001
    staff.parent, staff.parent_type, staff.parent_bone = rig, "BONE", "staff_mount.R"
    scene.frame_set(32)
    staff.matrix_world = before
    bpy.context.view_layer.update()


def check(scene, rig):
    assert scene.camera.name == "Camera_Tactical_3Q"
    assert scene.unit_settings.system == "METRIC" and scene.unit_settings.scale_length == 1
    assert scene.render.fps == 24 and (scene.frame_start,scene.frame_end,scene.frame_current) == (1,32,1)
    assert rig.animation_data.action.name == PREFIX+"Ally Heal"
    assert not bpy.data.libraries and not bpy.data.images
    staff = bpy.data.objects["Staff_R_Detachable"]
    assert staff.parent == rig and staff.parent_type == "BONE" and staff.parent_bone == "staff_mount.R"
    assert rig.data.bones["staff_mount.R"].parent.name == "hand.R"
    assert len(staff.children) >= 16
    assert all(bpy.data.actions[PREFIX+a].use_fake_user for a in (NEUTRAL,*ACTIONS))
    check_rest(scene,rig,staff)
    check_actions(scene,rig,staff)


def add_contact_proxy():
    """Open wire hemisphere drawn at the measured pad, not a scene asset."""
    point = position(bpy.data.objects["Staff_Knock_Contact"])
    data = bpy.data.curves.new("Diagnostic target crown", "CURVE")
    data.dimensions = "3D"
    data.bevel_depth = .003
    radius, depth = .146, .124
    for ring in (math.pi*.51,math.pi*.275):
        line = data.splines.new("POLY")
        line.points.add(47)
        line.use_cyclic_u = True
        for i,p in enumerate(line.points):
            a = i*2*math.pi/48
            p.co = (point.x+radius*math.sin(ring)*math.cos(a),
                    point.y+radius*math.sin(ring)*math.sin(a),
                    point.z-depth+depth*math.cos(ring), 1)
    for a in (0,math.pi*.50,math.pi):
        line = data.splines.new("POLY")
        line.points.add(23)
        for i,p in enumerate(line.points):
            a2 = math.pi*.51*i/23
            p.co = (point.x+radius*math.sin(a2)*math.cos(a),
                    point.y+radius*math.sin(a2)*math.sin(a),
                    point.z-depth+depth*math.cos(a2),1)
    obj = bpy.data.objects.new("Proxy only • approximate helmet height",data)
    bpy.context.scene.collection.objects.link(obj)
    material = bpy.data.materials.new("Diagnostic teal")
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (.039,.32,.29,1)
    shader.inputs["Emission Color"].default_value = (.073,.43,.35,1)
    shader.inputs["Emission Strength"].default_value = .6
    data.materials.append(material)
    obj.visible_shadow = False
    return obj


def render(scene, rig, output, motion, quick, diagnostic):
    output.mkdir(parents=True, exist_ok=True)
    cam = bpy.data.objects["Camera_Tactical_3Q"]
    staff = bpy.data.collections["06 • Staff (detach at root)"]

    def write(out, action, frame, camera=cam, size=(390,420), show_staff=True):
        set_pose(scene,rig,action,frame)
        scene.camera = camera
        staff.hide_render = not show_staff
        scene.render.resolution_x,scene.render.resolution_y = size
        scene.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)

    if quick:
        scene.cycles.samples = 7
    else:
        scene.cycles.samples = 16
    for name,action,frame in VIEWS:
        write(output / (name+".png"),action,frame,size=(310,334) if quick else (450,484))
        if name in {"wind-up","knock","rebound"}:
            crook = bpy.data.objects["Crook • oak with rounded knocking head"]
            framing = [world_to_camera_view(scene,cam,crook.matrix_world @ v.co) for v in crook.data.vertices]
            assert all(.025 < p.x < .975 and .025 < p.y < .975 for p in framing), (name,"crook clipping")
    write(output / "rest.png",NEUTRAL,1,bpy.data.objects["Camera_Neutral_Front"],(465,483),False)
    write(output / "back.png",NEUTRAL,1,bpy.data.objects["Camera_Back_Diagnostic"],(465,483),False)
    if diagnostic:
        set_pose(scene,rig,"Adjacent Bonk",15)
        proxy = add_contact_proxy()
        for name,frame in (("wind-up",10),("knock",15),("rebound",18)):
            write(output / f"proxy-{name}.png","Adjacent Bonk",frame,size=(360,388))
        bpy.data.objects.remove(proxy,do_unlink=True)
    if motion:
        scene.cycles.samples = 7
        for action in ACTIONS:
            seq = output / action.lower().replace(" ","-")
            seq.mkdir(exist_ok=True)
            for ordinal, frame in enumerate(range(1,33)):
                write(seq / f"{ordinal:03d}.png",action,frame,size=(282,304))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output",type=Path,nargs="?")
    parser.add_argument("--check-only",action="store_true")
    parser.add_argument("--render-only",action="store_true")
    parser.add_argument("--quick",action="store_true")
    parser.add_argument("--motion",action="store_true")
    parser.add_argument("--diagnostic",action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    scene = bpy.context.scene
    rig = bpy.data.objects["Healer_Rig"]
    if not args.render_only:
        check(scene,rig)
    if not args.check_only:
        if args.output is None:
            parser.error("an output directory is required for render")
        render(scene,rig,args.output.resolve(),args.motion,args.quick,args.diagnostic)


if __name__ == "__main__":
    main()
