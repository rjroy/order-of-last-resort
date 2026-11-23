"""clip: (source action suffix, sampled frames, exclusive stop frame, loop).
Times are absolute 24-fps source offsets; held poses need only one drawing.
"""

from ready_poses import GUARD, READY_IDLES
from training_poses import TRAINING_TAKES
from learner_poses import LEARNER_TAKES
from reward_poses import REWARD_TAKES, SHIELD_FLIGHT_CLIP, SHIELD_RELEASE

TAKES = {
    "alchemist": {
        "ready": READY_IDLES["alchemist"].take(),
        "potion": (
            "Healing Potion",
            [1, 4, 7, 10, 13, 17, 20, 23, 24, 28, 32, 36],
            39,
            False,
        ),
        "acid": ("Acid Toss", [1, 4, 6, 9, 13, 16, 18, 21, 25, 29, 32], 35, False),
        "acid_flask": ("Acid Toss", [18], 19, False),
    },
    "knight": {
        "ready": READY_IDLES["knight"].take(),
        "guard": (GUARD, [8, 14, 20, 25, 31, 35, 39, 44, 51, 65], 78, False),
        "shield_away": (GUARD, [8], 32, True),
    },
    "ferryman": {
        "ready": ("Ready", [1, 8, 15, 23, 29], 33, True),
        "travel": (
            "Cautious Step", [1, 4, 7, 10, 13, 18, 21, 24, 28, 31, 35, 39], 40, False
        ),
        "safe_bank": (
            "Safe Bank", [1, 5, 9, 12, 15, 20, 23, 28, 34, 39, 44], 45, False
        ),
        "flinch": ("Flinch", [1, 3, 5, 9, 13, 17, 23], 24, False),
        "down": ("Down", [1, 5, 10, 14, 19, 23, 31], 32, False),
        "recover": ("Recover", [1, 5, 8, 12, 15, 20, 24], 25, False),
    },
    "harpooner": {
        "ready": ("Ready", [1, 6, 12, 18, 24, 28, 34, 38], 41, True),
        "pursue": ("Pursue", [1, 3, 5, 7, 9, 12, 14, 16, 18, 21], 22, False),
        "close_thrust": (
            "Close Thrust", [1, 3, 5, 7, 8, 10, 13, 16, 19, 23], 24, False
        ),
        "ranged_cast": (
            "Ranged Cast", [1, 3, 5, 6, 8, 10, 11, 13, 16, 19, 23], 24, False
        ),
        "harpoon_projectile": ("Ranged Cast", [11], 12, False),
        "hit": ("Hit", [1, 3, 4, 6, 8, 12, 17], 18, False),
        "defeat": ("Defeat", [1, 3, 4, 7, 9, 12, 15, 18, 22], 26, False),
    },
    "healer": {
        "ready": READY_IDLES["healer"].take(),
        "ally_heal": ("Ally Heal", [1, 4, 7, 10, 13, 17, 20, 23, 26, 28], 33, False),
        "self_heal": ("Self Heal", [1, 5, 9, 12, 17, 21, 25, 28], 33, False),
        "bonk": ("Adjacent Bonk", [1, 5, 10, 13, 15, 18, 23, 29], 33, False),
    },
    "wizard": {
        "ready": READY_IDLES["wizard"].take(),
        "blast": ("Blast", [1, 4, 7, 11, 14, 17, 21, 24, 29, 34], 41, False),
        "pull": ("Pull", [1, 4, 8, 13, 16, 19, 21, 24, 28, 33], 41, False),
    },
    "rogue": {
        "ready": READY_IDLES["rogue"].take(),
        "retreat": ("Ready / Retreat", [1, 5, 9, 13, 17, 21, 26], 30, False),
        "swap": ("Confusing Dodge", [1, 4, 7, 10, 12, 15, 19, 25, 30, 34], 38, False),
        "misdirect": ("Wasn't Me", [1, 5, 9, 14, 36, 42, 47, 50], 54, False),
    },
    "bard": {
        "ready": ("Ready Count-In", [1, 5, 9, 13, 17, 22], 25, True),
        "inspiring_melody": (
            "Inspiring Melody",
            [1, 5, 8, 11, 13, 17, 21, 25, 29, 32, 34, 38, 41, 46],
            49,
            True,
        ),
        "healing_sonnet": (
            "Healing Sonnet",
            [1, 4, 8, 11, 16, 21, 25, 31, 38, 43, 48, 55],
            61,
            True,
        ),
    },
    "necromancer": {
        "ready": ("Ready", [1, 7, 13, 19], 25, True),
        "summon_skeleton": (
            "Summon Skeleton",
            [1, 4, 7, 10, 13, 16, 20, 24, 27, 34, 39, 43],
            46,
            False,
        ),
        "raise_dead": (
            "Raise Dead",
            [1, 8, 13, 18, 22, 26, 34, 41, 45, 49, 54, 59, 64, 67],
            70,
            False,
        ),
    },
    "skeleton": {
        "ready": ("Ready & Greet", [1, 7, 11, 15, 18, 21, 24, 29, 33], 45, True),
        "wave": ("Wave", [1, 5, 8, 12, 15, 18, 20, 23, 26, 31, 38, 46], 54, False),
        "dont_go": (
            "Don't Go",
            [1, 5, 8, 13, 19, 27, 35, 40, 45, 50, 58, 63],
            66,
            False,
        ),
    },
    "zombie": {
        "ready": READY_IDLES["zombie"].take(),
        "say_hello": ("Say Hello", [1, 7, 12, 16, 19, 25, 30, 36, 42], 46, False),
        "offer_flower": (
            "Offer Flower",
            [1, 6, 10, 14, 17, 19, 21, 22, 24, 26, 29, 32, 37, 42, 47, 53],
            58,
            False,
        ),
        "gift": ("Offer Flower", [22], 46, False),
    },
}

DERIVED_TAKES = {
    **{(role, "ready"): idle for role, idle in READY_IDLES.items()},
    **TRAINING_TAKES,
    **LEARNER_TAKES,
    **REWARD_TAKES,
}
for (role, clip), performance in DERIVED_TAKES.items():
    if clip != "ready":
        TAKES[role][clip] = performance.take()

# Actor clip, detached clip, prop root, release source frame, optional Blender marker.
RELEASES = {
    "alchemist": ("acid", "acid_flask", "Acid_Flask_Detachable", 18, None),
    "harpooner": ("ranged_cast", "harpoon_projectile", "Harpoon_Detachable", 11, "Release"),
    "knight": ("shield_throw", SHIELD_FLIGHT_CLIP, "Shield_L_Detachable", SHIELD_RELEASE, None),
    "zombie": ("offer_flower", "gift", "Daisy & fieldstone", 22, "Gift Release"),
}

PILOT = {
    "knight": "2f1bd3cb93992886383e8c8fe39c4854cd2dfdc9700a94d09ec7f348c958b590",
    "healer": "658f8fe81ad995b004a962c47a600f1d23feae72a53ca67283edae2bf671bf88",
}
