"""Compose model review evidence only. No game files are written."""

import json
from pathlib import Path
import subprocess
import sys


REPO = next(p for p in Path(__file__).resolve().parents
            if (p/"games/company-of-unlikely-heroes/assets/boards/manifest.json").is_file())
GAME = REPO/"games/company-of-unlikely-heroes"
PAPER, LIGHT, INK, RULE, ACCENT = "#ecdfc8", "#f7eddd", "#362820", "#bea78b", "#763a2d"
SCALE = 315/468
ATLAS_DISPLAY = .375*SCALE
BOARD_W, BOARD_H = round(734*SCALE),315
SERIF = subprocess.check_output(["fc-match","--format=%{file}","serif:style=Bold"],text=True)
SANS = subprocess.check_output(["fc-match","--format=%{file}","sans-serif"],text=True)


def magick(*args):
    subprocess.run(["magick",*map(str,args)],check=True)


def label(x,y,text,size,*,title=False,color=INK):
    return ["-fill",color,"-font",SERIF if title else SANS,"-pointsize",str(size),
            "-annotate",f"+{x}+{y}",text]


def paste(img,x,y,w=None):
    return ["(",str(img),*(["-resize",str(w)+"x"] if w else []),")",
            "-geometry",f"{x:+d}{y:+d}","-compose","Over","-composite"]


def rectangle(x,y,r,b,color):
    return ["-fill",color,"-stroke","none","-draw",f"rectangle {x},{y} {r},{b}"]


