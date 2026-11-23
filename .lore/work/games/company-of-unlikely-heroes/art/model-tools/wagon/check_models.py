"""Test the actual reopened Last Wagon Blender masters, without editing them."""

from math import degrees
from pathlib import Path
import sys
import bmesh
import bpy
from mathutils import Vector


ACTORS = {
    "WagonRaider": {
        "Neutral T":1, "Ready":33, "Intercept":29, "Wagon Strike":32, "Hit":21,"Defeat":37,
    },
    "Wagon": {"Neutral":1, "Ready":25, "Advance":33, "Stall":27, "Destroyed":42},
}


def bone_point(rig,bone,p=(0,0,0)):
    return rig.matrix_world @ rig.pose.bones[bone].matrix @ Vector(p)


def check_clear_geometry(meshes):
    vertices=faces=0
    for obj in meshes:
        assert obj.data.materials and all(not m.is_grease_pencil for m in obj.data.materials)
        vertices+=len(obj.data.vertices)
        faces+=len(obj.data.polygons)
        bm=bmesh.new()
        bm.from_mesh(obj.data)
        try:
            assert all(f.calc_area()>1e-9 for f in bm.faces),obj.name
            if not any(mod.type=="SOLIDIFY" for mod in obj.modifiers):
                assert all(e.is_manifold and e.is_contiguous for e in bm.edges),obj.name
                assert bm.calc_volume(signed=True)>0,obj.name
        finally:
            bm.free()
    print(f"{len(meshes)} mesh objects; {vertices:,} source vertices; {faces:,} source faces")


def bounds(scene, subset=None):
    dg=bpy.context.evaluated_depsgraph_get()
    coordinates=[]
    for obj in scene.objects if subset is None else subset:
        if obj.type not in {"MESH","CURVE"}:
            continue
        ev=obj.evaluated_get(dg)
        mesh=ev.to_mesh()
        if mesh:
            coordinates.extend(ev.matrix_world @ v.co for v in mesh.vertices)
        ev.to_mesh_clear()
    return tuple((min(v[i] for v in coordinates),max(v[i] for v in coordinates)) for i in range(3))


def probe(rig,scene,actor,action,frame):
    rig.animation_data.action=bpy.data.actions[f"{actor} | {action}"]
    scene.frame_set(frame)
    bpy.context.view_layer.update()


def check_raider(rig,scene,actor):
    prop=bpy.data.objects["Wedge_Stave_Detachable"]
    assert prop.parent == rig and prop.parent_bone == "wedge_socket" and len(prop.children) >= 12
    soles=[o for o in scene.objects if o.name.startswith("Flat rawhide outsole")]
    head=[o for o in scene.objects if o.name.startswith("Wedge head")]
    assert len(soles)==2 and len(head)==1
    max_slip=0
    for action,stop in ACTORS[actor].items():
        if action=="Neutral T":
            continue
        for f in range(1,stop+1):
            probe(rig,scene,actor,action,f)
            for side,offset in (("L",-.134),("R",.134)):
                grip=bone_point(rig,"wedge_socket",(0,offset,0))
                palm=bone_point(rig,"hand."+side,(0,.065,0))
                max_slip=max(max_slip,(grip-palm).length)
            assert bone_point(rig,"origin").length<.0001
    assert max_slip<.002,max_slip
    print(f"Fixed two-hand grip: maximum palm-to-stave error {1000*max_slip:.4f} mm on all action frames")
    for action,frame in (("Ready",1),("Intercept",10),("Intercept",14),("Wagon Strike",16),
                         ("Wagon Strike",20),("Defeat",29)):
        probe(rig,scene,actor,action,frame)
        ss=[bounds(scene,[s])[2][0] for s in soles]
        h=bounds(scene,head)[2]
        print(f"{action:>12} F{frame:02}: sole lows {[round(x,4) for x in ss]}, wedge Z {[round(x,4) for x in h]}")
        if (action,frame)==("Intercept",10):
            assert max(ss)>.085 and -.02<min(ss)<.025
        if (action,frame) in (("Ready",1),("Intercept",14)):
            assert max(map(abs,ss))<.025
        if (action,frame)==("Wagon Strike",16):
            assert .10<h[0]<.48 and h[1]<.75, h
    for name in ("Ready","Intercept","Wagon Strike","Hit"):
        probe(rig,scene,actor,name,1)
        poses=[b.matrix.copy() for b in rig.pose.bones]
        probe(rig,scene,actor,name,ACTORS[actor][name])
        assert all(abs(a-b)<.0001 for b1,b2 in zip(poses,rig.pose.bones)
                   for row1,row2 in zip(b1,b2.matrix) for a,b in zip(row1,row2)),name


