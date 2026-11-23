"""Author the Harpooner candidate in Blender, from an empty file."""

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


V = Vector
PI = math.pi
rng = random.Random(513)
scene = bpy.context.scene
rest = {}
geometry = []
groups = {}
materials = {}


def collection(name):
    group = bpy.data.collections.new(name)
    scene.collection.children.link(group)
    groups[name] = group
    return group


def pigment(name, dark, light, grit=62, metal=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*light, 1)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    link = mat.node_tree.links.new
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = .83 - .28 * metal
    bsdf.inputs["Metallic"].default_value = metal
    coord = nodes.new("ShaderNodeTexCoord")
    coord.location = -750, 0
    wash = nodes.new("ShaderNodeTexNoise")
    wash.location = -530, 80
    wash.inputs["Scale"].default_value = 8
    wash.inputs["Detail"].default_value = 3
    link(coord.outputs["Generated"], wash.inputs["Vector"])
    grains = nodes.new("ShaderNodeTexNoise")
    grains.location = -530, -175
    grains.inputs["Scale"].default_value = grit
    grains.inputs["Roughness"].default_value = .72
    link(coord.outputs["Generated"], grains.inputs["Vector"])
    mix = nodes.new("ShaderNodeMath")
    mix.operation = "MULTIPLY"
    mix.location = -320, 60
    link(wash.outputs["Fac"], mix.inputs[0])
    link(grains.outputs["Fac"], mix.inputs[1])
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.location = -150, 95
    ramp.color_ramp.elements[0].position = .075
    ramp.color_ramp.elements[0].color = (*dark, 1)
    ramp.color_ramp.elements[1].position = .43
    ramp.color_ramp.elements[1].color = (*light, 1)
    link(mix.outputs[0], ramp.inputs[0])
    link(ramp.outputs[0], bsdf.inputs["Base Color"])
    bump = nodes.new("ShaderNodeBump")
    bump.location = 20, -135
    bump.inputs["Strength"].default_value = .17
    bump.inputs["Distance"].default_value = .007
    link(grains.outputs["Fac"], bump.inputs["Height"])
    link(bump.outputs[0], bsdf.inputs["Normal"])
    bsdf.location = 240, 120
    nodes.get("Material Output").location = 525, 120
    return mat


def load_materials():
    colors = {
        "umber": ((.046,.027,.02),(.29,.16,.069)),
        "oilskin": ((.123,.045,.013),(.56,.274,.075)),
        "ochre": ((.29,.116,.028),(.80,.445,.119)),
        "lining": ((.032,.019,.016),(.15,.091,.06)),
        "hood": ((.016,.018,.027),(.072,.077,.121)),
        "hood_edge": ((.026,.025,.034),(.132,.141,.188)),
        "scarf": ((.123,.016,.014),(.477,.077,.048)),
        "russet": ((.090,.028,.017),(.387,.137,.055)),
        "patch": ((.181,.08,.03),(.505,.269,.10)),
        "linen": ((.22,.15,.10),(.69,.519,.344)),
        "skin": ((.27,.132,.078),(.715,.432,.267)),
        "flush": ((.225,.091,.048),(.65,.332,.188)),
        "stubble": ((.115,.072,.05),(.387,.251,.162)),
        "hair": ((.022,.012,.009),(.120,.066,.038)),
        "eye": ((.47,.36,.249),(.836,.762,.605)),
        "iris": ((.017,.023,.016),(.092,.112,.070)),
        "ink": ((.010,.006,.006),(.046,.028,.019)),
        "boot": ((.04,.025,.018),(.188,.120,.076)),
        "belt": ((.051,.027,.015),(.229,.123,.060)),
        "bag": ((.154,.082,.035),(.50,.317,.15)),
        "thread": ((.21,.117,.062),(.637,.445,.261)),
        "gold": ((.16,.076,.025),(.543,.341,.13)),
        "wood": ((.03,.015,.009),(.159,.082,.044)),
        "iron": ((.10,.084,.079),(.37,.341,.304)),
        "edge": ((.239,.21,.181),(.67,.619,.537)),
    }
    for name, (dark, light) in colors.items():
        materials[name] = pigment(name, dark, light, metal=.42 if name in ("gold","iron","edge") else 0)


def mesh(name, verts, faces, mat, group, bind=None, smooth=True, subs=0):
    data = bpy.data.meshes.new(name)
    data.from_pydata(verts, [], faces)
    data.update()
    ob = bpy.data.objects.new(name, data)
    group.objects.link(ob)
    for key in (mat,) if isinstance(mat,str) else mat:
        data.materials.append(materials[key])
    for poly in data.polygons:
        poly.use_smooth = smooth
    if subs:
        mod = ob.modifiers.new("Soft shape", "SUBSURF")
        mod.levels = mod.render_levels = subs
    if bind:
        geometry.append((ob, bind))
    return ob


