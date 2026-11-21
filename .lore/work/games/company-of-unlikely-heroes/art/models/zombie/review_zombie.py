"""Reopen and check the editable Zombie, or render review views. Never saves it."""

import argparse
import sys
from pathlib import Path

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector
from mathutils.bvhtree import BVHTree


REST, READY, HELLO, FLOWER = "Neutral T", "Ready", "Say Hello", "Offer Flower"
ENDS = {REST: 1, READY: 25, HELLO: 45, FLOWER: 57}
RELEASE, FLIGHT_PROOF, LAST_CLEAR = 22, 26, 32
PREFIX = "Zombie | "
TACTICAL = "Camera_Tactical_3Q"
STILLS = (
    ("neutral", REST, 1, "Camera_Neutral_Front"),
    ("ready", READY, 1, TACTICAL),
    ("hello", HELLO, 19, TACTICAL),
    ("windup", FLOWER, 14, TACTICAL),
    ("release", FLOWER, RELEASE, TACTICAL),
    ("flight", FLOWER, FLIGHT_PROOF, TACTICAL),
    ("follow", FLOWER, LAST_CLEAR, TACTICAL),
    ("hello-side", HELLO, 19, "Camera_Working_Side"),
    ("windup-side", FLOWER, 14, "Camera_Working_Side"),
    ("release-side", FLOWER, RELEASE, "Camera_Working_Side"),
    ("rear", REST, 1, "Camera_Working_Rear"),
    ("face", HELLO, 19, "Camera_Portrait"),
    ("grip", FLOWER, 14, "Camera_Throw_Detail"),
    ("empty-hand", FLOWER, FLIGHT_PROOF, "Camera_Throw_Detail"),
)
OBJ = bpy.data.objects


def pose(scene, rig, action, frame):
    rig.animation_data.action = bpy.data.actions[PREFIX + action]
    scene.frame_set(int(frame), subframe=frame % 1)


def delta(a, b):
    return max(abs(x-y) for row_a,row_b in zip(a,b) for x,y in zip(row_a,row_b))


def as_mesh(obj, graph, face_subset=None):
    evaluated = obj.evaluated_get(graph)
    mesh = evaluated.to_mesh()
    matrix = evaluated.matrix_world
    vertices = [matrix @ v.co for v in mesh.vertices]
    polygons = [tuple(p.vertices) for p in mesh.polygons]
    subset = face_subset(mesh) if face_subset else None
    evaluated.to_mesh_clear()
    assert vertices and polygons, obj.name
    return (vertices, polygons, subset) if face_subset else (vertices, polygons)


def apron_front_faces(mesh):
    """Find the loose front, excluding the hem edge, side wraps and waistband."""
    coords = mesh.attributes["bind_pigment"].data
    result = set()
    for face in mesh.polygons:
        xyz = sum((coords[i].vector for i in face.vertices),Vector()) / len(face.vertices)
        if abs(xyz.x)<.165 and xyz.y<-.120 and .39<xyz.z<.823:
            result.add(face.index)
    assert result
    return result


def measure(scene, graph, names):
    vertices = (co for name in names for co in as_mesh(OBJ[name],graph)[0])
    low, high = [float("inf")]*3, [-float("inf")]*3
    projection = [float("inf"), float("inf"), -float("inf"), -float("inf")]
    # An orthographic projection is affine. Project using the origin and basis once.
    def point(v):
        return world_to_camera_view(scene, scene.camera, Vector(v))
    origin = point((0,0,0))
    axes = [point(v) - origin for v in ((1,0,0),(0,1,0),(0,0,1))]
    for v in vertices:
        for i,x in enumerate(v):
            low[i],high[i] = min(low[i],x),max(high[i],x)
        u,w = [origin[i] + sum(axes[j][i]*v[j] for j in range(3)) for i in range(2)]
        projection = [min(projection[0],u),min(projection[1],w),
                      max(projection[2],u),max(projection[3],w)]
    return low,high,projection


