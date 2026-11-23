"""Create the editable Supply Wagon candidate in Blender 5.2.2."""

from math import cos, pi, radians, sin
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "model-tools" / "wagon"))
from model_tools import Model, Vector, Quaternion, Matrix, pigment


def spec(tag, p, parent, family, direction=(0, 0, 1)):
    return (tag, p, Vector(p) + Vector(direction)*.18, parent, family, (1, 0, 0))


WHEELS = {
    f"{end}.{side}": (x, y, .325)
    for end, y in (("fore", -.56), ("aft", .51))
    for side, x in (("L", -.55), ("R", .55))
}
BODY = (0, .20, .64)
STAVES = 9


def make_rig():
    bones = [spec("origin", (0, 0, 0), None, "Anchor"),
             spec("body", BODY, "origin", "Chassis"),
             spec("tongue", (0, -.78, .32), "body", "Chassis"),
             spec("tow_ring", (.012, -1.28, .28), "tongue", "Chassis"),
             spec("fore_axle", (0, -.56, .325), "origin", "Chassis"),
             spec("broken_stub", (-.35, -.56, .325), "fore_axle", "Breakaway"),
             spec("aft_axle", (0, .51, .325), "origin", "Chassis"),
             spec("side_break", (-.46, -.23, .64), "body", "Breakaway"),
             spec("chest", (.05, .51, .75), "body", "Cargo"),
             spec("barrel", (-.08, .02, .73), "body", "Cargo"),
             spec("webbing", (-.08, .02, .73), "body", "Cargo"),
             spec("sack.full", (-.17, -.43, .78), "body", "Cargo"),
             spec("sack.small", (.23, -.51, .75), "body", "Cargo"),
             spec("rag", (-.455, .40, .825), "body", "Cargo")]
    for tag, p in WHEELS.items():
        at = "broken_stub" if tag == "fore.L" else ("fore_axle" if tag.startswith("fore") else "aft_axle")
        bones.extend((spec("carrier." + tag, p, at, "Breakaway" if tag == "fore.L" else "Chassis"),
                      spec("wheel." + tag, p, "carrier." + tag, "Wheel spin", (1, 0, 0))))
    return Model("Wagon", bones, radians(36))


def materials():
    def wood(name, a, b, dimension):
        return pigment(name, a, b, 5, axis=dimension)
    return {
        "boards": [
            wood("Sawn oak • oat", (.13, .068, .036), (.46, .283, .139), (3.5, .65, 6)),
            wood("Sawn oak • honey", (.165, .086, .038), (.52, .317, .154), (3, .60, 7.1)),
            wood("Sawn oak • smoke", (.105, .054, .036), (.37, .218, .119), (3, .68, 7)),
        ],
        "cap": wood("Cross-grain end boards", (.15, .069, .035), (.44, .253, .127), (.48, 3.3, 6)),
        "post": wood("End grain and rail faces", (.099, .043, .022), (.39, .217, .106), (4, 4, .55)),
        "chassis": wood("Axles • hardwood core", (.048, .026, .014), (.23, .119, .057), (4, .7, 4)),
        "split": wood("Freshly torn oak", (.32, .16, .065), (.74, .477, .228), (3.3, .7, 7)),
        "spoke": wood("Wheel stock", (.135, .055, .019), (.54, .275, .083), (2.7, 3, 3)),
        "rim": wood("Bent wheel ash", (.23, .112, .047), (.65, .398, .175), (1.2, 2, 2)),
        "tire": pigment("Battered iron tire", (.048, .035, .024), (.222, .161, .109), 7, .69),
        "iron": pigment("Hand-wrought iron", (.041, .032, .028), (.190, .165, .145), 9, .62),
        "riv": pigment("Hammered pin heads", (.15, .098, .051), (.49, .359, .195), 7, .64),
        "strap": pigment("Oiled hide webs", (.116, .041, .021), (.38, .158, .066), 10),
        "buckle": pigment("Square old brass", (.31, .161, .059), (.74, .480, .204), 7, .56),
        "barrel": [wood(f"Cask stave • course {i+1}", (.15 + i*.026, .070, .038),
                        (.38+i*.051, .235+i*.020, .121+i*.013), (4, 4, .52)) for i in range(3)],
        "sack": pigment("Grain sack • flax", (.42, .29, .157), (.79, .644, .408), 9),
        "sack2": pigment("Grain sack • sand", (.33, .20, .10), (.67, .504, .286), 10),
        "rag": pigment("Old cream marker", (.39, .245, .125), (.81, .697, .466), 12),
        "hemp": pigment("Knot hemp", (.25, .142, .068), (.54, .389, .207), 12),
        "grain": pigment("Sawn fissures", (.055, .026, .011), (.121, .064, .029)),
    }