def loft(name, rings, mat, group, bind=None, count=12, axis=(0,0,1), subs=1, irregular=.019):
    """Elliptic cross-sections with no isolated end vertices."""
    w = V(axis).normalized()
    u = (V((1,0,0)) if abs(w.x)<.91 else V((0,1,0)))
    u = (u-u.dot(w)*w).normalized()
    v = w.cross(u)
    verts = []
    phase = rng.uniform(0,2*PI)
    for ring, (c, a, b) in enumerate(rings):
        for j in range(count):
            t = 2*PI*j/count
            r = 1+irregular*(math.sin(3*t+phase)+.55*math.sin(5*t+.6*ring))
            verts.append(V(c)+r*(a*math.cos(t)*u+b*math.sin(t)*v))
    faces = [tuple(reversed(range(count)))]
    for i in range(len(rings)-1):
        for j in range(count):
            a,b = i*count+j,i*count+(j+1)%count
            faces.append((a,b,b+count,a+count))
    faces.append(tuple(range(len(verts)-count,len(verts))))
    return mesh(name, verts, faces, mat, group, bind, subs=subs)


def blob(name, c, dims, mat, group, bind=None, *, tilt=0, subs=1):
    center = V(c)
    rotation = Matrix.Rotation(tilt, 3, "Y")
    rings = []
    for angle in (-86,-67,-40,-13,13,40,67,86):
        t = math.radians(angle)
        rings.append((center+rotation @ V((0,0,dims[2]*math.sin(t))),dims[0]*math.cos(t),dims[1]*math.cos(t)))
    return loft(name,rings,mat,group,bind,count=12,axis=rotation @ V((0,0,1)),subs=subs)


def along(name, a, b, radii, mat, group, bind, *, count=10, subs=1):
    a,b = V(a),V(b)
    return loft(name, [(a.lerp(b,t),u,v) for t,u,v in radii],mat,group,bind,count=count,axis=b-a,subs=subs)


def seam(name, pts, radius, mat, group, bind):
    data = bpy.data.curves.new(name,"CURVE")
    data.dimensions = "3D"
    data.resolution_u = 5
    data.bevel_depth = radius
    data.bevel_resolution = 2
    data.use_fill_caps = True
    spl = data.splines.new("BEZIER")
    spl.bezier_points.add(len(pts)-1)
    for bp, p in zip(spl.bezier_points,pts):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = "AUTO"
    ob = bpy.data.objects.new(name,data)
    group.objects.link(ob)
    data.materials.append(materials[mat])
    geometry.append((ob,bind))
    return ob


def cloth(name, verts, faces, mat, group, bind, *, thickness=.012, sub=1):
    ob = mesh(name, verts, faces, mat, group, bind, subs=sub)
    mod = ob.modifiers.new("Turned cloth edge", "SOLIDIFY")
    mod.thickness = thickness
    if isinstance(mat,tuple):
        mod.material_offset = mod.material_offset_rim = 1
    return ob


def trim(name, x, y, z, width, height, mat, group, bone):
    points = [(x-width/2,y,z-height/2),(x-width/2,y,z+height/2),
              (x+width/2,y,z+height/2),(x+width/2,y,z-height/2),
              (x-width/2,y,z-height/2)]
    ob = seam(name,points,.007,mat,group,bone)
    for point in ob.data.splines[0].bezier_points:
        point.handle_left_type = point.handle_right_type = "VECTOR"
    return ob


