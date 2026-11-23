"""Author the editable Hookhand candidate from the approved River and Village plate."""

import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "harpooner"))
import build_harpooner as forms

from pose_hookhand import COIL_EXIT, HOOK_REST, HOOK_TRAVEL, LINE_BONES, LINE_NODES, LINE_ROOT, animate


V = Vector
PI = math.pi
CONCEPT_SHA = "f3a93be9d71479a142b88c46597558e460ae9a729735b87fb8a54591c48af767"
rest = forms.rest
loft, along, blob, seam, cloth = forms.loft, forms.along, forms.blob, forms.seam, forms.cloth


def palette():
    colors = {
        "oil": ((.018,.039,.049),(.117,.184,.211)),
        "seam": ((.030,.051,.066),(.192,.278,.314)),
        "coat_fade": ((.10,.065,.035),(.39,.243,.101)),
        "coat_inner": ((.021,.018,.027),(.129,.100,.11)),
        "plum": ((.061,.027,.037),(.294,.131,.145)),
        "plum_seam": ((.104,.059,.061),(.43,.227,.204)),
        "vest": ((.075,.047,.026),(.25,.157,.10)),
        "stripe": ((.172,.114,.053),(.61,.413,.218)),
        "trouser": ((.045,.036,.032),(.242,.177,.145)),
        "linen": ((.245,.142,.067),(.70,.518,.305)),
        "skin": ((.275,.133,.065),(.741,.469,.282)),
        "flush": ((.32,.092,.042),(.69,.342,.173)),
        "stubble": ((.107,.053,.033),(.343,.214,.141)),
        "hair": ((.019,.011,.009),(.090,.050,.045)),
        "eye": ((.589,.422,.266),(.89,.809,.685)),
        "iris": ((.035,.026,.015),(.183,.135,.070)),
        "ink": ((.006,.008,.009),(.032,.028,.027)),
        "boot": ((.046,.028,.016),(.204,.127,.065)),
        "belt": ((.050,.025,.015),(.255,.145,.066)),
        "brass": ((.224,.095,.020),(.60,.367,.121)),
        "iron": ((.063,.075,.084),(.323,.351,.350)),
        "edge": ((.175,.179,.170),(.66,.615,.492)),
        "hemp": ((.220,.107,.030),(.779,.486,.167)),
        "hemp_light": ((.252,.127,.035),(.883,.608,.277)),
    }
    for name, (dark, light) in colors.items():
        forms.materials[name] = forms.pigment(
            name, dark, light, metal=.35 if name in ("brass","iron","edge") else 0
        )


def build_rig(group):
    arm = bpy.data.armatures.new("Hookhand bind")
    rig = bpy.data.objects.new("Hookhand_Rig", arm)
    group.objects.link(rig)
    rig.show_in_front = True
    arm.display_type = "STICK"
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    labels = {}

    def add(name, a, b, parent=None, label="Body"):
        e = arm.edit_bones.new(name)
        e.head, e.tail = a,b
        if parent:
            e.parent = arm.edit_bones[parent]
        e.align_roll(V((0,0,1)))
        rest[name] = (V(a),V(b))
        labels[name] = label

    add("root",(0,0,0),(0,-.21,0))
    add("pelvis",(0,0,.963),(0,0,1.214),"root")
    add("chest",(0,0,1.214),(0,-.018,1.575),"pelvis")
    add("neck",(0,-.018,1.575),(.006,-.058,1.726),"chest")
    add("head",(.006,-.058,1.726),(.006,-.057,2.013),"neck")
    add("mantle",(-.012,.113,1.485),(-.02,.205,.78),"chest","Cloth and kit")
    add("coil", COIL_EXIT,(-.27,-.054,.754),"pelvis","Cloth and kit")
    add("scarf",(-.029,-.13,1.631),(-.059,-.151,1.23),"chest","Cloth and kit")
    add("hook",HOOK_REST,HOOK_REST+V((0,0,-.18)),"root","Rope and hook")
    for i in range(LINE_BONES):
        a = LINE_ROOT.lerp(HOOK_REST,i/(LINE_BONES-1))
        b = a+V((.09,0,-.044))
        add(f"line.{i:02}",a,b,"root","Rope and hook")
    for side,s in (("R",-1),("L",1)):
        def limb(label,a,b,parent,category="Limbs"):
            add(label+"."+side,(s*a[0],a[1],a[2]),(s*b[0],b[1],b[2]),parent,category)
        limb("upper_arm",(.185,-.006,1.544),(.467,-.006,1.544),"chest")
        limb("forearm",(.467,-.006,1.544),(.750,-.006,1.544),"upper_arm."+side)
        limb("hand",(.750,-.006,1.544),(.858,-.006,1.544),"forearm."+side)
        limb("thigh",(.115,.007,.966),(.121,-.025,.539),"pelvis")
        limb("shin",(.121,-.025,.539),(.141,.016,.112),"thigh."+side)
        limb("foot",(.141,.016,.112),(.141,-.156,.063),"shin."+side)
        for i,(y,z) in enumerate(((-.027,.004),(-.010,.012),(.010,.010),(.031,.006))):
            length = (.061,.067,.062,.053)[i]
            limb(f"finger{i}",(.814,y,1.544+z),(.814+length,y,1.544+z),"hand."+side,"Fingers")
        limb("thumb",(.778,-.028,1.544),(.813,-.064,1.523),"hand."+side,"Fingers")
    bpy.ops.object.mode_set(mode="OBJECT")
    buckets = {k:arm.collections.new(k) for k in dict.fromkeys(labels.values())}
    for bone in arm.bones:
        buckets[labels[bone.name]].assign(bone)
        rig.pose.bones[bone.name].rotation_mode = "QUATERNION"
    buckets["Fingers"].is_visible = False
    return rig


