"""Key the Knight's protective tap on the exact shipped rig, without saving it."""

import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from knight_fitted import Arm, DONOR, DONOR_SHA, GUARD, Pose, RIG, Take, create_take, digest, require_donor, select
from review_knight_fitted import geometry_check


COVER = Take(
    "Keep Your Head Down", 13, "Quiet tap / cover", 28,
    (
        Pose(1),
        Pose(5, (-.012, -.010, -.018), (4, -3, 3), (1, 0, -3),
             Arm((-.32, -.25, 1.24), (-.59, .00, 1.03), -12, (-3, -3, 4), -5)),
        Pose(9, (-.021, -.029, -.037), (8, -4, 6), (6, 0, -3),
             Arm((-.53, -.35, 1.42), (-.63, -.13, 1.12), -22, (-9, 4, -8), -11)),
        Pose(13, (-.031, -.041, -.062), (11, -5, 8), (15, 0, -5),
             Arm((-.57, -.41, 1.31), (-.67, -.18, 1.02), -22, (-18, 2, -8), -8),
             cape=(5, -4, 0)),
        Pose(17, (-.026, -.038, -.056), (10, -4, 7), (13, 0, -5),
             Arm((-.54, -.39, 1.29), (-.66, -.17, 1.03), -20, (-15, 2, -8), -7),
             cape=(4, -3, 0)),
        Pose(22, (-.012, -.012, -.023), (4, -2, 3), (6, 0, -3),
             Arm((-.34, -.26, 1.18), (-.60, -.06, 1.02), -10, (-5, 2, -4))),
        Pose(28),
    ),
    (9, 13, 17), ("bonk", (9, 13, 17)),
)


def main():
    output = Path(sys.argv[sys.argv.index("--") + 1]).resolve()
    assert output.suffix == ".blend" and not output.exists() and output != DONOR
    require_donor()
    scene = bpy.context.scene
    rig = bpy.data.objects[RIG]
    donor = bpy.data.actions[GUARD]
    select(rig, donor)
    scene.frame_set(8)
    ready = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
    action = create_take(COVER, scene, rig, donor)
    issues = geometry_check(scene, rig, COVER, action, ready)
    assert not issues, "\n".join(issues)
    bpy.data.libraries.write(str(output), {action}, path_remap="NONE", compress=True)
    assert digest(DONOR) == DONOR_SHA
    print(f"{output}: {digest(output)}")


if __name__ == "__main__":
    main()