def plank(m, mat, name, x, y, z, split, bone):
    """Face profile split along one irregular seam on the near forward quarter."""
    start, stop = y
    base = [(-.071, start), (.065, start+.015), (.073, stop), (-.066, stop-.011)]
    if split == "base":
        base = [(-.070, -.79), (.066, -.786), (.074, -.29),
                (.031, -.307), (.016, -.202), (-.008, -.307),
                (-.038, -.258), (-.069, -.321)]
    elif split == "shard":
        base = [(-.069, -.315), (-.038, -.252), (-.008, -.301),
                (.016, -.196), (.031, -.301), (.074, -.284),
                (.067, .79), (-.067, .786)]
    rows = [[(x + depth + (height+.08)*.14*(1 if x > 0 else -1), j, z+height)
             for height, j in reversed(base)] for depth in (-.023, .022)]
    return m.profile(name, rows, mat, bone, bevel=.006)


def build_chassis(m, p):
    m.category = "01 | Oak bed, draw gear and running frame"
    for x, k in ((-.30, "L"), (.30, "R")):
        m.beam(f"Underframe runner {k}", (x, -.87, .447), (x*.97, .81, .469), (.059, .056),
               (.055, .053), p["chassis"], "body", .014)
    for y in (-.60, .02, .61):
        m.box("Through cross member", (0, y, .490), (1, .096, .10), p["post"], "body", .01)
    for i in range(6):
        m.box(f"Floorboard {i+1}", ((i-2.5)*.145, 0, .573), (.141, 1.63, .076),
              p["boards"][i % 3], "body", .008)
    for side, x in (("L", -.45), ("R", .45)):
        for tier in range(3):
            z = .627 + tier*.146 + (.008 if side == "R" else 0)
            if side == "L" and tier <= 1:
                plank(m, p["boards"][tier], f"Port strake {tier+1} • breaking nose", x,
                      (-.79, -.28), z, "base", "side_break")
                plank(m, p["boards"][tier], f"Port strake {tier+1} • long", x,
                      (-.28, .79), z, "shard", "body")
                # Actual split edge, tucked between the two oak halves until opened.
                m.line("Splinter fibres", [(x-.022, -.295, z+.068), (x-.023, -.302, z+.033),
                                          (x-.024, -.202, z+.016), (x-.025, -.307, z-.009),
                                          (x-.026, -.257, z-.039), (x-.03, -.316, z-.063)],
                       .007, p["split"], "side_break")
            else:
                plank(m, p["boards"][(tier+(side=="R")) % 3], f"{side} strake {tier+1}", x,
                      (-.79, .793), z, "", "body")
            sign = 1 if x > 0 else -1
            for y0, y1, h in ((-.68, -.38, -.027), (.07, .54, .031), (.43, .70, -.019)):
                face = x + sign*(.023+(h+.08)*.14)
                m.line("Long sawn grain checks",
                       [(face, y0, z+h), (face, y0*.58+y1*.42, z+h+.007),
                        (face, y1, z+h+.005)], .0028, p["grain"],
                       "side_break" if side=="L" and tier<=1 and y1<-.29 else "body")
    for end, y in (("Tail", .81), ("Head", -.81)):
        for tier in range(3):
            m.box(f"{end} board {tier+1}", (0, y+(.01 if y>0 else -.01)*tier, .629+tier*.145),
                  (.912+tier*.026, .051, .138), p["cap"], "body", .007)
        for x in (-.36, .36):
            m.box(f"{end} cleat", (x, y + (.038 if y>0 else -.038), .752),
                  (.084, .050, .434), p["post"], "body", .010)
    for x in (-.489, .489):
        for y in (-.727, .706):
            b = "side_break" if x < 0 and y < 0 else "body"
            sign = 1 if x>0 else -1
            m.beam("External angle stake", (x-sign*.024, y, .545), (x+sign*.045, y, .980),
                   (.044, .045), (.036, .043), p["post"], b)
            for z in (.623, .738, .852, .937):
                m.spheroid("Stake rosehead", (x+sign*(.041+(z-.63)*.15), y, z),
                           (.010, .019, .019), p["riv"], b, sides=9)
    for axle, y in (("fore_axle", -.56), ("aft_axle", .51)):
        m.box("Ash axle beam", (.094 if axle=="fore_axle" else 0, y, .325),
              (.967 if axle=="fore_axle" else 1.153, .104, .103), p["chassis"], axle, .012)
        for x in (-.31, .31):
            m.box("Greased axle mount", (x, y, .379), (.14, .16, .12), p["iron"], axle, .007)
    m.beam("Brittle end of fore axle", (-.536,-.56,.325), (-.368,-.559,.325),
           (.043,.044), (.05,.045), p["chassis"], "broken_stub", .006)
    for i in range(3):
        m.beam("Fresh tenon splinter", (-.369, -.59+i*.025, .340-i*.011),
               (-.326+i*.008, -.593+i*.026, .350-i*.014), (.013,.011),
               (.002,.002), p["split"], "broken_stub", .001)
    m.beam("Hitch draw pole", (0,-.619,.415), (.012,-1.288,.294),
           (.082,.052), (.048,.037), p["post"], "tongue", .012)
    m.box("Pole end iron shoe", (.012, -1.269, .301), (.124,.073,.096),
          p["iron"], "tongue", .009)
    m.line("Hitch tow eye", [(.012 + .047*cos(2*pi*i/20), -1.297-.009*sin(2*pi*i/20),
                            .243 + .073*sin(2*pi*i/20)) for i in range(20)],
           .013, p["iron"], "tow_ring", closed=True)


