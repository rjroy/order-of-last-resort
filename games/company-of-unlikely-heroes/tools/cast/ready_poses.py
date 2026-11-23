"""Ready-only performances sampled on immutable cast masters at bake time."""

from derived_poses import DerivedTake, PoseSample as ReadyPose


def ReadyIdle(source_action, end, poses):
    return DerivedTake("Ready Idle", source_action, end, poses, loop=True)


GUARD = "Wary, plant, cover, settle"

READY_IDLES = {
    # Tuck behind the shield a little, hold the worry, then let it ease.
    # Sample only the native lead-in before the guard's first step.
    "knight": ReadyIdle(GUARD, 43, (
        ReadyPose(1, 8),
        ReadyPose(6, 10),
        ReadyPose(10, 14),
        ReadyPose(15, 18, (("head", (2, 0, -2)),)),
        ReadyPose(21, 17, (("head", (2, 0, 1)),)),
        ReadyPose(26, 14),
        ReadyPose(32, 10.5),
    )),
    # A slow, skeptical tilt and a small drop of the free elbow. The staff
    # hand and its ground contact stay put.
    "healer": ReadyIdle("Ally Heal", 52, (
        ReadyPose(1, 1),
        ReadyPose(8, 1, (("head", (1, -2, 2)), ("clavicle.L", (0, -1, 0)))),
        ReadyPose(14, 1, (("head", (-1, -7, 7)), ("clavicle.L", (0, -3, 0)))),
        ReadyPose(20, 1, (("head", (-3, -11, 10)), ("clavicle.L", (1, -5, 0)),
                          ("forearm.L", (4, 0, -2)))),
        ReadyPose(29, 1, (("head", (-2, -10, 9)), ("clavicle.L", (1, -4, 0)),
                          ("forearm.L", (3, 0, -2)))),
        ReadyPose(36, 1, (("head", (0, -5, 4)), ("clavicle.L", (0, -2, 0)))),
        ReadyPose(42, 1, (("head", (0, -1, 1)),)),
    )),
    # Perk up, then let the big hat tip follow through. No raised casting hand.
    "wizard": ReadyIdle("Ready", 37, (
        ReadyPose(1, 1),
        ReadyPose(6, 1, (("chest", (-1, 0, 0)), ("head", (-2, 1, 0)))),
        ReadyPose(10, 1, (("chest", (-3, 1, 0)), ("head", (-5, 3, 1)),
                          ("hat.tip", (-6, -3, 0)))),
        ReadyPose(14, 1, (("chest", (-2, 1, 0)), ("head", (-2, 2, 2)),
                          ("hat.tip", (7, 12, 2)))),
        ReadyPose(19, 1, (("chest", (1, 0, 0)), ("head", (3, -1, 1)),
                          ("hat.tip", (6, 7, 1)))),
        ReadyPose(24, 1, (("head", (1, -1, 0)), ("hat.tip", (-3, -4, 0)))),
        ReadyPose(30, 1, (("hat.tip", (1, 2, 0)),)),
    )),
    # A quick look aside with the cap leading, then lag in the cape.
    # The retreat take moves a shoe from F6, so never use that section here.
    "rogue": ReadyIdle("Ready / Retreat", 45, (
        ReadyPose(1, 1),
        ReadyPose(7, 2.25),
        ReadyPose(11, 4, (("cap_tip", (0, 3, 0)),)),
        ReadyPose(15, 5, (("head", (0, 0, 8)), ("cape_fall", (0, -2, 3)))),
        ReadyPose(20, 4.5, (("head", (0, 0, 5)), ("cape_fall", (0, -4, 3)))),
        ReadyPose(25, 3, (("cape_fall", (0, -3, 1)),)),
        ReadyPose(32, 2, (("cape_fall", (0, 1, 0)),)),
    )),
    # Check the hip rack, nestle the elbow, then look back up. The rack and
    # both stowed flasks inherit the original pose throughout.
    "alchemist": ReadyIdle("Ready", 49, (
        ReadyPose(1, 1),
        ReadyPose(7, 1, (("head", (2, 1, -3)),)),
        ReadyPose(12, 1, (("head", (6, 4, -9)), ("upper.R", (0, -2, 2)))),
        ReadyPose(18, 1, (("head", (11, 8, -14)), ("upper.R", (1, -4, 3)),
                          ("fore.L", (-3, 2, 0)))),
        ReadyPose(24, 1, (("head", (9, 5, -12)), ("upper.R", (1, -4, 2)),
                          ("fore.L", (-2, 2, 0)))),
        ReadyPose(31, 1, (("head", (4, 2, -6)), ("upper.R", (0, -2, 1)))),
        ReadyPose(38, 1, (("head", (1, 0, -2)),)),
    )),
    # The head droops, then the gift-side shoulder catches up as he settles.
    # The stone follows the closed hand; nothing touches its socket or flight.
    "zombie": ReadyIdle("Ready", 57, (
        ReadyPose(1, 1),
        ReadyPose(8, 1, (("head", (3, -2, 0)),)),
        ReadyPose(15, 1, (("chest", (1, -2, 0)), ("head", (7, -5, -2)),
                          ("clavicle.R", (0, 1, 0)))),
        ReadyPose(22, 1, (("chest", (2, -3, 0)), ("head", (9, -8, -3)),
                          ("clavicle.R", (2, -2, 0)))),
        ReadyPose(29, 1, (("chest", (2, -3, 0)), ("head", (4, -5, -2)),
                          ("clavicle.R", (3, -3, 1)))),
        ReadyPose(37, 1, (("chest", (0, -1, 0)), ("head", (-3, 2, 1)),
                          ("clavicle.R", (1, -1, 0)))),
        ReadyPose(46, 1, (("head", (-1, 1, 0)),)),
    )),
}