def image_box(scene, coords):
    projected=[world_to_camera_view(scene,scene.camera,p) for p in coords]
    return [min(p.x for p in projected),min(p.y for p in projected),
            max(p.x for p in projected),max(p.y for p in projected)]


def verify_scene(scene, rig, graph):
    actions = bpy.data.actions
    assert rig.type == "ARMATURE" and rig.data.pose_position=="POSE"
    assert not (bpy.data.libraries or bpy.data.images or rig.animation_data.nla_tracks)
    assert scene.unit_settings.system=="METRIC" and scene.unit_settings.scale_length==1.
    assert scene.render.fps==24 and scene.frame_current==1 and scene.frame_end==ENDS[READY]
    assert rig.animation_data.action.name==PREFIX+READY
    assert scene.camera.name==TACTICAL and scene.camera.data.type=="ORTHO"
    assert abs(scene.camera.data.ortho_scale-2.47)<1e-5
    assert max(abs(a-b) for a,b in zip(scene.camera.rotation_euler,(1.1508292,0,-.4353864)))<1e-5
    assert set(actions.keys())=={PREFIX+title for title in ENDS}
    for title,end in ENDS.items():
        action=actions[PREFIX+title]
        assert action.use_fake_user and action.frame_range[:]==(1.,float(end))

    grip = OBJ["Daisy & fieldstone"]
    assert grip.parent==rig and grip.parent_type=="BONE" and grip.parent_bone=="gift_socket.R"
    assert len(grip.constraints)==1 and grip.constraints[0].target==rig
    assert grip.constraints[0].subtarget=="gift_flight" and grip.constraints[0].influence==0.
    throw = actions[PREFIX + FLOWER]
    assert throw.pose_markers["Gift Release"].frame==throw["Release frame"]==RELEASE
    assert throw["Release bone"]=="gift_socket.R"
    prop = tuple(obj.name for obj in grip.children)
    assert len(prop)==106 and all(name.startswith(("Daisy |","Gift |","Stone |")) for name in prop)
    assert rig.pose.bones["gift_socket.R"].parent==rig.pose.bones["hand.R"]
    body = tuple(o.name for o in rig.children if o!=grip)
    assert len(body)>370
    for name in body:
        o=OBJ[name]
        assert len(o.data.materials)>0, name
        if o.parent_type=="BONE":
            assert o.parent_bone in rig.pose.bones
        else:
            mod = o.modifiers[0]
            assert mod.type=="ARMATURE" and mod.object==rig and o.vertex_groups and o.type=="MESH"
            assert all(abs(sum(g.weight for g in v.groups)-1)<1e-4 for v in o.data.vertices), name
    for name in ("Split cheek | dark irregular interior", "Clouded eye | almond cornea",
                 "Head & nose | sculpt"):
        assert OBJ[name].parent_bone=="head"
    for name in ("Head & nose | sculpt", "Offering arm & open hand | sculpt",
                 "Resting arm & hand | sculpt", "Gift | worn slate stone"):
        bm=bmesh.new()
        try:
            bm.from_mesh(OBJ[name].data)
            assert all(e.is_manifold for e in bm.edges) and all(v.link_edges for v in bm.verts), name
            assert bm.calc_volume(signed=True)>0, name
        finally:
            bm.free()
    for side in "LR":
        assert OBJ[f"{side} boot sole"].parent_bone==f"foot.{side}"
        for a,b in (("upper_arm","forearm"),("forearm","hand"),("thigh","shin"),("shin","foot")):
            p,c=[rig.pose.bones[f"{n}.{side}"] for n in (a,b)]
            assert c.parent==p and c.bone.use_connect
    pose(scene,rig,REST,1)
    for bone in rig.pose.bones:
        assert delta(bone.matrix,bone.bone.matrix_local)<1e-5, bone.name
        if bone.name.startswith(("upper_arm","forearm","hand")):
            direction = Vector((1 if bone.name.endswith(".L") else -1,0,0))
            assert bone.vector.normalized().dot(direction)>.99999
    scene.camera=OBJ["Camera_Neutral_Front"]
    lo,hi,frame=measure(scene,graph,body)
    size=[round(b-a,3) for a,b in zip(lo,hi)]
    assert -.001<lo[2]<.002 and 1.75<hi[2]<1.95 and 1.55<size[0]<1.96
    assert min(frame[:2])>.02 and max(frame[2:])<.98
    pose(scene,rig,READY,1)
    lo2,hi2,_=measure(scene,graph,body)
    print(f"Rest: {len(rig.pose.bones)} bones, {len(body)} body pieces, {len(prop)} grouped prop pieces; "
          f"bounds {size} m; ready height {hi2[2]-lo2[2]:.3f} m.",flush=True)
    return body,prop


