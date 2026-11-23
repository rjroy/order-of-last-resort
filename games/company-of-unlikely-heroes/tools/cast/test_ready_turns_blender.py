"""Run: blender -b --python-exit-code 1 -P games/company-of-unlikely-heroes/tools/cast/test_ready_turns_blender.py"""

import sys
from pathlib import Path

import bpy
from mathutils import Euler

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bake_actor import ready_turns


armature = bpy.data.armatures.new("Test armature")
rig = bpy.data.objects.new("Test rig", armature)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
for name in ("keyed", "unkeyed"):
    bone = armature.edit_bones.new(name)
    bone.head = (0, 0, 0)
    bone.tail = (0, 0, 1)
bpy.ops.object.mode_set(mode="OBJECT")

keyed = rig.pose.bones["keyed"]
unkeyed = rig.pose.bones["unkeyed"]
keyed.rotation_mode = unkeyed.rotation_mode = "QUATERNION"
keyed.rotation_quaternion = Euler((0.1, 0.2, 0.3)).to_quaternion()
keyed.keyframe_insert(data_path="rotation_quaternion", frame=1)
unkeyed.rotation_quaternion = Euler((0.2, -0.1, 0.4)).to_quaternion()
scene = bpy.context.scene
scene.frame_set(1)
native = rig.animation_data.action
slot = rig.animation_data.action_slot
original = unkeyed.rotation_quaternion.copy()
turns = (("unkeyed", (0, 20, 0)),)


def check_restored(label):
    assert rig.animation_data.action == native, label + ": native action not restored"
    assert rig.animation_data.action_slot == slot, label + ": action slot not restored"
    scene.frame_set(2)
    scene.frame_set(1)
    assert unkeyed.rotation_quaternion.rotation_difference(original).angle < 1e-5, (
        label + ": unkeyed rotation leaked into the next native sample"
    )


with ready_turns(rig, turns):
    assert unkeyed.rotation_quaternion.rotation_difference(original).angle > 0.1
check_restored("normal exit")

try:
    with ready_turns(rig, turns):
        raise ValueError("render failed")
except ValueError:
    pass
check_restored("exceptional exit")

# A non-quaternion bone fails after an earlier bone was already modified.
unkeyed.rotation_mode = "XYZ"
keyed_original = keyed.rotation_quaternion.copy()
try:
    with ready_turns(rig, (("keyed", (0, 20, 0)),)):
        pass
except AssertionError:
    pass
else:
    raise AssertionError("non-quaternion mode was accepted")
assert unkeyed.rotation_mode == "XYZ", "rotation mode changed"
assert keyed.rotation_quaternion.rotation_difference(keyed_original).angle < 1e-5, (
    "partial setup leaked a rotation"
)
assert rig.animation_data.action == native and rig.animation_data.action_slot == slot
print("PASS: ready turns restore native action and unkeyed rotations on all exits")
