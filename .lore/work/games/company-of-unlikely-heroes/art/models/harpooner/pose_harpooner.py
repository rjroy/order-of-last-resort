"""The Harpooner's authored beats, sampled into editable FK keys."""

import math

import bpy
from mathutils import Matrix, Quaternion, Vector


V = Vector
PREFIX = "Harpooner | "
REST, READY, MOVE, JAB, CAST, HIT, FALL = (
    "Neutral T", "Ready", "Pursue", "Close Thrust", "Ranged Cast", "Hit", "Defeat"
)
END = {REST:1, READY:41, MOVE:21, JAB:23, CAST:29, HIT:17, FALL:25}
RELEASE = 11
RESTORE = 24

# Actor faces -Y. Keep the ranged butt at the near/front edge throughout
# loading. The projectile and the hand are separate rig controls after release.
READY_POSE = {
    "hip": (0,-.012,.911), "torso": (10,-5,5), "head": (-4,2,19),
    "rf": (-.20,.215,.117), "lf": (.207,-.27,.117), "feet": (-17,11),
    "butt": (-.57,-.20,.77), "aim": (.61,-.32,.73), "grips": (.43,.83),
    "rh": (-.205,-.353,1.286), "lh": (.3,-.44,1.33),
    "r_dir": (.25,-.87,.31), "l_dir": (.29,-.92,.26), "curl": (.97,.93),
    "cape": (1,-2,4), "scarf": (4,-7,2), "bag": (0,-1,-3), "coat": (1,-4,1),
    "r_toe": 0, "l_toe": 0, "scale": 1,
}


def controls(**overrides):
    return READY_POSE | overrides


