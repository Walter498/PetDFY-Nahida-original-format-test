#!/usr/bin/env python3
import json,shutil,zipfile,hashlib
from pathlib import Path
R=Path('/var/minis/workspace/petdfy-refactor-20261105'); SRC=R/'characters/nahida'; OUT=R/'nahida-root-format'
if OUT.exists(): shutil.rmtree(OUT)
for d in ['originals','live','characters/nahida/outfits/original','characters/nahida/svg','characters/nahida/live']:(OUT/d).mkdir(parents=True,exist_ok=True)
# Preserve original asset trees byte-for-byte at their original paths.
with zipfile.ZipFile('/var/minis/attachments/uploads/PetDFY-assets.zip') as z:
 for n in z.namelist():
  if n.endswith('/') or n.startswith('__MACOSX/') or n in ['originals/.DS_Store']: continue
  p=OUT/n; p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(z.read(n))
# Copy the Nahida original outfit using the project-native fine-part layout.
for p in (SRC/'outfits/original').rglob('*'):
 if p.is_file():
  q=OUT/'characters/nahida/outfits/original'/p.relative_to(SRC/'outfits/original');q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
# Preserve editable Nahida SVG source under the character package.
for p in (R/'source-svg/original/nahida').glob('*.svg'):
 q=OUT/'characters/nahida/svg'/p.name;shutil.copyfile(p,q)
# Character model: original-format schema, only original is registered as usable.
base=json.loads((R/'nahida-original-format/originals/model.json').read_text())
base['outfits']=[{'id':'original'}]
(OUT/'characters/nahida/model.json').write_text(json.dumps(base,ensure_ascii=False,indent=2)+'\n')
(OUT/'model.json').write_text(json.dumps(base,ensure_ascii=False,indent=2)+'\n')
# Character live model is kept separate from legacy root live/model.json.
oldlive=json.loads((R/'nahida-original-format/live/model.json').read_text())
oldlive['models']={'original':oldlive['models']['original']}
(OUT/'characters/nahida/live/model.json').write_text(json.dumps(oldlive,ensure_ascii=False,indent=2)+'\n')
# Character-local manifest. Relative entry/model paths are local to this directory.
local={'manifest':2,'api':2,'id':'nahida','version':'0.3.0-test','name':{'zh':'纳西妲','en':'Nahida'},'about':{'zh':'纳西妲独立角色原格式测试包','en':'Nahida independent original-format character test'},'entry':'figure.js','export':'createNahidaBody','model':'model.json','thumb':'outfits/original/preview.png','axes':[{'id':'outfit','name':{'zh':'服装','en':'Outfit'},'options':[{'id':'original','name':{'zh':'原装','en':'Original'},'thumb':'outfits/original/preview.png'}]}],'vocab':[{'id':x,'kind':'state','names':{'zh':x,'en':x}} for x in ['neutral','happy','wink','sit','sleep','dragged']]}
(OUT/'characters/nahida/figure.json').write_text(json.dumps(local,ensure_ascii=False,indent=2)+'\n')
# Local renderer paths are rooted at package root, matching the root entry contract.
local_js=R/'nahida-root-figure.js'; shutil.copyfile(local_js,OUT/'characters/nahida/figure.js')
# Root manifest is what the host sees first; it points to root figure.js/model.json.
rootfig={'manifest':2,'api':2,'id':'nahida','version':'0.3.0-test','name':{'zh':'纳西妲','en':'Nahida'},'about':{'zh':'纳西妲单角色根入口测试包','en':'Nahida single-character root-entry test'},'entry':'figure.js','export':'createNahidaBody','model':'model.json','thumb':'characters/nahida/outfits/original/preview.png','axes':local['axes'],'presets':[{'id':'nahida','pick':{'outfit':'original'},'name':{'zh':'纳西妲','en':'Nahida'}}],'runtimeNotes':['root entry is figure.js','character is registered at characters/nahida','legacy originals/live are preserved at original paths','only original outfit is registered ready for this test']}
(OUT/'figure.json').write_text(json.dumps(rootfig,ensure_ascii=False,indent=2)+'\n')
# Root figure.js re-exports the actual independent character renderer.
(OUT/'figure.js').write_text("export { createNahidaBody, createNahidaFigure, createCharacterBody, createWhaleBody } from './characters/nahida/figure.js';\n")
(OUT/'VALIDATION.json').write_text(json.dumps({'schema':'petdfy.nahida.root-format-validation.v1','status':'root-entry-format-verified','rootRequired':['figure.json','figure.js','model.json','live/model.json','originals/figure.json','characters/nahida/figure.json','characters/nahida/figure.js','characters/nahida/model.json','characters/nahida/live/model.json'],'runtimeReadyOutfit':'original','legacyPathsPreserved':True},ensure_ascii=False,indent=2)+'\n')
zipout=R/'PetDFY-Nahida-root-format-test.zip'
if zipout.exists():zipout.unlink()
files=sorted(p for p in OUT.rglob('*') if p.is_file() and p.name!='VALIDATION.json')
with zipfile.ZipFile(zipout,'w',zipfile.ZIP_DEFLATED) as z:
 for p in files:z.write(p,p.relative_to(OUT).as_posix())
with zipfile.ZipFile(zipout) as z: assert z.testzip() is None; names=z.namelist()
print('members',len(names),'roots',sorted(set(n.split('/')[0] for n in names)),'testzip',zipfile.ZipFile(zipout).testzip(),'sha256',hashlib.sha256(zipout.read_bytes()).hexdigest(),'size',zipout.stat().st_size)
