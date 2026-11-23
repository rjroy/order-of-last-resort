"""Create the editable Wagon Raider candidate in Blender 5.2.2."""

from math import cos, pi, radians, sin, sqrt
from pathlib import Path
import sys
import bpy

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "model-tools" / "wagon"))
from model_tools import Model, Vector, Matrix, axes, pigment


def xyz(*data):
    return Vector(data)


def spec(tag, p, end, parent, family, right=(1,0,0)):
    return tag, p, end, parent, family, right


def skeleton():
    s = [spec("origin",(0,0,0),(0,0,.15),None,"Anchor"),
         spec("hips",(0,.025,.934),(0,.025,1.067),"origin","Trunk"),
         spec("chest",(0,.022,1.075),(0,.014,1.394),"hips","Trunk"),
         spec("neck",(0,.012,1.415),(0,.000,1.516),"chest","Trunk"),
         spec("head",(0,.004,1.507),(0,.004,1.746),"neck","Trunk"),
         spec("tie",(-.014,.118,1.732),(-.017,.263,1.753),"head","Cloth"),
         spec("sash",(.064,-.147,1.035),(.08,-.192,.764),"hips","Cloth"),
         spec("sash.short",(-.077,-.139,1.027),(-.15,-.212,.834),"hips","Cloth"),
         spec("wedge_socket",(.025,-.304,1.06),(.605,-.304,1.06),"origin","Two-hand prop",(0,1,0))]
    for key, sign in (("L",-1),("R",1)):
        clav, shoulder, elbow, wrist, hand = [(sign*x,y,z) for x,y,z in
            [(.086,.015,1.392),(.218,.015,1.392),(.496,.015,1.392),
             (.722,.015,1.392),(.836,.015,1.392)]]
        hip,knee,ankle,toe = [(sign*x,y,z) for x,y,z in
            [(.115,.026,.944),(.141,.004,.543),(.162,.028,.127),(.163,-.126,.076)]]
        s.extend((spec("clavicle."+key,clav,shoulder,"chest","Hands",(0,-1,0)),
                  spec("upper_arm."+key,shoulder,elbow,"clavicle."+key,"Hands",(0,-1,0)),
                  spec("forearm."+key,elbow,wrist,"upper_arm."+key,"Hands",(0,-1,0)),
                  spec("hand."+key,wrist,hand,"forearm."+key,"Hands",(0,-1,0)),
                  spec("thigh."+key,hip,knee,"hips","Feet"),
                  spec("shin."+key,knee,ankle,"thigh."+key,"Feet"),
                  spec("boot."+key,ankle,toe,"shin."+key,"Feet")))
    return s


def materials():
    definitions = {
        "skin": ("Sun-dried warm skin",(.37,.161,.082),(.77,.463,.27),6),
        "skin_dark": ("Sunshadow",(.24,.095,.055),(.58,.294,.148),7),
        "skin_light": ("Nose and knuckles",(.48,.207,.103),(.82,.553,.34),7),
        "hair": ("Crooked espresso hair",(.039,.019,.014),(.152,.083,.048),7),
        "dark": ("Stubble and lash",(.03,.017,.012),(.098,.052,.031),12),
        "tooth": ("Ivory eye whites",(.63,.49,.31),(.89,.807,.61),5),
        "bandana": ("Smoked violet linen",(.116,.067,.082),(.337,.233,.252),11),
        "bandana_light": ("Turned bandana edge",(.175,.100,.116),(.435,.301,.307),12),
        "vest": ("Charcoal boiled hide",(.062,.039,.027),(.195,.115,.069),9),
        "hem": ("Worn saddle hide",(.131,.060,.029),(.358,.207,.107),8),
        "thread": ("Worn tan topstitch",(.329,.154,.067),(.611,.383,.171),11),
        "glove": ("Dark tawny gauntlets",(.104,.041,.017),(.315,.155,.077),8),
        "knuckle": ("Scuffed gauntlet leather",(.161,.064,.029),(.422,.239,.128),9),
        "brass": ("Pitted buckles",(.243,.125,.042),(.620,.408,.180),10),
        "trouser": ("Soot plum trousers",(.117,.076,.076),(.306,.209,.185),12),
        "patch": ("Coarse ochre mend",(.209,.101,.042),(.517,.305,.140),9),
        "wrap": ("Cream split linen",(.403,.274,.148),(.785,.652,.444),11),
        "sash": ("Brick red hacked sash",(.207,.058,.044),(.510,.194,.128),11),
        "boot": ("Mule leather boots",(.101,.049,.029),(.295,.164,.100),8),
        "sole": ("Dirty rawhide sole",(.056,.030,.021),(.174,.095,.061),9),
        "steel": ("Dented charcoal steel",(.146,.128,.113),(.461,.397,.337),9),
        "edge": ("Scoured facets",(.292,.261,.224),(.676,.593,.496),8),
        "rust": ("Iron oxide pits",(.135,.048,.024),(.295,.136,.075),10),
        "ash": ("Adze-cut ash handle",(.206,.100,.038),(.588,.381,.168),7),
    }
    return {k:pigment(name, dark, light, scale, .69 if k in ("steel","edge","brass") else .83)
            for k,(name,dark,light,scale) in definitions.items()}


