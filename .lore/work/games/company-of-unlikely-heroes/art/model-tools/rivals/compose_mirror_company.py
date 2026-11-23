"""Compose the three Blender review folders into labeled evidence. No model writes."""
from pathlib import Path
import sys,subprocess as sp

root=Path(sys.argv[1]).resolve()
actors={'rival_knight':['Shield Push'],'rival_wizard':['Nearest Blast'],'rival_healer':['Ally Heal','Padded Bonk']}
paper='#eae0cf'; ink='#332b2c';accent='#886849'
def cmd(*a):sp.run(list(map(str,a)),check=True)
def mag(*a):cmd('magick',*a)
def cell(src,dest,n,sz=280):
    # Shared ground line belongs to the review layout, not the model.
    mag(src,'-resize',f'{sz}x{sz}','-background',paper,'-alpha','remove','-alpha','off',
        '-gravity','south','-splice','0x30','-font','Liberation-Serif','-pointsize','19','-fill',ink,
        '-annotate','+0+7',n,dest)
def title(path,w,t,sub):
    mag('-size',f'{w}x72',f'xc:{ink}','-gravity','west','-font','Liberation-Serif','-fill',paper,'-pointsize','28','-annotate','+16-10',t,
        '-font','Liberation-Sans','-fill','#d5b78e','-pointsize','13','-annotate','+18+18',sub,path)
def montage(files,across,path):
    cmd('magick','montage',*files,'-tile',f'{across}x','-geometry','+0+0','-background',paper,path)
for name,acts in actors.items():
    d=root/name;temps=d/'layout';temps.mkdir(exist_ok=True)
    files=[]
    for i,n in enumerate(['Neutral T','Ready','Move']+acts+['Hit','Defeat']):
        img=temps/f'pose{i}.png';cell(d/(n+'.png'),img,n);files.append(img)
    montage(files,3,temps/'poses.png')
    title(temps/'title.png',840,name.replace('_',' ').title(),'MIRROR COMPANY     /     NATIVE POSES     /     FIXED TACTICAL PROJECTION')
    mag(temps/'title.png',temps/'poses.png','-append',d/'pose-sheet.png')
    frames=[]
    for n in acts:
        for src in sorted((d/n).glob('*.png')):
            dst=temps/f'motion{len(frames):03}.png';cell(src,dst,n,300);frames.append(dst)
    cmd('ffmpeg','-nostdin','-v','error','-y','-framerate','12','-i',temps/'motion%03d.png','-frames:v',len(frames),'-c:v','libx264','-pix_fmt','yuv420p','-movflags','+faststart',d/'motion-preview.mp4')
    cmd('ffmpeg','-nostdin','-v','error','-i',d/'motion-preview.mp4','-f','null','-')
    cmd('ffmpeg','-nostdin','-v','error','-y','-i',d/'motion-preview.mp4','-vf',r'select=eq(n\,4)','-frames:v','1',d/'decoded.png')
layout=root/'layout';layout.mkdir(exist_ok=True)
out=[]
for n in ('Ready','Action'):
    for k,acts in actors.items():
        label=k.split('_')[1].title() if n=='Ready' else acts[0]
        dst=layout/f'{n}-{k}.png';cell(root/k/((n if n=='Ready' else acts[0])+'.png'),dst,label,290);out.append(dst)
montage(out,3,layout/'group.png')
title(layout/'title.png',870,'Mirror Company','ENCOUNTER 05     /     READY AND ACTION     /     COMMON CAMERA, ORIGIN AND SCALE')
mag(layout/'title.png',layout/'group.png','-append',root/'group-comparison.png')