def body(group):
    loft("Lean vest and hips", [((0,y,z),a,b) for y,z,a,b in (
        (.005,.89,.145,.093),(.006,.94,.167,.107),(.009,1.04,.165,.105),
        (.009,1.16,.150,.104),(.002,1.29,.150,.115),(.002,1.43,.172,.133),
        (-.005,1.53,.191,.121),(-.016,1.58,.146,.095),(-.029,1.62,.094,.074)
    )],"vest",group,"weighted_torso",count=20)
    for i,x in enumerate((-.091,.062)):
        seam(f"Vertical vest edge {i+1}",[(x,-.111,1.07),(x*1.18,-.13,1.26),(x*1.30,-.135,1.46),
             (x,-.125,1.572)],.010,"stripe",group,"chest")
    for i in range(4):
        blob(f"Vest tack {i+1}",(-.021,-.128,1.167+i*.082),(.011,.009,.012),"brass",group,"chest")
    loft("Rope worker belt", [((0,.009,z),a,b) for z,a,b in (
        (1.012,.166,.118),(1.016,.182,.133),(1.079,.174,.123),(1.087,.160,.111)
    )],"belt",group,"pelvis",count=18,subs=0)
    forms.trim("Iron belt square",.030,-.13,1.047,.080,.052,"iron",group,"pelvis")
    seam("Diagonal rope harness",[(.139,-.064,1.56),(.108,-.139,1.46),(.018,-.153,1.32),
         (-.095,-.123,1.16),(-.158,-.075,1.079)],.019,"belt",group,"chest")
    loft("Knitted cowl collar", [((0,y,z),a,b) for y,z,a,b in (
        (-.043,1.535,.111,.110),(-.049,1.563,.139,.120),(-.048,1.616,.135,.111),
        (-.038,1.658,.113,.099),(-.030,1.682,.096,.084)
    )],"plum",group,"chest",count=18)
    seam("Rolled cowl front",[(-.108,-.092,1.621),(-.068,-.159,1.596),(.019,-.163,1.576),
         (.107,-.111,1.608)],.031,"plum",group,"chest")
    cloth("Russet apron scrap",[(-.013,-.108,1.065),(.102,-.093,1.047),(-.005,-.124,.887),
          (.133,-.097,.898),(-.042,-.084,.688),(.02,-.135,.568),(.052,-.091,.676),
          (.107,-.099,.618),(.149,-.075,.740)],[(0,1,3,2),(2,3,8,7,6,5,4)],
          ("plum","coat_inner"),group,"pelvis",sub=0,thickness=.012)