def make_rig(group):
    arm = bpy.data.armatures.new("Harpooner skeleton")
    rig = bpy.data.objects.new("Harpooner_Rig",arm)
    group.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    rig.show_in_front = True
    arm.display_type = "STICK"
    bpy.ops.object.mode_set(mode="EDIT")
    assign = {}

    def add(name,a,b,parent=None, category="Body"):
        edit = arm.edit_bones.new(name)
        edit.head,edit.tail = a,b
        if parent:
            edit.parent = arm.edit_bones[parent]
        edit.align_roll(V((0,0,1)))
        rest[name] = (V(a),V(b))
        assign[name] = category

    add("root",(0,0,0),(0,-.20,0))
    add("pelvis",(0,.009,.96),(0,.009,1.17),"root")
    add("chest",(0,.009,1.17),(0,-.006,1.53),"pelvis")
    add("neck",(0,-.006,1.53),(0,-.004,1.675),"chest")
    add("head",(0,-.004,1.675),(0,-.004,1.976),"neck")
    add("cape",(-.06,.105,1.59),(-.12,.25,1.18),"chest","Secondary")
    add("scarf",(-.045,-.13,1.55),(-.065,-.15,1.17),"chest","Secondary")
    add("satchel",(-.19,-.038,1.131),(-.23,-.127,.94),"pelvis","Secondary")
    add("harpoon",(0,-.30,.70),(0,.10,.70),"root","Prop")
    add("coat_tail",(.035,.105,1.10),(.08,.155,.83),"pelvis","Secondary")
    for side,s in (("R",-1),("L",1)):
        def limb(key,a,b,parent,category="Limbs"):
            add(key+"."+side,(s*a[0],a[1],a[2]),(s*b[0],b[1],b[2]),parent,category)
        limb("upper_arm",(.216,0,1.51),(.482,0,1.51),"chest")
        limb("forearm",(.482,0,1.51),(.749,0,1.51),"upper_arm."+side)
        limb("hand",(.749,0,1.51),(.864,0,1.51),"forearm."+side)
        limb("thigh",(.110,.011,.972),(.121,-.026,.555),"pelvis")
        limb("shin",(.121,-.026,.555),(.125,.013,.117),"thigh."+side)
        limb("foot",(.125,.013,.117),(.125,-.144,.068),"shin."+side)
        for i,(y,z) in enumerate(((-.028,.01),(-.01,.013),(.012,.011),(.031,.007))):
            l = (.064,.077,.071,.054)[i]
            limb(f"finger{i}",(.825,y,1.51+z),(.825+l,y,1.51+z),"hand."+side,"Hands")
        limb("thumb",(.776,-.023,1.509),(.820,-.058,1.487),"hand."+side,"Hands")
    bpy.ops.object.mode_set(mode="OBJECT")
    buckets = {k: arm.collections.new(k) for k in dict.fromkeys(assign.values())}
    for bone in arm.bones:
        buckets[assign[bone.name]].assign(bone)
        bone.use_deform = assign[bone.name] != "Prop" and bone.name != "root"
        rig.pose.bones[bone.name].rotation_mode = "QUATERNION"
    buckets["Hands"].is_visible = False
    return rig


def torso(group):
    segments = [
        ((0,.018,.895),.133,.094), ((0,.003,.935),.181,.108),
        ((0,.004,1.034),.188,.123), ((0,.008,1.125),.161,.106),
        ((0,.008,1.206),.159,.109), ((0,.005,1.30),.176,.129),
        ((0,0,1.415),.211,.136), ((0,.004,1.510),.225,.120),
        ((0,.002,1.552),.180,.103), ((0,-.003,1.574),.115,.076),
    ]
    loft("Shaped wool jerkin",segments,"umber",group,"skin_torso",count=20)
    loft("Russet doublet facing",[
        ((0,-.004,1.10),.165,.115),((0,-.003,1.123),.163,.118),
        ((0,-.000,1.27),.179,.135),((0,-.012,1.444),.206,.137),
        ((0,-.014,1.525),.183,.114),((0,-.015,1.541),.174,.104),
    ],"russet",group,"chest",count=20)
    for i, offset in enumerate((0,.018,.038)):
        seam(f"Overlapped front edge {i+1}",[(.055+offset,-.128,1.16),(.038+offset,-.153,1.28),
            (.025+offset,-.162,1.40),(-.025+offset,-.126,1.53)],.006 if i==0 else .003,
            "belt" if i==0 else "thread",group,"chest")
    for i in range(4):
        blob(f"Doublet tie {i+1}",(.019-i*.008,-.153,1.22+i*.067),(.019,.012,.009),"thread",group,"chest")
    loft("Broad work belt", [((0,.002,z),a,b) for z,a,b in (
        (1.049,.186,.128),(1.056,.194,.131),(1.115,.174,.117),(1.120,.170,.116))],
        "belt",group,"pelvis",count=20,subs=0)
    trim("Squared brass buckle",-.018,-.139,1.084,.068,.046,"gold",group,"pelvis")
    seam("Buckle pin", [(-.045,-.145,1.082),(.007,-.146,1.081)],.006,"gold",group,"pelvis")
    for i in range(3):
        blob(f"Belt eyelet {i+1}",(.056+i*.025,-.125+i*.004,1.083),(.006,.004,.006),"ink",group,"pelvis")
    cloth("Split brown coat-tail",[
        (-.172,.108,1.135),(.014,.143,1.113),(.171,.092,1.134),
        (-.181,.144,1.014),(.017,.169,.988),(.206,.130,.998),
        (-.192,.172,.918),(-.081,.201,.866),(.015,.166,.950),
        (.119,.182,.833),(.198,.152,.903)],
        [(0,1,4,3),(1,2,5,4),(3,4,8,7,6),(4,5,10,9,8)],("umber","lining"),group,"coat_tail",sub=1)
    loft("Work shoulder collar",[
        ((0,0,1.522),.119,.102),((0,-.008,1.549),.129,.115),
        ((0,-.01,1.576),.122,.101),((0,-.012,1.607),.101,.085),
        ((0,-.005,1.622),.083,.076)],"scarf",group,"chest",count=20)
    blob("Scarf knot",(-.046,-.114,1.568),(.068,.043,.038),"scarf",group,"chest",tilt=-.3)
    for i in range(2):
        off = i*.050
        points = [(-.075+off,-.146,1.57),(-.024+off,-.147,1.56),(-.075+off,-.156,1.44),
                  (-.022+off,-.160,1.40),(-.112+off,-.147,1.26),(-.062+off,-.149,1.25),
                  (-.134+off,-.137,1.19-i*.05),(-.096+off,-.145,1.175-i*.05)]
        cloth(f"Split oxblood neckerchief {i+1}",points,[(0,1,3,2),(2,3,5,4),(4,5,7,6)],
              ("scarf","lining"),group,"scarf",thickness=.009)


