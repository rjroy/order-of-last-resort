"""Author world-space performance beats and sample them into editable FK."""
import math

import bpy
from mathutils import Euler, Matrix, Vector

V=Vector

BASES={
    "bandit_damage":dict(hip=(-.062,.049,.829),torso=(29,-14,-3),head=(-15,5,21),
        rf=(-.288,.255,.113),lf=(.276,-.316,.113),yaw=(-16,18),toe=(0,0),
        r=(-.280,-.420,.956),l=(.40,-.335,1.06),a=(.94,-.32,-.115),b=(-.32,-.44,-.82),other=(.2,-.60,-.79),
        cape=(11,-8,-7),tail=(7,4,2),hair=(3,-2,4)),
    "bandit_guard":dict(hip=(.019,.063,.778),torso=(16,-5,2),head=(-8,4,10),
        rf=(-.285,.182,.113),lf=(.298,-.259,.113),yaw=(-16,19),toe=(0,0),
        r=(-.333,-.372,1.15),l=(.289,-.329,.991),a=(.20,-.09,.976),b=(.88,-.44,-.08),other=(.37,-.26,-.89),
        cape=(0,0,0),tail=(3,6,0),hair=(0,0,0)),
    "bandit_swift":dict(hip=(.015,.054,.975),torso=(18,-8,7),head=(-11,1,18),
        rf=(-.163,.220,.113),lf=(.207,-.29,.113),yaw=(-13,19),toe=(0,0),
        r=(-.213,-.235,1.151),l=(.374,-.374,1.018),a=(.78,-.60,.125),b=(-.31,-.48,-.82),other=(.21,-.75,-.63),
        cape=(0,0,0),tail=(9,-7,-12),hair=(8,-1,-8)),
}