TAKES = {
    READY: (
        (1,controls()),
        (12,controls(hip=(-.009,-.014,.920),torso=(9,-4,6),head=(-6,2,21),
                     butt=(-.572,-.203,.776),cape=(3,-4,6),scarf=(6,-5,3))),
        (28,controls(hip=(.009,-.010,.903),torso=(11,-6,5),head=(-4,4,18),
                     butt=(-.566,-.195,.766),cape=(0,-1,2))),
        (41,controls()),
    ),
    MOVE: (
        (1,controls()),
        (5,controls(hip=(-.027,.020,.902),torso=(17,-3,8),rf=(-.203,.159,.170),
                    lf=(.184,-.219,.117),r_toe=16,butt=(-.562,-.231,.842),aim=(.73,-.42,.54),
                    cape=(11,-7,2),scarf=(13,-9,2),bag=(10,-8,-6))),
        (9,controls(hip=(.005,-.023,.946),torso=(19,-5,11),rf=(-.154,-.140,.234),
                    lf=(.182,.069,.117),r_toe=-11,butt=(-.537,-.219,.823),aim=(.74,-.42,.52),
                    cape=(15,-4,7),scarf=(18,-8,8),bag=(-3,7,-9))),
        (12,controls(hip=(.025,-.058,.916),torso=(23,-2,8),rf=(-.126,-.267,.123),
                     lf=(.181,.188,.170),l_toe=12,butt=(-.525,-.251,.854),aim=(.74,-.38,.55),
                     cape=(15,-8,5),scarf=(16,-11,4),bag=(-2,-5,-7))),
        (16,controls(hip=(.04,-.048,.928),torso=(14,-5,7),rf=(-.179,.043,.117),
                     lf=(.2,.004,.225),l_toe=-5,butt=(-.563,-.232,.800),aim=(.68,-.37,.65),
                     cape=(9,2,9),scarf=(11,-8,6),bag=(8,2,-5))),
        (21,controls()),
    ),
    JAB: (
        (1,controls()),
        (5,controls(hip=(-.062,.074,.870),torso=(16,-9,-7),head=(3,2,22),
                    butt=(-.46,.175,1.08),aim=(.45,-.88,.07),grips=(.33,.68),
                    cape=(-4,-9,1),scarf=(7,-5,3),bag=(4,-8,-8))),
        (8,controls(hip=(.087,-.125,.793),torso=(34,-12,20),head=(-12,6,17),
                    butt=(-.16,.00,1.071),aim=(.49,-.87,.034),grips=(.34,.78),
                    cape=(16,-13,1),scarf=(20,-4,-4),bag=(15,-1,10),coat=(-5,-15,8))),
        (10,controls(hip=(.071,-.117,.811),torso=(28,-10,17),head=(-10,3,17),
                     butt=(-.186,.030,1.08),aim=(.48,-.87,.055),grips=(.34,.75),
                     cape=(13,-11,5),scarf=(14,-5,1),bag=(10,1,8))),
        (16,controls(hip=(.007,-.039,.875),torso=(15,-7,8),head=(-5,4,19),
                     butt=(-.42,-.099,.91),aim=(.60,-.54,.54),grips=(.41,.77),
                     cape=(6,-4,8),scarf=(8,-4,5),bag=(3,0,3))),
        (23,controls()),
    ),
    CAST: (
        (1,controls()),
        (3,controls(hip=(-.035,.011,.900),torso=(7,-8,-4),head=(-5,4,17),
                    butt=(-.57,-.24,.93),aim=(.695,-.32,.643),grips=(.35,.76),
                    lh=(.20,-.395,1.35),l_dir=(.56,-.60,.34),curl=(1,.48),cape=(2,-8,8))),
        (6,controls(hip=(-.040,.017,.896),torso=(2,-11,-5),head=(-8,5,17),
                    butt=(-.45,-.29,1.45),aim=(.575,-.795,.195),grips=(.23,None),
                    lh=(.366,-.240,1.196),l_dir=(.46,-.35,-.74),curl=(1,.20),
                    cape=(-2,-6,11),scarf=(-4,1,2),bag=(-3,-4,-9))),
        (8,controls(hip=(-.017,-.011,.898),torso=(2,-8,1),head=(-7,3,19),
                    butt=(-.411,-.347,1.455),aim=(.575,-.806,.139),grips=(.245,None),
                    lh=(.369,-.125,1.154),l_dir=(.49,-.22,-.80),curl=(1,.20),
                    cape=(0,-6,8),scarf=(-7,0,3),bag=(-6,3,-5))),
        (10,controls(hip=(.025,-.059,.910),torso=(10,-3,4),head=(-8,1,20),
                     butt=(-.030,-.366,1.499),aim=(.59,-.77,.245),grips=(.30,None),
                     rh=(.155,-.455,1.603),r_dir=(.81,-.43,.40),
                     lh=(.135,.147,1.075),l_dir=(-.18,.31,-.93),curl=(.92,.15),
                     cape=(8,-4,8),scarf=(9,2,5),bag=(6,-5,5))),
        (11,controls(hip=(.045,-.075,.902),torso=(12,-4,5),head=(-10,1,21),
                     butt=(.355,-.694,1.697),aim=(.59,-.77,.245),grips=(None,None),
                     rh=(.239,-.424,1.654),r_dir=(.81,-.43,.40),
                     lh=(.130,.288,1.155),l_dir=(-.36,.59,-.72),curl=(.12,.20),
                     cape=(10,-9,4),scarf=(11,-1,9),bag=(3,-8,8))),
        (13,controls(hip=(.056,-.070,.897),torso=(14,-6,6),head=(-11,2,20),
                     butt=(.561,-1.027,1.747),aim=(.59,-.77,.245),grips=(None,None),
                     rh=(.230,-.423,1.632),r_dir=(.84,-.40,.36),
                     lh=(.122,.292,1.124),l_dir=(-.38,.58,-.72),curl=(.06,.27),
                     cape=(16,-8,1),scarf=(16,-9,8),bag=(13,-4,21))),
        (14,controls(hip=(.055,-.068,.895),torso=(14,-6,7),head=(-9,2,20),
                     butt=(.44,-1.235,1.61),aim=(.575,-.804,.148),grips=(None,None),
                     rh=(.207,-.409,1.608),r_dir=(.80,-.43,.36),
                     lh=(.110,.293,1.122),l_dir=(-.38,.58,-.72),curl=(.07,.29),
                     cape=(14,-8,3),scarf=(13,-8,7),bag=(10,-4,19),scale=.001)),
        (19,controls(hip=(.024,-.035,.911),torso=(9,-5,10),head=(-6,3,16),
                     grips=(None,None),rh=(-.165,-.408,1.355),r_dir=(.43,-.57,-.59),
                     lh=(.331,-.116,1.191),l_dir=(.45,-.61,-.42),curl=(.38,.43),scale=.001,
                     cape=(7,-5,7),scarf=(6,-6,4),bag=(-5,-4,-6))),
        (23,controls(scale=.001)),
        (24,controls()),
        (29,controls()),
    ),
    HIT: (
        (1,controls()),
        (4,controls(hip=(-.043,.028,.885),torso=(-6,-13,-14),head=(10,-7,-9),
                    butt=(-.545,-.229,.900),aim=(.78,-.28,.55),grips=(.37,.73),
                    cape=(17,-14,-1),scarf=(15,-15,5),bag=(15,14,-10))),
        (8,controls(hip=(-.027,.006,.853),torso=(17,-11,-10),head=(12,3,10),
                    butt=(-.552,-.199,.83),aim=(.72,-.40,.58),grips=(.37,.76),
                    cape=(5,-8,3),scarf=(10,-8,2),bag=(7,-7,-8))),
        (17,controls()),
    ),
    FALL: (
        (1,controls()),
        (4,controls(hip=(-.061,.029,.876),torso=(-9,-15,-14),head=(10,-7,-9),
                    butt=(-.535,-.25,.952),aim=(.79,-.41,.42),grips=(.37,.69),
                    cape=(17,-14,-1),scarf=(15,-15,5),bag=(15,14,-10))),
        (9,controls(hip=(-.10,.04,.629),torso=(31,-14,-12),head=(12,4,18),
                    rf=(-.244,.27,.163), r_toe=16, butt=(-.412,-.306,.457),aim=(.65,-.49,.56),
                    grips=(.30,.62),cape=(14,-17,4),scarf=(18,-10,-7),bag=(14,-9,-2))),
        (15,controls(hip=(-.16,.067,.430),torso=(43,-33,6),head=(19,-19,4),
                     rf=(-.30,.29,.186),lf=(.242,-.253,.117), r_toe=20,
                     butt=(-.548,-.352,.105),aim=(.73,-.68,-.039),grips=(None,None),
                     rh=(-.32,-.48,.360),lh=(.31,-.435,.333),r_dir=(-.21,-.71,-.59),
                     l_dir=(.65,-.55,-.50),curl=(.19,.22),cape=(17,-11,12),
                     scarf=(14,-10,8),bag=(11,-16,-12))),
        (22,controls(hip=(-.185,.084,.395),torso=(48,-38,5),head=(21,-26,-1),
                     rf=(-.325,.294,.175),lf=(.24,-.252,.117), r_toe=17,
                     butt=(-.596,-.340,.046),aim=(.79,-.612,0),grips=(None,None),
                     rh=(-.40,-.465,.218),lh=(.29,-.425,.251),r_dir=(-.22,-.8,-.46),
                     l_dir=(.69,-.51,-.48),curl=(.51,.48),cape=(11,-10,4),
                     scarf=(15,-11,6),bag=(6,-19,-17))),
        (25,None),
    ),
}


