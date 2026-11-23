"""Build labeled model-review proofs from each sibling's reopened Blender renders."""
import concurrent.futures
import json
import subprocess
import sys
from pathlib import Path

GRAY = "#594943"
PAPER = "#f0e5d1"
RULE = "#c4b098"
RED = "#793d2c"
INK = "#29231f"
SERIF = "Noto-Serif-Display-Bold"
SANS = "Liberation-Sans"
SMALL_SCALE = .253
ROLES = {
    "damage": ("Fierce Bandit", "Axe, torn mantle, forward triangle", "Harder Strike", "Longer, lower axe follow-through"),
    "guard": ("Guard Bandit", "Hood, sheepskin collar, round buckler", "Brace", "Buckler closes; both feet stay put"),
    "swift": ("Swift Bandit", "Flying braid, split sash, narrow footwork", "Quick Step", "Airy passing stride, knife kept low"),
}
POSES = (("rest", "01  T-rest"), ("ready", "02  Ready"), ("move", "03  Move"), ("melee", "04  Melee"),
         ("rear", "05  Rear view"), ("feature", "06  {feature}"), ("hit", "07  Hit"), ("defeat", "08  Defeat"))


def run(*args):
    subprocess.run([str(x) for x in args], check=True, timeout=120,
                   stdin=subprocess.DEVNULL)


def magick(*args):
    run("magick","-limit","thread","1",*args)


def text(x,y,message,*,font=SANS,size=16,fill=GRAY):
    return ["-font",font,"-pointsize",str(size),"-fill",fill,"-annotate",f"+{x}+{y}",message]


def rectangle(x,y,w,h,fill,stroke="none"):
    return ["-fill",fill,"-stroke",stroke,"-draw",f"rectangle {x},{y} {x+w},{y+h}","-stroke","none"]


def place(file,x,y,resize=None,extra=()):
    return ["(",str(file),*(["-resize",resize] if resize else []),*extra,")",
            "-geometry",f"+{x}+{y}","-compose","Over","-composite"]


def outline(src,out):
    magick(src,"-alpha","extract","-morphology","Dilate","Disk:2","-write","mpr:mask","+delete",
           "-size","320x320","xc:#352b28","mpr:mask","-compose","CopyOpacity","-composite",
           src,"-compose","Over","-composite","-strip",f"PNG32:{out}")


