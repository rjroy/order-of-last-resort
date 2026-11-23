"""Cross-trained abilities performed by the learner, not the donor."""

from derived_poses import DerivedTake, PoseSample as Pose
from ready_poses import GUARD


BONK = DerivedTake("Bonk and Taunt", GUARD, 33, (
    Pose(1, 8),
    Pose(5, 8, (("upper_arm.R", (-41, 7, -6)), ("forearm.R", (-14, -15, -21)))),
    Pose(9, 8, (("upper_arm.R", (-111, 10, -17)), ("forearm.R", (-34, -24, -20)),
                ("head", (-4, 0, -5)), ("hand.R", (12, 0, 0)))),
    Pose(11, 8, (("upper_arm.R", (-143, 7, 0)), ("forearm.R", (-35, -22, -14)),
                 ("head", (-4, 0, -6)), ("hand.R", (10, -5, 0)))),
    Pose(13, 8, (("upper_arm.R", (-51, 14, 35)), ("forearm.R", (10, 10, -19)),
                 ("hand.R", (45, -30, -15)), ("head", (8, 0, -6)))),
    Pose(16, 8, (("upper_arm.R", (-66, 5, 32)), ("forearm.R", (-10, -10, -14)),
                 ("hand.R", (11, -5, -4)), ("head", (4, 0, -6)))),
    Pose(20, 8, (("upper_arm.R", (-23, 3, 20)), ("forearm.R", (-27, 8, 2)),
                 ("head", (-7, -4, 9)))),
    Pose(24, 8, (("upper_arm.R", (-10, 1, 9)), ("forearm.R", (-18, 4, 0)),
                 ("head", (-4, -2, 5)))),
    Pose(30, 8),
))

BLAST = DerivedTake("Blast", "Ally Heal", 29, (
    Pose(1, 1),
    Pose(4, 5, (("head", (-3, -4, 3)), ("forearm.L", (-10, 3, -7)))),
    Pose(8, 8, (("head", (-5, -6, 7)), ("forearm.L", (-30, 7, -14)),
                ("hand.L", (-11, -4, 0)))),
    Pose(12, 15, (("clavicle.L", (-9, -3, 12)), ("forearm.L", (-4, -9, 4)),
                 ("hand.L", (-28, -9, 3)), ("head", (5, 0, 8)))),
    Pose(15, 14, (("clavicle.L", (-7, -1, 9)), ("forearm.L", (-2, -7, 3)),
                 ("hand.L", (-24, -7, 0)), ("head", (-5, 3, 7)))),
    Pose(18, 10, (("forearm.L", (-12, 3, -7)), ("head", (-6, 0, 5)))),
    Pose(22, 25, (("hand.L", (-8, 0, 0)), ("head", (-3, 0, 0)))),
    Pose(27, 1),
))

DODGE = DerivedTake("Confusing Dodge", "Pull", 27, (
    Pose(1, 1),
    Pose(4, 3, (("chest", (5, 8, -10)), ("head", (5, -4, 7)),
                ("forearm.L", (-17, -5, 12)))),
    Pose(8, 5, (("chest", (13, -17, -20)), ("head", (8, 11, 13)),
                ("upper_arm.L", (3, 11, -25)), ("forearm.L", (-21, 17, 16)),
                ("tail.side.L", (7, 7, -17)), ("hat.tip", (-8, 14, 12)))),
    Pose(11, 7, (("chest", (24, -27, 3)), ("head", (12, 16, 11)),
                 ("upper_arm.L", (8, 3, -31)), ("forearm.L", (-24, 15, 17)),
                 ("upper_arm.R", (16, -15, 6)), ("forearm.R", (-13, 11, 4)),
                 ("tail.side.L", (8, 10, -23)), ("hat.tip", (-19, 15, 3)))),
    Pose(14, 6, (("chest", (16, -17, 22)), ("head", (6, 14, -12)),
                 ("upper_arm.L", (12, 0, -23)), ("forearm.L", (-18, 12, 15)),
                 ("upper_arm.R", (5, -7, -7)), ("tail.side.L", (6, 8, -14)),
                 ("hat.tip", (11, -13, -13)))),
    Pose(18, 4, (("chest", (7, 4, 13)), ("head", (1, -4, -7)),
                 ("tail.side.L", (4, -3, 7)), ("hat.tip", (5, -9, 6)))),
    Pose(22, 2, (("head", (-3, 0, 0)), ("hat.tip", (-3, 3, 2)))),
    Pose(25, 1),
))

