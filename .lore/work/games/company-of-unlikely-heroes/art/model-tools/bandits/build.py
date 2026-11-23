"""Construct the three separately editable Blender candidates."""
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector

V = Vector
ROOT = Path(__file__).parent.resolve()
sys.path.insert(0, str(ROOT))
from perform import animate

VARIANTS = {
    "bandit_damage": ("Fierce Bandit", .252, .99, 1.57, 1.715, .292, .275, .195, .98),
    "bandit_guard": ("Guard Bandit", .317, .94, 1.49, 1.622, .287, .258, .247, 1.06),
    "bandit_swift": ("Swift Bandit", .193, 1.06, 1.59, 1.735, .270, .279, .158, .93),
}

COLORS = {
    "ink": ("1a1515","382624"), "hair":("2a191a","543127"),
    "hairlight":("503027","9a6447"), "hairdark":("201719","3b2824"),
    "skin":("ae6d50","ecb789"), "flush":("99503f","cb8462"),
    "eye":("a88968","f6dcb0"), "iris":("33271c","795b3e"),
    "stubble":("56352b","99654b"), "fur":("8e684f","d3b184"),
    "fur_dark":("6c4b3b","a98967"), "hood":("383043","655568"),
    "hood_edge":("504154","8b6973"), "wool":("52413a","84644a"),
    "undyed":("8b6d50","ceaf86"), "patch":("997047","c99c61"),
    "rust":("652e29","aa5645"), "rustdark":("462529","703739"),
    "olive":("3f3c30","726445"), "olive_edge":("736249","b28657"),
    "trouser":("373039","64535a"), "boot":("322524","685043"),
    "sole":("221c1d","44332d"), "belt":("412b27","77523b"),
    "bag":("795237","aa7750"), "gold":("895d39","d6a866"),
    "thread":("9b7754","d4aa78"), "wood":("4c342a","9b6f46"),
    "iron":("484750","847d78"), "edge":("9b8881","d3c5ad"),
}


def pigment(name, tones):
    def rgb(hexcolor):
        s = [int(hexcolor[i:i+2], 16) / 255 for i in range(0, 6, 2)]
        return tuple((x / 12.92 if x <= .04045 else ((x + .055) / 1.055) ** 2.4) for x in s)
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb(tones[1]), 1)
    m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links.new
    shader = n.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = .74 if name in {"edge","iron","gold"} else .87
    coarse = n.new("ShaderNodeTexNoise")
    coarse.inputs["Scale"].default_value = 6.4
    coarse.inputs["Detail"].default_value = 3.5
    grain = n.new("ShaderNodeTexNoise")
    grain.inputs["Scale"].default_value = 78
    grain.inputs["Detail"].default_value = 2
    grain.inputs["Roughness"].default_value = .72
    mapping = n.new("ShaderNodeTexCoord")
    for tex in (coarse, grain):
        l(mapping.outputs["Generated"], tex.inputs["Vector"])
    multiply = n.new("ShaderNodeMath")
    multiply.operation = "MULTIPLY_ADD"
    multiply.inputs[1].default_value = .30
    l(grain.outputs["Fac"], multiply.inputs[0])
    l(coarse.outputs["Fac"], multiply.inputs[2])
    ramp = n.new("ShaderNodeValToRGB")
    for el, color, at in zip(ramp.color_ramp.elements, tones, (.32,.88)):
        el.position, el.color = at, (*rgb(color),1)
    l(multiply.outputs[0], ramp.inputs["Fac"])
    l(ramp.outputs[0], shader.inputs["Base Color"])
    bump = n.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .16
    bump.inputs["Distance"].default_value = .006
    l(grain.outputs["Fac"], bump.inputs["Height"])
    l(bump.outputs[0], shader.inputs["Normal"])
    return m