def hood_and_face(group):
    loft("Long exposed neck", [((.006,y,z),a,b) for y,z,a,b in (
        (-.015,1.57,.088,.068),(-.041,1.65,.077,.080),(-.060,1.743,.069,.059)
    )],"skin",group,"neck",count=16)
    loft("Worn long-jawed face", [((x,y,z),a,b) for x,y,z,a,b in (
        (.015,-.102,1.703,.038,.052),(.016,-.117,1.715,.065,.074),
        (.015,-.104,1.758,.085,.096),(.011,-.084,1.811,.092,.108),
        (.005,-.078,1.864,.091,.109),(.004,-.053,1.909,.089,.092),
        (-.002,-.039,1.954,.073,.073),(-.010,-.026,1.984,.048,.038)
    )],"skin",group,"head",count=22,irregular=.042)
    blob("Ash chin and beard shadow",(.017,-.144,1.731),(.067,.053,.039),"stubble",group,"head")
    blob("Strained chin",(.020,-.184,1.739),(.051,.025,.025),"skin",group,"head")
    loft("Crooked bridge and nose", [((x,y,z),a,b) for x,y,z,a,b in (
        (.014,-.177,1.803,.020,.018),(.021,-.195,1.821,.031,.035),
        (.023,-.217,1.838,.025,.041),(.015,-.189,1.857,.018,.029),
        (.004,-.173,1.887,.016,.022)
    )],"flush",group,"head",count=14)
    for side,s in (("R",-1),("L",1)):
        x = s*.045+.008
        blob("Windburnt cheek "+side,(s*.066,-.158,1.80),(.037,.027,.035),"flush",group,"head",tilt=s*.28)
        blob("Tired sclera "+side,(x,-.172,1.867),(.025,.019,.013),"eye",group,"head")
        blob("Eye "+side,(x+.008,-.189,1.868),(.010,.005,.012),"iris",group,"head")
        blob("Pupil "+side,(x+.009,-.193,1.868),(.005,.003,.007),"ink",group,"head")
        seam("Weather brow "+side,[(x-.025,-.172,1.891),(x-.008,-.191,1.904),
             (x+.014,-.189,1.898),(x+.026,-.175,1.881)],.007,"hair",group,"head")
        seam("Eye bag "+side,[(x-.025,-.174,1.852),(x+.002,-.186,1.845),(x+.020,-.175,1.850)],
             .003,"stubble",group,"head")
        seam("Crease "+side,[(s*.056,-.185,1.824),(s*.051,-.187,1.802),(s*.057,-.173,1.783)],
             .0038,"stubble",group,"head")
    seam("Set mouth",[(-.041,-.170,1.773),(-.012,-.192,1.774),(.017,-.205,1.774),
         (.047,-.177,1.770)],.004,"stubble",group,"head")
    for i, points in enumerate((
        [(-.066,-.138,1.975),(-.077,-.170,1.927),(-.089,-.170,1.874),(-.073,-.155,1.818)],
        [(-.035,-.14,1.988),(-.063,-.182,1.945),(-.059,-.205,1.920),(-.046,-.193,1.892)],
        [(.037,-.109,1.998),(.051,-.161,1.951),(.089,-.182,1.926),(.106,-.152,1.910)],
        [(.075,-.094,1.954),(.096,-.118,1.884),(.104,-.136,1.827),(.088,-.151,1.808)],
    ),1):
        seam(f"Loose lock {i}",points,.010,"hair",group,"head")
    rings = [
       [(-.097,-.056,1.725),(-.108,-.112,1.825),(-.106,-.157,1.934),(-.067,-.164,1.987),
        (-.018,-.144,2.038),(.048,-.134,2.026),(.094,-.111,1.964),(.113,-.068,1.860),(.104,-.045,1.749)],
       [(-.117,.029,1.713),(-.133,-.032,1.831),(-.126,-.042,1.969),(-.105,-.005,2.046),
        (-.035,.016,2.080),(.042,.017,2.059),(.104,.024,2.015),(.127,.057,1.874),(.109,.036,1.738)],
       [(-.106,.114,1.688),(-.122,.134,1.772),(-.113,.113,1.904),(-.103,.114,2.003),
        (-.063,.106,2.035),(-.002,.103,2.040),(.074,.114,1.997),(.100,.141,1.839),(.077,.105,1.714)],
       [(-.102,.156,1.644),(-.108,.183,1.705),(-.083,.202,1.818),(-.085,.195,1.891),
        (-.055,.190,1.932),(-.016,.180,1.929),(.028,.179,1.893),(.061,.181,1.779),(.049,.165,1.669)]
    ]
    verts = [v for ring in rings for v in ring]
    faces = [(9*i+j,9*(i+1)+j,9*(i+1)+j+1,9*i+j+1) for i in range(3) for j in range(8)]
    faces.append(tuple(range(27,36)))
    cloth("Long knitted plum cowl",verts,faces,("plum","coat_inner"),group,"head",thickness=.018)
    seam("Heavy folded hood edge",rings[0],.011,"plum_seam",group,"head")
    seam("Fold from the crown",[(-.094,.013,2.031),(-.124,.030,1.965),(-.122,.055,1.882),
         (-.118,.093,1.788),(-.099,.134,1.738)],.010,"plum",group,"head")
    for j in range(6):
        x = -.117+j*.012
        seam(f"Knit ridge {j+1}",[(x,.091,1.911),(x+.001,.068,1.972),(x+.022,.027,2.043)],
             .004,"plum_seam",group,"head")
    seam("Weighted neck fold",[(-.093,.119,1.720),(-.133,.102,1.656),(-.110,-.013,1.609),
         (-.075,-.137,1.616)],.027,"plum",group,"scarf")


