"""Author the Hookhand's existing movement, planted pull and reaction poses."""

import math
from pathlib import Path
import sys

import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent.parent / "harpooner"))
from pose_harpooner import anchored, frame_matrix, relative, rotation, solve

V=Vector
REST, READY, WALK, PULL, HIT, DOWN, RECOVER = (
    "Neutral T","Ready","Approach","Hook Pull","Flinch","Down","Recover"
)
PREFIX="Hookhand | "
END={REST:1,READY:39,WALK:29,PULL:43,HIT:19,DOWN:30,RECOVER:28}
COIL_EXIT=V((-.244,-.198,1.033))
LINE_ROOT=COIL_EXIT.copy()
HOOK_REST=V((.36,-.37,.765))
PULL_DIR=V((.50,-.866,0)).normalized()
HOOK_TRAVEL=.94
LINE_BONES, LINE_NODES = 19,96
SNAP_FRAME=18


def midpoint(a,b,amount=.5,drop=0):
    return V(a).lerp(V(b),amount)+V((0,0,-drop))


READY_POSE={
    "hip":(-.036,.037,.888),"torso":(25,-10,10),"head":(-15,1,19),
    "rf":(-.256,.232,.112),"lf":(.216,-.237,.112),"feet":(-23,10),
    "r_toe":0,"l_toe":0,"r_grip":(-.247,-.295,.991),"l_grip":(.266,-.371,1.023),
    "hook":(.339,-.426,.694),"arc":(.022,.118,.030),"tip":(-7,-8,11),
    "cape":(1,2,-2),"coil":(1,3,-4),"scarf":(1,2,-5),
}


def pose(**changes):
    return READY_POSE | changes


def extend(travel,z):
    return tuple(V((.258,-.349,z))+PULL_DIR*travel)


LOW=pose(hip=(-.220,.150,.429),torso=(46,-32,-8),head=(14,-25,18),
         rf=(-.35,.35,.153),lf=(.218,-.237,.112),r_toe=13,
         r_grip=(-.37,-.431,.329),l_grip=(.188,-.331,.260),
         hook=(.545,-.648,.055),arc=(.021,.047,.042),tip=(81,0,-15),
         cape=(18,-13,-6),coil=(20,-8,-9),scarf=(18,6,4))