def rotation(angles):
    x,y,z = map(math.radians,angles)
    return (Quaternion((0,0,1),z) @ Quaternion((0,1,0),y) @ Quaternion((1,0,0),x)).to_matrix()


def frame_matrix(point, axis, up=(0,0,1)):
    y = V(axis).normalized()
    z = V(up) - y.dot(V(up))*y
    if z.length < .001:
        z = V((1,0,0))-y.x*y
    z.normalize()
    x = y.cross(z).normalized()
    return anchored(Matrix((x,y,z)).transposed().to_4x4(),point)


def anchored(matrix, at):
    result = matrix.copy()
    result.translation = V(at)
    return result


def relative(point, orient, parent_delta):
    return anchored(parent_delta @ orient.to_4x4(),parent_delta @ point)


def solve(start, target, pole, length_a, length_b):
    vector = target-start
    direction = vector.normalized()
    distance = min(length_a+length_b-.0005,max(vector.length,abs(length_a-length_b)+.0005))
    flat = pole - direction*direction.dot(pole)
    if flat.length < .0001:
        flat = direction.cross(V((1,0,0)))
    flat.normalize()
    along = (length_a*length_a + distance*distance - length_b*length_b)/(2*distance)
    bend = math.sqrt(max(0,length_a*length_a-along*along))
    return start+along*direction+bend*flat,start+distance*direction


