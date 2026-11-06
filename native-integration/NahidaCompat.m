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

static NSString *const Domain = @"com.susudear.petdfyprefs";
static BOOL IsNahida(id v) { return [v isKindOfClass:NSString.class] && [v isEqualToString:@"nahida"]; }
static BOOL Selected(void) {
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("Scheme"), (CFStringRef)Domain);
    BOOL yes = IsNahida((id)v); if (v) CFRelease(v); return yes;
}
static BOOL SafePath(id p) {
    if (![p isKindOfClass:NSString.class] || ![p length] || [p hasPrefix:@"/"] || [p containsString:@"\\"]) return NO;
    for (NSString *s in [p componentsSeparatedByString:@"/"])
        if (!s.length || [s isEqual:@"."] || [s isEqual:@".."]) return NO;
    return YES;
}
// Reject symlinks at every descendant component (not just the leaf).
static NSData *Read(NSURL *root, NSString *rel) {
    if (!SafePath(rel)) return nil;
    NSString *p = root.path;
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
static BOOL Validate(NSURL *root, NSString **why) {
    id c=JSON(Read(root,@"native-contract.json"));
    if (!Dict(c) || ![c[@"schema"] isEqual:@1] || !IsNahida(c[@"scheme"]) || !IsNahida(c[@"outfit"])) return Fail(why,@"missing/invalid native-contract.json");
    id files=c[@"files"], features=c[@"featureFiles"];
    if (!Dict(files) || ![files count] || [files count]>2000 || !Array(features) || ![features count]) return Fail(why,@"missing files/feature closure");
    for (id p in files) {
        id entry=files[p]; NSData *d=Read(root,p);
        if (!Dict(entry) || !d || ![entry[@"bytes"] isKindOfClass:NSNumber.class] || [entry[@"bytes"] unsignedLongLongValue]!=d.length || ![Hash(d) isEqual:entry[@"sha256"]]) return Fail(why,@"missing, unsafe or hash-mismatched asset");
        if ([p hasSuffix:@".png"]) { const unsigned char sig[]={137,80,78,71,13,10,26,10};
            if (d.length<24 || memcmp(d.bytes,sig,8)) return Fail(why,@"invalid PNG header"); }
    }
    if (!files[@"live/model.json"] || !files[@"originals/model.json"]) return Fail(why,@"models not pinned in contract");
    id live=JSON(Read(root,@"live/model.json")), source=JSON(Read(root,@"originals/model.json"));
    if (!Dict(live) || !Dict(source) || !Dict(live[@"models"]) || !Dict(live[@"tables"]) || !Array(source[@"outfits"]) || !Dict(source[@"pivots"]) || !Dict(source[@"units"])) return Fail(why,@"invalid native model structure");
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
        NSString *rel=nil;
        if (part[@"src"]) { if (!SafePath(part[@"src"])) return Fail(why,@"unsafe part.src"); rel=[@"originals/" stringByAppendingString:part[@"src"]]; }
        else if ([part[@"tex"] isEqual:@"faceFx"]) continue;
        else { if (!SafePath(part[@"tex"])) return Fail(why,@"invalid part.tex"); rel=[NSString stringWithFormat:@"originals/schemes/nahida/tex/%@.png",part[@"tex"]]; }
        if (!files[rel]) return Fail(why,@"part texture not pinned in contract");
    }
    for (id f in features) if (!SafePath(f) || ![f hasPrefix:@"originals/schemes/nahida/feat/"] || !files[f]) return Fail(why,@"feature not pinned in contract");
    // This is an admission check, NOT a renderer-ready assertion or a helper ready.json.
    return YES;
}

static NSMutableSet *installed;
static BOOL Signature(Method m, unsigned args, const char *ret) {
    if (!m || method_getNumberOfArguments(m)!=args) return NO;
    char *r=method_copyReturnType(m); BOOL ok=!strcmp(r,ret); free(r); return ok;
}
static BOOL Arg(Method m,unsigned i,char type) {
    char *t=method_copyArgumentType(m,i); BOOL ok=t && t[0]==type; free(t); return ok;
}
static void HookPreferences(Class cls) {
    // Per-Class captured IMPs: the identically named Settings/SpringBoard classes
    // have different addresses, ivar layouts and original implementations.
    Method getter=class_getInstanceMethod(cls,sel_registerName("scheme"));
    Method reload=class_getInstanceMethod(cls,sel_registerName("reload"));
    Ivar iv=class_getInstanceVariable(cls,"_scheme");
    if (!Signature(getter,2,"@") || !Signature(reload,2,"v") || !iv || ivar_getTypeEncoding(iv)[0]!='@') return;
    IMP oldGet=method_getImplementation(getter), oldReload=method_getImplementation(reload);
    IMP newGet=imp_implementationWithBlock(^id(id obj) {
        if (Selected()) return @"nahida";
        return ((id(*)(id,SEL))oldGet)(obj,sel_registerName("scheme"));
    });
    IMP newReload=imp_implementationWithBlock(^(id obj) {
        ((void(*)(id,SEL))oldReload)(obj,sel_registerName("reload"));
        if (Selected()) { id old=object_getIvar(obj,iv); id value=[@"nahida" copy]; object_setIvar(obj,iv,value); [old release]; }
    });
    method_setImplementation(getter,newGet); method_setImplementation(reload,newReload);
    [installed addObject:[NSValue valueWithPointer:cls]];
    NSLog(@"[NahidaCompat] preference hooks registered in %@",NSProcessInfo.processInfo.processName);
}
static void HookRig(Class cls) {
    SEL sel=sel_registerName("initWithResourceURL:scheme:seed:freeGround:");
    Method m=class_getInstanceMethod(cls,sel);
    if (!Signature(m,6,"@") || !Arg(m,2,'@') || !Arg(m,3,'@') || !Arg(m,4,'I') || !Arg(m,5,'B')) return;
    IMP old=method_getImplementation(m);
    IMP replacement=imp_implementationWithBlock(^id(id obj,NSURL *url,id selection,unsigned int seed,BOOL freeGround) {
        typedef id(*Init)(id,SEL,NSURL *,id,unsigned int,BOOL);
        if (![selection isKindOfClass:NSString.class] || !IsNahida([[selection componentsSeparatedByString:@"-"] firstObject])) return ((Init)old)(obj,sel,url,selection,seed,freeGround);
        NSURL *privateRoot=[url URLByAppendingPathComponent:@"native/nahida" isDirectory:YES]; NSString *why=nil;
        @try {
            if (!url.isFileURL || !Validate(privateRoot,&why)) {
                NSLog(@"[NahidaCompat] nahida unavailable: %@ (root %@)",why ?: @"invalid URL",privateRoot.path);
                [obj release]; return (id)nil;
            }
            return ((Init)old)(obj,sel,privateRoot,@"nahida-nahida",seed,freeGround);
        } @catch (NSException *e) {
            NSLog(@"[NahidaCompat] nahida native load failed: %@ %@",e.name,e.reason);
            // Ownership after a foreign init throws is unknown: do not double-release.
            // A failed init may leak; it must never turn into a fake ready rig.
            return (id)nil;
        }
    });
    method_setImplementation(m,replacement); [installed addObject:[NSValue valueWithPointer:cls]];
    NSLog(@"[NahidaCompat] native rig hook registered (not runtime validated)");
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
