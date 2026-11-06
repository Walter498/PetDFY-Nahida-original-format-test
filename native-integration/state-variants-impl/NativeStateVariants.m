#import "NativeStateVariants.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <math.h>
#include <string.h>

#if !__has_feature(objc_arc)
#error NativeStateVariants.m requires -fobjc-arc
#endif

static char MarkKey, RendererKey;
static BOOL installed;
static __thread void *renderingRig;
static id Get(id o, const char *s) { return ((id(*)(id,SEL))objc_msgSend)(o,sel_registerName(s)); }
static void Put(id o,const char *s,id v) { ((void(*)(id,SEL,id))objc_msgSend)(o,sel_registerName(s),v); }
static void Run(id o,const char *s) { ((void(*)(id,SEL))objc_msgSend)(o,sel_registerName(s)); }
static id One(id o,const char *s,id v) { return ((id(*)(id,SEL,id))objc_msgSend)(o,sel_registerName(s),v); }
static BOOL Fail(NSError **e, NSString *s) {
    if(e) *e=[NSError errorWithDomain:@"NativeStateVariants" code:1
                            userInfo:@{NSLocalizedDescriptionKey:s}];
    return NO;
}
@interface NSVContext : NSObject
@property(nonatomic,strong) NSDictionary *base;
@property(nonatomic,strong) NSDictionary *variants;
@property(nonatomic,strong) NSURL *root;
@property(nonatomic,strong) NSDictionary *rollback;
@property(nonatomic,strong) NSString *failure;
@property(nonatomic) BOOL seated, changed, disabled;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL rollbackSeated;
@property(nonatomic) NSUInteger rollbackGeneration;
@end
@implementation NSVContext
@end
static NSVContext *Context(id r) { return objc_getAssociatedObject(r,&MarkKey); }
static BOOL Quad(id a, BOOL size) {
    if(![a isKindOfClass:NSArray.class] || [a count]!=4) return NO;
    for(id x in a) if(![x isKindOfClass:NSNumber.class] || !isfinite([x doubleValue])) return NO;
    return !size || ([a[2] doubleValue]>0 && [a[3] doubleValue]>0);
}
static BOOL SafeSrc(id s) {
    return [s isKindOfClass:NSString.class] && [s hasPrefix:@"schemes/nahida/tex/"] &&
      [s hasSuffix:@".png"] && ![s containsString:@".."] && ![s containsString:@"\\"] &&
      ![s containsString:@":"];
}
static NSDictionary *Snapshot(id r) {
    NSMutableDictionary *d=[NSMutableDictionary dictionary];
    for(NSString *key in @[@"model",@"compiledDeformers",@"localVertices",@"order",@"positions",@"alpha"])
        d[key]=Get(r,key.UTF8String) ?: NSNull.null;
    return d;
}
static void Restore(id r, NSDictionary *d) {
    NSDictionary *setters=@{@"model":@"setModel:",@"compiledDeformers":@"setCompiledDeformers:",
       @"localVertices":@"setLocalVertices:",@"order":@"setOrder:",@"positions":@"setPositions:",@"alpha":@"setAlpha:"};
    for(NSString *key in setters) Put(r,[setters[key] UTF8String], d[key]==NSNull.null ? nil : d[key]);
    // prepareDeformers rebuilds the matrices on the next original render.
    Ivar dirty=class_getInstanceVariable(object_getClass(r),"deformersDirty");
    if(dirty) *((BOOL *)((char *)(__bridge void *)r+ivar_getOffset(dirty)))=YES;
}
/* Preserve part count, order, id, parent, grid, faceFx and brow dictionaries exactly.
 * Only named fields are overlaid. Stand always starts from the saved immutable base,
 * so base z/rect/alpha (including absent keys) are restored without accumulating edits.
 */