def coat(group):
    n = 23
    walk = (.22,.34,.52,.65,.55,.80,.63,.94,.70,.98,.67,.90,.73,.95,.71,.91,.65,.79,.54,.63,.40,.32,.21)
    rows = []
    for i in range(5):
        f = i/4
        row = []
        for j, length in enumerate(walk):
            theta = math.radians(-32 - 293*j/(n-1))
            w = .107+.204*math.sin(math.pi*.65*f)
            d = .092+.255*math.sin(math.pi*.58*f)
            rad = math.sin(j*1.61+i*.61)*.015+.01*math.cos(j*3.81-i)
            x = -.013+(w+rad*f)*math.sin(theta)
            tear = .045*math.cos(j*1.53)*f**3 if 5<=j<=19 else 0
            y = .021-(d+rad*f)*math.cos(theta) + .188*f*f+tear
            z = 1.609-length*f + .017*math.cos(j*.72)*f
            row.append((x,y,z))
        rows.append(row)
    faces = [(i*n+j,i*n+j+1,(i+1)*n+j+1,(i+1)*n+j) for i in range(4) for j in range(n-1)]
    ob=cloth("Long split oilcloth back and cape", [q for row in rows for q in row],faces,
             ("oil","coat_inner","coat_fade","seam"),group,"weighted_coat",thickness=.019)
    for f in ob.data.polygons:
        i,j = divmod(f.index,n-1)
        if (i,j) in {(1,4),(2,3),(2,6),(2,10),(3,3),(3,7),(3,8),(3,13),(3,17),(3,19)}:
            f.material_index=2
    creases=ob.data.attributes.new("crease_edge","FLOAT","EDGE")
    for edge in ob.data.edges:
        if min(edge.vertices)>=4*n:
            creases.data[edge.index].value=.97
    for j in (2,6,11,16,20):
        seam(f"Coat topstitch {j}",[rows[i][j] for i in range(4)],.004,"seam",group,"mantle")
    blob("Off-center cloak clasp",(-.075,-.120,1.559),(.029,.015,.028),"brass",group,"chest")


