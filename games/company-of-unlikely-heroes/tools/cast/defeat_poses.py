"""Unsupported terminal falls, kept within the heroes' registered tiles."""

from derived_poses import DerivedTake, PoseSample as Pose
from ready_poses import READY_IDLES


# Weight travels across the hips rather than standing on a spare hand or knee.
# Width and center are tuned independently for each approved silhouette.
FALLS = {
    "knight": (
        (-.02, -.05),
        (
            ("pelvis", (-17, -88, 10)), ("chest", (-45, 3, -9)), ("head", (-4, -46, -10)),
            ("thigh.L", (-26, 23, 10)), ("shin.L", (37, 0, 0)), ("boot.L", (-6, 14, -7)),
            ("thigh.R", (41, 8, -9)), ("shin.R", (18, 0, 0)), ("boot.R", (-9, -2, 3)),
            ("upper_arm.L", (7, 8, -12)), ("forearm.L", (-12, -18, -19)),
            ("upper_arm.R", (8, -8, 18)), ("forearm.R", (25, 8, -17)),
            ("skirt.L", (-25, 0, -8)), ("skirt.R", (15, 0, 4)), ("mantle", (6, 10, -5)),
        ),
    ),
    "healer": (
        (-.04, .03),
        (
            ("pelvis", (98, -63, -6)), ("chest", (66, -20, 4)), ("head", (19, -13, -7)),
            ("thigh.L", (-36, 31, 11)), ("shin.L", (44, 0, 0)), ("foot.L", (12, 5, -5)),
            ("thigh.R", (-23, -5, -9)), ("shin.R", (19, 0, 0)), ("foot.R", (0, -5, 6)),
            ("upper_arm.L", (9, -14, -11)), ("forearm.L", (21, -4, 13)),
            ("upper_arm.R", (-1, -51, -9)), ("forearm.R", (-48, 2, 8)), ("hand.R", (-37, -6, -18)),
            ("satchel", (29, 22, 0)), ("coat.back", (18, 0, 0)),
            ("coat.front.L", (-24, 0, -3)), ("coat.front.R", (-15, 16, 8)),
        ),
    ),
    "wizard": (
        (-.08, .04),
        (
            ("pelvis", (-52, 81, -43)), ("chest", (28, 14, -3)), ("head", (30, 13, -15)),
            ("thigh.L", (-53, -3, 5)), ("shin.L", (15, 0, 0)), ("foot.L", (3, 8, 2)),
            ("thigh.R", (-14, -10, -8)), ("shin.R", (52, -8, 0)), ("foot.R", (2, -7, -6)),
            ("upper_arm.L", (6, -6, 11)), ("forearm.L", (17, -3, -11)),
            ("upper_arm.R", (-4, 12, 9)), ("forearm.R", (21, 6, -8)),
            ("hat.tip", (22, -20, 23)), ("ledger_mount", (-6, -12, 1)),
            ("tail.front.R", (-23, 0, 6)), ("tail.side.R", (9, 0, -8)),
            ("tail.back.L", (-30, 0, 0)), ("tail.side.L", (-46, 0, 0)),
        ),
    ),
    "rogue": (
        (.04, .06),
        (
            ("pelvis", (69, 105, 13)), ("chest", (6, 10, 9)), ("head", (9, 13, -7)),
            ("thigh.L", (-32, -15, 8)), ("shin.L", (38, 0, 0)), ("foot.L", (3, 18, -3)),
            ("thigh.R", (-12, -23, -5)), ("shin.R", (52, -32, 0)), ("foot.R", (-8, -5, -5)),
            ("upper_arm.L", (5, -8, 22)), ("forearm.L", (12, -14, 9)),
            ("upper_arm.R", (8, 2, -11)), ("forearm.R", (23, 11, -8)),
            ("cape_fall", (13, -23, -24)), ("cap_tip", (9, -2, 6)),
        ),
    ),
    "bard": (
        (.07, -.05),
        (
            ("pelvis", (-86, -49, 32)), ("chest", (-17, -31, 35)), ("head", (36, 6, -8)),
            ("thigh.L", (4, 17, 8)), ("shin.L", (35, 0, 0)), ("foot.L", (0, 17, 1)),
            ("thigh.R", (-11, 9, -10)), ("shin.R", (21, 0, 0)), ("foot.R", (2, -9, -6)),
            ("upper_arm.L", (-62, -22, 0)),
            ("upper_arm.R", (83, 40, -8)), ("forearm.R", (17, 12, -59)),
            ("coat_tail.L", (17, -8, 13)), ("coat_tail.R", (13, 10, -8)),
        ),
    ),
    "necromancer": (
        (-.06, .06),
        (
            ("pelvis", (53, 101, -18)), ("chest", (4, -3, 8)), ("head", (17, -21, 49)),
            ("thigh.L", (-43, -13, -5)), ("shin.L", (48, 0, 0)), ("foot.L", (8, 9, 4)),
            ("thigh.R", (18, -11, -9)), ("shin.R", (26, 0, 0)), ("foot.R", (7, 1, -4)),
            ("upper_arm.L", (12, 57, 17)), ("forearm.L", (16, -14, 9)),
            ("upper_arm.R", (-3, -34, 5)), ("forearm.R", (23, 4, -6)),
            ("stole_end.L", (6, -22, 8)), ("stole_end.R", (9, 14, 9)),
            ("coat_tail.L", (-7, 10, -8)), ("coat_tail.R", (-4, -8, 7)),
        ),
    ),
    "alchemist": (
        (.06, -.04),
        (
            ("pelvis", (-63, 41, 13)), ("chest", (-30, 14, 4)), ("head", (-4, 13, 8)),
            ("thigh.L", (-62, -11, 5)), ("shin.L", (57, 0, 0)), ("foot.L", (3, 3, -4)),
            ("thigh.R", (-20, 11, -5)), ("shin.R", (32, 0, 0)), ("foot.R", (0, -7, 3)),
            ("upper.L", (15, -13, 7)), ("fore.L", (22, 6, -9)),
            ("upper.R", (5, 9, 12)), ("fore.R", (17, 9, -6)),
            ("rack", (5, -8, -2)), ("apron", (-20, 7, -8)),
        ),
    ),
}