def verify_timing(scene, rig, graph, diagnostics):
    grip = OBJ["Daisy & fieldstone"]
    stone = OBJ["Gift | worn slate stone"]
    bones = rig.pose.bones
    foot_names = ("foot.L","foot.R")
    pose(scene,rig,READY,1)
    initial = {b.name:b.matrix.copy() for b in bones}
    prop_relative = {o.name:grip.matrix_world.inverted() @ o.matrix_world for o in grip.children}
    socket_to_grip = bones["gift_socket.R"].matrix.inverted() @ grip.matrix_world
    assert all(abs(stone.matrix_world.translation[i]-grip.matrix_world.translation[i])<.005 for i in range(3))
    contact_height = [min(v.z for v in as_mesh(OBJ[f"{side} boot sole"],graph)[0]) for side in "LR"]
    endpoint_delta = foot_drift = grip_drift = scale_drift = 0.
    support = {side:[] for side in "LR"}
    assert len(bones)==33
    for title in (READY,HELLO,FLOWER):
        for half in range(2,ENDS[title]*2+1):
            frame=half/2
            pose(scene,rig,title,frame)
            planted = foot_names if title!=FLOWER else ("foot.R",)
            foot_drift=max(foot_drift,*(delta(initial[n],bones[n].matrix) for n in planted))
            held = title!=FLOWER or frame<RELEASE
            assert (grip.constraints[0].influence<.0001) == held
            if held:
                grip_drift=max(grip_drift,delta(socket_to_grip,bones["gift_socket.R"].matrix.inverted()@grip.matrix_world))
            scale_drift=max(scale_drift,*(abs(x-1) for b in bones for x in b.scale))
            if frame==1 or (title!=FLOWER and frame==ENDS[title]):
                endpoint_delta=max(endpoint_delta,*(delta(initial[b.name],b.matrix)
                                                    for b in bones if b.name!="gift_flight"))
            if frame in (1,ENDS[title]) or (title==FLOWER and frame in (RELEASE,FLIGHT_PROOF)):
                assert all(delta(m,grip.matrix_world.inverted()@OBJ[n].matrix_world)<1e-5
                           for n,m in prop_relative.items())
            if title==FLOWER:
                for side in "LR":
                    support[side].append(min(v.z for v in as_mesh(OBJ[f"{side} boot sole"],graph)[0]))
    print("Foot height above Z=0 (mm):", [round(h*1000,3) for h in contact_height],
          f"; max foot matrix drift {foot_drift:.6g}; max prop socket drift {grip_drift:.6g}; "
          f"endpoint delta {endpoint_delta:.6g}; scale drift {scale_drift:.6g}.",flush=True)
    if not diagnostics:
        assert max(foot_drift,grip_drift,scale_drift,endpoint_delta)<.0003
        assert all(-.001<h<.003 for h in contact_height)
    print("Throw sole Z ranges (mm), including the rocking far boot:",
          {side:[round(min(v)*1000,2),round(max(v)*1000,2)] for side,v in support.items()},flush=True)
    if not diagnostics:
        assert all(-.003<min(v)<=max(v)<.003 for v in support.values())

    pose(scene,rig,HELLO,19)
    lean = initial["head"].translation.y - bones["head"].head.y
    hello_lead = bones["hand.L"].head.y - bones["head"].head.y
    print(f"Hello head advance {lean:.3f} m, head lead over greeting wrist {hello_lead:.3f} m.",flush=True)
    if not diagnostics:
        assert lean>.24 and hello_lead>.055


