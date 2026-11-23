"""One-shot guild gestures, on the performing hero's own rig."""

from derived_poses import DerivedTake, PoseSample as Pose
from ready_poses import GUARD


RESCUE_LINE = DerivedTake("Rescue Line", GUARD, 28, (
    Pose(1, 8),
    Pose(4, 8, (("upper_arm.R", (-28, 4, 23)), ("forearm.R", (-13, -5, 0)),
                ("head", (1, 0, -5)))),
    Pose(8, 8, (("upper_arm.R", (-53, -6, 34)), ("forearm.R", (-13, -6, -14)),
                ("hand.R", (4, -10, -10)), ("head", (5, 0, -9)))),
    Pose(11, 8, (("upper_arm.R", (-56, -7, 36)), ("forearm.R", (-12, -6, -15)),
                 ("hand.R", (7, -12, -10)), ("head", (4, 0, -9)))),
    Pose(14, 8, (("upper_arm.R", (5, 4, 4)), ("forearm.R", (-70, 6, -14)),
                 ("hand.R", (0, -12, -7)), ("head", (-5, 0, -5)))),
    Pose(18, 8, (("upper_arm.R", (8, 1, 7)), ("forearm.R", (-53, 4, -7)),
                 ("head", (-3, 0, -3)))),
    Pose(22, 8, (("upper_arm.R", (3, 0, 4)), ("forearm.R", (-23, 1, 5)))),
    Pose(26, 8),
))

RING_SPARKS = DerivedTake("Ring of Sparks", "Pull", 28, (
    Pose(1, 1),
    Pose(4, 4),
    Pose(8, 8, (("forearm.L", (0, 0, -9)), ("forearm.R", (0, 0, 9)))),
    Pose(12, 8, (("upper_arm.L", (0, 0, 24)), ("forearm.L", (14, -10, 65)),
                 ("hand.L", (-9, 0, 0)), ("upper_arm.R", (0, 0, -24)),
                 ("forearm.R", (14, 10, -65)), ("hand.R", (-9, 0, 0)),
                 ("head", (-12, 0, -4)), ("hat.tip", (9, 0, 0)))),
    Pose(15, 8, (("upper_arm.L", (0, 0, 22)), ("forearm.L", (12, -9, 60)),
                 ("upper_arm.R", (0, 0, -22)), ("forearm.R", (12, 9, -60)),
                 ("head", (-8, 0, -3)), ("hat.tip", (5, 0, 0)))),
    Pose(19, 6, (("upper_arm.L", (0, 0, 14)), ("forearm.L", (9, -4, 35)),
                 ("upper_arm.R", (0, 0, -14)), ("forearm.R", (9, 4, -35)),
                 ("head", (-3, 0, 0)))),
    Pose(23, 3, (("forearm.L", (4, -2, 10)), ("forearm.R", (4, 2, -10)))),
    Pose(26, 1),
))

TRIPWIRE = DerivedTake("Tripwire", "Confusing Dodge", 27, (
    Pose(1, 1),
    Pose(4, 3, (("head", (4, 0, 0)),)),
    Pose(8, 4, (("chest", (26, 1, 0)), ("head", (14, 0, 2)),
                ("upper_arm.L", (5, -17, -7)), ("forearm.L", (11, -7, 27)),
                ("hand.L", (12, -8, 0)))),
    Pose(10, 4, (("chest", (34, 2, 1)), ("head", (17, 0, 3)),
                 ("upper_arm.L", (9, -20, -13)), ("forearm.L", (10, -17, 32)),
                 ("hand.L", (15, -12, 0)), ("cape_fall", (6, -7, 0)))),
    Pose(13, 4, (("chest", (22, 0, 14)), ("head", (7, 0, -3)),
                 ("upper_arm.L", (12, -6, 4)), ("forearm.L", (-34, 22, -12)),
                 ("hand.L", (0, 12, -10)), ("upper_arm.R", (7, 0, -5)),
                 ("cape_fall", (9, -7, 0)))),
    Pose(17, 4, (("chest", (8, 0, 4)), ("head", (2, 0, -3)), ("forearm.L", (-16, 8, -5)),
                 ("cape_fall", (5, -4, 0)))),
    Pose(21, 3, (("forearm.L", (-5, 3, -2)), ("cape_fall", (2, 0, 0)))),
    Pose(25, 1),
))

GRAVE_BELL = DerivedTake("Grave Bell", "Summon Skeleton", 27, (
    Pose(1, 1),
    Pose(4, 4, (("forearm.L", (8, 0, 0)),)),
    Pose(8, 7, (("forearm.L", (14, 0, 5)), ("forearm.R", (-8, 0, 20)),
                ("hand.R", (-6, 13, 7)), ("head", (2, 0, 1)))),
    Pose(12, 7, (("upper_arm.R", (-8, 5, -8)), ("forearm.R", (4, 0, -31)),
                 ("hand.R", (17, -27, -12)), ("clapper.R", (-12, 0, 13)),
                 ("forearm.L", (20, 0, 6)), ("head", (6, 0, -5)))),
    Pose(15, 7, (("upper_arm.R", (-5, 4, -5)), ("forearm.R", (-1, 0, -24)),
                 ("hand.R", (9, -13, -8)), ("clapper.R", (11, 0, -6)),
                 ("forearm.L", (17, 0, 5)), ("head", (4, 0, -3)))),
    Pose(19, 5, (("forearm.R", (-4, 0, -8)), ("forearm.L", (9, 0, 3)))),
    Pose(23, 3),
    Pose(25, 1),
))

FLASK_GRIP = ("prop.acid", "hand.L")
ETCHING_PASTE = DerivedTake("Etching Paste", "Acid Toss", 29, (
    Pose(1, 1),
    Pose(4, 4),
    Pose(7, 6),
    Pose(10, 6, (("upper.L", (-14, -3, 34)), ("fore.L", (-10, 0, 14)),
                 ("hand.L", (3, -3, 0)), ("head", (-4, 0, 10))), FLASK_GRIP),
    Pose(13, 6, (("upper.L", (-25, -8, 61)), ("fore.L", (-17, 0, 34)),
                 ("hand.L", (13, -8, 5)), ("head", (-5, 0, 19))), FLASK_GRIP),
    Pose(16, 6, (("upper.L", (-26, -9, 58)), ("fore.L", (-13, 0, 36)),
                 ("hand.L", (19, -9, 3)), ("head", (-5, 1, 18))), FLASK_GRIP),
    Pose(19, 6, (("upper.L", (-15, -4, 34)), ("fore.L", (-8, 0, 16)),
                 ("head", (-2, 0, 9))), FLASK_GRIP),
    Pose(22, 6),
    Pose(25, 4),
    Pose(27, 1),
))

TRAINING_TAKES = {
    ("knight", "rescue_line"): RESCUE_LINE,
    ("knight", "rescue_line_unshielded"): RESCUE_LINE,
    ("wizard", "ring_sparks"): RING_SPARKS,
    ("rogue", "tripwire"): TRIPWIRE,
    ("necromancer", "grave_bell"): GRAVE_BELL,
    ("alchemist", "etching_paste"): ETCHING_PASTE,
}
