"""Read-only visualization. Coordinates for Pillow's exact board registration are emitted alongside views."""
import bpy,sys,json,math
from pathlib import Path
from mathutils import Vector,Matrix
from bpy_extras.object_utils import world_to_camera_view
out=Path(sys.argv[-1]);out.mkdir(exist_ok=False);s=bpy.context.scene
geometry=[o for o in s.objects if o.type in ('MESH','CURVE')];assert len(geometry)==len(s.objects);assert any('griffin' in o.name for o in geometry);assert len([c for c in bpy.data.collections if 'folding leaf' in c.name])==2
dg=bpy.context.evaluated_depsgraph_get();bounds=[o.matrix_world@p.co for ob in geometry for o in [ob.evaluated_get(dg)] for p in o.to_mesh().vertices];print('LOCAL AABB',[[round(f(v[i] for v in bounds),4) for i in range(3)] for f in (min,max)],'parts',len(geometry),'materials',len(set(m for o in geometry for m in o.data.materials)),flush=True);assert min(v.z for v in bounds)>-.03
r=s.render;r.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=18;s.cycles.use_denoising=True;s.cycles.seed=13;r.film_transparent=True;r.use_border=False;r.use_compositing=False;r.use_sequencer=False;r.resolution_percentage=100;r.image_settings.file_format='PNG';r.image_settings.color_mode='RGBA';r.image_settings.color_depth='8';s.view_settings.view_transform='AgX';s.view_settings.look='AgX - Medium High Contrast';s.view_settings.exposure=0;s.view_settings.gamma=1
world=bpy.data.worlds.new('Read-only studio ambient');s.world=world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.44,.42,.38,1);world.node_tree.nodes['Background'].inputs[1].default_value=.55
cam=bpy.data.cameras.new('Orthographic');c=bpy.data.objects.new('Registration camera',cam);s.collection.objects.link(c);cam.type='ORTHO';s.camera=c
lights=[]
for name,loc,power,col,size in [('Key',(-3,-4,6),600,(1,.91,.82),4),('Bounce',(3,-3,3),240,(.83,.89,1),4),('Skylight',(1,3,5),510,(1,.95,.86),3)]:
 d=bpy.data.lights.new(name,'AREA');o=bpy.data.objects.new(name,d);s.collection.objects.link(o);d.energy=power;d.color=col;d.shape='DISK';d.size=size;o.location=loc;o.rotation_euler=(Vector((0,0,.9))-o.location).to_track_quat('-Z','Y').to_euler();lights.append(o)
meta={}
def view(name,eye,target,width,res):
 c.location=Vector(target)+Vector(eye).normalized()*10;q=(Vector(target)-c.location).to_track_quat('-Z','Y');c.rotation_euler=(q.to_matrix() @ Matrix.Rotation(math.radians(27) if name in ('column-raw','crest-east-raw') else 0,3,'Z')).to_euler();cam.ortho_scale=width;r.resolution_x,r.resolution_y=res;bpy.context.view_layer.update();r.filepath=str(out/(name+'.png')); assert 'FINISHED' in bpy.ops.render.render(write_still=True)
 def uv(v):
  p=world_to_camera_view(s,c,Vector(v));return [p.x*res[0],(1-p.y)*res[1]]
 meta[name]=[uv(p) for p in [(0,0,0),(1,0,0),(0,1,0),(0,0,1)]]
view('front',(-.14,-1,.19),(0,0,1),5.05,(900,500));view('reverse',(.54,1,.53),(0,0,.95),5.15,(650,370));view('cast-angle',(-.386,-.828,.408),(0,0,.95),5.12,(650,370))
# Cast-style upright orthographic: row looks across the front, column down the span.
# Use a higher eye for the column to preserve depth measured in 80px grid steps.
def board(name,yaw,elevation):
 a,e=map(math.radians,(yaw,elevation));view(name,(math.sin(a)*math.cos(e),-math.cos(a)*math.cos(e),math.sin(e)),(0,0,.93),5.8,(1000,1000))
board('row-raw',-13,24.05);board('column-raw',59,53)

# Equivalent to a 180-degree turn of the wall under the fixed board camera
# and lighting, without changing any model geometry or mirroring its heraldry.
turn = Matrix.Rotation(math.pi, 3, 'Z')
for lamp in lights:
 lamp.location = turn @ lamp.location
 lamp.rotation_euler = (turn @ lamp.rotation_euler.to_matrix()).to_euler()
a, e = map(math.radians, (59, 53))
eye = turn @ Vector((math.sin(a)*math.cos(e), -math.cos(a)*math.cos(e), math.sin(e)))
view('crest-east-raw', eye, (0,0,.93), 5.8, (1000,1000))
(out/'projections.json').write_text(json.dumps(meta,indent=2))