def ribbon(m, name, rows, mat, bone, thickness=.014):
    mesh = m.mesh(name, [p for row in rows for p in row],
                  [(3*i+j,3*i+j+1,3*i+j+4,3*i+j+3)
                   for i in range(len(rows)-1) for j in range(2)], mat, bone, smooth=True)
    mod = mesh.modifiers.new("Fabric thickness", "SOLIDIFY")
    mod.thickness = thickness
    return mesh


def buckle(m, name, center, width, height, mat, bone):
    x,y,z = center
    m.line(name, [(x+width*dx,y,z+height*dz) for dx,dz in
                  [(-.5,-.44),(-.42,-.5),(.41,-.5),(.5,-.4),
                   (.5,.37),(.40,.5),(-.42,.5),(-.5,.34)]],
            .0085, mat, bone, closed=True)
    m.line(name+" tongue", [(x-width*.43,y-.003,z),(x+width*.28,y-.003,z+.009)], .006,mat,bone)


def build_body(m,p):
    m.category = "01 | Vest, belts and wind-torn sash"
    def shell(name,a,b,rings,mat,bone,power=.80):
        return m.loft(name,a,b,rings,p[mat],bone,sides=18,power=power,wobble=.036)
    shell("Tapered narrow leather vest",(0,.020,1.001),(0,.015,1.442),
          [(0,.135,.088),(.20,.151,.093),(.47,.164,.106),(.76,.196,.111),
           (.88,.184,.108),(.985,.136,.079),(1,.104,.067)],"vest","chest")
    shell("Trousers and hem beneath waist",(0,.025,.854),(0,.027,1.078),
          [(0,.133,.088),(.29,.183,.107),(.57,.181,.109),(.8,.161,.105),
           (1,.136,.091)],"trouser","hips")
    shell("Waist sash base",(0,.027,1.000),(0,.025,1.087),
          [(0,.162,.116),(.18,.169,.123),(.81,.167,.116),(1,.158,.106)],"hem","hips")
    shell("Wide waist belt",(0,.024,1.014),(0,.023,1.077),
          [(0,.169,.126),(.1,.175,.129),(.92,.17,.128),(1,.163,.120)],"glove","hips")
    buckle(m,"Central square belt buckle",(.008,-.115,1.044),.079,.060,p["brass"],"hips")
    for x in (-.144,-.104,-.074,.075,.111,.151):
        m.spheroid("Old belt nails",(x,-.105+abs(x)**2*1.4,1.047),
                   (.009,.008,.01),p["brass"],"hips",sides=8)
    # Contrasting inset chest skin with raised edges on the two leather lapels.
    m.spheroid("Exposed throat and chest",(.007,-.084,1.376),(.089,.048,.109),
               p["skin"],"chest",sides=18,wobble=.017)
    for s in (-1,1):
        a = .014 if s<0 else 0
        wrist = [(s*(.034+a),-.090,1.241),(s*.055,-.127,1.328),
                 (s*.102,-.108,1.402),(s*.114,-.079,1.444)]
        m.line("Turned vest lapel",wrist,.018,p["hem"],"chest",spline="BEZIER")
        m.line("Lapels' stitch line",[(x+s*.011,y-.014,z) for x,y,z in wrist],
               .0035,p["thread"],"chest",spline="BEZIER")
        line = [(s*.184,.025,1.369),(s*.169,-.072,1.385),(s*.157,-.085,1.310),
                (s*.155,-.064,1.223)]
        m.line("Leather sleevehole piping",line,.012,p["hem"],"chest",spline="BEZIER")
    m.loft("Narrow throat",(0,.006,1.405),(.005,-.004,1.555),
           [(0,.074,.069),(.31,.069,.063),(.88,.061,.053),(1,.059,.052)],
           p["skin_dark"],"neck",wobble=.042)
    ribbon(m,"Work strap across vest",
           [[(x+dx,y+.004*(abs(dx)/.025),z-dx*.54) for dx in (-.025,0,.025)]
            for x,y,z in [(-.15,-.086,1.149),(-.09,-.120,1.192),(-.034,-.127,1.221),
                          (.036,-.129,1.265),(.104,-.109,1.301),(.164,-.081,1.335)]],
           p["hem"],"chest",.013)
    buckle(m,"Off-centre work strap buckle",(.039,-.142,1.264),.056,.049,p["brass"],"chest")
    for at in [(-.127,-.112,1.167),(-.098,-.129,1.182),(.092,-.122,1.298),(.134,-.108,1.322)]:
        m.spheroid("Cross strap eyelet",at,(.008,.006,.008),p["brass"],"chest",sides=8)
    for name, bone, peg, size in [("Rivet pouch","hips",(-.186,-.042,.946),(.086,.068,.097)),
                                  ("Tool roll","hips",(.166,.069,.956),(.060,.056,.082))]:
        x,y,z = peg
        m.spheroid(name,peg,size,p["hem"],bone,power=.76)
        m.spheroid(name+" heavy flap",(x,y-size[1]*.65,z+.043),
                   (size[0]*.85,.033,.052),p["patch"],bone,power=.70)
        m.spheroid(name+" stud",(x,y-size[1]*1.09,z+.036),(.012,.008,.011),p["brass"],bone)
    tails = [
        ("sash", [[(.023,-.113,1.04),(.078,-.120,1.047),(.124,-.11,1.04)],
                  [(.027,-.155,.948),(.079,-.167,.946),(.137,-.143,.937)],
                  [(.037,-.182,.828),(.090,-.198,.807),(.131,-.160,.842)],
                  [(.048,-.196,.745),(.100,-.204,.714),(.141,-.170,.802)],
                  [(.070,-.212,.683),(.096,-.221,.675),(.125,-.180,.769)]]),
        ("sash.short", [[(-.146,-.099,1.033),(-.076,-.117,1.044),(-.017,-.120,1.033)],
                        [(-.152,-.135,.952),(-.078,-.169,.942),(-.011,-.158,.962)],
                        [(-.179,-.162,.866),(-.104,-.207,.850),(-.035,-.179,.906)],
                        [(-.166,-.176,.810),(-.137,-.192,.799),(-.067,-.201,.869)]])
    ]
    for b, rows in tails:
        ribbon(m,"Uneven brick-red waist tail",rows,p["sash"],b)
        m.line("Cloth ridge",[r[1] for r in rows],.005,p["hem"],b,spline="BEZIER")


