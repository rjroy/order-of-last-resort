import bpy, sys, math, random
from math import sin, cos, pi, radians as rad
from mathutils import Vector as V, Quaternion, Matrix, Euler
from pathlib import Path

out = Path(sys.argv[-1])
assert out.is_absolute() and not out.exists(), out
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
random.seed(501)


def collection(n):
    c = bpy.data.collections.new(n)
    scene.collection.children.link(c)
    return c


body = collection("01 • Face and figure")
garb = collection("02 • Split gambeson and boots")
armor = collection("03 • Forged pauldrons")
tool = collection("04 • Square maul")
ctr = collection("05 • Animation")
C = body
m = {}


def mat(n, col, spread=0.21):
    a = bpy.data.materials.new(n)
    a.diffuse_color = (*col, 1)
    a.use_nodes = True
    nt = a.node_tree
    p = nt.nodes.get("Principled BSDF")
    p.inputs["Roughness"].default_value = 0.88
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 6
    noise.inputs["Detail"].default_value = 3.5
    r = nt.nodes.new("ShaderNodeValToRGB")
    nt.links.new(noise.outputs["Fac"], r.inputs[0])
    nt.links.new(r.outputs[0], p.inputs["Base Color"])
    for e, k, pos in zip(
        r.color_ramp.elements, (1 - spread * 0.50, 1 + spread * 0.50), (0.32, 0.66)
    ):
        e.position = pos
        e.color = (*[min(1, c * k) for c in col], 1)
    m[n] = a


for n, col, sp in [
    ("oxblood", (0.29, 0.087, 0.041), 0.65),
    ("hem", (0.38, 0.14, 0.063), 0.49),
    ("rust", (0.18, 0.063, 0.032), 0.7),
    ("iron", (0.148, 0.122, 0.109), 0.68),
    ("steel", (0.29, 0.237, 0.168), 0.53),
    ("ochre", (0.54, 0.303, 0.092), 0.40),
    ("leather", (0.154, 0.079, 0.034), 0.55),
    ("welt", (0.075, 0.052, 0.035), 0.44),
    ("flax", (0.60, 0.455, 0.278), 0.53),
    ("dirt", (0.34, 0.244, 0.153), 0.55),
    ("skin", (0.64, 0.335, 0.166), 0.33),
    ("cheek", (0.59, 0.257, 0.135), 0.22),
    ("beard", (0.293, 0.179, 0.092), 0.46),
    ("buzz", (0.132, 0.087, 0.056), 0.63),
    ("hair", (0.080, 0.047, 0.028), 0.35),
    ("pants", (0.207, 0.156, 0.113), 0.6),
    ("wood", (0.312, 0.173, 0.074), 0.53),
    ("ink", (0.040, 0.027, 0.021), 0.23),
    ("ivory", (0.76, 0.64, 0.41), 0.22),
]:
    mat(n, col, sp)
ad = bpy.data.armatures.new("Bruiser • neutral bind")
rig = bpy.data.objects.new("Bruiser_Rig", ad)
ctr.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bind = {}


def bone(n, a, b, parent=None):
    e = ad.edit_bones.new(n)
    e.head = a
    e.tail = b
    if parent:
        e.parent = ad.edit_bones[parent]
    bind[n] = V(a), V(b)


bone("root", (0, 0, 0), (0, 0, 0.20))
bone("hips", (0, 0, 0.76), (0, 0, 1.01), "root")
bone("ribcage", (0, 0, 1.01), (0, 0, 1.55), "hips")
bone("head", (0, -0.03, 1.55), (0, -0.03, 1.87), "ribcage")
bone("maul", (0, 0, 1.5), (0.25, 0, 1.5), "root")
for side, tag in [(-1, "R"), (1, "L")]:
    for nm, a, b, p in [
        ("upper", (0.334 * side, 0, 1.51), (0.676 * side, 0, 1.51), "ribcage"),
        ("fore", (0.676 * side, 0, 1.51), (0.981 * side, 0, 1.51), "upper." + tag),
        ("fist", (0.981 * side, 0, 1.51), (1.085 * side, 0, 1.51), "fore." + tag),
        ("thigh", (0.16 * side, 0, 0.785), (0.177 * side, 0, 0.446), "hips"),
        ("calf", (0.177 * side, 0, 0.446), (0.195 * side, 0, 0.143), "thigh." + tag),
        ("boot", (0.195 * side, 0, 0.143), (0.195 * side, -0.16, 0.07), "calf." + tag),
    ]:
        bone(nm + "." + tag, a, b, p)
bpy.ops.object.mode_set(mode="OBJECT")
rig.show_in_front = True
ad.display_type = "STICK"


def attach(o, n):
    if n == "maul":
        # Parent assembly to the wrist via a single editable socket.
        o.parent = prop
        return
    g = o.vertex_groups.new(name=n)
    g.add(list(range(len(o.data.vertices))), 1, "REPLACE")
    o.parent = rig
    mod = o.modifiers.new("Bruiser bind", "ARMATURE")
    mod.object = rig


def mesh(name, vs, fs, ma, b, sm=True):
    d = bpy.data.meshes.new(name)
    d.from_pydata(vs, [], fs)
    d.update()
    o = bpy.data.objects.new(name, d)
    C.objects.link(o)
    d.materials.append(m[ma])
    for p in d.polygons:
        p.use_smooth = sm
    attach(o, b)
    return o


