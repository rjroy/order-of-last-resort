"""Build a fresh wall from the verified, read-only Knight master open in Blender."""
import bpy,bmesh,sys,hashlib,math,random
from mathutils import Vector,Matrix
from pathlib import Path
out=Path(sys.argv[-1]).resolve(); assert not out.exists()
assert hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()=='0bdf470f4472f2ee269337e458b605bf53be0f36f700e9ebbf8156147e10b45b'
s=bpy.context.scene
# Native element coordinates of the shield are in the unposed rig space.
shield=[o for o in s.objects if o.parent and o.parent.name=='Shield_L_Detachable' and not o.name.startswith('Shield reverse')]; shieldset=set(shield)
for o in shield: o.parent=None; o.matrix_world=Matrix.Diagonal((2.47,1.8,2.08,1))@Matrix.Translation((-.714,.01,-.961)); o.hide_render=False
for o in list(bpy.data.objects):
 if o not in shieldset: bpy.data.objects.remove(o,do_unlink=True)
def collection(name):
 c=bpy.data.collections.new(name);s.collection.children.link(c);return c
crest=collection('01 | Detachable Knight escutcheon');
for o in shield:
 for c in list(o.users_collection): c.objects.unlink(o)
 crest.objects.link(o)
for c in list(bpy.data.collections):
 if c!=crest: bpy.data.collections.remove(c)
def material(name,lo,hi,sc=(1,1,1),metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*hi,1);m.use_nodes=True;t=m.node_tree; p=t.nodes.get('Principled BSDF');p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=.68
 def link(a,b):t.links.new(a,b)
 tex=t.nodes.new('ShaderNodeTexCoord');v=t.nodes.new('ShaderNodeVectorMath');v.operation='MULTIPLY';v.inputs[1].default_value=sc;link(tex.outputs['Object'],v.inputs[0]);n=t.nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=5;n.inputs['Detail'].default_value=3;n.inputs['Distortion'].default_value=.28;link(v.outputs[0],n.inputs[0]);r=t.nodes.new('ShaderNodeValToRGB');r.color_ramp.elements[0].position=.24;r.color_ramp.elements[0].color=(*lo,1);r.color_ramp.elements[1].position=.79;r.color_ramp.elements[1].color=(*hi,1);link(n.outputs['Fac'],r.inputs[0]);link(r.outputs[0],p.inputs['Base Color']);b=t.nodes.new('ShaderNodeBump');b.inputs['Strength'].default_value=.18;b.inputs['Distance'].default_value=.013;link(n.outputs['Fac'],b.inputs['Height']);link(b.outputs[0],p.inputs['Normal']);return m
wood=[material('Riven oak | '+str(i),tuple(t*f for t in (.095,.040,.017)),tuple(t*f for t in (.45,.22,.082)),(7,6,.55)) for i,f in enumerate((.85,1,1.13))];iron=material('Blackened iron | hinges',(.045,.035,.029),(.16,.11,.074),metal=.56); bronze=material('Weathered bronze | straps',(.12,.063,.032),(.39,.23,.115),metal=.49);pin=material('Hammered brass | heads',(.26,.13,.04),(.57,.36,.14),metal=.62)
def mesh(name,verts,faces,mat,bevel):
 m=bpy.data.meshes.new(name);m.from_pydata(verts,[],faces);m.update();bm=bmesh.new();bm.from_mesh(m);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(m);bm.free();o=bpy.data.objects.new(name,m);col.objects.link(o);o.data.materials.append(mat)
 if bevel:
  b=o.modifiers.new('Hand-softened edges','BEVEL');b.width=bevel;b.segments=2;b=o.modifiers.new('Plane normals','WEIGHTED_NORMAL')
 return o
