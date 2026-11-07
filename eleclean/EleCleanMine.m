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

// ---- diagnostics: counters surfaced in an on-device alert ----
static int gJsonCalls = 0, gBodyCalls = 0, gParseCalls = 0, gParseCardsCalls = 0, gBridgeCalls = 0;
static int gJsonSubCalls = 0, gTsfmCalls = 0, gMistCalls = 0;
static BOOL gPersonalSeen = NO;
static NSMutableString *gSeenApis = nil;
static NSMutableString *gPersonalVia = nil;
static NSMutableString *gDroppedBiz = nil;
static NSString *gSubclassInfo = @"";
static void ECNoteApi(NSString *api) {
    if (api == nil) return;
    if (gSeenApis == nil) gSeenApis = [NSMutableString string];
    if ([gSeenApis rangeOfString:api].location == NSNotFound && [gSeenApis length] < 400) {
        [gSeenApis appendFormat:@"%@ ", api];
    }
    if ([api hasPrefix:@"mtop.alsc.personal."]) gPersonalSeen = YES;
}
static void ECNotePersonalVia(NSString *clsName) {
    if (gPersonalVia == nil) gPersonalVia = [NSMutableString string];
    if ([gPersonalVia rangeOfString:clsName].location == NSNotFound) {
        [gPersonalVia appendFormat:@"%@ ", clsName];
    }
}

// v7 diagnostics
static NSMutableString *gPersonalApis = nil;
static NSMutableString *gCardBiz = nil;
static int gFilteredCount = 0, gCardModelCalls = 0, gMusCalls = 0;
static void ECNotePersonalApi(NSString *api) {
    if (api == nil) return;
    if (gPersonalApis == nil) gPersonalApis = [NSMutableString string];
    if ([gPersonalApis rangeOfString:api].location == NSNotFound && [gPersonalApis length] < 500) {
        [gPersonalApis appendFormat:@"%@ ", api];
    }
}
static void ECNoteCardBiz(NSString *biz, id tpl) {
    if (gCardBiz == nil) gCardBiz = [NSMutableString string];
    NSString *entry = [NSString stringWithFormat:@"%@(%@)", biz ?: @"?", tpl ?: @"?"];
    if ([gCardBiz rangeOfString:entry].location == NSNotFound && [gCardBiz length] < 700) {
        [gCardBiz appendFormat:@"%@ ", entry];
    }
}
static void ECNoteDropped(NSString *biz) {
    if (biz == nil) biz = @"?";
    if (gDroppedBiz == nil) gDroppedBiz = [NSMutableString string];
    if ([gDroppedBiz rangeOfString:biz].location == NSNotFound && [gDroppedBiz length] < 300) {
        [gDroppedBiz appendFormat:@"%@ ", biz];
    }
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
        NSString *apiL = [api lowercaseString];
        BOOL isFeeds = [apiL hasPrefix:@"mtop.alsc.personal.queryminecenterfeeds"] ||
                       [apiL hasPrefix:@"mtop.alsc.personal.collectminecenterfeeds"] ||
                       ([apiL containsString:@"minecenter"] && [apiL containsString:@"feeds"]);
        BOOL isMain = [apiL hasPrefix:@"mtop.alsc.personal."] && !isFeeds;
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
        for (NSString *key in @[@"api", @"apiName", @"name", @"method"]) {
            id a = ((NSDictionary *)request)[key];
            if ([a isKindOfClass:[NSString class]] && [(NSString *)a hasPrefix:@"mtop."]) { api = a; break; }
        }
        if (api == nil) {
            // Fall back to scanning values for a personal API name.
            for (id v in [(NSDictionary *)request allValues]) {
                if ([v isKindOfClass:[NSString class]] &&
                    [(NSString *)v rangeOfString:@"queryminecenter"].location != NSNotFound) { api = v; break; }
            }
        }
    }
    BOOL target = api != nil && [[api lowercaseString] hasPrefix:@"mtop.alsc.personal."];
    if (target) ECNotePersonalApi([@"bridge:" stringByAppendingString:api]);
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
    return [b rangeOfString:@"advertisement"].location != NSNotFound;
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
            if (ECIsAdSceneCard(e)) {
                ECNoteDropped([(NSDictionary *)e objectForKey:@"bizCode"]);
                continue;
            }
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
    if (api != nil && [[api lowercaseString] hasPrefix:@"mtop.alsc.personal."]) {
        ECNotePersonalApi(api);
        ECNotePersonalVia(NSStringFromClass([self class]));
        id out = ELProcessResult(api, payload);
        if (out != payload) gFilteredCount++;
        return out;
    }
    return payload;
}