def check_wagon(rig,scene,actor):
    wheels=[f"wheel.{end}.{side}" for end in ("fore","aft") for side in ("L","R")]
    assert all(k in rig.pose.bones for k in wheels)
    assert sum(o.name.startswith("Shrunk iron tire") for o in scene.objects)==4
    probe(rig,scene,actor,"Ready",1)
    origin=bone_point(rig,"origin")
    baseline={b.name:b.matrix.copy() for b in rig.pose.bones}
    probe(rig,scene,actor,"Advance",33)
    rolled=[degrees(baseline[k].to_quaternion().rotation_difference(
                   rig.pose.bones[k].matrix.to_quaternion()).angle) for k in wheels]
    assert all(abs(a-173)<.01 for a in rolled),rolled
    assert (bone_point(rig,"origin")-origin).length<.0001
    for f in range(1,28):
        probe(rig,scene,actor,"Stall",f)
        for k in wheels:
            assert all(abs(a-b)<.0001 for p,q in zip(baseline[k],rig.pose.bones[k].matrix)
                       for a,b in zip(p,q)),(k,f)
        assert (bone_point(rig,"origin")-origin).length<.0001
        if f==7:
            cargo=rig.pose.bones["barrel"].matrix.translation
            assert (cargo-baseline["barrel"].translation).length>.03
    probe(rig,scene,actor,"Destroyed",42)
    changes={k:(rig.pose.bones[k].matrix.translation-baseline[k].translation).length
             for k in ["wheel.fore.L","wheel.fore.R","side_break","body","sack.full"]}
    assert changes["wheel.fore.L"]>.26 and changes["wheel.fore.R"]<.09
    assert changes["side_break"]>.12 and changes["sack.full"]>.12
    assert (bone_point(rig,"origin")-origin).length<.0001
    tires=[o for o in scene.objects if o.name.startswith("Shrunk iron tire")]
    print("Advance spin by wheel in degrees:",[round(a,4) for a in rolled])
    print("Destroyed offsets in metres:",{k:round(v,4) for k,v in changes.items()})
    tire_lows=[bounds(scene,[o])[2][0] for o in tires]
    print("Destroyed tire lows in metres:",[round(z,4) for z in tire_lows])
    assert all(abs(z)<.027 for z in tire_lows),tire_lows


def main():
    scene=bpy.context.scene
    rig,=tuple(o for o in scene.objects if o.type=="ARMATURE")
    actor=rig.name[:-4]
    assert bpy.app.version[:3]==(5,2,2) and scene.render.fps==24 and not bpy.data.libraries
    assert not any(i.source=="FILE" for i in bpy.data.images)
    assert rig.animation_data.action.name==f"{actor} | Ready" and scene.frame_current==1
    assert scene["Approved concept SHA-256"] == "7f57ebb14852b0dd1a832c3783abd31d937a3d2babb1e23aac0e2ebb75a913c6"
    actions={a.name.split(" | ",1)[1]:int(a.frame_range.y) for a in bpy.data.actions}
    assert ACTORS[actor]==actions,actions
    assert not any(o.type in {"LIGHT","CAMERA"} for o in scene.objects)
    meshes=[o for o in scene.objects if o.type=="MESH"]
    curves=[o for o in scene.objects if o.type=="CURVE"]
    assert all(o.parent==rig or (o.parent and o.parent.name=="Wedge_Stave_Detachable")
               for o in meshes+curves)
    print(f"{Path(bpy.data.filepath).name}: {rig.name}, {len(rig.pose.bones)} bones; "
          f"{len(bpy.data.materials)} materials; {len(curves)} curves; actions: {actions}")
    extent=bounds(scene)
    print("Ready world bounds:",[tuple(round(k,4) for k in ab) for ab in extent])
    print("Ready world extent:",[round(b-a,4) for a,b in extent])
    bind="Neutral T" if actor=="WagonRaider" else "Neutral"
    probe(rig,scene,actor,bind,1)
    assert all(all(abs(a-b)<.0001 for p,q in zip(b.matrix,b.bone.matrix_local)
                   for a,b in zip(p,q)) for b in rig.pose.bones),bind
    check_clear_geometry(meshes)
    (check_raider if actor=="WagonRaider" else check_wagon)(rig,scene,actor)
    print("PASS: reopened self-contained rig, native actions, mesh orientation and performance checks")


if __name__=="__main__":
    main()