static NSDictionary *Model(NSVContext *c, BOOL sit) {
    NSDictionary *v=c.variants[@"states"][sit ? @"sit" : @"stand"];
    NSMutableDictionary *m=[c.base mutableCopy];
    NSMutableArray *parts=[NSMutableArray array];
    NSSet *hidden=[NSSet setWithArray:v[@"hiddenParts"]];
    NSSet *visible=[NSSet setWithArray:v[@"visibleParts"]];
    for(NSDictionary *base in c.base[@"parts"]) {
        NSString *name=base[@"id"];
        NSMutableDictionary *p=[base mutableCopy];
        NSDictionary *rep=v[@"replacements"][name];
        // Stand replacements were validated against the effective base texture path.
        // Keep the raw base dictionary on return to stand (including absent src).
        if(sit) for(NSString *k in @[@"tex",@"src",@"box"]) if(rep[k]) p[k]=rep[k];
        if(v[@"zOverrides"][name]) p[@"z"]=v[@"zOverrides"][name];
        if([hidden containsObject:name]) p[@"alpha"]=@0;
        if([visible containsObject:name]) p[@"alpha"]=base[@"alpha"] ?: @1;
        [parts addObject:[p copy]];
    }
    m[@"parts"]=[parts copy];
    NSMutableDictionary *defs=[c.base[@"deformers"] mutableCopy];
    for(NSString *key in v[@"deformerRectOverrides"]) {
        NSMutableDictionary *d=[defs[key] mutableCopy];
        d[@"rect"]=v[@"deformerRectOverrides"][key]; defs[key]=[d copy];
    }
    m[@"deformers"]=[defs copy];
    return [m copy];
}
static void Mask(id r, NSVContext *c) {
    NSDictionary *v=c.variants[@"states"][c.seated ? @"sit" : @"stand"];
    NSArray *parts=Get(r,"model")[@"parts"];
    NSMutableArray *a=[Get(r,"alpha") mutableCopy];
    if(a.count!=parts.count) [NSException raise:@"NSVAlpha" format:@"part/alpha mismatch"];
    NSSet *hide=[NSSet setWithArray:v[@"hiddenParts"]], *show=[NSSet setWithArray:v[@"visibleParts"]];
    for(NSUInteger i=0;i<parts.count;i++) {
        NSString *key=parts[i][@"id"];
        if([hide containsObject:key]) a[i]=@0;
        else if([show containsObject:key]) a[i]=c.base[@"parts"][i][@"alpha"] ?: @1;
    }
    Put(r,"setAlpha:",[a copy]);
}
static void Transition(id r, NSVContext *c, BOOL sit) {
    if(c.disabled || c.seated==sit) return;
    NSDictionary *old=Snapshot(r);
    @try {
        Put(r,"setModel:",Model(c,sit));
        Run(r,"compileMesh"); // rebuild localVertices, z order AND compiledDeformers
        if(!c.rollback) { c.rollback=old; c.rollbackSeated=c.seated; c.rollbackGeneration=c.generation; }
        c.seated=sit; c.generation++; c.changed=YES;
    } @catch(NSException *ex) {
        Restore(r,old); c.disabled=YES; c.failure=ex.reason ?: ex.name;
    }
}
BOOL NSVMarkVerifiedNahidaRig(id r, NSURL *root, NSDictionary *v, NSError **error) {
    if(!installed) return Fail(error,@"Install candidate explicitly before marking");
    if(!r || object_getClass(r)!=NSClassFromString(@"WNLiveRig")) return Fail(error,@"Not the audited exact rig class");
    if(Context(r)) return Fail(error,@"Already marked; never recapture a seated model as stand");
    if(!root.isFileURL || ![root.path hasSuffix:@"/native/nahida"] ||
       ![Get(r,"scheme") isEqual:@"nahida"] || ![Get(r,"outfit") isEqual:@"nahida"])
        return Fail(error,@"Private validated nahida root/selection required");
    if(![v isKindOfClass:NSDictionary.class] || ![v[@"schema"] isEqual:@"same-master-state-variants/v1"])
        return Fail(error,@"Unsupported state contract");
    NSDictionary *base=Get(r,"model");
    if(![base[@"parts"] isKindOfClass:NSArray.class] || ![base[@"deformers"] isKindOfClass:NSDictionary.class])
        return Fail(error,@"Unexpected live model layout");
    NSMutableDictionary *byID=[NSMutableDictionary dictionary];
    for(NSDictionary *p in base[@"parts"]) {
        if(![p isKindOfClass:NSDictionary.class] || ![p[@"id"] isKindOfClass:NSString.class] || byID[p[@"id"]])
            return Fail(error,@"Invalid/duplicate part id");
        byID[p[@"id"]]=p;
    }
    NSSet *mutableParts=[NSSet setWithArray:@[@"torso_up",@"hair_back",@"arm_far",@"arm_near",@"skirt",@"skirt_sit",@"leg_back",@"leg_front"]];
    for(NSString *state in @[@"stand",@"sit"]) {
        NSDictionary *s=v[@"states"][state];
        if(![s isKindOfClass:NSDictionary.class] || ![s[@"hiddenParts"] isKindOfClass:NSArray.class] ||
           ![s[@"visibleParts"] isKindOfClass:NSArray.class] || ![s[@"replacements"] isKindOfClass:NSDictionary.class])
            return Fail(error,@"Missing state fields");
        for(NSString *key in [s[@"hiddenParts"] arrayByAddingObjectsFromArray:s[@"visibleParts"]])
            if(!byID[key] || ![mutableParts containsObject:key]) return Fail(error,@"Unsafe visibility target");
        for(NSString *key in s[@"replacements"]) {
            NSDictionary *p=s[@"replacements"][key];
            if(![@[@"torso_up",@"hair_back"] containsObject:key] || !byID[key] ||
               !SafeSrc(p[@"src"]) || ![p[@"tex"] isKindOfClass:NSString.class] || !Quad(p[@"box"],YES))
                return Fail(error,@"Invalid replacement");
            if([state isEqual:@"stand"])
                for(NSString *field in @[@"tex",@"src",@"box"])
                    {
                        id expected=byID[key][field];
                        // Native parts normally omit src; the validated contract
                        // spells out the same texture key's canonical relative path.
                        if([field isEqual:@"src"] && !expected)
                            expected=[NSString stringWithFormat:@"schemes/nahida/tex/%@.png",byID[key][@"tex"]];
                        if(![p[field] isEqual:expected]) return Fail(error,@"Stand baseline differs from validated variant");
                    }
        }
        for(NSString *key in s[@"zOverrides"])
            if(!byID[key] || ![mutableParts containsObject:key] ||
               ![s[@"zOverrides"][key] isKindOfClass:NSNumber.class] || !isfinite([s[@"zOverrides"][key] doubleValue]))
                return Fail(error,@"Unsafe z override");
        for(NSString *key in s[@"deformerRectOverrides"])
            if(![key isEqual:@"hairSway"] || !base[@"deformers"][key] || !Quad(s[@"deformerRectOverrides"][key],NO))
                return Fail(error,@"Unsafe deformer override");
    }
    // Deep immutable snapshot: never mutate the shared JSON parse or sourceModel.
    NSData *bytes=[NSJSONSerialization dataWithJSONObject:base options:0 error:error];
    if(!bytes) return NO;
    NSVContext *c=[NSVContext new];
    c.base=[NSJSONSerialization JSONObjectWithData:bytes options:0 error:error];
    bytes=[NSJSONSerialization dataWithJSONObject:v options:0 error:error];
    c.variants=bytes ? [NSJSONSerialization JSONObjectWithData:bytes options:0 error:error] : nil;
    if(!c.base || !c.variants) return NO;
    c.root=root; c.generation=1;
    // The source model intentionally has skirt_sit alpha=1. No transition occurs
    // for the default seated=NO, so mask NOW, before publishing even a paused rig.
    NSDictionary *old=Snapshot(r);
    @try { Mask(r,c); }
    @catch(NSException *ex) { Restore(r,old); return Fail(error,ex.reason ?: ex.name); }
    objc_setAssociatedObject(r,&MarkKey,c,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}
NSDictionary *NSVStatus(id r) {
    NSVContext *c=Context(r);
    return c ? @{@"marked":@YES,@"state":c.seated ? @"sit" : @"stand",@"generation":@(c.generation),
                 @"disabled":@(c.disabled),@"failure":c.failure ?: @"",
                 @"validation":@"static-offline-only",@"deviceValidated":@NO} :
               @{@"marked":@NO,@"validation":@"static-offline-only",@"deviceValidated":@NO};
}

/* Mirrors reset's part -> textureForPart -> meshesForParts sequence WITHOUT reset,
 * allocating a new rig, touching its motion, or clearing painter/__face surfaces.
 * Rebuild ALL meshes to preserve offsets and topology ordering. Old Metal resources
 * remain strongly held by already encoded commands; do not manually release buffers.
 */
static BOOL SyncRenderer(id renderer,id r,NSVContext *c) {
    NSDictionary *state=objc_getAssociatedObject(renderer,&RendererKey);
    if(state[@"rig"]==r && [state[@"generation"] unsignedIntegerValue]==c.generation) return YES;
    id clip=Get(renderer,"liveClip");
    id oldMeshes=Get(clip,"meshes");
    id oldBuffers=Get(renderer,"livePositionBuffers");
    @try {
        if(!clip) [NSException raise:@"NSVClip" format:@"missing live clip"];
        NSMutableArray *parts=[NSMutableArray array];
        for(NSDictionary *p in Get(r,"model")[@"parts"]) {
            NSMutableDictionary *copy=[p mutableCopy];
            id key=One(r,"textureForPart:",p); // uses the main module's private path hook
            if(![key isKindOfClass:NSString.class] || ![key length])
                [NSException raise:@"NSVTexture" format:@"missing texture key"];
            copy[@"texture"]=key; [parts addObject:copy];
        }
        id meshes=One(renderer,"meshesForParts:",parts);
        if(![meshes isKindOfClass:NSArray.class] || [meshes count]!=parts.count)
            [NSException raise:@"NSVMesh" format:@"mesh construction failed"];
        Put(clip,"setMeshes:",meshes);
        // Replace the slot dictionary rather than mutating old buffer objects.
        // Next preparedLiveClip obtains the caller's AVAILABLE slot and writes new data.
        Put(renderer,"setLivePositionBuffers:",[NSMutableDictionary dictionary]);
        objc_setAssociatedObject(renderer,&RendererKey,@{@"rig":r,@"generation":@(c.generation)},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        c.changed=NO; c.rollback=nil;
        return YES;
    } @catch(NSException *ex) {
        Put(clip,"setMeshes:",oldMeshes);
        Put(renderer,"setLivePositionBuffers:",oldBuffers);
        if(c.rollback) {
            Restore(r,c.rollback); c.seated=c.rollbackSeated; c.generation=c.rollbackGeneration;
            c.rollback=nil; c.changed=NO;
        }
        c.disabled=YES; c.failure=ex.reason ?: ex.name;
        return NO;
    }
}
static BOOL ABI(Class cls,const char *name,const char *encoding) {
    Method m=class_getInstanceMethod(cls,sel_registerName(name));
    return m && !strcmp(method_getTypeEncoding(m),encoding);
}
static BOOL Image(Class cls) {
    const char *p=class_getImageName(cls);
    return p && strstr(p,"/PetDFY.dylib");
}
BOOL NSVInstall(BOOL enable,NSError **error) {
    @synchronized(NSVContext.class) {
        if(installed) return YES;
        if(!enable) return Fail(error,@"BLOCKED: explicitly opt into static-only candidate; no device acceptance");
        Class rig=NSClassFromString(@"WNLiveRig"), motion=NSClassFromString(@"WNMotion"),
              renderer=NSClassFromString(@"WNRenderer"), clip=NSClassFromString(@"WNClip");
        if(!rig || !motion || !renderer || !clip || !Image(rig) || !Image(motion) || !Image(renderer) || !Image(clip))
            return Fail(error,@"Audited PetDFY classes not registered");
        if(!ABI(rig,"renderBuildingMesh:","v20@0:8B16") || !ABI(motion,"render","v16@0:8") ||
           !ABI(motion,"frame","@16@0:8") || !ABI(renderer,"preparedLiveClipForCommand:slot:","@32@0:8@16Q24") ||
           !ABI(renderer,"meshesForParts:","@24@0:8@16") || !ABI(rig,"textureForPart:","@24@0:8@16"))
            return Fail(error,@"Render ABI mismatch");
        for(NSString *s in @[@"compileMesh",@"updateMesh"])
            if(!ABI(rig,s.UTF8String,"v16@0:8")) return Fail(error,@"Rig builder ABI mismatch");
        for(NSString *s in @[@"model",@"compiledDeformers",@"localVertices",@"order",@"positions",@"alpha",@"motion",@"scheme",@"outfit"])
            if(!ABI(rig,s.UTF8String,"@16@0:8")) return Fail(error,@"Rig getter ABI mismatch");
        for(NSString *s in @[@"setModel:",@"setCompiledDeformers:",@"setLocalVertices:",@"setOrder:",@"setPositions:",@"setAlpha:"])
            if(!ABI(rig,s.UTF8String,"v24@0:8@16")) return Fail(error,@"Rig setter ABI mismatch");
        for(NSString *s in @[@"liveRig",@"liveClip",@"livePositionBuffers"])
            if(!ABI(renderer,s.UTF8String,"@16@0:8")) return Fail(error,@"Renderer getter ABI mismatch");
        if(!ABI(renderer,"setLivePositionBuffers:","v24@0:8@16") || !ABI(clip,"meshes","@16@0:8") ||
           !ABI(clip,"setMeshes:","v24@0:8@16")) return Fail(error,@"Clip/slot ABI mismatch");
        Ivar dirty=class_getInstanceVariable(rig,"deformersDirty");
        if(!dirty || strcmp(ivar_getTypeEncoding(dirty),"B")) return Fail(error,@"Dirty flag ABI mismatch");
        SEL rs=sel_registerName("renderBuildingMesh:"), ms=sel_registerName("render"),
            ps=sel_registerName("preparedLiveClipForCommand:slot:");
        Method rm=class_getInstanceMethod(rig,rs), mm=class_getInstanceMethod(motion,ms), pm=class_getInstanceMethod(renderer,ps);
        IMP oldR=method_getImplementation(rm), oldM=method_getImplementation(mm), oldP=method_getImplementation(pm);
        IMP newM=imp_implementationWithBlock(^(id obj) {
            ((void(*)(id,SEL))oldM)(obj,ms);
            id r=(__bridge id)renderingRig;
            NSVContext *c=Context(r);
            if(!c || c.disabled || Get(r,"motion")!=obj) return;
            id sit=Get(obj,"frame")[@"sit"];
            if(![sit isKindOfClass:NSNumber.class] || !isfinite([sit doubleValue])) {
                c.disabled=YES; c.failure=@"Missing/nonfinite native frame.sit"; return;
            }
            Transition(r,c,[sit doubleValue]>=0.5);
        });
        IMP newR=imp_implementationWithBlock(^(id r,BOOL build) {
            NSVContext *c=Context(r);
            if(!c || c.disabled) { ((void(*)(id,SEL,BOOL))oldR)(r,rs,build); return; }
            NSDictionary *before=Snapshot(r);
            BOOL beforeSeated=c.seated; NSUInteger beforeGeneration=c.generation;
            void *prior=renderingRig; renderingRig=(__bridge void *)r;
            @try {
                ((void(*)(id,SEL,BOOL))oldR)(r,rs,build);
                if(!c.disabled) {
                    Mask(r,c); // discrete visibility targets only, after native alpha
                    if(c.changed && !build) Run(r,"updateMesh");
                }
                // A compile failure caught inside Transition must not leak the
                // remainder of oldR's partially recomputed arrays into submission.
                if(c.disabled) {
                    Restore(r,c.rollback ?: before);
                    c.seated=c.rollback ? c.rollbackSeated : beforeSeated;
                    c.generation=c.rollback ? c.rollbackGeneration : beforeGeneration;
                    c.rollback=nil; c.changed=NO;
                }
            } @catch(NSException *ex) {
                Restore(r,c.rollback ?: before);
                c.seated=c.rollback ? c.rollbackSeated : beforeSeated;
                c.generation=c.rollback ? c.rollbackGeneration : beforeGeneration;
                c.rollback=nil; c.changed=NO;
                c.disabled=YES; c.failure=ex.reason ?: ex.name;
            } @finally { renderingRig=prior; }
        });
        IMP newP=imp_implementationWithBlock(^id(id obj,id command,NSUInteger slot) {
            id r=Get(obj,"liveRig"); NSVContext *c=Context(r);
            // Audited arm64/arm64e drawInMTKView: steps/renders BEFORE this call;
            // oldP paints surfaces and copies positions/order/alpha, but never
            // steps/renders the rig. Keep sync BEFORE oldP (not after its blits).
            // Mask again for first/paused frames that have no render callback.
            if(c) {
                if(c.disabled) return nil;
                @try { Mask(r,c); }
                @catch(NSException *ex) {
                    if(c.rollback) {
                        Restore(r,c.rollback); c.seated=c.rollbackSeated;
                        c.generation=c.rollbackGeneration; c.rollback=nil; c.changed=NO;
                    }
                    c.disabled=YES; c.failure=ex.reason ?: ex.name; return nil;
                }
                if(!SyncRenderer(obj,r,c)) return nil;
            }
            return ((id(*)(id,SEL,id,NSUInteger))oldP)(obj,ps,command,slot);
        });
        if(!newM || !newR || !newP) {
            if(newM) imp_removeBlock(newM); if(newR) imp_removeBlock(newR); if(newP) imp_removeBlock(newP);
            return Fail(error,@"IMP block creation failed");
        }
        method_setImplementation(mm,newM); method_setImplementation(rm,newR); method_setImplementation(pm,newP);
        installed=YES; return YES;
    }
}
