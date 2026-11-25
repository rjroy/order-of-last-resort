"""Build the actual-scale offline sheet and silent storyboard from verified frames."""

from argparse import ArgumentParser
from dataclasses import dataclass
from functools import cache
import json
from pathlib import Path
import re
from subprocess import check_output, run

HERE = Path(__file__).resolve().parent
CAST = HERE.parents[6] / "games/company-of-unlikely-heroes/assets/cast"
MANIFEST = json.loads((CAST/"manifest.json").read_text())
SCALE = MANIFEST["display_scale"] * 315/(5*80+2*34)
COL, ROW = 65, 54
FOOT = (33, 42)
PAPER, PANEL, LINE, INK = "#f2ead8", "#ded1af", "#a99975", "#302a22"
FONT = check_output(["fc-match", "-f", "%{file}", "Liberation Sans"], text=True).strip()


@dataclass(frozen=True)
class Figure:
    role: str
    clip: str
    frame: int
    x: int
    y: int
    new: bool = False
    left: bool = False


def c(clip, frame):
    return Figure("necromancer", clip, frame, 1, 1, True)


def z(frame):
    return Figure("zombie", "play_dead", frame, 2, 1, True)


def s(frame, y):
    return Figure("skeleton", "recall_tuck", frame, 2, y, True)


READY = Figure("necromancer", "ready", 1, 1, 1)
SKEL = Figure("skeleton", "ready", 1, 2, 0)
ZOMB = Figure("zombie", "ready", 1, 2, 1)
KNIGHT = Figure("knight", "ready", 1, 2, 1)
GOBLIN = Figure("goblin", "defeat", 25, 2, 1, left=True)
RALLY_ZOMB = Figure("zombie", "ready", 1, 0, 1)


def stock(role, key, frame, x, y, left=False):
    return Figure(role, key, frame, x, y, left=left)


def bell(frame, x):
    return (stock("necromancer", "grave_bell", frame, 0, 1),
            stock("goblin", "ready", 1, x, 1, True))


def melody(frame):
    return (stock("necromancer", "melody", frame, 0, 1),
            stock("knight", "ready", 1, 2, 1))


def call(*args):
    run([str(a) for a in args], check=True)


def pixels(path):
    return tuple(map(int, check_output(["magick", "identify", "-format", "%w %h", path]).split()))


def art(frames, work):
    @cache
    def layer(role, clip, frame, new, left):
        if new:
            path = frames/f"{role}-{clip}-{frame:02d}.png"
            crop, anchor = None, (160,248)
            assert pixels(path) == (320,320)
            bound = check_output(
                ["magick",path,"-alpha","extract","-threshold","10%","-format","%@","info:"],
                text=True).strip()
            match = re.fullmatch(r"(\d+)x(\d+)\+(\d+)\+(\d+)", bound)
            assert match, (path, bound)
            w,h,x,y = map(int, match.groups())
            assert w and h and x > 1 and y > 1 and x+w < 319 and y+h < 319, (path, bound)
        else:
            take = MANIFEST["actors"][role]["clips"][clip]
            x,y,w,h = next(f["rect"] for f in take["frames"] if f["source_frame"] == frame)
            path, crop, anchor = CAST.parent.parent/take["path"][6:], f"{w}x{h}+{x}+{y}", take["anchor"]
            if left:
                anchor = (w-anchor[0],anchor[1])
        result = work/f"{role}-{clip}-{frame}-{int(left)}.png"
        args = [path]
        if crop:
            args += ["-crop", crop, "+repage"]
        if left:
            args += ["-flop"]
        call("magick", *args, "-resize", f"{100*SCALE}%", "+repage", result)
        return result, tuple(round(v*SCALE) for v in anchor)
    return layer


def text(message, x, y, size):
    return ["-stroke","none","-fill",INK,"-font",FONT,"-pointsize",size,
            "-annotate",f"+{x}+{y}",message]


def panel(layer, figures, x, y, mark=None):
    marks = [f"rectangle {x},{y} {x+3*COL},{y+2*ROW}"]
    marks += [f"line {x+i*COL},{y} {x+i*COL},{y+2*ROW}" for i in (1,2)]
    marks += [f"line {x},{y+ROW} {x+3*COL},{y+ROW}"]
    args = ["-fill",PANEL,"-stroke",LINE,"-strokewidth",1,"-draw",marks[0],
            "-fill","none","-draw"," ".join(marks[1:])]
    if mark:
        mx,my = mark
        a,b = x+mx*COL+2, y+my*ROW+2
        args += ["-stroke","#7b6642","-strokewidth",2,"-draw",f"rectangle {a},{b} {a+COL-4},{b+ROW-4}"]
    for f in sorted(figures, key=lambda f: f.y):
        image, (dx,dy) = layer(f.role, f.clip, f.frame, f.new, f.left)
        a,b = x+f.x*COL+FOOT[0]-dx, y+f.y*ROW+FOOT[1]-dy
        args += [image,"-geometry",f"{a:+d}{b:+d}","-compose","over","-composite"]
    return args