FRAMES = (1, 4, 8, 12, 16, 20, 24)
# A short recoil, then weight breaks quickly into the contact pose.
FRACTIONS = (0, -.08, .21, .59, 1, 1, 1)
# Heights refine each visible floor contact independently of fall rotation.
# Values are signed offsets from the original ready pelvis, in metres.
HEIGHTS = {
    "knight": (0, .001, .045, -.127, -.470, -.470, -.471),
    "healer": (0, .001, .070, -.224, -.304, -.307, -.309),
    "wizard": (0, -.001, -.084, -.337, -.434, -.435, -.435),
    "rogue": (0, .001, .027, -.235, -.430, -.429, -.428),
    "bard": (0, -.005, .012, -.155, -.397, -.376, -.366),
    "necromancer": (0, .001, .060, -.175, -.510, -.510, -.510),
    "alchemist": (0, .004, -.052, -.282, -.536, -.534, -.532),
}


def defeat_take(role):
    if ready := READY_IDLES.get(role):
        source, ready_frame = ready.source_action, ready.poses[0].source
    else:
        source, ready_frame = ("Ready Count-In" if role == "bard" else "Ready"), 1
    center, angles = FALLS[role]
    samples = [Pose(1, ready_frame)]
    for frame, weight, z in zip(FRAMES[1:], FRACTIONS[1:], HEIGHTS[role][1:]):
        turns = []
        for name, values in angles:
            if weight < 0 and name not in ("chest", "head"):
                continue
            xyz = [round(v * weight, 3) for v in values]
            # A small last drop of the head and shoulders, not a brace.
            if frame < 24 and weight == 1 and name in ("chest", "head"):
                xyz[0] += (3 if frame == 16 else 1) * (1 if values[0] < 0 else -1)
            turns.append((name, tuple(xyz)))
        x, y = (round(v * max(weight, 0), 4) for v in center)
        # The Bard's idle mounts the fiddle to the chest, not the wrist.
        # When the arm goes slack, carry the original grip with it.
        carried = ("fiddle_mount.L", "hand.L") if role == "bard" and weight > 0 else None
        samples.append(Pose(frame, ready_frame, tuple(turns), carried=carried,
                            shifts=(("pelvis", (x, y, z)),)))
    return DerivedTake("Defeat", source, 28, tuple(samples))


DEFEAT_TAKES = {(role, "defeat"): defeat_take(role) for role in FALLS}
DEFEAT_TAKES["knight", "defeat_unshielded"] = DEFEAT_TAKES["knight", "defeat"]