PUSH = DerivedTake("Push", "Ready Count-In", 29, (
    Pose(1, 1),
    Pose(4, 1, (("chest", (-5, 5, -9)), ("head", (-4, 2, -3)),
                ("forearm.R", (3, -7, 3)))),
    Pose(8, 1, (("chest", (-9, 10, -18)), ("head", (-7, 3, -5)),
                ("forearm.R", (7, -10, 6)), ("coat_tail.L", (3, -5, 9)))),
    Pose(12, 1, (("chest", (20, 9, 26)), ("head", (3, -5, -15)),
                 ("forearm.R", (9, -10, -12)), ("coat_tail.L", (-14, -4, 7)),
                 ("coat_tail.R", (-12, 8, 11)))),
    Pose(15, 1, (("chest", (17, 10, 22)), ("head", (5, -5, -14)),
                 ("forearm.R", (7, -8, -10)),
                 ("coat_tail.L", (-12, -3, 6)), ("coat_tail.R", (-8, 5, 7)))),
    Pose(19, 1, (("chest", (8, 4, 13)), ("head", (3, -2, -8)),
                 ("forearm.R", (5, -5, -5)), ("coat_tail.R", (-4, 3, 5)))),
    Pose(23, 1, (("chest", (2, -2, 5)), ("head", (0, 0, -3)))),
    Pose(27, 1),
))

# The vial is an action-only accessory. It stays with the left hand through
# the offer and is hidden on withdrawal, never launched as a projectile.
VIAL_FRAMES = frozenset({8, 11, 15, 18})
POTION = DerivedTake("Healing Potion", "Ready / Retreat", 31, (
    Pose(1, 1),
    Pose(4, 1, (("chest", (5, 7, -10)), ("head", (9, -4, 8)),
                ("upper_arm.L", (11, -12, -15)), ("forearm.L", (8, 6, -12)))),
    Pose(8, 1, (("chest", (7, 8, -12)), ("head", (13, -3, 9)),
                ("upper_arm.L", (-14, -15, -15)), ("forearm.L", (-16, -11, 4)),
                ("hand.L", (2, 4, -16)))),
    Pose(11, 1, (("chest", (6, 1, 4)), ("head", (6, -2, 9)),
                 ("upper_arm.L", (-31, -23, -21)), ("forearm.L", (-28, -9, 40)),
                 ("hand.L", (19, -9, 1)))),
    Pose(15, 1, (("chest", (9, 0, 8)), ("head", (3, 0, 6)),
                 ("upper_arm.L", (-39, -32, -25)), ("forearm.L", (-35, -10, 53)),
                 ("hand.L", (25, -15, 8)))),
    Pose(18, 1, (("chest", (8, 2, 8)), ("head", (2, 0, 7)),
                 ("upper_arm.L", (-38, -29, -25)), ("forearm.L", (-33, -7, 50)),
                 ("hand.L", (21, -12, 8)))),
    Pose(22, 1, (("chest", (4, 2, 5)), ("head", (1, 0, 3)),
                 ("upper_arm.L", (-21, -5, -21)), ("forearm.L", (-14, -3, 26)))),
    Pose(26, 1, (("forearm.L", (-6, 0, 8)),)),
    Pose(29, 1),
))

MELODY = DerivedTake("Inspiring Melody", "Summon Skeleton", 43, (
    Pose(1, 1),
    Pose(5, 4),
    Pose(9, 7, (("head", (-6, -6, -3)), ("forearm.L", (-9, -6, 5)))),
    Pose(13, 10, (("forearm.R", (9, 8, 17)), ("hand.R", (18, 9, 18)),
                 ("clapper.R", (-16, -3, 22)), ("head", (6, -9, -5)),
                 ("forearm.L", (-18, 3, 7)))),
    Pose(17, 11, (("forearm.R", (-12, -5, -14)), ("hand.R", (-19, -9, -12)),
                 ("clapper.R", (16, 7, -26)), ("head", (-6, 9, 6)),
                 ("forearm.L", (8, 0, 2)))),
    Pose(21, 10, (("forearm.R", (8, 7, 16)), ("hand.R", (18, 8, 20)),
                 ("clapper.R", (-16, -3, 20)), ("head", (6, -8, -6)),
                 ("forearm.L", (-15, 5, 12)))),
    Pose(25, 9, (("forearm.R", (-7, -3, -9)), ("hand.R", (-14, -3, -8)),
                 ("clapper.R", (13, 5, -19)), ("head", (-5, 6, 4)),
                 ("forearm.L", (5, 0, 3)))),
    Pose(29, 8, (("forearm.R", (6, 5, 9)), ("hand.R", (10, 4, 11)),
                 ("clapper.R", (-9, 0, 13)), ("head", (3, -5, -3)),
                 ("forearm.L", (-8, 4, 10)))),
    Pose(34, 5, (("head", (-3, 2, 3)),)),
    Pose(40, 1),
))