# All rings run counterclockwise from the apron front, looking down.
def rings(name, rows, ma, b, n=28, sm=True):
    vs = sum(rows, [])
    fs = (
        [tuple(reversed(range(n)))]
        + [
            (i * n + j, i * n + (j + 1) % n, (i + 1) * n + (j + 1) % n, (i + 1) * n + j)
            for i in range(len(rows) - 1)
            for j in range(n)
        ]
        + [tuple(range((len(rows) - 1) * n, len(rows) * n))]
    )
    return mesh(name, vs, fs, ma, b, sm)


def ell(name, loc, scale, ma, b, tilt=0):
    x, y, z = loc
    rx, ry, rz = scale
    n = 20
    rows = []
    for i in range(13):
        a = -pi / 2 + 0.003 + (pi - 0.006) * i / 12
        rows.append(
            [
                (
                    x + rx * cos(a) * sin(t) * cos(tilt) + rz * sin(a) * sin(tilt),
                    y - ry * cos(a) * cos(t),
                    z + rz * sin(a) * cos(tilt) - rx * cos(a) * sin(t) * sin(tilt),
                )
                for t in [2 * pi * j / n for j in range(n)]
            ]
        )
    return rings(name, rows, ma, b, n)


def loft(name, x, y, levels, ma, b, n=32, ir=0.0):
    rows = []
    for z, rx, ry, dy in levels:
        row = []
        for j in range(n):
            t = j * 2 * pi / n
            k = 1 + ir * (0.6 * cos(7 * t + 0.4) + 0.4 * sin(11 * t + z))
            row.append((x + rx * k * sin(t), y + dy - ry * k * cos(t), z))
        rows.append(row)
    return rings(name, rows, ma, b, n)


def line(n, pts, r, ma, b):
    pts = [V(p) for p in pts]
    rows = []
    ex = V((1, 0, 0))
    prev = None
    for i, p in enumerate(pts):
        v = (pts[min(len(pts) - 1, i + 1)] - pts[max(0, i - 1)]).normalized()
        ax = prev if prev is not None else (ex if abs(v.x) < 0.85 else V((0, 1, 0)))
        u = (ax - v * ax.dot(v)).normalized()
        w = v.cross(u)
        prev = u
        rr = r[i] if isinstance(r, list) else r
        rows.append(
            [
                tuple(p + rr * (u * cos(j * pi / 4) + w * sin(j * pi / 4)))
                for j in range(8)
            ]
        )
    return rings(n, rows, ma, b, 8)


def grid(n, rows, ma, b, thick=0.007):
    w = len(rows[0])
    o = mesh(
        n,
        sum(rows, []),
        [
            (i * w + j, i * w + j + 1, (i + 1) * w + j + 1, (i + 1) * w + j)
            for i in range(len(rows) - 1)
            for j in range(w - 1)
        ],
        ma,
        b,
    )
    mod = o.modifiers.new("Folded edge thickness", "SOLIDIFY")
    mod.thickness = thick
    return o


def axisform(n, side, levels, ma, b, z=1.51, N=28):
    rows = []
    for x, ry, rz, dy, dz in levels:
        rows.append(
            [
                (
                    side * x,
                    dy + ry * cos(side * 2 * pi * j / N),
                    z + dz + rz * sin(side * 2 * pi * j / N),
                )
                for j in range(N)
            ]
        )
    return rings(n, rows, ma, b, N)


def poly(n, face, offset, ma, b):
    # Bevel-edged, closed plates; normals recalculated below.
    vs = list(face) + [tuple(V(p) + V(offset)) for p in face]
    l = len(face)
    o = mesh(
        n,
        vs,
        [tuple(range(l)), tuple(reversed(range(l, 2 * l)))]
        + [(i, (i + 1) % l, l + (i + 1) % l, l + i) for i in range(l)],
        ma,
        b,
        False,
    )
    be = o.modifiers.new("Beaten edges", "BEVEL")
    be.width = 0.009
    be.segments = 2
    return o


def rect(n, x, y, z, w, d, h, ma, b):
    return poly(
        n,
        [
            (x - w, y - d, z - h),
            (x + w, y - d, z - h),
            (x + w, y + d, z - h),
            (x - w, y + d, z - h),
        ],
        (0, 0, 2 * h),
        ma,
        b,
    )


C = body
loft(
    "Thick neck",
    0,
    -0.018,
    [(1.41, 0.142, 0.126, 0), (1.51, 0.157, 0.12, 0), (1.625, 0.117, 0.122, -0.012)],
    "skin",
    "ribcage",
)
loft(
    "Chest at open vest",
    0,
    0,
    [
        (0.88, 0.264, 0.19, 0),
        (1.01, 0.288, 0.214, 0),
        (1.23, 0.341, 0.222, -0.002),
        (1.39, 0.355, 0.226, 0.006),
        (1.48, 0.292, 0.19, 0.013),
        (1.54, 0.138, 0.12, 0),
    ],
    "skin",
    "ribcage",
    32,
    0.027,
)
C = garb
# Front opening narrows at the belt, then opens into two separate split tails.
vest = []
for z, rx, ry, a, k in [
    (0.499, 0.396, 0.288, 0.23, 0.073),
    (0.640, 0.376, 0.28, 0.21, 0.041),
    (0.80, 0.328, 0.245, 0.17, 0.014),
    (0.95, 0.299, 0.237, 0.11, 0.003),
    (1.05, 0.31, 0.241, 0.14, 0.004),
    (1.17, 0.339, 0.236, 0.24, 0.004),
    (1.32, 0.365, 0.253, 0.39, 0.003),
    (1.45, 0.369, 0.221, 0.56, 0.003),
    (1.535, 0.308, 0.173, 0.55, 0.004),
    (1.562, 0.157, 0.134, 0.55, 0.006),
]:
    row = []
    for j in range(65):
        t = a + (2 * pi - 2 * a) * j / 64
        r = k * (0.30 * cos(t * 15) + 0.2 * sin(t * 19))
        row.append(
            (
                (rx + r) * sin(t),
                -(ry + r) * cos(t),
                z
                + k
                * (
                    0.57 * cos(t * 23 + 0.3)
                    + 0.54 * sin(9 * t)
                    + 0.42 * sin(17 * t + 0.85)
                ),
            )
        )
    vest.append(row)