def wheel_ring(m, name, center, width, outer, inner, mat, b, n=36):
    x, y, z = center
    vs = [(x + a*width/2, y + rad*cos(2*pi*i/n), z + rad*sin(2*pi*i/n))
          for a, rad in ((-1, outer), (1, outer), (1, inner), (-1, inner))
          for i in range(n)]
    faces = [(a*n+i, a*n+(i+1)%n, ((a+1)%4)*n+(i+1)%n, ((a+1)%4)*n+i)
             for a in range(4) for i in range(n)]
    m.mesh(name, vs, faces, mat, b, bevel=.003, smooth=True)


def build_wheels(m, p):
    for key, (x,y,z) in WHEELS.items():
        m.category = f"02 | Wheel • {key}"
        b = f"wheel.{key}"
        sign = 1 if x > 0 else -1
        wheel_ring(m, "Oak felloe", (x,y,z), .078, .316, .257, p["rim"], b)
        wheel_ring(m, "Shrunk iron tire", (x,y,z), .089, .325, .307, p["tire"], b)
        wheel_ring(m, "Iron tire flange", (x+sign*.043,y,z), .009, .318, .301, p["iron"], b)
        for i in range(8):
            a = (i+.22)*pi/4 + (.12 if key.startswith("aft") else 0)
            dy, dz = cos(a), sin(a)
            m.beam(f"Staggered spoke {i+1}", (x, y+.068*dy, z+.068*dz),
                   (x-sign*.006, y+.284*dy, z+.284*dz), (.021,.028),
                   (.019,.018), p["spoke"], b, .006)
            m.spheroid("Felloe nail", (x+sign*.051, y+.303*dy, z+.303*dz),
                       (.008,.012,.012), p["riv"], b, sides=9)
        m.loft("Wheel hub", (x-sign*.061,y,z), (x+sign*.114,y,z),
               [(0,.080,.080),(.18,.091,.091),(.65,.095,.095),(.92,.074,.074),(1,.068,.068)],
               p["spoke"], b, sides=14)
        m.loft("Round axle band", (x+sign*.075,y,z), (x+sign*.114,y,z),
               [(0,.064,.064),(.10,.070,.070),(.88,.070,.070),(1,.063,.063)],
               p["iron"], b, sides=14)
        m.spheroid("Square linch cap", (x+sign*.120,y,z), (.024,.036,.038), p["riv"], b,
                   power=.56, sides=10)