TAKES={
    READY: (
        (1,pose()),
        (13,pose(hip=(-.037,.034,.899),torso=(24,-11,10),head=(-15,3,21),
                 hook=(.330,-.439,.702),cape=(3,3,-6),coil=(3,2,-7),scarf=(3,3,-3))),
        (27,pose(hip=(-.038,.042,.883),torso=(26,-10,10),head=(-14,0,18),
                 hook=(.336,-.421,.682),cape=(-2,1,0),coil=(-1,4,-2))),
        (39,pose()),
    ),
    WALK: (
        (1,pose()),
        (6,pose(hip=(-.041,.020,.884),torso=(25,-9,14),head=(-14,2,17),
                rf=(-.22,.148,.180),lf=(.213,-.212,.112),r_toe=13,
                hook=(.408,-.499,.807),r_grip=(-.271,-.247,1.04),l_grip=(.299,-.420,1.06),
                tip=(-11,-16,12),cape=(12,-11,2),coil=(7,-6,9),scarf=(8,-5,-2))),
        (11,pose(hip=(-.004,-.053,.910),torso=(28,-7,11),head=(-17,4,18),
                 rf=(-.173,-.244,.159),lf=(.197,.037,.112),r_toe=-12,
                 hook=(.298,-.516,.778),r_grip=(-.297,-.323,1.02),l_grip=(.257,-.417,1.06),
                 tip=(-9,-2,-4),cape=(14,-7,8),coil=(11,4,4),scarf=(12,-4,-2))),
        (16,pose(hip=(.029,-.062,.875),torso=(26,-10,16),head=(-14,2,15),
                 rf=(-.164,-.267,.112),lf=(.199,.155,.176),l_toe=13,
                 hook=(.334,-.526,.744),l_grip=(.324,-.452,1.01),
                 tip=(-4,-10,-9),cape=(18,-12,6),coil=(-2,10,-5),scarf=(10,7,5))),
        (22,pose(hip=(.012,-.035,.903),torso=(20,-9,13),head=(-13,1,17),
                 rf=(-.212,-.073,.120),lf=(.202,.010,.233),l_toe=-10,
                 hook=(.315,-.458,.707),l_grip=(.299,-.363,1.02),
                 tip=(-3,-10,2),cape=(11,-5,-11),coil=(3,-6,5),scarf=(6,4,-4))),
        (29,pose()),
    ),
    PULL: (
        (1,pose()),
        (5,pose(hip=(-.028,.014,.868),torso=(23,-8,13),head=(-13,2,15),
                r_grip=(-.206,-.30,1.113),l_grip=(.310,-.499,1.157),
                hook=extend(.43,.965),arc=(.020,.074,.045),tip=(-3,1,15),
                cape=(8,-6,5),coil=(9,-8,-6),scarf=(9,1,-2))),
        (10,pose(hip=(-.007,.008,.865),torso=(14,-8,14),head=(-12,2,17),
                r_grip=(-.121,-.380,1.172),l_grip=(.424,-.673,1.204),
                hook=extend(1.94,1.031),arc=(.030,.050,.011),tip=(-17,-12,22),
                cape=(8,-11,5),coil=(11,-8,-7),scarf=(9,-4,-2))),
        (14,pose(hip=(-.030,.051,.857),torso=(7,-10,14),head=(-9,2,18),
                r_grip=(-.192,-.305,1.204),l_grip=(.363,-.583,1.184),
                hook=extend(1.94,1.015),arc=(.025,.022,.002),tip=(-16,-12,22),
                cape=(4,-8,7),coil=(14,-11,-13),scarf=(6,-4,-4))),
        (18,pose(hip=(-.087,.149,.793),torso=(-16,-16,13),head=(9,2,22),
                r_grip=(-.284,-.148,1.282),l_grip=(.307,-.338,1.191),
                hook=extend(1.94-HOOK_TRAVEL*.82,.943),arc=(.030,.025,.001),tip=(-14,-6,21),
                cape=(-9,3,-2),coil=(-15,14,11),scarf=(-9,7,6))),
        (22,pose(hip=(-.108,.160,.791),torso=(-19,-14,14),head=(13,3,21),
                r_grip=(-.271,-.142,1.248),l_grip=(.294,-.295,1.171),
                hook=extend(1.94-HOOK_TRAVEL,.930),arc=(.034,.026,.004),tip=(-12,-5,18),
                cape=(-12,7,-4),coil=(-13,8,8),scarf=(-13,6,6))),
        (29,pose(hip=(-.081,.101,.854),torso=(-4,-8,12),head=(1,4,22),
                r_grip=(-.284,-.246,1.137),l_grip=(.294,-.393,1.078),
                hook=extend(.64,.767),arc=(.027,.064,.065),tip=(-3,-8,14),
                cape=(-4,6,-3),coil=(-4,7,4),scarf=(-5,1,3))),
        (36,pose(hip=(-.039,.044,.888),torso=(21,-9,10),head=(-12,1,19),
                r_grip=(-.257,-.28,1.025),l_grip=(.276,-.352,1.038),
                hook=(.365,-.461,.682),arc=(.023,.135,.027),tip=(-9,-8,11),
                cape=(4,-3,-4),coil=(4,-3,-9))),
        (43,pose()),
    ),
    HIT: (
        (1,pose()),
        (5,pose(hip=(-.098,.089,.851),torso=(-8,-19,-8),head=(13,-16,12),
                r_grip=(-.355,-.174,1.129),l_grip=(.282,-.348,1.132),
                hook=(.456,-.499,.808),tip=(-17,-22,16),
                cape=(17,-10,9),coil=(15,-3,-7),scarf=(17,4,12))),
        (9,pose(hip=(-.052,.058,.852),torso=(23,-16,6),head=(-5,1,11),
                r_grip=(-.278,-.256,1.027),l_grip=(.241,-.388,1.034),
                hook=(.359,-.414,.755),tip=(-4,-1,-6),
                cape=(16,3,13),coil=(7,-4,5),scarf=(8,5,5))),
        (19,pose()),
    ),
    DOWN: (
        (1,pose()),
        (5,pose(hip=(-.099,.072,.842),torso=(-6,-15,9),head=(13,-12,15),
                r_grip=(-.302,-.196,1.084),l_grip=(.312,-.336,1.091),
                hook=(.461,-.463,.795),tip=(-11,-26,19),cape=(10,-9,9),coil=(12,-9,-3))),
        (11,pose(hip=(-.130,.085,.680),torso=(19,-19,14),head=(6,-14,17),
                 rf=(-.275,.267,.163),r_toe=14, r_grip=(-.340,-.342,.777),
                 l_grip=(.254,-.399,.829),hook=(.493,-.554,.531),tip=(9,-15,23),
                 cape=(18,-13,12),coil=(22,-4,11),scarf=(4,-12,4))),
        (19,pose(hip=(-.191,.130,.473),torso=(41,-28,-2),head=(13,-22,17),
                 rf=(-.329,.326,.165),r_toe=16,r_grip=(-.364,-.422,.371),
                 l_grip=(.210,-.388,.351),hook=(.569,-.637,.125),arc=(.028,.073,.095),
                 tip=(72,-4,-17),cape=(20,-14,-1),coil=(22,-8,-4),scarf=(15,8,7))),
        (25,LOW),(30,LOW),
    ),
}
TAKES[RECOVER]=((1,LOW),(7,TAKES[DOWN][3][1]),(13,TAKES[DOWN][2][1]),
                (20,pose(hip=(-.086,.094,.841),torso=(23,-11,12),head=(-11,1,20),
                         rf=(-.289,.316,.166),r_toe=-9,hook=(.438,-.544,.660),
                         r_grip=(-.302,-.267,1.012),l_grip=(.270,-.421,1.013),
                         cape=(7,-7,-2),coil=(4,4,11))),
                (28,pose()))