coat = grid(
    "Sleeveless oxblood jerkin • jagged split tails", vest, "oxblood", "ribcage", 0.014
)
# Transfer skirt to hips with a continuous transition at the waist.
g = coat.vertex_groups.new(name="hips")
cg = coat.vertex_groups["ribcage"]
for v in coat.data.vertices:
    w = max(0, min(1, (1.09 - v.co.z) / 0.25))
    cg.add([v.index], 1 - w, "REPLACE")
    g.add([v.index], w, "REPLACE")
for edge, sgn in [(0, 1), (-1, -1)]:
    grid(
        "Turned collar facing",
        [[r[edge], r[edge + 2 * sgn]] for r in vest[4:]],
        "hem",
        "ribcage",
    )
    line("Shoulder piping", [r[edge] for r in vest[4:]], 0.008, "rust", "ribcage")
for s in (-1, 1):
    for j in range(4):
        x = s * (0.106 + 0.031 * j)
        z = 1.09 + j * 0.088
        ell(
            "Brass jerkin stud",
            (x, -0.233 + 0.004 * j, z),
            (0.016, 0.010, 0.016),
            "ochre",
            "ribcage",
        )
    for j in range(4):
        t = s * (0.48 + j * 0.455)
        line(
            "Vertical quilt seam",
            [
                (0.326 * sin(t), -0.245 * cos(t), 0.81),
                (0.306 * sin(t), -0.239 * cos(t), 0.92),
                (0.307 * sin(t), -0.241 * cos(t), 1.04),
            ],
            [0.001, 0.006, 0.002],
            "rust",
            "hips",
        )