def build_head(m,p):
    m.category = "02 | Slant face and tied bandana"
    b = "head"
    m.loft("Angular jaw and long temples",(.0,-.039,1.525),(.004,.008,1.832),
           [(0,.039,.045),(.085,.078,.070,0,.007),(.22,.083,.084,0,.014),
            (.45,.084,.102,-.007,.008),(.59,.098,.102,0,.000),
            (.80,.099,.089,0,-.013),(.95,.072,.067,0,-.009),(1,.030,.044)],
           p["skin"],b,sides=18,power=.78,wobble=.024)
    m.spheroid("Thrust-out chin",(.006,-.111,1.562),(.065,.044,.038),
               p["skin"],b,power=.72)
    m.spheroid("Lower lip",(.004,-.131,1.590),(.046,.019,.012),p["skin_dark"],b)
    m.line("Downturned mouth", [(-.049,-.130,1.604),(-.025,-.150,1.610),
                               (.006,-.155,1.608),(.038,-.146,1.604),(.059,-.126,1.598)],
           .006,p["dark"],b,spline="BEZIER")
    m.loft("Hooked nose",(.012,-.105,1.714),(.012,-.157,1.624),
           [(0,.018,.017),(.25,.019,.025),(.68,.036,.042),(.85,.028,.033),(1,.018,.021)],
           p["skin_light"],b,sides=12,power=.73)
    for s in (-1,1):
        m.spheroid("Nostril",(s*.027+.009,-.168,1.632),(.013,.013,.009),p["skin_dark"],b)
        m.spheroid("High angular cheek",(s*.060,-.081,1.653),(.039,.043,.033),
                   p["skin"],b,power=.74)
        m.spheroid("Socket shadow",(s*.047,-.102,1.689),(.045,.027,.027),
                   p["skin_dark"],b,power=.82)
        m.spheroid("Visible eye",(s*.049,-.120,1.687),(.029,.013,.014),p["tooth"],b,sides=14)
        m.spheroid("Dark iris",(s*.049+.008,-.132,1.685),(.010,.006,.012),p["dark"],b,sides=12)
        m.line("Raider's angled brow",
               [(s*.023,-.131,1.703),(s*.047,-.131,1.716),(s*.072,-.113,1.719),
                (s*.084,-.091,1.715)],.011,p["hair"],b,spline="BEZIER")
        m.spheroid("Ear",(s*.096,.004,1.664),(.024,.037,.043),p["skin"],b,power=.87)
        m.spheroid("Ear fold",(s*.114,-.001,1.668),(.008,.021,.026),p["skin_dark"],b)
        m.line("Cheek nick" if s==-1 else "Squint line",
               [(s*.082,-.101,1.665),(s*.070,-.116,1.646),(s*.071,-.114,1.638)],
               .0038,p["skin_dark"],b)
        m.loft("Tapered swept sideburn",(s*.086,-.020,1.753),(s*.087,-.027,1.588),
               [(0,.025,.050),(.31,.024,.052),(.63,.017,.030),(.88,.011,.021),(1,.005,.011)],
               p["hair"],b,sides=10,wobble=.14)
        m.line("Jaw stubble edge",[(s*.085,-.043,1.608),(s*.066,-.069,1.567),(s*.038,-.094,1.553)],
               .006,p["skin_dark"],b,spline="BEZIER")
        for i in range(7):
            x = s*(.041+i*.006)
            y = -.105 + (.007*i)
            z = 1.560 + .008*sin(i*.75)+i*.004
            m.line("Notched stubble",[(x,y,z),(x+s*.004,y+.001,z+.008)],.0022,p["dark"],b)
    m.spheroid("Matted back hair",(0,.057,1.698),(.101,.073,.105),p["hair"],b,wobble=.065)
    for s in (-1,1):
        for i in range(3):
            m.loft("Loose lock at nape",(s*(.041+i*.019),.080,1.696),
                   (s*(.058+i*.022),.099+i*.013,1.592+i*.022),
                   [(0,.03,.021),(.36,.030,.021),(.81,.013,.011),(1,.004,.004)],
                   p["hair"],b,sides=9,wobble=.12)
    m.loft("Slouch bandana skull cap",(0,.009,1.742),(-.020,.044,1.854),
           [(0,.105,.107),(.16,.116,.111),(.40,.112,.100),(.66,.096,.084),
            (.84,.068,.060,.006,.009),(1,.027,.030,.015,-.007)],
           p["bandana"],b,sides=22,power=.88,wobble=.060)
    for j in range(3):
        m.line("Diagonal wrap ridge",
               [(.111*cos(i*pi/12),.010+.107*sin(i*pi/12),
                 1.746+j*.015+.019*cos(i*pi/12+j*.35)) for i in range(24)],
               .006 if j else .010,p["bandana_light"] if j==0 else p["bandana"],b,
               spline="BEZIER",closed=True)
    for i in range(3):
        m.line("Straying widow's lock",[(-.034+i*.029,-.093,1.757),
               (-.021+i*.034,-.118,1.734),(-.013+i*.035,-.119,1.712-i*.006)],
               .010-i*.001,p["hair"],b,spline="BEZIER")
    m.spheroid("Bunched back knot",(-.017,.112,1.750),(.060,.040,.035),
               p["bandana_light"],b,power=.72)
    for i, (x,end,z) in enumerate(((-.067,.351,1.761),(.005,.290,1.692))):
        ribbon(m,"Directional bandana tail",
               [[(x-.024,.136,1.751-i*.012),(x+.002,.147,1.756-i*.014),
                 (x+.023,.138,1.750-i*.011)],
                [(x-.031,.219,1.804-i*.032),(x-.006,.225,1.809-i*.034),
                 (x+.023,.218,1.792-i*.037)],
                [(x-.043,end-.051,z+.023),(x-.016,end-.039,z+.037),
                 (x+.01,end-.066,z+.020)],
                [(x-.033,end-.013,z+.010),(x-.020,end,z),(x-.011,end-.033,z+.016)]],
               p["bandana"],"tie",.008)