def web(m, name, xy, width, mat, bone):
    """A closed rectangular-section ribbon laid over the curve of the load."""
    rows = []
    for i, (x, y, z) in enumerate(xy):
        a = pi*i/(len(xy)-1)
        rows.append([(x+.009*r*cos(a), y+t*width/2, z+.009*r*sin(a))
                     for t,r in [(-1,1),(1,1),(1,-1),(-1,-1)]])
    m.profile(name, rows, mat, bone, bevel=.003)


def build_cargo(m, p):
    m.category = "03 | Latched field stores"
    # Chest is slightly crooked; the lid and ironwork each remain editable.
    b = "chest"
    m.box("Recessed field chest shell", (.035,.501,.883), (.693,.483,.335), p["post"], b, .02)
    for i in range(4):
        x = -.230 + i*.177
        m.box("Separate chest lid stave", (x,.501,1.063+(.005 if i==1 else 0)),
              (.168,.522,.055), p["boards"][i%3], b, .011)
        for y in (.250,.751):
            m.box("End panel stave", (x,y,.892), (.168,.037,.275),
                  p["boards"][(i+1)%3], b, .007)
    for x in (-.235,.283):
        m.box("Chest strap on lid", (x,.50,1.095), (.072,.550,.018), p["strap"], b, .005)
        for y in (.232,.77):
            m.box("Bent chest lock rail", (x,y,.932), (.069,.026,.309),
                  p["strap"], b, .006)
            for z in (.842,.961,1.035):
                m.spheroid("Lock rail rivet", (x, y+(-.019 if y<.5 else .019), z),
                           (.018,.012,.019), p["riv"], b, sides=9)
    m.box("Latch plate", (.02,.219,.982), (.111,.017,.088), p["iron"], b, .010)
    m.box("Latch clasp", (.018,.202,.964), (.043,.019,.056), p["buckle"], b, .006)

    m.category = "04 | Banded water cask"
    b, cx, cy = "barrel", -.079, .02
    profile = [(0.66,.224),(.72,.248),(.91,.272),(1.09,.27),(1.222,.227),(1.24,.221)]
    for i in range(STAVES+2):
        n = STAVES+2
        a = i*2*pi/n
        outlines = []
        for k,(z,r) in enumerate(profile):
            angles = [a+.012+j*(2*pi/n-.024)/3 for j in range(4)]
            outlines.append([(cx+r*cos(v),cy+r*sin(v),z+(.006*sin(i*2.1) if k==5 else 0))
                             for v in angles] +
                            [(cx+(r-.033)*cos(v),cy+(r-.033)*sin(v),z) for v in reversed(angles)])
        m.profile(f"Cask stave {i+1:02}", outlines, p["barrel"][i%3], b, bevel=.002)
    for z, r in ((.758,.260),(.975,.280),(1.171,.246)):
        m.loft("Riveted cask hoop", (cx,cy,z-.026),(cx,cy,z+.026),
               [(0,r-.008,r-.008),(.17,r,r),(.85,r,r),(1,r-.006,r-.006)],
               p["iron"], b, sides=30)
        for i in range(12):
            a = (i+.35)*pi/6
            m.spheroid("Cask hoop pin", (cx+(r+.002)*cos(a),cy+(r+.002)*sin(a),z),
                       (.012,.012,.013), p["riv"], b, sides=8)
    m.loft("Cask recessed oak lid", (cx,cy,1.206),(cx,cy,1.228),
           [(0,.209,.209),(1,.209,.209)], p["cap"], b, sides=26)
    for x in (-.128,-.042,.051):
        span = (.198**2 - x*x)**.5
        m.line("Cask top board seam", [(cx+x,cy-span,1.23),(cx+x,cy+span,1.23)],
               .004, p["grain"], b)
    m.spheroid("Cask bung", (cx+.088,cy-.047,1.232), (.036,.034,.017), p["post"], b)

    m.category = "05 | Sacks, rolled strap and marker"
    for b, c, d, mat in (
        ("sack.full", (-.227,-.435,.86), (.228,.216,.29), p["sack"]),
        ("sack.small", (.222,-.475,.853), (.185,.201,.231), p["sack2"]),
        ("sack.small", (.21,-.24,.769), (.164,.171,.18), p["sack2"]),
    ):
        m.spheroid("Packed field sack", c, d, mat, b, wobble=.046, power=.89, sides=18)
        x,y,z = c
        if y > -.30:
            continue
        a, tip = (x-.038,y+.026,z+d[2]-.042), (x-.050,y+.026,z+d[2]+.065)
        m.loft("Gathered sack neck", a, tip, [(0,.087,.077),(.52,.036,.041),
                (.69,.041,.043),(1,.064,.039)], mat, b, wobble=.11)
        for phase in (0, pi/2, pi, 3*pi/2):
            m.line("Gathered cloth fold",
                   [(x+.103*cos(phase),y+.104*sin(phase),z+d[2]-.039),
                    (x-.038+.044*cos(phase),y+.026+.041*sin(phase),z+d[2]+.010),
                    (x-.051+.036*cos(phase),y+.026+.039*sin(phase),z+d[2]+.037)],
                   .007, p["sack2"], b, spline="BEZIER")
        m.line("Sack hitch knot", [(-.05+x+.045*cos(i*pi/10), y+.026+.045*sin(i*pi/10),
                                  z+d[2]+.023+sin(i*pi/10)*.007) for i in range(20)],
               .011, p["hemp"], b, closed=True)
        m.line("Knot cord tails", [(x-.010,y,z+d[2]+.025),(x+.048,y-.038,z+d[2]-.009),
                                  (x+.112,y-.085,z+d[2]-.078)], .009, p["hemp"], b, spline="BEZIER")
    # Cargo web crosses over the barrel from each side of the bed.
    web(m, "Over-cask load strap", [(0.07 + .59*cos(i*pi/14), .045+.052*cos(i*pi/14),
                                     .80+.468*sin(i*pi/14)) for i in range(15)],
        .087, p["strap"], "webbing")
    for x in (-.519,.518):
        m.box("Hanging cargo web", (x,-.002,.72), (.027,.082,.36), p["strap"], "webbing", .007)
        k = -.539 if x<0 else .535
        m.line("Squared load buckle",
               [(k,y,z) for y,z in ((-.056,.795),(.051,.795),(.053,.673),(-.051,.676))],
               .013, p["buckle"], "webbing", closed=True)
        m.line("Load buckle tongue", [(k,-.043,.743),(k,.032,.749)], .008, p["buckle"], "webbing")
    for i in range(6):
        m.spheroid("Load web pin", (-.536,-.007,.552+i*.044), (.006,.012,.012),
                   p["riv"], "webbing", sides=8)
    rag = [(-.482,.51,.858),(-.477,.275,.85),(-.509,.282,.80),(-.535,.305,.747),
           (-.56,.319,.707),(-.554,.345,.714),(-.564,.356,.691),(-.552,.393,.727),
           (-.54,.425,.762),(-.504,.461,.792)]
    m.mesh("Torn quarter marker", rag, [tuple(range(len(rag)))], p["rag"], "rag").modifiers.new(
        "Folded linen thickness", "SOLIDIFY").thickness = .008
    m.line("Marker thread", [(-.491,.52,.856),(-.489,.40,.853),(-.488,.277,.85)],
           .008, p["hemp"], "rag")


