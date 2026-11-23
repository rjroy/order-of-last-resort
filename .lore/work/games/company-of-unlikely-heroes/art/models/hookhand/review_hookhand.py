"""Reopen and check or render Hookhand and the accepted Harpooner control."""

import argparse
from pathlib import Path
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
from pose_hookhand import DOWN, END, HIT, LINE_BONES, PREFIX, PULL, PULL_DIR, READY, RECOVER, REST, WALK


V=Vector
ACTOR="Hookhand_Rig"
STILLS=(
    ("neutral",REST,1,"Camera_Neutral_Front"),
    ("ready",READY,1,"Camera_Tactical_Wide"),
    ("back",READY,1,"Camera_Back_3Q"),
    ("tension",PULL,14,"Camera_Tactical_Wide"),
    ("haul",PULL,22,"Camera_Tactical_Wide"),
    ("approach",WALK,11,"Camera_Tactical_Wide"),
    ("flinch",HIT,5,"Camera_Tactical_Wide"),
    ("down",DOWN,25,"Camera_Tactical_Wide"),
    ("recover",RECOVER,13,"Camera_Tactical_Wide"),
)
MOVES={"pull":PULL,"approach":WALK,"flinch":HIT,"down":DOWN,"recover":RECOVER}


def pose(rig,take,frame,prefix=PREFIX):
    rig.animation_data.action=bpy.data.actions[prefix+take]
    bpy.context.scene.frame_set(int(frame),subframe=frame%1)


def points(obj):
    evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh=evaluated.to_mesh()
    try:
        return [evaluated.matrix_world@v.co for v in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()


def matrix_gap(a,b):
    return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4))


def snapshot(rig):
    return {bone.name:bone.matrix.copy() for bone in rig.pose.bones}


def closest(a,b,v):
    axis=b-a
    t=max(0,min(1,(v-a).dot(axis)/axis.length_squared))
    return (v-a-t*axis).length


def check_hook_detach(hook):
    world=hook.matrix_world.copy()
    refs={child:child.matrix_world.copy() for child in hook.children}
    parent,parent_inv,basis=hook.parent,hook.matrix_parent_inverse.copy(),hook.matrix_basis.copy()
    hook.parent=None
    hook.matrix_world=world
    bpy.context.view_layer.update()
    assert all(matrix_gap(child.matrix_world,transform)<.00002 for child,transform in refs.items())
    hook.parent,hook.parent_type,hook.parent_bone=parent,"BONE","hook"
    hook.matrix_parent_inverse,hook.matrix_basis=parent_inv,basis
    bpy.context.view_layer.update()


def check():
    scene=bpy.context.scene
    rig=bpy.data.objects[ACTOR]
    hook=bpy.data.objects["Hook_Detachable"]
    bones=rig.pose.bones
    assert not bpy.data.libraries and not bpy.data.images
    assert scene.unit_settings.system=="METRIC" and scene.render.fps==24
    assert rig.animation_data.action.name==PREFIX+READY
    assert set(a.name for a in bpy.data.actions)=={PREFIX+take for take in END}
    assert (hook.parent,hook.parent_type,hook.parent_bone)==(rig,"BONE","hook")
    assert len(hook.children)==4
    for name,stop in END.items():
        a=bpy.data.actions[PREFIX+name]
        assert a.use_fake_user and tuple(a.frame_range)==(1,stop)
    pose(rig,REST,1)
    assert all(matrix_gap(b.matrix,b.bone.matrix_local)<.000045 for b in bones)
    assert (bones["hand.L"].tail-bones["upper_arm.L"].head).normalized().dot(V((1,0,0)))>.999
    pieces=[o for o in scene.objects if o.type in ("MESH","CURVE")]
    body=[o for o in pieces if o not in hook.children[:] and o.name not in ("Live hemp towline","Spiral fibre on towline")]
    pts=[v for o in body for v in points(o)]
    span=[max(v[i] for v in pts)-min(v[i] for v in pts) for i in range(3)]
    print(f"{len(bones)} bones, {len(pieces)} native mesh/curve pieces; neutral body {span[0]:.3f} × {span[1]:.3f} × {span[2]:.3f} m")
    pose(rig,READY,1)
    check_hook_detach(hook)
    baseline=snapshot(rig)
    pose(rig,DOWN,END[DOWN])
    collapsed=snapshot(rig)
    assert collapsed["pelvis"].translation.z < baseline["pelvis"].translation.z-.40
    rope=bpy.data.objects["Live hemp towline"]
    floors={}
    down_slack=0
    max_drift=0
    max_end_gap=0
    max_rest_gap=0
    min_rear_follow=1
    max_grip=0
    n=0
    for take,stop in END.items():
        if take==REST:
            continue
        floors[take]=float("inf")
        for sample_index in range(2,stop*2+1):
            frame=sample_index/2
            pose(rig,take,frame)
            n+=1
            assert matrix_gap(bones["root"].matrix,baseline["root"])<.00001
            if frame in (1,stop):
                if (take==RECOVER and frame==1) or (take==DOWN and frame==stop):
                    expected=collapsed
                else:
                    expected=baseline
                max_rest_gap=max(max_rest_gap,max(matrix_gap(b.matrix,expected[b.name]) for b in bones))
            for side in "RL":
                floors[take]=min(floors[take],min(v.z for v in points(bpy.data.objects["Hookhand sole "+side])))
                if take==PULL:
                    max_drift=max(max_drift,(bones["foot."+side].head-baseline["foot."+side].translation).length)
            geo=points(rope)
            end=sum(geo[-8:],V((0,0,0)))/8
            eye=hook.matrix_world@V((0,0,.041))
            max_end_gap=max(max_end_gap,(end-eye).length)
            for anchor,side in ((6,"R"),(12,"L")):
                grip=bones["hand."+side].head.lerp(bones["hand."+side].tail,.077/.108)
                max_grip=max(max_grip,(grip-bones[f"line.{anchor:02}"].head).length)
            if take==PULL and 14<=frame<=22:
                a,b=bones["line.12"].head,bones[f"line.{LINE_BONES-1:02}"].head
                down_slack=max(down_slack,max(closest(a,b,bones[f"line.{i:02}"].head) for i in range(13,LINE_BONES-1)))
                delta=(b-a).dot(PULL_DIR)
                min_rear_follow=min(min_rear_follow,delta)
    assert max_rest_gap<.00004,max_rest_gap
    assert max_end_gap<.00007,max_end_gap
    assert max_grip<.00007,max_grip
    assert max_drift<.006,max_drift
    assert down_slack<.006,down_slack
    assert min_rear_follow>.65,min_rear_follow
    assert min(floors.values())>-.010,floors
    pose(rig,PULL,14)
    out=bones["hook"].head.copy()
    early=bones["hand.L"].head.copy()
    pose(rig,PULL,22)
    back=bones["hook"].head.copy()
    late=bones["hand.L"].head.copy()
    travel=(out-back).dot(PULL_DIR)
    grip_reel=(early-late).dot(PULL_DIR)
    assert travel>.90 and grip_reel>.20
    print(f"{n} half-frame samples; exact holds/ready transitions; root fixed throughout.")
    print(f"Hook retracted {travel*100:.1f} cm; lead grip drew back {grip_reel*100:.1f} cm; planted ankle drift {max_drift*1000:.2f} mm.")
    print(f"Taut span maximum bend {down_slack*1000:.2f} mm; hook eye join error {max_end_gap*1000:.3f} mm; grip anchor error {max_grip*1000:.3f} mm.")
    print("Minimum sole height by take (mm):",{k:round(v*1000,2) for k,v in floors.items()})