def build_arms(m,p):
    m.category = "03 | Bare arms and oversized breaker gauntlets"
    for side,s in (("L",-1),("R",1)):
        a,b,h = "upper_arm."+side,"forearm."+side,"hand."+side
        def arm(name,x0,x1,rings,mat,bone,power=1):
            return m.loft(name,(s*x0,.015,1.392),(s*x1,.015,1.392),
                          rings,p[mat],bone,sides=16,power=power,wobble=.034,right=(0,-1,0))
        arm("Bare deltoid and bicep",.175,.536,[(0,.048,.058),(.15,.096,.091),
             (.31,.091,.085),(.53,.082,.083),(.72,.071,.076),(.94,.059,.066),(1,.052,.054)],
            "skin",a)
        arm("Exposed elbow",.473,.674,[(0,.052,.055),(.15,.064,.067),(.39,.069,.071),
             (.60,.074,.077),(.9,.050,.062),(1,.045,.045)],"skin",b)
        arm("Layered gauntlet main shell",.519,.737,[(0,.088,.097),(.1,.112,.119),
             (.37,.106,.104),(.62,.098,.102),(.92,.069,.077),(1,.066,.071)],"glove",b,.77)
        for i in range(3):
            start = .523 + i*.061
            r = .109-i*.013
            arm("Raised gauntlet binding",start,start+.031,[(0,r-.007,r-.004),
                 (.17,r+.004,r+.008),(.84,r+.003,r+.007),(1,r-.006,r-.005)],"knuckle",b,.78)
            for y,z in [(-.079,1.405),(-.063,1.459),(-.033,1.485),(.019,1.497)]:
                m.spheroid("Binding copper rivet",(s*(start+.016),y+(i*.009 if y<0 else 0),
                                                      z-i*.009),(.011,.009,.009),p["brass"],b,sides=8)
        arm("Folded glove palm",.715,.844,[(0,.059,.064),(.21,.075,.070),(.68,.077,.074),
              (.93,.062,.057),(1,.048,.045)],"knuckle",h,.68)
        mx=m.rig.data.bones[h].matrix_local
        for i in range(4):
            q = lambda x,y,z: mx @ xyz(x,y,z)
            x = (i-1.5)*.030
            m.loft("Individual curled finger",
                   q(x,.057,.046),q(x,.108,-.017),
                   [(0,.014,.018),(.28,.017,.019),(.66,.018,.017),(1,.012,.013)],
                   p["glove"],h,sides=10,right=mx.to_3x3().col[0])
            m.spheroid("Knuckle cap",q(x,.085,.026),(.016,.017,.014),p["knuckle"],h,sides=9)
        m.loft("Crossed thumb",mx @ xyz(-.053,.022,-.024),mx @ xyz(-.018,.099,-.056),
               [(0,.027,.025),(.43,.031,.025),(.86,.022,.019),(1,.015,.015)],
               p["knuckle"],h,sides=11)