def group(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


def mesh(name, verts, faces, mat, bone, *, smooth=True, sub=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    topology=bmesh.new()
    topology.from_mesh(data)
    if all(len(e.link_faces)==2 for e in topology.edges):
        bmesh.ops.recalc_face_normals(topology,faces=topology.faces[:])
        topology.to_mesh(data)
    topology.free()
    data.update()
    ob = bpy.data.objects.new(name, data)
    collection.objects.link(ob)
    data.materials.append(mats[mat])
    for p in data.polygons:
        p.use_smooth = smooth
    if sub:
        mod = ob.modifiers.new("Turned form", "SUBSURF")
        mod.levels = mod.render_levels = sub
    bindings.append((ob, bone))
    return ob


def bridge(n, rings, caps=True):
    faces = [tuple(reversed(range(n)))] if caps else []
    for k in range(0, (rings-1)*n, n):
        faces.extend((k+i, k+(i+1)%n, k+(i+1)%n+n, k+i+n) for i in range(n))
    if caps:
        faces.append(tuple(range((rings-1)*n,rings*n)))
    return faces


def loft(name, rings, mat, bone, *, direction=(0,0,1), n=14, sub=1, var=.022):
    w = V(direction).normalized()
    u = V((1,0,0)) if abs(w.x)<.91 else V((0,1,0))
    u = (u-w*u.dot(w)).normalized()
    v = w.cross(u)
    phase = rng.uniform(0,math.tau)
    vert = []
    for j,(c,a,b) in enumerate(rings):
        for i in range(n):
            t = math.tau*i/n
            r = 1+var*(math.sin(3*t+phase)+.46*math.sin(5*t-.7*j))
            vert.append(V(c)+r*(a*math.cos(t)*u+b*math.sin(t)*v))
    return mesh(name,vert,bridge(n,len(rings)),mat,bone,sub=sub)


def blob(name, center, radii, mat, bone, *, tilt=0, sub=1, n=12):
    rot = Matrix.Rotation(tilt,3,"Y")
    return loft(name,[(V(center)+rot@V((0,0,radii[2]*math.sin(a))),radii[0]*math.cos(a),radii[1]*math.cos(a))
                      for a in map(math.radians,(-87,-66,-39,-13,13,39,66,87))],
                mat,bone,direction=rot@V((0,0,1)),sub=sub,n=n)


def segment(name,start,end,shape,mat,bone,*,n=12,sub=1):
    start,end=V(start),V(end)
    return loft(name,[(start.lerp(end,f),a,b) for f,a,b in shape],mat,bone,direction=end-start,n=n,sub=sub)


def cord(name, points, width, mat, bone, *, poly=False):
    data = bpy.data.curves.new(name,"CURVE")
    data.dimensions = "3D"
    data.resolution_u = 5
    data.bevel_depth = width
    data.bevel_resolution = 2
    data.use_fill_caps = True
    spl = data.splines.new("POLY" if poly else "BEZIER")
    if poly:
        spl.points.add(len(points)-1)
        for bp, p in zip(spl.points,points):
            bp.co = (*p,1)
    else:
        spl.bezier_points.add(len(points)-1)
        for bp,p in zip(spl.bezier_points,points):
            bp.co = p
            bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new(name,data)
    collection.objects.link(ob)
    data.materials.append(mats[mat])
    bindings.append((ob,bone))
    return ob


def plate(name, outline, mat, bone, thickness, bevel=.008, outward=(0,1,0)):
    n=len(outline)
    verts=[V(p)-thickness*V(outward)/2 for p in outline]+[V(p)+thickness*V(outward)/2 for p in outline]
    ob=mesh(name,verts,bridge(n,2),mat,bone,smooth=False)
    mod=ob.modifiers.new("Worn edge roll","BEVEL")
    mod.width,mod.segments=bevel,2
    return ob


def strand(name, points, widths, mat, bone, *, highlights=True):
    n=8
    verts=[]
    pts=list(map(V,points))
    for i,(p,w) in enumerate(zip(pts,widths)):
        direction=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
        front=V((0,-1,0))
        front=(front-direction*front.dot(direction)).normalized()
        across=front.cross(direction)
        verts.extend(p+w*(math.cos(t)*across+.68*math.sin(t)*front) for t in (math.tau*j/n for j in range(n)))
    mesh(name,verts,bridge(n,len(points)),mat,bone,sub=1)
    if highlights:
        cord(name+" pigment ridge",[p+V((.18*w,-.54*w,0)) for p,w in zip(pts,widths)],.0037,"hairlight",bone)


def rig_setup():
    arm=bpy.data.armatures.new(title+" skeleton")
    rig=bpy.data.objects.new(title.replace(" ","_")+"_Rig",arm)
    collection.objects.link(rig)
    rig.show_in_front=True
    arm.display_type="STICK"
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    specs={}
    def bone(k, a, b, parent, layer):
        ob=arm.edit_bones.new(k)
        ob.head,ob.tail=a,b
        if parent:
            ob.parent=arm.edit_bones[parent]
        ob.align_roll(V((0,0,1)))
        specs[k]=layer
        rest[k]=(V(a),V(b))
    bone("root",(0,0,0),(0,-.20,0),None,"Core")
    bone("pelvis",(0,.012,hip_z),(0,.012,hip_z+.19),"root","Core")
    bone("chest",(0,.012,hip_z+.19),(0,0,shoulder),"pelvis","Core")
    bone("neck",(0,0,shoulder),(0,-.011,chin),"chest","Core")
    bone("head",(0,-.011,chin),(0,-.011,chin+.29),"neck","Core")
    bone("mantle",(0,.08,shoulder+.02),(0,.32,shoulder-.30),"chest","Cloth and hair")
    for s, sign in (("R",-1),("L",1)):
        def side(k,a,b,p,layer="Limbs"):
            bone(k+"."+s,(sign*a[0],*a[1:]),(sign*b[0],*b[1:]),p,layer)
        side("upper_arm",(width,0,shoulder),(width+upper,0,shoulder),"chest")
        side("forearm",(width+upper,0,shoulder),(width+upper+lower,0,shoulder),"upper_arm."+s)
        side("hand",(width+upper+lower,0,shoulder),(width+upper+lower+.135,0,shoulder),"forearm."+s)
        side("thigh",(waist*.66,0,hip_z+.013),(waist*.69,-.027,.52),"pelvis")
        side("shin",(waist*.69,-.027,.52),(waist*.74,.014,.125),"thigh."+s)
        side("foot",(waist*.74,.014,.125),(waist*.74,-.19,.125),"shin."+s)
        side("tail",(waist*.65,.11,hip_z+.15),(waist*1.12,.22,hip_z-.19),"pelvis","Cloth and hair")
        side("hair",(.125,.012,chin+.30),(.20,.21,chin+.18),"head","Cloth and hair")
        side("grip",(width+upper+lower+.071,0,shoulder),(width+upper+lower+.071,.18,shoulder),"hand."+s,"Gear")
    bpy.ops.object.mode_set(mode="OBJECT")
    layers={key:arm.collections.new(key) for key in dict.fromkeys(specs.values())}
    for b in arm.bones:
        layers[specs[b.name]].assign(b)
        b.use_deform=specs[b.name]!="Gear" and b.name!="root"
        rig.pose.bones[b.name].rotation_mode="QUATERNION"
    rig["Role ID"]=role
    rig["Model status"]="Candidate, no runtime acceptance"
    rig["Rest orientation"]="T-rest; forward -Y, up +Z, wearer right -X"
    return rig


def clothes():
    garment={"bandit_damage":"wool","bandit_guard":"hood","bandit_swift":"olive"}[role]
    zs=[hip_z-.035,hip_z+.023,hip_z+.15,hip_z+.24,shoulder-.16,shoulder-.052,shoulder+.035,shoulder+.072]
    wx=[.76*waist,.98*waist,.97*waist,.86*waist,.90*width,1.05*width,.94*width,.55*width]
    dep=[.105,.132,.142,.135,.158,.155,.125,.093]
    depth_scale=1.28 if guard else .87 if swift else 1
    loft("Continuous tailored doublet",[((0,0,z),x,d*depth_scale) for z,x,d in zip(zs,wx,dep)],
         garment,"weighted",n=22)
    for sign,s in ((-1,"R"),(1,"L")):
        # Unmatched wool skirts make movement separable from the trousers.
        x=sign*.10
        p=[(x-.095,-.12,hip_z+.125),(x+.082,-.12,hip_z+.125),
           (x+.11,-.19,hip_z-.075),(x+.078,-.20,hip_z-.162),
           (x+.012,-.191,hip_z-.131),(x-.022,-.205,hip_z-.204),
           (x-.065,-.19,hip_z-.149),(x-.101,-.17,hip_z-.18)]
        plate("Overlapping split skirt "+s,p,garment,"tail."+s,.026,.015)
        cord("Skirt turned seam "+s,[p[0],p[-1],p[-2],p[-3]],.005,
             "olive_edge" if swift else "belt","tail."+s,poly=True)
    belt_center=hip_z+.124
    for n,(z,h,offset) in enumerate(((belt_center,.090,0),(belt_center-.072,.038,.027))):
        loft(f"Crossed leather belt {n+1}",
            [((0,0,z-d),waist*(1.04+inc),.145*depth_scale+offset+inc*.05)
             for d,inc in ((h/2,0),(h/2-.006,.09),(-h/2+.006,.04),(-h/2,0))],
            "belt","pelvis",n=24,sub=0)
    x=-waist*.32
    y=-.16*depth_scale
    z=belt_center+.002
    cord("Shared brass belt square",[(x+a,y,z+b) for a,b in ((-.036,-.023),(.036,-.023),(.036,.023),(-.036,.023),(-.036,-.023))],
         .008,"gold","pelvis",poly=True)
    cord("Buckle pin",[(x-.036,y-.009,z),(x+.021,y-.009,z+.005)],.004,"gold","pelvis")
    for sign,s in ((-1,"R"),(1,"L")):
        x=sign*(waist+.022)
        y=.004 if s=="L" else .055
        z=belt_center-(.086 if guard else .044)
        blob("Tool pouch body "+s,(x,y,z),(.086,.102,.098 if swift else .121),"bag","pelvis",tilt=sign*.23)
        blob("Pouch folded flap "+s,(x-.007,y-.035,z+.040),(.081,.081,.032),"belt","pelvis",tilt=sign*.18)
        blob("Pouch button "+s,(x,y-.102,z+.031),(.011,.008,.010),"gold","pelvis",sub=0)
    for sign in (-1,1):
        x=sign*width*.62
        if guard:
            for band in range(4):
                z=shoulder-.27+band*.070
                for dx in (.040,.115):
                    cx=sign*(dx+(.018 if band%2 else 0))
                    y=-.175*math.sqrt(max(.26,1-(cx/(width+.006))**2))
                    outline=[(cx-.039,y,z),(cx,y-.006,z-.047),(cx+.040,y,z),(cx,y-.006,z+.049)]
                    cord(f"Quilt ridge {sign} {band} {dx}",outline+[outline[0]],.004,"hood_edge","chest",poly=True)
        else:
            cord("Shaped lapel "+str(sign),[(x,-.094,shoulder+.043),(x*.84,-.145,shoulder-.061),
                (x*.52,-.159,shoulder-.142),(x*.13,-.148,hip_z+.193)],.016 if swift else .012,
                 "olive_edge" if swift else "undyed","chest")
    for j in range(3):
        z=shoulder-.157-j*.065
        cord("Toggle "+str(j),[(-.040,-.191 if guard else -.166,z-.005),(.038,-.188 if guard else -.161,z+.012)],
             .008 if guard else .005,"gold","chest")


def drapery():
    if guard:
        # Ragged sheepskin collar wraps shoulders without becoming a shoulderplate.
        n=32
        rows=[]
        for row in range(3):
            for i in range(n):
                a=math.tau*i/n
                l=(1,.36,0)[row]
                rag=(.045*(i%3==1)+.024*math.sin(i*2.53))*l
                rows.append((math.cos(a)*(.147+l*.219),math.sin(a)*(.105+l*.147)+.035,
                    shoulder+.152-l*(.186+.09*max(0,-math.sin(a)))-rag))
        obj=mesh("Low scalloped sheepskin collar",rows,bridge(n,3,False),"fur","chest")
        solid=obj.modifiers.new("Double-sided leather backing","SOLIDIFY")
        solid.thickness=.030
        for i in range(16):
            a=math.tau*i/16
            c=(.332*math.cos(a),.225*math.sin(a)+.035,shoulder-.032-.07*max(0,-math.sin(a)))
            strand(f"Rough collar lock {i+1}",[(c[0]*.71,c[1]*.73,c[2]+.12),c,
                   (c[0]*1.10,c[1]*1.1,c[2]-.039),(c[0]*1.075,c[1]*1.07,c[2]-.09-rng.random()*.033)],
                   [.026,.048,.035,.002],"fur" if i%3 else "fur_dark","chest",highlights=False)
    elif not swift:
        # The hair and broken shoulder mantle create an asymmetric triangle in profile.
        n=28
        rows=[]
        for row in range(4):
            for i in range(n):
                a=math.tau*i/n
                l=(1,.64,.28,0)[row]
                front=max(0,-math.sin(a))
                rag=.09*((i%4 in (1,2))+.5*math.sin(2.1*i)) if row==0 else .01
                rows.append((.025+math.cos(a)*(.124+l*(.193-.02*front)),
                    math.sin(a)*(.092+l*.149)+.036+l*.044,
                    shoulder+.11-l*(.27+.17*max(0,math.sin(a))-.060*front)-rag))
        obj=mesh("Frayed wool work mantle",rows,bridge(n,4,False),"rust","mantle")
        solid=obj.modifiers.new("Wool thickness","SOLIDIFY")
        solid.thickness=.022
        for i in (0,3,7,9,12,16,20,23,26):
            p=rows[i]
            cord("Ragged mantle mending "+str(i),[(p[0]*.72,p[1]*.71,p[2]+.10),p,(p[0]*1.03,p[1]+.008,p[2]-.041)],
                 .006,"rustdark","mantle")
        plate("Front waist sash",[(-.076,-.182,hip_z+.108),(.048,-.162,hip_z+.098),(.035,-.219,hip_z-.236),
              (.002,-.212,hip_z-.192),(-.021,-.223,hip_z-.277),(-.074,-.206,hip_z-.197)],"rustdark","tail.R",.016)
    else:
        for sign,s in ((-1,"R"),(1,"L")):
            x=sign*.11
            segments=[(x-.045,.156,hip_z+.13),(x,.173,hip_z+.129),(x+.044,.155,hip_z+.12),
                      (x+sign*.065-.040,.27,hip_z-.019),(x+sign*.065,.298,hip_z-.023),
                      (x+sign*.065+.038,.278,hip_z-.032),
                      (x+sign*.128-.039,.371,hip_z-.214-sign*.025),
                      (x+sign*.128-.003,.364,hip_z-.173-sign*.032),
                      (x+sign*.128+.033,.358,hip_z-.235-sign*.022)]
            sash=mesh("Split trailing sash "+s,segments,[(0,3,4,1),(1,4,5,2),(3,6,7,4),(4,7,8,5)],
                      "rust","tail."+s)
            solid=sash.modifiers.new("Turned sash thickness","SOLIDIFY")
            solid.thickness=.014
            cord("Sash fold "+s,[segments[1],segments[4],segments[7]],.005,"rustdark","tail."+s)


def head():
    h=head_size
    at=lambda x,y,z:(x*h,y*h,chin+z*h)
    loft("Neck",[ ((0,.004,z),a*h,b*h) for z,a,b in [
        (shoulder-.022,.078,.072),(shoulder-.010,.080,.075),(chin+.034,.084,.084),(chin+.059,.086,.081)]],
         "skin","neck")
    rings=[
        ((.012,-.042,.001),.065,.064),((.009,-.060,.033),.106 if guard else .087,.092),
        ((.006,-.034,.078),.121 if guard else .103,.106),((.003,-.018,.130),.124,.112),
        ((.000,-.010,.176),.125,.115),((-.007,.001,.223),.118,.108),
        ((-.008,.009,.267),.100,.096),((-.010,.009,.304),.054,.060),
    ]
    loft("Asymmetric jaw and cranium",[(at(*c),a*h,b*h) for c,a,b in rings],"skin","head",n=22,var=.016)
    for sign in (-1,1):
        x=sign*.066
        eye_lift=.012 if sign<0 else .004
        coords=[
            at(x-.042,-.111,.153+eye_lift),at(x-.029,-.128,.169+eye_lift),
            at(x+.008,-.140,.172+eye_lift),at(x+.035,-.125,.163+eye_lift),
            at(x+.038,-.119,.154+eye_lift),at(x+.009,-.132,.143+eye_lift),
            at(x-.021,-.131,.144+eye_lift),
        ]
        plate("Cut almond sclera "+str(sign),coords,"eye","head",.012,.004)
        cord("Heavy upper lid "+str(sign),coords[:5],.0055,"ink","head")
        cord("Lower eyelid "+str(sign),coords[4:]+coords[:1],.004,"flush","head")
        blob("Brown iris "+str(sign),at(x+.012,-.142,.155+eye_lift),(.014*h,.007,.017*h),"iris","head")
        blob("Pupil "+str(sign),at(x+.014,-.149,.156+eye_lift),(.007*h,.004,.011*h),"ink","head")
        blob("Catchlight "+str(sign),at(x+.012,-.154,.164+eye_lift),(.0038,.0029,.0041),"eye","head",sub=0)
        points=[at(x-.044,-.119,.192+eye_lift),at(x-.019,-.138,.211+eye_lift),
                at(x+.012,-.138,.214+eye_lift),at(x+.043,-.118,.190+eye_lift)]
        if not swift:
            if sign>0:
                points=points[::-1]
            points[-1]=V(points[-1])+V((0,-.006,-.013))
        strand("Stern swept brow "+str(sign),points,[.005,.018 if guard else .013,.010,.003],"hairdark","head",highlights=False)
        blob("Shaped ear "+str(sign),at(sign*.120,.007,.119),(.032*h,.036*h,.060*h),"skin","head",tilt=sign*.24)
        blob("Ear hollow "+str(sign),at(sign*.140,-.021,.122),(.014*h,.008*h,.031*h),"flush","head",tilt=sign*.24)
        cord("Cheek plane "+str(sign),[at(sign*.075,-.121,.117),at(sign*.10,-.100,.132),at(sign*.111,-.088,.148)],
             .004,"flush","head")
        for i in range(4):
            ax=(.050+.010*i)*sign
            blob("Weathered freckle "+str((sign,i)),at(ax,-.133+.005*i,.114+.004*(i%2)),(.0035,.0027,.0031),"flush","head",sub=0)
    nose=[(at(.004,-.119,.114),.037*h,.027*h),(at(.008,-.146,.122),.033*h,.040*h),
          (at(.010,-.151,.139),.029*h,.043*h),(at(.007,-.130,.163),.026*h,.031*h),
          (at(-.004,-.110,.198),.021*h,.017*h)]
    loft("Hooked wedge of nose",nose,"skin","head",n=12)
    for sign in (-1,1):
        blob("Nostril "+str(sign),at(sign*.021+.007,-.158,.117),(.011,.010,.006),"stubble","head")
    cord("Crooked mouth", [at(-.049,-.123,.069),at(-.022,-.141,.074),at(.009,-.145,.069),at(.041,-.129,.080)],
         .0045,"ink","head")
    cord("Lower lip", [at(-.027,-.139,.057),at(.006,-.145,.057),at(.030,-.137,.064)],.006,"flush","head")
    if not guard:
        cord("Shared hammered earring",[at(-.147,-.011,.108),at(-.153,-.026,.074),at(-.144,-.009,.057),
              at(-.135,.009,.076),at(-.147,-.011,.108)],.006,"gold","head")
    hair(at)


def hair(at):
    if guard:
        rings=[(at(0,.056,-.046),.126,.105),(at(0,.079,.025),.171,.139),
            (at(-.004,.079,.13),.187,.150),(at(-.017,.070,.239),.176,.140),
            (at(-.032,.060,.319),.141,.111),(at(-.068,.068,.374),.075,.076),
            (at(-.10,.083,.367),.039,.043)]
        loft("Fallen peak of shaggy hood",rings,"hood","head",n=18,var=.06)
        cord("Frayed hood opening",[at(x,-.09,z) for x,z in [
            (-.132,.028),(-.157,.103),(-.148,.223),(-.092,.290),(.007,.303),(.109,.268),(.151,.175),(.147,.063)]],
             .019,"hood_edge","head")
        for sign in (-1,1):
            outline=[at(sign*x,y,z) for x,y,z in ((.120,.002,.152),(.122,-.044,.116),(.113,-.093,.082),
                    (.099,-.105,.043),(.078,-.107,.054),(.092,-.094,.105),(.101,-.056,.141))]
            plate("Unshaven sideburn "+str(sign),outline,"stubble","head",.016,.008,outward=(sign*.9,-.2,0))
            for i in range(4):
                strand("Loose side curl "+str((sign,i)),[at(sign*(.104+.011*i),-.025,.25-.025*i),
                    at(sign*(.134+.007*i),-.060,.202-.025*i),at(sign*(.140+.008*i),-.067,.152-.025*i),
                    at(sign*(.123+.010*i),-.086,.143-.025*i)], [.014,.027,.019,.001],"hair","head")
        for i in range(4):
            x=-.11+i*.054
            strand(f"Forelock {i}",[at(x+.045,.001,.297),at(x+.018,-.109,.265),at(x-.025,-.124,.237),
                     at(x-.031,-.126,.209+.009*i)],[.038,.031,.016,.002],"hair","head")
    else:
        blob("Dense swept hair cap",at(-.010,.052,.228),(.150 if swift else .172,.127,.118),"hairdark","head",tilt=-.2)
        for i in range(8):
            x=-.155+i*.041
            strand(f"Swept crown curl {i+1}",[at(x*.54+.03,.085,.316),at(x*.8+.037,-.011,.337-.009*(i%3)),
                    at(x,-.097,.289+.015*math.sin(i)),at(x-.027,-.106,.238+.011*i),
                    at(x-.046,-.071,.212+.011*i)],
                   [.035,.048,.037,.019,.001],"hair" if i%3 else "hairdark","head")
        if swift:
            # The braid is sculpted from interlocking folds, carried by its own swing bone.
            points=[(-.103,.143,.294),(-.112,.209,.377),(-.149,.275,.422),(-.194,.329,.399),
                    (-.239,.382,.414),(-.275,.423,.385),(-.291,.459,.343),(-.274,.485,.307)]
            cord("Braided hair spine",[at(*p) for p in points],.026,"hair","hair.R")
            for i,(x,y,z) in enumerate(points[1:-1]):
                for j in (-1,1):
                    blob(f"Interlaced braid fold {i+1} {j}",at(x+j*.022,y-.005*j,z+j*.008),
                         (.047-i*.003,.040-i*.002,.045-i*.003),"hair" if (i+j)%3 else "hairlight",
                         "hair.R",tilt=j*.62)
            blob("Braid cloth tie",at(*points[-2]),(.03,.032,.029),"rust","hair.R")
            strand("Split end of braid",[at(*p) for p in points[-2:]]+[at(-.305,.511,.299),at(-.324,.521,.314)],
                   [.022,.032,.018,.002],"hair","hair.R")
            strand("Escaped temple lock",[at(.116,.012,.268),at(.147,-.031,.217),at(.097,-.105,.183),at(.112,-.101,.147)],
                   [.029,.019,.011,.001],"hair","head")
        else:
            for side,s in ((-1,"R"),(1,"L")):
                for i in range(7):
                    y=-.045+i*.034
                    p=[at(side*.093,y,.302),at(side*(.178+i*.006),y+.014,.241),
                       at(side*(.174+i*.008),y+.058,.159),
                       at(side*(.190+i*.009),y+.069,.068-.022*i),
                       at(side*(.214+i*.006),y+.132+.009*(i%3),.080-.028*i),
                       at(side*(.188+i*.010),y+.169+.017*(i%3),.100-.026*i)]
                    strand(f"Windblown side lock {s} {i+1}",p,[.039,.044,.038,.028,.019,.002],
                           "hair" if i%3 else "hairdark","hair."+s)
            strand("Loose brow curl",[at(-.051,-.102,.301),at(-.122,-.126,.248),at(-.124,-.149,.207),
                   at(-.092,-.146,.179),at(-.115,-.124,.150)],[.030,.026,.016,.010,.001],"hairlight","head",highlights=False)


def limbs():
    for s,sign in (("R",-1),("L",1)):
        arm,fore,hand,thigh,shin,foot=(key+"."+s for key in ("upper_arm","forearm","hand","thigh","shin","foot"))
        a,b=rest[arm]
        m=1.12 if guard else .77 if swift else 1
        segment("Shaped upper arm "+s,a,b,[(f,rx*m,ry*m) for f,rx,ry in [
            (-.11,.071,.076),(.04,.101,.103),(.30,.094,.097),(.57,.081,.083),(.82,.058,.065),(1.10,.050,.050)]],
                "skin",arm)
        length=.79 if guard else .45 if swift else .29
        segment("Pressed work sleeve "+s,a,a.lerp(b,length),[(f,rx*m,ry*m) for f,rx,ry in [
            (-.30,.064,.069),(-.18,.109,.109),(.23,.121,.123),(.63,.107,.111),(.90,.107,.110),
            (1.03,.104,.111),(1.13,.086,.093)]],"undyed",arm)
        for i in range(2):
            f=length*(.81+.18*i)
            segment(f"Rolled cuff fold {s} {i+1}",a.lerp(b,f),a.lerp(b,f+.08),
                [(0,.091*m,.101*m),(.22,.115*m,.118*m),(.83,.110*m,.115*m),(1,.091*m,.102*m)],
                "wool" if i==0 else "undyed",arm,n=12)
        a,b=rest[fore]
        segment("Tapered forearm "+s,a,b,[(f,rx*m,ry*m) for f,rx,ry in [
            (-.115,.045,.052),(.01,.064,.069),(.24,.073,.081),(.54,.065,.068),(.96,.041,.049),(1.08,.039,.044)]],
                "skin",fore)
        start=.37 if guard else .56 if not swift else .66
        segment("Layered forearm bracer "+s,a.lerp(b,start),a.lerp(b,1.015),[
            (0,.061*m,.067*m),(.12,.070*m,.077*m),(.45,.063*m,.070*m),(.87,.055*m,.059*m),(1,.041*m,.050*m)],
            "belt",fore)
        for i in range(3):
            f=start+(1-start)*(.17+i*.29)
            mx=(.077-.009*i)*m
            segment("Overbound cuff "+s+str(i),a.lerp(b,f),a.lerp(b,f+.051),
                [(0,mx*.95,mx),(.20,mx,mx*1.07),(.86,mx,mx*1.07),(1,mx*.96,mx)],
                "thread" if i==1 and swift else "boot",fore,sub=0)
        make_hand(s,sign,hand)
        a,b=rest[thigh]
        t=1.19 if guard else .78 if swift else 1.02
        segment("Full-cut slop trousers "+s,a,b,[(f,rx*t,ry*t) for f,rx,ry in [
            (-.15,.094,.097),(-.03,.134,.130),(.18,.142,.135),(.39,.132,.122),(.54,.107,.117),
            (.69,.117,.107),(.80,.092,.101),(.99,.079,.077),(1.10,.066,.065)]],"trouser",thigh,n=16)
        patch(s,t,thigh,a,b)
        a,b=rest[shin]
        segment("Layered gaiter "+s,a,b,[(f,rx*t,ry*t) for f,rx,ry in [
            (-.110,.073,.076),(.04,.087,.085),(.26,.094,.097),(.50,.078,.082),
            (.76,.069,.078),(1.0,.067,.071),(1.08,.067,.072)]],"wool",shin,n=14)
        for i in range(4 if swift else 3):
            f=.30+i*.147
            r=(.098-.009*i)*t
            segment("Calf wrap "+s+str(i),a.lerp(b,f),a.lerp(b,f+.069),
                    [(0,r*.93,r*.96),(.15,r,r*1.05),(.83,r,r*1.05),(1,r*.92,r*.96)],
                    "undyed" if swift else "belt",shin,sub=0)
        boot(foot,s,t)


def make_hand(s, sign, bone):
    pivot=rest[bone][0]
    def p(forward,y,z):
        return pivot+V((sign*forward,y,z))
    sx=.91 if swift else 1.08 if guard else 1
    segment("Palm with metacarpal taper "+s,p(-.012,0,0),p(.137,0,0),
            [(f,a*sx,b*sx) for f,a,b in [(0,.035,.033),(.22,.046,.037),(.45,.050,.036),(.68,.047,.035),(1,.036,.023)]],
            "skin",bone)
    for i in range(4):
        y=(-.035+i*.023)*sx
        end=(.124,.143,.139,.121)[i]
        if swift and s=="L":
            spread=(-.031,-.011,.011,.031)[i]
            cord("Splayed balancing finger "+str(i),[p(.087,y,.007),p(end-.003,y+spread*.46,-.008),
                 p(end+.026,y+spread,-.017-.005*i)],.0105,"skin",bone)
            continue
        cord("Curling gripping finger "+s+str(i),[p(.083,y,.019),p(end,y,.014),p(end+.012,y,-.013),
             p(end-.006,y,-.033),p(.080,y,-.029)],.013*sx,"skin",bone)
        cord("Finger crease "+s+str(i),[p(end+.009,y-.007,-.012),p(end+.011,y+.003,-.011)],.0028,"flush",bone)
    thumb_end=p(.075,-.080,-.031) if swift and s=="L" else p(.104,-.039,-.027)
    cord("Opposing thumb "+s,[p(.034,-.027,.018),p(.050,-.049,.003),p(.070,-.055,-.022),thumb_end],
         .019*sx,"skin",bone)


def patch(s,scale,bone,a,b):
    x,y,z=a.lerp(b,.48)
    if s=="R":
        y-=scale*.103
        shape=[(-.063,.049),(-.039,.076),(.060,.061),(.067,.018),(.050,-.040),(.029,-.062),
               (.007,-.054),(-.035,-.070),(-.060,-.037)]
        plate("Shared crudely repaired knee patch",[(x+u*scale,y,z+v) for u,v in shape],"patch",bone,.023,.007)
        cord("Patch split",[(x-.049*scale,y-.015,z+.009),(x,y-.019,z-.004),(x+.042*scale,y-.014,z-.014)],.004,"belt",bone)
        for i in (-1,0,1):
            u=.027*i*scale
            cord("Rough patch staple "+str(i),[(x+u-.011,y-.015,z+.021-i*.006),(x+u+.007,y-.026,z+.004-i*.006),
                 (x+u+.012,y-.015,z-.019-i*.006)],.006,"belt",bone)
    else:
        cord("Torn trouser side seam "+s,[(x+.053,y-.097*scale,z+.105),(x+.087,y-.083*scale,z+.010),
             (x+.066,y-.081*scale,z-.079)],.005,"wool",bone)


def boot(bone,s,t):
    x,_,_=rest[bone][0]
    w=.085*(.86 if swift else 1.17 if guard else 1)
    layers=[
        (.024,-.064,w,.184),(.029,-.066,w*1.10,.189),(.052,-.067,w*1.11,.190),
        (.073,-.067,w*1.03,.185),(.096,-.067,w,.173),(.119,-.027,w*.97,.135),
        (.151,.001,w*.86,.098),(.204,.014,w*.83,.089),(.231,.014,w*.78,.077),
    ]
    loft("Stitched planted work boot "+s,[((x,y,z),a,b) for z,y,a,b in layers],"boot",bone,n=18)
    loft("Grouped sole and heel "+s,[((x,y,z),a,b) for z,y,a,b in layers[:4]],"sole",bone,n=18,sub=0)
    cord("Toe-cap needle seam "+s,[(x+w*math.cos(a),-.116-.124*math.sin(a),.088+.017*math.sin(a))
         for a in (0,.36,.73,1.12,1.57,2.03,2.51,2.82,3.14)],.0047,"thread",bone)
    for j in range(2 if not swift else 1):
        z=.133+j*.055
        cord("Boot crossing belt "+s+str(j),[(x-w*.88,-.077,z+.009),(x,-.123+j*.040,z+.006),
             (x+w*.77,-.065,z-.010)],.012,"belt",bone)
        q=x-.037
        yy=-.116+j*.028
        cord("Boot buckle "+s+str(j),[(q+.018*math.cos(a),yy-.004*math.sin(a),z+.018*math.sin(a))
             for a in (0,.8,1.6,2.36,3.14,3.93,4.71,5.49,math.tau)],.006,"gold",bone)


def gear():
    if guard:
        shield()
        club()
        return
    # Props are separate child collections bound to independently editable grip mounts.
    bone="grip.R"
    center=rest[bone][0]
    p=lambda x,y,z:center+V((x,y,z))
    if swift:
        a,b=p(0,-.103,0),p(0,.105,0)
        segment("Knife wood grip",a,b,[(0,.018,.022),(.13,.024,.026),(.81,.022,.024),(1,.021,.022)],
                "wood",bone)
        for i in range(5):
            t=.16+i*.139
            segment("Knife grip bands "+str(i),a.lerp(b,t),a.lerp(b,t+.06),
                    [(0,.023,.026),(1,.022,.026)],"thread",bone,sub=0)
        plate("Forged knife quillon", [p(x,y,0) for x,y in [(-.055,.071),(.066,.068),(.076,.086),(.050,.102),(-.063,.102)]],
              "iron",bone,.033,.009,outward=(0,0,1))
        outline=[(-.042,.093),(-.043,.237),(-.022,.342),(.008,.395),(.027,.320),(.042,.21),(.030,.123)]
        plate("Leaf-shaped working blade", [p(x,y,.012) for x,y in outline],"edge",bone,.019,.004,outward=(0,0,1))
        plate("Spine of knife", [p(x,y,.022) for x,y in [(-.028,.102),(-.034,.21),(-.013,.329),(.009,.374),(.011,.235),(.014,.108)]],
             "iron",bone,.005,.002,outward=(0,0,1))
    else:
        a,b=p(0,-.19,.005),p(0,.66,.005)
        segment("Hand-hewn ash axe haft",a,b,[(0,.029,.026),(.02,.037,.036),(.115,.029,.032),
            (.32,.028,.029),(.55,.031,.032),(.76,.034,.035),(.94,.035,.033),(1,.032,.031)],"wood",bone,n=9)
        for i in range(13):
            t=.11+i*.048
            segment("Axe grip winding "+str(i),a.lerp(b,t),a.lerp(b,t+.026),
                [(0,.030,.034),(1,.031,.034)],"thread" if i%3 else "belt",bone,n=9,sub=0)
        # Asymmetric hewing blade with a hooked beard; normal broadside is Z.
        outline=[(-.038,.500),(-.050,.612),(.057,.633),(.138,.657),(.194,.707),(.221,.670),
                 (.257,.595),(.262,.545),(.243,.482),(.214,.442),(.174,.417),(.144,.401),
                 (.110,.413),(.115,.464),(.135,.489),(.078,.502)]
        plate("Forged bearded iron axe", [p(x,y,.003) for x,y in outline],"iron",bone,.058,.009,outward=(0,0,1))
        edge=[outline[j] for j in range(4,13)]+[(.179,.444),(.213,.509),(.223,.557),(.202,.619)]
        plate("Exposed bright axe cutting bevel",[p(x,y,.033) for x,y in edge],"edge",bone,.013,.004,outward=(0,0,1))
        for j in range(3):
            q=outline[6+j]
            cord("Forging scratch "+str(j),[p(q[0]-.027,q[1],.041),p(q[0]-.008,q[1]-.012,.041)],.0023,"iron",bone)


def shield():
    bone="grip.R"
    center=rest[bone][0]
    p=lambda x,y,z:center+V((x,y,z))
    n=36
    radial=[]
    for z,rx,ry in [(.026,.224,.250),(.038,.254,.284),(.067,.257,.285),
                     (.079,.246,.275),(.101,.224,.250),(.120,.149,.169),(.127,.068,.077)]:
        radial.extend(p(rx*math.cos(a)*(1+.021*math.cos(5*a)),ry*math.sin(a),z) for a in (math.tau*i/n for i in range(n)))
    disk=mesh("Dished, hammered iron buckler",radial,bridge(n,7),"iron",bone)
    disk.data.materials.append(mats["edge"])
    disk.data.materials.append(mats["boot"])
    for i, face in enumerate(disk.data.polygons):
        face.material_index=1 if n+1<=i<=3*n else 2 if i<=n else 0
    cord("Raised buckler ring",[p(.244*math.cos(a),.273*math.sin(a),.078) for a in (math.tau*i/n for i in range(n+1))],
         .014,"gold",bone)
    cord("Inset chased iron ring",[p(.203*math.cos(a),.226*math.sin(a),.105) for a in (math.tau*i/n for i in range(n+1))],
         .007,"edge",bone)
    for i in range(12):
        a=math.tau*(i+.25)/12
        blob("Hand-peened buckler rivet "+str(i),p(.224*math.cos(a),.249*math.sin(a),.104),
             (.014,.014,.010),"gold",bone,sub=0)
    blob("Buckler boss",p(0,0,.147),(.077,.084,.058),"gold",bone,n=16)
    blob("Boss bright center",p(-.009,.007,.185),(.038,.045,.024),"edge",bone)
    for i in range(5):
        x=rng.uniform(-.15,.14)
        y=rng.uniform(-.16,.15)
        if abs(x)+abs(y)<.12:
            y-=.10
        cord("Old blade scrape "+str(i),[p(x-.020,y-.032,.126),p(x,y,.132),p(x+.010,y+.018,.129)],
             .003,"edge",bone)
    cord("Buckler inside handle",[p(-.092,0,.045),p(-.052,0,-.021),p(.050,0,-.021),p(.093,0,.044)],
         .017,"wood",bone)


def club():
    bone="grip.L"
    center=rest[bone][0]
    p=lambda x,y,z:center+V((x,y,z))
    a,b=p(0,-.118,0),p(0,.449,0)
    segment("Tapered knotted cudgel",a,b,[(0,.021,.022),(.04,.025,.028),(.31,.027,.029),
            (.48,.035,.039),(.76,.050,.044),(.90,.054,.052),(.98,.049,.047),(1,.042,.037)],
            "wood",bone,n=11)
    for i,d in enumerate((.68,.83,.91)):
        segment("Cudgel iron ferrule "+str(i),a.lerp(b,d),a.lerp(b,d+.05),
                 [(0,.049+i*.002,.047+i*.003),(1,.047+i*.002,.046+i*.003)],"iron",bone,n=11,sub=0)
    cord("Cudgel wood grain",[p(.02,.09,.030),p(.029,.19,.033),p(.035,.30,.033),p(.042,.43,.033)],.003,"thread",bone)


def attach(rig):
    for ob,bone in bindings:
        if bone=="weighted":
            pb,cb=(ob.vertex_groups.new(name=k) for k in ("pelvis","chest"))
            for vert in ob.data.vertices:
                f=max(0,min(1,(vert.co.z-hip_z-.119)/.176))
                if f<1:
                    pb.add([vert.index],1-f,"REPLACE")
                if f>0:
                    cb.add([vert.index],f,"REPLACE")
            deform=ob.modifiers.new("Continuous waist deformation","ARMATURE")
            deform.object=rig
            deform.use_deform_preserve_volume=True
            ob.parent=rig
        else:
            ob.parent=rig
            ob.parent_type="BONE"
            ob.parent_bone=bone
            transform=rig.data.bones[bone].matrix_local @ Matrix.Translation((0,rig.data.bones[bone].length,0))
            ob.matrix_parent_inverse=transform.inverted()


def preview_camera():
    data=bpy.data.cameras.new("Cast three-quarter preview")
    obj=bpy.data.objects.new("Cast three-quarter preview",data)
    collection.objects.link(obj)
    obj.rotation_euler=(1.150829196,0,-.435386419)
    data.type="ORTHO"
    data.ortho_scale=3.05
    obj.location=obj.rotation_euler.to_matrix()@V((0,.84,6))
    scene.camera=obj


def build():
    global role,title,width,hip_z,shoulder,chin,upper,lower,waist,head_size,guard,swift,scene,collection,rng,mats,bindings,rest
    role,out=sys.argv[sys.argv.index("--")+1:]
    output=Path(out)
    if not output.is_absolute() or output.exists():
        raise ValueError("Pass an absolute, nonexistent .blend destination")
    title,width,hip_z,shoulder,chin,upper,lower,waist,head_size=VARIANTS[role]
    guard,swift=role=="bandit_guard",role=="bandit_swift"
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene=bpy.context.scene
    scene.name="Last One Standing · "+title
    scene.unit_settings.system="METRIC"
    scene.render.fps=24
    scene["Concept SHA-256"]="f71417d10728115de4c5a7d0c7793224e92bc2e2a347edc3469eedd2cbef4843"
    scene["Reader"]="Barnaby’s Order of Last Resort. Native art candidate, no runtime wiring."
    rng=random.Random(541+list(VARIANTS).index(role))
    mats={k:pigment(k,v) for k,v in COLORS.items()}
    bindings,rest=[],{}
    collection=group("01 · Editable FK armature")
    rig=rig_setup()
    for name,builder in (("02 · Tailoring and kit",clothes),("03 · Fur and cloth",drapery),("04 · Face and hair",head),
                         ("05 · Limbs and boots",limbs),("06 · Mounted gear",gear)):
        collection=group(name)
        builder()
    attach(rig)
    collection=group("07 · Framing guide")
    preview_camera()
    animate(scene,rig,rest,role,title)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(output),compress=True)


build()