def head(group):
    loft("Neck",[
        ((0,.006,1.522),.079,.071),((0,-.003,1.544),.084,.075),
        ((0,-.015,1.648),.076,.067),((0,-.006,1.718),.081,.068),
    ],"skin",group,"neck",count=16)
    rings = [
        ((.008,-.038,1.645),.042,.047),((.008,-.059,1.665),.073,.079),
        ((.004,-.043,1.710),.091,.094),((.001,-.023,1.755),.103,.113),
        ((-.007,-.017,1.808),.108,.115),((-.008,.000,1.855),.108,.109),
        ((-.012,.013,1.910),.101,.099),((-.015,.022,1.948),.083,.076),
        ((-.009,.030,1.963),.049,.046),
    ]
    loft("Tall angular face",rings,"skin",group,"head",count=24,irregular=.037)
    blob("Shade at chin",(.011,-.097,1.68),(.073,.050,.042),"stubble",group,"head",tilt=-.09)
    blob("Chin plane",(.013,-.13,1.688),(.052,.022,.025),"skin",group,"head")
    loft("Hooked nose",[
        ((.010,-.124,1.772),.024,.022),((.017,-.145,1.780),.031,.031),
        ((.021,-.170,1.797),.030,.038),((.010,-.148,1.816),.019,.033),
        ((.000,-.119,1.853),.017,.016),((-.006,-.111,1.864),.011,.012),
    ],"flush",group,"head",count=12)
    for side,s in (("R",-1),("L",1)):
        blob("Ear "+side,(s*.101,.002,1.768),(.026,.037,.05),"flush",group,"head",tilt=s*.32)
        blob("Ear interior "+side,(s*.108,-.026,1.771),(.015,.01,.024),"stubble",group,"head")
        blob("Weathered cheek "+side,(s*.068,-.093,1.769),(.037,.027,.034),"flush",group,"head",tilt=s*.32)
        x = s*.049
        blob("Small eye "+side,(x,-.111,1.825),(.032,.020,.015),"eye",group,"head",tilt=s*.10)
        blob("Hazel iris "+side,(x+.005,-.130,1.826),(.012,.005,.013),"iris",group,"head")
        blob("Pupil "+side,(x+.007,-.134,1.826),(.005,.002,.007),"ink",group,"head")
        seam("Upper lid "+side,[(x-.030,-.114,1.829),(x-.012,-.129,1.838),
            (x+.010,-.132,1.839),(x+.030,-.110,1.830)],.0035,"stubble",group,"head")
        seam("Sidelong brow "+side,[(x-.040,-.109,1.856),(x-.019,-.124,1.865+(s*.003)),
            (x+.008,-.126,1.864),(x+.038,-.106,1.851)],.007,"hair",group,"head")
        blob("Nostril "+side,(.019+s*.018,-.172,1.787),(.007,.009,.0035),"stubble",group,"head")
        seam("Cheek crease "+side,[(x+s*.023,-.105,1.771),(x+s*.013,-.123,1.758),
            (x+s*.010,-.119,1.749)],.002,"stubble",group,"head")
    seam("Pressed mouth",[(-.040,-.128,1.727),(-.012,-.149,1.726),
        (.017,-.152,1.731),(.054,-.123,1.727)],.004,"stubble",group,"head")
    seam("Lower lip",[(-.020,-.143,1.718),(.012,-.149,1.718),(.034,-.140,1.721)],
         .003,"flush",group,"head")
    for i in range(28):
        x = rng.uniform(-.065,.071)
        z = rng.uniform(1.66,1.728)
        y = -.142 + .055*(x/.08)**2 + .026*abs(z-1.690)/.04
        seam(f"Beard fleck {i+1}",[(x,y-.002,z),(x+.002,y+.001,z+.004)],.0013,
             "stubble",group,"head")
    for i, pts in enumerate((
        [(-.070,-.074,1.932),(-.083,-.125,1.913),(-.091,-.121,1.870),(-.105,-.095,1.831)],
        [(-.045,-.090,1.957),(-.056,-.119,1.930),(-.045,-.139,1.906),(-.060,-.141,1.867)],
        [( .016,-.083,1.958),( .021,-.131,1.939),( .040,-.139,1.922),( .059,-.127,1.899)],
        [( .059,-.075,1.945),( .079,-.112,1.923),( .106,-.121,1.915),( .134,-.090,1.891)],
        [( .089,-.034,1.933),( .115,-.077,1.893),( .130,-.105,1.877),( .112,-.119,1.853)],
        [(-.129,.029,1.873),(-.128,-.005,1.816),(-.118,-.032,1.791),(-.120,-.024,1.774)],
    )):
        seam(f"Escaped lock {i+1}",pts,.013 if i<5 else .011,"hair",group,"head")