def render(path,size,samples):
    scene=bpy.context.scene
    scene.render.resolution_x,scene.render.resolution_y=size
    scene.render.resolution_percentage=100
    scene.cycles.samples=samples
    scene.render.filepath=str(path)
    bpy.ops.render.render(write_still=True)


def registered():
    """Same tactical projection and pixels/metre for both rigs, relative to root."""
    scene=bpy.context.scene
    cam=bpy.data.objects["Camera_Tactical_Wide"]
    scene.camera=cam
    w,h=125,85
    ppm=26.55
    ax,ay=42,69
    cam.data.ortho_scale=w/ppm
    offset=V(((.5-ax/w)*w/ppm,(ay/h-.5)*h/ppm,7))
    cam.location=cam.rotation_euler.to_matrix()@offset
    scene.render.resolution_x,scene.render.resolution_y=w*4,h*4
    bpy.context.view_layer.update()
    uv=world_to_camera_view(scene,cam,V((0,0,0)))
    assert abs(uv.x*w-ax)<.01 and abs((1-uv.y)*h-ay)<.01, tuple(uv)
    return (w*4,h*4)


def poses(out):
    scene=bpy.context.scene
    rig=bpy.data.objects[ACTOR]
    kit=bpy.data.collections["04 · Coil, towline and detachable hook"]
    for name,action,beat,camera in STILLS:
        scene.camera=bpy.data.objects[camera]
        kit.hide_render=action==REST
        pose(rig,action,beat)
        render(out/f"{name}.png",(490,490),13)
    kit.hide_render=False
    size=registered()
    for name,action,frame in (("ready",READY,1),("tension",PULL,14),("haul",PULL,22)):
        pose(rig,action,frame)
        render(out/f"small-hook-{name}.png",size,10)


def harpooner(out):
    rig=bpy.data.objects["Harpooner_Rig"]
    size=registered()
    for name,action,frame in (("ready","Ready",1),("jab","Close Thrust",8),("cast","Ranged Cast",11)):
        pose(rig,action,frame,"Harpooner | ")
        render(out/f"small-harpooner-{name}.png",size,10)


def motion(out):
    scene=bpy.context.scene
    rig=bpy.data.objects[ACTOR]
    scene.camera=bpy.data.objects["Camera_Tactical_Wide"]
    for clip,take in MOVES.items():
        folder=out/clip
        folder.mkdir(exist_ok=True)
        frames=list(range(1,END[take]+1,2))
        if frames[-1]!=END[take]:
            frames.append(END[take])
        for i,frame in enumerate(frames,1):
            pose(rig,take,frame)
            render(folder/f"{i:03}.png",(290,290),7)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode",choices=("check","poses","motion","harpooner"))
    parser.add_argument("output",type=Path,nargs="?")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    if args.mode=="check":
        check(); return
    if args.output is None:
        parser.error("output directory required to render")
    args.output.mkdir(parents=True,exist_ok=True)
    {"poses":poses,"motion":motion,"harpooner":harpooner}[args.mode](args.output)


if __name__=="__main__":
    main()
