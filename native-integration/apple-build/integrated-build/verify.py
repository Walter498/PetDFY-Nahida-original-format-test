import hashlib,json,pathlib,re,struct,sys
from verify_macho import verify,thin
PIN='4c13f9551c15b09585f5344611970123570cd6d0cccc31133e788925c77a2ea9'
def pin(path):
    text=pathlib.Path(path).read_text()
    assert re.search(r'static\s+NSString\s*\*OwnPin\(void\)\s*\{\s*return\s*@"'+PIN+r'"\s*;',text), 'actual preprocessed OwnPin is not expected contract'
    assert 'OwnReleasePin.h' in text, 'real pin header not included'
    return {'contract':PIN,'preprocessed_sha256':hashlib.sha256(text.encode()).hexdigest(),'actual_OwnPin_expansion':True}
def symbols(data):
    pos=32
    for _ in range(struct.unpack_from('<I',data,16)[0]):
        cmd,size=struct.unpack_from('<II',data,pos)
        if cmd==2:
            _,_,off,n,stroff,strsize=struct.unpack_from('<6I',data,pos)
            result={}
            for i in range(n):
                idx,kind,sect,desc,value=struct.unpack_from('<IBBHQ',data,off+16*i)
                if not idx: continue
                name=data[stroff+idx:data.index(b'\0',stroff+idx)].decode()
                result[name]={'undefined':kind&0xe==0,'kind':kind,'section':sect}
            return result
        pos+=size
    raise AssertionError('missing LC_SYMTAB')
if __name__=='__main__':
    if sys.argv[1]=='--pin':
        print(json.dumps(pin(sys.argv[2])));sys.exit()
    root=pathlib.Path(sys.argv[1]); report=verify(root); report['state_objects']=[]; report['integration']={}
    expected=['_NSVInstall','_NSVMarkVerifiedNahidaRig','_NSVStatus']
    for arch in ['arm64','arm64e']:
        obj=(root/f'NativeStateVariants.{arch}.o').read_bytes()
        entry=thin(obj,arch,1)
        assert entry['cpusubtype_raw']==report['objects'][['arm64','arm64e'].index(arch)]['cpusubtype_raw']
        report['state_objects'].append(entry)
        syms=symbols((root/f'NahidaCompat.{arch}.dylib').read_bytes())
        assert all(n in syms and not syms[n]['undefined'] for n in expected),'missing defined NSV symbols'
        assert not any(n.startswith('_NSV') and s['undefined'] for n,s in syms.items()),'unresolved NSV'
        main=symbols((root/f'NahidaCompat.{arch}.o').read_bytes())
        assert all(main[n]['undefined'] for n in expected[:2]), 'main object does not call NSV entry points'
        assert not re.search(r'^\s*_NSV\w*\s*$',(root/f'undefined.{arch}.txt').read_text(),re.M), 'unresolved NSV C symbol'
        report['integration'][arch]={'defined_NSV_symbols':expected,'unresolved_NSV':[],'main_references_resolved':True,'pin':pin(root/f'NahidaCompat.{arch}.i')}
    report['result']='PASS: integrated MRC main + ARC state, actual pin, resolved NSV, genuine arm64/arm64e'
    print(json.dumps(report,indent=2))