def mantle(group):
    # Cut-away hood, with a peaked top and a deeper nape behind the visible face.
    sections = [
        [(-.116,.001,1.684),(-.113,-.023,1.789),(-.113,-.064,1.879),
         (-.100,-.088,1.936),(-.053,-.112,1.974),(.008,-.116,1.995),
         (.066,-.090,1.961),(.124,-.038,1.866),(.117,.008,1.734)],
        [(-.148,.083,1.669),(-.153,.048,1.761),(-.147,.027,1.872),
         (-.133,-.017,1.982),(-.069,-.029,2.025),(.010,-.030,2.035),
         (.092,.000,1.976),(.149,.058,1.860),(.150,.082,1.716)],
        [(-.094,.142,1.659),(-.125,.163,1.749),(-.131,.134,1.857),
         (-.116,.110,1.936),(-.080,.079,2.037),(-.027,.094,2.024),
         (.072,.106,1.997),(.128,.135,1.852),(.099,.148,1.692)],
        [(-.051,.138,1.654),(-.059,.180,1.737),(-.064,.186,1.858),
         (-.059,.175,1.934),(-.064,.142,1.993),(-.039,.139,1.985),
         (.038,.143,1.951),(.065,.174,1.850),(.042,.166,1.695)],
    ]
    verts = [v for row in sections for v in row]
    faces = [(i*9+j,(i+1)*9+j,(i+1)*9+j+1,i*9+j+1) for i in range(3) for j in range(8)]
    faces.append(tuple(range(27,36)))
    cloth("Cutaway charcoal hood",verts,faces,("hood","lining"),group,"head",thickness=.018)
    seam("Hood opening turned seam",sections[0],.008,"hood_edge",group,"head")
    seam("Hood crown repair",[(-.126,.035,1.859),(-.135,.042,1.916),(-.104,.015,1.976),
         (-.059,.002,2.01),(-.027,.062,2.027)],.005,"hood_edge",group,"head")
    for i in range(8):
        z = 1.876+i*.014
        x = -.143+i*.004
        seam(f"Hood repair stitch {i+1}",[(x,.058,z),(x+.005,.074,z+.006)],.0028,
             "thread",group,"head")
    n = 21
    rows = []
    hems = [.071,.104,.124,.181,.285,.224,.395,.278,.516,.382,.537,
            .389,.529,.424,.398,.259,.327,.182,.221,.099,.069]
    for r in range(5):
        f = r/4
        row = []
        for j in range(n):
            # Start at the near collar and wrap over the back, not the chest.
            a = math.radians(-26-304*j/(n-1))
            fold = .018*math.sin(j*1.18+.41*r) + .009*math.sin(j*2.8-.89*r)
            x = -.024 + (.095+.229*math.sin(f*PI*.60))*math.sin(a)
            y = .008 - (.094+.230*math.sin(f*PI*.66))*math.cos(a)
            z = 1.606 - f*hems[j] + fold*f
            if j in (5,6,7,8,9,10,12):
                # Riverward side streams away from the arm, across the back.
                strength = {5:.038,6:.127,7:.096,8:.174,9:.087,10:.151,12:.101}[j]
                x -= strength*f**2
                y += (strength*.92+.015)*f**2
            row.append((x + f*fold*.65,y+f*fold,z))
        rows.append(row)
    verts = [v for row in rows for v in row]
    faces = [(i*n+j,i*n+j+1,(i+1)*n+j+1,(i+1)*n+j)
              for i in range(4) for j in range(n-1)]
    # Crease the hem so refinement rounds broad folds without losing tears.
    ob = cloth("Asymmetric jagged oilskin shoulder mantle",verts,faces,("oilskin","lining","ochre","umber"),
        group,"skin_cape",thickness=.014,sub=1)
    hem = ob.data.attributes.new("crease_edge","FLOAT","EDGE")
    for edge in ob.data.edges:
        a,b = edge.vertices
        if min(a,b) >= 4*n:
            hem.data[edge.index].value = .96
    for i, poly in enumerate(ob.data.polygons):
        row, j = divmod(i,n-1)
        if row==3 and (j in (3,4,9,10,13,15,17)):
            poly.material_index = 3
        elif (j,row) in ((1,1),(2,2),(6,1),(9,2),(12,3),(13,3),(16,1),(17,2),(18,2)):
            poly.material_index = 2
    # Seams are on the upper yoke and follow the rigid chest keys.
    seam("Yoke fold from clasp",[(-.064,-.104,1.585),(-.123,-.092,1.563),
        (-.171,-.067,1.524),(-.195,-.043,1.493)],.007,"umber",group,"chest")
    for i in range(3):
        seam(f"Shoulder repair {i+1}",[(-.112-i*.019,-.102+i*.003,1.548-i*.017),
            (-.103-i*.020,-.107+i*.003,1.557-i*.017)],.003,"thread",group,"chest")
    blob("Mantle clasp ring",(-.051,-.109,1.559),(.029,.013,.027),"gold",group,"chest")
    blob("Mantle clasp center",(-.050,-.121,1.560),(.014,.008,.012),"belt",group,"chest")
    seam("Mantle retaining cord",[(-.097,-.106,1.584),(-.064,-.125,1.563),
        (-.012,-.127,1.553),(.063,-.103,1.582)],.005,"belt",group,"chest")