def scores(role):
    ready=BASES[role]
    done={}
    R=lambda **k: ready|k
    def add(name, beats, labels=()):
        done[name]=(beats,labels)
    add("Ready",[(1,R()),(11,R(hip=(ready["hip"][0]+.006,ready["hip"][1]-.009,ready["hip"][2]+.012),
         torso=(ready["torso"][0]+2,*ready["torso"][1:]),hair=(6,3,8))),
         (23,R(hip=(ready["hip"][0]-.007,ready["hip"][1]+.007,ready["hip"][2]-.008),
          torso=(ready["torso"][0]-1,*ready["torso"][1:]),hair=(-3,1,-2))),(33,R())])
    if role=="bandit_damage":
        add("Move",[(1,R()),(5,R(hip=(-.114,.020,.846),lf=(.260,-.09,.205),toe=(0,8),torso=(27,-7,-7))),
            (9,R(hip=(.016,-.070,.854),lf=(.231,-.39,.151),rf=(-.249,.136,.178),toe=(6,-5),cape=(17,-7,-3))),
            (14,R(hip=(.084,-.045,.833),rf=(-.231,-.064,.220),lf=(.25,-.31,.113),torso=(26,0,14),cape=(15,-7,2))),
            (20,R())],((9,"Front plant"),))
        load=R(hip=(-.091,.111,.854),torso=(13,-16,-28),head=(-6,4,32),r=(-.355,.006,1.279),
               a=(.44,-.160,.88),b=(-.10,-.7,-.71),cape=(-8,8,-15),hair=(-5,9,-16))
        cut=R(hip=(.057,-.044,.824),torso=(30,-16,18),head=(-17,3,-2),r=(-.16,-.474,1.280),
              a=(.86,-.50,-.14),b=(-.16,-.41,-.9),cape=(9,-4,-5),tail=(10,9,6),hair=(11,-5,9))
        settle=R(hip=(.085,-.075,.808),torso=(34,-16,24),head=(-13,7,-5),r=(-.066,-.505,.964),
                a=(.86,-.43,-.24),b=(.0,-.47,-.88),cape=(21,-4,12),tail=(20,2,8),hair=(16,-8,12))
        add("Melee",[(1,R()),(6,load),(10,cut),(14,settle),(24,R())],((6,"Shoulder load"),(10,"Contact"),(14,"Follow-through")))
        heavy_load=load|dict(hip=(-.123,.133,.818),torso=(5,-18,-39),head=(-5,3,44),
                             r=(-.424,.011,1.279),a=(.13,.092,.987),cape=(-13,12,-27))
        heavy_cut=cut|dict(hip=(.115,-.122,.756),torso=(35,-19,26),head=(-22,6,-9),
                           lf=(.265,-.408,.113),r=(-.043,-.587,1.190),a=(.56,-.79,-.24),cape=(12,-12,-10))
        heavy_settle=settle|dict(hip=(.156,-.182,.735),torso=(44,-19,30),head=(-19,7,-10),
                                lf=(.266,-.412,.113),rf=(-.27,.24,.168),toe=(10,0),
                                r=(.062,-.587,.868),a=(.85,-.51,-.27),cape=(27,-11,17),hair=(22,-12,13))
        add("Harder Strike",[(1,R()),(8,heavy_load),(12,heavy_cut),(17,heavy_settle),
             (23,settle),(31,R())],((8,"Deeper load"),(12,"Contact"),(17,"Long follow-through")))
        add("Hit",[(1,R()),(4,R(hip=(-.093,.100,.855),torso=(-2,-22,-17),head=(14,-12,-12),
             r=(-.350,-.320,1.251),a=(.91,-.34,.154),cape=(15,5,-19),hair=(15,-17,-9))),
             (9,R(hip=(-.057,.039,.831),torso=(28,-8,3),r=(-.339,-.371,1.067))),(17,R())],((4,"Impact recoil"),))
        terminal=R(hip=(-.161,.069,.441),torso=(57,-28,-4),head=(-7,-5,12),rf=(-.279,.22,.157),toe=(0,0),
             r=(-.266,-.365,.307),a=(.85,-.46,-.11),b=(-.07,-.34,-.93),lf=(.264,-.26,.113),
             cape=(11,-15,4),hair=(15,-7,18),tail=(10,-18,-4))
    elif role=="bandit_guard":
        add("Move",[(1,R()),(5,R(hip=(-.040,.061,.834),rf=(-.249,.017,.169),toe=(10,0))),
            (10,R(hip=(-.031,-.053,.842),rf=(-.257,-.203,.113),lf=(.261,-.066,.173),toe=(0,7),
                  r=(-.351,-.414,1.14),torso=(21,-4,-5))),
            (15,R(hip=(.063,.001,.81),rf=(-.26,.125,.131),lf=(.269,-.350,.113),toe=(4,0))),
            (22,R())],((10,"Heavy plant"),))
        ready_cudgel=(.289,-.329,.991)
        add("Melee",[(1,R()),(6,R(hip=(.043,.106,.798),torso=(4,6,21),head=(0,-6,-16),
              l=(.42,.04,1.26),b=(.46,.25,.85),other=(.26,-.26,-.92))),
             (10,R(hip=(.072,-.088,.798),torso=(27,3,-13),head=(-16,2,23),
              r=(-.35,-.354,1.108),a=(.18,-.14,.97),l=(.26,-.544,1.221),b=(.46,-.86,-.19),other=(.54,-.3,-.78))),
             (14,R(hip=(.054,-.021,.797),torso=(22,-2,-14),l=(.13,-.49,1.019),
              b=(.70,-.53,-.48),other=(.31,-.55,-.77))),(23,R())],((6,"Cudgel lift"),(10,"Contact")))
        brace=R(hip=(.012,.047,.682),torso=(30,-3,3),head=(-12,0,12),r=(-.092,-.445,1.166),
                a=(.05,-.10,.994),l=(.222,-.296,.935),b=(.74,-.64,.21),other=(.23,-.56,-.79))
        add("Brace",[(1,R()),(4,R(hip=(.006,.055,.795),torso=(18,-4,1),r=(-.275,-.423,1.19))),
            (8,brace),(16,brace|dict(hip=(.012,.057,.690),r=(-.133,-.460,1.166),head=(-9,1,13))),
            (23,R())],((8,"Buckler seals sternum"),(16,"Feet hold")))
        add("Hit",[(1,R()),(4,R(hip=(.043,.106,.801),torso=(-2,9,5),head=(11,-7,0),
            r=(-.335,-.301,1.206),a=(.35,-.2,.91),l=(.30,-.24,1.045),b=(.71,-.24,.65))),
            (10,R(hip=(.031,.035,.784),torso=(22,-4,5),l=ready_cudgel)),(18,R())],((4,"Impact recoil"),))
        terminal=R(hip=(-.177,.141,.448),torso=(62,-20,0),head=(-5,2,16),rf=(-.257,.216,.174),
            toe=(0,0),r=(-.357,-.248,.432),a=(.15,-.09,.98),l=(.229,-.278,.329),
            other=(.45,-.27,-.82),b=(.68,-.69,-.15),lf=(.269,-.22,.113))
    else:
        add("Move",[(1,R()),(4,R(hip=(-.055,.031,.958),lf=(.22,-.146,.21),toe=(0,-8),torso=(23,-8,3),tail=(18,2,-14))),
            (8,R(hip=(.047,-.083,.963),lf=(.229,-.347,.113),rf=(-.151,.166,.169),toe=(16,0),
              r=(-.21,-.271,1.132),l=(.38,-.39,1.08),torso=(27,-7,9),hair=(21,-5,-11))),
            (12,R(hip=(.044,-.071,.978),rf=(-.156,-.055,.255),lf=(.203,-.29,.113),toe=(-15,0),
              l=(.293,-.403,1.02),tail=(22,-7,-10))),(17,R())],((8,"Plant"),))
        skim=R(hip=(.075,-.113,1.007),torso=(33,-13,11),head=(-19,4,12),
            rf=(-.318,.301,.246),lf=(.387,-.473,.265),toe=(18,-23),r=(-.195,-.232,1.104),
            a=(.74,-.67,-.09),l=(.465,-.431,1.060),other=(.54,-.71,-.45),hair=(22,-14,-19),tail=(31,-10,-22))
        add("Quick Step",[(1,R()),(3,R(hip=(-.066,.046,.910),rf=(-.190,.199,.113),lf=(.201,-.259,.135),
             toe=(0,7),torso=(31,-10,6),r=(-.240,-.258,1.078),l=(.345,-.378,.992),tail=(18,-12,-15),hair=(11,-4,-12))),
             (6,skim),(9,R(hip=(.096,-.135,.934),rf=(-.059,.028,.294), lf=(.298,-.428,.115),
             toe=(-6,0),torso=(31,-8,12),r=(-.182,-.287,1.092),l=(.38,-.427,1.067),hair=(27,-12,-18),tail=(33,-12,-20))),
             (12,R(hip=(.061,-.105,.982),rf=(-.153,-.107,.205),lf=(.2,-.32,.113),
             toe=(-12,0),l=(.388,-.384,1.032),hair=(12,-6,-13),tail=(19,-8,-14))),
             (16,R())],((3,"Coil"),(6,"Airy passing stride"),(9,"Fast plant")))
        add("Melee",[(1,R()),(4,R(hip=(-.070,.067,.958),torso=(15,-8,-13),head=(-7,2,24),
             r=(-.320,-.067,1.278),a=(.60,-.20,.77),l=(.297,-.344,1.04),hair=(-7,-11,11))),
            (7,R(hip=(.048,-.075,.944),torso=(29,-9,19),head=(-16,2,9),r=(.077,-.543,1.219),
             a=(.71,-.70,.04),b=(-.51,-.34,-.80),l=(.32,-.289,.977),other=(.47,-.52,-.71),tail=(24,4,6),hair=(16,-6,-12))),
            (11,R(hip=(.071,-.081,.927),torso=(24,-6,25),r=(.157,-.472,1.084),
             a=(.82,-.50,-.27),b=(-.26,-.31,-.92),l=(.301,-.383,1.045))),(18,R())],((4,"Knife load"),(7,"Contact")))
        add("Hit",[(1,R()),(3,R(hip=(-.102,.110,.932),torso=(-3,-18,-22),head=(15,-13,-12),
             r=(-.264,-.238,1.288),a=(.58,-.62,.48),l=(.267,-.412,1.099),hair=(-15,-6,12))),
             (7,R(hip=(-.069,.052,.927),torso=(24,-10,-2),r=(-.26,-.27,1.108),hair=(10,4,13))),
             (15,R())],((3,"Impact recoil"),))
        terminal=R(hip=(-.141,.117,.396),torso=(59,-34,-2),head=(-7,-3,13),rf=(-.211,.217,.156),
             lf=(.236,-.249,.113),toe=(0,0),r=(-.215,-.393,.291),l=(.241,-.290,.363),
             a=(.77,-.59,-.12),other=(.13,-.69,-.70),hair=(18,-9,8),tail=(3,12,13))
    start_fall=done["Hit"][0][1][1]
    fold=terminal|dict(hip=(terminal["hip"][0]*.71,terminal["hip"][1]*.82,terminal["hip"][2]+.235),
        torso=(32,terminal["torso"][1]*.63,1),r=(terminal["r"][0],terminal["r"][1],terminal["r"][2]+.42),
        l=(terminal["l"][0],terminal["l"][1],terminal["l"][2]+.32))
    add("Defeat",[(1,R()),(4,start_fall),(10,fold),(20,terminal),(25,terminal)],((10,"Fold"),(20,"Hold down")))
    return done


