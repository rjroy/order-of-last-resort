"""Read-only camera registration test: blender -b --python-exit-code 1 -P this file."""
import sys
from pathlib import Path

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bake_actor import setup

scene = bpy.context.scene
samples = [Vector((0, 0, 0)), Vector((0.7, -0.4, 1.5)), Vector((-0.2, 0.8, 0.3))]
projections = []
for size, anchor in [(320, [160, 248]), (512, [256, 344])]:
    setup(scene, "test", anchor, size)
    bpy.context.view_layer.update()
    camera = scene.camera.evaluated_get(bpy.context.evaluated_depsgraph_get())
    coords = [world_to_camera_view(scene, camera, p) for p in samples]
    projections.append([(uv.x * size - anchor[0], (1 - uv.y) * size - anchor[1]) for uv in coords])
for old, new in zip(*projections):
    assert all(abs(a - b) < 0.0001 for a, b in zip(old, new)), (old, new)
print("PASS: ground registration and projected release offsets match at 320px and 512px")