def q(axis, degrees):
    return Quaternion(axis, radians(degrees))


def animate(m):
    def key(f, *, roll=0, z=0, lean=0, pitch=0, jog=0, cargo=0,
            ring=0, broken=0, scud=0):
        # Vertical bones have local X aligned to world X; local Z faces -Y.
        m.local_key("origin", f)
        m.local_key("body", f, (jog*.16, z, jog),
                    q((1,0,0), pitch) @ q((0,0,1), lean))
        m.local_key("fore_axle", f, (0, -broken*.035, 0), q((0,0,1), 5*broken))
        m.local_key("aft_axle", f)
        m.local_key("broken_stub", f, (-.022*broken, -.055*broken, 0),
                    q((0,0,1), -24*broken))
        m.local_key("tongue", f, (0,0,0), q((1,0,0), 1.4*cargo+13*broken))
        m.local_key("tow_ring", f, (0,0,0), q((1,0,0), ring) @ q((0,1,0), -19*broken))
        m.local_key("side_break", f, (-.094*broken,-.117*broken,.019*broken),
                    q((0,1,0), -12*broken) @ q((1,0,0), -16*broken))
        for name, w, d in (("barrel",1,.075),("chest",.34,-.038),
                           ("sack.full",1.65,.14),("sack.small",-.93,.048),
                           ("webbing",1,.061),("rag",-1.5,.029)):
            m.local_key(name, f, (-.027*broken*w,.013*cargo*w,d*broken),
                        q((1,0,0), 3.8*cargo*w+17*broken*w) @ q((0,0,1), 5*broken*w))
        for wheel in WHEELS:
            if wheel == "fore.L":
                m.local_key("carrier."+wheel, f, (-.228*broken, -.197*broken+scud, .192*broken),
                            q((0,0,1), -53*broken) @ q((0,1,0), -13*broken))
                m.local_key("wheel."+wheel, f, (0,0,0), q((0,1,0), roll-66*broken))
            else:
                m.local_key("carrier."+wheel, f)
                m.local_key("wheel."+wheel, f, (0,0,0), q((0,1,0), roll))

    for name, stop in (("Neutral",1),("Ready",25)):
        m.action(name, stop)
        key(1)
        if stop > 1:
            key(stop)
    m.action("Advance", 33, [("Take the load",6),("Axle bump",18),("Settle",29)])
    for frame, roll, z, lean, pitch, cargo, ring, jog in [
        (1,0,0,0,0,0,0,0),(5,9,-.018,1.7,2,-.54,-13,-.025),
        (9,33,.024,-2.9,-2.3,-.84,19,.015),(13,62,-.011,2.2,2.1,.69,33,.021),
        (18,95,.039,-3,-4,1.44,-7,-.015),(22,127,-.018,2.1,2.8,-.80,-26,.005),
        (26,151,.015,-1.75,-2,.55,12,.004),(30,167,-.006,.48,.5,-.32,5,0),
        (33,173,0,0,0,0,0,0),
    ]:
        key(frame, roll=roll,z=z,lean=lean,pitch=pitch,cargo=cargo,ring=ring,jog=jog)
    m.action("Stall", 27, [("Wheel locked",1),("Arrested load",5),("Stopped",23)])
    for frame, z, lean, pitch, jog, cargo, ring in [
        (1,0,0,0,0,0,0),(4,-.023,1.8,4.8,.023,-.62,-17),
        (7,-.034,2.2,7.3,.048,1.48,34),(11,.012,-2,-2,-.010,-.84,-25),
        (16,-.009,.62,1.1,.013,.35,15),(22,0,0,0,0,-.1,-5),(27,0,0,0,0,0,0),
    ]:
        key(frame,z=z,lean=lean,pitch=pitch,jog=jog,cargo=cargo,ring=ring)
    m.action("Destroyed", 42, [("Impact",5),("Axle parts",11),("Wheel down",29)])
    for frame, roll,z,lean,pitch,jog,cargo,ring,broken,scud in [
        (1,0,0,0,0,0,0,0,0,0),(5,0,-.033,3.2,3,.031,.85,26,0,0),
        (9,0,.014,-3.8,-2,-.016,-.94,-21,.18,-.02),
        (13,0,-.056,6.5,5.1,.028,.75,33,.57,.09),
        (19,0,-.111,14.8,9.2,.035,1.24,36,1,.11),
        (24,0,-.090,12.0,7.3,.028,-.46,-12,.90,.034),
        (29,0,-.125,15.2,9.2,.033,.48,16,1.13,0),
        (35,0,-.107,14.0,8.1,.031,-.14,-5,1.05,0),
        (42,0,-.113,14.4,8.7,.030,0,0,1.08,0),
    ]:
        key(frame,roll=roll,z=z,lean=lean,pitch=pitch,jog=jog,cargo=cargo,ring=ring,
            broken=broken,scud=scud)


if __name__ == "__main__":
    path = Path(sys.argv[sys.argv.index("--")+1]).resolve()
    if path.exists():
        raise FileExistsError(path)
    wagon = make_rig()
    mats = materials()
    build_chassis(wagon, mats)
    build_wheels(wagon, mats)
    build_cargo(wagon, mats)
    animate(wagon)
    wagon.save(path, "Ready", 25, "Driverless load, rigid parts on 22 named controls; independent wheel spin and near fore breakaway.")