def recoil(frame, tilt, shin, toe, lean, shift, hands, cloth=(0, 0)):
    return Pose(frame, 1, (
        ("chest", (lean, -3, 2)), ("head", (18, 4, -3)),
        ("thigh.L", (tilt[0], -3, 0)), ("thigh.R", (tilt[1], 4, 0)),
        ("shin.L", (shin[0], 0, 0)), ("shin.R", (shin[1], 0, 0)),
        ("foot.L", (toe[0], 0, 0)), ("foot.R", (toe[1], 0, 0)),
        ("apron", (cloth[0], 0, 0)), ("rack", (0, cloth[1], 0)),
        *hands,
    ), shifts=(("pelvis", shift),))


PULL = DerivedTake("Pull", "Ready", 37, (
    Pose(1, 1),
    Pose(5, 1, (("chest", (6, 0, 6)), ("upper.L", (-20, -4, -11)),
                ("fore.L", (-9, 2, 12)), ("upper.R", (-19, 0, 9)),
                ("fore.R", (-13, -3, 7)))),
    Pose(9, 1, (("chest", (13, 0, 4)), ("upper.L", (-37, 4, -28)),
                ("fore.L", (-18, 8, 27)), ("upper.R", (-45, 2, 17)),
                ("fore.R", (-13, -8, -8)), ("head", (2, -1, 7)))),
    Pose(13, 1, (("chest", (-13, 2, 5)), ("upper.L", (-13, -3, -15)),
                 ("fore.L", (-59, 5, 17)), ("upper.R", (-11, 1, 7)),
                 ("fore.R", (-48, -4, -8)), ("head", (-4, 5, 6)))),
    recoil(16, (-19, -19), (5, 3), (8, 4), -20, (0, .10, -.029), (
        ("upper.L", (-31, 4, -25)), ("fore.L", (-55, 12, 27)),
        ("upper.R", (-23, 1, 10)), ("fore.R", (-35, -2, -9)),
    )),
    recoil(20, (-60, -64), (22, 12), (25, 24), -30, (.03, .18, -.30), (
        ("upper.L", (-32, -4, -28)), ("fore.L", (-28, 7, 25)),
        ("upper.R", (7, -6, 17)), ("fore.R", (21, 9, -7)),
    ), cloth=(-37, 12)),
    recoil(24, (-104, -111.3), (53, 38), (49, 58), -23, (.055, .22, -.734), (
        ("upper.L", (-18, 2, -14)), ("fore.L", (-36, 9, 24)),
        ("upper.R", (22, -2, 13)), ("fore.R", (24, -5, -8)),
    ), cloth=(-100, 44)),
    recoil(28, (-104, -111.3), (53, 38), (49, 58), -13, (.055, .22, -.734), (
        ("upper.L", (-3, 2, -10)), ("fore.L", (-26, 6, 16)),
        ("upper.R", (17, -2, 11)), ("fore.R", (13, -5, -4)),
    ), cloth=(-98, 44)),
    recoil(33, (-104, -111.3), (53, 38), (49, 58), -10, (.055, .22, -.734), (
        ("upper.L", (0, 2, -9)), ("fore.L", (-20, 4, 14)),
        ("upper.R", (14, -2, 11)), ("fore.R", (12, -5, -4)),
    ), cloth=(-98, 44)),
))

LEARNER_TAKES = {
    ("knight", "bonk"): BONK,
    ("knight", "bonk_unshielded"): BONK,
    ("healer", "blast"): BLAST,
    ("wizard", "dodge"): DODGE,
    ("bard", "push"): PUSH,
    ("rogue", "potion"): POTION,
    ("necromancer", "melody"): MELODY,
    ("alchemist", "pull"): PULL,
}