def blend(d0,d1,t):
    def mix(a,b):
        if a is None or b is None:
            return a if t<.5 else b
        if isinstance(a,tuple):
            return tuple(mix(u,v) for u,v in zip(a,b))
        return a+(b-a)*t
    d = {key:mix(value,d1[key]) for key,value in d0.items()}
    # The authored release and prop reset are events, not eased blends.
    d["scale"] = d0["scale"]
    return d


def target_at(take,frame):
    beats = TAKES[take]
    if frame==beats[-1][0]:
        return beats[-1][1] or beats[-2][1]
    for (a,first),(b,second) in zip(beats,beats[1:]):
        if a<=frame<b:
            second = second or first
            t = (frame-a)/(b-a)
            eased = t*t*(3-2*t)
            data = blend(first,second,eased)
            # Ease the release hand between its grip-derived and free poses
            # without dragging the wrist toward the outgoing projectile.
            if take==CAST and 10<frame<11:
                data["grips"] = (None,None)
            return data
    raise ValueError((take,frame))


def transforms(rig,rest,data):
    refs = {bone.name:bone.matrix_local.copy() for bone in rig.data.bones}
    p = {}

    def delta(key):
        return p[key] @ refs[key].inverted()

    p["root"] = refs["root"].copy()
    p["pelvis"] = anchored(rotation((1,0,data["torso"][2]*.22)).to_4x4() @ refs["pelvis"],data["hip"])
    p["chest"] = relative(rest["chest"][0], rotation(data["torso"]) @ refs["chest"].to_3x3(),delta("pelvis"))
    p["neck"] = delta("chest") @ refs["neck"]
    p["head"] = relative(rest["head"][0], rotation(data["head"]) @ refs["head"].to_3x3(),delta("neck"))
    for k, parent, key in (("cape","chest","cape"),("scarf","chest","scarf"),
                            ("satchel","pelvis","bag"),("coat_tail","pelvis","coat")):
        p[k] = relative(rest[k][0],rotation(data[key]) @ refs[k].to_3x3(),delta(parent))
    direction = V(data["aim"]).normalized()
    butt = V(data["butt"])
    shaft = frame_matrix(butt,direction,(0,0,1))
    # Align the key space with the built prop's rest roll.
    shaft_base = frame_matrix(rest["harpoon"][0],(0,1,0),(0,0,1))
    shaft = shaft @ shaft_base.inverted() @ refs["harpoon"]
    p["harpoon"] = shaft @ Matrix.Diagonal((data["scale"],)*3+(1,))
    for index, (side,sign) in enumerate((("R",-1),("L",1))):
        arm,fore,hand,thigh,shin,foot = (key+"."+side for key in
                                        ("upper_arm","forearm","hand","thigh","shin","foot"))
        shoulder = delta("chest") @ rest[arm][0]
        hold = data["grips"][index]
        palm_axis = V(data["r_dir" if index==0 else "l_dir"]).normalized()
        wrist = V(data["rh" if index==0 else "lh"])
        if hold is not None:
            grip = butt+direction*hold
            approach = V((-.35 if index==0 else .14,-.76,.33))
            palm_axis = (approach-direction*approach.dot(direction)).normalized()
            wrist = grip - palm_axis*.08 + V((0,0,.014))
            hand_up = palm_axis.cross(direction)
            if hand_up.z<0:
                hand_up.negate()
        else:
            hand_up = V((.36 if index==0 else -.23,.04,1))
        pole = V((sign*.9,.25,-.89))
        if hold is None and index==1:
            pole = V((.57,.88,-.60))
        elbow, wrist = solve(shoulder,wrist,pole,.266,.267)
        p[arm] = frame_matrix(shoulder,elbow-shoulder,(-.13*sign,.3,1))
        p[fore] = frame_matrix(elbow,wrist-elbow,(0,.04,1))
        p[hand] = frame_matrix(wrist,palm_axis,hand_up)
        for i in range(4):
            key = f"finger{i}.{side}"
            palm = data["curl"][index]
            spread = (-12,-3,7,18)[i]*(1-palm)
            curl = -palm*(47+i*3)
            p[key] = anchored(
                 delta(hand).to_3x3().to_4x4() @ refs[key].to_3x3().to_4x4() @
                 rotation((curl,0,spread)).to_4x4(),delta(hand) @ rest[key][0]
            )
        key = "thumb."+side
        p[key] = anchored(delta(hand).to_3x3().to_4x4() @ refs[key].to_3x3().to_4x4() @
                          rotation((data["curl"][index]*31,0,0)).to_4x4(),delta(hand) @ rest[key][0])
        hip = delta("pelvis") @ rest[thigh][0]
        edge = "r" if index==0 else "l"
        ankle = V(data[edge+"f"])
        knee, end = solve(hip,ankle,V((.27*sign,-1,.10)),(rest[thigh][1]-rest[thigh][0]).length,
                          (rest[shin][1]-rest[shin][0]).length)
        # Keep each limb's rest roll rather than choosing a new pole at every frame.
        for bone, st, en in ((thigh,hip,knee),(shin,knee,end)):
            rest_dir = (rest[bone][1]-rest[bone][0]).normalized()
            p[bone] = anchored(rest_dir.rotation_difference((en-st).normalized()).to_matrix().to_4x4() @ refs[bone],st)
        p[foot] = anchored(rotation((data[edge+"_toe"],0,data["feet"][index])).to_4x4() @ refs[foot],end)
    return p