SHOTS = (
    ("Recall Skeleton",
     ("Stock: high summon", (stock("necromancer","summon_skeleton",16,1,1),), None),
     ("Reach: original cell", (c("recall",9),SKEL), (2,0)),
     ("Draw in: same skeleton", (c("recall",17),s(1,1)), (2,1)),
     ("Settle: no greeting", (READY,s(17,1)), (2,1))),
    ("Play Dead",
     ("Stock: kneeling Raise Dead", (stock("necromancer","raise_dead",34,1,1),), None),
     ("Hush: zombie lowers", (c("hush",17),z(10)), (2,1)),
     ("Rest: no impact", (c("hush",23),z(26)), (2,1)),
     ("Original goblin corpse", (READY,GOBLIN), (2,1))),
    ("Dinner Bell",
     ("Stock: Grave Bell", bell(12,2), None),
     ("Ready to ring", bell(8,2), None),
     ("One chime", bell(12,2), (2,1)),
     ("One open step closer", bell(19,1), (1,1))),
    ("Stay Close to That One",
     ("Stock: hostile point", (stock("necromancer","nominate",13,1,1),), None),
     ("Open hand: choose hero", (c("stay_close",10),KNIGHT,SKEL,RALLY_ZOMB), (2,1)),
     ("Indicate: summons wait", (c("stay_close",15),KNIGHT,SKEL,RALLY_ZOMB), (2,1)),
     ("Rally set, no extra turn", (READY,KNIGHT,SKEL,RALLY_ZOMB), (2,1))),
    ("Inspiring Melody, in tune",
     ("Stock: Crypter's Melody", melody(13), None),
     ("Crypter plays", melody(13), None),
     ("A phrase, not one chime", melody(21), None),
     ("Hero Inspired, no laughter", melody(40), (2,1))),
)


def make_sheet(layer, out):
    args = ["-size","864x842",f"xc:{PAPER}"]
    args += text("FRIENDLY CRYPTER   /   TRY THIS PERFORMANCES",20,29,21)
    args += text("Stock controls and candidates at 65 × 54 px per tile. View at 100%. Offline staging, not game footage.",
                 20,51,13)
    for i,(title,*beats) in enumerate(SHOTS):
        top = 67+152*i
        args += text(title,20,top+13,15)
        for j,(caption,figures,mark) in enumerate(beats):
            x = 20+210*j
            args += panel(layer,figures,x,top+20,mark)
            args += text(caption,x,top+145,12)
    call("magick", *args, "-strip", out)
    assert pixels(out) == (864,842)


def motion():
    """Rows of held poses, independent from future host cue timing."""
    for frame in (1,5,9,13,17,21):
        stage = (SKEL,) if frame < 17 else (s(1 if frame == 17 else 9,1),)
        yield 0, .17, (c("recall",frame),*stage), (2,0 if frame < 17 else 1)
    yield 0, .65, (READY,s(17,1)), (2,1)
    for owner, zombie in ((6,1),(11,5),(17,10),(23,13),(23,15),(29,18),(29,21),(35,26)):
        yield 1, .18, (c("hush",owner),z(zombie)), (2,1)
    yield 1, .7, (READY,GOBLIN), (2,1)
    for frame in (1,4,8,12,15,19,23,25):
        yield 2, .15 if frame != 25 else .6, bell(frame,2 if frame <= 12 else 1), (2 if frame <= 12 else 1,1)
    for frame in (6,10,15,20,26,32):
        yield 3, .20 if frame != 32 else .6, (c("stay_close",frame),KNIGHT,SKEL,RALLY_ZOMB), (2,1)
    for stock_frame in MANIFEST["actors"]["necromancer"]["clips"]["melody"]["frames"]:
        frame, duration = stock_frame["source_frame"], stock_frame["duration_ms"]/1000
        yield 4, duration+(.5 if frame == 40 else 0), melody(frame), (2,1) if frame == 40 else None


def make_film(layer, work, out):
    lines = ["ffconcat version 1.0"]
    for i,(row,seconds,figures,mark) in enumerate(motion()):
        path = work/f"beat-{i:02d}.png"
        args = ["-size","480x208",f"xc:{PAPER}"]
        args += text(SHOTS[row][0],22,30,19)
        args += text("Actual-scale motion study • silent • no runtime changes",22,190,13)
        args += panel(layer,figures,142,51,mark)
        call("magick",*args,"-strip",path)
        lines += [f"file '{path.name}'",f"duration {seconds:.4f}"]
    lines.append(f"file '{path.name}'")
    concat = work/"beats.ffconcat"
    concat.write_text("\n".join(lines)+"\n")
    call("ffmpeg","-v","error","-y","-threads","2","-f","concat","-safe","0","-i",concat,
         "-r","24","-pix_fmt","yuv420p","-c:v","libx264","-threads","2","-movflags","+faststart",out)
    call("ffmpeg","-v","error","-threads","2","-i",out,"-f","null","-")


if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    scratch = out/"composite"
    scratch.mkdir(exist_ok=True)
    layer = art(out/"frames", scratch)
    make_sheet(layer, out/"tactical-sheet.png")
    make_film(layer, scratch, out/"tactical-motion.mp4")