def rotation(vals):
    return Euler(tuple(map(math.radians,vals)),"XYZ").to_matrix()


def located(mat,p):
    result=mat.to_4x4()
    result.translation=p
    return result


def basis(p,y,z=(0,0,1)):
    y=V(y).normalized()
    z=V(z)-V(z).dot(y)*y
    if z.length<1e-4:
        w=V((1,0,0)) if abs(y.x)<.8 else V((0,0,1))
        z=w-w.dot(y)*y
    z.normalize()
    return located(Matrix((y.cross(z),y,z)).transposed(),p)


def perpendicular(axis,wanted):
    wanted=V(wanted)
    return (wanted-axis*axis.dot(wanted)).normalized()


def solve(origin,target,pole,a,b):
    difference=target-origin
    direction=difference.normalized()
    distance=max(abs(a-b)+.0003,min(difference.length,a+b-.0003))
    flat=perpendicular(direction,pole)
    along=(a*a+distance*distance-b*b)/(2*distance)
    return origin+direction*along+flat*math.sqrt(max(0,a*a-along*along)),origin+direction*distance


def move_basis(refs,rest,name,start,end):
    source=(rest[name][1]-rest[name][0]).normalized()
    swing=source.rotation_difference((end-start).normalized()).to_matrix()
    return located(swing@refs[name].to_3x3(),start)


