"""Read-only Last Wagon candidate review. Uses the actual cast projection and ink."""

from pathlib import Path
import sys
import bpy
from mathutils import Euler, Vector
from bpy_extras.object_utils import world_to_camera_view


REPO = next(p for p in Path(__file__).resolve().parents
            if (p/"games/company-of-unlikely-heroes/tools/cast/bake_actor.py").is_file())
sys.path.insert(0,str(REPO/"games/company-of-unlikely-heroes/tools/cast"))
from bake_actor import ANCHOR, SIZE, setup

RAIDER = {
    "bind": ("Neutral T", 1, None),
    "ready": ("Ready", 1, None),
    "lift": ("Intercept", 10, None),
    "plant": ("Intercept", 14, None),
    "coil": ("Wagon Strike", 10, None),
    "strike": ("Wagon Strike", 16, None),
    "follow": ("Wagon Strike", 20, None),
    "hit": ("Hit",4,None),
    "defeat": ("Defeat",29,None),
    "profile": ("Ready", 1, -1.54),
    "back": ("Ready", 1, 2.65),
}
WAGON = {
    "bind": ("Neutral", 1, None),
    "ready": ("Ready", 1, None),
    "roll": ("Advance", 18, None),
    "stall": ("Stall", 7, None),
    "break": ("Destroyed", 13, None),
    "down": ("Destroyed", 42, None),
    "profile": ("Ready", 1, -1.27),
    "back": ("Ready", 1, 2.88),
    "break-back": ("Destroyed", 42, 2.88),
}
MOTION = {
    "WagonRaider": {
        "Ready": (1,7,13,19,25,31),
        "Intercept": (1,4,7,10,13,14,16,19,22,25,28),
        "Wagon Strike": (1,4,7,10,12,13,14,15,16,17,19,20,22,25,28,31),
        "Hit": (1,4,7,10,14,18,21),
        "Defeat": (1,4,7,10,13,16,19,22,25,28,31,37),
    },
    "Wagon": {
        "Ready": (1,),
        "Advance": (1,4,7,10,13,16,18,19,22,25,28,31,33),
        "Stall": (1,3,5,7,10,13,16,19,22,25,27),
        "Destroyed": (1,4,5,7,9,11,13,15,17,19,22,25,28,31,34,37,40,42),
    },
}


def capture(scene,rig,out,action,f):
    rig.animation_data.action=bpy.data.actions[f"{rig.name[:-4]} | {action}"]
    scene.frame_set(f)
    bpy.context.view_layer.update()
    dots=[]
    dg=bpy.context.evaluated_depsgraph_get()
    for obj in scene.objects:
        if obj.type not in {"MESH","CURVE"}:
            continue
        ev=obj.evaluated_get(dg)
        if obj.type == "CURVE":
            mesh = ev.to_mesh()
            vertices = [v.co.copy() for v in mesh.vertices] if mesh else []
            ev.to_mesh_clear()
        else:
            vertices = [v.co for v in ev.data.vertices]
        dots.extend((world_to_camera_view(scene,scene.camera,ev.matrix_world @ v), obj.name)
                    for v in vertices)
    minimum, min_name=min((min(p.x,p.y), n) for p,n in dots)
    maximum, max_name=max((max(p.x,p.y), n) for p,n in dots)
    print(f"{out.name}: {action} F{f:02} projection {minimum:.4f} … {maximum:.4f}",flush=True)
    assert .008<minimum and maximum<.992, (action,f,minimum,min_name,maximum,max_name)
    scene.render.filepath=str(out)
    bpy.ops.render.render(write_still=True)


def pose_camera(cam, azimuth, wagon):
    cam.rotation_euler = Euler((1.150829196, 0, azimuth))
    cam.data.ortho_scale=2.68 if wagon else 2.52
    cam.location=Vector((0,0,.80 if wagon else .86))+cam.rotation_euler.to_matrix() @ Vector((0,0,6))


def main(out, mode):
    out.mkdir(parents=True,exist_ok=True)
    s=bpy.context.scene
    rig,=tuple(o for o in s.objects if o.type=="ARMATURE")
    actor=rig.name[:-4]
    assert actor in MOTION and not bpy.data.libraries
    assert not any(i.source=="FILE" for i in bpy.data.images)
    setup(s, "frontier_wagon_raider" if actor=="WagonRaider" else "frontier_wagon", ANCHOR)
    if mode in ("draft","poses"):
        s.cycles.samples=6 if mode=="draft" else 12
        s.render.resolution_x=s.render.resolution_y=280 if mode=="draft" else 416
        picks=RAIDER if actor=="WagonRaider" else WAGON
        for name,(action,f,az) in picks.items():
            if mode=="draft" and name not in {"ready","plant","strike","defeat","roll","stall","down"}:
                continue
            pose_camera(s.camera, -.435386419 if az is None else az, actor=="Wagon")
            capture(s,rig,out/f"{name}.png",action,f)
    elif mode=="motion":
        s.cycles.samples=6
        for action,frames in MOTION[actor].items():
            for f in frames:
                slug=action.lower().replace(" ","-")
                capture(s,rig,out/f"{slug}-{f:02}.png",action,f)
    else:
        raise ValueError(mode)


if __name__=="__main__":
    output,mode=sys.argv[sys.argv.index("--")+1:]
    main(Path(output).resolve(),mode)
