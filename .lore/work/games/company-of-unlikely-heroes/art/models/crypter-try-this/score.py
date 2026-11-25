"""Shot score at 24 fps. Marker labels mark presentation beats, not game rules."""

RIGS = {"necromancer": "Necromancer", "skeleton": "Skeleton", "zombie": "Zombie"}
READY = {"necromancer": "Ready", "skeleton": "Ready & Greet", "zombie": "Ready"}

# Frame, body pitch, head pitch, left wrist in rig space (or the native ready pose).
OWNER = {
    "recall": (
        (1, 0, 0, None), (5, 3, 3, (.27, -.36, 1.26)),
        (9, 8, 0, (.53, -.53, 1.33)), (13, 3, -3, (.44, -.34, 1.43)),
        (17, -5, -4, (.29, -.16, 1.47)), (21, 0, 4, (.24, -.23, 1.32)),
        (27, 0, 0, None),
    ),
    "hush": (
        (1, 0, 0, None), (6, 3, 4, (.24, -.35, 1.34)),
        (11, 5, 7, (.49, -.53, 1.23)), (17, 11, 8, (.55, -.56, 1.06)),
        (23, 12, 10, (.49, -.53, .98)), (29, 3, 5, (.26, -.34, 1.14)),
        (35, 0, 0, None),
    ),
    "stay_close": (
        (1, 0, 0, None), (6, -3, 3, (.29, -.21, 1.32)),
        (10, 1, -3, (.59, -.37, 1.33)), (15, 2, -3, (.63, -.42, 1.34)),
        (20, 1, 1, (.58, -.37, 1.32)), (26, 0, 0, (.34, -.31, 1.25)),
        (32, 0, 0, None),
    ),
}

# Zombie lowers to his right side. Each row gives the pelvis translation relative
# to Ready and the body-space offsets relative to the inherited Ready transforms.
# There is no recoil, launch, impact, flower throw, or reverse Rise animation.
LOWER = (
    (1, (0, 0, 0), {}),
    (5, (0, .04, -.08), {"chest": (11, 4, 0), "head": (11, 0, 0)}),
    (10, (-.03, .12, -.25), {"pelvis": (-10, -9, 2), "chest": (23, 5, 0), "head": (12, 5, 0)}),
    (15, (-.17, .11, -.49), {
        "pelvis": (-14, -36, 10), "chest": (12, -8, -5), "head": (6, 12, 8),
        "thigh.L": (-29, 6, 4), "shin.L": (52, 0, 0),
        "thigh.R": (-28, -5, 0), "shin.R": (45, 0, 0),
        "upper_arm.R": (16, 3, -19), "forearm.R": (8, 14, -34),
        "upper_arm.L": (-16, 5, 15), "forearm.L": (-30, 7, 2),
    }),
    (21, (-.17, .07, -.56), {
        "pelvis": (-12, -82, 11), "chest": (8, -2, -4), "head": (6, 0, 10),
        "thigh.L": (-15, 4, 5), "shin.L": (34, 0, 0), "foot.L": (-5, 7, 3),
        "thigh.R": (-10, -4, -2), "shin.R": (28, 0, 0),
        "upper_arm.R": (10, -18, -15), "forearm.R": (16, 9, -32),
        "upper_arm.L": (-15, 12, 5), "forearm.L": (-28, 6, 2),
    }),
    (26, (-.17, .07, -.57), {
        "pelvis": (-12, -88, 11), "chest": (8, -4, -4), "head": (4, -3, 10),
        "thigh.L": (-15, 4, 5), "shin.L": (33, 0, 0), "foot.L": (-5, 7, 3),
        "thigh.R": (-10, -4, -2), "shin.R": (28, 0, 0),
        "upper_arm.R": (10, -18, -15), "forearm.R": (16, 9, -32),
        "upper_arm.L": (-15, 12, 5), "forearm.L": (-28, 6, 2),
    }),
)

CLIPS = {
    "necromancer": {
        "recall": (27, {"Reach": 9, "Recall handoff": 17}),
        "hush": (35, {"Lowering cue": 11, "Release": 23}),
        "stay_close": (32, {"Indicate hero": 15}),
    },
    "skeleton": {"recall_tuck": (17, {"Arrival settle": 5, "Single identity handoff": 17})},
    "zombie": {"play_dead": (26, {"Lowering": 10, "Weight down": 21, "Original corpse handoff": 26})},
}

RENDER = {
    "necromancer": {"recall": (1, 5, 9, 13, 17, 21, 27), "hush": (6, 11, 17, 23, 29, 35),
                    "stay_close": (6, 10, 15, 20, 26, 32)},
    "skeleton": {"recall_tuck": (1, 5, 9, 13, 17)},
    "zombie": {"play_dead": (1, 5, 10, 13, 15, 18, 21, 26)},
}
