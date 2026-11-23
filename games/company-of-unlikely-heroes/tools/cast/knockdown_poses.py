"""Living falls, braced holds, and recovery on each hero's own rig."""

from derived_poses import DerivedTake, PoseSample as Pose
from learner_poses import PULL
from ready_poses import GUARD


# Actor-specific support poses, with the board registration root kept at
# the tile. Pelvis offsets and bone turns are measured in model space.
BRACES = {
    # Right knee, left sole; the shield curls in clear of the floor.
    "knight": (
        GUARD, 8, (-.09, .02, -.37), (
            ("pelvis", (7, 0, -4)), ("chest", (12, -7, 4)), ("head", (-17, -4, 4)),
            ("thigh.L", (-66, -8, 0)), ("shin.L", (22, 0, 0)), ("boot.L", (19, 0, 0)),
            ("thigh.R", (13, 6, 0)), ("shin.R", (81, 0, 0)), ("boot.R", (-55, 0, 0)),
            ("upper_arm.R", (6, 12, -2)), ("forearm.R", (26, -8, 12)),
            ("upper_arm.L", (-9, -8, 9)), ("forearm.L", (8, -13, 12)),
            ("skirt.R", (-12, 0, 0)),
            ("skirt.L", (-38, 0, 6)), ("mantle", (-24, 0, 1)),
        ),
    ),
    # Left hip, free hand low, staff and satchel clear of the planted heel.
    "healer": (
        "Ally Heal", 1, (.12, .16, -.70), (
            ("pelvis", (1, 9, 0)), ("chest", (-8, 19, -4)), ("head", (9, -20, 6)),
            ("thigh.L", (-106, -9, 5)), ("shin.L", (40, 0, 0)), ("foot.L", (55, 0, 0)),
            ("thigh.R", (-106, 9, 0)), ("shin.R", (39, 0, 0)), ("foot.R", (65, 0, 0)),
            ("upper_arm.L", (27, -16, -27)), ("forearm.L", (15, -13, 17)),
            ("upper_arm.R", (-7, 3, 2)), ("forearm.R", (-20, -13, 18)),
            ("hand.R", (-70, 6, -12)), ("satchel", (9, 20, 0)),
            ("coat.front.L", (-86, 0, 5)), ("coat.front.R", (-77, 0, -5)),
            ("coat.back", (65, 0, 0)),
        ),
    ),
    # One knee and low elbow; no resemblance to the back-seated Pull tail.
    "wizard": (
        "Ready", 1, (.13, -.07, -.42), (
            ("pelvis", (5, 2, 0)), ("chest", (37, 13, 12)), ("head", (-24, -13, -8)),
            ("thigh.L", (-64, -11, 0)), ("shin.L", (23, 0, 0)), ("foot.L", (22, 0, 0)),
            ("thigh.R", (12, 8, 0)), ("shin.R", (89, 0, 0)), ("foot.R", (-54, 0, 0)),
            ("upper_arm.L", (5, 2, -14)), ("forearm.L", (30, -19, 6)),
            ("forearm.R", (-7, -8, 8)), ("tail.front.L", (-47, -4, 8)),
            ("tail.front.R", (-13, 0, -6)), ("tail.back.R", (40, 0, 6)),
            ("tail.side.L", (-50, 0, 0)), ("tail.back.L", (36, 0, 4)),
            ("tail.side.R", (-39, 0, 0)),
            ("hat.tip", (-9, 12, 6)), ("ledger_mount", (0, -14, 0)),
        ),
    ),
    # Evasive side spill; the left arm brakes the fall and the cape lags.
    "rogue": (
        "Ready / Retreat", 1, (.18, .12, -.73), (
            ("pelvis", (0, 10, -8)), ("chest", (3, 26, 10)), ("head", (-13, -21, -3)),
            ("thigh.L", (-117, -16, 0)), ("shin.L", (47, 0, 0)), ("foot.L", (25, 0, 0)),
            ("thigh.R", (-112, 11, -5)), ("shin.R", (25, 0, 0)), ("foot.R", (76, 0, 0)),
            ("upper_arm.L", (37, -23, -17)), ("forearm.L", (26, -15, 9)),
            ("hand.L", (-5, 0, 0)),
            ("upper_arm.R", (-22, 0, -5)), ("forearm.R", (-13, 2, 4)),
            ("cape_fall", (45, 8, -12)), ("cap_tip", (-5, 8, 0)),
        ),
    ),
    # Fold to the free side. Both instruments keep their native grips.
    "bard": (
        "Ready Count-In", 1, (-.14, .12, -.329), (
            ("pelvis", (4, -5, -3)), ("chest", (13, -18, -10)), ("head", (-12, 11, 4)),
            ("thigh.L", (20, -6, 0)), ("shin.L", (87, 0, 0)), ("foot.L", (-60, 0, 0)),
            ("thigh.R", (-80, 9, 0)), ("shin.R", (30, 0, 0)), ("foot.R", (16, 0, 0)),
            ("coat_tail.L", (29, 0, 0)), ("coat_tail.R", (26, 0, 0)),
        ),
    ),
    # The approval includes a grounded kneel and matching rise with held bell.
    # These are sampled with different arm work below to avoid a Raise Dead cue.
    "necromancer": ("Raise Dead", 1, (0, 0, 0), ()),
    # Fold away from the hip rack and catch with the free side.
    "alchemist": (
        "Ready", 1, (.16, .17, -.70), (
            ("pelvis", (0, 9, 0)), ("chest", (11, 21, 12)), ("head", (-9, -18, -5)),
            ("thigh.L", (-105, -13, 4)), ("shin.L", (48, 0, 0)), ("foot.L", (48, 0, 0)),
            ("thigh.R", (-112, 10, 0)), ("shin.R", (28, 0, 0)), ("foot.R", (71, 0, 0)),
            ("upper.L", (13, -20, -18)), ("fore.L", (18, -12, 9)),
            ("upper.R", (-18, 9, 8)), ("fore.R", (-12, -3, 3)),
            ("apron", (-99, 0, 0)), ("rack", (0, 44, 0)),
        ),
    ),
}