def arms(group):
    for side,s in (("R",-1),("L",1)):
        arm,fore,hand = [key+"."+side for key in ("upper_arm","forearm","hand")]
        sh,el = rest[arm]
        _,wr = rest[fore]
        along(f"Bunched upper sleeve {side}",sh,el,[
            (-.11,.080,.081),(.03,.089,.094),(.30,.081,.094),(.62,.078,.082),
            (.91,.064,.075),(1.06,.063,.061)],"linen",group,arm,count=16)
        along(f"Ruched cuff {side}",sh,el,[
            (.77,.074,.075),(.83,.082,.076),(.93,.080,.070),
            (1.01,.069,.067),(1.08,.068,.065)],"linen",group,arm,count=16)
        for j,(t,dy,dz) in enumerate(((.30,-.042,.071),(.56,-.053,.063),(.90,-.058,.055))):
            q = sh.lerp(el,t)
            seam(f"Sleeve crease {side} {j+1}",[q+V((-.014,dy,dz)),q+V((.006,dy-.013,dz-.015)),
                q+V((.020,dy-.014,dz-.032))],.004,"thread",group,arm)
        along(f"Tapered bare forearm {side}",el,wr,[
            (-.137,.054,.056),(.08,.062,.059),(.35,.054,.056),(.71,.042,.043),
            (.93,.034,.035),(1.048,.033,.032)],"skin",group,fore,count=14)
        if side=="R":
            along("Worn leather wrist wrap",el,wr,[
                (.75,.043,.041),(.78,.044,.042),(.91,.039,.040),(.94,.037,.039)],
                "belt",group,fore,count=14,subs=0)
        along(f"Palm {side}",wr,rest[hand][1],[
            (-.10,.029,.029),(.11,.032,.037),(.43,.035,.039),
            (.68,.028,.038),(.79,.025,.035)],"skin",group,hand,count=12)
        for i in range(4):
            bone = f"finger{i}.{side}"
            a,b = rest[bone]
            along(f"Finger {i+1} {side}",a,b,[
                (-.14,.013,.012),(.14,.015,.013),(.52,.014,.012),
                (.81,.012,.011),(1.04,.007,.008)],"skin",group,bone,count=8)
        bone = f"thumb.{side}"
        a,b = rest[bone]
        along("Thumb "+side,a,b,[(0,.020,.017),(.29,.021,.018),(.72,.015,.015),
              (1.06,.010,.012)],"skin",group,bone,count=10)


