// EleCleanMine — removes three sections from the personal center ("我的")
// page of Taobao Flash (eleme) 12.10.38: 互动中心, 口味档案, 推荐商品.
//
// The personal center is a WindVane/H5 page (eatPersonal). Its data comes
// from MTOP through the native WindVane bridge plugin
// -[MtopBridgePlugin sendMtopRequest:callBack:ext:], where the request is
// an NSDictionary carrying @"api" and the callback receives the MTOP
// result NSDictionary.
//
//   mtop.alsc.personal.queryMineCenter        -> drop modules whose
//      subtree mentions 互动中心 or the flavor profile (口味档案 / 口味偏好,
//      JS-side bizCode "ai_profile", component FlavorProfile).
//   mtop.alsc.personal.queryMineCenterFeeds   -> empty the payload
//   mtop.alsc.personal.collectMineCenterFeeds -> empty the payload
//      (the whole feeds stream is the 推荐商品 waterfall; the page JS has
//      an explicit empty-recall state, so an empty payload is safe).
//
// Fail-open: any unexpected shape passes data through untouched, and
// non-matching APIs are not even wrapped.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

static BOOL ELTextHasMarker(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return NO;
    return [s containsString:@"互动中心"] ||
           [s containsString:@"口味档案"] ||
           [s containsString:@"口味偏好"] ||
           [s containsString:@"ai_profile"] ||
           [s rangeOfString:@"flavor" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL ELSubtreeHasMarker(id obj, int depth) {
    if (obj == nil || depth > 10) return NO;
    if ([obj isKindOfClass:[NSString class]]) return ELTextHasMarker((NSString *)obj);
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            if (ELSubtreeHasMarker(k, depth + 1)) return YES;
            if (ELSubtreeHasMarker(((NSDictionary *)obj)[k], depth + 1)) return YES;
        }
        return NO;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) {
            if (ELSubtreeHasMarker(e, depth + 1)) return YES;
        }
        return NO;
    }
    return NO;
}

static id ELFilterModules(id obj, int depth) {
    if (obj == nil || depth > 10) return obj;
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:((NSArray *)obj).count];
        for (id e in (NSArray *)obj) {
            if (ELSubtreeHasMarker(e, depth + 1)) continue;
            [out addObject:ELFilterModules(e, depth + 1)];
        }
        return out;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        for (id k in (NSDictionary *)obj) {
            out[k] = ELFilterModules(((NSDictionary *)obj)[k], depth + 1);
        }
        return out;
    }
    return obj;
}

static id ELEmptyFeedsData(id data) {
    if (![data isKindOfClass:[NSDictionary class]]) return @{};
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    for (id k in (NSDictionary *)data) {
        id v = ((NSDictionary *)data)[k];
        if ([v isKindOfClass:[NSArray class]]) { out[k] = @[]; continue; }
        if ([v isKindOfClass:[NSDictionary class]]) { out[k] = ELEmptyFeedsData(v); continue; }
        if ([v isKindOfClass:[NSNumber class]]) { out[k] = @0; continue; }
        out[k] = v;
    }
    return out;
}

static id ELProcessResult(NSString *api, id result) {
    if (![result isKindOfClass:[NSDictionary class]]) return result;
    @try {
        BOOL isFeeds = [api hasPrefix:@"mtop.alsc.personal.queryMineCenterFeeds"] ||
                       [api hasPrefix:@"mtop.alsc.personal.collectMineCenterFeeds"];
        BOOL isMain = [api hasPrefix:@"mtop.alsc.personal.queryMineCenter"] && !isFeeds;
        if (!isFeeds && !isMain) return result;
        NSMutableDictionary *res = [((NSDictionary *)result) mutableCopy];
        id data = res[@"data"];
        if (isFeeds) {
            res[@"data"] = ELEmptyFeedsData(data);
        } else if (data != nil) {
            res[@"data"] = ELFilterModules(data, 0);
        }
        return res;
    } @catch (NSException *e) {
        return result;
    }
}

typedef void (^ELWVCallBack)(id result);
typedef void (*ELSendIMP)(id, SEL, id, ELWVCallBack, id);
static ELSendIMP gOrigSend = NULL;

