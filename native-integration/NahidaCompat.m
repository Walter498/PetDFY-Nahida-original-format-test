// Standalone MRC Objective-C; no Substrate dependency; no JS execution.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <dispatch/dispatch.h>
#include <sys/stat.h>
#include <string.h>
#include <math.h>
// A release header must define a C string literal. Missing/empty pin is legacy mode.
#if __has_include("OwnReleasePin.h")
#include "OwnReleasePin.h"
#endif
#ifndef NAHIDA_OWN_CONTRACT_SHA256
#define NAHIDA_OWN_CONTRACT_SHA256 ""
#endif
static NSString *OwnPin(void) { return @NAHIDA_OWN_CONTRACT_SHA256; }
static BOOL OwnRelease(void) { return OwnPin().length != 0; }
static BOOL HexHash(id x) {
    if (![x isKindOfClass:NSString.class] || [x length]!=64) return NO;
    return [x rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location==NSNotFound;
}

static NSString *const Domain = @"com.susudear.petdfyprefs";
static NSString *const PrivateRelativeRoot = @"originals/native/nahida";
static BOOL IsNahida(id v) { return [v isKindOfClass:NSString.class] && [v isEqualToString:@"nahida"]; }
static BOOL Selected(void) {
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("Scheme"), (CFStringRef)Domain);
    BOOL yes = IsNahida((id)v); if (v) CFRelease(v); return yes;
}
static BOOL SafePath(id p) {
    if (![p isKindOfClass:NSString.class] || ![p length] || [p length]>512 || [p rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound || [p hasPrefix:@"/"] || [p containsString:@"\\"]) return NO;
    for (NSString *s in [p componentsSeparatedByString:@"/"])
        if (!s.length || [s isEqual:@"."] || [s isEqual:@".."]) return NO;
    return YES;
}
// Reject symlinks at every descendant component (not just the leaf).
static NSData *Read(NSURL *root, NSString *rel) {
    if (!SafePath(rel)) return nil;
    if (!root.isFileURL) return nil;
    NSString *p = root.path; struct stat rootStat;
    if (lstat(p.fileSystemRepresentation,&rootStat) || !S_ISDIR(rootStat.st_mode) || S_ISLNK(rootStat.st_mode)) return nil;
    for (NSString *s in [rel componentsSeparatedByString:@"/"]) {
        p = [p stringByAppendingPathComponent:s]; struct stat st;
        if (lstat(p.fileSystemRepresentation, &st) || S_ISLNK(st.st_mode)) return nil;
    }
    struct stat st;
    if (lstat(p.fileSystemRepresentation, &st) || !S_ISREG(st.st_mode) || st.st_size < 1 || st.st_size > 67108864) return nil;
    return [NSData dataWithContentsOfFile:p];
}
static id JSON(NSData *d) { return d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL] : nil; }
static BOOL Dict(id x) { return [x isKindOfClass:NSDictionary.class]; }
static BOOL Array(id x) { return [x isKindOfClass:NSArray.class]; }
static NSString *Hash(NSData *d) {
    unsigned char h[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *s = [NSMutableString string];
    for (unsigned i=0;i<sizeof(h);i++) [s appendFormat:@"%02x", h[i]]; return s;
}
static BOOL Fail(NSString **why, NSString *s) { if (why) *why=s; return NO; }
static BOOL Vector(id a, NSUInteger n) {
    if (!Array(a) || [a count]!=n) return NO;
    for (id v in a) if (![v isKindOfClass:NSNumber.class] || !isfinite([v doubleValue])) return NO;
    return YES;
}
static BOOL Geometry(id model) {
    id defs=model[@"deformers"];
    for (id key in defs) {
        id d=defs[key];
        if (!Dict(d) || (d[@"pivot"] && !Vector(d[@"pivot"],2)) || (d[@"rect"] && !Vector(d[@"rect"],4))) return NO;
        NSMutableSet *seen=[NSMutableSet set]; id p=key;
        while (p) {
            if (![p isKindOfClass:NSString.class] || [seen containsObject:p] || !Dict(defs[p])) return NO;
            [seen addObject:p]; p=defs[p][@"parent"];
        }
    }
    for (id p in model[@"parts"]) {
        if (!Dict(p) || !Vector(p[@"grid"],2) || !Vector(p[@"box"],4) || !Dict(defs[p[@"parent"]])) return NO;
        for (id g in p[@"grid"]) if ([g doubleValue]<1 || [g doubleValue]>128 || floor([g doubleValue])!=[g doubleValue]) return NO;
        // Native part.box is [x,y,width,height], not [left,top,right,bottom].
        if ([p[@"box"][2] doubleValue]<=0 || [p[@"box"][3] doubleValue]<=0) return NO;
    }
    return YES;
}
// root is a PRIVATE subtree under the original, already jbroot-resolved URL.
// Never resolve /var/jb or scan guessed .jbroot-* prefixes.
static BOOL Entry(NSData *d,id e) {
    id b=Dict(e) ? e[@"bytes"] : nil;
    return d && [b isKindOfClass:NSNumber.class] && CFGetTypeID((CFTypeRef)b)!=CFBooleanGetTypeID() &&
        [b doubleValue]==(double)d.length && HexHash(e[@"sha256"]) && [Hash(d) isEqual:e[@"sha256"]];
}
static NSString *PartPath(id part) {
    if (!Dict(part)) return nil;
    if ([part[@"tex"] isEqual:@"faceFx"]) return @"__face";
    if (part[@"src"]) return SafePath(part[@"src"]) ? [@"originals/" stringByAppendingString:part[@"src"]] : nil;
    return SafePath(part[@"tex"]) ? [NSString stringWithFormat:@"originals/schemes/nahida/tex/%@.png",part[@"tex"]] : nil;
}
static BOOL Validate(NSURL *root, NSURL *outer, BOOL own, NSString **why) {
    NSData *raw=Read(root,@"native-contract.json");
    if (own && (!HexHash(OwnPin()) || !raw || ![Hash(raw) isEqual:OwnPin()])) return Fail(why,@"release contract pin mismatch");
    id c=JSON(raw);
    if (!Dict(c) || ![c[@"schema"] isEqual:@1] || !IsNahida(c[@"scheme"]) || !IsNahida(c[@"outfit"])) return Fail(why,@"missing/invalid native-contract.json");
    if (own && (!c[@"ownOnly"] || CFGetTypeID((CFTypeRef)c[@"ownOnly"])!=CFBooleanGetTypeID() || ![c[@"ownOnly"] boolValue] ||
        ![c[@"bootstrapSelection"] isEqual:@"deepseek-maid"] || ![c[@"effectiveSelection"] isEqual:@"nahida-nahida"])) return Fail(why,@"invalid own declaration");
    id files=c[@"files"], features=c[@"featureFiles"];
    if (!Dict(files) || ![files count] || [files count]>2000 || !Array(features) || ![features count]) return Fail(why,@"missing files/feature closure");
    for (id p in files) {
        if ([p isEqual:@"native-contract.json"]) return Fail(why,@"self-pinned contract");
        id entry=files[p]; NSData *d=Read(root,p);
        if (!Entry(d,entry)) return Fail(why,@"missing, unsafe or hash-mismatched asset");
        if ([p hasSuffix:@".png"]) { const unsigned char sig[]={137,80,78,71,13,10,26,10};
            if (d.length<24 || memcmp(d.bytes,sig,8)) return Fail(why,@"invalid PNG header"); }
    }
    if (!files[@"live/model.json"] || !files[@"originals/model.json"]) return Fail(why,@"models not pinned in contract");
    id live=JSON(Read(root,@"live/model.json")), source=JSON(Read(root,@"originals/model.json"));
    if (!Dict(live) || !Dict(source) || !Dict(live[@"models"]) || !Dict(live[@"tables"]) || !Array(source[@"outfits"]) || !Dict(source[@"pivots"]) || !Dict(source[@"units"])) return Fail(why,@"invalid native model structure");
    if (own) {
        id boot=c[@"bootFiles"];
        if (!Dict(boot) || [boot count]!=2) return Fail(why,@"invalid bootFiles");
        for (NSString *rel in @[@"live/model.json",@"originals/model.json"]) {
            NSData *d=Read(outer,rel);
            if (!Entry(d,boot[rel]) || ![d isEqualToData:Read(root,rel)]) return Fail(why,@"boot model differs from pinned native model");
        }
        if ([live[@"models"] count]!=1 || [source[@"outfits"] count]!=1 || !Array(source[@"schemes"]) || [source[@"schemes"] count]!=1)
            return Fail(why,@"foreign own model/scheme/outfit");
    }
    id model=live[@"models"][@"nahida"];
    NSUInteger outfits=0;
    for (id o in source[@"outfits"]) if (Dict(o) && IsNahida(o[@"id"])) outfits++;
    if (!Dict(model) || !Array(model[@"parts"]) || ![model[@"parts"] count] || !Dict(model[@"deformers"]) || ![model[@"deformers"] count] || outfits!=1) return Fail(why,@"independent nahida rig/outfit absent");
    if (!Geometry(model)) return Fail(why,@"invalid numeric geometry or cyclic/missing deformer parent");
    id schemes=source[@"schemes"]; NSUInteger n=0;
    if (!Array(schemes)) return Fail(why,@"schemes absent");
    for (id s in schemes) if (Dict(s) && IsNahida(s[@"id"])) n++;
    if (n!=1) return Fail(why,@"nahida scheme must be unique");
    for (id part in model[@"parts"]) {
        if (!Dict(part) || !Array(part[@"grid"]) || [part[@"grid"] count]!=2 || !Array(part[@"box"]) || [part[@"box"] count]!=4 || ![part[@"parent"] isKindOfClass:NSString.class]) return Fail(why,@"invalid native part geometry");
        NSString *rel=PartPath(part);
        if ([rel isEqual:@"__face"]) continue;
        if (!rel) return Fail(why,@"unsafe texture reference");
        if (!files[rel]) return Fail(why,@"part texture not pinned in contract");
    }
    for (id f in features) if (!SafePath(f) || ![f hasPrefix:@"originals/schemes/nahida/feat/"] || !files[f]) return Fail(why,@"feature not pinned in contract");
    if (own) {
        if (!files[@"state-variants.json"]) return Fail(why,@"state JSON not pinned");
        id variants=JSON(Read(root,@"state-variants.json"));
        if (!Dict(source[@"stateVariants"]) || ![source[@"stateVariants"] isEqual:variants]) return Fail(why,@"embedded stateVariants differs from pinned state JSON");
        if (!Dict(variants) || ![variants[@"schema"] isEqual:@"same-master-state-variants/v1"] || !Dict(variants[@"states"])) return Fail(why,@"invalid state JSON");
        for (NSString *required in @[@"stand",@"sit"]) if (!Dict(variants[@"states"][required])) return Fail(why,@"missing state");
        for (id state in variants[@"states"]) {
            id node=variants[@"states"][state];
            id replacements=Dict(node) ? node[@"replacements"] : nil;
            if (!Dict(replacements)) return Fail(why,@"invalid replacements");
            for (id key in replacements) {
                NSString *rel=PartPath(replacements[key]);
                if (!rel || (![rel isEqual:@"__face"] && !files[rel])) return Fail(why,@"replacement texture not pinned");
            }
        }
        // Close features actually referenced by the source, not only a self-reported list.
        id feat=source[@"feat"], sprites=Dict(feat) ? feat[@"sprites"] : nil, eyes=Dict(feat) ? feat[@"eyes"] : nil;
        if (!Dict(sprites) || !Dict(eyes)) return Fail(why,@"missing source features");
        NSMutableArray *names=[NSMutableArray arrayWithArray:[sprites allKeys]];
        for (id eye in eyes) for (NSString *suffix in @[@"ball",@"iris",@"lash",@"hl"])
            [names addObject:[NSString stringWithFormat:@"%@_%@",eye,suffix]];
        for (id name in names) {
            if (!SafePath(name)) return Fail(why,@"unsafe feature name");
            NSString *rel=[NSString stringWithFormat:@"originals/schemes/nahida/feat/%@.png",name];
            if (!files[rel] || ![features containsObject:rel]) return Fail(why,@"source feature not pinned");
        }
    }
    // This is an admission check, NOT a renderer-ready assertion or a helper ready.json.
    return YES;
}

static NSMutableSet *installed;
static char PrivateRigKey;
static BOOL Signature(Method m, unsigned args, const char *ret) {
    if (!m || method_getNumberOfArguments(m)!=args) return NO;
    char *r=method_copyReturnType(m); BOOL ok=!strcmp(r,ret); free(r); return ok;
}
static BOOL Arg(Method m,unsigned i,char type) {
    char *t=method_copyArgumentType(m,i); BOOL ok=t && t[0]==type; free(t); return ok;
}
// Process-lifetime immutable resource generation. Installation must stop/restart the
// host; neither successful nor failed contexts are refreshed during hot replacement.
static NSMutableDictionary *OwnContexts;
static BOOL OwnPreferencesActive;
static BOOL RigHookReady;
static NSDictionary *OwnContext(NSURL *outer) {
    if (!OwnRelease() || !outer.isFileURL) return nil;
    @synchronized (Domain) {
        if (!OwnContexts) OwnContexts=[NSMutableDictionary new];
        NSString *key=outer.absoluteString;
        id cached=OwnContexts[key];
        if (cached) return Dict(cached) ? cached : nil;
        NSURL *native=[outer URLByAppendingPathComponent:PrivateRelativeRoot isDirectory:YES];
        NSString *why=nil; BOOL valid=NO;
        @try {
            // Walk from R as well, rejecting symlinked originals/native ancestors.
            valid=Read(outer,[PrivateRelativeRoot stringByAppendingString:@"/native-contract.json"]) && Validate(native,outer,YES,&why);
        }
        @catch (NSException *e) { why=e.reason; }
        // Retain the parsed source from the same pinned immutable generation.
        id sourceModel=valid ? JSON(Read(native,@"originals/model.json")) : nil;
        valid=valid && Dict(sourceModel);
        id context=valid ? (id)@{@"outer":outer,@"native":native,@"pin":OwnPin(),@"sourceModel":sourceModel} : (id)NSNull.null;
        OwnContexts[key]=context;
        if (valid) OwnPreferencesActive=YES;
        else NSLog(@"[NahidaCompat] own admission denied: %@",why);
        return valid ? context : nil;
    }
}
static BOOL OwnPrefs(void) { @synchronized (Domain) { return OwnPreferencesActive; } }
static BOOL OwnSelection(id selection) {
    return [selection isKindOfClass:NSString.class] &&
        ( [selection isEqual:@"deepseek-maid"] || [selection isEqual:@"nahida"] || [selection isEqual:@"nahida-nahida"] );
}
static void Deny(NSString *reason) {
    [NSException raise:@"NahidaOwnAdmission" format:@"%@",reason];
}
// Install the ARC state module only after native classes and pinned art exist.
// Its BOOL interlock enables this candidate code, never certifies device acceptance.
#import "state-variants-impl/NativeStateVariants.h"
BOOL NCPostValidateRig(id actualRig, NSURL *privateRoot, NSDictionary *sourceModel, NSError **error) {
    if (!actualRig || !privateRoot.isFileURL || !Dict(sourceModel) || !Dict(sourceModel[@"stateVariants"])) {
        if (error) *error=[NSError errorWithDomain:@"NahidaCompat" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Invalid verified rig callback input"}];
        return NO;
    }
    if (!NSVInstall(YES,error)) return NO;
    return NSVMarkVerifiedNahidaRig(actualRig,privateRoot,sourceModel[@"stateVariants"],error);
}
static void HookPreferences(Class cls) {
    Method reload=class_getInstanceMethod(cls,sel_registerName("reload"));
    Method scheme=class_getInstanceMethod(cls,sel_registerName("scheme"));
    Method outfit=class_getInstanceMethod(cls,sel_registerName("outfit"));
    Ivar si=class_getInstanceVariable(cls,"_scheme"), oi=class_getInstanceVariable(cls,"_outfit");
    if (!Signature(reload,2,"v") || !Signature(scheme,2,"@") || !Signature(outfit,2,"@") ||
        !si || !oi || ivar_getTypeEncoding(si)[0]!='@' || ivar_getTypeEncoding(oi)[0]!='@') return;
    IMP oldReload=method_getImplementation(reload);
    for (NSString *name in @[@"scheme",@"outfit"]) {
        SEL sel=NSSelectorFromString(name); Method getter=class_getInstanceMethod(cls,sel);
        IMP old=method_getImplementation(getter); BOOL isScheme=[name isEqual:@"scheme"];
        method_setImplementation(getter,imp_implementationWithBlock(^id(id obj) {
            if (OwnPrefs() || (isScheme && Selected())) return @"nahida";
            return ((id(*)(id,SEL))old)(obj,sel);
        }));
    }
    method_setImplementation(reload,imp_implementationWithBlock(^(id obj) {
        ((void(*)(id,SEL))oldReload)(obj,sel_registerName("reload"));
        if (OwnPrefs() || Selected()) {
            id old=object_getIvar(obj,si); object_setIvar(obj,si,[@"nahida" copy]); [old release];
        }
        if (OwnPrefs()) {
            id old=object_getIvar(obj,oi); object_setIvar(obj,oi,[@"nahida" copy]); [old release];
        }
        // Enabled and download preferences are deliberately not changed here.
    }));
    [installed addObject:[NSValue valueWithPointer:cls]];
}
// WNPainter.url and WNRenderer.resourceURL stay at the outer bundle root.
// Only file paths returned by a Nahida rig are rebased; __face remains a live texture.
static NSString *PrivateAssetPath(id rig, id path) {
    if (![path isKindOfClass:NSString.class] || [path hasPrefix:@"__"]) return path;
    if (!objc_getAssociatedObject(rig,&PrivateRigKey)) return path;
    if (!SafePath(path)) return nil;
    NSString *prefix=[PrivateRelativeRoot stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) return path;
    if (!SafePath(path) || ![path hasPrefix:@"originals/"]) return nil;
    return [prefix stringByAppendingString:path];
}
static void HookRig(Class cls) {
    SEL sel=sel_registerName("initWithResourceURL:scheme:seed:freeGround:");
    Method m=class_getInstanceMethod(cls,sel);
    Method texture=class_getInstanceMethod(cls,sel_registerName("textureForPart:"));
    Method feature=class_getInstanceMethod(cls,sel_registerName("featurePath:"));
    if (!Signature(m,6,"@") || !Arg(m,2,'@') || !Arg(m,3,'@') || !Arg(m,4,'I') || !Arg(m,5,'B') ||
        !Signature(texture,3,"@") || !Arg(texture,2,'@') || !Signature(feature,3,"@") || !Arg(feature,2,'@')) return;
    IMP oldTexture=method_getImplementation(texture), oldFeature=method_getImplementation(feature);
    IMP newTexture=imp_implementationWithBlock(^id(id obj,id part) {
        id path=((id(*)(id,SEL,id))oldTexture)(obj,sel_registerName("textureForPart:"),part);
        return PrivateAssetPath(obj,path);
    });
    IMP newFeature=imp_implementationWithBlock(^id(id obj,id name) {
        id path=((id(*)(id,SEL,id))oldFeature)(obj,sel_registerName("featurePath:"),name);
        return PrivateAssetPath(obj,path);
    });
    method_setImplementation(texture,newTexture); method_setImplementation(feature,newFeature);
    IMP old=method_getImplementation(m);
    IMP replacement=imp_implementationWithBlock(^id(id obj,NSURL *url,id selection,unsigned int seed,BOOL freeGround) {
        typedef id(*Init)(id,SEL,NSURL *,id,unsigned int,BOOL);
        NSDictionary *context=OwnContext(url);
        BOOL own=OwnRelease();
        if (own && (!context || !OwnSelection(selection))) { [obj release]; Deny(@"unverified own rig or foreign selection"); return (id)nil; }
        if (!own && (![selection isKindOfClass:NSString.class] || !IsNahida([[selection componentsSeparatedByString:@"-"] firstObject])))
            return ((Init)old)(obj,sel,url,selection,seed,freeGround);
        NSURL *privateRoot=own ? context[@"native"] : [url URLByAppendingPathComponent:PrivateRelativeRoot isDirectory:YES];
        NSString *why=nil;
        @try {
            if (!own && (!url.isFileURL || !Validate(privateRoot,url,NO,&why))) { [obj release]; return (id)nil; }
            objc_setAssociatedObject(obj,&PrivateRigKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            id result=((Init)old)(obj,sel,privateRoot,@"nahida-nahida",seed,freeGround);
            if (!result || ![result isKindOfClass:cls]) {
                if (result) [result release];
                if (own) Deny(@"foreign rig initializer returned nil/wrong class");
                return (id)nil;
            }
            objc_setAssociatedObject(result,&PrivateRigKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSDictionary *sourceModel=own ? context[@"sourceModel"] : JSON(Read(privateRoot,@"originals/model.json"));
            NSError *callbackError=nil;
            if (!NCPostValidateRig(result,privateRoot,sourceModel,&callbackError)) {
                [result release]; if (own) Deny(@"verified rig callback rejected"); return (id)nil;
            }
            return result;
        } @catch (NSException *e) {
            // Own failures must unwind reset, never feed nil into mesh construction.
            if (own) @throw;
            NSLog(@"[NahidaCompat] native load failed: %@",e.reason);
            return (id)nil;
        }
    });
    method_setImplementation(m,replacement); RigHookReady=YES; [installed addObject:[NSValue valueWithPointer:cls]];
    NSLog(@"[NahidaCompat] native rig hook registered (not runtime validated)");
}
static void HookRenderer(Class cls) {
    SEL initSel=sel_registerName("initWithResourceURL:liveOnly:"), resetSel=sel_registerName("resetLiveWithScheme:freeGround:");
    Method init=class_getInstanceMethod(cls,initSel), reset=class_getInstanceMethod(cls,resetSel);
    Method live=class_getInstanceMethod(cls,sel_registerName("liveRig"));
    Ivar resource=class_getInstanceVariable(cls,"_resourceURL");
    if (!Signature(init,4,"@") || !Arg(init,2,'@') || !Arg(init,3,'B') ||
        !Signature(reset,4,"v") || !Arg(reset,2,'@') || !Arg(reset,3,'B') ||
        !Signature(live,2,"@") || !resource || ivar_getTypeEncoding(resource)[0]!='@') return;
    IMP oldInit=method_getImplementation(init), oldReset=method_getImplementation(reset), getLive=method_getImplementation(live);
    method_setImplementation(reset,imp_implementationWithBlock(^(id obj,id selection,BOOL ground) {
        if (OwnRelease()) {
            NSURL *outer=object_getIvar(obj,resource);
            if (!RigHookReady || !OwnContext(outer) || !OwnSelection(selection)) Deny(@"renderer reset admission denied");
        }
        ((void(*)(id,SEL,id,BOOL))oldReset)(obj,resetSel,selection,ground);
    }));
    method_setImplementation(init,imp_implementationWithBlock(^id(id obj,NSURL *outer,BOOL liveOnly) {
        typedef id(*Init)(id,SEL,NSURL *,BOOL);
        if (!OwnRelease()) return ((Init)oldInit)(obj,initSel,outer,liveOnly);
        // Gate BEFORE foreign init: original init immediately resets deepseek-maid,
        // and audited reset is not proven nil-rig-safe. Do not change renderer R.
        if (!RigHookReady || !OwnContext(outer)) { [obj release]; return (id)nil; }
        @try {
            id result=((Init)oldInit)(obj,initSel,outer,YES); // Disable legacy clip manifest.
            if (!result || ![result isKindOfClass:cls]) { if (result) [result release]; return (id)nil; }
            id rig=((id(*)(id,SEL))getLive)(result,sel_registerName("liveRig"));
            if (!rig || !objc_getAssociatedObject(rig,&PrivateRigKey)) { [result release]; return (id)nil; }
            return result;
        } @catch (NSException *e) {
            NSLog(@"[NahidaCompat] renderer startup stopped: %@",e.reason);
            // Foreign initializer ownership on exception is unspecified; no release.
            return (id)nil;
        }
    }));
    [installed addObject:[NSValue valueWithPointer:cls]];
}
static void Scan(void) {
    @autoreleasepool {
        if (!installed) installed=[NSMutableSet new];
        unsigned n=0; Class *classes=objc_copyClassList(&n);
        for (unsigned i=0;i<n;i++) {
            Class c=classes[i]; if ([installed containsObject:[NSValue valueWithPointer:c]]) continue;
            const char *image=class_getImageName(c), *name=class_getName(c);
            // Never hook an unrelated application's same-named class.
            if (!image || (!strstr(image,"/PetDFY.dylib") && !strstr(image,"/PetDFYPrefs.bundle/"))) continue;
            if (!strcmp(name,"PDPreferences")) HookPreferences(c);
            if (!strcmp(name,"WNLiveRig")) HookRig(c);
            if (!strcmp(name,"WNRenderer")) HookRenderer(c);
        } free(classes);
    }
}
static void AddedImage(const struct mach_header *h,intptr_t slide) {
    (void)h;(void)slide;
    // No ObjC messaging or class initialization inside dyld's loader lock.
    dispatch_async(dispatch_get_main_queue(),^{ Scan(); });
}
__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        Scan();
        [NSNotificationCenter.defaultCenter addObserverForName:NSBundleDidLoadNotification object:nil queue:nil usingBlock:^(NSNotification *note) { (void)note; dispatch_async(dispatch_get_main_queue(),^{ Scan(); }); }];
        _dyld_register_func_for_add_image(AddedImage);
        // Class registration may finish after add-image callback. Retry indefinitely,
        // on one serial queue; absence at constructor time is not considered success.
        static dispatch_source_t timer;
        timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
        dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,0),NSEC_PER_SEC,NSEC_PER_MSEC*50);
        dispatch_source_set_event_handler(timer,^{ Scan(); }); dispatch_resume(timer);
    }
}