loft(
    "Heavy waist belt",
    0,
    0,
    [
        (0.918, 0.304, 0.24, 0),
        (0.931, 0.315, 0.25, 0),
        (1.022, 0.308, 0.249, 0),
        (1.033, 0.301, 0.237, 0),
    ],
    "leather",
    "hips",
)
x = 0.014
y = -0.255
z = 0.973
line(
    "Wide beaten buckle",
    [
        (x - 0.082, y, z - 0.044),
        (x + 0.071, y - 0.005, z - 0.044),
        (x + 0.082, y - 0.005, z + 0.050),
        (x - 0.071, y, z + 0.050),
        (x - 0.082, y, z - 0.044),
    ],
    0.014,
    "ochre",
    "hips",
)
line(
    "Buckle pin",
    [(x - 0.023, y - 0.012, z + 0.037), (x - 0.024, y - 0.011, z - 0.018)],
    0.007,
    "steel",
    "hips",
)
line(
    "Cross-body carrying strap",
    [
        (0.225, -0.157, 1.511),
        (0.143, -0.219, 1.39),
        (0.062, -0.243, 1.28),
        (-0.088, -0.24, 1.12),
        (-0.181, -0.202, 1.012),
    ],
    0.028,
    "leather",
    "ribcage",
)
line(
    "Strap at back",
    [
        (0.225, -0.157, 1.511),
        (0.237, 0, 1.554),
        (0.213, 0.17, 1.486),
        (0.074, 0.239, 1.31),
        (-0.12, 0.216, 1.13),
        (-0.217, 0.179, 1.0),
    ],
    0.031,
    "leather",
    "ribcage",
)
loft(
    "Hip pouch • gusset",
    -0.328,
    -0.08,
    [
        (0.669, 0.077, 0.073, 0),
        (0.685, 0.102, 0.082, 0),
        (0.799, 0.107, 0.078, 0),
        (0.849, 0.087, 0.065, 0),
    ],
    "leather",
    "hips",
    18,
)
ell(
    "Envelope flap",
    (-0.343, -0.149, 0.803),
    (0.104, 0.031, 0.055),
    "wood",
    "hips",
    -0.13,
)
rect("Pouch clasp", -0.344, -0.183, 0.791, 0.020, 0.006, 0.018, "ochre", "hips")
for side, tag in [(-1, "R"), (1, "L")]:
    up = "upper." + tag
    fo = "fore." + tag
    fi = "fist." + tag
    th = "thigh." + tag
    ca = "calf." + tag
    bt = "boot." + tag
    C = garb
    loft(
        "Gathered broad breeches " + tag,
        side * 0.165,
        0,
        [
            (0.396, 0.114, 0.115, 0),
            (0.427, 0.142, 0.135, 0),
            (0.51, 0.151, 0.152, 0),
            (0.63, 0.157, 0.162, 0.005),
            (0.76, 0.156, 0.15, 0),
            (0.821, 0.127, 0.135, 0),
        ],
        "pants",
        th,
        28,
        0.09,
    )
    loft(
        "Raw breech hem " + tag,
        side * 0.17,
        0,
        [(0.383, 0.112, 0.109, 0), (0.405, 0.141, 0.129, 0), (0.444, 0.138, 0.128, 0)],
        "dirt",
        th,
        24,
        0.10,
    )
    loft(
        "Shin boot " + tag,
        side * 0.188,
        0,
        [
            (0.103, 0.097, 0.118, -0.005),
            (0.194, 0.104, 0.112, 0),
            (0.27, 0.109, 0.11, 0.004),
            (0.321, 0.124, 0.126, 0),
            (0.35, 0.116, 0.125, 0),
            (0.390, 0.103, 0.102, 0),
        ],
        "leather",
        ca,
        24,
        0.03,
    )
    loft(
        "Turned boot collar " + tag,
        side * 0.188,
        0,
        [
            (0.306, 0.121, 0.127, 0),
            (0.317, 0.134, 0.134, 0),
            (0.36, 0.129, 0.128, 0),
            (0.375, 0.12, 0.128, 0),
        ],
        "welt",
        ca,
        24,
        0.055,
    )
    loft(
        "Clumped broadtoe boots " + tag,
        side * 0.195,
        0,
        [
            (0.023, 0.119, 0.190, -0.068),
            (0.048, 0.13, 0.201, -0.064),
            (0.094, 0.135, 0.196, -0.066),
            (0.124, 0.125, 0.174, -0.048),
            (0.157, 0.099, 0.122, -0.014),
        ],
        "leather",
        bt,
        24,
        0.036,
    )
    loft(
        "Hobnailed sole " + tag,
        side * 0.195,
        0,
        [
            (0.010, 0.12, 0.192, -0.065),
            (0.016, 0.129, 0.202, -0.067),
            (0.041, 0.132, 0.202, -0.066),
            (0.051, 0.13, 0.197, -0.068),
        ],
        "welt",
        bt,
        24,
        0.035,
    )
    for i, z in enumerate((0.165, 0.255)):
        loft(
            "Boot strap " + tag,
            side * 0.188,
            0,
            [(z, 0.11 + i * 0.006, 0.119, 0), (z + 0.026, 0.112 + i * 0.007, 0.120, 0)],
            "welt",
            ca,
            24,
        )
        rect(
            "Boot buckle " + tag,
            side * 0.189,
            -0.123,
            z + 0.013,
            0.028,
            0.010,
            0.023,
            "ochre",
            ca,
        )
        rect(
            "Buckle well " + tag,
            side * 0.189,
            -0.136,
            z + 0.013,
            0.016,
            0.005,
            0.012,
            "welt",
            ca,
        )
    for j in range(3):
        ell(
            "Toe studs " + tag,
            (side * 0.195 + (j - 1) * 0.046, -0.228 + 0.014 * abs(j - 1), 0.096),
            (0.011, 0.009, 0.008),
            "steel",
            bt,
        )
    C = body
    axisform(
        "Deltoid to triceps " + tag,
        side,
        [
            (0.285, 0.112, 0.112, 0, 0),
            (0.337, 0.145, 0.153, 0.008, 0),
            (0.409, 0.171, 0.159, 0.009, 0),
            (0.482, 0.159, 0.148, 0.013, -0.005),
            (0.56, 0.146, 0.137, 0.015, -0.002),
            (0.633, 0.114, 0.112, 0, 0),
            (0.686, 0.098, 0.10, 0, 0),
        ],
        "skin",
        up,
    )
    ell(
        "Biceps mound " + tag,
        (side * 0.524, -0.047, 1.513),
        (0.129, 0.116, 0.113),
        "skin",
        up,
        side * 0.05,
    )
    axisform(
        "Forearm " + tag,
        side,
        [
            (0.639, 0.091, 0.098, 0, 0),
            (0.694, 0.113, 0.117, 0, 0),
            (0.744, 0.14, 0.13, 0, 0),
            (0.81, 0.13, 0.119, 0, 0),
            (0.895, 0.099, 0.095, 0, 0),
            (0.989, 0.074, 0.071, 0, 0),
        ],
        "skin",
        fo,
    )
    C = garb
    for j in range(6):
        x = 0.704 + j * 0.038
        r = [0.123, 0.145, 0.145, 0.138, 0.125, 0.112][j]
        axisform(
            "Underwrap fold " + tag,
            side,
            [
                (x - 0.011, r * 0.95, r * 0.88, 0, 0.003),
                (x, r + 0.004, r * 0.94, 0, 0.002),
                (x + 0.026, r + 0.001, r * 0.92, 0, -0.002),
                (x + 0.041, r * 0.88, r * 0.82, 0, 0),
            ],
            "flax" if j in [0, 2, 3, 5] else "dirt",
            fo,
        )
    axisform(
        "Leather wrist stop " + tag,
        side,
        [
            (0.924, 0.10, 0.09, 0, 0),
            (0.936, 0.111, 0.101, 0, 0),
            (0.965, 0.10, 0.092, 0, 0),
            (0.982, 0.083, 0.078, 0, 0),
        ],
        "leather",
        fo,
    )
    C = body
    # Hands close around the same keyed local shaft axis. Fingers are individually editable.
    ell(
        "Broad palm " + tag,
        (side * 1.026, 0.012, 1.513),
        (0.089, 0.075, 0.066),
        "skin",
        fi,
    )
    for j in range(4):
        xx = side * (1.012 + j * 0.031)
        line(
            "Curled finger " + tag,
            [
                (xx, 0.022, 1.542),
                (xx + 0.003 * side, -0.026, 1.549),
                (xx + 0.005 * side, -0.070, 1.524),
                (xx, -0.082, 1.485),
                (xx - 0.003 * side, -0.057, 1.468),
            ],
            [0.024, 0.027, 0.026, 0.022, 0.017],
            "skin",
            fi,
        )
    line(
        "Locking thumb " + tag,
        [
            (side * 0.99, -0.004, 1.504),
            (side * 0.981, -0.045, 1.483),
            (side * 1.00, -0.078, 1.472),
            (side * 1.039, -0.079, 1.483),
        ],
        [0.035, 0.032, 0.029, 0.021],
        "skin",
        fi,
    )
    C = armor
    # Six-sided folded shoulder shell hangs over the arm; rivets and brass rim follow the ribcage.
    for tier in [0, 1]:
        rows = []
        for j in range(4):
            f = j / 3
            xx = side * (0.196 + 0.296 * f + (0.033 if tier else 0))
            w = (0.146 + 0.057 * sin(f * 2.4) + 0.034 * f) * (
                1.0 if tier == 0 else 0.95
            )
            cz = 1.642 + 0.053 * sin(f * 2.7) - 0.103 * f - (0.077 if tier else 0)
            rows.append(
                [
                    (xx, ww * w, cz - dz * w)
                    for ww, dz in [
                        (-1, 0.75),
                        (-0.86, 0.31),
                        (-0.50, 0.06),
                        (0.08, -0.03),
                        (0.65, 0.16),
                        (1, 0.59),
                    ]
                ]
            )
        plate = grid(
            "Stepped pauldron " + tag,
            rows,
            "iron" if tier == 0 else "leather",
            "ribcage",
            0.023,
        )
        plate.data.polygons.foreach_set(
            "use_smooth", [False] * len(plate.data.polygons)
        )
        line(
            "Hammered rim " + tag,
            rows[-1],
            0.013,
            "ochre" if not tier else "steel",
            "ribcage",
        )
        line("Front-flange rim " + tag, [r[0] for r in rows], 0.010, "ochre", "ribcage")
        for k in (1, 3):
            xx, yy, zz = rows[k][1]
            ell(
                "Pauldron peen " + tag,
                (xx, yy - 0.006, zz + 0.006),
                (0.017, 0.015, 0.017),
                "ochre",
                "ribcage",
            )