def verify_throw(scene, rig, graph, prop, diagnostics):
    """Check the contact handoff, continuous outbound flight and tactical proof."""
    grip=OBJ["Daisy & fieldstone"]
    bones=rig.pose.bones
    pose(scene,rig,FLOWER,14)
    wind=bones["hand.R"].head.copy()
    wind_hips=bones["pelvis"].head.copy()
    pose(scene,rig,FLOWER,RELEASE-1)
    held_relative=bones["gift_socket.R"].matrix.inverted()@grip.matrix_world
    pose(scene,rig,FLOWER,RELEASE)
    start=grip.matrix_world.copy()
    wrist=bones["hand.R"].head.copy()
    release_shift=(bones["gift_socket.R"].matrix@held_relative).translation-start.translation
    throw_shift=(bones["pelvis"].head-wind_hips).length
    last=start.translation.copy()
    apex=last.z
    gaps=[]
    for frame in range(RELEASE+1,ENDS[FLOWER]+1):
        pose(scene,rig,FLOWER,frame)
        pos=grip.matrix_world.translation.copy()
        if not diagnostics:
            assert pos.x<last.x and pos.y<last.y and (pos-last).length<.29, frame
        last=pos
        apex=max(apex,pos.z)
        if frame>=FLIGHT_PROOF:
            gaps.append((pos-bones["hand.R"].head).length)
    assert rig["gift_airborne"]==1. and min(gaps)>.50
    pose(scene,rig,READY,1)
    assert rig["gift_airborne"]==0. and grip.constraints[0].influence==0.

    pose(scene,rig,FLOWER,FLIGHT_PROOF)
    palm = bones["hand.R"].matrix.to_3x3().col[2].normalized()
    scene.camera=native_camera(scene)
    scene.render.resolution_x,scene.render.resolution_y=65,54
    cam_vector=(scene.camera.location-bones["hand.R"].head).normalized()
    palm_facing=palm.dot(cam_vector)
    hand_mesh=OBJ["Offering arm & open hand | sculpt"]
    groups={g.index for g in hand_mesh.vertex_groups if g.name!="forearm.R"}
    visible_hand=as_mesh(hand_mesh,graph)[0]
    hand_image=image_box(scene,(visible_hand[v.index] for v in hand_mesh.data.vertices
                                if sum(w.weight for w in v.groups if w.group in groups)>.7))
    _,_,prop_image=measure(scene,graph,prop)
    # A positive gap on either image axis guarantees the two silhouettes are apart.
    gap_px=max(65*max(prop_image[0]-hand_image[2],hand_image[0]-prop_image[2]),
               54*max(prop_image[1]-hand_image[3],hand_image[1]-prop_image[3]))
    print(f"Windup-to-release wrist travel {(wrist-wind).length:.3f} m; hip transfer {throw_shift:.3f} m; "
          f"release continuity {release_shift.length*1000:.2f} mm; arc rises {apex-start.translation.z:.3f} m. "
          f"F{FLIGHT_PROOF} palm camera facing {palm_facing:.2f}, hand-to-prop silhouette gap ≥{gap_px:.1f} px.",flush=True)
    if not diagnostics:
        assert (wrist-wind).length>.48 and throw_shift>.12 and release_shift.length<.0003
        assert .19<apex-start.translation.z<.40 and gap_px>3.5 and palm_facing>.55


def verify_detach(scene, rig):
    """Exercise clearing the prop parent with Keep Transform without saving."""
    pose(scene,rig,FLOWER,21)
    root=OBJ["Daisy & fieldstone"]
    world=root.matrix_world.copy()
    base=root.matrix_basis.copy()
    inverse=root.matrix_parent_inverse.copy()
    parts=[OBJ[name] for name in ("Gift | worn slate stone","Daisy | bent stem","Gift | knot")]
    held=[p.matrix_world.copy() for p in parts]
    flight=root.constraints[0]
    flight.mute=True
    root.parent=None
    root.matrix_world=world
    pose(scene,rig,FLOWER,27)
    assert all(delta(part.matrix_world,m)<1e-5 for part,m in zip(parts,held))
    root.parent=rig
    root.parent_type="BONE"
    root.parent_bone="gift_socket.R"
    root.matrix_parent_inverse=inverse
    root.matrix_basis=base
    flight.mute=False
    pose(scene,rig,FLOWER,21)
    assert all(delta(part.matrix_world,m)<1e-5 for part,m in zip(parts,held))
    print("Prop detaches as one unchanged assembly and reseats on its grip socket.",flush=True)