def build_legs(m,p):
    m.category = "04 | Torn knees and long reaching boots"
    for side,s in (("L",-1),("R",1)):
        t,b,f = "thigh."+side,"shin."+side,"boot."+side
        m.loft("Narrow tapered trouser thigh",(s*.115,.022,.986),(s*.141,.004,.498),
               [(0,.099,.086),(.13,.122,.110),(.29,.125,.113),(.67,.105,.094),
                (.87,.092,.085),(.955,.078,.066),(1,.060,.050)],
               p["trouser"],t,sides=18,power=.84,wobble=.07)
        m.loft("Rumpled trouser calf",(s*.145,.012,.598),(s*.16,.021,.276),
               [(0,.072,.070),(.22,.089,.084),(.40,.100,.094),(.75,.087,.078),(1,.073,.056)],
               p["trouser"],b,sides=16,power=.88,wobble=.08)
        if side=="L":
            for i in range(5):
                z = .604+i*.031
                x = s*(.14-(z-.54)*.09)
                m.loft("Offset bandage lap",(x,.005,z-.019),(x+.007,-.004,z+.018),
                       [(0,.099+i*.002,.086+i*.002),(.18,.106+i*.002,.091+i*.002),
                        (.82,.109+i*.002,.092+i*.002),(1,.098+i*.002,.087+i*.002)],
                       p["wrap"],t,sides=18,wobble=.045,power=.86)
            ribbon(m,"Short pulled linen tail",
                   [[(-.219,-.044,.727),(-.230,-.056,.711),(-.222,-.079,.702)],
                    [(-.235,-.092,.668),(-.243,-.100,.651),(-.235,-.111,.659)],
                    [(-.248,-.128,.621),(-.243,-.126,.600),(-.232,-.115,.621)]],
                   p["wrap"],t,.007)
        else:
            ribbon(m,"Raw-edged old trouser mend",
                   [[(.081,-.074,.691),(.129,-.095,.701),(.181,-.083,.681)],
                    [(.07,-.078,.646),(.131,-.089,.652),(.216,-.072,.649)],
                    [(.086,-.070,.592),(.146,-.088,.587),(.197,-.073,.612)],
                    [(.108,-.061,.578),(.149,-.077,.553),(.176,-.068,.589)]],
                   p["patch"],t,.011)
        m.loft("Slanted folded boot shaft",(s*.156,.025,.084),(s*.158,.023,.376),
               [(0,.065,.068),(.23,.075,.074),(.49,.066,.069),(.68,.079,.078),
                (.91,.083,.078),(1,.072,.076)],p["boot"],b,sides=16,power=.80,wobble=.065)
        for i in range(3):
            z=.142+i*.060
            m.loft("Wrapping boot straps",(s*.157,.026,z-.010),(s*.157,.026,z+.011),
                   [(0,.074+i*.004,.073+i*.002),(.31,.080+i*.004,.079+i*.002),
                    (.88,.079+i*.004,.077+i*.002),(1,.074+i*.004,.071+i*.002)],
                   p["hem"],b,sides=13,power=.76,wobble=.07)
            buckle(m,"Small boot pin buckle",(s*.165,-.059-i*.003,z),.044,.027,p["brass"],b)
        m.loft("Long pointed toe and heel",(s*.161,.098,.064),(s*.183,-.229,.081),
               [(0,.048,.044),(.10,.065,.055),(.29,.073,.072),(.50,.079,.062),
                (.71,.074,.042),(.85,.059,.038),(.96,.039,.025),(1,.017,.017)],
               p["boot"],f,sides=16,power=.62,wobble=.02)
        m.loft("Flat rawhide outsole",(s*.161,.099,.024),(s*.183,-.224,.034),
               [(0,.050,.018),(.13,.069,.020),(.35,.076,.019),(.62,.080,.020),
                (.80,.068,.019),(.96,.040,.016),(1,.019,.008)],
               p["sole"],f,sides=14,power=.64)
        m.line("Stitch at toe",[(s*.225,-.145,.059),(s*.209,-.164,.081),
              (s*.179,-.179,.101),(s*.142,-.165,.087),(s*.123,-.137,.061)],
               .0045,p["thread"],f,spline="BEZIER")


