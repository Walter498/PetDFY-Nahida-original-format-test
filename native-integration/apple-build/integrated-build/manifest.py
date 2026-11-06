import hashlib,json,os,pathlib,shutil,sys
ROOT=pathlib.Path(sys.argv[1]); OUT=pathlib.Path(sys.argv[2])
files=['NahidaCompat.m','state-variants-impl/NativeStateVariants.m','state-variants-impl/NativeStateVariants.h','own-assets-staging-v3/OwnReleasePin.h','apple-build/integrated-build/build.sh','apple-build/integrated-build/manifest.py','apple-build/integrated-build/verify.py','apple-build/integrated-build/verify_macho.py']
manifest={'commit':os.environ.get('GITHUB_SHA'),'run_id':os.environ.get('GITHUB_RUN_ID'),'contract_pin':'4c13f9551c15b09585f5344611970123570cd6d0cccc31133e788925c77a2ea9','files':{}}
for f in files:
    b=(ROOT/f).read_bytes(); manifest['files'][f]=hashlib.sha256(b).hexdigest()
    target=OUT/'source'/f; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(b)
(OUT/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