DOWN_FRAMES = (1, 4, 8, 12, 16, 20, 24)
RECOVER_FRAMES = (1, 5, 9, 13, 17, 22, 26)

# The feet may skid briefly on impact. These pelvis offsets are tuned
# independently of the angular weights so the body does not sink mid-fall.
DOWN_MOTION = ((0, 0), (-.09, 0), (.24, .06), (.57, .31), (1, 1), (1, 1), (1, 1))
UP_MOTION = ((1, 1), (1, 1), (.87, .80), (.64, .52), (.36, .23), (.10, .035), (0, 0))

# Small clearance offsets measured on the evaluated soles during the in-between
# drawings. Entry and terminal equipment/hold pictures do not use adjustments.
DOWN_CLEARANCE = {
    "knight": {12: -.025},
    "healer": {4: .014, 12: -.045},
    "wizard": {12: -.030},
    "rogue": {8: .014, 12: -.014},
    "bard": {8: .021},
    "alchemist": {12: -.061},
}
UP_CLEARANCE = {
    "healer": {13: .012, 17: .034, 22: .013},
    "rogue": {13: .041, 17: .071, 22: .028},
    "bard": {13: .031, 17: .048, 22: .017},
    "alchemist": {9: -.03, 13: -.030, 17: .010, 22: .011},
}


def brace_sample(frame, role, phase, drop, settle=0, clearance=0):
    _, native_frame, shift, axes = BRACES[role]
    if not phase and not drop:
        return Pose(frame, native_frame)
    turns = tuple((name, tuple(round(v * phase, 3) for v in angle)) for name, angle in axes
                  if phase > 0 or name in ("chest", "head"))
    if settle:
        turns = tuple((name, (angle[0] + settle, angle[1], angle[2]) if name == "head"
                             else angle) for name, angle in turns)
    x, y, z = shift
    offset = (round(x * max(0, phase), 4), round(y * max(0, phase), 4),
              round(z * drop + clearance, 4))
    return Pose(frame, native_frame, turns, shifts=(("pelvis", offset),))


