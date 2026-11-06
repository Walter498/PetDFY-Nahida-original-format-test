import hashlib,json,pathlib,plistlib,struct,unittest,math
from prepare import augment,ORIGINAL,HERE,ROOT

def safe(p):
    return isinstance(p,str) and bool(p) and not p.startswith('/') and '\\' not in p and '\0' not in p and all(x not in ('','.','..') for x in p.split('/'))
def geometry(model):
    defs=model['deformers']
    def vector(a,n):return isinstance(a,list) and len(a)==n and all(isinstance(v,(int,float)) and math.isfinite(v) for v in a)
    for key,d in defs.items():
        assert isinstance(d,dict)
        if 'pivot' in d:assert vector(d['pivot'],2)
        if 'rect' in d:assert vector(d['rect'],4)
        seen=set();p=key
        while p is not None:
            assert isinstance(p,str) and p not in seen and isinstance(defs.get(p),dict)
            seen.add(p);p=defs[p].get('parent')
    for p in model['parts']:
        assert vector(p['box'],4) and p['box'][2]>0 and p['box'][3]>0
        assert vector(p['grid'],2) and all(1<=v<=128 and int(v)==v for v in p['grid'])
        assert isinstance(defs.get(p.get('parent')),dict)
    return True

def validate(root):
    def read(p):
        if not safe(p): raise ValueError('unsafe path')
        f=root
        for s in p.split('/'):
            f=f/s
            if f.is_symlink(): raise ValueError('symlink')
        if not f.is_file() or not 0<f.stat().st_size<=67108864: raise ValueError('missing/empty asset')
        return f.read_bytes()
    c=json.loads(read('native-contract.json'))
    assert c['schema']==1 and c['scheme']==c['outfit']=='nahida'
    files=c['files'];assert isinstance(files,dict) and 0<len(files)<=2000
    assert c['featureFiles']
    for p,e in files.items():
        d=read(p);assert len(d)==e['bytes'] and hashlib.sha256(d).hexdigest()==e['sha256']
        if p.endswith('.png'): assert len(d)>=24 and d.startswith(b'\x89PNG\r\n\x1a\n')
    assert all(p in files for p in ('live/model.json','originals/model.json'))
    live=json.loads(read('live/model.json'));source=json.loads(read('originals/model.json'))
    assert isinstance(live['tables'],dict) and isinstance(source['pivots'],dict) and isinstance(source['units'],dict)
    assert sum(x.get('id')=='nahida' for x in source['schemes'])==1
    assert sum(x.get('id')=='nahida' for x in source['outfits'])==1
    model=live['models']['nahida'];assert isinstance(model['deformers'],dict) and model['deformers']
    assert isinstance(model['parts'],list) and model['parts']
    assert geometry(model)
    for part in model['parts']:
        assert len(part['grid'])==2 and len(part['box'])==4 and isinstance(part['parent'],str)
        if 'src' in part:
            assert safe(part['src']);rel='originals/'+part['src']
        elif part['tex']=='faceFx':continue
        else:
            assert safe(part['tex']);rel='originals/schemes/nahida/tex/'+part['tex']+'.png'
        assert rel in files
    for f in c['featureFiles']: assert safe(f) and f.startswith('originals/schemes/nahida/feat/') and f in files
    return 'contract_admissible_not_runtime_ready'

class ContractTests(unittest.TestCase):
    def fixture(self):return {'deformers':{'body':{'kind':'rot','pivot':[128,256]}},'parts':[{'parent':'body','grid':[2,2],'box':[120,200,30,40]}]}
    def test_xywh_not_right_bottom(self):self.assertTrue(geometry(self.fixture()))
    def test_invalid_geometry(self):
        for bad in ([120,200,0,40],[120,200,-1,40],[float('nan'),200,30,40]):
            m=self.fixture();m['parts'][0]['box']=bad
            with self.assertRaises(AssertionError):geometry(m)
    def test_cyclic_deformer(self):
        m=self.fixture();m['deformers']['body']['parent']='body'
        with self.assertRaises(AssertionError):geometry(m)
    def test_menu_preserves_all_other_fields(self):
        d=plistlib.loads((ROOT/'Library/PreferenceBundles/PetDFYPrefs.bundle/Root.plist').read_bytes());out=augment(d)
        s=next(x for x in out['items'] if x.get('key')=='Scheme')
        self.assertEqual(s['validValues'],[]); self.assertFalse(s['enabled'])
        p=next(x for x in augment(d,preview=True)['items'] if x.get('key')=='Scheme')
        self.assertEqual(p['validValues'],['nahida']);self.assertEqual(p['validTitles'],['纳西妲'])
        self.assertEqual([x for x in d['items'] if x.get('key') not in ('Scheme','Outfit')],[x for x in out['items'] if x.get('key') not in ('Scheme','Outfit')])
        preview=augment(d,preview=True)
        o=next(x for x in preview['items'] if x.get('key')=='Outfit')
        self.assertEqual(o['validValues'],['original']);self.assertEqual(o['validTitles'],['原装'])
    def test_idempotent_menu(self):
        d=plistlib.loads((ROOT/'Library/PreferenceBundles/PetDFYPrefs.bundle/Root.plist').read_bytes())
        self.assertEqual(augment(d),augment(augment(d)))
    def test_path_traversal(self):
        for p in ('../x','/x','a/../b','a//b','a\\b','a\0b','./a',''):
            self.assertFalse(safe(p))
    def test_missing_private_bundle_fails(self):
        with self.assertRaises((ValueError,FileNotFoundError)):validate(HERE/'assets-not-supplied')
    def test_source_has_no_global_whitelist_or_js_patch(self):
        s=(HERE/'NahidaCompat.m').read_text()
        self.assertNotIn('method_setImplementation(class_getInstanceMethod(NSArray',s);self.assertNotIn('evaluateJavaScript',s)
        self.assertIn('@"nahida-nahida"',s);self.assertIn('objc_copyClassList',s)
        self.assertIn('oldGet',s);self.assertIn('oldReload',s)
    def test_original_deb_intact(self):
        p=pathlib.Path('/var/minis/attachments/uploads/shared-A334561D_PetDFY-1.0-roothide.deb')
        self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),'6eac26dbf749e1c5330d161f03bf8232f1017534862929dc602dc042a918fb6c')
if __name__=='__main__': unittest.main(verbosity=2)
