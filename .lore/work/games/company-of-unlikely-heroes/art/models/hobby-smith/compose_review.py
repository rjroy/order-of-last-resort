"""Assemble the local Smith review sheet and an optional silent motion comparison."""

import argparse
import subprocess
from pathlib import Path


PAPER = "#eee2cc"
DARK = "#312721"
INK = "#614d3d"
RUST = "#823f31"
PANELS = (
    ("neutral-front", "Neutral T", "True bind pose, kit hidden"),
    ("ready", "Ready", "Weight on both boots"),
    ("try-this", "Try This", "Presents a single fitting"),
    ("hammer-time", "Hammer Time", "Compact downward strike"),
    ("pursue-step", "Pursue Step", "Transfers weight and follows"),
)


def font(family):
    path = subprocess.check_output(["fc-match","-f","%{file}",family],text=True)
    assert Path(path).is_file(), (family,path)
    return path


class Sheet:
    def __init__(self, width, height, fonts):
        self.args = ["magick","-size",f"{width}x{height}",f"xc:{PAPER}"]
        self.fonts = fonts

    def text(self, x, y, label, *, size=19, color=INK, display=False):
        self.args += ["-font",self.fonts[1 if display else 0],"-pointsize",str(size),"-fill",color,
                      "-stroke","none","-draw",f"text {x},{y} '{label}'"]

    def rule(self, x1, y1, x2, y2, color="#b4a08a"):
        self.args += ["-fill","none","-stroke",color,"-strokewidth","1","-draw",f"line {x1},{y1} {x2},{y2}"]

    def image(self, path, size, x, y):
        assert path.is_file() and path.stat().st_size > 4096, path
        self.args += ["(",str(path),"-resize",f"{size}x{size}!",")","-geometry",f"+{x}+{y}","-composite"]

    def write(self, path):
        assert not path.exists(), path
        subprocess.run(self.args + ["-strip",str(path)],check=True)


def pose_sheet(src, out, fonts):
    sheet = Sheet(1824,753,fonts)
    sheet.text(48,43,"BARNABY’S ORDER OF LAST RESORT",size=16,color=RUST)
    sheet.text(46,95,"Hobby Smith",size=53,color=DARK,display=True)
    sheet.text(1280,63,"MODEL CANDIDATE   /   BLENDER PERFORMANCE STUDY",size=15)
    sheet.rule(46,114,1778,114)
    for i, (key,title,description) in enumerate(PANELS):
        start = 46 + i*350
        sheet.image(src/f"{key}.png",338,start-8,129)
        sheet.text(start+8,479,f"0{i+1}",size=16,color=RUST)
        sheet.text(start+42,480,title,size=30,color=DARK,display=True)
        sheet.text(start+9,512,description)
        if i < len(PANELS)-1:
            sheet.rule(start+329,159,start+329,510,"#d3c2a8")

    sheet.rule(46,550,1778,550)
    sheet.text(55,596,"TACTICAL SCALE CHECK",size=19,color=RUST)
    sheet.text(55,627,"65 × 54 px tile footprints")
    sheet.text(55,657,"Fixed scale, no game effects")
    samples = (("ready","Ready"),("try-this","Try This"),("hammer-windup","Wind-up"),
               ("hammer-time","Strike"),("pursue-step","Pursue"))
    # The cast manifest gives 104.918 px/m at source and 0.375 display scale.
    # The 2.47 m view at the five-row minimum board height is ~65 px wide.
    for i, (key,title) in enumerate(samples):
        x = 443 + i*258
        sheet.args += ["-fill","#dfd0b8","-stroke","#b19c84","-strokewidth","1",
                       "-draw",f"rectangle {x},610 {x+64},663"]
        sheet.image(src/f"{key}.png",65,x,604)
        sheet.text(x,695,title,size=17,color=INK)
    sheet.write(out)


def motion_comparison(frames, out, fonts):
    composed = frames/"paired"
    composed.mkdir(exist_ok=True)
    for i in range(18):
        sheet = Sheet(552,328,fonts)
        sheet.rule(275,43,275,309)
        sheet.text(18,33,"Try This",size=23,color=DARK,display=True)
        sheet.text(294,33,"Hammer Time",size=23,color=DARK,display=True)
        for x, directory in ((0,"fitting"),(276,"hammer")):
            sheet.image(frames/directory/f"{i:03d}.png",276,x,43)
        sheet.write(composed/f"{i:03d}.png")
    assert not out.exists(), out
    subprocess.run(["ffmpeg","-hide_banner","-loglevel","error","-n","-framerate","12","-i",
                    str(composed/"%03d.png"),"-c:v","libwebp_anim","-loop","0","-quality","86",
                    "-vf","format=yuv420p",str(out)], check=True)


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("renders",type=Path)
    cli.add_argument("output",type=Path)
    cli.add_argument("--motion",type=Path,help="Optional directory of Blender motion frames")
    args = cli.parse_args()
    fonts = font("sans-serif"),font("serif")
    pose_sheet(args.renders,args.output,fonts)
    if args.motion:
        motion_comparison(args.motion,args.output.with_name("try-this-and-hammer-time.webp"),fonts)


if __name__ == "__main__":
    main()
