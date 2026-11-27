"""Render-only images to three-times sprites, a 1:1 grid proof and neutral sheet."""
from pathlib import Path
import sys,json
import numpy as np
from PIL import Image as I,ImageDraw as D,ImageFont as F,ImageFilter
v=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(exist_ok=False);proj=json.loads((v/'projections.json').read_text()); meta={};S=3;ink=(56,45,37);paper='#ede9de';font='/usr/share/fonts/noto/NotoSans-Regular.ttf';serif='/usr/share/fonts/noto/NotoSerif-Regular.ttf'
def txt(d,xy,text,size=15,col=ink,title=False,**kw):d.text(xy,text,font=F.truetype(serif if title else font,size),fill=col,**kw)
def rgbpaste(im,path,box):
 i=I.open(path).convert('RGBA');i=i.crop(i.getchannel('A').getbbox());i.thumbnail((box[2]-32,box[3]-32));im.paste(i,(box[0]+(box[2]-i.width)//2,box[1]+(box[3]-i.height)//2),i)
for name in ('row','column','crest-east'):
 raw=name+'-raw';i=I.open(v/(raw+'.png')).convert('RGBA');bb=i.getchannel('A').getbbox();assert min(*bb[:2],i.width-bb[2],i.height-bb[3])>4
 uv=np.array(proj[raw]); # Physical image length in each axis; verticals stay upright, unlike a grid shear.
 # A column requires extra depth exposure: see the projection and size record.
 scale=np.array([51,35.0]) if name=='row' else np.array([49,50]);a=np.diag((1000/5.8)/(S*scale));pivot=np.array([160,170])*S;t=uv[0]-a@pivot
 i=i.transform((320*S,340*S),I.Transform.AFFINE,np.column_stack((a,t)).flatten(),resample=I.Resampling.BICUBIC);alpha=i.getchannel('A');bg=I.new('RGBA',i.size,(*ink,255));bg.putalpha(alpha.filter(ImageFilter.MaxFilter(5)));bg.alpha_composite(i);bb=bg.getchannel('A').getbbox();crop=(bb[0]-4,bb[1]-4,bb[2]+4,bb[3]+4);bg=bg.crop(crop);bg.save(out/(name+'.png'));meta[name]={'size':bg.size,'pivot':(pivot-np.array(crop[:2])).tolist(),'alpha_bbox':bg.getchannel('A').getbbox(),'display_scale':1/3,'center_tile_ground_origin':[40 if name=='column' else 48,62]};assert bg.getchannel('A').getextrema()==(0,255)
(out/'registration.json').write_text(json.dumps(meta,indent=2)+'\n')
im=I.new('RGB',(920,652),paper);d=D.Draw(im);txt(d,(34,18),'Shield Wall',40,title=True);txt(d,(36,76),'DEPLOYED BARRICADE    /    MODEL STUDY',14);d.line((35,108,885,108),fill='#8b8478');rgbpaste(im,v/'front.png',(40,108,840,290));d.line((35,402,885,402),fill='#bdb6a9');rgbpaste(im,v/'cast-angle.png',(35,412,415,193));rgbpaste(im,v/'reverse.png',(470,412,415,193));txt(d,(240,622),'Tactical three-quarter',17,title=True,anchor='mm');txt(d,(678,622),'Reverse and foot braces',17,title=True,anchor='mm');im.save(out/'review.png')
im=I.new('RGB',(862,460),paper);d=D.Draw(im);txt(d,(28,15),'Shield Wall  /  board registration',30,title=True);txt(d,(29,68),'Actual board pixels   •   96 × 80 px cells   •   highlighted cells share one wall',15);tile=(96,80)
for ix,name in enumerate(('row','column')):
 x=28+414*ix;y=124;txt(d,(x,y-25),('Row   /   west to east','Column   /   north to south')[ix],17,title=True)
 # 3x3 registration diagram: underline the occupied cells and mark their centers.
 for cy in range(3):
  for cx in range(3):
   active=(cy==1 if ix==0 else cx==1);p=(x+cx*96,y+cy*80);d.rectangle((*p,p[0]+95,p[1]+79),fill=('#bcac90' if active else '#d6ccba'),outline='#9c9383');
   if active:d.line((p[0]+2,p[1]+78,p[0]+93,p[1]+78),fill='#806332',width=2)
 crop=I.open(out/(name+'.png'));p=meta[name]['pivot'];base=np.array([x+96,y+80])+np.array(meta[name]['center_tile_ground_origin']);mini=crop.resize(tuple(round(a/3) for a in crop.size),I.Resampling.LANCZOS);im.paste(mini,tuple(np.rint(base-np.array(p)/3).astype(int)),mini)
 for i,c in enumerate(((-1,0),(0,0),(1,0)) if ix==0 else ((0,-1),(0,0),(0,1))):
  px=x+96*(1+c[0])+48;py=y+80*(1+c[1])+72
  if ix==0:txt(d,(px,py+102),str(c),13,anchor='mm')
  else:txt(d,(x+307,py-32),str(c),13,anchor='lm')
 txt(d,(x,397),('Tile offsets:   (−96, 0)   /   (0, 0)   /   (+96, 0)','Tile offsets:   (0, −80)   /   (0, 0)   /   (0, +80)')[ix],13)
txt(d,(28,430),'Registration study, not a game capture.  Center-tile ground origin: row (48, 62), column (40, 62) px.',13);im.save(out/'board-size.png');print(json.dumps(meta))