def sample(take, f):
    beats=TAKES[take]
    if f==beats[-1][0]:
        return beats[-1][1]
    for (lo,a),(hi,b) in zip(beats,beats[1:]):
        if lo <= f < hi:
            u=(f-lo)/(hi-lo)
            u=u*u*(3-2*u)
            return {k:tuple(V(v).lerp(V(b[k]),u)) if isinstance(v,tuple) else v+(b[k]-v)*u
                    for k,v in a.items()}
    raise ValueError((take,f))


def path(pts, ratios=(6,6,6)):
    anchors=[]
    for segment,(a,m,b) in enumerate(pts):
        for i in range(ratios[segment]):
            t=i/ratios[segment]
            anchors.append(((1-t)**2)*a+2*t*(1-t)*m+t*t*b)
    anchors.append(pts[-1][-1])
    return anchors


def pose_matrices(rest,refs,d):
    p={}
    def delta(b):
        return p[b] @ refs[b].inverted()
    def orient(k,parent,angles):
        p[k]=relative(rest[k][0], rotation(angles) @ refs[k].to_3x3(),delta(parent))
    def steer(k,a,b,fallback):
        base=(rest[k][1]-rest[k][0]).normalized()
        axis=(b-a).normalized()
        p[k]=anchored(base.rotation_difference(axis).to_matrix().to_4x4()@fallback,a)

    p["root"]=refs["root"]
    p["pelvis"]=anchored(rotation((1,-3,d["torso"][2]*.18)).to_4x4()@refs["pelvis"],d["hip"])
    orient("chest","pelvis",d["torso"])
    p["neck"]=delta("chest")@refs["neck"]
    orient("head","neck",d["head"])
    orient("mantle","chest",d["cape"])
    orient("scarf","chest",d["scarf"])
    orient("coil","pelvis",d["coil"])
    coil=delta("coil")@COIL_EXIT
    actual=[]
    for i,(side,s) in enumerate((("R",-1),("L",1))):
        upper,fore,hand,hip,shin,foot=(k+"."+side for k in
                                      ("upper_arm","forearm","hand","thigh","shin","foot"))
        k=side.lower()
        shoulder=delta("chest")@rest[upper][0]
        grip=V(d[k+"_grip"])
        palm_axis=V((-.10 if i==0 else .22,-.55,-.83)).normalized()
        pol=V((s*.72,.88,-.35))
        elbow,wrist=solve(shoulder,grip-palm_axis*.074,pol,.282,.283)
        p[upper]=frame_matrix(shoulder,elbow-shoulder,(s*-.2,.33,1))
        p[fore]=frame_matrix(elbow,wrist-elbow,(0,.09,1))
        p[hand]=frame_matrix(wrist,palm_axis,(-s*.31,-.23,.77))
        actual.append(wrist+palm_axis*.077)
        for digit in range(5):
            name=("thumb" if digit==4 else f"finger{digit}")+"."+side
            orient(name,hand,(22 if digit==4 else -47-digit*5,0,0))
        h=delta("pelvis")@rest[hip][0]
        goal=V(d[k+"f"])
        knee,ankle=solve(h,goal,V((s*.29,-1,.15)),(rest[hip][1]-rest[hip][0]).length,
                         (rest[shin][1]-rest[shin][0]).length)
        steer(hip,h,knee,refs[hip])
        steer(shin,knee,ankle,refs[shin])
        p[foot]=anchored(rotation((d[k+"_toe"],0,d["feet"][i])).to_4x4()@refs[foot],ankle)
    hook=V(d["hook"])
    p["hook"]=anchored(rotation(d["tip"]).to_4x4()@refs["hook"],hook)
    eye=delta("hook")@(HOOK_REST+V((0,0,.041)))
    r,l=actual
    landing=r.lerp(l,.49)+V((0,-.081,0))
    droop=d["arc"]
    nodes=path((
        (coil,midpoint(coil,r,drop=droop[0])+V((-.009,-.022,0)),r),
        (r,landing+V((0,0,-droop[1])),l),
        (l,midpoint(l,eye,drop=droop[2]),eye),
    ))
    orig=(HOOK_REST-LINE_ROOT).normalized()
    for i,center in enumerate(nodes):
        k=f"line.{i:02}"
        tangent=(nodes[min(i+1,LINE_BONES-1)]-nodes[max(0,i-1)]).normalized()
        adjustment=orig.rotation_difference(tangent).to_matrix().to_4x4()
        p[k]=anchored(adjustment@refs[k],center)
    return p


