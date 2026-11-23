"""Reopen either field actor and render timed samples using the shipped cast projection."""
import hashlib
import sys
from pathlib import Path
import bpy
import bmesh

root = next(p for p in Path(__file__).resolve().parents if (p / 'games/company-of-unlikely-heroes/tools/cast').is_dir())
sys.path.insert(0, str(root / 'games/company-of-unlikely-heroes/tools/cast'))
from bake_actor import setup, ANCHOR

samples = {
    'Sheep': {'Ready':[1,13], 'Startle':[1,4,9,14], 'Flee step':[1,4,8,12,16,22], 'Pen settle':[1,6,11,15,20,24,36], 'Penned':[1]},
    'Shepherd': {'Ready':[1,13], 'Pursuit step':[1,4,6,9,12,15,18,21,25], 'Scatter wave':[1,5,10,15,20,25,29,33,36,40]},
}
s = bpy.context.scene
role=s['role']; actor={'frontier_sheep':'Sheep','frontier_shepherd':'Shepherd'}[role]
rig=bpy.data.objects[actor+'_Rig'];src=Path(bpy.data.filepath); digest=hashlib.sha256(src.read_bytes()).hexdigest(); assert not bpy.data.libraries
out=Path(sys.argv[-1]).resolve()/role;out.mkdir(parents=True,exist_ok=True)
meshes=[o for o in s.objects if o.type=='MESH'];bb=[v.co for o in meshes for v in o.data.vertices];print('REST BOUNDS',[(min(p[i] for p in bb),max(p[i] for p in bb)) for i in range(3)])
for o in meshes:
    assert o.parent==rig and o.modifiers[0].object==rig and all(len(v.groups)==1 for v in o.data.vertices)
    bm=bmesh.new();bm.from_mesh(o.data);assert all(e.is_manifold for e in bm.edges),o.name;bm.free()
assert {a.name for a in bpy.data.actions}=={actor+' | '+k for k in samples[actor]}
print('VALIDATION',role,digest,len(meshes),'mesh parts',len(rig.data.bones),'bones',sum(len(o.data.polygons) for o in meshes),'faces')
setup(s,role,ANCHOR)
for suffix,frames in samples[actor].items():
    rig.animation_data.action=bpy.data.actions[actor+' | '+suffix]
    for f in frames:
        s.frame_set(f); s.render.filepath=str(out/f'{suffix.replace(" ","_")}-{f:02}.png'); bpy.ops.render.render(write_still=True)
assert hashlib.sha256(src.read_bytes()).hexdigest()==digest