def animate(scene,rig,rest):
    rig.animation_data_create()
    bpy.context.view_layer.update()
    actions = {}
    last = {}
    for take,end in END.items():
        action = bpy.data.actions.new(PREFIX+take)
        action.use_fake_user = True
        rig.animation_data.action = action
        actions[take] = action
        last.clear()
        for sample in range(2,2*end+1):
            frame = sample/2
            p = ({b.name:b.matrix_local.copy() for b in rig.data.bones}
                 if take==REST else transforms(rig,rest,target_at(take,frame)))
            for bone in rig.pose.bones:
                data = bone.bone
                parent = bone.parent
                parents = ({"parent_matrix":p[parent.name],"parent_matrix_local":parent.bone.matrix_local}
                           if parent else {})
                local = data.convert_local_to_pose(p[bone.name],data.matrix_local,invert=True,**parents)
                location,quat,scale = local.decompose()
                if bone.name in last and quat.dot(last[bone.name])<0:
                    quat.negate()
                last[bone.name] = quat.copy()
                bone.location, bone.rotation_quaternion, bone.scale = location,quat,scale
                for path in ("location","rotation_quaternion") if bone.name!="harpoon" else (
                    "location","rotation_quaternion","scale"
                ):
                    bone.keyframe_insert(path,frame=frame,group=bone.name)
        # Half-frame authored FK samples use linear interpolation between keys.
        for fcurve in action.layers[0].strips[0].channelbag(rig.animation_data.action_slot).fcurves:
            for key in fcurve.keyframe_points:
                key.interpolation = "LINEAR"
                if fcurve.data_path == 'pose.bones["harpoon"].scale':
                    key.interpolation = "CONSTANT"
    for take, markers in {
        JAB:((1,"Ready"),(5,"Load"),(8,"Contact"),(23,"Ready")),
        CAST:((1,"Ready"),(8,"Aim in front"),(11,"Release"),(24,"Ready reset")),
        MOVE:((5,"Lift"),(12,"Plant"),(21,"Ready")),
        FALL:((22,"Settled defeat"),),
    }.items():
        for frame,label in markers:
            mark = actions[take].pose_markers.new(label)
            mark.frame = frame
    rig.animation_data.action = actions[READY]
    scene.frame_start,scene.frame_end = 1, END[READY]
    scene.frame_set(1)