def compose(role,refs,rest,d):
    p={"root":refs["root"].copy()}
    def delta(b):
        return p[b]@refs[b].inverted()
    def relative(k,parent,angles):
        p[k]=located(delta(parent).to_3x3()@rotation(angles)@refs[k].to_3x3(),delta(parent)@rest[k][0])
    p["pelvis"]=located(rotation((2,0,d["torso"][2]*.25))@refs["pelvis"].to_3x3(),V(d["hip"]))
    relative("chest","pelvis",d["torso"])
    relative("neck","chest",(0,0,0))
    relative("head","neck",d["head"])
    relative("mantle","chest",d["cape"])
    kind=role.removeprefix("bandit_")
    first_axis,second_axis=V(d["a"]).normalized(),V(d["b"]).normalized()
    shared_origin=V(d["r"])
    if kind=="damage":
        # The axe is one rigid shaft. Find the closest reachable position to
        # the authored target in the common reach of both wrists.
        reach=[]
        for i,s in enumerate(("R","L")):
            upper,fore="upper_arm."+s,"forearm."+s
            aim=perpendicular(first_axis,second_axis if i==0 else (.50,-.54,-.69))
            normal=aim.cross(first_axis)
            if normal.z<0:
                normal.negate()
            center=delta("chest")@rest[upper][0]+.076*aim-.010*normal-i*.287*first_axis
            limit=sum((rest[k][1]-rest[k][0]).length for k in (upper,fore))-.002
            reach.append((center,limit))
        for _ in range(8):
            for center,limit in reach:
                vector=shared_origin-center
                if vector.length>limit:
                    shared_origin=center+vector.normalized()*limit
    for i,(s,sign) in enumerate((("R",-1),("L",1))):
        arm,fore,hand,thigh,shin,foot,prop=(key+"."+s for key in
            ("upper_arm","forearm","hand","thigh","shin","foot","grip"))
        relative("tail."+s,"pelvis",d["tail"] if i==0 else (d["tail"][0]*.78,-d["tail"][1]*.88,d["tail"][2]*.61))
        relative("hair."+s,"head",d["hair"] if i==0 else (-d["hair"][0]*.5,d["hair"][1],d["hair"][2]*.64))
        grip=V(d["r" if i==0 else "l"])
        axis=first_axis if i==0 else second_axis
        if kind=="damage":
            axis=first_axis
            grip=shared_origin+i*.287*axis
            aim=perpendicular(axis,second_axis if i==0 else (.50,-.54,-.69))
            normal=aim.cross(axis)
            if normal.z<0:
                normal=-normal
            prop_up=perpendicular(axis,(-.30,-.66,.69))
        elif kind=="guard" and i==0:
            # Center-held buckler, rotated into a compact cover rather than raised like a wall shield.
            normal=perpendicular(axis,(-.61,-.76,.065))
            aim=perpendicular(axis,(.74,-.52,-.50))
            prop_up=normal
        elif kind=="guard":
            aim=perpendicular(axis,V(d["other"]))
            normal=aim.cross(axis)
            if normal.z<0:
                normal=-normal
            prop_up=perpendicular(axis,(-.25,-.15,.93))
        elif i==0:
            aim=perpendicular(axis,second_axis)
            normal=aim.cross(axis)
            if normal.z<0:
                normal=-normal
            prop_up=perpendicular(axis,(-.24,-.53,.81))
        else:
            aim=V(d["other"]).normalized()
            normal=perpendicular(aim,(.30,-.11,1))
            prop_up=(0,0,1)
        a=delta("chest")@rest[arm][0]
        target=grip-.076*aim+.010*normal
        lengths=[(rest[k][1]-rest[k][0]).length for k in (arm,fore)]
        elbow,wrist=solve(a,target,(sign*1.05,.20,-.83),*lengths)
        p[arm]=basis(a,elbow-a,(0,.25,1))
        p[fore]=basis(elbow,wrist-elbow,(0,.15,1))
        p[hand]=basis(wrist,aim,normal)
        # Move the active mount with the solved wrist. The full-span check also
        # measures the second hand against the Fierce attack's same fixed haft.
        actual_grip=wrist+.076*aim-.010*normal
        authored=basis(rest[prop][0],(0,1,0))
        p[prop]=basis(actual_grip,axis,prop_up)@authored.inverted()@refs[prop]
        h=delta("pelvis")@rest[thigh][0]
        ankle=V(d["rf" if i==0 else "lf"])
        # Preserve the same planted-knee line throughout every action.
        lengths=[(rest[k][1]-rest[k][0]).length for k in (thigh,shin)]
        knee,end=solve(h,ankle,(sign*.18,-1,.05),*lengths)
        p[thigh]=move_basis(refs,rest,thigh,h,knee)
        p[shin]=move_basis(refs,rest,shin,knee,end)
        p[foot]=located(rotation((d["toe"][i],0,d["yaw"][i]))@refs[foot].to_3x3(),end)
    return p


