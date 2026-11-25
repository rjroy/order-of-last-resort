"""Compare candidate frames to the shipped atlas and make a timed review film."""

from argparse import ArgumentParser
import json
from pathlib import Path
from subprocess import check_output, run

from choreography import CUES
from sound_candidates import GAME, RATE, generate, write

CAST = GAME / "assets/cast"
STOCK = {"it_was_me": ("misdirect",14), "clear_jump": ("swap",10),
         "cut_the_wire": ("tripwire",13), "bitter_medicine": ("potion",15)}
HERO_FRAME = {"it_was_me": (10,19), "clear_jump": (12,17),
              "cut_the_wire": (13,15), "bitter_medicine": (10,13)}
FONT = check_output(["fc-match", "-f", "%{file}", "Liberation Sans"], text=True).strip()
PAPER = "#e9dec4"


def command(*args):
    run(list(map(str,args)),check=True)


def magick(*args):
    command("magick",*args)


def get_stock(clip_key, frame):
    manifest = json.loads((CAST/"manifest.json").read_text())
    clip = manifest["actors"]["rogue"]["clips"][clip_key]
    assert manifest["display_scale"] == .375
    assert clip["path"] == "res://assets/cast/rogue.png"
    x,y,w,h = next(f["rect"] for f in clip["frames"] if f["source_frame"] == frame)
    ox,oy = clip["anchor"]
    return (CAST/"rogue.png",f"{w}x{h}+{x}+{y}",(ox,oy))


def draw(w, h, notes, layers, out, ink=None):
    """Each layer is (image, crop, ground_anchor, display_scale, canvas_ground)."""
    args = ["-size",f"{w}x{h}",f"xc:{PAPER}"]
    if ink:
        args += ["-stroke","#b8a787","-fill","none","-strokewidth","1","-draw",ink]
    for path,crop,anchor,scale,ground in layers:
        x,y = (round(v-k*scale) for v,k in zip(ground,anchor))
        args += ["(",path]
        if crop:
            args += ["-crop",crop,"+repage"]
        args += ["-resize",f"{scale*100}%","+repage",")","-geometry",f"{x:+d}{y:+d}",
                 "-compose","over","-composite"]
    for message,x,y,size in notes:
        args += ["-stroke","none","-fill","#302622","-font",FONT,"-pointsize",size,
                 "-annotate",f"+{x}+{y}",message]
    magick(*args,"-strip",out)


def png(frames, key, frame):
    return frames / ("ready.png" if frame in (1,CUES[key]["end"]) else f"{key}-{frame:02d}.png")


def make_sheet(frames, meta, output):
    layers, notes = [], [
        ("DAFT DODGER   /   TRY THIS",22,28,20),
        ("Stock take         /         New take: two moments         /         Same pair at 65 x 54 tile scale",22,55,13),
    ]
    anchor = meta["origin_px"]
    markers = {key: {v:k for k,v in cue["markers"].items()} for key,cue in CUES.items()}
    for i,(key,cue) in enumerate(CUES.items()):
        top = 79 + 171*i
        y = top+132
        notes.append((cue["title"],22,top,15))
        clip,frame = STOCK[key]
        layers.append((*get_stock(clip,frame),.54,(102,y)))
        notes.append((f"{clip}  F{frame}",54,y+17,12))
        for j, f in enumerate(HERO_FRAME[key]):
            point = 238+142*j
            layers.append((png(frames,key,f),None,anchor,.54,(point,y)))
            layers.append((png(frames,key,f),None,anchor,.254,(526+84*j,y-15)))
            notes.append((f"{markers[key][f]}  F{f}",point-40,y+17,12))
    draw(672,770,notes,layers,output/"tactical-comparison.png")


def make_film(frames, meta, output, sounds):
    scratch = output/"film-frames"
    scratch.mkdir(exist_ok=True)
    lead, tail, index = 12, 10, 0
    mixed = [0.] * round(sum(lead+c["end"]+tail for c in CUES.values())*RATE/24)
    for i,(key,cue) in enumerate(CUES.items()):
        for fx,f in cue["effects"].items():
            start = round((index+lead+f-1)*RATE/24)
            mixed[start:start+len(sounds[fx])] = sounds[fx]
        labels = {v:k for k,v in cue["markers"].items()}
        for f in range(1-lead,cue["end"]+tail+1):
            sample = max((v for v in cue["samples"] if v <= max(1,f)), default=1)
            label = labels.get(max((v for v in labels if v <= f),default=0), "")
            x,y = 254,142
            ink = "line 137,132 423,132"
            if key == "clear_jump":
                begin,end = cue["travel"]
                t = min(1,max(0,(f-begin)/(end-begin)))
                # Single-actor example. Figurine height comes from the native take,
                # while the stage ground anchor travels monotonically to the landing.
                x,y = 146+148*t,123+24*t
                ink = "polyline 128,117 153,116 168,122 146,129 128,117 " \
                      "polyline 273,143 295,140 316,146 293,154 273,143 " \
                      "polyline 337,149 356,146 378,152 356,160 337,149"
            notes = [(f"{i+1}   {cue['title']}",26,28,21),(label,26,54,13),
                     ("ACTUAL DODGER   /   CANDIDATE",26,179,11)]
            if key == "clear_jump":
                notes.append(("Foe tile stays put",335,125,11))
            draw(464,196,notes,[(png(frames,key,sample),None,meta["origin_px"],.375,(x,y))],
                 scratch/f"f-{index:04d}.png",ink)
            index += 1
    assert round(index * RATE / 24) == len(mixed)
    write(output/"synchronized.wav",mixed)
    command("ffmpeg","-v","error","-y","-framerate","24","-i",scratch/"f-%04d.png","-i",
            output/"synchronized.wav","-frames:v",index,"-c:v","libx264","-crf","17",
            "-pix_fmt","yuv420p","-c:a","aac","-movflags","+faststart",output/"tactical-motion.mp4")


def main():
    p = ArgumentParser()
    p.add_argument("frames",type=Path)
    p.add_argument("output",type=Path)
    p.add_argument("--sheet-only",action="store_true")
    args = p.parse_args()
    assert args.frames.resolve() != args.output.resolve()
    args.output.mkdir(parents=True,exist_ok=True)
    meta = json.loads((args.frames/"cues.json").read_text())
    assert meta["fp_s"] == 24 and meta["display_scale"] == .375
    make_sheet(args.frames,meta,args.output)
    if not args.sheet_only:
        make_film(args.frames,meta,args.output,generate(args.output/"sound"))


if __name__ == "__main__":
    main()