static void ELSendMtopRequest(id self, SEL _cmd, id request, ELWVCallBack callBack, id ext) {
    NSString *api = nil;
    if ([request isKindOfClass:[NSDictionary class]]) {
        id a = ((NSDictionary *)request)[@"api"];
        if ([a isKindOfClass:[NSString class]]) api = a;
    }
    BOOL target = api != nil &&
        ([api hasPrefix:@"mtop.alsc.personal.queryMineCenter"] ||
         [api hasPrefix:@"mtop.alsc.personal.collectMineCenterFeeds"]);
    if (!target || callBack == nil) {
        gOrigSend(self, _cmd, request, callBack, ext);
        return;
    }
    NSString *apiCopy = [api copy];
    ELWVCallBack wrapped = ^(id result) {
        callBack(ELProcessResult(apiCopy, result));
    };
    gOrigSend(self, _cmd, request, wrapped, ext);
}

static BOOL ELInstall(void) {
    Class cls = objc_getClass("MtopBridgePlugin");
    if (cls == Nil) return NO;
    SEL sel = @selector(sendMtopRequest:callBack:ext:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m == NULL) return NO;
    if (gOrigSend != NULL) return YES;
    gOrigSend = (ELSendIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ELSendMtopRequest);
    return YES;
}

// ---------------------------------------------------------------------------
// Homepage banner strip ("广告场景卡"): the strip is a card in the LMagex
// page data (bizCode home_sceneCard*_advertisement*, templateId 3102). Every
// LMagex page's raw data passes through
// -[LMXTransformerParser parse:data:completion:] before card models are
// built, so stripping the card dicts there kills the strip regardless of
// which transport/prefetch/cache path delivered the data. Matching is on
// the card dict's own bizCode only, so shop cards are untouched.

static BOOL ECIsAdSceneCard(id obj) {
    if (![obj isKindOfClass:[NSDictionary class]]) return NO;
    id biz = [(NSDictionary *)obj objectForKey:@"bizCode"];
    if (![biz isKindOfClass:[NSString class]]) return NO;
    NSString *b = (NSString *)biz;
    return [b hasPrefix:@"home_sceneCard"] &&
           [b rangeOfString:@"advertisement"].location != NSNotFound;
}

static id ECSanitizePageData(id obj, int depth) {
    if (obj == nil || depth > 12) return obj;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:((NSDictionary *)obj).count];
        for (id k in (NSDictionary *)obj) {
            out[k] = ECSanitizePageData(((NSDictionary *)obj)[k], depth + 1);
        }
        return out;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:((NSArray *)obj).count];
        for (id e in (NSArray *)obj) {
            if (ECIsAdSceneCard(e)) continue;
            [out addObject:ECSanitizePageData(e, depth + 1)];
        }
        return out;
    }
    return obj;
}

typedef void (*ECParseIMP)(id, SEL, id, id, id);
static ECParseIMP gOrigParse = NULL;

static void ECParseReplacement(id self, SEL _cmd, id page, id data, id completion) {
    id clean = data;
    @try {
        if ([data isKindOfClass:[NSDictionary class]] || [data isKindOfClass:[NSArray class]]) {
            clean = ECSanitizePageData(data, 0);
        }
    } @catch (NSException *e) {
        clean = data;
    }
    if (gOrigParse) gOrigParse(self, _cmd, page, clean, completion);
}

static BOOL ECInstallParse(void) {
    if (gOrigParse != NULL) return YES;
    Class cls = objc_getClass("LMXTransformerParser");
    if (cls == Nil) return NO;
    SEL sel = NSSelectorFromString(@"parse:data:completion:");
    Method m = class_getInstanceMethod(cls, sel);
    if (m == NULL) return NO;
    gOrigParse = (ECParseIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ECParseReplacement);
    return YES;
}

__attribute__((constructor)) static void ELEntry(void) {
    @autoreleasepool {
        BOOL a = ELInstall();
        BOOL b = ECInstallParse();
        if (!a || !b) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ELInstall();
                ECInstallParse();
            });
        }
    }
}