def hero_fall(role):
    source = BRACES[role][0]
    down = tuple(brace_sample(f, role, *timing, settle=-5 if f == 16 else -2 if f == 20 else 0,
                              clearance=DOWN_CLEARANCE.get(role, {}).get(f, 0))
                 for f, timing in zip(DOWN_FRAMES, DOWN_MOTION))
    # The Bard leads the rise with the chin away from the fiddle.
    brace = (-8, -5) if role == "bard" else (8, 5)
    rise = tuple(brace_sample(f, role, *timing, settle=brace[0] if f == 5 else brace[1] if f == 9 else 0,
                              clearance=UP_CLEARANCE.get(role, {}).get(f, 0))
                 for f, timing in zip(RECOVER_FRAMES, UP_MOTION))
    return DerivedTake("Down", source, 28, down), DerivedTake("Recover", source, 29, rise)


def crypter_kneel(frame, source, weight):
    if not weight:
        return Pose(frame, 1, native="Ready")
    # Close the offering palm into a downward brace rather than opening it
    # toward a corpse. Bell hand follows the native tucked pose.
    turns = (
        ("upper_arm.L", (15, -12, -9)), ("forearm.L", (26, -10, 7)),
        ("hand.L", (16, 8, -5)), ("head", (-14, 4, -6)),
    )
    return Pose(frame, source, tuple((name, tuple(v * weight for v in angles))
                                      for name, angles in turns))


def crypter_fall():
    down = ((1, 0), (3, .1), (10, .3), (16, .7), (26, 1), (30, 1), (34, 1))
    rise = ((34, 1), (39, 1), (46, .9), (51, .7), (56, .45), (62, .2), (69, 0))
    return (
        DerivedTake("Down", "Raise Dead", 28, tuple(crypter_kneel(f, *args)
                     for f, args in zip(DOWN_FRAMES, down))),
        DerivedTake("Recover", "Raise Dead", 29, tuple(crypter_kneel(f, *args)
                     for f, args in zip(RECOVER_FRAMES, rise))),
    )


def seats():
    # These first drawings reuse the exact registered final Pull samples.
    wizard = DerivedTake("Seated Recover", "Pull", 29, (
        Pose(1, 33),
        Pose(5, 28, (("head", (9, 0, -2)), ("forearm.R", (12, 1, 2)))),
        Pose(9, 24, (("chest", (7, 0, 1)), ("head", (7, 0, -2)))),
        Pose(13, 21, (("chest", (9, 0, 0)), ("head", (3, 0, 0)))),
        Pose(17, 16),
        Pose(22, 1, (("chest", (3, 0, 0)), ("head", (-2, 0, 0))), native="Ready"),
        Pose(26, 1, native="Ready"),
    ))
    alchemist = DerivedTake("Seated Recover", "Ready", 29, (
        PULL.poses[-1]._replace(frame=1),
        PULL.poses[-2]._replace(frame=5),
        PULL.poses[-3]._replace(frame=9),
        PULL.poses[-4]._replace(frame=13),
        PULL.poses[-5]._replace(frame=17),
        Pose(22, 1, (("chest", (4, 0, 1)), ("head", (0, 3, 1)))),
        Pose(26, 1),
    ))
    return {("wizard", "seated_recover"): wizard, ("alchemist", "seated_recover"): alchemist}


KNOCKDOWN_TAKES = {}
for role in BRACES:
    down, recover = crypter_fall() if role == "necromancer" else hero_fall(role)
    KNOCKDOWN_TAKES[role, "down"] = down
    KNOCKDOWN_TAKES[role, "recover"] = recover
    if role == "knight":
        KNOCKDOWN_TAKES[role, "down_unshielded"] = down
        KNOCKDOWN_TAKES[role, "recover_unshielded"] = recover
KNOCKDOWN_TAKES.update(seats())