def check_clearances(scene, rig, graph, body, prop, diagnostics):
    shirt = "Shirt body | upright bind"
    right_arm = "Offering arm & open hand | sculpt"
    left_arm = "Resting arm & hand | sculpt"
    sleeves = ("Offering arm | gathered sleeve", "Resting arm | rolled linen sleeve")
    stone = "Gift | worn slate stone"
    head = "Head & nose | sculpt"
    apron = "Apron | gathered rag-hem wrap"
    near = (shirt, head, apron, "Trowel | curved blade")
    pairs = [(arm,target) for arm in (right_arm,left_arm) for target in near]
    pairs.extend((name, target) for name in (stone,"Daisy | serrated leaf 1","Daisy | serrated leaf 2",
                                           "Daisy | floret cushion","Daisy | bent stem")
                 for target in (left_arm,right_arm,*near)
                 if (name,target)!=(stone,right_arm))  # Deliberate stone/palm contact is checked below.
    overlaps = {}
    wraps = {"L":0,"R":0}
    open_seams = []
    palm_points = []
    # Dense hair and tiny thread details are judged in the images, not by proxy surfaces.
    for title in (REST,READY,HELLO,FLOWER):
        for frame in range(1, ENDS[title]+1):
            if title==READY and frame not in (1,ENDS[READY]):
                continue
            pose(scene,rig,title,frame)
            v,p,front_apron=as_mesh(OBJ[apron],graph,apron_front_faces)
            cache={apron:(v,BVHTree.FromPolygons(v,p))}
            def surface(n):
                if n not in cache:
                    vertices,faces=as_mesh(OBJ[n],graph)
                    cache[n]=vertices,BVHTree.FromPolygons(vertices,faces)
                return cache[n]

            for a,b in pairs:
                if surface(a)[1].overlap(surface(b)[1]):
                    overlaps.setdefault((a,b),[]).append((title,frame))
            for sleeve in sleeves:
                if not surface(sleeve)[1].overlap(surface(shirt)[1]):
                    open_seams.append((sleeve,title,frame))
            for side in "LR":
                leg = f"{side} trouser leg"
                hits = surface(apron)[1].overlap(surface(leg)[1])
                if any(face in front_apron for face,_ in hits):
                    overlaps.setdefault(("loose front apron",leg),[]).append((title,frame))
                elif hits:
                    wraps[side] += 1
            if title!=REST and (title!=FLOWER or frame<=RELEASE):
                points,_ = surface(stone)
                palm_points.append(min(surface(right_arm)[1].find_nearest(v)[3] for v in points))
            if title==FLOWER and frame>=RELEASE+2 and surface(stone)[1].overlap(surface(right_arm)[1]):
                overlaps.setdefault((stone,right_arm),[]).append((title,frame))
    print("Targeted significant surface overlaps (pair, count, first, last):",
          [(pair,len(hits),hits[0],hits[-1]) for pair,hits in overlaps.items()],flush=True)
    print(f"Stone-to-offering-hand closest sampled point: {min(palm_points)*1000:.2f}"
          f"–{max(palm_points)*1000:.2f} mm across whole-frame checks.",flush=True)
    print("Apron overlap away from the loose front (sample counts by side):", wraps,flush=True)
    print("Unseated shirt/shoulder seams:",open_seams,flush=True)
    if not diagnostics:
        assert not overlaps and not open_seams
        assert max(palm_points)<.008

    permitted = [float("inf"),float("inf"),-float("inf"),-float("inf")]
    scene.camera=native_camera(scene)
    scene.render.resolution_x,scene.render.resolution_y=65,54
    for title,frame in ((READY,1),(HELLO,7),(HELLO,19),(HELLO,25),
                        *((FLOWER,i) for i in (10,14,17,*range(RELEASE,LAST_CLEAR+1)))):
        pose(scene,rig,title,frame)
        _,_,projected=measure(scene,graph,body+prop)
        permitted=[fn(a,b) for fn,a,b in zip((min,min,max,max),permitted,projected)]
    print(f"Normalized tactical actor + gift bounds at key beats and frames {RELEASE}–{LAST_CLEAR}:",
          [round(x,4) for x in permitted],flush=True)
    if not diagnostics:
        assert min(permitted[:2])>.015 and max(permitted[2:])<.985