def build_prop(m,p):
    m.category = "05 | Detachable short stave and scorched iron wedge"
    b = "wedge_socket"
    bone = m.rig.data.bones[b].matrix_local
    def pt(x,y,z):
        return bone @ xyz(x,y,z)
    before = set(m.scene.objects)
    m.loft("Adze-shaped hickory stave",pt(0,-.38,0),pt(0,.38,0),
           [(0,.034,.027),(.11,.034,.027),(.27,.028,.024),(.64,.022,.021),(.9,.027,.027),(1,.032,.034)],
           p["ash"],b,sides=11,power=.73,right=bone.to_3x3().col[0])
    for i in range(11):
        y = -.292+i*.042
        m.loft("Low leather handle lashing",pt(0,y-.015,0),pt(.001,y+.013,0),
               [(0,.028,.026),(.25,.031,.029),(.85,.030,.029),(1,.026,.026)],
               p["hem"] if i%4 else p["thread"],b,sides=10,power=.76,
               right=bone.to_3x3().col[0])
    # It is a battered wedge-spalled sledge, not the Bruiser's square block.
    sections = [(.239,.048,.070,.012),(.271,.068,.087,.007),
                (.341,.077,.109,-.013),(.406,.077,.144,-.033),
                (.448,.065,.128,-.032)]
    rows = []
    for y,w,h,z in sections:
        corners = [(.70,.88),(.99,.54),(1,-.70),(.76,-1),
                   (-.66,-.97),(-.97,-.63),(-1,.28),(-.86,.66)]
        rows.append([pt(x*w,y,z+v*h) for x,v in corners])
    m.profile("Wedge head • offset peen and wide wheel face",rows,
              [p["steel"],p["edge"]],b,bevel=.008,
              indices=[0]+[1 if ((i in (1,2,5) and k==3) or (i==2 and k==2)) else 0
                           for k in range(4) for i in range(8)]+[1])
    for j,(y,z,r) in enumerate([(.277,-.027,.013),(.323,.017,.012),(.368,-.047,.010),
                                (.390,-.106,.016),(.416,-.03,.009),(.357,.048,.011)]):
        m.spheroid("Scorched radial pit",pt(-.063-(.011 if j>1 else 0),y,z),
                   (.004,r,r*.6),p["rust"],b,sides=9)
    for i in range(3):
        m.line("Edge wear notch",[pt(-.069,.409,-.11+i*.063),pt(-.067,.429,-.099+i*.061)],
               .0035,p["edge"],b)
    # Hierarchy gives the detachable prop one coherent root with no double transforms.
    root = m.mount(bpy.data.objects.new("Wedge_Stave_Detachable",None),b)
    root.empty_display_size = .07
    for obj in set(m.scene.objects)-before-{root}:
        obj.parent = root
        obj.parent_type = "OBJECT"
        obj.matrix_parent_inverse = Matrix.Identity(4)


def rotate(d, axis):
    return Matrix.Rotation(radians(d), 3, axis)


def align(base, natural, direction, preferred):
    return axes(direction, preferred) @ axes(natural, preferred).transposed() @ base


def elbow_for(a,b,l1,l2,pole):
    run = b-a
    length = run.length
    if not abs(l1-l2)+.001 < length < l1+l2-.001:
        raise ValueError(f"Unreachable two-bone target: dist {length:.3f} on {l1:.3f}+{l2:.3f}")
    u = run.normalized()
    v = (pole-u*pole.dot(u)).normalized()
    projection = (l1*l1-l2*l2+length*length)/(2*length)
    return a+u*projection+v*sqrt(l1*l1-projection*projection)


NEUTRAL_GUARD = dict(
    hip=(-.017,.056,.809), body=(13,-5,-15), head=(-7,5,15),
    foot_l=(-.384,-.141,.131,-27,0), foot_r=(.394,.171,.131,31,0),
    tool=(.017,-.336,1.015, .94,-.35,.14), cloth=(0,0,0), shoulder=(0,0),
    knee=(-.24,-1,.08,.24,-1,.08))


def beat(**kwargs):
    return {**NEUTRAL_GUARD, **kwargs}


def blend(a,b,t):
    return {k:tuple(x+(y-x)*t for x,y in zip(a[k],b[k])) for k in a}