def pose_sheet(work,key):
    title,subtitle,feature,caption=ROLES[key]
    folder=work/key
    data=["-size","1180x795",f"xc:{PAPER}",*rectangle(0,0,1180,9,RED),
          *text(35,41,"BARNABY’S ORDER OF LAST RESORT  /  MODEL REVIEW",size=15,fill=RED),
          *text(34,93,title,font=SERIF,size=44,fill=INK),*text(38,122,subtitle,size=18),
          *text(776,89,"06 / LAST ONE STANDING",size=16,fill=RED),
          *text(776,114,"Fixed cast angle  ·  Neutral studio light",size=14)]
    for i,(slug,label) in enumerate(POSES):
        x=34+(i%4)*282
        y=148+(i//4)*308
        palette=("#e2d3bd","#eadbc5") if i!=5 else ("#dcc2ab","#e5ccb1")
        data.extend(rectangle(x,y,266,290,palette[0],RULE))
        data.extend(rectangle(x+1,y+250,264,39,palette[1]))
        data.extend(place(folder/f"{slug}.png",x+2,y-1,"262x262"))
        data.extend(text(x+14,y+276,label.format(feature=feature),font=SERIF,size=17,fill=INK))
    data+=text(37,778,caption+"  ·  Rendered from the editable candidate  ·  No gameplay effects",size=15)
    magick(*data,"-strip",folder/"pose-sheet.png")


def tactical(work):
    data=["-size","675x349",f"xc:{PAPER}",*rectangle(0,0,675,7,RED),
          *text(21,28,"LAST ONE STANDING  /  MODEL REVIEW",size=13,fill=RED),
          *text(20,56,"Three silhouettes, one camera",font=SERIF,size=26,fill=INK),
          *text(20,76,"Fixed registration at 26.55 px/m. Diagram, not gameplay.",size=14)]
    stage=work/"tactical"
    stage.mkdir(exist_ok=True)
    for i,(key,(title,_,feature,_)) in enumerate(ROLES.items()):
        cellmid=206+i*171
        data.extend(text(cellmid-39,108,title,font=SERIF,size=16,fill=INK))
        for row,slug in enumerate(("ready","feature","ready")):
            y=127+row*73+(7 if row==2 else 0)
            cellx=cellmid-32
            shadow=cellmid-40
            data.extend(rectangle(cellx,y,65,53,"#deceb3",RULE))
            data.extend(["-fill","#bcab91","-draw",f"ellipse {cellmid},{y+35} 22,4 0,360"])
            outlined=stage/f"{key}-{slug}.png"
            if row!=2:
                outline(work/key/f"tactical-{slug}.png",outlined)
            extra=() if row!=2 else ("-fill","#413b39","-colorize","100")
            data.extend(place(outlined,shadow,y-28,f"{SMALL_SCALE*100}%",extra))
            if row==1:
                data.extend(text(cellmid-37,y+60,feature,size=11,fill=RED))
    data.extend(text(20,155,"Ready",font=SERIF,size=17))
    data.extend(text(20,227,"Passive take",font=SERIF,size=17))
    data.extend(text(20,308,"No color / ready",font=SERIF,size=16))
    magick(*data,"-strip",work/"tactical-siblings.png")


def motion(work,key,workers):
    title,subtitle,feature,_=ROLES[key]
    clip=work/key
    strips=json.loads((clip/"motion-index.json").read_text())
    layout=clip/"encoded"
    layout.mkdir(exist_ok=True)
    backdrop=layout/"paper.png"
    magick("-size","570x410",f"xc:{PAPER}",*rectangle(0,0,570,7,RED),
           *text(28,36,"LAST ONE STANDING  /  BLENDER MOTION",size=14,fill=RED),
           *text(27,74,title,font=SERIF,size=32,fill=INK),
           *text(30,94,subtitle,size=14),
           *rectangle(28,105,514,270,"#deceb6",RULE),
           "-fill","#bda98e","-draw","ellipse 286,329 55,7 0,360",
           *text(29,396,"24 fps source sampled at 12 fps  ·  Stationary board anchor",size=13),
           backdrop)

    def frame(i,label):
        png=clip/f"motion-{i:03d}.png"
        outlined=layout/f"outline-{i:03d}.png"
        outline(png,outlined)
        magick(backdrop,*place(outlined,99,41,"372x372"),
               *rectangle(42,342,168,24,"#ead9c1"),
               *text(49,359,label,font=SERIF,size=15,fill=INK),
               "-alpha","remove","-strip",layout/f"frame-{i:03d}.png")

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        futures=[pool.submit(frame,i,row["action"])
                 for row in strips for i in range(row["first_display_frame"],row["last_display_frame"]+1)]
        for task in futures:
            task.result()
    run("ffmpeg","-hide_banner","-loglevel","error","-y","-framerate","12",
        "-start_number","0","-i",layout/"frame-%03d.png","-threads","2","-c:v","libx264",
        "-crf","18","-pix_fmt","yuv420p","-movflags","+faststart",clip/"motion-preview.mp4")
    run("ffmpeg","-hide_banner","-loglevel","error","-xerror","-threads","2","-i",
        clip/"motion-preview.mp4","-f","null","-")


def main():
    work=Path(sys.argv[1]).resolve()
    mode=sys.argv[2] if len(sys.argv)>2 else "all"
    if mode in ("stills","all"):
        for key in ROLES:
            pose_sheet(work,key)
        tactical(work)
    if mode in ("motion","all"):
        for key in ROLES:
            motion(work,key,4)


if __name__=="__main__":
    main()