// LTF/LUEF response subclasses have their OWN -json/-body (v5 diag: OWN),
// so the base-class hooks never see their payloads. Install per-class too.
static NSMutableDictionary *gOrigMap = nil;
static int gBodySubCalls = 0;

static id ECJsonSubReplacement(id self, SEL _cmd) {
    gJsonSubCalls++;
    NSString *key = [NSStringFromClass([self class]) stringByAppendingString:@":json"];
    IMP orig = (IMP)[gOrigMap[key] pointerValue];
    id v = orig ? ((id (*)(id, SEL))orig)(self, _cmd) : nil;
    @try { return ECFilterResponseObject(self, v); } @catch (NSException *e) { }
    return v;
}

static id ECBodySubReplacement(id self, SEL _cmd) {
    gBodySubCalls++;
    NSString *key = [NSStringFromClass([self class]) stringByAppendingString:@":body"];
    IMP orig = (IMP)[gOrigMap[key] pointerValue];
    id v = orig ? ((id (*)(id, SEL))orig)(self, _cmd) : nil;
    @try { return ECFilterResponseObject(self, v); } @catch (NSException *e) { }
    return v;
}

static void ECInstallSubclassHooks(void) {
    if (gOrigMap == nil) gOrigMap = [NSMutableDictionary dictionary];
    for (NSString *name in @[@"LTFMtopExtResponse", @"LUEFMtopExtResponse"]) {
        Class cls = objc_getClass(name.UTF8String);
        if (cls == Nil) continue;
        for (NSString *selName in @[@"json", @"body"]) {
            NSString *key = [name stringByAppendingFormat:@":%@", selName];
            if (gOrigMap[key] != nil) continue;
            Method m = class_getInstanceMethod(cls, NSSelectorFromString(selName));
            if (m == NULL) continue;
            gOrigMap[key] = [NSValue valueWithPointer:method_getImplementation(m)];
            method_setImplementation(m, (IMP)([selName isEqualToString:@"json"]
                ? ECJsonSubReplacement : ECBodySubReplacement));
        }
    }
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

// ---------------------------------------------------------------------------
// LMagex page data entry points actually used by this build (v5 diag:
// LMXTransformerParser parse* were never called; home runs on TSFM data).
// -[LMXLoadTask setTsfmPageData:] receives the whole page dict;
// -[LMagexController loadMistPageWithData:completion:] / refresh variant
// cover the non-TSFM Mist pages. Sanitize at these doors instead.

typedef void (*ECSetDataIMP)(id, SEL, id);
static ECSetDataIMP gOrigSetTsfm = NULL;

static void ECSetTsfmReplacement(id self, SEL _cmd, id data) {
    gTsfmCalls++;
    id clean = data;
    @try {
        if ([data isKindOfClass:[NSDictionary class]] || [data isKindOfClass:[NSArray class]]) {
            clean = ECSanitizePageData(data, 0);
        }
    } @catch (NSException *e) { clean = data; }
    if (gOrigSetTsfm) gOrigSetTsfm(self, _cmd, clean);
}

typedef void (*ECLoadMistIMP)(id, SEL, id, id);
static ECSetDataIMP gOrigLoadMist = NULL;
static ECSetDataIMP gOrigRefreshMist = NULL;

static void ECLoadMistReplacement(id self, SEL _cmd, id data, id completion) {
    gMistCalls++;
    id clean = data;
    @try {
        if ([data isKindOfClass:[NSDictionary class]] || [data isKindOfClass:[NSArray class]]) {
            clean = ECSanitizePageData(data, 0);
        }
    } @catch (NSException *e) { clean = data; }
    if (gOrigLoadMist) ((ECLoadMistIMP)gOrigLoadMist)(self, _cmd, clean, completion);
}

static void ECRefreshMistReplacement(id self, SEL _cmd, id data, id completion) {
    gMistCalls++;
    id clean = data;
    @try {
        if ([data isKindOfClass:[NSDictionary class]] || [data isKindOfClass:[NSArray class]]) {
            clean = ECSanitizePageData(data, 0);
        }
    } @catch (NSException *e) { clean = data; }
    if (gOrigRefreshMist) ((ECLoadMistIMP)gOrigRefreshMist)(self, _cmd, clean, completion);
}

static void ECInstallPageDataHooks(void) {
    if (gOrigSetTsfm == NULL) {
        Class cls = objc_getClass("LMXLoadTask");
        Method m = cls ? class_getInstanceMethod(cls, NSSelectorFromString(@"setTsfmPageData:")) : NULL;
        if (m) {
            gOrigSetTsfm = (ECSetDataIMP)method_getImplementation(m);
            method_setImplementation(m, (IMP)ECSetTsfmReplacement);
        }
    }
    Class ctl = objc_getClass("LMagexController");
    if (ctl != Nil) {
        if (gOrigLoadMist == NULL) {
            Method m = class_getInstanceMethod(ctl, NSSelectorFromString(@"loadMistPageWithData:completion:"));
            if (m) {
                gOrigLoadMist = (ECSetDataIMP)method_getImplementation(m);
                method_setImplementation(m, (IMP)ECLoadMistReplacement);
            }
        }
        if (gOrigRefreshMist == NULL) {
            Method m = class_getInstanceMethod(ctl, NSSelectorFromString(@"refreshMistPageWithData:completion:"));
            if (m) {
                gOrigRefreshMist = (ECSetDataIMP)method_getImplementation(m);
                method_setImplementation(m, (IMP)ECRefreshMistReplacement);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// v7 probes: (1) record bizCode/templateId of every LMXCardModel built from a
// Mist node (covers LMagex pages incl. home); (2) watch the Weex MUS mtop
// module for personal APIs (the eatPersonal page's likely carrier).

typedef id (*ECCardFactoryIMP)(id, SEL, id);
static ECCardFactoryIMP gOrigCardFactory = NULL;

static id ECCardFactoryReplacement(id cls, SEL _cmd, id node) {
    gCardModelCalls++;
    id model = gOrigCardFactory ? gOrigCardFactory(cls, _cmd, node) : nil;
    @try {
        if (model != nil) {
            NSString *biz = nil; id tpl = nil;
            SEL bizSel = NSSelectorFromString(@"bizCode");
            if ([model respondsToSelector:bizSel]) {
                biz = ((id (*)(id, SEL))objc_msgSend)(model, bizSel);
            }
            SEL tplSel = NSSelectorFromString(@"templateId");
            if ([model respondsToSelector:tplSel]) {
                tpl = ((id (*)(id, SEL))objc_msgSend)(model, tplSel);
            }
            ECNoteCardBiz(biz, tpl);
        }
    } @catch (NSException *e) { }
    return model;
}

static BOOL ECInstallCardProbe(void) {
    if (gOrigCardFactory != NULL) return YES;
    Class cls = objc_getClass("LMXCardModel");
    if (cls == Nil) return NO;
    Method m = class_getClassMethod(cls, NSSelectorFromString(@"modelWithMPCustomNode:"));
    if (m == NULL) return NO;
    gOrigCardFactory = (ECCardFactoryIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ECCardFactoryReplacement);
    return YES;
}

static void ECScanDescriptionForPersonalApi(id obj) {
    if (obj == nil) return;
    @try {
        NSString *desc = [obj description];
        NSRange r = [desc rangeOfString:@"mtop.alsc.personal."];
        if (r.location != NSNotFound) {
            NSUInteger end = r.location;
            while (end < [desc length]) {
                unichar c = [desc characterAtIndex:end];
                if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                      (c >= '0' && c <= '9') || c == '.' || c == '_')) break;
                end++;
            }
            ECNotePersonalApi([@"MUS:" stringByAppendingString:
                [desc substringWithRange:NSMakeRange(r.location, end - r.location)]]);
        }
    } @catch (NSException *e) { }
}

typedef void (*ECMusReqIMP)(id, SEL, id, id, id);
static ECMusReqIMP gOrigMusReq = NULL;
static void ECMusReqReplacement(id self, SEL _cmd, id req, id success, id failure) {
    gMusCalls++;
    ECScanDescriptionForPersonalApi(req);
    if (gOrigMusReq) gOrigMusReq(self, _cmd, req, success, failure);
}

typedef void (*ECMusSendIMP)(id, SEL, id, id);
static ECMusSendIMP gOrigMusSend = NULL;
static void ECMusSendReplacement(id self, SEL _cmd, id req, id callback) {
    gMusCalls++;
    ECScanDescriptionForPersonalApi(req);
    if (gOrigMusSend) gOrigMusSend(self, _cmd, req, callback);
}

static void ECInstallMusProbe(void) {
    Class cls = objc_getClass("MUSMtopModule");
    if (cls == Nil) return;
    if (gOrigMusReq == NULL) {
        Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"request:success:failure:"));
        if (m) {
            gOrigMusReq = (ECMusReqIMP)method_getImplementation(m);
            method_setImplementation(m, (IMP)ECMusReqReplacement);
        }
    }
    if (gOrigMusSend == NULL) {
        Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"send:callback:"));
        if (m) {
            gOrigMusSend = (ECMusSendIMP)method_getImplementation(m);
            method_setImplementation(m, (IMP)ECMusSendReplacement);
        }
    }
}