class Performance:
    """Solve deliberate hand and boot targets, then save editable FK keys."""

    def __init__(self,m):
        self.m = m
        self.bones = m.rig.data.bones

    def matrix(self,k):
        return self.bones[k].matrix_local.to_3x3()

    def head(self,k):
        return self.bones[k].head_local

    def aim(self,k,d,right):
        b=self.bones[k]
        return align(self.matrix(k),b.tail_local-b.head_local,d,right)

    def frame(self,f,a):
        targets={}
        m=self.m

        def set_bone(k,p,mat):
            targets[k]=Vector(p),mat

        def carry(child,parent):
            point, orient=targets[parent]
            old=self.matrix(parent)
            k=orient @ old.transposed()
            return point+k @ (self.head(child)-self.head(parent)),k @ self.matrix(child)

        lean,bank,yaw=a["body"]
        # Minus X rotation pitches the torso toward the marked target (-Y).
        trunk=rotate(lean,"X") @ rotate(bank,"Y") @ rotate(yaw,"Z")
        set_bone("hips",a["hip"],rotate(bank*.42,"Y") @ rotate(yaw*.56,"Z") @ self.matrix("hips"))
        chest,_=carry("chest","hips")
        set_bone("chest",chest,trunk @ self.matrix("chest"))
        p,r=carry("neck","chest")
        set_bone("neck",p,r)
        p,r=carry("head","neck")
        hx,hy,hz=a["head"]
        set_bone("head",p,trunk @ rotate(hx,"X") @ rotate(hy,"Y") @ rotate(hz,"Z") @ self.matrix("head"))
        for k,s in zip(("tie","sash","sash.short"),a["cloth"]):
            p,r=carry(k,self.bones[k].parent.name)
            set_bone(k,p,rotate(s,"X") @ r)

        center = xyz(*a["tool"][:3])
        rod = xyz(*a["tool"][3:]).normalized()
        tool_basis = axes(rod,(0,-1,0))
        set_bone("wedge_socket",center,tool_basis)
        for side,s,shift in zip(("L","R"),(-1,1),a["shoulder"]):
            clav,upper,fore,hand=[f"{b}.{side}" for b in ("clavicle","upper_arm","forearm","hand")]
            anchor,_=carry(clav,"chest")
            shoulder,_=carry(upper,"chest")
            shoulder+=xyz(0,-.028*shift,-.025*shift)
            set_bone(clav,anchor,self.aim(clav,shoulder-anchor,(0,-1,0)))
            grip=center+rod*(s*.134)
            face=xyz(s*-.16,-.55,-.26)
            palm=axes(face,rod if s>0 else -rod)
            wrist=grip-palm @ xyz(0,.065,0)
            elbow=elbow_for(shoulder,wrist,self.bones[upper].length,
                            self.bones[fore].length,xyz(s*.91,.32,-.66))
            set_bone(upper,shoulder,self.aim(upper,elbow-shoulder,(0,-1,0)))
            set_bone(fore,elbow,self.aim(fore,wrist-elbow,(0,-1,0)))
            set_bone(hand,wrist,palm)
            thigh,shin,boot=[f"{b}.{side}" for b in ("thigh","shin","boot")]
            hip,_=carry(thigh,"hips")
            d=a["foot_"+side.lower()]
            foot=xyz(*d[:3])
            pole=a["knee"][:3] if s<0 else a["knee"][3:]
            knee=elbow_for(hip,foot,self.bones[thigh].length,
                           self.bones[shin].length,xyz(*pole))
            set_bone(thigh,hip,self.aim(thigh,knee-hip,(1,0,0)))
            set_bone(shin,knee,self.aim(shin,foot-knee,(1,0,0)))
            set_bone(boot,foot,rotate(d[3],"Z") @ rotate(d[4],"X") @ self.matrix(boot))
        m.absolute_keys(f,targets)

    def take(self,name,stop,beats,markers=()):
        self.m.action(name,stop,markers)
        for (start,a),(end,b) in zip(beats,beats[1:]):
            for f in range(start,end):
                t=(f-start)/(end-start)
                try:
                    self.frame(f,blend(a,b,t*t*(3-2*t)))
                except ValueError as exc:
                    raise ValueError(f"{name}, frame {f}: {exc}") from exc
        self.frame(*beats[-1])


