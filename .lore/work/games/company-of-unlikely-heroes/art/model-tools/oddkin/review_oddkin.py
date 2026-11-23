"""Read-only inspection of the Goblin, Village Troll, Ogre and Trickster models."""
import sys,hashlib,json
from pathlib import Path
import bpy
from mathutils import Vector
src=Path(bpy.data.filepath);root=next(p for p in src.parents if (p/'games/company-of-unlikely-heroes/tools/cast').exists());sys.path.insert(0,str(root/'games/company-of-unlikely-heroes/tools/cast'));import bake_actor as cast
args=sys.argv[sys.argv.index('--')+1:];out=Path(args[0]);assert out.is_absolute();out.mkdir(exist_ok=True,parents=True);n=src.parent.name;mode=args[1] if len(args)>1 else 'all';s=bpy.context.scene;rig=next(o for o in s.objects if o.type=='ARMATURE');acts={a.name.split(' | ')[1]:a for a in bpy.data.actions};parts=[o for o in s.objects if o.type=='MESH'];assert all(o.parent==rig and o.parent_type=='BONE' and o.parent_bone in rig.data.bones and len(o.data.materials)>0 for o in parts);sha=hashlib.sha256(src.read_bytes()).hexdigest()
def pose(a,f):rig.animation_data.action=acts[a];s.frame_set(f);bpy.context.view_layer.update()
pose('Neutral T',1);assert all(b.rotation_quaternion.angle<.0001 and b.location.length<.0001 for b in rig.pose.bones);pts=[o.matrix_world@Vector(c) for o in parts for c in o.bound_box];bounds=[[round(min(p[i] for p in pts),4),round(max(p[i] for p in pts),4)] for i in range(3)];pose('Ready',1);ready={b.name:b.matrix.copy() for b in rig.pose.bones};checks={}
for a,act in acts.items():
 if a=='Neutral T':continue
 end=int(act.frame_range[1]);diff=[]
 for f in range(1,end+1):
  pose(a,f);diff.append(max(abs(b.matrix[i][j]-ready[b.name][i][j]) for b in rig.pose.bones for i in range(4) for j in range(4)))
 assert diff[0]<.001 and max(diff)>.014 and (a in ('Defeat','Leaves Square Alive') or diff[-1]<.001),(a,diff[0],max(diff),diff[-1]);checks[a]=end
beats={'goblin':[('Scamper',7),('Goblin Jab',8)],'village_troll':[('Curious Follow',7),('Stop Beside Hero',13),('Displaced',6),('Leaves Square Alive',20)],'ogre':[('Heavy Tread',7),('Heavy Strike',14),('Heavy Strike',22),('Swap Reaction',6)],'trickster':[('Quick Step',7),('Melee Feint',11),('Switch Places',10),('Switch Places',20)]}[n];stills=[('Neutral T',1),('Ready',1)]+beats+[('Hit',4),('Defeat',25)]
cast.setup(s,n,cast.ANCHOR);s.camera.data.ortho_scale=3.74 if n=='village_troll' else 3.4;s.camera.location=s.camera.rotation_euler.to_matrix()@Vector((0,1.08,6));s.cycles.samples=3;s.render.threads_mode='FIXED';s.render.threads=2
report={'sha256':sha,'blender':bpy.app.version_string,'bounds':bounds,'bones':len(rig.data.bones),'pieces':len(parts),'materials':len(set(m for o in parts for m in o.data.materials)),'actions':checks,'stills':stills};(out/'verified.json').write_text(json.dumps(report,indent=2)+'\n')
def render(a,f,p,size):pose(a,f);s.render.resolution_x=s.render.resolution_y=size;s.render.filepath=str(p);bpy.ops.render.render(write_still=True)
if mode in ('all','poses'):
 for i,(a,f) in enumerate(stills):render(a,f,out/f'pose-{i}.png',320)
if mode in ('all','motion'):
 s.cycles.samples=2
 for a in dict.fromkeys([a for a,f in beats]+['Defeat']):
  d=out/a;d.mkdir(exist_ok=True);end=checks[a]
  for i,f in enumerate(range(1,end+1,2)):render(a,f,d/f'{i:03}.png',192)
assert sha==hashlib.sha256(src.read_bytes()).hexdigest()
