#!/usr/bin/env python3
"""Read-only validation; NEVER rewrites Mach-O headers. Python standard library only."""
import hashlib, json, pathlib, struct, sys
CPU_ARM64=0x0100000c

def thin(data, arch, filetype):
    assert len(data)>=32, 'truncated Mach-O'
    magic,cpu,sub,kind,ncmds,sizeofcmds,flags,reserved=struct.unpack_from('<8I',data)
    assert magic==0xfeedfacf, 'not little-endian 64-bit Mach-O'
    assert cpu==CPU_ARM64, f'wrong CPU {cpu:#x}'
    assert sub & 0x00ffffff == {'arm64':0,'arm64e':2}[arch], f'{arch} wrong subtype {sub:#x}'
    assert kind==filetype, f'wrong file type {kind}'
    assert 32+sizeofcmds<=len(data), 'truncated load commands'
    pos=32
    for _ in range(ncmds):
        cmd,size=struct.unpack_from('<II',data,pos)
        assert size>=8 and pos+size<=32+sizeofcmds, 'invalid load command'
        pos+=size
    assert pos==32+sizeofcmds, 'load command sizes inconsistent'
    return {'arch':arch,'cputype':hex(cpu),'cpusubtype_raw':hex(sub),'cpusubtype_base':sub&0xffffff,'capability_bits':hex(sub&0xff000000),'filetype':kind,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}

def verify(root):
    root=pathlib.Path(root); report={'objects':[], 'thin_dylibs':[], 'fat_slices':[]}
    for arch in ('arm64','arm64e'):
        obj=thin((root/f'NahidaCompat.{arch}.o').read_bytes(),arch,1)
        dylib=thin((root/f'NahidaCompat.{arch}.dylib').read_bytes(),arch,6)
        assert obj['cpusubtype_raw']==dylib['cpusubtype_raw'], 'object/dylib subtype mismatch'
        report['objects'].append(obj); report['thin_dylibs'].append(dylib)
    fat=(root/'NahidaCompat.dylib').read_bytes()
    magic,n=struct.unpack_from('>II',fat)
    assert magic==0xcafebabe and n==2, 'expected FAT_MAGIC with exactly two slices'
    seen=set(); ranges=[]
    for i in range(n):
        cpu,sub,offset,size,align=struct.unpack_from('>5I',fat,8+20*i)
        assert cpu==CPU_ARM64 and sub&0xffffff in (0,2), 'wrong fat architecture'
        arch='arm64e' if sub&0xffffff==2 else 'arm64'
        assert arch not in seen, 'duplicate architecture'
        seen.add(arch)
        assert offset>=8+20*n and offset+size<=len(fat), 'invalid slice range'
        assert align<=30 and offset%(1<<align)==0, 'invalid slice alignment'
        for a,b in ranges: assert offset+size<=a or offset>=b, 'overlapping slices'
        ranges.append((offset,offset+size))
        payload=fat[offset:offset+size]
        entry=thin(payload,arch,6)
        assert int(entry['cpusubtype_raw'],16)==sub, 'fat entry/header subtype mismatch'
        assert payload==(root/f'NahidaCompat.{arch}.dylib').read_bytes(), 'fat slice differs from thin dylib'
        report['fat_slices'].append(entry)
    report['fat_sha256']=hashlib.sha256(fat).hexdigest()
    report['result']='PASS: genuine arm64 subtype 0 + arm64e subtype 2; object/link/fat consistent'
    return report
if __name__=='__main__':
    print(json.dumps(verify(sys.argv[1]),indent=2))
