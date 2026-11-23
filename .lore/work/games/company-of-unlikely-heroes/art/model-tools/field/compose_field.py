"""Compose the reopened-model reviews. Takes the render directory; uses ImageMagick 7."""
from pathlib import Path
from subprocess import run
import sys

out=Path(sys.argv[1]).resolve()
root=next(p for p in Path(__file__).resolve().parents if (p/'games/company-of-unlikely-heroes/tools/cast').is_dir())
board=root/'games/company-of-unlikely-heroes/assets/boards/frontier_sheep_board.png'
roles={'frontier_sheep':[('Ready',1),('Startle',4),('Flee_step',8),('Penned',1)],'frontier_shepherd':[('Ready',1),('Pursuit_step',6),('Scatter_wave',15),('Scatter_wave',40)]}
font='/usr/share/fonts/liberation/LiberationSans-Regular.ttf'; paper='#eadcc4'; ink='#382f32'
def im(*args):run(['magick',*map(str,args)],check=True)
def img(role,action,f):return out/role/f'{action}-{f:02}.png'
for role,stills in roles.items():
    title='Sheep' if role.endswith('sheep') else 'Opposing Shepherd';tile=[]
    for action,f in stills:
        label='Return' if f==40 else action.replace('_',' ')
        tile+=['(',img(role,action,f),'-gravity','northwest','-crop','264x236+28+34','+repage','-background',paper,'-alpha','remove','-gravity','south','-splice','0x24','-font',font,'-pointsize','15','-fill',ink,'-annotate','+0+5',label,')']
    im(*tile,'+append','-background',paper,'-gravity','north','-splice','0x38','-font',font,'-pointsize','21','-fill',ink,'-annotate','+0+7',title+'    /    The Great Sheep Escape',out/(role+'-poses.png'))
    # Each clip plays for its source time. Add only deliberate holds between takes.
    seq=['Ready','Startle','Flee_step','Pen_settle','Penned'] if title=='Sheep' else ['Ready','Pursuit_step','Pursuit_step','Scatter_wave'];args=[]
    for a in seq:
        frames=sorted((out/role).glob(a+'-*.png'));nums=[int(p.stem.split('-')[-1]) for p in frames];end={'Ready':25,'Startle':15,'Flee_step':23,'Pen_settle':37,'Penned':25,'Pursuit_step':26,'Scatter_wave':44}[a]
        for file,fr,nxt in zip(frames,nums,nums[1:]+[end]):args+=['-delay',str(round((nxt-fr)*100/24)),'(',file,'-background',paper,'-alpha','remove','-gravity','south','-font',font,'-pointsize','15','-fill',ink,'-annotate','+0+19',a.replace('_',' '),')']
    im(*args,'-loop',0,out/(role+'-motion.gif'))
args=[board,'-resize','768x512!']; roles_short=list(roles)
for r,c,row,a,f in [(0,3,1,'Ready',1),(0,3,2,'Ready',1),(1,5,2,'Ready',1),(0,3,3,'Ready',1)]:
    # Half-size board registration and 22/80 cell foot offset. Actor size from manifest .375.
    x=(272+184*c-28*row)/2+1;y=(176+18*c+146*row)/2+22*73/80;scale=.375*73/80
    args+=['(',img(roles_short[r],a,f),'-resize',f'{round(320*scale)}x',')','-geometry',f'+{round(x-160*scale)}+{round(y-248*scale)}','-composite']
im(*args,'-background',paper,'-gravity','south','-splice','0x34','-fill',ink,'-font',font,'-pointsize',15,'-annotate','+0+8','Stock placements   /   Model composite on the sheep field, not a runtime capture',out/'tactical-group.png')
# Staged neighboring-cell contrast, not a recorded turn: keep the sheep still on the harmless wave.
for filename,caption,a,f,offset in [('wave','Adjacent wave   /   watch the open hand, not the planted crook','Ready',1,0),('flight','Round end   /   one free step away from the nearest character','Flee_step',8,-.5)]:
    args=[board,'-resize','768x512!']
    for r,c,row,act,frame,flip in [(0,3,1,'Ready',1,False),(0,4+offset,2,a,f,True),(1,5,2,'Scatter_wave' if filename=='wave' else 'Ready',15 if filename=='wave' else 1,True),(0,3,3,'Ready',1,False)]:
        x=(272+184*c-28*row)/2+1;y=(176+18*c+146*row)/2+22*73/80
        args+=['(',img(roles_short[r],act,frame),*(['-flop'] if flip else []),'-resize',f'{round(320*scale)}x',')','-geometry',f'+{round(x-160*scale)}+{round(y-248*scale)}','-composite']
    im(*args,'-gravity','northwest','-crop','412x244+252+115','+repage','-gravity','south','-background',paper,'-splice','0x32','-font',font,'-pointsize',13,'-fill',ink,'-annotate','+0+7',caption,out/f'{filename}-detail.png')
im(out/'wave-detail.png',out/'flight-detail.png','+append',out/'tactical-event-contrast.png')
