"""Offline staging only. Never modifies the input package or extracted root."""
import hashlib, json, pathlib, plistlib
HERE=pathlib.Path(__file__).resolve().parent
BASE=HERE.parent
ROOT=BASE/'plugin-audit-20261106/root'
ORIGINAL=['deepseek','harness','chatgpt','claude','gemini','qwen','kimi','minimax']
def augment(data, preview=False):
    data=plistlib.loads(plistlib.dumps(data))
    specs=[x for x in data['items'] if x.get('key')=='Scheme']
    assert len(specs)==1
    item=specs[0]
    config=json.loads((HERE/'own-characters.json').read_text())
    # First patch supports ONLY nahida; never enable other IDs just via config.
    verified=set(config.get('nativeVerifiedCharacters',[]))
    chars=[c for c in config['characters'] if c['id']=='nahida' and (preview or c['id'] in verified)]
    item['validValues']=[c['id'] for c in chars]
    item['validTitles']=[c['name'] for c in chars]
    item['default']=config['defaultCharacter']
    if not chars: item['enabled']=False
    else: item.pop('enabled',None)
    if preview: item['footerText']='开发预览：原生资产未验证，不代表可用。'
    outfits=[x for x in data['items'] if x.get('key')=='Outfit']
    assert len(outfits)==1
    outfit=outfits[0]
    outfit['validValues']=['original'] if chars else []
    outfit['validTitles']=['原装'] if chars else []
    outfit['default']='original'
    if not chars: outfit['enabled']=False
    else: outfit.pop('enabled',None)
    return data
if __name__=='__main__':
    src=ROOT/'Library/PreferenceBundles/PetDFYPrefs.bundle/Root.plist'
    out=HERE/'staging/Library/PreferenceBundles/PetDFYPrefs.bundle/Root.plist'
    out.parent.mkdir(parents=True,exist_ok=True)
    out.write_bytes(plistlib.dumps(augment(plistlib.loads(src.read_bytes())),fmt=plistlib.FMT_XML,sort_keys=False))
    preview=HERE/'staging-preview/Library/PreferenceBundles/PetDFYPrefs.bundle/Root.plist'
    preview.parent.mkdir(parents=True,exist_ok=True)
    preview.write_bytes(plistlib.dumps(augment(plistlib.loads(src.read_bytes()),preview=True),fmt=plistlib.FMT_XML,sort_keys=False))
    inject=HERE/'NahidaCompat.plist'
    inject.write_bytes(plistlib.dumps({'Filter':{'Bundles':['com.apple.springboard','com.apple.Preferences']}},fmt=plistlib.FMT_XML))
    deb=pathlib.Path('/var/minis/attachments/uploads/shared-A334561D_PetDFY-1.0-roothide.deb')
    sha=hashlib.sha256(deb.read_bytes()).hexdigest()
    assert sha=='6eac26dbf749e1c5330d161f03bf8232f1017534862929dc602dc042a918fb6c'
    print(json.dumps({'original_deb_sha256':sha,'menu':str(out),'original_unmodified':True},ensure_ascii=False))