def trousers_and_boots(group):
    for side,s in (("R",-1),("L",1)):
        thigh,shin,foot = (key+"."+side for key in ("thigh","shin","foot"))
        hip,knee = rest[thigh]
        _,ankle = rest[shin]
        along(f"Creased field breeches {side}",hip,knee,[
            (-.12,.078,.080),(.02,.096,.096),(.26,.111,.104),(.49,.101,.089),
            (.78,.088,.078),(1.06,.069,.067)],"russet",group,thigh,count=16)
        along(f"Wrinkled lower breeches {side}",knee,ankle,[
            (-.17,.066,.069),(.018,.075,.076),(.22,.075,.066),(.44,.066,.061),
            (.63,.059,.054),(.80,.050,.052)],"russet",group,shin,count=16)
        v = knee.lerp(hip,.22 if side=="R" else .12)
        cloth("Stitched knee patch "+side,[
            (v.x-.060,v.y-.069,v.z+.045),(v.x+.028,v.y-.085,v.z+.060),
            (v.x+.064,v.y-.044,v.z+.035),(v.x-.071,v.y-.061,v.z-.056),
            (v.x+.009,v.y-.093,v.z-.064),(v.x+.053,v.y-.055,v.z-.027)],
            [(0,1,4,3),(1,2,5,4)],("ochre","russet"),group,thigh,sub=0,thickness=.008)
        for j in range(5):
            x = v.x-.046+j*.016
            seam(f"Knee patch tack {side} {j+1}",[(x,v.y-.082,v.z+.046),(x+.004,v.y-.087,v.z+.036)],
                .0023,"thread",group,thigh)
        along(f"Collapsed boot shaft {side}",knee,ankle,[
            (.49,.067,.069),(.514,.075,.071),(.60,.065,.062),(.70,.058,.056),
            (.84,.062,.058),(.92,.051,.057),(1.12,.054,.060)],"boot",group,shin,count=14)
        along(f"Rolled shaft rim {side}",knee,ankle,[
            (.485,.070,.067),(.495,.074,.074),(.56,.070,.071),(.57,.066,.066)],
            "belt",group,shin,count=14,subs=0)
        loft("Broken-in boot "+side, [
            ((ankle.x,-.065,.031),.063,.125),((ankle.x,-.068,.045),.066,.129),
            ((ankle.x,-.065,.067),.062,.124),((ankle.x,-.032,.104),.057,.090),
            ((ankle.x,.009,.146),.055,.056)],"boot",group,foot,count=20)
        loft("Welt and sole "+side, [
            ((ankle.x,-.061,.007),.068,.132),((ankle.x,-.062,.012),.071,.136),
            ((ankle.x,-.064,.029),.072,.134),((ankle.x,-.064,.036),.066,.127)],
            "lining",group,foot,count=20,subs=1)
        for j in range(4):
            z = .193+j*.029
            y = -.052 - j*.003
            seam(f"Boot cross tie {side} {j+1}",[(ankle.x-.031,y+.006,z+.011),
                (ankle.x,y-.012,z),(ankle.x+.029,y+.004,z-.005)],.005,"thread",group,shin)
        for j in range(2):
            seam(f"Leather toe seam {side} {j+1}",[(ankle.x-.051,-.128+j*.024,.058),
                (ankle.x,-.143+j*.024,.078),(ankle.x+.047,-.132+j*.024,.059)],.003,"belt",group,foot)


def satchel(group):
    bag = "satchel"
    loft("Oil-stained canvas side satchel",[
        ((-.221,-.091,.884),.079,.049),((-.235,-.095,.907),.112,.069),
        ((-.245,-.101,1.02),.105,.076),((-.232,-.092,1.09),.079,.060),
        ((-.229,-.091,1.105),.070,.051)],"bag",group,bag,count=16)
    cloth("Notched satchel flap",[
        (-.314,-.123,1.100),(-.237,-.135,1.113),(-.162,-.113,1.103),
        (-.334,-.157,1.054),(-.239,-.179,1.058),(-.147,-.151,1.066),
        (-.313,-.156,.994),(-.231,-.177,.976),(-.151,-.153,1.013)],
        [(0,1,4,3),(1,2,5,4),(3,4,7,6),(4,5,8,7)],("linen","belt"),group,bag,thickness=.018)
    seam("Satchel flap seam",[(-.320,-.156,1.057),(-.311,-.164,1.009),(-.232,-.181,.989),
        (-.158,-.159,1.020)],.004,"bag",group,bag)
    blob("Satchel brass button",(-.226,-.185,1.009),(.017,.008,.016),"gold",group,bag)
    seam("Satchel belt loop",[(-.257,-.099,1.020),(-.247,-.105,1.134),
        (-.218,-.079,1.156),(-.206,-.028,1.145)],.014,"belt",group,bag)
    for i in range(7):
        x = -.300+i*.020
        seam(f"Canvas repaired hem {i+1}",[(x,-.148,.945),(x+.005,-.151,.956)],.003,"belt",group,bag)


SHAFT = 1.69


def harpoon(group):
    base = rest["harpoon"][0]
    axis = V((0,1,0))
    along("Single straight ash shaft",base,base+axis*1.51,[
        (0,.018,.018),(.03,.019,.019),(.10,.016,.016),(.46,.018,.018),
        (.75,.016,.016),(.98,.015,.015),(1,.015,.015)],"wood",group,"prop",count=12,subs=0)
    for i,t in enumerate((.014,.042,.074,.464,.490,.516,1.392,1.423,1.455)):
        along(f"Shaft binding band {i+1}",base+axis*t,base+axis*(t+.012),[
            (0,.020,.020),(.25,.022,.022),(.75,.022,.022),(1,.020,.020)],
            "belt" if i not in (6,8) else "iron",group,"prop",subs=0)
    outline = [(-.012,1.462),(-.018,1.517),(-.063,1.493),(-.053,1.559),
        (0,SHAFT),(.048,1.537),(.018,1.550),(.014,1.466)]
    verts = [base+V((a,b,z)) for z in (-.007,.007) for a,b in outline]
    verts += [base+V((0,1.565,-.014)),base+V((0,1.565,.015))]
    faces = [(8+i,8+(i+1)%8,17) for i in range(8)]
    faces += [((i+1)%8,i,16) for i in range(8)]
    faces += [(i,(i+1)%8,8+(i+1)%8,8+i) for i in range(8)]
    ob = mesh("Forged single-barb harpoon head",verts,faces,("iron","edge"),group,"prop",smooth=False)
    for i, p in enumerate(ob.data.polygons):
        p.material_index = 1 if i in (3,4,11,12,19,20) else 0