def animate(s,rig,rest):
    rig.animation_data_create()
    refs={b.name:b.matrix_local.copy() for b in rig.data.bones}
    actions={}
    for name,end in END.items():
        act=bpy.data.actions.new(PREFIX+name)
        act.use_fake_user=True
        rig.animation_data.action=act
        actions[name]=act
        last={}
        for n in range(2,2*end+1):
            frame=n/2
            p=refs if name==REST else pose_matrices(rest,refs,sample(name,frame))
            for bone in rig.pose.bones:
                parent=bone.parent
                parents=({"parent_matrix":p[parent.name],"parent_matrix_local":refs[parent.name]} if parent else {})
                basis=bone.bone.convert_local_to_pose(p[bone.name],refs[bone.name],invert=True,**parents)
                l,r,_=basis.decompose()
                if bone.name in last and last[bone.name].dot(r)<0:
                    r.negate()
                last[bone.name]=r
                bone.location,bone.rotation_quaternion=l,r
                for prop in ("location","rotation_quaternion"):
                    bone.keyframe_insert(prop,frame=frame,group=bone.name)
        for fc in act.layers[0].strips[0].channelbag(rig.animation_data.action_slot).fcurves:
            for key in fc.keyframe_points:
                key.interpolation="LINEAR"
    markers={
        PULL:((1,"Ready"),(10,"Line takes tension"),(14,"Brace"),(SNAP_FRAME,"Haul"),(22,"Settle"),(43,"Ready")),
        WALK:((11,"Lead boot"),(22,"Trail boot"),(29,"Ready")),
        DOWN:((25,"Hold"),),
    }
    for take,items in markers.items():
        for frame,label in items:
            actions[take].pose_markers.new(label).frame=frame
    rig.animation_data.action=actions[READY]
    s.frame_start,s.frame_end=1,END[READY]
    s.frame_set(1)
