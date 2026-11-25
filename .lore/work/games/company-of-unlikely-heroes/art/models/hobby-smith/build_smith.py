"""Build the self-contained Hobby Smith source with Blender 5.2.2 LTS."""

import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector


V = Vector
TAU = math.tau
FPS = 24
CAMERA = (1.150829196, 0.0, -0.435386419)
PALETTE = {
    # sRGB paint swatches; the shader converts them before mixing.
    "shirt": ("893f31", .29, 0),
    "shirt_light": ("975142", .24, 0),
    "shirt_dark": ("63322b", .25, 0),
    "apron": ("49443c", .45, 0),
    "scorch": ("292927", .26, 0),
    "edge": ("675648", .23, 0),
    "stitch": ("bc966b", .17, 0),
    "breeches": ("5d5147", .27, 0),
    "boot": ("533a2a", .24, 0),
    "sole": ("362c27", .19, 0),
    "wood": ("9f7249", .35, 0),
    "iron": ("676860", .28, .28),
    "steel": ("aaa89b", .21, .32),
    "brass": ("ba8b51", .26, .26),
    "skin": ("b8835f", .18, 0),
    "rouge": ("b47259", .17, 0),
    "lip": ("965f4d", .15, 0),
    "crease": ("865e4b", .16, 0),
    "coal": ("3b2f2a", .23, 0),
    "umber": ("635047", .24, 0),
    "grey": ("aa9a87", .19, 0),
    "silver": ("c9bba4", .20, 0),
    "eye": ("cfb797", .10, 0),
    "iris": ("59716d", .13, 0),
}


def collection(name):
    result = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(result)
    return result