def limbs(group):
    for side,s in (("R",-1),("L",1)):
        arm,fore,hand,thigh,shin,foot=(key+"."+side for key in
            ("upper_arm","forearm","hand","thigh","shin","foot"))
        sh,el=rest[arm]; _,wrist=rest[fore]; hip,knee=rest[thigh]; _,ankle=rest[shin]
        along("Puffed linen sleeve "+side,sh,el,[
            (-.12,.075,.082),(.05,.095,.094),(.39,.090,.087),(.63,.079,.081),
            (.85,.065,.068),(.98,.069,.063),(1.04,.063,.061)],"linen",group,arm,count=16)
        along("Sleeve gathers "+side,sh,el,[
            (.86,.059,.058),(.91,.071,.073),(1.01,.072,.067),(1.10,.051,.050)],
            "stripe",group,arm,count=14)
        along("Ropy forearm "+side,el,wrist,[
            (-.09,.055,.051),(.09,.056,.057),(.42,.048,.046),(.73,.037,.041),
            (.93,.030,.032),(1.09,.031,.031)],"skin",group,fore,count=16)
        if side=="L":
            along("Riveted hook cuff",el,wrist,[
                (.42,.064,.067),(.48,.068,.067),(.81,.059,.063),(.97,.062,.063),
                (1.02,.057,.056)],"iron",group,fore,count=14,subs=0)
            for i,t in enumerate((.46,.88,.98)):
                along(f"Cuff turned lip {i+1}",el,wrist,[(t,.065,.066),(t+.025,.067,.067),
                      (t+.055,.064,.066)],"edge" if i==2 else "belt",group,fore,count=14,subs=0)
            for i,t in enumerate((.56,.70,.83)):
                p=el.lerp(wrist,t)+V((0,-.058,.020))
                blob(f"Cuff rivet {i+1}",p,(.009,.009,.010),"brass",group,fore)
        else:
            along("Rope glove wrist edge",el,wrist,[
                (.83,.037,.038),(.88,.041,.043),(1.05,.036,.039)],"belt",group,fore,count=14)
        along("Narrow work palm "+side,wrist,rest[hand][1],[
            (-.04,.030,.032),(.14,.030,.036),(.48,.032,.038),
            (.78,.027,.035),(.87,.025,.033)],"skin",group,hand,count=12)
        for i in range(5):
            bone = ("thumb" if i==4 else f"finger{i}")+"."+side
            a,b=rest[bone]
            along(f"Digit {i+1} {side}",a,b,[(-.05,.014,.014),(.19,.015,.013),
                (.70,.012,.011),(1,.008,.008)],"skin",group,bone,count=8)
        along("Breeches thigh "+side,hip,knee,[
            (-.11,.087,.090),(.09,.096,.091),(.30,.099,.099),
            (.55,.086,.082),(.86,.071,.072),(1.09,.061,.061)],"trouser",group,thigh,count=16)
        along("Breeches shin "+side,knee,ankle,[
            (-.13,.062,.064),(.02,.068,.071),(.31,.067,.065),(.60,.054,.058),(.91,.047,.047)],
            "trouser",group,shin,count=14)
        c=knee.lerp(hip,.27 if side=="R" else .13)
        cloth("Ragged ochre knee mend "+side,[
            (c.x-.062,c.y-.072,c.z+.06),(c.x+.044,c.y-.080,c.z+.055),
            (c.x+.057,c.y-.075,c.z-.04),(c.x+.014,c.y-.093,c.z-.074),
            (c.x-.038,c.y-.087,c.z-.051)],[(0,1,2,3,4)],("coat_fade","trouser"),group,thigh,sub=0)
        for i in range(4):
            x=c.x-.042+i*.022
            seam(f"Knee hand stitch {side} {i+1}",[(x,c.y-.085,c.z+.053),(x+.005,c.y-.091,c.z+.041)],
                 .003,"stripe",group,thigh)
        along("Weathered boot shaft "+side,knee,ankle,[
            (.52,.064,.066),(.58,.071,.071),(.69,.063,.065),(.77,.060,.057),
            (.88,.054,.054),(1.10,.054,.060)],"boot",group,shin,count=14)
        for i in range(3):
            h=.197+i*.052
            seam(f"Crossed boot cord {side} {i+1}",[(ankle.x-.041,-.036,h+.015),
                (ankle.x,-.059,h),(ankle.x+.041,-.035,h-.012)],.006,"stripe",group,shin)
        loft("Hookhand sole "+side,[((ankle.x,-.068,z),a,b) for z,a,b in (
            (.009,.068,.137),(.014,.074,.141),(.028,.075,.142),(.038,.067,.136)
        )],"coat_inner",group,foot,count=20)
        loft("Turned river boot "+side, [((ankle.x,y,z),a,b) for y,z,a,b in (
            (-.067,.031,.070,.137),(-.067,.048,.069,.134),(-.058,.071,.063,.117),
            (-.023,.105,.057,.078),(.012,.146,.054,.053)
        )],"boot",group,foot,count=20)
        c=ankle.x
        seam("Boot toe crease "+side,[(c-.052,-.156,.049),(c-.006,-.179,.069),(c+.050,-.152,.054)],
             .005,"belt",group,foot)