C = body


# Broad four-square jaw with a tight cropped scalp, thick brow break, split ear and broken nose.
def skull(name, levels, ma, N=40):
    rows = []
    for z, rx, ry, dy in levels:
        row = []
        for j in range(N):
            t = j * 2 * pi / N
            v = sin(t)
            u = cos(t)
            row.append(
                (
                    rx * math.copysign(abs(v) ** 0.73, v),
                    dy - ry * math.copysign(abs(u) ** 0.78, u),
                    z,
                )
            )
        rows.append(row)
    return rings(name, rows, ma, "head", N)


skull(
    "Block jaw and domed skull",
    [
        (1.545, 0.077, 0.079, -0.053),
        (1.558, 0.115, 0.131, -0.066),
        (1.589, 0.153, 0.139, -0.051),
        (1.644, 0.158, 0.148, -0.043),
        (1.701, 0.147, 0.149, -0.034),
        (1.761, 0.154, 0.144, -0.026),
        (1.817, 0.146, 0.134, -0.018),
        (1.867, 0.115, 0.111, -0.012),
        (1.885, 0.072, 0.082, -0.010),
    ],
    "skin",
)
ell(
    "Protruding battered chin",
    (0.007, -0.168, 1.597),
    (0.113, 0.063, 0.050),
    "skin",
    "head",
)
ell("Thick lower lip", (0.011, -0.204, 1.641), (0.072, 0.027, 0.014), "cheek", "head")
line(
    "Set mouth",
    [
        (-0.075, -0.19, 1.646),
        (-0.041, -0.215, 1.647),
        (0.011, -0.224, 1.651),
        (0.051, -0.212, 1.655),
        (0.077, -0.19, 1.652),
    ],
    [0.002, 0.004, 0.005, 0.004, 0.001],
    "ink",
    "head",
)
ell("Bent bridge", (0.003, -0.183, 1.73), (0.032, 0.045, 0.061), "skin", "head", 0.12)
ell("Broken nose", (0.009, -0.213, 1.7), (0.048, 0.044, 0.031), "cheek", "head", -0.13)
for side in [-1, 1]:
    ell(
        "Ear lobe",
        (side * 0.151, -0.015, 1.705),
        (0.035, 0.049, 0.057),
        "skin",
        "head",
        -side * 0.12,
    )
    ell(
        "Battered ear fold",
        (side * 0.175, -0.043, 1.711),
        (0.019, 0.022, 0.035),
        "cheek",
        "head",
        side * 0.2,
    )
    line(
        "Ear notch",
        [
            (side * 0.169, -0.058, 1.738),
            (side * 0.179, -0.055, 1.719),
            (side * 0.172, -0.061, 1.705),
        ],
        [0.002, 0.005, 0.002],
        "beard",
        "head",
    )
    ell(
        "Knotted cheek",
        (side * 0.104, -0.147, 1.682),
        (0.056, 0.038, 0.040),
        "skin",
        "head",
        -side * 0.13,
    )
    ell(
        "Eye socket",
        (side * 0.068, -0.166, 1.746),
        (0.053, 0.017, 0.022),
        "buzz",
        "head",
        -side * 0.12,
    )
    ell(
        "Narrow ivory eye",
        (side * 0.069, -0.176, 1.746),
        (0.039, 0.013, 0.014),
        "ivory",
        "head",
        -side * 0.10,
    )
    ell(
        "Forward gaze",
        (side * 0.069 + 0.007, -0.187, 1.747),
        (0.012, 0.006, 0.013),
        "ink",
        "head",
    )
    line(
        "Scowling shelf",
        [
            (side * 0.024, -0.185, 1.754),
            (side * 0.051, -0.186, 1.763),
            (side * 0.079, -0.173, 1.772),
            (side * 0.106, -0.156, 1.775),
            (side * 0.124, -0.142, 1.764),
        ],
        [0.013, 0.022, 0.022, 0.016, 0.003],
        "beard",
        "head",
    )
    line(
        "Brows in shadow",
        [
            (side * 0.028, -0.20, 1.757),
            (side * 0.053, -0.201, 1.763),
            (side * 0.085, -0.183, 1.777),
            (side * 0.104, -0.166, 1.777),
        ],
        [0.004, 0.008, 0.008, 0.003],
        "buzz",
        "head",
    )
    line(
        "Cheek plane crease",
        [
            (side * 0.062, -0.19, 1.69),
            (side * 0.082, -0.186, 1.672),
            (side * 0.087, -0.182, 1.652),
        ],
        [0.003, 0.005, 0.001],
        "beard",
        "head",
    )
    ell(
        "Nostril",
        (side * 0.026 + 0.009, -0.242, 1.696),
        (0.010, 0.006, 0.005),
        "beard",
        "head",
    )