def prism(name,pts,y,t,mat,b=.008):
 n=len(pts);verts=[(x,y(x)+d,z) for d in (0,t) for x,z in pts];return mesh(name,verts,[tuple(range(n)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat,b)
def cylinder(name,p,r,h,mat,axis='Z'):
 bpy.ops.mesh.primitive_cylinder_add(vertices=12,radius=r,depth=h,location=p,rotation=(math.pi/2 if axis=='Y' else 0,0,0));o=bpy.context.object;o.name=name;o.data.materials.append(mat);o.users_collection[0].objects.unlink(o);col.objects.link(o);b=o.modifiers.new('Forged arris','BEVEL');b.width=.006;b.segments=2;o.modifiers.new('Flat facets','WEIGHTED_NORMAL');return o
col=collection('02 | Center backing');
# A real bearer fills the tapered shield's lower flanks and carries both hinges.
for i in range(7):
 x=-.65+i*1.3/7; w=1.3/7-.004;prism('Carrier stave',[(x,.055),(x+w,.055),(x+w,1.69),(x,1.69)],lambda x:-.14,.17,wood[i%3]);
for z in (.44,1.27):
 prism('Carrier cross-tie',[(-.65,z-.061),(.65,z-.061),(.65,z+.061),(-.65,z+.061)],lambda x:.027,.051,bronze)
 for x in (-.54,-.20,.20,.54):cylinder('Carrier tie nail',(x,.081,z),.025,.017,pin,'Y')
for side in (-1,1):
 col=collection(('03 | West' if side<0 else '04 | East')+' folding leaf');sx=lambda u:side*(.66+u); y=lambda x:-.14+.13*(abs(x)-.66)+.042*(abs(x)-.66)**2
 L=1.57;top=lambda u:1.70+.15*math.sin(math.pi*u/L)-.17*(u/L)**2
 def face(name,u0,u1,zlo,zhi,yoff,th,mat,b=.008,n=1):
  us=[u0+(u1-u0)*i/n for i in range(n+1)];pts=[(sx(u),zlo(u)) for u in us]+[(sx(u),zhi(u)) for u in reversed(us)];return prism(name,pts,lambda x:y(x)+yoff,th,mat,b)
 for i in range(8):
  face('Quarter-sawn stave %02d'%i,L*i/8+.002,L*(i+1)/8-.002,lambda u:.055,top,0,.145,wood[(i*7+(side>0))%3]);
 face('Crowned cap',0,L,lambda u:top(u)-.088,lambda u:top(u)+.014,-.026,.198,bronze,n=12)
 for level in (.44,1.27):
  arch=lambda u:.046*math.sin(math.pi*u/L)-.05*u/L
  face('Long hinge strap',0,L,lambda u:level+arch(u)-.052,lambda u:level+arch(u)+.052,-.036,.045,bronze,n=8)
  face('Reverse tie',0,L,lambda u:level-.054,lambda u:level+.054,.138,.045,iron,n=6)
  for u in (.15,.46,.83,1.20,1.49):cylinder('Peened strap rove',(sx(u),y(sx(u))-.044,level+arch(u)),.029,.023,pin,'Y')
  for u in (.17,.76,1.43):cylinder('Rear tie nail',(sx(u),y(sx(u))+.186,level),.022,.019,pin,'Y')
  # Knuckles and leaves are supported by fixed center stiles, not by the shield tip.
  face('Hinge leaf',-.20,.16,lambda u:level-.094,lambda u:level+.094,-.069,.044,iron);cx=sx(0)
  cylinder('Pintle',(cx,-.239,level),.037,.29,pin)
  for k in (-1,0,1):cylinder('Alternating knuckle',(cx,-.237,level+k*.087),.057,.077,bronze if k==0 else iron)
 for idx in range(5):
  u=.10+idx*.335;cylinder('Crown nail',(sx(u),y(sx(u))-.034,top(u)-.04),.024,.016,pin,'Y')
 # End trestle with an iron shoe, a raked knee and a standing post.
 u=L-.17;x=sx(u);fy=y(x); w=.115
 def knee(name,coords,mat):
  vs=[(x+dx,fy+yy,z) for dx in (-w,w) for yy,z in coords];n=len(coords);mesh(name,vs,[tuple(range(n)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat,.012)
 knee('Splayed oak shoe',[(-.37,.014),(.44,.014),(.43,.13),(.29,.17),(-.28,.17),(-.37,.13)],wood[0]);knee('Fore knee',[(-.34,.145),(-.18,.145),(.03,.57),(-.045,.60)],wood[1]);knee('Rear knee',[(.20,.15),(.41,.15),(.20,.80),(.135,.80)],wood[1]);knee('Iron toe cap',[(-.38,.004),(-.27,.004),(-.27,.175),(-.38,.147)],iron)
for c in [o for o in bpy.data.collections if not o.objects and not o.children]:bpy.data.collections.remove(c)
bpy.ops.outliner.orphans_purge(do_recursive=True);s.unit_settings.system='METRIC';s.render.use_compositing=False;s.render.use_sequencer=False;s.world=bpy.data.worlds.new('Neutral studio');s.world.color=(.24,.24,.24)
bpy.ops.object.select_all(action='DESELECT');s.frame_set(1)
for area in bpy.context.screen.areas:
 if area.type=='VIEW_3D':
  space=area.spaces.active;space.region_3d.view_rotation=Vector((-.17,1,-.25)).to_track_quat('-Z','Y');space.region_3d.view_location=(0,0,1);space.region_3d.view_distance=6;space.shading.color_type='MATERIAL';space.overlay.show_overlays=False
bpy.ops.wm.save_as_mainfile(filepath=str(out),compress=True)
