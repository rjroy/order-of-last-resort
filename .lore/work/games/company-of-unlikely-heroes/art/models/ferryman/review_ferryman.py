"""Read-only Blender review of the saved Ferryman; no game exports."""

from pathlib import Path
import sys, math
import bpy
from mathutils import Vector, Euler
from bpy_extras.object_utils import world_to_camera_view

args = sys.argv[sys.argv.index("--") + 1 :]
out = Path(args[0])
out.mkdir(exist_ok=True, parents=True)
mode = args[1] if len(args) > 1 else "poses"
repo = next(
    p
    for p in Path(__file__).resolve().parents
    if (p / "games/company-of-unlikely-heroes/tools/cast/bake_actor.py").is_file()
)
sys.path.insert(0, str(repo / "games/company-of-unlikely-heroes/tools/cast"))
from bake_actor import ink_light

s = bpy.context.scene
rig = bpy.data.objects["Ferryman_Rig"]
assert not bpy.data.libraries and not any(i.source == "FILE" for i in bpy.data.images)
assert bpy.data.objects["Oar_R_Detachable"].parent_bone == "oar_socket"
assert all(
    bpy.data.actions.get("Ferryman | " + name)
    for name in [
        "Neutral T",
        "Ready",
        "Cautious Step",
        "Safe Bank",
        "Down",
        "Flinch",
        "Recover",
    ]
)
print(
    "BONES",
    len(rig.pose.bones),
    "MESHES",
    sum(o.type == "MESH" for o in s.objects),
    "MATERIALS",
    len(bpy.data.materials),
)
print("ACTIONS", [(a.name, list(a.frame_range)) for a in bpy.data.actions])
for m in bpy.data.materials:
    ink_light(m)
cam = bpy.data.cameras.new("Review")
c = bpy.data.objects.new("Review", cam)
s.collection.objects.link(c)
s.camera = c
cam.type = "ORTHO"
cam.ortho_scale = 2.48
s.render.engine = "CYCLES"
s.cycles.samples = 4 if mode == "motion" else 8
s.cycles.use_denoising = False
s.render.film_transparent = True
s.render.image_settings.color_mode = "RGBA"
s.render.image_settings.file_format = "PNG"
s.render.resolution_x = s.render.resolution_y = 192 if mode == "motion" else 360
s.render.resolution_percentage = 100
s.view_settings.view_transform = "Standard"
s.view_settings.look = "None"
s.render.dither_intensity = 0
sets = [
    ("neutral", "Neutral T", 1, -0.435386419),
    ("ready", "Ready", 1, -0.435386419),
    ("travel", "Cautious Step", 13, -0.435386419),
    ("arrival", "Safe Bank", 34, -0.435386419),
    ("flinch", "Flinch", 5, -0.435386419),
    ("down", "Down", 23, -0.435386419),
    ("back", "Ready", 1, 2.56),
    ("side", "Ready", 1, -1.48),
]
if mode == "motion":
    seq = [
        ("Ready", range(1, 33, 3)),
        ("Cautious Step", range(1, 39, 3)),
        ("Safe Bank", range(1, 45, 3)),
        ("Safe Bank", [44] * 4),
    ]
    sets = [
        (f"m{i:03}", a, f, -0.435386419)
        for i, (a, f) in enumerate([(a, f) for a, fr in seq for f in fr])
    ]
for name, act, f, az in sets:
    rig.animation_data.action = bpy.data.actions["Ferryman | " + act]
    s.frame_set(f)
    c.rotation_euler = (1.150829196, 0, az)
    c.location = Vector((0, 0, 0.92)) + c.rotation_euler.to_matrix() @ Vector((0, 0, 6))
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    vs = [
        o.evaluated_get(dg).matrix_world @ v.co
        for o in s.objects
        if o.type == "MESH"
        for v in o.evaluated_get(dg).data.vertices
    ]
    bounds = [
        (round(min(p[k] for p in vs), 4), round(max(p[k] for p in vs), 4))
        for k in range(3)
    ]
    print("BOUNDS", name, bounds, flush=True)
    assert all(
        0.005 < x < 0.995 for p in vs[::5] for x in world_to_camera_view(s, c, p)[:2]
    )
    s.render.filepath = str(out / (name + ".png"))
    bpy.ops.render.render(write_still=True)
