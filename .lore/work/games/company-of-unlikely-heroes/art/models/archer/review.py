"""Read-only review and mechanical checks of an exact saved Sheet 02 .blend."""
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from bpy_extras.object_utils import world_to_camera_view

mode, dest = sys.argv[sys.argv.index("--")+1:]
role = bpy.context.scene["Candidate role"]
assert role == Path(__file__).resolve().parent.name
source=Path(bpy.data.filepath)
assert source.is_absolute() and source.is_file()
out=Path(dest).resolve();out.mkdir(exist_ok=True,parents=True)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
original=sha(source)
repo=next(p for p in source.parents if (p/"games/company-of-unlikely-heroes/tools/cast/bake_actor.py").is_file())
sys.path.insert(0,str(repo/"games/company-of-unlikely-heroes/tools/cast"))
from bake_actor import setup, ANCHOR, SIZE

actor=role.title()
rig=bpy.data.objects[actor+"_Rig"]
s=bpy.context.scene
assert bpy.app.version[:3]==(5,2,2) and s.render.fps==24
assert not bpy.data.libraries and all(i.source!="FILE" for i in bpy.data.images)

stills = {'archer': [('neutral', 'Neutral T', 1), ('ready', 'Ready', 1), ('nock', 'Draw and Release', 8), ('draw', 'Draw and Release', 14), ('release', 'Draw and Release', 18), ('recover', 'Draw and Release', 22), ('arrival', 'Reserve Arrival', 8), ('advance', 'Advance', 15), ('hit', 'Hit', 4), ('defeat', 'Defeat', 24)]}
main = {'archer': ('Reserve Arrival', 'Draw and Release')}
mount = {'archer': 'Longbow_Detachable'}[role]
props=[bpy.data.objects[mount]]
if role=="archer": props.append(bpy.data.objects["Arrow_Detachable"])
propgeo={o for p in props for o in p.children_recursive}
for o in s.objects:
    if o.type=="LIGHT":o.hide_render=True
setup(s,role,ANCHOR)
s.render.threads_mode="FIXED";s.render.threads=2
s.cycles.samples=12
s.render.resolution_x=s.render.resolution_y=SIZE
c=s.camera
common=c.rotation_euler.copy()
common_location=c.location.copy()
default_prj=c.data.ortho_scale

def prepare(act,f,diagnostic=None):
    rig.animation_data.action=bpy.data.actions[f"{actor} | {act}"]
    s.frame_set(f)
    for o in propgeo:o.hide_render=act=="Neutral T"
    c.rotation_euler=common;c.location=common_location;c.data.ortho_scale=default_prj
    if diagnostic:
        c.rotation_euler.z={"back":2.56, "side":1.22, "bow-side":-1.70}[diagnostic]
        c.location=c.rotation_euler.to_matrix() @ Vector((0,default_prj*(ANCHOR[1]/SIZE-.5),6))
    bpy.context.view_layer.update()

def verts(objs):
    dg=bpy.context.evaluated_depsgraph_get()
    for o in objs:
        e=o.evaluated_get(dg)
        for v in e.data.vertices:
            yield e.matrix_world @ v.co

def render(stem,act,f,diag=None):
    prepare(act,f,diag)
    s.render.filepath=str(out/(stem+".png"))
    bpy.ops.render.render(write_still=True)

if mode=="poses":
    for name,act,f in stills[role]:render(name,act,f)
    render("back","Ready",1,"back")
    render("side","Ready",1,"side")
elif mode=="views":
    for name, take, frame in (
        ("ready", "Ready", 1), ("move", "Advance", 15), ("nock", "Draw and Release", 8),
        ("draw", "Draw and Release", 14), ("release", "Draw and Release", 18),
        ("recover", "Draw and Release", 22), ("hit", "Hit", 4), ("down", "Defeat", 24),
    ):
        for angle in ("side", "bow-side"):
            render(f"{name}-{angle}",take,frame,angle)
elif mode in ("motion","motion-full"):
    seq=["Ready",*main[role],"Advance","Hit","Defeat"]
    items=[]
    for act in seq:
        end=round(bpy.data.actions[f"{actor} | {act}"].frame_range[1])
        frames=list(range(1,min(17,end)+1,2) if act=="Ready" else range(1,end+1,2))
        if mode == "motion-full":
            frames=range(1,end+1)
        elif act == "Draw and Release":
            # Preserve the one authored flight drawing at 12 fps.
            frames[frames.index(19)] = 18
        for f in frames:
            render(f"frame-{len(items):03}",act,f)
            items.append({"action":act,"source_frame":f})
    (out/"index.json").write_text(json.dumps(items,indent=2)+"\n")