def pose_sheet(out, role, name, subtitle, posts, note):
    width, height = 1264, 700
    cmd=["-size",f"{width}x{height}",f"xc:{PAPER}"]
    cmd+= label(22,28,"BARNABY’S ORDER OF LAST RESORT  /  LAST WAGON  /  SOURCE REVIEW",13,color=ACCENT)
    cmd+= label(22,68,name,38,title=True)+label(23,94,subtitle,15)
    for i,(slug,title,detail) in enumerate(posts):
        x,y=22+(i%4)*308,117+(i//4)*264
        cmd+=rectangle(x,y,x+291,y+243,LIGHT)
        cmd+=paste(out/role/"poses"/f"{slug}.png",x+32,y-17,231)
        cmd+=label(x+12,y+217,title,19,title=True)+label(x+13,y+236,detail,12)
    cmd+=label(23,682,note,13,color=ACCENT)
    magick(*cmd,out/f"{role}-pose-sheet.png")


def engraved(src, dest):
    # The production baker places two capture pixels of ink beneath RGBA edges.
    magick(src,"-alpha","extract","-morphology","Dilate","Disk:2","-write","mpr:mask","+delete",
           "-size","320x320","xc:#352b28","mpr:mask","-compose","CopyOpacity","-composite",
           src,"-compose","Over","-composite","-strip",f"PNG32:{dest}")


def board_ground(base):
    board=json.loads((GAME/"assets/boards/manifest.json").read_text())["boards"]["frontier_wagon_board"]
    reg=board["registration"]
    x,y=reg["a1_center_px"]
    dx,dy=reg["column_px"]
    rx,ry=reg["row_px"]
    points=[((x,y),(79,74)),((x+dx,y+dy),(175,74)),((x+rx,y+ry),(79,154))]
    control=" ".join(f"{a},{b} {c*SCALE:.5f},{d*SCALE:.5f}" for ((a,b),(c,d)) in points)
    cmd=[GAME/"assets/boards"/board["file"],"-virtual-pixel","edge","-define",
         f"distort:viewport={BOARD_W}x{BOARD_H}+0+0","-distort","Affine",control,"+repage"]
    for i in range(8):
        x=round((31+96*i)*SCALE)
        cmd+=["-stroke","#40332266","-strokewidth","1","-draw",
              f"line {x},{round(34*SCALE)} {x},{round(434*SCALE)}"]
    for i in range(6):
        y=round((34+80*i)*SCALE)
        cmd+=["-stroke","#40332266","-strokewidth","1","-draw",
              f"line {round(31*SCALE)},{y} {round(703*SCALE)},{y}"]
    magick(*cmd,base)


def foot(cell):
    x,y=cell
    return ((31+96*x+49)*SCALE,(34+80*y+62)*SCALE)


def hero_sprite(role,work):
    manifest=json.loads((GAME/"assets/cast/manifest.json").read_text())
    clip=manifest["actors"][role]["clips"]["ready"]
    x,y,w,h=clip["frames"][0]["rect"]
    p=work/f"shipped-{role}.png"
    magick(GAME/"assets/cast"/f"{role}.png","-crop",f"{w}x{h}+{x}+{y}","+repage",p)
    return p,w,h,clip["anchor"]


def tactical_frame(base, dest, sprites, highlight=None):
    cmd=[base]
    if highlight:
        x,y=highlight
        x,y=(31+x*96)*SCALE,(34+y*80)*SCALE
        cmd+=["-fill","#583b3028","-stroke","#8d463acc","-strokewidth","1.25","-draw",
              f"rectangle {x+1},{y+1} {x+96*SCALE-1},{y+80*SCALE-1}"]
    for (cx,cy),(path,w,h,anchor),flipped in sorted(sprites,key=lambda item:item[0][1]):
        x,y=foot((cx,cy))
        a,b=anchor
        if flipped:
            a=w-a
        cmd+=["-fill","#22282452","-stroke","none","-draw",f"ellipse {x},{y} 13,3 0,360",
              "(",str(path),*(["-flop"] if flipped else []),"-resize",f"{ATLAS_DISPLAY*100}%",")",
              "-geometry",f"+{round(x-a*ATLAS_DISPLAY)}+{round(y-b*ATLAS_DISPLAY)}",
              "-compose","Over","-composite"]
    magick(*cmd,dest)


def grouping(out):
    work=out/"staging"
    work.mkdir(exist_ok=True)
    base=work/"board.png"
    board_ground(base)
    catalog=json.loads((GAME/"content/missions/last_wagon.json").read_text())
    encounter=catalog["encounters"]["frontier_wagon_road"]
    heroes=[(tuple(cell),hero_sprite(hero,work),False)
            for cell,hero in zip(encounter["party_slots"],catalog["missions"]["last_wagon"]["default_party"])]
    roles={}
    for role,frames in {"wagon": ("ready-01","advance-18","stall-07","destroyed-42"),
                        "raider": ("ready-01","intercept-14","wagon-strike-16")}.items():
        for frame in frames:
            png=work/f"{role}-{frame}.png"
            engraved(out/role/"motion"/f"{frame}.png",png)
            roles[role,frame]=(png,320,320,(160,248))
    r=lambda f: roles["raider",f]
    w=lambda f: roles["wagon",f]
    picks=[
        ("Stock opening","Two raiders; the three default party slots.",[
            ((1,2),w("ready-01"),False),((4,0),r("ready-01"),True),((4,4),r("ready-01"),True)
        ],None),
        ("Make a gap","Advance drawing: open adjacent cells.",[
            ((2.52,2),w("advance-18"),False),((4,1),r("intercept-14"),True),((4,3),r("ready-01"),True)
        ],(3,2)),
        ("The road is blocked","Stall drawing: foe adjacent, wheels locked.",[
            ((3,2),w("stall-07"),False),((4,2),r("intercept-14"),True),((4,3),r("ready-01"),True)
        ],(3,2)),
        ("Lose the axle","Held wreck; no explosion and no invented driver.",[
            ((3,2),w("destroyed-42"),False),((4,2),r("wagon-strike-16"),True),((4,3),r("ready-01"),True)
        ],(3,2)),
    ]
    cmd=["-size","1040x840",f"xc:{PAPER}"]
    cmd+=label(16,32,"The Last Wagon at tactical size",34,title=True)
    cmd+=label(17,57,"Model-only composite  /  Stock board registration  /  65 × 54 px cells  /  Not gameplay capture",13)
    for i,(title,sub,sprites,highlight) in enumerate(picks):
        x,y=16+i%2*512,76+i//2*377
        frame=work/f"tactical-{i}.png"
        tactical_frame(base,frame,[*heroes,*sprites],highlight)
        cmd+=paste(frame,x,y)+label(x+2,y+341,title,22,title=True)+label(x+3,y+360,sub,13)
    magick(*cmd,out/"last-wagon-tactical-proof.png")


def motion(out,role,title,seq):
    width,height=592,434
    video=subprocess.Popen(["ffmpeg","-v","error","-y","-f","rawvideo","-pixel_format","rgb24",
                            "-video_size",f"{width}x{height}","-framerate","24","-i","-",
                            "-c:v","libx264","-threads","2","-crf","17","-pix_fmt","yuv420p",
                            "-movflags","+faststart",str(out/f"{role}-motion.mp4")],
                           stdin=subprocess.PIPE)
    try:
        for action,frames,stop,hold in seq:
            slug=action.lower().replace(" ","-")
            for i,f in enumerate(frames):
                image=out/role/"motion"/f"{slug}-{f:02}.png"
                cmd=["magick","-size",f"{width}x{height}",f"xc:{PAPER}"]
                cmd+=label(18,32,title,29,title=True)
                cmd+=label(19,53,"EDITABLE BLENDER CANDIDATE  /  FIXED CAST CAMERA",10,color=ACCENT)
                cmd+=rectangle(16,65,575,380,LIGHT)
                cmd+=paste(image,16,39,410)
                cmd+=rectangle(444,189,558,305,PAPER)
                cmd+=paste(image,460,196,80)
                cmd+=label(450,292,"TACTICAL SIZE",11,color=ACCENT)
                cmd+=label(19,409,action,20,title=True)+label(428,408,f"SOURCE F{f:02} / 24 FPS",11)
                rgb=subprocess.check_output(cmd+["-depth","8","rgb:-"])
                count=(frames[i+1]-f) if i+1<len(frames) else stop-f+hold
                assert count>0
                video.stdin.write(rgb*count)
    finally:
        video.stdin.close()
        if video.wait() != 0:
            raise RuntimeError(f"FFmpeg failed: {role}")


if __name__=="__main__":
    out=Path(sys.argv[1]).resolve()
    mode=sys.argv[2] if len(sys.argv)>2 else "all"
    if mode in ("all","poses"):
        pose_sheet(out,"raider","Wagon Raider",
                   "Bandana • bare shoulders • breaker gauntlets • short wedge",
                   [("bind","Neutral bind","T-pose; weapon on its own socket"),
                    ("ready","Ready","Low split stance; both hands on the stave"),
                    ("plant","Intercept","Front boot cuts across the wheel line"),
                    ("coil","Load the swing","The wedge rotates back below the shoulder"),
                    ("strike","Wagon strike","The body and short stave reach wheel height"),
                    ("defeat","Defeat","Folds behind the handle; no invented move"),
                    ("profile","Profile","Clearance between face, cuff and tool"),
                    ("back","Rear","Tied linen and bare shoulders")],
                   "Actual saved geometry  /  Blender 5.2.2  /  Consistent cast ink and orthographic scale")
        pose_sheet(out,"wagon","Supply Wagon",
                   "No driver • four working wheels • field chest, water cask and grain sacks",
                   [("ready","Ready / intact","The named cargo stays secured in the bed"),
                    ("roll","Advance","All four wheels turn and the cargo takes a bump"),
                    ("stall","Stall","Wheels fixed; body and cargo pitch forward"),
                    ("break","Breakaway","The near front wheel twists out"),
                    ("down","Destroyed / held","Wagon leans onto a splayed wheel and jagged panel"),
                    ("profile","Front quarter","Draw pole, tow eye and wheel spacing"),
                    ("back","Rear quarter","Rear load and the farther axle"),
                    ("break-back","Wreck / reverse","Shows the undamaged farther running gear")],
                   "Actual saved geometry  /  Blender 5.2.2  /  No gameplay, terrain or VFX in these model poses")
    if mode in ("all","group"):
        grouping(out)
    if mode in ("all","raider"):
        motion(out,"raider","Wagon Raider",[
            ("Ready",[1,7,13,19,25,31],34,0),
            ("Intercept",[1,4,7,10,13,14,16,19,22,25,28],30,3),
            ("Wagon Strike",[1,4,7,10,12,13,14,15,16,17,19,20,22,25,28,31],33,6),
            ("Hit",[1,4,7,10,14,18,21],22,0),
            ("Defeat",[1,4,7,10,13,16,19,22,25,28,31,37],38,12)])
    if mode in ("all","wagon"):
        motion(out,"wagon","Supply Wagon",[
            ("Advance",[1,4,7,10,13,16,18,19,22,25,28,31,33],34,3),
            ("Stall",[1,3,5,7,10,13,16,19,22,25,27],28,7),
            ("Destroyed",[1,4,5,7,9,11,13,15,17,19,22,25,28,31,34,37,40,42],43,16)])