static void ECShowDiag(void) {
    // Fully dynamic UIKit access: the CI link line only has Foundation.
    NSString *msg = [NSString stringWithFormat:
        @"json=%d sub=%d tsfm=%d mist=%d bridge=%d mus=%d cards=%d filt=%d\npersonalApis: %@\ncardBiz: %@",
        gJsonCalls, gJsonSubCalls, gTsfmCalls, gMistCalls, gBridgeCalls, gMusCalls,
        gCardModelCalls, gFilteredCount,
        gPersonalApis ?: @"(none)",
        gCardBiz ?: @"(none)"];
    Class acCls = objc_getClass("UIAlertController");
    Class aaCls = objc_getClass("UIAlertAction");
    Class appCls = objc_getClass("UIApplication");
    if (acCls == Nil || aaCls == Nil || appCls == Nil) return;
    id ac = ((id (*)(id, SEL, id, id, long))objc_msgSend)(acCls,
        NSSelectorFromString(@"alertControllerWithTitle:message:preferredStyle:"),
        @"EleClean v7 诊断", msg, 1L);
    id ok = ((id (*)(id, SEL, id, long, id))objc_msgSend)(aaCls,
        NSSelectorFromString(@"actionWithTitle:style:handler:"), @"知道了", 0L, nil);
    ((void (*)(id, SEL, id))objc_msgSend)(ac, NSSelectorFromString(@"addAction:"), ok);
    id app = ((id (*)(id, SEL))objc_msgSend)(appCls, NSSelectorFromString(@"sharedApplication"));
    NSArray *windows = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"windows"));
    id key = nil;
    for (id w in windows) {
        char isKey = ((char (*)(id, SEL))objc_msgSend)(w, NSSelectorFromString(@"isKeyWindow"));
        if (isKey) { key = w; break; }
    }
    if (key == nil) key = [windows firstObject];
    id top = ((id (*)(id, SEL))objc_msgSend)(key, NSSelectorFromString(@"rootViewController"));
    while (top != nil) {
        id presented = ((id (*)(id, SEL))objc_msgSend)(top, NSSelectorFromString(@"presentedViewController"));
        if (presented == nil) break;
        top = presented;
    }
    if (top != nil) {
        ((void (*)(id, SEL, id, char, id))objc_msgSend)(top,
            NSSelectorFromString(@"presentViewController:animated:completion:"), ac, 1, nil);
    }
}

__attribute__((constructor)) static void ELEntry(void) {
    @autoreleasepool {
        BOOL a = ELInstall();
        BOOL b = ECInstallParse();
        BOOL c = ECInstallJson();
        ECInstallBody();
        ECInstallParseCards();
        ECInstallSubclassHooks();
        ECInstallPageDataHooks();
        ECInstallCardProbe();
        ECInstallMusProbe();
        if (!a || !b || !c) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ELInstall();
                ECInstallParse();
                ECInstallJson();
                ECInstallBody();
                ECInstallParseCards();
                ECInstallSubclassHooks();
                ECInstallPageDataHooks();
                ECInstallCardProbe();
                ECInstallMusProbe();
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

    }
}

// v6 build retrigger
