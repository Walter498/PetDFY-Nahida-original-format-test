#!/usr/bin/env python3
import json, shutil, zipfile, hashlib
from pathlib import Path
from PIL import Image
R=Path('/var/minis/workspace/petdfy-refactor-20261105')
SRC=R/'characters/nahida'; ST=R/'staging/characters/nahida'; OUT=R/'nahida-original-format'
if OUT.exists(): shutil.rmtree(OUT)
(OUT/'live').mkdir(parents=True)
(OUT/'originals').mkdir(parents=True)
# Read the formal original outfit manifest.
om=json.loads((SRC/'outfits/original/outfit.json').read_text())
# Original-format asset layout: non-face parts under tex, face parts under feat.
face={'face','eye_creases','brows','eye_near_ball','eye_near_iris','eye_near_lash','eye_near_highlight','eye_far_ball','eye_far_iris','eye_far_lash','eye_far_highlight'}
for p in om['parts']:
    part=p['id']; folder='feat' if part in face else 'tex'
    src=SRC/'outfits/original'/p['src']; dst=OUT/'originals'/folder/(part+'.png')
    dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
# Original-format state directory, plus outfit states for later outfit switching.
(OUT/'originals/states').mkdir(parents=True,exist_ok=True)
for stn in ['neutral','happy','wink','sit','sleep','dragged']:
    shutil.copyfile(SRC/'outfits/original/states'/f'{stn}.png', OUT/'originals/states'/f'{stn}.png')
for of in ['pajamas','sailor','blazer']:
    src=ST/'outfits'/of; dst=OUT/'originals/outfits'/of
    for p in src.rglob('*'):
        if p.is_file() and p.suffix.lower() in ['.png','.json']:
            q=dst/p.relative_to(src); q.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(p,q)
# Preview thumbnail in the original-format thumbs directory.
thumb=OUT/'originals/thumbs/nahida.png'; thumb.parent.mkdir(parents=True,exist_ok=True)
shutil.copyfile(SRC/'outfits/original/preview.png',thumb)
# Convert the current manifest into the original model shape.
parts=[]
for p in om['parts']:
    part=dict(p); part.pop('svg',None); part.pop('alpha_bbox_T',None); part.pop('channels',None)
    part['src']=('feat/' if p['id'] in face else 'tex/')+p['id']+'.png'
    # Original model boxes use rig units. Keep the measured local extents and original grid contract.
    if not part.get('box'): part['box']=[0,0,1,1]
    parts.append(part)
base_units={'S':0.19,'X0':650,'FEET':1363,'DS':0.6,'featDS':1}
pivots={'body':[128,256],'waist':[128,189],'neck':[128,155],'armNear':[113,166],'armFar':[154,169],'legBack':[112,203],'legFront':[144,203],'head':[138,115]}
def outfit_entry(of):
    if of=='original': return {'id':'original'}
    src=ST/'outfits'/of/'outfit.json'
    d=json.loads(src.read_text())
    op=[]
    for p in d.get('parts',[]):
        x=dict(p); x.pop('svg',None); x.pop('alpha_bbox_T',None); x.pop('channels',None)
        x['src']=f'outfits/{of}/'+p['src']
        op.append(x)
    return {'id':of,'parts':op}
model={'units':base_units,'pivots':pivots,'parts':parts,'feat':{'eyes':{},'sprites':{},'blush':None,'skin':None},'schemes':[{'id':'nahida','brand':'Nahida','label':'纳西妲','accent':'#7AA96F','ready':True,'eyeHighlights':False}],'view':[-12,-8,268,272],'outfits':[outfit_entry(x) for x in ['original','pajamas','sailor','blazer']]}
(OUT/'originals/model.json').write_text(json.dumps(model,ensure_ascii=False,indent=2)+'\n')
# live/model.json keeps original live schema: tables plus model registry.
oldzip='/var/minis/attachments/uploads/PetDFY-assets.zip'
with zipfile.ZipFile(oldzip) as z: oldlive=json.loads(z.read('live/model.json'))
# Host-facing deformer registry for the sprite figure; keys and value shapes follow live/model.json.
deformers={'body':{'kind':'rot','pivot':[128,256]},'waist':{'kind':'rot','parent':'body','pivot':[128,189]},'armNear':{'kind':'rot','parent':'waist','pivot':[113,166]},'armFar':{'kind':'rot','parent':'waist','pivot':[154,169]},'legBack':{'kind':'warp','parent':'body','rect':[80,168,175,256]},'legFront':{'kind':'warp','parent':'body','rect':[105,168,180,256]},'neck':{'kind':'rot','parent':'waist','pivot':[128,155]},'headBack':{'kind':'warp','parent':'neck','rect':[30,12,215,168]},'headMid':{'kind':'warp','parent':'neck','rect':[30,12,215,168]},'headFeat':{'kind':'warp','parent':'neck','rect':[30,12,215,168]},'headFront':{'kind':'warp','parent':'neck','rect':[30,12,215,168]},'hairSway':{'kind':'warp','parent':'headBack','rect':[30,30,220,250]},'bangsSway':{'kind':'warp','parent':'headFront','rect':[40,20,220,180]}}
live_models={}
for of in ['original','pajamas','sailor','blazer']:
 entry=model if of=='original' else next(x for x in model['outfits'] if x['id']==of)
 live_models[of]={'deformers':deformers,'parts':len(entry.get('parts',parts)),'view':model['view']}
live={'version':1,'tables':oldlive.get('tables',{}),'models':live_models,'upstreamCommit':'nahida-original-format-test'}
(OUT/'live/model.json').write_text(json.dumps(live,ensure_ascii=False,indent=2)+'\n')
# Write the actual original-format figure entry.
fig={'manifest':2,'api':2,'id':'nahida','version':'0.2.0-test','name':{'zh':'纳西妲','en':'Nahida'},'about':{'zh':'纳西妲单角色原格式测试包','en':'Nahida single-character original-format test'},'entry':'figure.js','export':'createNahidaBody','model':'model.json','thumb':'thumbs/nahida.png','axes':[{'id':'outfit','name':{'zh':'服装','en':'Outfit'},'options':[{'id':x,'thumb':'thumbs/nahida.png','name':{'zh':x,'en':x}} for x in ['original','pajamas','sailor','blazer']]}],'presets':[{'id':'nahida','pick':{'outfit':'original'},'name':{'zh':'纳西妲','en':'Nahida'}}],'status':'experimental-original-format','runtimeNotes':['originals/ and live/ preserve the original package layout','original uses the independent Nahida figure renderer','new outfits are included with path-compatible assets']}
(OUT/'originals/figure.json').write_text(json.dumps(fig,ensure_ascii=False,indent=2)+'\n')
# Copy the format-compatible renderer generated below by this build step.
renderer=R/'nahida-original-format-figure.js'
shutil.copyfile(renderer,OUT/'originals/figure.js')
# Keep the import root strict: only the original-format live/originals trees go into the ZIP.
(OUT/'README.md').unlink(missing_ok=True)
zipout=R/'PetDFY-Nahida-original-format-test.zip'
if zipout.exists(): zipout.unlink()
files=sorted(p for p in OUT.rglob('*') if p.is_file())
with zipfile.ZipFile(zipout,'w',zipfile.ZIP_DEFLATED) as z:
    for p in files:z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(zipout) as z:
    assert z.testzip() is None
    names=z.namelist()
print('members',len(names),'testzip',zipfile.ZipFile(zipout).testzip(),'sha256',hashlib.sha256(zipout.read_bytes()).hexdigest(),'size',zipout.stat().st_size)
print('roots',sorted(set(n.split('/')[0] for n in names)))