elif mode=="check":
    import bmesh
    mesh=[o for o in s.objects if o.type=="MESH"]
    for o in mesh:
        bm=bmesh.new();bm.from_mesh(o.data)
        assert bm.faces and not any(e.is_wire or len(e.link_faces)>2 for e in bm.edges),o.name
        assert o.modifiers.get("Cloth edge thickness") or all(e.is_manifold for e in bm.edges),o.name
        bm.free()
    soles=[o for o in mesh if o.name.startswith("Heel and forefoot sole")]
    assert len(soles)==2
    assert props[0].parent==rig and props[0].parent_bone=="implement" and props[0].children
    assert all(o.parent==rig and len(o.vertex_groups)>0 for o in mesh if o not in propgeo)
    assert all(m.node_tree and not m.library for m in bpy.data.materials)
    ready={}
    for act in ["Neutral T","Ready",*[v for v in main[role]],"Advance","Hit","Defeat"]:
        assert bpy.data.actions.get(f"{actor} | {act}"),act
    prepare("Neutral T",1)
    assert all((p.matrix.translation-p.bone.matrix_local.translation).length<.00001 for p in rig.pose.bones)
    for tag,sign in (("L",1),("R",-1)):
        v=rig.pose.bones["hand."+tag].head-rig.pose.bones["upper."+tag].head
        assert max(abs(v.y),abs(v.z))<.00001 and v.x*sign>.50
    body=list(verts(o for o in mesh if o not in propgeo and "Tensioned string" not in o.name))
    bind_bounds=[[round(min(p[i] for p in body),4),round(max(p[i] for p in body),4)] for i in range(3)]
    prepare("Ready",1)
    ready={b.name:b.matrix.copy() for b in rig.pose.bones}
    samples=0; minsole=1; minmargin=1; margin_at=None; minshield=(1,None)
    arrow_geo=set(props[1].children_recursive) if role=="archer" else set()
    for a in bpy.data.actions:
        name=a.name.split(" | ")[1]
        if name=="Neutral T":continue
        for f in range(1,round(a.frame_range[1])+1):
            prepare(name,f);samples+=1
            assert rig.pose.bones["root"].head.length<.00001,(name,f)
            low=min(p.z for p in verts(soles))
            minsole=min(minsole,low)
            if role=="shieldbearer":
                ground=min(p.z for p in verts(props[0].children_recursive))
                if ground<minshield[0]:minshield=(ground,(name,f))
            # Extending live study arrow excluded: production detaches it at F17.
            visible=[o for o in mesh if o not in arrow_geo and not o.hide_render]
            uv=[world_to_camera_view(s,c,p) for i,p in enumerate(verts(visible)) if i%7==0]
            dist=min(min(v.x,1-v.x,v.y,1-v.y) for v in uv)
            if dist<minmargin:minmargin,margin_at=dist,(name,f)
        if name!="Defeat":
            assert max((b.matrix.translation-ready[b.name].translation).length for b in rig.pose.bones)<.0004,name
            assert min(abs(b.matrix.to_quaternion().dot(ready[b.name].to_quaternion()))
                       for b in rig.pose.bones) > .999999, name
    assert bpy.data.actions[f"{actor} | Ready"].frame_range[1] == 33
    props_z = sorted(o.name for o in propgeo if o.type!="MESH")
    assert not props_z, props_z
    if role=="archer":
        act="Draw and Release"
        a=bpy.data.actions[f"{actor} | {act}"]
        assert a.pose_markers["Release"].frame==17
        prepare(act,13)
        full=rig["Draw"]
        ae=props[1].matrix_world.translation.copy()
        w=rig.pose.bones["implement"].head.copy()
        assert .8<full<.99 and .55<(w-ae).length<.62
        assert (rig.pose.bones["bow.nock"].head-ae).length<.0001
        draw_hand=rig.pose.bones["hand.L"]
        draw_grip=draw_hand.matrix @ (draw_hand.bone.matrix_local.inverted()
            @ (draw_hand.bone.head_local + Vector((.058,-.028,.001))))
        assert (ae-draw_grip).length<.042, (ae,draw_grip)
        prepare(act,18)
        assert rig["Draw"]<.01 and (props[1].matrix_world.translation-ae).length>.05
        prepare(act,20)
        assert props[1].matrix_world.translation.z < -1.9
    report=dict(source_sha256=original,object_count=len(s.objects)-1,mesh_count=len(mesh),
        materials=len(bpy.data.materials),bones=len(rig.pose.bones),frame_samples=samples,
        neutral_body_bounds=bind_bounds,min_sole_z=round(minsole,4),
        min_capture_margin_px=round(minmargin*SIZE,2),capture_margin_at=margin_at,
        shield_ground=minshield if role=="shieldbearer" else None,
        actions={a.name:list(a.frame_range) for a in bpy.data.actions})
    print(json.dumps(report,indent=2),flush=True)
    (out/"checks.json").write_text(json.dumps(report,indent=2)+"\n")
    assert minsole>=.0005,minsole
    assert minmargin>=.012,report
    if role=="shieldbearer":assert minshield[0]>=-.001,minshield
else:
    raise ValueError(mode)
assert original==sha(source)