def rgb(hex_color):
    srgb = [int(hex_color[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [((x + .055) / 1.055) ** 2.4 if x > .04045 else x / 12.92 for x in srgb]


def material(name, hex_color, variation, metallic):
    col = rgb(hex_color)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*col, 1)
    mat.use_nodes = True
    tree = mat.node_tree
    shader = tree.nodes.get("Principled BSDF")
    shader.inputs["Roughness"].default_value = .83 if not metallic else .56
    shader.inputs["Metallic"].default_value = metallic
    coords = tree.nodes.new("ShaderNodeTexCoord")
    wash = tree.nodes.new("ShaderNodeTexNoise")
    wash.label = "Pigment patches in the surface"
    wash.inputs["Scale"].default_value = 13
    wash.inputs["Detail"].default_value = 3
    tree.links.new(coords.outputs["Generated"], wash.inputs["Vector"])
    ramp = tree.nodes.new("ShaderNodeValToRGB")
    for stop, pos, gain in zip(ramp.color_ramp.elements, (.20, .79), (1 - variation, 1 + variation)):
        stop.position = pos
        stop.color = (*[min(1., c * gain) for c in col], 1)
    tree.links.new(wash.outputs["Fac"], ramp.inputs[0])
    pigment = ramp.outputs[0]
    if name in {"apron", "skin", "shirt", "wood"}:
        wear = tree.nodes.new("ShaderNodeTexNoise")
        wear.label = "Broad, irregular wear"
        wear.inputs["Scale"].default_value = 4.3
        wear.inputs["Detail"].default_value = 4
        tree.links.new(coords.outputs["Generated"], wear.inputs["Vector"])
        glaze = tree.nodes.new("ShaderNodeValToRGB")
        glaze.color_ramp.elements[0].position = .26
        glaze.color_ramp.elements[0].color = (.35,.28,.21,1) if name == "apron" else (.62,.49,.42,1)
        glaze.color_ramp.elements[1].position = .67
        glaze.color_ramp.elements[1].color = (1.,.91,.79,1) if name == "apron" else (1.,.96,.9,1)
        tree.links.new(wear.outputs["Fac"], glaze.inputs[0])
        blend = tree.nodes.new("ShaderNodeMixRGB")
        blend.blend_type = "MULTIPLY"
        blend.inputs[0].default_value = .87 if name == "apron" else .56
        tree.links.new(pigment, blend.inputs[1])
        tree.links.new(glaze.outputs[0], blend.inputs[2])
        pigment = blend.outputs[0]
    tree.links.new(pigment, shader.inputs["Base Color"])
    if name in {"shirt", "apron", "wood", "breeches", "iron", "boot", "skin"}:
        tooth = tree.nodes.new("ShaderNodeTexNoise")
        tooth.label = "Subtle material tooth"
        tooth.inputs["Scale"].default_value = 115
        tooth.inputs["Detail"].default_value = 2.2
        tree.links.new(coords.outputs["Generated"], tooth.inputs["Vector"])
        bump = tree.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = .20 if name != "skin" else .12
        bump.inputs["Distance"].default_value = .008
        tree.links.new(tooth.outputs["Fac"], bump.inputs["Height"])
        tree.links.new(bump.outputs[0], shader.inputs["Normal"])
    return mat


def make_rig(bucket):
    arm = bpy.data.armatures.new("Hobby Smith neutral bind")
    rig = bpy.data.objects.new("HobbySmith_Rig", arm)
    bucket.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    groups = {name: arm.collections.new(name) for name in ("Body", "Arms", "Legs")}

    def bone(name, start, end, parent=None, group="Body"):
        b = arm.edit_bones.new(name)
        b.head, b.tail = start, end
        if parent:
            b.parent = arm.edit_bones[parent]
            b.use_connect = (b.parent.tail - b.head).length < 1e-6
        groups[group].assign(b)

    bone("root", (0, 0, 0), (0, 0, .20))
    bone("pelvis", (0, 0, .89), (0, 0, 1.10), "root")
    bone("chest", (0, 0, 1.10), (0, 0, 1.59), "pelvis")
    bone("head", (0, -.026, 1.59), (0, -.026, 2.0), "chest")
    bone("apron", (0, -.228, .98), (.0, -.290, .66), "pelvis")
    for side, sign in (("R", -1), ("L", 1)):
        shoulder = (sign * .272, 0, 1.50)
        elbow = (sign * .565, 0, 1.50)
        wrist = (sign * .837, 0, 1.50)
        hip = (sign * .133, .025, .91)
        knee = (sign * .153, -.036, .52)
        ankle = (sign * .165, .008, .149)
        bone(f"upper_arm.{side}", shoulder, elbow, "chest", "Arms")
        bone(f"forearm.{side}", elbow, wrist, f"upper_arm.{side}", "Arms")
        bone(f"hand.{side}", wrist, (sign * .957, 0, 1.50), f"forearm.{side}", "Arms")
        bone(f"thigh.{side}", hip, knee, "pelvis", "Legs")
        bone(f"shin.{side}", knee, ankle, f"thigh.{side}", "Legs")
        bone(f"foot.{side}", ankle, (sign * .165, -.195, .067), f"shin.{side}", "Legs")
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.show_in_front = True
    arm.display_type = "STICK"
    return rig


class Geometry:
    def __init__(self, rig, materials):
        self.rig = rig
        self.materials = materials
        self.bucket = None

    def mesh(self, name, vertices, faces, paint, bind, *, smooth=True, closed=True):
        data = bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        if closed:
            bm = bmesh.new()
            bm.from_mesh(data)
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            bm.to_mesh(data)
            bm.free()
        model = bpy.data.objects.new(name, data)
        self.bucket.objects.link(model)
        data.materials.append(self.materials[paint])
        for face in data.polygons:
            face.use_smooth = smooth
        if isinstance(bind, bpy.types.Object):
            model.parent = bind
        else:
            groups = {}
            for i, pt in enumerate(vertices):
                weights = {bind: 1.0} if isinstance(bind, str) else bind(pt)
                for bone, weight in weights.items():
                    if weight <= 0:
                        continue
                    if bone not in groups:
                        groups[bone] = model.vertex_groups.new(name=bone)
                    groups[bone].add([i], weight, "REPLACE")
            model.parent = self.rig
            deform = model.modifiers.new("Smith • bind", "ARMATURE")
            deform.object = self.rig
            deform.use_deform_preserve_volume = True
        return model

    def rings(self, name, rows, paint, bind, *, smooth=True):
        width = len(rows[0])
        last = (len(rows) - 1) * width
        faces = [tuple(reversed(range(width)))]
        faces.extend(
            (i + j, i + (j + 1) % width, i + width + (j + 1) % width, i + width + j)
            for i in range(0, last, width) for j in range(width)
        )
        faces.append(tuple(range(last, last + width)))
        return self.mesh(name, sum(rows, []), faces, paint, bind, smooth=smooth)

    def loft(self, name, levels, paint, bind, *, steps=32, fold=0., profile=1.):
        rows = []
        for z, x, y, rx, ry in levels:
            row = []
            for j in range(steps):
                a = TAU * j / steps
                sx, cy = math.sin(a), math.cos(a)
                k = 1 + fold * (.65 * math.sin(6 * a + 2 * z) + .35 * math.sin(11 * a - z))
                row.append((x + rx * k * math.copysign(abs(sx) ** profile, sx),
                            y - ry * k * math.copysign(abs(cy) ** profile, cy), z))
            rows.append(row)
        return self.rings(name, rows, paint, bind)

    def orb(self, name, center, radii, paint, bind, *, tilt=0., steps=24):
        center = V(center)
        rotation = Matrix.Rotation(tilt, 3, "Y")
        rows = []
        for i in range(15):
            p = -.5 * math.pi + .01 + (math.pi - .02) * i / 14
            row = []
            for j in range(steps):
                a = TAU * j / steps
                q = V((radii[0] * math.cos(p) * math.sin(a),
                       -radii[1] * math.cos(p) * math.cos(a), radii[2] * math.sin(p)))
                row.append(tuple(center + rotation @ q))
            rows.append(row)
        return self.rings(name, rows, paint, bind)

    def tube(self, name, pts, sizes, paint, bind, *, steps=12, flat=1., rounds=1):
        path = [V(p) for p in pts]
        radii = [sizes] * len(pts) if isinstance(sizes, (int, float)) else list(sizes)
        # Round hand-drawn paths by cutting the corners while keeping their ends.
        for _ in range(rounds):
            path = [path[0]] + [a.lerp(b, t) for a, b in zip(path, path[1:]) for t in (.25, .75)] + [path[-1]]
            radii = [radii[0]] + [
                a + (b - a) * t for a, b in zip(radii, radii[1:]) for t in (.25, .75)
            ] + [radii[-1]]
        rows, guide = [], None
        for i, (point, radius) in enumerate(zip(path, radii)):
            tangent = (path[min(i + 1, len(path) - 1)] - path[max(0, i - 1)]).normalized()
            if guide is None or abs(guide.dot(tangent)) > .97:
                guide = V((0, 1, 0)) if abs(tangent.y) < .85 else V((0, 0, 1))
            u = (guide - tangent * guide.dot(tangent)).normalized()
            v = tangent.cross(u)
            guide = u
            rows.append([
                tuple(point + radius * (u * math.cos(a) * flat + v * math.sin(a)))
                for a in (TAU * j / steps for j in range(steps))
            ])
        return self.rings(name, rows, paint, bind)

    def slab(self, name, face, offset, paint, bind, bevel=.005):
        count = len(face)
        vertices = list(face) + [tuple(V(p) + V(offset)) for p in face]
        faces = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
        faces += [(i, (i + 1) % count, (i + 1) % count + count, i + count) for i in range(count)]
        model = self.mesh(name, vertices, faces, paint, bind, smooth=False)
        edge = model.modifiers.new("Soft forged edges", "BEVEL")
        edge.width = bevel
        edge.segments = 2
        return model

    def panel(self, name, rows, paint, bind, thickness=.018):
        width = len(rows[0])
        faces = [
            (i * width + j, i * width + j + 1, (i + 1) * width + j + 1, (i + 1) * width + j)
            for i in range(len(rows) - 1) for j in range(width - 1)
        ]
        model = self.mesh(name, sum(rows, []), faces, paint, bind, closed=False)
        shell = model.modifiers.new("Supple leather thickness", "SOLIDIFY")
        shell.thickness = thickness
        return model


def mix(a, b, amount):
    t = max(0., min(1., amount))
    return {a: 1 - t, b: t}


def box(g, name, center, size, paint, bind, bevel=.007):
    x, y, z = center
    a, b, c = (n * .5 for n in size)
    return g.slab(name, [(x-a, y-b, z-c), (x+a, y-b, z-c), (x+a, y-b, z+c), (x-a, y-b, z+c)],
                  (0, 2*b, 0), paint, bind, bevel)


def make_costume(g):
    hip, chest = "pelvis", "chest"
    torso = lambda p: mix(hip, chest, (p[2] - .94) / .31)
    leather = lambda p: mix("apron", hip, (p[2] - .70) / .28) if p[2] < .98 else torso(p)
    g.loft("Joined seat under the waist tie", [
        (.812,0,.021,.222,.147),(.855,0,.023,.272,.160),(.91,0,.025,.279,.174),
        (.969,-.002,.03,.257,.159),(.984,-.002,.034,.236,.142),
    ], "breeches", hip, fold=.038, profile=.82)
    g.loft("Soot-red shirt • shaped body", [
        (.93, 0, .029, .255, .16), (.975, -.007, .012, .282, .185),
        (1.09, 0, .008, .287, .204), (1.27, -.008, -.013, .315, .221),
        (1.39, -.006, .003, .327, .208), (1.50, 0, .022, .321, .166),
        (1.567, -.005, .021, .239, .111), (1.602, -.013, .002, .112, .095),
    ], "shirt", torso, fold=.055, profile=.85)
    g.loft("Open shirt neck", [
        (1.452, -.01, -.052, .078, .065), (1.509, -.009, -.061, .116, .101),
        (1.61, -.01, -.052, .108, .098), (1.71, -.008, -.039, .09, .09),
    ], "skin", chest)
    for sign in (-1, 1):
        g.slab("Lopsided open collar", [
            (sign*.032, -.165, 1.61), (sign*.133, -.111, 1.595),
            (sign*.194, -.158, 1.53), (sign*.132, -.208, 1.453 + .025*sign),
            (sign*.046, -.193, 1.52),
        ], (0, .025, 0), "shirt_light", chest)
    g.tube("Button placket", [(0, -.181, 1.56), (.013, -.215, 1.47), (.019, -.235, 1.31)],
           [.010, .014, .011], "shirt_dark", chest, flat=.48)
    for z in (1.44, 1.38):
        g.orb("Horn shirt button", (.028, -.218 - .014*(1.44-z)/.06, z),
              (.015, .008, .016), "wood", chest)

    # Width, center and depth vary so the apron stays a shape at sprite scale.
    apron = [
        (1.355, -.021, .223, -.217), (1.30, -.018, .238, -.249),
        (1.21, -.006, .257, -.258), (1.105, -.014, .266, -.248),
        (.98, -.007, .303, -.246), (.86, -.002, .306, -.302),
        (.755, .002, .274, -.338), (.685, .021, .258, -.335),
    ]
    rows = [
        [(cx + w*u, y + (.081 if k < 4 else .026)*u*u + .015*math.sin(5*u+k*.7),
          z + (.047*u + .012*math.sin(8*u) if k == len(apron)-1 else -.021*u)) for u in
         (-1., -.77, -.54, -.31, -.07, .17, .41, .68, .86, 1.)]
        for k, (z, cx, w, y) in enumerate(apron)
    ]
    g.panel("Charcoal apron • warped hide", rows, "apron", leather)
    for name, seam in (
        ("Grease-polished apron edge R", [r[0] for r in rows]),
        ("Grease-polished apron edge L", [r[-1] for r in rows]),
        ("Battered bottom hem", rows[-1]),
        ("Top apron welt", rows[0]),
    ):
        g.tube(name, seam, .012, "edge", leather, flat=.68)
    for a, b in zip(rows[0], rows[0][1:]):
        points = [tuple(V(a).lerp(V(b), t) + V((0,-.013,-.018))) for t in (.26, .60)]
        g.tube("Uneven linen stitching", points, .005, "stitch", chest, rounds=0)
    g.panel("Offset apron patch", [
        [(-.057, -.319, .865), (.041, -.333, .85), (.153, -.320, .857)],
        [(-.061, -.351, .784), (.049, -.366, .791), (.151, -.344, .787)],
        [(-.055, -.352, .734), (.049, -.359, .723), (.137, -.350, .739)],
    ], "scorch", leather, .011)
    g.tube("Pocket mouth welt", [(-.057, -.324, .865), (.041, -.339, .85), (.153, -.327, .857)],
           [.010, .011, .007], "edge", leather)
    for i in range(6):
        u = i*.125
        g.tube("Patched pocket stitch",
               [(-.047+u*.16,-.361,.736-u*.01),(-.038+u*.16,-.362,.736-u*.01)],
               .0035, "stitch", leather, rounds=0)
    for sign in (-1, 1):
        y = -.202 if sign < 0 else -.193
        strap = [(sign*.168, -.222, 1.325), (sign*.19, y, 1.45),
                 (sign*.20, -.080, 1.557), (sign*.172, .018, 1.594),
                 (sign*.178, .110, 1.559), (sign*.159, .177, 1.492),
                 (sign*.116, .213, 1.374), (sign*.063, .229, 1.253),
                 (sign*.002, .230, 1.16), (sign*-.091, .203, 1.003)]
        g.tube("Apron shoulder strap", strap, .031 if sign < 0 else .024,
               "edge", torso, flat=.45)
        g.orb("Apron strap stud", (sign*.169, -.249, 1.33), (.015,.008,.015), "brass", chest)
    box(g, "Square strap buckle", (-.192, -.228, 1.433), (.094,.032,.092), "brass", chest)
    box(g, "Buckle leather inset", (-.192, -.247, 1.431), (.065,.015,.057), "sole", chest)
    g.tube("Buckle catch", [(-.22,-.258,1.431), (-.183,-.258,1.425),(-.165,-.253,1.435)],
           .005, "steel", chest)
    g.tube("Apron waist ties", [(.28,.01,.996),(.22,.162,1.01),(.02,.209,1.002),(-.19,.178,.982),(-.289,.025,.991)],
           [.023,.025,.030,.025,.022], "boot", hip, flat=.62)
    g.tube("Waist tie tail", [(.019,.208,.998),(.061,.226,.968),(.024,.209,.866),(.032,.177,.834)],
           [.023,.020,.016,.009], "boot", hip, flat=.54)


def make_limbs(g):
    for side, sign in (("R", -1), ("L", 1)):
        upper, fore, hand = (f"{part}.{side}" for part in ("upper_arm", "forearm", "hand"))
        thigh, shin, foot = (f"{part}.{side}" for part in ("thigh", "shin", "foot"))
        arms = lambda p: mix(upper, fore, (abs(p[0]) - .516) / .103)
        legs = lambda p: mix(thigh, shin, (.61 - p[2]) / .23)
        # Rings along the T-pose arm, shared weighted elbow under the rolled sleeve.
        def arm(name, levels, paint, bind, fold=.035):
            rows = [
                [(sign*x, y + ry*math.cos(a)*k, 1.50+dz+rz*math.sin(a)*k)
                 for j in range(28) for a in (TAU*j/28,)
                 for k in (1+fold*math.cos(6*a+x*5),)]
                for x, y, dz, ry, rz in levels
            ]
            g.rings(name + " " + side, rows, paint, bind)

        arm("Tapered forearm and elbow", [
            (.39, .011, -.002, .104, .098), (.49, .008, -.002, .100, .102),
            (.543, .004, -.008, .086, .077), (.58, .009, .004, .090, .077),
            (.64, .006, .007, .096, .085), (.705, -.001, .007, .092, .070),
            (.773, -.002, .004, .068, .058), (.846, 0, 0, .050, .047),
        ], "skin", arms)
        cuff = .499 if side == "R" else .474
        arm("Soot-red sleeve", [
            (.242, .01, .02, .124, .127), (.296, .008, .017, .161, .150),
            (.376, .009, .013, .154, .134), (.437, -.007, -.005, .128, .111),
            (cuff-.007, -.006, -.006, .112, .101),
        ], "shirt", upper, .08)
        arm("Two folds in the rolled cuff", [
            (cuff-.06, -.007, -.01, .120, .112), (cuff-.049, -.004, -.004, .134, .123),
            (cuff-.030, -.01, -.002, .132, .117), (cuff-.021, -.01, 0, .121, .109),
            (cuff-.011, -.008, -.003, .128, .116), (cuff+.009, -.004, -.006, .119, .109),
            (cuff+.017, .0, -.005, .102, .090),
        ], "shirt_light", upper, .07)
        g.orb("Callused palm " + side, (sign * .887,.014,1.499), (.072,.050,.056), "skin", hand)
        for j in range(4):
            z = 1.548 - j*.029
            edge_x = sign*(.950 - abs(1-j)*.005)
            g.tube("Curled finger " + side, [
                (sign*.907,.039,z), (edge_x,.025,z+.004), (edge_x,-.028,z),
                (sign*.923,-.053,z-.004), (sign*.900,-.052,z-.010),
            ], [.019,.021,.020,.017,.014], "skin", hand)
            g.orb("Work-worn nail " + side, (sign*.902,-.067,z-.009),
                  (.011,.005,.009), "eye", hand, tilt=.12*sign, steps=12)
        g.tube("Thumb locks the grip " + side, [
            (sign*.850,.004,1.520), (sign*.855,-.035,1.544), (sign*.878,-.059,1.540),
            (sign*.912,-.052,1.531),
        ], [.027,.025,.024,.019], "skin", hand)

        def c(z, x, y, rx, ry):
            return (z, sign*x, y, rx, ry)

        g.loft("Coal-stained trousers " + side, [
            c(.292,.164,.006,.083,.084), c(.352,.159,-.019,.101,.103),
            c(.437,.157,-.020,.114,.114), c(.516,.152,-.031,.121,.123),
            c(.605,.148,-.008,.136,.152), c(.72,.144,.014,.153,.156),
            c(.84,.134,.020,.155,.164), c(.92,.129,.022,.136,.145),
        ], "breeches", legs, fold=.085)
        g.loft("Folded boot shaft " + side, [
            c(.111,.165,.00,.098,.113), c(.165,.166,.013,.094,.103),
            c(.221,.162,.019,.107,.104), c(.279,.166,.008,.101,.103),
            c(.329,.163,.003,.117,.118), c(.354,.162,-.007,.108,.108),
        ], "boot", shin, fold=.053)
        g.loft("Turned rim " + side, [
            c(.299,.163,.004,.111,.114), c(.321,.163,.004,.120,.125),
            c(.352,.162,-.004,.123,.124), c(.361,.161,-.002,.117,.121),
        ], "edge", shin, fold=.04)
        g.loft("Blunt leather toe " + side, [
            c(.034,.165,-.060,.107,.180), c(.066,.165,-.075,.115,.193),
            c(.117,.165,-.073,.106,.179), c(.147,.165,-.039,.098,.144),
            c(.181,.166,-.005,.092,.106),
        ], "boot", foot, fold=.035, profile=.72)
        g.loft("Layered welt " + side, [
            c(.008,.165,-.061,.112,.185), c(.018,.165,-.066,.117,.191),
            c(.042,.165,-.071,.117,.194), c(.050,.165,-.073,.108,.189),
        ], "sole", foot, fold=.025, profile=.72)
        for i in range(3):
            z = .176 + .035*i
            g.tube("Scuffed shaft lace " + side, [
                (sign*.111,-.092,z+.012), (sign*.163,-.113,z-.005), (sign*.213,-.098,z+.014),
            ], .008,"stitch" if i == 1 else "wood", shin)
        for j in range(3):
            x = sign*.165 + (j-1)*.047
            g.orb("Toe welt pin " + side, (x,-.254+.014*abs(j-1),.062),
                  (.009,.009,.010), "iron", foot, steps=12)


def make_face(g):
    h = "head"
    g.loft("Strong cheekbones and square chin", [
        (1.642,-.012,-.061,.072,.080), (1.659,-.012,-.066,.112,.093),
        (1.697,-.013,-.067,.138,.127), (1.75,-.010,-.064,.146,.139),
        (1.81,-.010,-.050,.164,.148), (1.87,-.009,-.041,.162,.145),
        (1.934,-.012,-.034,.156,.143), (1.990,-.014,-.024,.138,.117),
        (2.032,-.012,-.021,.094,.097), (2.056,-.010,-.015,.029,.040),
    ], "skin", h, steps=48, profile=.76, fold=.016)
    for side, sign in (("right", -1), ("left", 1)):
        x = sign * .164
        g.orb("Worn ear " + side, (x,-.025,1.808), (.042,.042,.068), "skin", h, tilt=sign*.20)
        g.orb("Ear concha " + side, (x+sign*.012,-.059,1.811), (.021,.012,.042), "rouge", h, tilt=sign*.23)
        g.tube("Bent ear rim " + side, [
            (x,-.064,1.774), (x+sign*.028,-.056,1.808), (x+sign*.025,-.055,1.853),
            (x,-.056,1.861), (x-sign*.015,-.057,1.84),
        ], [.008,.009,.011,.013,.007], "skin", h)
        eye_z = 1.861 if sign < 0 else 1.847
        eye_x = -.081 if sign < 0 else .069
        g.orb("Visible eye " + side, (eye_x,-.173,eye_z), (.037,.018,.012 if sign < 0 else .0065), "eye", h)
        g.orb("Grey iris " + side, (eye_x+.010,-.189,eye_z), (.012,.004,.011 if sign < 0 else .0055), "iris", h)
        g.orb("Pupil " + side, (eye_x+.012,-.193,eye_z), (.006,.0017,.007 if sign < 0 else .0035), "coal", h)
        g.tube("Upper lid " + side, [
            (eye_x-.041,-.163,eye_z-.002), (eye_x-.026,-.181,eye_z+.009),
            (eye_x+.007,-.190,eye_z+.012 if sign < 0 else eye_z+.005),
            (eye_x+.038,-.186 if sign < 0 else -.169,eye_z+.001),
        ], [.003,.004,.004,.0018], "crease", h, flat=.78)
        g.tube("Lower lid weight " + side, [
            (eye_x-.039,-.160,eye_z-.005), (eye_x-.015,-.184,eye_z-.013),
            (eye_x+.021,-.184,eye_z-.010), (eye_x+.042,-.167,eye_z-.004),
        ], [.002,.005,.004,.0018], "skin", h, flat=.64)
        brow_z = 1.906 if sign < 0 else 1.889
        g.tube("Raised eyebrow " + side, [
            (eye_x-.048,-.158,brow_z-.007*sign), (eye_x-.022,-.171,brow_z+.014),
            (eye_x+.014,-.185,brow_z+.008), (eye_x+.046,-.172,brow_z+.006*sign),
        ], [.003,.009,.011,.004], "umber", h, flat=.46)
        g.tube("Nasolabial fold " + side, [
            (sign*.051,-.197,1.785),(sign*.068,-.190,1.764),
            (sign*.075,-.187,1.736),(sign*.093,-.175,1.719),
        ], [.002,.003,.003,.0015], "crease", h, flat=.49)
        for j in range(2):
            g.tube("Weathered eye crease " + side, [
                (eye_x+sign*.031,-.173,eye_z-.015-j*.010),
                (eye_x+sign*.056,-.157,eye_z-.018-j*.013),
                (eye_x+sign*.067,-.139,eye_z-.012-j*.017),
            ], [.0016,.0026,.0014], "crease", h, flat=.40)
    g.loft("Crooked nose bridge and tip", [
        (1.761,.001,-.18,.024,.030), (1.774,.006,-.195,.040,.044),
        (1.798,.008,-.205,.038,.053), (1.826,.000,-.189,.024,.042),
        (1.859,-.005,-.171,.021,.031), (1.899,-.006,-.16,.012,.010),
    ], "skin", h, steps=28)
    for sign in (-1, 1):
        g.orb("Nostril shadow", (sign*.018+.004,-.225,1.777), (.009,.010,.005), "lip", h)
    g.tube("Upper lip", [(-.061,-.189,1.725),(-.026,-.205,1.734),(.005,-.211,1.735),
                        (.029,-.204,1.734),(.067,-.185,1.720)],
           [.002,.005,.006,.004,.002], "lip", h, flat=.52)
    g.tube("Press of the lower lip", [(-.052,-.191,1.721),(-.020,-.206,1.722),
                                     (.016,-.210,1.721),(.050,-.192,1.716)],
           [.0015,.007,.007,.002], "rouge", h, flat=.52)
    g.tube("Crooked mouth seam", [(-.061,-.191,1.724),(-.026,-.212,1.728),
                                  (.015,-.217,1.727),(.038,-.207,1.723),(.066,-.188,1.719)],
           [.0018,.0025,.0027,.0025,.002], "crease", h, flat=.8)
    for j in range(2):
        z = 1.927 + j*.023
        g.tube("Short forehead fold", [(-.075,-.165,z),(-.043,-.171,z+.006),(-.005,-.177,z+.003),
                                      (.029,-.174,z+.004),(.059,-.167,z-.001)],
               [.0014,.0024,.0025,.0022,.0013], "crease", h, flat=.44)
    g.tube("Old brass sleeper earring", [(.165,-.065,1.761),(.17,-.080,1.742),
                                        (.187,-.068,1.734),(.191,-.053,1.749),(.181,-.053,1.762)],
           .007, "brass", h)

    # Crop one temple and lay ribbons in the direction of the approved silver quiff.
    g.loft("Cropped hair cap", [
        (1.842,-.008,.039,.145,.092), (1.886,-.007,.019,.163,.115),
        (1.929,-.012,.012,.164,.137), (1.981,-.023,-.007,.153,.146),
        (2.025,-.044,-.017,.143,.129), (2.065,-.063,-.024,.122,.101),
        (2.085,-.068,-.031,.077,.075), (2.097,-.061,-.03,.032,.041),
    ], "coal", h, steps=38, fold=.049)
    locks = [
        ([(.116,.052,2.025),(.038,.017,2.091),(-.035,-.011,2.139),(-.113,-.050,2.132),
          (-.176,-.083,2.081),(-.171,-.120,2.019),(-.205,-.118,1.981),(-.209,-.076,1.988)], .051, "umber"),
        ([(.078,.083,2.066),(.031,.043,2.125),(-.043,-.006,2.153),(-.104,-.046,2.127),
          (-.123,-.104,2.081),(-.160,-.125,2.052),(-.190,-.121,2.074)], .038, "coal"),
        ([(.087,-.092,2.023),(.028,-.116,2.103),(-.039,-.131,2.137),(-.10,-.164,2.102),
          (-.108,-.189,2.04),(-.144,-.175,1.981),(-.187,-.140,1.984),(-.198,-.121,2.011)], .039, "silver"),
        ([(.078,-.113,2.018),(.038,-.139,2.067),(-.018,-.153,2.095),(-.062,-.175,2.070),
          (-.079,-.189,2.017),(-.115,-.183,1.966),(-.17,-.151,1.955),(-.176,-.112,1.980)], .038, "grey"),
        ([(.063,-.126,1.998),(.012,-.145,2.043),(-.046,-.169,2.035),(-.069,-.182,1.985),
          (-.122,-.159,1.946),(-.168,-.132,1.941),(-.184,-.096,1.964)], .037, "umber"),
        ([(-.092,-.038,2.06),(-.169,-.060,2.035),(-.207,-.072,1.989),(-.200,-.091,1.944),
          (-.229,-.058,1.926),(-.24,-.032,1.949)], .047, "coal"),
        ([(-.105,.018,2.034),(-.178,.019,2.011),(-.207,.006,1.958),(-.186,-.024,1.910),
          (-.199,-.032,1.872),(-.227,-.017,1.867)], .036, "umber"),
        ([(.105,.011,2.046),(.135,-.032,2.008),(.151,-.025,1.963),(.165,-.005,1.93),
          (.169,.021,1.887)], .032, "grey"),
    ]
    for i, (path, weight, paint) in enumerate(locks):
        n = len(path)
        radii = [max(.004, weight * math.sin(math.pi*(j + .40) / (n-.51))**.55) for j in range(n-1)] + [.005]
        g.tube(f"Swept quiff • lock {i+1}", path, radii, paint, h, flat=.69, rounds=2)
        if i in (2,3,4):
            fleck = "grey" if paint == "silver" else "umber" if paint == "grey" else "coal"
            for strand in (-1,1):
                detail = [tuple(V(p) + V((strand*r*.26,-r*.60,strand*r*.20))) for p, r in zip(path,radii)]
                g.tube(f"Quiff flow • strand {i+1}", detail, [r*.077 for r in radii], fleck,
                       h, steps=8, rounds=2)
    for j in range(5):
        g.tube("Scissor-cut temple", [(.140,.023,1.858+j*.025),(.155,.002,1.881+j*.02),
                                    (.141,-.050,1.925+j*.017),(.116,-.067,1.949+j*.017)],
               [.003,.011,.010,.004], "umber" if j%2 else "grey", h, flat=.53)


def prop_mount(bucket, rig, name, bone, anchor):
    obj = bpy.data.objects.new(name, None)
    bucket.objects.link(obj)
    obj.empty_display_type = "CIRCLE"
    obj.empty_display_size = .048
    obj.parent = rig
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    bpy.context.view_layer.update()
    obj.matrix_world = Matrix.Translation(V(anchor))
    return obj


def make_props(g):
    # Each root origin is inside the actual grip. The editable shape is in its local space.
    hammer = prop_mount(g.bucket, g.rig, "Hammer_Detachable", "hand.R", (-.918,-.028,1.500))
    hammer["Purpose"] = "Short smith's hammer; the head, shaft and grip leave together."
    g.loft("Oval ash handle", [
        (-.186,-.004,.006,.033,.027),(-.173,-.005,.004,.035,.030),
        (-.09,-.002,.003,.029,.024),(.032,0,0,.026,.023),
        (.135,.009,.001,.029,.024),(.238,.018,.0,.034,.026),
        (.308,.021,0,.032,.025),
    ], "wood", hammer, steps=24, fold=.032, profile=.82)
    for i in range(4):
        g.tube("Seam in handle grip", [(-.022,-.020,-.097+i*.032),
                                      (0,-.028,-.104+i*.032),(.018,-.020,-.115+i*.032)],
               .0045, "edge", hammer)
    head = [(-.079,-.159,.232),(.065,-.156,.237),(.078,-.111,.247),(.068,.117,.253),
            (.049,.140,.255),(-.061,.138,.25),(-.077,.106,.247),(-.081,-.112,.243)]
    g.slab("Hand-forged square head", head, (.009,.003,.105), "iron", hammer, .014)
    g.slab("Dressed square striking face", [(-.076,-.168,.231),(.060,-.165,.233),
                                           (.078,-.164,.328),(.064,-.164,.355),
                                           (-.053,-.171,.352),(-.082,-.171,.321)],
           (0,.024,0), "steel", hammer, .008)
    box(g, "Ash-and-iron wedge", (.022,.003,.349), (.071,.056,.018), "wood", hammer)
    g.tube("Hammer nick", [(-.086,-.111,.272),(-.086,-.103,.291),(-.084,-.099,.293)],
           [.002,.004,.002], "steel", hammer, rounds=0)

    fitting = prop_mount(g.bucket, g.rig, "Fitting_Detachable", "hand.L", (.918,-.032,1.509))
    fitting["Purpose"] = "Single forged fitting. Displayed without changing the recipient's gear."
    # Wide irregular crescent with a dark cutout, silver lip and three readable peens.
    face = [
        (-.120,-.033,.010),(-.093,-.033,.091),(-.019,-.033,.142),(.072,-.033,.146),
        (.137,-.033,.105),(.155,-.033,.071),(.115,-.033,.035),(.079,-.033,.078),
        (.013,-.033,.082),(-.038,-.033,.055),(-.060,-.033,.000),
    ]
    g.slab("Crescent fitting • blackened heel", face, (0,.059,.006), "iron", fitting, .008)
    g.tube("Fitting bright hammered edge", [p for p in face[:7]],
           [.009,.010,.013,.014,.012,.009,.006], "steel", fitting, flat=.71)
    for x,z,r in ((-.080,.059,.018),(-.004,.116,.016),(.094,.112,.015)):
        g.orb("Recessed peen seat", (x,-.037,z), (r*1.30,.005,r*1.25),"sole",fitting)
        g.orb("Flattened brass peen", (x,-.043,z), (r,.009,r*.86),"brass",fitting)
    box(g, "Fitting handle tongue", (.000,-.004,-.037), (.045,.044,.146), "iron", fitting)


def aim_bone(rig, name, direction, twist=0.):
    b = rig.pose.bones[name]
    rest = b.bone.matrix_local.to_quaternion()
    axis = V(direction).normalized()
    rot = Quaternion(axis, twist) @ (rest @ V((0, 1, 0))).rotation_difference(axis)
    set_world_rotation(rig, name, rot)


def set_world_rotation(rig, name, relative):
    b = rig.pose.bones[name]
    desired = relative @ b.bone.matrix_local.to_quaternion()
    inherited = b.parent.matrix.to_quaternion() @ b.parent.bone.matrix_local.to_quaternion().inverted()
    b.rotation_quaternion = (inherited @ b.bone.matrix_local.to_quaternion()).inverted() @ desired
    bpy.context.view_layer.update()


def elbow_point(start, end, pole, a, b):
    vector = end - start
    dist = min(vector.length, a + b - .0002)
    assert dist > abs(a-b)
    axis = vector.normalized()
    pole = pole - axis * pole.dot(axis)
    projection = (a*a + dist*dist - b*b) / (2*dist)
    return start + axis * projection + pole.normalized() * math.sqrt(max(0., a*a - projection*projection))


def limb(rig, upper, lower, end, pole):
    a, b = (rig.pose.bones[name] for name in (upper, lower))
    start = a.head.copy()
    delta = end - start
    limit = a.length + b.length - .002
    if delta.length > limit:
        end = start + delta.normalized()*limit
    mid = elbow_point(start, end, V(pole), a.length, b.length)
    aim_bone(rig, upper, mid - start)
    aim_bone(rig, lower, end - mid)


def wrist(rig, side, down, face):
    # The held prop's upright axis and orientation are independent of the forearm aim.
    # This also keeps the hammer's shaft in the fist over the full strike arc.
    z = V(down).normalized()
    y = V(face) - z * z.dot(V(face))
    y.normalize()
    x = y.cross(z)
    set_world_rotation(rig, f"hand.{side}", Matrix((x,y,z)).transposed().to_quaternion())


def q(axis, deg):
    return Quaternion(axis, math.radians(deg))


# These tuples describe actual wrist and ankle targets in metres, and facing in degrees.
# The upper and lower segments solve from those targets before FK keys are baked.
READY = {
    "hip": (0, .005, -.053), "body": (.5, -1, -3), "look": (-3, -5, -5),
    "apron": -2.,
    "R": (-.365,-.037,1.013), "L": (.369,-.175,1.137),
    "hammer": (-.28,.05,.96), "fitting": (.39,.10,.91),
    "rfoot": (-.225,.060,.149), "lfoot": (.229,-.093,.149),
    "turn_r": -12., "turn_l": 8.,
}


def beat(**values):
    return READY | values


def actions():
    return {
        "Ready": [(1, READY), (13, beat(hip=(-.006,.007,-.048), body=(2,-1,-4),
                                      look=(-4,-5,-2), R=(-.373,-.042,1.021), L=(.369,-.175,1.154))),
                  (25, READY)],
        "Try This": [(1, READY),
                     (6, beat(L=(.359,-.235,1.215), look=(7,1,-13), fitting=(.13,.2,.96))),
                     (13, beat(hip=(.027,.004,-.057), body=(4,4,2), look=(-2,5,22),
                               L=(.650,-.284,1.421), R=(-.374,-.036,1.008),
                               fitting=(.18,-.13,.97))),
                     (18, beat(hip=(.028,.002,-.056), body=(4,4,2), look=(-1,5,23),
                               L=(.651,-.287,1.425), R=(-.374,-.036,1.009),
                               fitting=(.21,-.15,.96))),
                     (23, beat(hip=(.021,.003,-.052), body=(3,2,0), look=(0,4,19),
                               L=(.601,-.248,1.386), fitting=(.40,.12,.92))),
                     (33, READY)],
        "Hammer Time": [(1, READY),
                        (8, beat(hip=(-.034,.058,-.055), body=(-14,-5,-15), look=(9,1,-5),
                                  R=(-.48,-.041,1.55), L=(.405,-.082,1.065),
                                  hammer=(-.29,.31,.90), fitting=(.42,.19,.89))),
                        (12, beat(hip=(-.040,.066,-.043), body=(-10,-6,-18), look=(9,2,5),
                                   R=(-.53,-.080,1.685), L=(.415,-.121,1.073),
                                   hammer=(-.26,.31,.91), fitting=(.40,.23,.88))),
                        (14.5, beat(hip=(-.055,-.022,-.080), body=(6,-6,-5), look=(10,2,-9),
                                   R=(-.539,-.277,1.421), L=(.385,-.145,1.053),
                                   hammer=(-.55,-.67,.49), fitting=(.38,.18,.91), apron=-9.)),
                        (17, beat(hip=(-.057,-.100,-.124), body=(18,-6,-12), look=(11,3,-18),
                                   R=(-.545,-.425,1.10), L=(.344,-.152,1.028),
                                   hammer=(-.51,-.71,-.49), fitting=(.35,.15,.93), apron=-14.)),
                        (19, beat(hip=(-.059,-.088,-.115), body=(17,-5,-11), look=(9,2,-16),
                                   R=(-.542,-.412,1.155), L=(.349,-.156,1.036),
                                   hammer=(-.52,-.69,-.46), fitting=(.35,.12,.94), apron=-12.)),
                        (24, beat(hip=(-.025,-.043,-.072), body=(7,-2,-1), look=(2,0,1),
                                   R=(-.373,-.315,1.186), hammer=(-.16,-.96,.22))),
                        (34, READY)],
        "Pursue Step": [(1, READY),
                        (6, beat(hip=(.055,-.015,-.043), body=(5,3,0), look=(-2,-2,0),
                                 R=(-.358,-.134,1.052), L=(.381,-.117,1.111),
                                 rfoot=(-.212,.007,.219), apron=-4.)),
                        (13, beat(hip=(-.005,-.174,-.084), body=(10,-1,-3), look=(-4,-1,0),
                                  R=(-.366,-.226,1.020), L=(.371,-.292,1.146),
                                  rfoot=(-.225,-.433,.149), apron=-13.)),
                        (19, beat(hip=(-.053,-.345,-.060), body=(7,-3,-3), look=(-2,-3,0),
                                  R=(-.357,-.327,1.015), L=(.359,-.498,1.166),
                                  rfoot=(-.225,-.433,.149), lfoot=(.224,-.278,.218), apron=-10.)),
                        (28, beat(hip=(0,-.488,-.053), R=(-.365,-.530,1.013), L=(.369,-.668,1.137),
                                  rfoot=(-.225,-.433,.149), lfoot=(.229,-.586,.149)))],
    }


def pose(rig, p):
    for bone in rig.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
        bone.rotation_mode = "QUATERNION"
    bpy.context.view_layer.update()
    pelvis = rig.pose.bones["pelvis"]
    pelvis.location = pelvis.bone.matrix_local.to_3x3().inverted() @ V(p["hip"])
    bpy.context.view_layer.update()
    pitch, lean, turn = p["body"]
    set_world_rotation(rig, "chest", q((0,0,1),turn) @ q((0,1,0),lean) @ q((1,0,0),pitch))
    pitch, lean, turn = p["look"]
    set_world_rotation(rig, "head", q((0,0,1),turn) @ q((0,1,0),lean) @ q((1,0,0),pitch))
    set_world_rotation(rig, "apron", q((1,0,0),p["apron"]))
    for side, s in (("R",-1),("L",1)):
        lift = max(0., min(1., (p["R"][2] - 1.13) / .43))
        arm_pole = (-.91,.70-.44*lift,-.09+.31*lift) if side == "R" else (.31,.54,-.80)
        limb(rig, f"upper_arm.{side}", f"forearm.{side}", V(p[side]), arm_pole)
        prop = p["hammer" if side == "R" else "fitting"]
        wrist(rig, side, prop, (.16,1.,.10) if side == "R" else (.20,1.,-.10))
        limb(rig, f"thigh.{side}", f"shin.{side}", V(p["rfoot" if side == "R" else "lfoot"]),
             (.29*s,-1.,.06))
        set_world_rotation(rig, f"foot.{side}", q((0,0,1), p["turn_r" if side == "R" else "turn_l"]))


def sample(keys, frame):
    for (start, a), (end, b) in zip(keys, keys[1:]):
        if frame <= end:
            t = (frame - start) / (end - start)
            t = t*t*(3-2*t)
            return {k: tuple(x+(y-x)*t for x,y in zip(a[k], b[k])) if isinstance(a[k], tuple)
                    else a[k]+(b[k]-a[k])*t for k in a}
    return keys[-1][1]


def make_actions(rig):
    scene = bpy.context.scene
    rig.animation_data_create()
    for name, keys in {"Neutral T": [(1, None)], **actions()}.items():
        asset = bpy.data.actions.new("Hobby Smith | " + name)
        asset.use_fake_user = True
        rig.animation_data.action = asset
        previous = {}
        for half in range(2, keys[-1][0]*2 + 1):
            frame = half / 2
            if name == "Neutral T":
                for bone in rig.pose.bones:
                    bone.matrix_basis = Matrix.Identity(4)
                    bone.rotation_mode = "QUATERNION"
            else:
                pose(rig, sample(keys, frame))
            for bone in rig.pose.bones:
                rotation = bone.rotation_quaternion.copy()
                if bone.name in previous and rotation.dot(previous[bone.name]) < 0:
                    rotation.negate()
                previous[bone.name] = rotation
                bone.rotation_quaternion = rotation
                bone.keyframe_insert("rotation_quaternion", frame=frame, group=bone.name)
            rig.pose.bones["pelvis"].keyframe_insert("location", frame=frame, group="pelvis")
        for channelbag in asset.layers[0].strips[0].channelbags:
            for curve in channelbag.fcurves:
                for key in curve.keyframe_points:
                    key.interpolation = "LINEAR"
        asset.asset_mark()
    rig.animation_data.action = bpy.data.actions["Hobby Smith | Ready"]
    scene.frame_start, scene.frame_end = 1, 25
    scene.frame_set(1)


def studio(bucket):
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.render.fps = FPS
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 18
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 624
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "AgX"
    world = bpy.data.worlds.new("Neutral workshop bounce")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (.74,.78,.86,1)
    background.inputs["Strength"].default_value = .42

    def camera(name, rotation, target, ortho):
        data = bpy.data.cameras.new(name)
        obj = bpy.data.objects.new(name, data)
        bucket.objects.link(obj)
        obj.rotation_euler = rotation
        obj.location = V(target) + obj.rotation_euler.to_matrix() @ V((0,0,7))
        data.type = "ORTHO"
        data.ortho_scale = ortho
        return obj

    # Aim slightly along the travelling step; the lens and facing do not change.
    scene.camera = camera("Camera_Tactical_3Q", CAMERA, (0,-.25,1.04), 2.47)
    camera("Camera_Front", (math.pi/2,0,0), (0,0,1.09), 2.48)
    camera("Camera_Portrait", (1.46,0,-.29), (-.014,-.09,1.84), .79)
    camera("Camera_Back", (1.37,0,2.77), (0,0,1.09), 2.47)

    for name, pos, energy, size, color in (
        ("Broad key", (-3.7,-4.6,5.8), 630, 4.1, (1.,.86,.69)),
        ("Pale fill", (2.9,-2.8,3.9), 270, 4.0, (.73,.82,1.)),
        ("Warm rim", (1.1,2.9,4.9), 420, 3.0, (1.,.84,.68)),
    ):
        data = bpy.data.lights.new(name, "AREA")
        obj = bpy.data.objects.new(name, data)
        bucket.objects.link(obj)
        obj.location = pos
        obj.rotation_euler = (V((0,0,1.11))-obj.location).to_track_quat("-Z","Y").to_euler()
        data.energy, data.shape, data.size, data.color = energy, "DISK", size, color


def main():
    output = Path(sys.argv[sys.argv.index("--") + 1])
    assert output.is_absolute() and output.suffix == ".blend" and not output.exists(), output
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    groups = {name: collection(label) for name, label in [
        ("rig", "01 • Animation"), ("face", "02 • Face and quiff"), ("garb", "03 • Work clothes"),
        ("limb", "04 • Arms and boots"), ("gear", "05 • Detachable field kit"), ("studio", "06 • Review studio"),
    ]}
    rig = make_rig(groups["rig"])
    g = Geometry(rig, {name: material(name, *spec) for name, spec in PALETTE.items()})
    for key, fn in (("face", make_face), ("garb", make_costume), ("limb", make_limbs), ("gear", make_props)):
        g.bucket = groups[key]
        fn(g)
    make_actions(rig)
    studio(groups["studio"])
    bpy.context.scene["Asset status"] = "Hobby Smith model candidate; pending visual acceptance."
    bpy.context.scene["Concept"] = "games/company-of-unlikely-heroes/assets-source/guild-book/classes/blacksmith-native.png"
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == "VIEW_3D":
                area.spaces.active.region_3d.view_perspective = "CAMERA"
                area.spaces.active.overlay.show_overlays = False
    bpy.ops.wm.save_as_mainfile(filepath=str(output))


if __name__ == "__main__":
    main()