def native_camera(scene):
    """Keep the common 2.47 m horizontal scale; center the shorter native gate."""
    name = "Camera_Tactical_Native (review only)"
    if name in OBJ:
        return OBJ[name]
    source = OBJ[TACTICAL]
    camera = source.copy()
    camera.data = source.data.copy()
    camera.name = name
    scene.collection.objects.link(camera)
    camera.data.shift_y = -.067
    return camera


def throw_detail_camera(scene, rig, frame):
    camera = OBJ[TACTICAL].copy()
    camera.data = OBJ[TACTICAL].data.copy()
    scene.collection.objects.link(camera)
    wrist = rig.pose.bones["hand.R"].head
    palm = rig.pose.bones["hand.R"].tail
    focus = wrist.lerp(palm,.65)
    if frame==14:
        focus=focus.lerp(OBJ["Daisy & fieldstone"].matrix_world.translation,.45)
        camera.data.ortho_scale=.47
    else:
        camera.data.ortho_scale=.35
    camera.location = focus + camera.rotation_euler.to_matrix()@Vector((0,0,8))
    return camera


def render(scene, rig, out, action, frame, camera, width, height, samples):
    pose(scene,rig,action,frame)
    if camera=="Camera_Throw_Detail":
        scene.camera=throw_detail_camera(scene,rig,frame)
    else:
        scene.camera=native_camera(scene) if (width,height)==(65,54) else OBJ[camera]
    for item in OBJ["Daisy & fieldstone"].children:
        item.hide_render = action == REST
    scene.render.resolution_x,scene.render.resolution_y=width,height
    scene.cycles.samples=samples
    scene.render.filepath=str(out)
    assert "FINISHED" in bpy.ops.render.render(write_still=True)
    assert out.is_file() and out.stat().st_size>100


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output",type=Path)
    parser.add_argument("--check-only",action="store_true")
    parser.add_argument("--render-only",action="store_true")
    parser.add_argument("--diagnostics",action="store_true",help="Report, but do not assert motion tolerances")
    parser.add_argument("--quick",action="store_true")
    parser.add_argument("--motion",action="store_true")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    scene,rig=bpy.context.scene,OBJ["Zombie_Rig"]
    if not args.render_only:
        graph=bpy.context.evaluated_depsgraph_get()
        body,prop=verify_scene(scene,rig,graph)
        verify_timing(scene,rig,graph,args.diagnostics)
        verify_throw(scene,rig,graph,prop,args.diagnostics)
        verify_detach(scene,rig)
        check_clearances(scene,rig,graph,body,prop,args.diagnostics)
    if args.check_only:
        return

    out=args.output.resolve()
    out.mkdir(parents=True,exist_ok=True)
    if args.motion:
        for title, slug in ((HELLO,"hello"),(FLOWER,"offer")):
            for frame in range(1,ENDS[title]+1):
                render(scene,rig,out/f"{slug}-{frame:02}.png",
                       title,frame,TACTICAL,300,272,8)
        return
    size=(320,295,8) if args.quick else (640,590,28)
    for name,title,frame,cam in STILLS:
        render(scene,rig,out/f"{name}.png",title,frame,cam,*size)
        if cam==TACTICAL:
            render(scene,rig,out/f"{name}-native.png",title,frame,cam,65,54,24)


if __name__=="__main__":
    main()
