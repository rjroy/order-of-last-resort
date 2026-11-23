"""Read-only review of one saved rival, using the cast bake's material and projection."""
import sys,json
import numpy as np
from pathlib import Path
import bpy
from mathutils import Vector

src=Path(bpy.data.filepath)
name=src.parent.name
args=sys.argv[sys.argv.index('--')+1:]
out=Path(args[0]); assert out.is_absolute()
out.mkdir(parents=True,exist_ok=True)
root=next(p for p in src.parents if (p/'games/company-of-unlikely-heroes/tools/cast').is_dir())
sys.path.insert(0,str(root/'games/company-of-unlikely-heroes/tools/cast'))
import bake_actor as bake
s=bpy.context.scene
rig=next(o for o in s.objects if o.type=='ARMATURE')
actions={a.name.split(' | ')[1]:a for a in bpy.data.actions}
sig={'rival_healer':['Ally Heal','Padded Bonk'],'rival_knight':['Shield Push'],'rival_wizard':['Nearest Blast']}[name]
assert set(actions)==set(['Neutral T','Ready','Move','Hit','Defeat']+sig)
def at(n,f):
    rig.animation_data.action=actions[n];s.frame_set(f);bpy.context.view_layer.update()
def xyz(v):return [round(float(x),4) for x in v]
at('Neutral T',1)
assert all(b.location.length<1e-5 and b.rotation_quaternion.angle<1e-4 for b in rig.pose.bones)
meshes=[o for o in s.objects if o.type in ('MESH','CURVE')]
assert all(o.parent is not None and len(o.data.materials)>0 for o in meshes)
pts=[o.matrix_world@Vector(c) for o in meshes for c in o.bound_box]
ext=[[min(v[i] for v in pts),max(v[i] for v in pts)] for i in range(3)]
at('Ready',1)
def skeleton():return {b.name:b.matrix.copy() for b in rig.pose.bones}
ready=skeleton()
checks={}
for n,a in actions.items():
    if n=='Neutral T':continue
    last=int(a.frame_range[1]); changes=[];gaps=[];minimum=1e3;largest_contact_gap=-1e3
    for f in range(1,last+1):
        at(n,f)
        delta=max(abs(b.matrix[i][j]-ready[b.name][i][j]) for b in rig.pose.bones for i in range(4) for j in range(4))
        changes.append(delta)
        lowest_sole=1e3
        for ob in meshes:
            if not (ob.name.startswith(('Welt and sole','Gored panel','Bound heater shield','Cudgel staff'))):continue
            ev=ob.evaluated_get(bpy.context.evaluated_depsgraph_get())
            verts=ev.data.vertices;xyz_buf=np.empty(3*len(verts),dtype=np.float32)
            verts.foreach_get('co',xyz_buf);mat=ev.matrix_world[2]
            low=float((xyz_buf.reshape(-1,3)@np.array(mat[:3])+mat[3]).min())
            minimum=min(minimum,low)
            if ob.name.startswith('Welt and sole'):lowest_sole=min(lowest_sole,low)
        largest_contact_gap=max(largest_contact_gap,lowest_sole)
        if name!='rival_wizard':
            hand=rig.pose.bones['hand.L' if name=='rival_knight' else 'hand.R'].matrix
            gaps.append((rig.pose.bones['regalia'].head-hand@Vector((0,.073,-.01))).length)
    assert changes[0]<.0001 and max(changes)>.005 and (n=='Defeat' or changes[-1]<.0001),(n,changes)
    if gaps:assert max(gaps)<.0001,(n,gaps)
    checks[n]={'frames':last,'max_matrix_change':round(max(changes),3),'max_grip_error_m':round(max(gaps),6) if gaps else None,'minimum_sole_hem_prop_z':round(minimum,4),'largest_nearest_sole_z':round(largest_contact_gap,4)}
report=dict(actor=name,source=src.name,version=bpy.app.version_string,editable_pieces=len(meshes),bones=len(rig.data.bones),materials=len(set(m for o in meshes for m in o.data.materials)),neutral_bounds=ext,checks=checks)
(out/'checks.json').write_text(json.dumps(report,indent=2)+'\n')
if 'check' in args:sys.exit()
bake.setup(s,name,bake.ANCHOR)
s.camera.data.ortho_scale=3.14
s.camera.location=s.camera.rotation_euler.to_matrix()@Vector((0,1.03,6))
s.cycles.samples=3
def render(n,f,path,size):
    at(n,f)
    s.render.resolution_x=s.render.resolution_y=size
    s.render.filepath=str(path);bpy.ops.render.render(write_still=True)
beats={'Shield Push':10,'Nearest Blast':10,'Ally Heal':15,'Padded Bonk':12}
stills=[('Neutral T',1),('Ready',1),('Move',10)]+[(n,beats[n]) for n in sig]+[('Hit',4),('Defeat',22)]
for n,f in stills:render(n,f,out/(n+'.png'),380)
if 'stills' not in args:
    # Every other native frame. Compositor plays at 12 fps, preserving timing.
    for n in sig:
        d=out/n;d.mkdir(exist_ok=True)
        for i,f in enumerate(range(1,int(actions[n].frame_range[1])+1,2)):render(n,f,d/('%03d.png'%i),256)