def animate(m):
    m.action("Neutral T",1)
    for bone in m.rig.data.bones:
        m.local_key(bone.name,1)
    p=Performance(m)
    g=NEUTRAL_GUARD
    p.take("Ready",33,[(1,g),(9,beat(hip=(-.013,.058,.824),head=(-8,4,11),
                                  tool=(.012,-.329,1.031,.94,-.35,.18),cloth=(-3,5,3))),
                       (18,beat(hip=(-.015,.058,.814),head=(-8,7,-4),
                                  tool=(.015,-.330,1.024,.94,-.35,.15),cloth=(3,-4,-3))),
                       (26,beat(head=(-7,3,9),cloth=(2,-2,3))),
                       (33,g)])
    intercept=beat(hip=(-.093,-.042,.722),body=(29,-11,-7),head=(-16,6,13),
                   foot_l=(-.491,-.330,.131,-24,0),foot_r=(.398,.184,.131,30,0),
                   tool=(-.027,-.438,.990,.95,-.30,.15),cloth=(-15,24,16),shoulder=(.4,.4))
    p.take("Intercept",29,[
        (1,g),
        (5,beat(hip=(.034,.050,.77),body=(15,-1,-17),head=(-6,4,18),
                foot_l=(-.346,-.153,.146,-27,-7),tool=(.026,-.37,.991,.96,-.15,.21),
                cloth=(4,9,5))),
        (10,beat(hip=(-.054,.016,.79),body=(18,-5,-10),head=(-10,3,18),
                 foot_l=(-.447,-.270,.257,-24,4),tool=(.016,-.393,1.032,.91,-.29,.29),
                 cloth=(-22,19,13))),
        (14,intercept),(18,beat(**{**intercept,"hip":(-.089,-.041,.733),
                                 "tool":(-.037,-.438,.979,.95,-.30,.15)})),
        (23,beat(hip=(-.033,.018,.782),body=(18,-4,-9),head=(-9,4,17),
                 foot_l=(-.435,-.258,.203,-25,7),tool=(.016,-.377,1.017,.94,-.35,.17),
                 cloth=(8,-15,-13))),
        (29,g)], [("Step lifts",10),("Cut off the wheel line",14),("Return to guard",29)])
    load=beat(hip=(.052,.008,.752),body=(14,4,-28),head=(-8,3,31),
              foot_l=(-.427,-.271,.131,-24,0),foot_r=(.399,.236,.131,36,0),
              tool=(.056,-.323,1.070,.81,.54,.23),cloth=(13,-16,-8),shoulder=(.17,-.08))
    hit=beat(hip=(-.101,-.151,.629),body=(57,-9,23),head=(-35,4,-5),
             foot_l=(-.452,-.317,.131,-21,0),foot_r=(.431,.206,.177,34,17),
             tool=(.075,-.648,.626,.51,-.81,-.34),cloth=(30,-28,-24),shoulder=(.50,.70))
    follow=beat(**{**hit,"hip":(-.104,-.167,.625),"body":(61,-7,23),
                   "tool":(.064,-.642,.610,.52,-.80,-.30),"cloth":(23,-15,-15)})
    p.take("Wagon Strike",32,[
        (1,g),(6,beat(hip=(.018,.031,.778),foot_l=(-.419,-.265,.139,-25,-3),
                     tool=(.044,-.323,1.052,.89,.22,.26))),
        (10,load),
        (13,beat(hip=(.029,-.048,.738),body=(34,-5,8),head=(-20,4,12),
                 foot_l=(-.428,-.271,.131,-24,0),foot_r=(.408,.223,.154,34,9),
                 tool=(.039,-.493,.909,.82,-.56,-.20),cloth=(23,-22,-13))),
        (16,hit),(20,follow),
        (25,beat(hip=(-.046,-.036,.758),body=(27,-5,7),head=(-15,2,10),
                 foot_l=(-.409,-.261,.216,-26,7),foot_r=(.399,.183,.137,31,2),
                 tool=(.055,-.444,.872,.66,-.69,-.14),cloth=(-14,10,11))),
        (32,g)], [("Coil low",10),("Wheel-height impact",16),("Follow through",20)])
    p.take("Hit",21,[(1,g),(4,beat(hip=(.008,.116,.811),body=(-2,10,3),head=(-4,-13,13),
                                   tool=(.008,-.265,1.066,.89,-.31,.37),cloth=(28,-21,-15))),
                     (8,beat(hip=(.030,.113,.771),body=(11,11,-3),head=(8,-5,0),
                             tool=(.017,-.283,1.001,.92,-.17,.25),cloth=(-15,13,8))),
                     (14,beat(hip=(-.020,.079,.800),head=(-2,3,13),
                              tool=(.014,-.320,1.012,.94,-.35,.17))),
                     (21,g)], [("Recoil",4)])
    down=beat(hip=(.102,.122,.346),body=(66,18,-20),head=(16,-10,4),
              foot_l=(-.359,-.215,.135,-29,4),foot_r=(.527,.402,.131,63,0),
              tool=(.016,-.410,.282,.90,-.30,-.23),cloth=(24,13,-11),shoulder=(.4,.23),
              knee=(-.24,-1,.08,.38,.07,-1))
    p.take("Defeat",37,[(1,g),(5,beat(hip=(.029,.132,.79),body=(0,12,-9),head=(-1,-11,22),
                                   tool=(.061,-.263,1.069,.86,-.31,.36),cloth=(18,-20,-12))),
                        (12,beat(hip=(.084,.155,.655),body=(24,19,-23),head=(3,-8,20),
                                 foot_r=(.455,.279,.144,42,6),
                                 tool=(.082,-.253,.778,.91,-.31,.15),cloth=(-9,15,-2))),
                        (23,down),(29,beat(**{**down,"hip":(.102,.121,.337),
                                              "tool":(.016,-.414,.270,.90,-.30,-.23)})),
                        (37,down)], [("Give ground",12),("Knee down",23)])


if __name__ == "__main__":
    path=Path(sys.argv[sys.argv.index("--")+1]).resolve()
    if path.exists():
        raise FileExistsError(path)
    raider=Model("WagonRaider",skeleton(),radians(11))
    mats=materials()
    build_body(raider,mats)
    build_head(raider,mats)
    build_arms(raider,mats)
    build_legs(raider,mats)
    build_prop(raider,mats)
    animate(raider)
    raider.save(path,"Ready",33,"Neutral T bind; forward reach and two fixed handle grips solved to editable FK keys.")
