"""clip: (source action suffix, sampled frames, exclusive stop frame, loop).
Times are absolute 24-fps source offsets; held poses need only one drawing.
"""

GUARD = "Wary, plant, cover, settle"
TAKES = {
    "knight": {
        "ready": (GUARD, [8], 32, True),
        "guard": (GUARD, [8, 14, 20, 25, 31, 35, 39, 44, 51, 65], 78, False),
        "shield_away": (GUARD, [8], 32, True),
    },
    "healer": {
        "ready": ("Ally Heal", [1], 25, True),
        "ally_heal": ("Ally Heal", [1, 4, 7, 10, 13, 17, 20, 23, 26, 28], 33, False),
        "self_heal": ("Self Heal", [1, 5, 9, 12, 17, 21, 25, 28], 33, False),
        "bonk": ("Adjacent Bonk", [1, 5, 10, 13, 15, 18, 23, 29], 33, False),
    },
    "wizard": {
        "ready": ("Ready", [1], 13, True),
        "blast": ("Blast", [1, 4, 7, 11, 14, 17, 21, 24, 29, 34], 41, False),
        "pull": ("Pull", [1, 4, 8, 13, 16, 19, 21, 24, 28, 33], 41, False),
    },
    "rogue": {
        "ready": ("Ready / Retreat", [1], 25, True),
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
        "ready": ("Ready", [1], 25, True),
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
PILOT = {
    "knight": "2f1bd3cb93992886383e8c8fe39c4854cd2dfdc9700a94d09ec7f348c958b590",
    "healer": "658f8fe81ad995b004a962c47a600f1d23feae72a53ca67283edae2bf671bf88",
}