# Conform the cap to the same squared skull profile at each hairline height.
profile = [
    (1.68, 0.154, 0.148, -0.039),
    (1.701, 0.147, 0.149, -0.034),
    (1.761, 0.154, 0.144, -0.026),
    (1.817, 0.146, 0.134, -0.018),
    (1.867, 0.115, 0.111, -0.012),
    (1.885, 0.072, 0.082, -0.010),
    (1.894, 0.005, 0.010, -0.010),
]


def scalp(t, u):
    low = 1.761 + 0.054 * cos(t) - 0.040 * abs(sin(t)) + 0.004 * cos(13 * t)
    zz = low + (1.893 - low) * u
    for (za, xa, ya, da), (zb, xb, yb, db) in zip(profile, profile[1:]):
        if zz <= zb:
            break
    k = max(0, min(1, (zz - za) / (zb - za)))
    x = xa + (xb - xa) * k + 0.003
    y = ya + (yb - ya) * k + 0.003
    dy = da + (db - da) * k
    return (
        x * math.copysign(abs(sin(t)) ** 0.73, sin(t)),
        dy - y * math.copysign(abs(cos(t)) ** 0.78, cos(t)),
        zz + 0.002,
    )


rows = [
    [scalp(j * 2 * pi / 64, u) for j in range(64)]
    for u in (0, 0.05, 0.15, 0.26, 0.4, 0.52, 0.65, 0.78, 0.86, 0.94, 0.985, 1)
]
rings("Close-cropped scalp with cut hairline", rows, "buzz", "head", 64)
for j in range(47):
    t = j * 2 * pi / 47
    line(
        "Clipper mark",
        [scalp(t, 0.038), scalp(t + 0.01, 0.105)],
        [0.002, 0.001],
        "beard",
        "head",
    )
line(
    "Old temple nick",
    [(0.111, -0.147, 1.782), (0.122, -0.139, 1.794), (0.13, -0.129, 1.809)],
    [0.002, 0.003, 0.001],
    "flax",
    "head",
)
for j in range(75):
    t = random.uniform(-1.44, 1.44)
    z = random.uniform(1.572, 1.623)
    x = 0.142 * math.copysign(abs(sin(t)) ** 0.75, sin(t))
    y = -0.057 - 0.143 * max(0.01, cos(t)) ** 0.78
    if abs(x) < 0.098:
        y = min(
            y,
            -0.164
            - 0.064
            * math.sqrt(max(0, 1 - (x / 0.114) ** 2 - ((z - 1.596) / 0.053) ** 2)),
        )
    line(
        "Two-day stubble",
        [(x, y - 0.002, z), (x + 0.0014, y - 0.003, z + 0.005)],
        [0.0016, 0.0009],
        "beard",
        "head",
    )
C = garb
# Crossed linen collar, edging, small reinforcement patches and individual brass peens.
for sgn in [-1, 1]:
    grid(
        "Turned linen neckline",
        [
            [(sgn * 0.047, -0.167, 1.513), (sgn * 0.129, -0.139, 1.52)],
            [(sgn * 0.033, -0.218, 1.413), (sgn * 0.099, -0.216, 1.407)],
            [(sgn * 0.006, -0.233, 1.307), (sgn * 0.039, -0.236, 1.312)],
        ],
        "flax",
        "ribcage",
    )
    line(
        "Vest roll",
        [
            (sgn * 0.235, -0.117, 1.517),
            (sgn * 0.218, -0.172, 1.461),
            (sgn * 0.158, -0.227, 1.328),
            (sgn * 0.084, -0.246, 1.18),
        ],
        [0.027, 0.021, 0.017, 0.010],
        "hem",
        "ribcage",
    )
    for k in range(4):
        x = sgn * (0.112 + 0.035 * k)
        ell(
            "Lower studs",
            (x, -0.245 + 0.012 * k, 0.729 + 0.021 * k),
            (0.013, 0.01, 0.014),
            "ochre",
            "hips",
        )
for t in (0.35, 0.88, 1.4, 2.01, 2.6, 3.11, 3.6, 4.17, 4.8, 5.31, 5.86):

    def skirt(a, z, k):
        return (0.384 * k * sin(a), -0.29 * k * cos(a), z)

    grid(
        "Overlap at skirt edge",
        [
            [skirt(t - 0.13, 0.748, 0.91), skirt(t + 0.18, 0.765, 0.91)],
            [skirt(t - 0.15, 0.588, 1.0), skirt(t + 0.16, 0.61, 1.0)],
            [
                skirt(t - 0.108, 0.52 + 0.024 * sin(t * 5), 1.03),
                skirt(t + 0.111, 0.496 + 0.024 * cos(t * 7), 1.02),
            ],
        ],
        "rust" if t > 3 else "hem",
        "hips",
    )
