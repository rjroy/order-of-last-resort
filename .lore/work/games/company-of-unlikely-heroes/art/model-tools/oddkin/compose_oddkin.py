"""Compose pose proof and real motion previews; needs ImageMagick 7 and FFmpeg."""
import sys,json,subprocess as sp
from pathlib import Path
p=Path(sys.argv[1]).resolve();n=p.name;title=n.replace('_',' ').title();stills=json.loads((p/'verified.json').read_text())['stills'];wk=p/'layout';wk.mkdir(exist_ok=True);bg='#eee6d6';ink='#3b302b';font='Liberation-Sans';cols=3

def run(*args):sp.run([str(x) for x in args],check=True)
def mag(*args):run('magick','-limit','thread','1',*args)
def titlebar(path,w,head,sub):mag('-size',f'{w}x77',f'xc:{ink}','-font','Liberation-Serif','-pointsize','30','-fill',bg,'-annotate','+17+35',head,'-font',font,'-pointsize','13','-fill','#d3b795','-annotate','+18+60',sub,path)
def tiles(files,across,dest):run('magick','montage','-limit','thread','1',*files,'-background',bg,'-tile',f'{across}x','-geometry','+0+0',dest)
def cell(src,path,label,size):
 # Titles get an actor-specific fixed crop; each physical-size proof below stays at 26.5 px/m.
 crop={'goblin':'204x187+59+104','trickster':'229x213+44+81','ogre':'320x277+0+30','village_troll':'320x252+0+47'}[n]
 mag(src,'-resize','320x320!','-crop',crop,'+repage','-resize',f'{size}x{size}','-background',bg,'-alpha','remove','-alpha','off','-gravity','center','-extent',f'{size}x{size}','-gravity','south','-splice','0x30','-font',font,'-pointsize','16','-fill',ink,'-annotate','+0+6',label,path)
files=[]
for i,(a,f) in enumerate(stills):
 dst=wk/f'cell-{i}.png';cell(p/f'pose-{i}.png',dst,f'{a}  /  {f:02}',260);files.append(dst)
tiles(files,cols,wk/'sheet.png');titlebar(wk/'title.png',780,title,'MODEL CANDIDATE     /     NATIVE RIG PERFORMANCES     /     TACTICAL PROJECTION');mini=[]
for i,(a,f) in enumerate(stills[1:],1):
 dst=wk/f'mini-{i}.png';mag(p/f'pose-{i}.png','-resize',('99x99' if n=='village_troll' else '90x90'),'-background',bg,'-alpha','remove','-alpha','off',dst);mini.append(dst)
mag(*mini,'+append','-gravity','west','-background',bg,'-extent','780x90',wk/'minis.png');mag('-size','780x29',f'xc:{bg}','-font',font,'-pointsize','14','-fill',ink,'-annotate','+16+21','Board-size silhouettes   /   26.5 pixels per metre',wk/'scale.png');mag(wk/'title.png',wk/'sheet.png',wk/'scale.png',wk/'minis.png','-append',p/'pose-sheet.png')
clips=[a for a in dict.fromkeys(a for a,f in stills) if (p/a).is_dir()];seqs=[]
for i,a in enumerate(clips):
 seq=[]
 for j,src in enumerate(sorted((p/a).glob('*.png'))):
  dest=wk/f'clip-{i}-{j}.png';cell(src,dest,a,220);seq.append(dest)
 assert len(seq)>1;seqs.append(seq)
if seqs:
 c=3 if len(seqs)>4 else 2;titlebar(wk/'motion-title.png',c*220,title,'MOTION STUDY     /     AUTHORED TIMING');total=max(map(len,seqs))+6
 for i in range(total):
  tiles([s[min(i,len(s)-1)] for s in seqs],c,wk/'frame.png');mag(wk/'motion-title.png',wk/'frame.png','-append','-background',bg,'-gravity','north','-splice','0x1',wk/f'frame-{i:03}.png')
 run('ffmpeg','-nostdin','-loglevel','error','-y','-framerate','12','-i',wk/'frame-%03d.png','-frames:v',total,'-c:v','libx264','-threads','2','-pix_fmt','yuv420p','-movflags','+faststart',p/'motion-preview.mp4');run('ffmpeg','-nostdin','-loglevel','error','-i',p/'motion-preview.mp4','-f','null','-');run('ffmpeg','-nostdin','-loglevel','error','-y','-ss','0.5','-i',p/'motion-preview.mp4','-frames:v',1,p/'decoded.png')