def blend(a,b,t):
    return {key:tuple(x+(y-x)*t for x,y in zip(value,b[key])) for key,value in a.items()}


def sample(beats,frame):
    if frame==beats[-1][0]:
        return beats[-1][1]
    for (a,av),(b,bv) in zip(beats,beats[1:]):
        if a<=frame<b:
            t=(frame-a)/(b-a)
            return blend(av,bv,t*t*(3-2*t))
    raise ValueError(frame)


def animate(scene,rig,rest,role,title):
    rig.animation_data_create()
    refs={b.name:b.matrix_local.copy() for b in rig.data.bones}
    actions={}
    for name,(beats,markers) in {"Neutral T":([(1,None)],()),**scores(role)}.items():
        action=bpy.data.actions.new(title+" | "+name)
        action.use_fake_user=True
        rig.animation_data.action=action
        actions[name]=action
        last={}
        for half in range(2,beats[-1][0]*2+1):
            frame=half/2
            pose=refs if name=="Neutral T" else compose(role,refs,rest,sample(beats,frame))
            for bone in rig.pose.bones:
                p=bone.parent
                inputs={"parent_matrix":pose[p.name],"parent_matrix_local":p.bone.matrix_local} if p else {}
                local=bone.bone.convert_local_to_pose(pose[bone.name],refs[bone.name],invert=True,**inputs)
                location,quat,_=local.decompose()
                if bone.name in last and quat.dot(last[bone.name])<0:
                    quat.negate()
                last[bone.name]=quat.copy()
                bone.location,bone.rotation_quaternion=location,quat
                for path in ("location","rotation_quaternion"):
                    bone.keyframe_insert(path,frame=frame,group=bone.name)
        bag=action.layers[0].strips[0].channelbag(rig.animation_data.action_slot)
        for channel in bag.fcurves:
            for k in channel.keyframe_points:
                k.interpolation="LINEAR"
        for frame,label in markers:
            action.pose_markers.new(label).frame=frame
    rig.animation_data.action=actions["Ready"]
    scene.frame_start,scene.frame_end=1,33
    scene.frame_set(1)