def bind(rig, prop_group):
    bpy.context.view_layer.update()
    prop = bpy.data.objects.new("Harpoon_Detachable",None)
    prop_group.objects.link(prop)
    prop.empty_display_type = "PLAIN_AXES"
    prop.empty_display_size = .11
    prop.location = rest["harpoon"][0]
    bpy.context.view_layer.update()

    def parent_keep(ob,parent,bone=None):
        world = ob.matrix_world.copy()
        ob.parent = parent
        if bone:
            ob.parent_type = "BONE"
            ob.parent_bone = bone
        bpy.context.view_layer.update()
        ob.matrix_world = world

    parent_keep(prop,rig,"harpoon")
    for ob, bone in geometry:
        if bone=="prop":
            parent_keep(ob,prop)
        elif bone in ("skin_torso","skin_cape"):
            ob.parent = rig
            mod = ob.modifiers.new("Weighted drape","ARMATURE")
            mod.object = rig
            a,b = ("pelvis","chest") if bone=="skin_torso" else ("cape","chest")
            first,second = [ob.vertex_groups.new(name=k) for k in (a,b)]
            for idx,v in enumerate(ob.data.vertices):
                z = v.co.z
                t = min(1,max(0,(z-(1.03 if bone=="skin_torso" else 1.29))/.25))
                first.add([idx],1-t,"REPLACE")
                second.add([idx],t,"REPLACE")
        else:
            parent_keep(ob,rig,bone)
    return prop


def camera_and_lights(group):
    def camera(name, rot, target, width):
        ob = bpy.data.objects.new(name,bpy.data.cameras.new(name))
        group.objects.link(ob)
        ob.rotation_euler = rot
        ob.location = V(target)+ob.rotation_euler.to_matrix()@V((0,0,7))
        ob.data.type = "ORTHO"
        ob.data.ortho_scale = width
        return ob

    tactical = (1.150829196,0,-.435386419)
    scene.camera = camera("Camera_Tactical_3Q",tactical,(.18,-.10,1.03),2.95)
    camera("Camera_Neutral_Front",(PI/2,0,0),(0,0,1.01),2.32)
    camera("Camera_Back_3Q",(1.25,0,2.30),(-.035,0,1.00),2.43)
    camera("Camera_Tactical_Wide",tactical,(.56,-.23,1.03),3.69)
    for name,position,power,color,size in (
        ("Large window",(-3.6,-4.2,6.2),730,(1,.94,.87),3.5),
        ("Open sky",(3.6,-2.4,4.3),225,(.74,.84,1),4.1),
        ("Contour from river",(2.0,3.4,5.0),710,(1,.83,.65),3.3),
    ):
        light = bpy.data.objects.new(name,bpy.data.lights.new(name,"AREA"))
        group.objects.link(light)
        light.location = position
        light.rotation_euler = (V((0,0,1.1))-light.location).to_track_quat("-Z","Y").to_euler()
        light.data.energy,light.data.color,light.data.shape,light.data.size = power,color,"DISK",size
    scene.world = bpy.data.worlds.new("Warm diffuse world")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.33,.29,.23,1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .28
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 800
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.fps = 24
    scene.unit_settings.system = "METRIC"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    global scene
    scene = bpy.context.scene
    scene.name = "Harpooner • editable review candidate"
    output = Path(sys.argv[sys.argv.index("--")+1]).resolve()
    if output.exists():
        raise FileExistsError(output)
    load_materials()
    rig = make_rig(collection("01 · Actor rig"))
    coat = collection("02 · Coat, head, and gear")
    limbs = collection("03 · Limbs and boots")
    prop_group = collection("04 · Detachable ash harpoon")
    torso(coat)
    head(coat)
    mantle(coat)
    arms(limbs)
    trousers_and_boots(limbs)
    satchel(coat)
    harpoon(prop_group)
    bind(rig,prop_group)
    camera_and_lights(collection("05 · Review cameras and lighting"))
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    from pose_harpooner import animate
    animate(scene,rig,rest)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    scene["Facing"] = "Metres, -Y forward, +Z up, right at -X"
    scene["Concept SHA256"] = "1ae252bab5a944bfef6b9aeead748479628485e053857081037a0cdafb34b0d0"
    scene["Status"] = "Model and acting candidate; not approved for integration"
    bpy.ops.wm.save_as_mainfile(filepath=str(output),compress=True)


if __name__ == "__main__":
    main()
