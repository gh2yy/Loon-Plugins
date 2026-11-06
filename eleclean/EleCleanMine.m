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
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- v5 diagnostics: counters surfaced in an on-device alert ----
static int gJsonCalls = 0, gBodyCalls = 0, gParseCalls = 0, gParseCardsCalls = 0, gBridgeCalls = 0;
static BOOL gPersonalSeen = NO;
static NSMutableString *gSeenApis = nil;
static NSString *gSubclassInfo = @"";
static void ECNoteApi(NSString *api) {
    if (api == nil) return;
    if (gSeenApis == nil) gSeenApis = [NSMutableString string];
    if ([gSeenApis rangeOfString:api].location == NSNotFound && [gSeenApis length] < 400) {
        [gSeenApis appendFormat:@"%@ ", api];
    }
    if ([api hasPrefix:@"mtop.alsc.personal."]) gPersonalSeen = YES;
}
#import <dispatch/dispatch.h>

static BOOL ELTextHasMarker(NSString *s) {
    if (![s isKindOfClass:[NSString class]]) return NO;
    return [s containsString:@"互动中心"] ||
           [s containsString:@"口味"] ||
           [s containsString:@"ai_profile"] ||
           [s containsString:@"interact_center"] ||
           [s containsString:@"INTERACT"] ||
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
        if (data == nil) {
            // Result IS the payload (no wrapper): filter/empty it directly.
            return isFeeds ? ELEmptyFeedsData(res) : ELFilterModules(res, 0);
        }
        if (isFeeds) {
            res[@"data"] = ELEmptyFeedsData(data);
        } else {
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
    gBridgeCalls++;
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

// ---------------------------------------------------------------------------
// Personal center, second hook point (the v3 build's WindVane-bridge hook
// did not fire for this page on device): every MTOP response in the app is
// an MtopExtResponse, and its -json is what callers consume. The response
// knows its own request, hence the API name, so filtering here covers the
// WindVane, Weex/MUS and native senders alike.

static NSString *ECApiNameFromObject(id obj, int depth) {
    if (obj == nil || depth > 3) return nil;
    SEL getApi = NSSelectorFromString(@"getApiName");
    if ([obj respondsToSelector:getApi]) {
        id v = ((id (*)(id, SEL))objc_msgSend)(obj, getApi);
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
    }
    SEL apiNameSel = NSSelectorFromString(@"apiName");
    if ([obj respondsToSelector:apiNameSel]) {
        id v = ((id (*)(id, SEL))objc_msgSend)(obj, apiNameSel);
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) return v;
    }
    if ([obj respondsToSelector:@selector(request)]) {
        return ECApiNameFromObject([obj request], depth + 1);
    }
    return nil;
}

typedef id (*ECJsonIMP)(id, SEL);
static ECJsonIMP gOrigJson = NULL;

static id ECFilterResponseObject(id self, id payload) {
    if (![payload isKindOfClass:[NSDictionary class]]) return payload;
    NSString *api = ECApiNameFromObject(self, 0);
    ECNoteApi(api);
    if (api != nil &&
        ([api hasPrefix:@"mtop.alsc.personal.queryMineCenter"] ||
         [api hasPrefix:@"mtop.alsc.personal.collectMineCenterFeeds"])) {
        return ELProcessResult(api, payload);
    }
    return payload;
}

static id ECJsonReplacement(id self, SEL _cmd) {
    gJsonCalls++;
    id json = gOrigJson ? gOrigJson(self, _cmd) : nil;
    @try {
        return ECFilterResponseObject(self, json);
    } @catch (NSException *e) {
    }
    return json;
}

typedef id (*ECBodyIMP)(id, SEL);
static ECBodyIMP gOrigBody = NULL;

static id ECBodyReplacement(id self, SEL _cmd) {
    gBodyCalls++;
    id body = gOrigBody ? gOrigBody(self, _cmd) : nil;
    @try {
        return ECFilterResponseObject(self, body);
    } @catch (NSException *e) {
    }
    return body;
}

static BOOL ECInstallBody(void) {
    if (gOrigBody != NULL) return YES;
    Class cls = objc_getClass("MtopExtResponse");
    if (cls == Nil) return NO;
    Method m = class_getInstanceMethod(cls, @selector(body));
    if (m == NULL) return NO;
    gOrigBody = (ECBodyIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ECBodyReplacement);
    return YES;
}

static BOOL ECInstallJson(void) {
    if (gOrigJson != NULL) return YES;
    Class cls = objc_getClass("MtopExtResponse");
    if (cls == Nil) return NO;
    Method m = class_getInstanceMethod(cls, @selector(json));
    if (m == NULL) return NO;
    gOrigJson = (ECJsonIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ECJsonReplacement);
    return YES;
}

typedef void (*ECParseIMP)(id, SEL, id, id, id);
static ECParseIMP gOrigParse = NULL;

static void ECParseReplacement(id self, SEL _cmd, id page, id data, id completion) {
    gParseCalls++;
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

typedef id (*ECParseCardsIMP)(id, SEL, id);
static ECParseCardsIMP gOrigParseCards = NULL;

static id ECParseCardsReplacement(id self, SEL _cmd, id cards) {
    gParseCardsCalls++;
    id clean = cards;
    @try {
        if ([cards isKindOfClass:[NSArray class]] &&
            ([(NSArray *)cards count] == 0 || [[(NSArray *)cards firstObject] isKindOfClass:[NSDictionary class]])) {
            clean = ECSanitizePageData(cards, 0);
        }
    } @catch (NSException *e) {
        clean = cards;
    }
    return gOrigParseCards ? gOrigParseCards(self, _cmd, clean) : clean;
}

static BOOL ECInstallParseCards(void) {
    if (gOrigParseCards != NULL) return YES;
    Class cls = objc_getClass("LMXTransformerParser");
    if (cls == Nil) return NO;
    SEL sel = NSSelectorFromString(@"parseCardModels:");
    Method m = class_getInstanceMethod(cls, sel);
    if (m == NULL) return NO;
    gOrigParseCards = (ECParseCardsIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ECParseCardsReplacement);
    return YES;
}

static void ECShowDiag(void) {
    NSString *msg = [NSString stringWithFormat:
        @"json=%d body=%d parse=%d parseCards=%d bridge=%d\npersonalAPI=%@\n%@\napis: %@",
        gJsonCalls, gBodyCalls, gParseCalls, gParseCardsCalls, gBridgeCalls,
        gPersonalSeen ? @"YES" : @"NO", gSubclassInfo,
        gSeenApis ?: @""];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"EleClean v5 诊断"
        message:msg preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    UIWindow *key = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { key = w; break; }
    }
    if (key == nil) key = [[UIApplication sharedApplication].windows firstObject];
    UIViewController *top = key.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    if (top) [top presentViewController:ac animated:YES completion:nil];
}

__attribute__((constructor)) static void ELEntry(void) {
    @autoreleasepool {
        BOOL a = ELInstall();
        BOOL b = ECInstallParse();
        BOOL c = ECInstallJson();
        ECInstallBody();
        ECInstallParseCards();
        if (!a || !b || !c) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ELInstall();
                ECInstallParse();
                ECInstallJson();
                ECInstallBody();
                ECInstallParseCards();
            });
        }
        // Subclass override check for the diagnostic readout.
        {
            Class base = objc_getClass("MtopExtResponse");
            IMP baseJson = base ? method_getImplementation(class_getInstanceMethod(base, @selector(json))) : NULL;
            NSMutableString *info = [NSMutableString string];
            for (NSString *name in @[@"LTFMtopExtResponse", @"LUEFMtopExtResponse"]) {
                Class sub = objc_getClass(name.UTF8String);
                if (sub == Nil) { [info appendFormat:@"%@:none ", name]; continue; }
                IMP ij = method_getImplementation(class_getInstanceMethod(sub, @selector(json)));
                [info appendFormat:@"%@:%@ ", name, (ij == baseJson) ? @"inherited" : @"OWN"];
            }
            gSubclassInfo = [info copy];
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ECShowDiag();
        });
    }
}