C = armor
for sg in [-1, 1]:
    pts = [
        (0.221, -0.062, 1.647),
        (0.351, -0.103, 1.666),
        (0.48, -0.143, 1.586),
        (0.498, -0.127, 1.566),
        (0.425, -0.043, 1.62),
        (0.279, 0.023, 1.656),
    ]
    poly(
        "Embossed shoulder ridge",
        [(sg * x, y, z) for x, y, z in pts],
        (0, 0, 0.01),
        "steel",
        "ribcage",
    )
C = tool
prop = bpy.data.objects.new("Maul_Detachable", None)
tool.objects.link(prop)
prop.parent = rig
prop.parent_type = "BONE"
prop.parent_bone = "maul"
bpy.context.view_layer.update()
prop.matrix_parent_inverse = prop.matrix_world.inverted()
axisform(
    "Short ash haft",
    1,
    [
        (-0.40, 0.035, 0.036, 0, 0),
        (-0.365, 0.041, 0.040, 0, 0),
        (-0.31, 0.034, 0.033, 0, 0),
        (-0.21, 0.030, 0.034, 0, 0),
        (0.16, 0.030, 0.034, 0, 0),
        (0.32, 0.039, 0.041, 0, 0),
        (0.429, 0.06, 0.055, 0, 0),
        (0.64, 0.052, 0.052, 0, 0),
    ],
    "wood",
    "maul",
    1.5,
    16,
)
for j in range(9):
    x = -0.295 + j * 0.048
    axisform(
        "Haft binding",
        1,
        [
            (x, 0.034, 0.036, 0, 0),
            (x + 0.01, 0.037, 0.038, 0, 0),
            (x + 0.021, 0.036, 0.036, 0, 0),
        ],
        "leather",
        "maul",
        1.5,
        16,
    )
# Eight-sided chamfered rectangular hammer, short enough to carry horizontally.
for name, lev, ma in [
    (
        "Wedge-forged iron head",
        [
            (0.38, 0.064, 0.083),
            (0.415, 0.103, 0.116),
            (0.575, 0.119, 0.126),
            (0.637, 0.105, 0.109),
        ],
        "iron",
    ),
    (
        "Face collar",
        [(0.571, 0.121, 0.128), (0.603, 0.124, 0.13), (0.621, 0.118, 0.123)],
        "steel",
    ),
    (
        "Poll hoop",
        [(0.393, 0.087, 0.10), (0.413, 0.107, 0.119), (0.432, 0.106, 0.118)],
        "ochre",
    ),
]:
    rows = []
    for x, ry, rz in lev:
        rows.append(
            [
                (x, vy * ry, 1.50 + vz * rz)
                for vy, vz in [
                    (1, 0.68),
                    (0.67, 1),
                    (-0.67, 1),
                    (-1, 0.68),
                    (-1, -0.68),
                    (-0.67, -1),
                    (0.67, -1),
                    (1, -0.68),
                ]
            ]
        )
    rings(name, rows, ma, "maul", 8, False)
for xx in [0.455, 0.548]:
    ell("Square head pin", (xx, -0.108, 1.50), (0.019, 0.012, 0.019), "ochre", "maul")
    ell("Back pin", (xx, 0.108, 1.50), (0.016, 0.009, 0.016), "steel", "maul")
# Analytic grips and leg reach sampled onto ordinary local FK keys. The square head is never released.
I = Quaternion()
Q = lambda x=0, y=0, z=0: Euler(tuple(map(rad, (x, y, z))), "XYZ").to_quaternion()
rig.animation_data_create()
pbs = rig.pose.bones
# Record world poses compactly: rib tilt, side bend, twist, head aim, hip drop / shift,
# center of the two grips, tool axis pitch & yaw, leading and trailing foot lifts.
#            lean side twist look  drop sx  gy       gx     gz    pitch yaw   lead rear
P = {
    "base": (13, -3, -6, 12, -0.078, 0, -0.355, 0.045, 1.052, -9, 0, 0, 0),
    "breath": (15, -4, -8, 15, -0.082, 0.008, -0.36, 0.055, 1.067, -10, 1, 0, 0),
    "step": (18, -9, -11, 15, -0.094, -0.032, -0.38, 0.057, 1.043, -13, 2, 0.15, 0),
    "pass": (15, 4, -2, 12, -0.071, 0.038, -0.35, 0.037, 1.073, -7, -2, 0, 0.13),
    "load": (5, -17, -25, 17, -0.122, -0.069, -0.32, -0.144, 1.318, -58, 12, 0, 0),
    "crest": (3, -21, -31, 18, -0.134, -0.081, -0.30, -0.164, 1.405, -66, 9, 0, 0),
    "impact": (33, 15, 19, 14, -0.138, 0.083, -0.49, 0.302, 0.95, 31, -6, 0, 0),
    "follow": (39, 20, 24, 13, -0.151, 0.093, -0.505, 0.29, 0.87, 39, -5, 0, 0),
    "catch": (21, 11, 11, 14, -0.109, 0.051, -0.421, 0.169, 0.962, 17, 0, 0, 0),
    "hit": (-7, -18, -17, 4, -0.119, -0.048, -0.302, -0.067, 1.135, -27, 4, 0, 0),
    "buckle": (39, 17, 20, 9, -0.29, 0.074, -0.49, 0.204, 0.751, 28, -4, 0, 0),
    "down": (61, 28, 27, 12, -0.462, 0.09, -0.56, 0.219, 0.49, 35, -6, 0, 0),
}


def direction(n, d):
    return (bind[n][1] - bind[n][0]).normalized().rotation_difference(V(d).normalized())