def equipment(group):
    b="coil"
    # Three staggered loops, behind a visible belt hanger.
    for j in range(3):
        pts=[]
        for i in range(21):
            a=2*PI*i/20
            pts.append((-.265+j*.020+(.096-j*.009)*math.sin(a),
                        -.192+j*.016-.018*math.sin(a)-.008*math.sin(2*a),
                        .854-j*.041+(.166-j*.012)*math.cos(a)))
        seam(f"Coiled hemp loop {j+1}",pts,.018,"hemp",group,b)
        # Partial strand ridges keep the rope reading as fibre, at low cost.
        for i in (3,5,8,11,13,16,18):
            a=pts[i]; c=pts[i+1]
            p=V(a).lerp(V(c),.24)+V((-.009,-.018,-.001))
            q=V(a).lerp(V(c),.61)+V((.006,-.019,.002))
            seam(f"Coil fibre {j+1}.{i}",[p,q],.0028,"hemp_light",group,b)
    seam("Bent hanging keeper",[(-.196,-.098,1.091),(-.233,-.161,1.064),
         (-.225,-.199,1.007),(-.179,-.186,1.035)],.014,"belt",group,b)
    seam("Short coil tail",[COIL_EXIT,(-.29,-.22,.888),(-.30,-.20,.664),(-.34,-.18,.612)],
         .017,"hemp",group,b)
    blob("Coil knot",(-.23,-.214,1.012),(.037,.031,.030),"hemp_light",group,b)
    p=HOOK_REST
    curve=[(0,0,0),(.008,0,-.067),(.045,0,-.130),(.098,0,-.151),
          (.151,0,-.144),(.194,0,-.108),(.210,0,-.057),(.198,0,-.018),(.166,0,.004)]
    spec=[(p+V(k),r,r*.76) for k,r in zip(curve,(.021,.024,.025,.025,.024,.023,.018,.014,.005))]
    verts=[]; faces=[]; n=10
    for i,(c,wide,deep) in enumerate(spec):
        tangent=(spec[min(i+1,8)][0]-spec[max(0,i-1)][0]).normalized()
        across=V((0,1,0)).cross(tangent)
        verts.extend(c+wide*math.cos(2*PI*j/n)*across+V((0,deep*math.sin(2*PI*j/n),0)) for j in range(n))
    for i in range(8):
        for j in range(n):
            a,b=i*n+j,i*n+(j+1)%n
            faces.append((a,b,b+n,a+n))
    faces.extend((tuple(reversed(range(n))),tuple(range(8*n,9*n))))
    hook=forms.mesh("Forged open C hook",verts,faces,("iron","edge"),group,"prop",subs=1)
    for f in hook.data.polygons:
        if f.index%10 in (0,1,7,8):
            f.material_index=1
    for side in (-1,1):
        pts=[p+V((.018*math.sin(i*2*PI/12),side*.010,.024+.027*math.cos(i*2*PI/12))) for i in range(13)]
        seam("Forged eye "+str(side),pts,.007,"iron",group,"prop")
    blob("Wrapped line knot",p+V((0,0,.047)),(.026,.022,.031),"hemp",group,"prop")


