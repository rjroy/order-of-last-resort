"""Adventure reward gestures on the approved Knight and Crypter rigs."""

from derived_poses import DerivedTake, PoseSample as Pose
from ready_poses import GUARD


SHIELD_RELEASE = 16
SHIELD_FLIGHT_CLIP = "shield_projectile"
SHIELD_THROW = DerivedTake("Shield Throw", GUARD, 35, (
    Pose(1, 8),
    Pose(5, 8, (("chest", (-2, -2, -5)), ("head", (0, 2, 6)),
                ("upper_arm.L", (-7, 2, -8)), ("forearm.L", (2, -6, 7)))),
    Pose(9, 8, (("chest", (-5, -6, -10)), ("head", (1, 4, 10)),
                ("upper_arm.L", (-12, 9, -13)), ("forearm.L", (-9, -17, 17)),
                ("pauldron.L", (-2, 2, -3)), ("mantle", (2, 0, 5)))),
    Pose(12, 8, (("chest", (-7, -8, -14)), ("head", (3, 4, 12)),
                 ("upper_arm.L", (-15, 14, -20)), ("forearm.L", (-13, -21, 24)),
                 ("pauldron.L", (-3, 3, -4)), ("mantle", (5, -2, 8)))),
    Pose(15, 8, (("chest", (11, 0, 13)), ("head", (-5, 0, -7)),
                 ("upper_arm.L", (-14, 6, 4)), ("forearm.L", (0, -3, -32)),
                 ("mantle", (-5, 4, -11)))),
    Pose(SHIELD_RELEASE, 8, (("chest", (14, 1, 16)), ("head", (-7, 0, -8)),
                           ("upper_arm.L", (-15, 6, 6)), ("forearm.L", (3, -4, -36)),
                           ("mantle", (-7, 3, -15)))),
    Pose(19, 8, (("chest", (17, 1, 20)), ("head", (-5, 1, -9)),
                 ("upper_arm.L", (-13, 6, 10)), ("forearm.L", (6, 1, -40)),
                 ("mantle", (-11, 4, -18)))),
    Pose(23, 8, (("chest", (12, 0, 10)), ("head", (-4, 1, -5)),
                 ("upper_arm.L", (-7, 3, 6)), ("forearm.L", (5, 0, -20)),
                 ("mantle", (-8, 3, -11)))),
    Pose(28, 8, (("chest", (3, 0, 3)), ("head", (-2, 0, -2)),
                 ("upper_arm.L", (-2, 0, 3)), ("forearm.L", (2, 0, -7)))),
    Pose(32, 8),
))

NOMINATE = DerivedTake("Say Hello to That One", "Ready", 30, (
    Pose(1, 1),
    Pose(5, 1, (("upper_arm.L", (-10, 0, 5)), ("forearm.L", (-4, 4, 7)),
                ("head", (-3, -2, 4)))),
    Pose(9, 1, (("upper_arm.L", (-29, -18, 4)), ("forearm.L", (3, -8, 52)),
                ("head", (-4, 0, 7)), ("hand.L", (45, -27, 1)),
                ("Index.L", (20, -7, 13)), ("Index_tip.L", (28, -9, 17)))),
    Pose(13, 1, (("upper_arm.L", (-37, -31, 4)), ("forearm.L", (8, -13, 76)),
                 ("head", (0, 0, 10)), ("hand.L", (74.3, -42.8, 1.4)),
                 ("Index.L", (33, -10.8, 21.3)), ("Index_tip.L", (46.4, -15.2, 28.4)))),
    Pose(17, 1, (("upper_arm.L", (-37, -31, 4)), ("forearm.L", (8, -13, 76)),
                 ("head", (3, 0, 9)), ("hand.L", (74.3, -42.8, 1.4)),
                 ("Index.L", (33, -10.8, 21.3)), ("Index_tip.L", (46.4, -15.2, 28.4)))),
    Pose(22, 1, (("upper_arm.L", (-18, -12, 2)), ("forearm.L", (1, -5, 34)),
                 ("head", (1, 0, 4)), ("hand.L", (22, -16, 0)))),
    Pose(27, 1),
))

REWARD_TAKES = {
    ("knight", "shield_throw"): SHIELD_THROW,
    ("knight", SHIELD_FLIGHT_CLIP): DerivedTake(
        SHIELD_THROW.title, SHIELD_THROW.source_action, SHIELD_RELEASE + 1,
        tuple(pose for pose in SHIELD_THROW.poses if pose.frame == SHIELD_RELEASE),
    ),
    ("necromancer", "nominate"): NOMINATE,
}