def solve(a, goal, pole, l1, l2):
    aim = goal - a
    u = aim.normalized()
    r = max(abs(l1 - l2) + 0.001, min(l1 + l2 - 0.001, aim.length))
    along = (l1 * l1 - l2 * l2 + r * r) / (2 * r)
    pole = V(pole)
    v = (pole - u * pole.dot(u)).normalized()
    joint = a + along * u + math.sqrt(max(0, l1 * l1 - along * along)) * v
    return joint - a, a + r * u - joint


lastq = {}


def pose(frame, values=None):
    heads = {}
    world = {}

    def put(n, q=I, delta=None):
        p = pbs[n]
        rest = p.bone.matrix_local.to_quaternion()
        parent = p.parent.name if p.parent else None
        par = world.get(parent, I)
        heads[n] = (
            heads[parent] + par @ (bind[n][0] - bind[parent][0])
            if parent
            else bind[n][0]
        ) + V(delta or (0, 0, 0))
        world[n] = q
        rot = rest.inverted() @ par.inverted() @ q @ rest
        if n in lastq:
            rot.make_compatible(lastq[n])
        lastq[n] = rot.copy()
        p.rotation_mode = "QUATERNION"
        p.rotation_quaternion = rot
        p.location = rest.inverted() @ par.inverted() @ V(delta or (0, 0, 0))
        p.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=n)
        p.keyframe_insert(data_path="location", frame=frame, group=n)

    if values is None:
        for p in pbs:
            put(p.name)
        return
    lean, side, twist, look, drop, sx, gy, gx, gz, pitch, yaw, lead, rear = values
    put("root")
    hip = Q(0, side * 0.13, twist * 0.14)
    put("hips", hip, (sx, 0, drop))
    rib = Q(lean, side, twist)
    put("ribcage", rib)
    put("head", Q(lean * 0.35 - 7 + max(0, (-drop - 0.20) * 126), side * 0.49, look))
    mq = Q(9, pitch, yaw)
    center = V((gx, gy, gz))
    put("maul", mq, center - bind["maul"][0])
    for s, t in [(-1, "R"), (1, "L")]:
        up = "upper." + t
        fo = "fore." + t
        fi = "fist." + t
        th = "thigh." + t
        ca = "calf." + t
        bt = "boot." + t
        shoulder = heads["ribcage"] + rib @ (bind[up][0] - bind["ribcage"][0])
        grip = center + mq @ V((s * 0.153, 0, 0))
        handq = mq
        wrist = grip - handq @ V((s * 0.065, -0.048, 0))
        a, b = solve(shoulder, wrist, (s * 1.1, 0.32, -0.34), 0.342, 0.305)
        put(up, direction(up, a))
        put(fo, direction(fo, b))
        put(fi, handq)
        h = heads["hips"] + hip @ (bind[th][0] - bind["hips"][0])
        lift = lead if t == "L" else rear
        ankle = V(
            (
                s * (0.286 + 0.20 * lift),
                (-0.082 if t == "L" else 0.074) - 0.62 * lift,
                0.143 + lift,
            )
        )
        a, b = solve(
            h,
            ankle,
            (s * 0.24, -1, 0.05),
            (bind[th][1] - bind[th][0]).length,
            (bind[ca][1] - bind[ca][0]).length,
        )
        put(th, direction(th, a))
        put(ca, direction(ca, b))
        put(bt, Q(-lift * 60, 0, s * 5))


def take(name, keys):
    lastq.clear()
    action = bpy.data.actions.new("Bruiser | " + name)
    action.use_fake_user = True
    rig.animation_data.action = action
    if keys is None:
        pose(1)
        return action
    for (fa, pa), (fb, pb) in zip(keys, keys[1:]):
        for f in range(fa, fb):
            u = (f - fa) / (fb - fa)
            u = u * u * (3 - 2 * u)
            pose(f, [a + (b - a) * u for a, b in zip(P[pa], P[pb])])
    pose(keys[-1][0], P[keys[-1][1]])
    return action


take("Neutral T", None)
ready = take("Ready", [(1, "base"), (18, "breath"), (37, "base")])
take("Trudge", [(1, "base"), (8, "step"), (15, "base"), (22, "pass"), (29, "base")])
strike = take(
    "Heavy Strike",
    [
        (1, "base"),
        (9, "load"),
        (15, "crest"),
        (18, "impact"),
        (21, "follow"),
        (25, "follow"),
        (33, "catch"),
        (42, "base"),
    ],
)
strike.pose_markers.new("Weight lands").frame = 18
strike.pose_markers.new("Follow through").frame = 21
take("Hit", [(1, "base"), (4, "hit"), (8, "hit"), (17, "base")])
take("Down", [(1, "base"), (5, "hit"), (12, "buckle"), (21, "down"), (29, "down")])
rig.animation_data.action = ready
scene.frame_set(1)
scene.render.fps = 24
scene.frame_end = 37
scene.unit_settings.system = "METRIC"
scene.world = bpy.data.worlds.new("Studio")
scene.world.color = (0.48, 0.48, 0.48)
scene.view_settings.view_transform = "Standard"
rig["Reference"] = (
    "Sheet 01, bottom left, SHA f3a93be9d71479a142b88c46597558e460ae9a729735b87fb8a54591c48af767"
)
rig["Stage"] = "Model review candidate"
for a in bpy.context.screen.areas:
    if a.type == "VIEW_3D":
        a.spaces.active.region_3d.view_rotation = Euler(
            (1.15, 0, -0.435)
        ).to_quaternion()
        a.spaces.active.region_3d.view_distance = 3.1
        a.spaces.active.region_3d.view_location = (0, 0, 0.91)
        a.spaces.active.overlay.show_overlays = False
        a.spaces.active.shading.color_type = "MATERIAL"
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(out), compress=True)