def bind(rig, group):
    bpy.context.view_layer.update()
    hook=bpy.data.objects.new("Hook_Detachable",None)
    group.objects.link(hook)
    hook.empty_display_size=.08
    hook.location=HOOK_REST
    bpy.context.view_layer.update()

    def attach(ob,parent,bone=None):
        world=ob.matrix_world.copy()
        ob.parent=parent
        if bone:
            ob.parent_type="BONE"
            ob.parent_bone=bone
        bpy.context.view_layer.update()
        ob.matrix_world=world

    attach(hook,rig,"hook")
    for ob, bone in forms.geometry:
        if bone=="prop":
            attach(ob,hook)
        elif bone.startswith("weighted_"):
            ob.parent=rig
            a,b=("mantle","chest") if bone=="weighted_coat" else ("pelvis","chest")
            cut=.92 if bone=="weighted_coat" else 1.08
            first,second=[ob.vertex_groups.new(name=k) for k in (a,b)]
            for i,v in enumerate(ob.data.vertices):
                t=min(1,max(0,(v.co.z-cut)/.55))
                first.add([i],1-t,"REPLACE")
                second.add([i],t,"REPLACE")
            mod=ob.modifiers.new("Garment drape","ARMATURE")
            mod.object=rig
        else:
            attach(ob,rig,bone)
    return hook


def rig_line(rig, group):
    # Two independent tubes share a continuous run of bone-weighted rings.
    # The finer strand is wound into the main tube so pigment moves with it.
    direction=(HOOK_REST-LINE_ROOT).normalized()
    across=direction.cross(V((0,0,1))).normalized()
    up=direction.cross(across)
    for name,radius,wrap,mat in (
        ("Live hemp towline",.0145,0,"hemp"),
        ("Spiral fibre on towline",.004,.013,"hemp_light"),
    ):
        n=8
        verts=[]
        for i in range(LINE_NODES):
            t=i/(LINE_NODES-1)
            c=LINE_ROOT.lerp(HOOK_REST,t)
            turn=t*2*PI*13
            c += wrap*(math.sin(turn)*across+math.cos(turn)*up)
            verts.extend(c+radius*(math.sin(2*PI*j/n)*across+math.cos(2*PI*j/n)*up) for j in range(n))
        faces=[(i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j)
               for i in range(LINE_NODES-1) for j in range(n)]
        faces+= [tuple(reversed(range(n))),tuple(range(len(verts)-n,len(verts)))]
        obj=forms.mesh(name,verts,faces,mat,group)
        slot=[obj.vertex_groups.new(name=f"line.{i:02}") for i in range(LINE_BONES)]
        for i in range(LINE_NODES):
            k=i*(LINE_BONES-1)/(LINE_NODES-1)
            a,b=int(k),min(int(k)+1,LINE_BONES-1)
            ids=list(range(i*n,(i+1)*n))
            slot[a].add(ids,1-(k-a),"REPLACE")
            if b!=a:
                slot[b].add(ids,k-a,"REPLACE")
        obj.parent=rig
        mod=obj.modifiers.new("Editable line rig","ARMATURE")
        mod.object=rig


def cameras(group):
    forms.camera_and_lights(group)
    s=forms.scene
    wide=bpy.data.objects["Camera_Tactical_Wide"]
    wide.data.ortho_scale=3.53
    wide.location=V((.37,-.23,1.03))+wide.rotation_euler.to_matrix()@V((0,0,7))
    back=bpy.data.objects["Camera_Back_3Q"]
    back.data.ortho_scale=2.55
    s.cycles.samples=16
    s.view_settings.view_transform="Standard"


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s=forms.scene=bpy.context.scene
    s.name="Hookhand | Model review"
    output=Path(sys.argv[sys.argv.index("--")+1]).resolve()
    if output.exists():
        raise FileExistsError(output)
    palette()
    rig=build_rig(forms.collection("01 · Rig"))
    kit=forms.collection("02 · Garment, cowl and face")
    body(kit)
    hood_and_face(kit)
    coat(kit)
    limbs(forms.collection("03 · Sleeves, arms, trousers and boots"))
    gear=forms.collection("04 · Coil, towline and detachable hook")
    equipment(gear)
    bind(rig,gear)
    rig_line(rig,gear)
    cameras(forms.collection("05 · Review cameras and lighting"))
    animate(s,rig,rest)
    s["Facing"]="Metres, -Y forward, +Z up"
    s["Concept SHA256"]=CONCEPT_SHA
    s["Status"]="Hookhand model candidate. No runtime integration."
    s["Pull displacement reference in metres"]=HOOK_TRAVEL
    bpy.context.view_layer.objects.active=rig
    rig.select_set(True)
    bpy.ops.wm.save_as_mainfile(filepath=str(output),compress=True)


if __name__=="__main__":
    main()
