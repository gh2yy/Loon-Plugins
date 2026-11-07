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
           [s containsString:@"借钱"] ||
           [s containsString:@"生意贷"] ||
           [s containsString:@"先享后付"] ||
           [s containsString:@"我的钱包"] ||
           [s containsString:@"我的关注"] ||
           [s containsString:@"常点的店"] ||
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

static void ELCollectFinanceLabels(id obj, int depth, NSMutableSet *acc) {
    if (obj == nil || depth > 10) return;
    if ([obj isKindOfClass:[NSString class]]) {
        static NSArray *labels = nil;
        if (labels == nil) labels = @[@"零钱", @"生意贷", @"超时赔", @"先享后付",
                                      @"礼品卡", @"外卖红包", @"支付权益", @"借钱"];
        for (NSString *l in labels) {
            if ([(NSString *)obj containsString:l]) [acc addObject:l];
        }
        return;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            ELCollectFinanceLabels(k, depth + 1, acc);
            ELCollectFinanceLabels(((NSDictionary *)obj)[k], depth + 1, acc);
        }
        return;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) ELCollectFinanceLabels(e, depth + 1, acc);
    }
}
static BOOL ELIsFinanceModule(id obj) {
    NSMutableSet *acc = [NSMutableSet set];
    ELCollectFinanceLabels(obj, 0, acc);
    return [acc count] >= 2;
}

static BOOL ELSubtreeHasDeniedCode(id obj, int depth) {
    if (obj == nil || depth > 5) return NO;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        id code = ((NSDictionary *)obj)[@"code"] ?: ((NSDictionary *)obj)[@"bizCode"];
        if ([code isKindOfClass:[NSString class]] &&
            ([code isEqualToString:@"personal_my_wallet"] ||
             [code isEqualToString:@"eat_personal_operation_strip"] ||
             [code isEqualToString:@"eleme_personal_game_center"] ||
             [code isEqualToString:@"eat_personal_myfollow"])) {
            return YES;
        }
        for (id k in (NSDictionary *)obj) {
            if (ELSubtreeHasDeniedCode(((NSDictionary *)obj)[k], depth + 1)) return YES;
        }
        return NO;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) {
            if (ELSubtreeHasDeniedCode(e, depth + 1)) return YES;
        }
    }
    return NO;
}

static id ELFilterModules(id obj, int depth) {
    if (obj == nil || depth > 10) return obj;
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:((NSArray *)obj).count];
        for (id e in (NSArray *)obj) {
            if ([e isKindOfClass:[NSDictionary class]] && ELSubtreeHasDeniedCode(e, 0)) {
                continue;
            }
            if (ELSubtreeHasMarker(e, depth + 1)) continue;
            if (ELIsFinanceModule(e)) continue;
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

// v12 diag: record module/card identities to find stable keys.
static NSMutableString *gIdentityInfo = nil;
static void ECNoteIdentity(NSString *tag, id dictNode) {
    if (![dictNode isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *d = (NSDictionary *)dictNode;
    NSString *ident = nil;
    for (NSString *k in @[@"bizCode", @"code", @"type", @"templateId", @"name", @"moduleName", @"title"]) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
            ident = [NSString stringWithFormat:@"%@=%@", k, v];
            break;
        }
    }
    if (ident == nil) return;
    if (gIdentityInfo == nil) gIdentityInfo = [NSMutableString string];
    NSString *entry = [NSString stringWithFormat:@"%@:%@ ", tag, ident];
    if ([gIdentityInfo rangeOfString:entry].location == NSNotFound && [gIdentityInfo length] < 600) {
        [gIdentityInfo appendString:entry];
    }
}
static void ECRecordModuleIdentities(id node, int depth) {
    if (node == nil || depth > 4) return;
    if ([node isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)node) {
            ECNoteIdentity(@"M", e);
            ECRecordModuleIdentities(e, depth + 1);
        }
        return;
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)node) ECRecordModuleIdentities(((NSDictionary *)node)[k], depth + 1);
    }
}

// v9: home top-banner hunt. The creative copy must travel inside SOME mtop
// payload that passes -json. Fingerprint-scan every dict payload; record the
// carrier api; strip fingerprinted elements on the two suspect APIs.
static NSMutableString *gBannerHits = nil;
static NSArray *ECFingerprints(void) {
    return @[@"爆好价", @"猜谜抽奖", @"周末爆款", @"大券包", @"天猫双11"];
}
static BOOL ECNodeContainsFingerprint(id node, int depth, int *budget) {
    if (node == nil || depth > 8 || *budget <= 0) return NO;
    (*budget)--;
    if ([node isKindOfClass:[NSString class]]) {
        for (NSString *fp in ECFingerprints()) {
            if ([node containsString:fp]) return YES;
        }
        return NO;
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        for (id v in [node allValues]) {
            if (ECNodeContainsFingerprint(v, depth + 1, budget)) return YES;
        }
        return NO;
    }
    if ([node isKindOfClass:[NSArray class]]) {
        for (id v in node) {
            if (ECNodeContainsFingerprint(v, depth + 1, budget)) return YES;
        }
    }
    return NO;
}
static id ECStripFingerprinted(id node, int depth) {
    if (depth > 8 || node == nil) return node;
    if ([node isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id el in node) {
            int b = 300;
            if (ECNodeContainsFingerprint(el, 0, &b)) { ECNoteIdentity(@"S", el); continue; }
            [out addObject:ECStripFingerprinted(el, depth + 1)];
        }
        return out;
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        for (id k in node) {
            id v = node[k];
            if ([v isKindOfClass:[NSArray class]]) {
                out[k] = ECStripFingerprinted(v, depth + 1);
                continue;
            }
            if (depth >= 1) {
                int b = 300;
                if (ECNodeContainsFingerprint(v, 0, &b)) continue;
            }
            out[k] = ECStripFingerprinted(v, depth + 1);
        }
        return out;
    }
    return node;
}
static void ECNoteBannerHit(NSString *api, NSString *how) {
    if (gBannerHits == nil) gBannerHits = [NSMutableString string];
    NSString *entry = [NSString stringWithFormat:@"%@(%@) ", api ?: @"?", how];
    if ([gBannerHits rangeOfString:entry].location == NSNotFound && [gBannerHits length] < 450) {
        [gBannerHits appendString:entry];
    }
}

static id ECFilterResponseObject(id self, id payload) {
    if (![payload isKindOfClass:[NSDictionary class]]) return payload;
    NSString *api = ECApiNameFromObject(self, 0);
    ECNoteApi(api);
    NSString *apiL = [api lowercaseString];
    if (api != nil && [apiL hasPrefix:@"mtop.alsc.personal."]) {
        ECNotePersonalApi(api);
        ECNotePersonalVia(NSStringFromClass([self class]));
        ECRecordModuleIdentities(payload, 0);
        id out = ELProcessResult(api, payload);
        if (out != payload) gFilteredCount++;
        return out;
    }
    // banner trap (read-only scan on all apis; strip on the two suspects)
    int budget = 4000;
    if (ECNodeContainsFingerprint(payload, 0, &budget)) {
        BOOL suspect = [apiL containsString:@"tsfm.non.build"] ||
                       [apiL containsString:@"querymaterialinfo"] ||
                       [apiL containsString:@"carddatarecallfacade"];
        ECNoteBannerHit(api, suspect ? @"STRIPPED" : @"seen");
        if (suspect) {
            return ECStripFingerprinted(payload, 0);
        }
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

// v15: master door — every JSON response in the app is parsed through
// NSJSONSerialization, including the Weex/TMS pages' data (which never
// touches MtopExtResponse) and the storedcard formwork behind the rotating
// finance strip. Pre-check the raw text for rare trigger tokens, then run
// the existing filters on the parsed object and return the filtered copy.
static int gSerCalls = 0, gSerFiltered = 0;
typedef id (*ECSerIMP)(id, SEL, id, NSUInteger, id *);
static ECSerIMP gOrigSer = NULL;

static id ECSerReplacement(id cls, SEL _cmd, id data, NSUInteger options, id *error) {
    id result = gOrigSer ? gOrigSer(cls, _cmd, data, options, error) : nil;
    @try {
        if (result == nil || ![result isKindOfClass:[NSDictionary class]]) return result;
        if (![data isKindOfClass:[NSData class]] || [data length] > 3 * 1024 * 1024) return result;
        gSerCalls++;
        NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (raw == nil) return result;
        BOOL personalish = [raw containsString:@"eat_personal"] ||
                           [raw containsString:@"personal_my_wallet"] ||
                           [raw containsString:@"queryminecenter"];
        BOOL financeish = [raw containsString:@"storedcard"] ||
                          [raw containsString:@"生意贷"] || [raw containsString:@"超时赔"];
        if (personalish || financeish) {
            NSString *api = [raw containsString:@"queryminecenterfeeds"]
                ? @"mtop.alsc.personal.queryminecenterfeeds"
                : @"mtop.alsc.personal.queryminecenter";
            id out = ELProcessResult(api, result);
            if (out != result) { gSerFiltered++; result = out; }
        }
        int budget = 4000;
        if (ECNodeContainsFingerprint(result, 0, &budget)) {
            ECNoteBannerHit(@"jsonser", @"STRIPPED");
            gSerFiltered++;
            result = ECStripFingerprinted(result, 0);
        }
    } @catch (NSException *e) { }
    return result;
}

static void ECInstallSerHook(void) {
    if (gOrigSer != NULL) return;
    Class cls = objc_getClass("NSJSONSerialization");
    if (cls == Nil) return;
    Method m = class_getClassMethod(cls, NSSelectorFromString(@"JSONObjectWithData:options:error:"));
    if (m == NULL) return;
    gOrigSer = (ECSerIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ECSerReplacement);
}

// v16: MUS framework doors. The home/mine pages are MUS (TMS) pages; their
// JS-side fetches are parsed by MST_MUSFetchModule's own _JSONObjFromData:
// and mtop calls cross MUSMtopBridge. Filter at both.
static int gMusJsonCalls = 0, gMusBridgeCalls = 0;

static BOOL ECSubtreeContainsToken(id obj, NSString *token, int depth) {
    if (obj == nil || depth > 8) return NO;
    if ([obj isKindOfClass:[NSString class]]) {
        return [(NSString *)obj containsString:token];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            if (ECSubtreeContainsToken(k, token, depth + 1)) return YES;
            if (ECSubtreeContainsToken(((NSDictionary *)obj)[k], token, depth + 1)) return YES;
        }
        return NO;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) {
            if (ECSubtreeContainsToken(e, token, depth + 1)) return YES;
        }
    }
    return NO;
}

static id ECFilterAnyPayload(id result) {
    if (result == nil) return result;
    @try {
        BOOL personalish = ECSubtreeContainsToken(result, @"eat_personal", 0) ||
                           ECSubtreeContainsToken(result, @"personal_my_wallet", 0) ||
                           ECSubtreeContainsToken(result, @"queryminecenter", 0);
        BOOL financeish = ECSubtreeContainsToken(result, @"storedcard", 0);
        if ((personalish || financeish) && [result isKindOfClass:[NSDictionary class]]) {
            NSString *api = ECSubtreeContainsToken(result, @"queryminecenterfeeds", 0)
                ? @"mtop.alsc.personal.queryminecenterfeeds"
                : @"mtop.alsc.personal.queryminecenter";
            result = ELProcessResult(api, result);
        } else if (personalish && [result isKindOfClass:[NSArray class]]) {
            result = ELFilterModules(result, 0);
        }
        int budget = 4000;
        if (ECNodeContainsFingerprint(result, 0, &budget)) {
            ECNoteBannerHit(@"musjson", @"STRIPPED");
            result = ECStripFingerprinted(result, 0);
        }
    } @catch (NSException *e) { }
    return result;
}

typedef id (*ECMusJsonIMP)(id, SEL, id);
static ECMusJsonIMP gOrigMusJson = NULL;
static id ECMusJsonReplacement(id self, SEL _cmd, id data) {
    gMusJsonCalls++;
    id result = gOrigMusJson ? gOrigMusJson(self, _cmd, data) : nil;
    return ECFilterAnyPayload(result);
}

static void ECInstallMusJsonHook(void) {
    if (gOrigMusJson != NULL) return;
    Class cls = objc_getClass("MST_MUSFetchModule");
    if (cls == Nil) return;
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"_JSONObjFromData:"));
    if (m == NULL) return;
    gOrigMusJson = (ECMusJsonIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ECMusJsonReplacement);
}

typedef void (*ECMusBridgeIMP)(id, SEL, id, id, id);
static ECMusBridgeIMP gOrigMusBridge = NULL;
static void ECMusBridgeReplacement(id self, SEL _cmd, id request, id success, id failure) {
    gMusBridgeCalls++;
    id wrapped = success;
    @try {
        if (success != nil) {
            wrapped = ^(id resp) {
                id filtered = ECFilterAnyPayload(resp);
                ((void (^)(id))success)(filtered);
            };
        }
    } @catch (NSException *e) { wrapped = success; }
    if (gOrigMusBridge) gOrigMusBridge(self, _cmd, request, wrapped, failure);
}

static void ECInstallMusBridgeHook(void) {
    if (gOrigMusBridge != NULL) return;
    Class cls = objc_getClass("MUSMtopBridge");
    if (cls == Nil) return;
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(@"didSendRequest:success:failure:"));
    if (m == NULL) return;
    gOrigMusBridge = (ECMusBridgeIMP)method_getImplementation(m);
    method_setImplementation(m, (IMP)ECMusBridgeReplacement);
}

// v17: passive logging NSURLProtocol. Weex-stream / xtop traffic is plain
// HTTPS; if the banner/strip payloads travel that way, this sees their URLs
// and fingerprint tokens even though the payloads are parsed inside JS.
static NSMutableString *gProtoHits = nil;
static void ECNoteProtoHit(NSString *url, NSString *token) {
    if (gProtoHits == nil) gProtoHits = [NSMutableString string];
    NSString *entry = [NSString stringWithFormat:@"%@~%@ ", token, url];
    if ([gProtoHits rangeOfString:entry].location == NSNotFound && [gProtoHits length] < 500) {
        [gProtoHits appendString:entry];
    }
}

@interface ECLogProtocol : NSURLProtocol <NSURLConnectionDataDelegate> {
    NSURLConnection *_conn;
    NSMutableData *_data;
}
@end
@implementation ECLogProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"ECLogHandled" inRequest:request]) return NO;
    NSString *scheme = [[request URL] scheme];
    return [scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"];
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSMutableURLRequest *req = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"ECLogHandled" inRequest:req];
    _data = [NSMutableData data];
    _conn = [[NSURLConnection alloc] initWithRequest:req delegate:self];
}
- (void)stopLoading { [_conn cancel]; }
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [[self client] URLProtocol:self didReceiveResponse:response
        cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [_data appendData:data];
    [[self client] URLProtocol:self didLoadData:data];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    @try {
        if (_data.length > 0 && _data.length < 4 * 1024 * 1024) {
            NSString *text = [[NSString alloc] initWithData:_data encoding:NSUTF8StringEncoding];
            if (text != nil) {
                NSString *url = [[self.request URL] host] ?: @"?";
                for (NSString *tok in @[@"爆好价", @"personal_my_wallet",
                                        @"eat_personal_operation_strip", @"超时赔",
                                        @"礼品卡", @"queryminecenter"]) {
                    if ([text containsString:tok]) ECNoteProtoHit(url, tok);
                }
            }
        }
    } @catch (NSException *e) { }
    [[self client] URLProtocolDidFinishLoading:self];
}
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [[self client] URLProtocol:self didFailWithError:error];
}
@end

static void ECInstallProtoHook(void) {
    [NSURLProtocol registerClass:[ECLogProtocol class]];
}

// v18: view-layer enforcer. Every data channel is exhausted (proto sensor
// saw nothing: payloads ride the private AMNet/TNET stack and are parsed
// inside JS). Collapse the two remaining modules in the rendered view
// tree: the Mine finance strip is identified by its rotating title label
// (礼品卡 / 借钱 / 我的钱包), the home top banner by geometry (first
// full-width block under the header inside the home TMS page).
static int gEnforcePasses = 0;
static NSString *gPageVCs = nil;
static NSMutableString *gTreeDump = nil;

static void ECDumpTree(id view, NSMutableString *out, int depth, int *budget) {
    if (view == nil || depth > 13 || *budget <= 0) return;
    (*budget)--;
    CGRect f = ECViewFrame(view);
    CGRect inWin = [view convertRect:[view bounds] toView:nil];
    NSString *text = ECLabelText(view);
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"·"];
    [out appendFormat:@"%@%@ y=%.0f h=%.0f w=%.0f%@\n", indent,
        NSStringFromClass([view class]), inWin.origin.y, f.size.height, f.size.width,
        text ? [NSString stringWithFormat:@" 「%@」", [text substringToIndex:MIN(text.length, 8)]] : @""];
    for (id sub in ECSubviews(view)) ECDumpTree(sub, out, depth + 1, budget);
}

static NSMutableString *gCollapsed = nil;
static NSTimer *gEnforcer = nil;

static void ECNoteCollapsed(NSString *what, id view) {
    if (gCollapsed == nil) gCollapsed = [NSMutableString string];
    NSString *entry = [NSString stringWithFormat:@"%@:%@ ", what, NSStringFromClass([view class])];
    if ([gCollapsed rangeOfString:entry].location == NSNotFound && [gCollapsed length] < 300) {
        [gCollapsed appendString:entry];
    }
}

static BOOL ECIsUIViewClass(id o) {
    Class uiview = objc_getClass("UIView");
    return uiview != Nil && [o isKindOfClass:uiview];
}
static CGRect ECViewFrame(id v) {
    return ((CGRect (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"frame"));
}
static NSArray *ECSubviews(id v) {
    return ((NSArray * (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"subviews")) ?: @[];
}
static id ECSuperviewOf(id v) {
    return ((id (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"superview"));
}
static void ECSetHidden(id v, BOOL h) {
    ((void (*)(id, SEL, BOOL))objc_msgSend)(v, NSSelectorFromString(@"setHidden:"), h);
}
static BOOL ECIsHidden(id v) {
    return ((BOOL (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"isHidden"));
}
static void ECSetFrame(id v, CGRect f) {
    ((void (*)(id, SEL, CGRect))objc_msgSend)(v, NSSelectorFromString(@"setFrame:"), f);
}
static NSString *ECLabelText(id v) {
    Class label = objc_getClass("UILabel");
    if (label == Nil || ![v isKindOfClass:label]) return nil;
    return ((NSString * (*)(id, SEL))objc_msgSend)(v, NSSelectorFromString(@"text"));
}

// Collapse a container: zero its height, hide it, pull later siblings up.
static void ECCollapseView(id target, NSString *what) {
    if (!ECIsUIViewClass(target)) return;
    CGRect f = ECViewFrame(target);
    if (f.size.height < 5 || ECIsHidden(target)) return;
    id parent = ECSuperviewOf(target);
    CGFloat delta = f.size.height;
    ECSetHidden(target, YES);
    ECSetFrame(target, CGRectMake(f.origin.x, f.origin.y, f.size.width, 0));
    if (parent != nil) {
        for (id sib in ECSubviews(parent)) {
            if (sib == target) continue;
            CGRect sf = ECViewFrame(sib);
            if (sf.origin.y >= f.origin.y + 1) {
                ECSetFrame(sib, CGRectMake(sf.origin.x, sf.origin.y - delta, sf.size.width, sf.size.height));
            }
        }
    }
    ECNoteCollapsed(what, target);
}

// Find a label with any of the given titles inside root (depth-limited);
// return the enclosing module container: the highest ancestor (below the
// page root) that spans ~full width.
static id ECFindModuleByLabel(id root, NSArray *titles, int depth) {
    if (root == nil || depth > 24) return nil;
    NSString *text = ECLabelText(root);
    if (text != nil) {
        for (NSString *t in titles) {
            if ([text isEqualToString:t] || [text hasPrefix:t]) {
                id node = root;
                id best = ECSuperviewOf(root);
                for (int i = 0; i < 8; i++) {
                    id up = ECSuperviewOf(node);
                    if (up == nil) break;
                    CGRect uf = ECViewFrame(up);
                    CGRect nf = ECViewFrame(node);
                    if (uf.size.width >= 340 && uf.size.height >= nf.size.height + 2 &&
                        uf.size.height <= 400) {
                        best = up;
                        node = up;
                    } else break;
                }
                return best;
            }
        }
    }
    for (id sub in ECSubviews(root)) {
        id hit = ECFindModuleByLabel(sub, titles, depth + 1);
        if (hit != nil) return hit;
    }
    return nil;
}

// All TMS page views currently in any window.
static void ECCollectTMSViews(id view, NSMutableArray *out, int depth) {
    if (view == nil || depth > 30) return;
    if ([NSStringFromClass([view class]) containsString:@"TMSPageView"]) {
        [out addObject:view];
        return;
    }
    for (id sub in ECSubviews(view)) ECCollectTMSViews(sub, out, depth + 1);
}

static void ECEnforcePass(void) {
    gEnforcePasses++;
    @try {
        id app = ((id (*)(id, SEL))objc_msgSend)(objc_getClass("UIApplication"),
                     NSSelectorFromString(@"sharedApplication"));
        NSArray *windows = ((NSArray * (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"windows"));
        NSMutableArray *pages = [NSMutableArray array];
        for (id w in windows) ECCollectTMSViews(w, pages, 0);
        CGFloat winW = 0;
        if (windows.count > 0) winW = ECViewFrame(windows.firstObject).size.width;
        if (winW < 300) winW = 400;
        for (id page in pages) {
            // Which tab's page is this? Walk the responder chain to its VC.
            NSString *vcName = nil;
            id resp = page;
            for (int i = 0; i < 20 && resp != nil; i++) {
                Class vcCls = objc_getClass("UIViewController");
                if (vcCls != Nil && [resp isKindOfClass:vcCls]) {
                    vcName = NSStringFromClass([resp class]);
                    break;
                }
                resp = ((id (*)(id, SEL))objc_msgSend)(resp, NSSelectorFromString(@"nextResponder"));
            }
            if (vcName != nil) gPageVCs = vcName;
            // One-time hierarchy dump of the first page that looks like home.
            if (gTreeDump == nil && (vcName == nil || [vcName containsString:@"Home"] ||
                [vcName containsString:@"Tab"] || [vcName containsString:@"Main"])) {
                NSMutableString *dump = [NSMutableString string];
                int budget = 110;
                ECDumpTree(page, dump, 0, &budget);
                if ([dump length] > 20) gTreeDump = dump;
            }
            BOOL isHome = vcName == nil || [vcName containsString:@"Home"];
            BOOL isMine = vcName == nil || [vcName containsString:@"Personal"];
            // Mine finance strip by rotating title.
            if (isMine) {
                id strip = ECFindModuleByLabel(page, @[@"礼品卡", @"借钱"], 0);
                if (strip != nil) ECCollapseView(strip, @"strip");
            }
            if (!isHome) continue;
            // Home top banner by geometry among the page's direct visual
            // blocks: walk children of the page's first scroll content.
            NSMutableArray *blocks = [NSMutableArray array];
            [blocks addObjectsFromArray:ECSubviews(page)];
            for (id child in blocks) {
                CGRect f = ECViewFrame(child);
                (void)f;
                for (id sub in ECSubviews(child)) {
                    CGRect sf = ECViewFrame(sub);
                    if (sf.size.width >= winW * 0.88 && sf.size.height >= 55 && sf.size.height <= 140) {
                        CGRect inPage = [sub convertRect:[sub bounds] toView:page];
                        if (inPage.origin.y > 90 && inPage.origin.y < 300) {
                            ECCollapseView(sub, @"banner");
                        }
                    }
                }
            }
        }
    } @catch (NSException *e) { }
}

static void ECStartEnforcer(void) {
    if (gEnforcer != nil) return;
    gEnforcer = [NSTimer scheduledTimerWithTimeInterval:0.6
        repeats:YES block:^(NSTimer *t) { ECEnforcePass(); }];
}

// v13: walk the view tree and record classes of views sitting in the home
// top-banner band (between the search bar and the category icons).
static NSMutableString *gViewInfo = nil;
static void ECWalkViews(id view, id window, int depth) {
    if (view == nil || depth > 22) return;
    @try {
        CGRect bounds = ((CGRect (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"bounds"));
        CGRect inWin = ((CGRect (*)(id, SEL, CGRect, id))objc_msgSend)(view, NSSelectorFromString(@"convertRect:toView:"), bounds, window);
        // banner band: full-width-ish, 50..160pt tall, top area of the screen
        NSString *clsName = NSStringFromClass([view class]);
        BOOL nameHint = [clsName containsString:@"Banner"] || [clsName containsString:@"Mist"] ||
                        [clsName containsString:@"Weex"] || [clsName containsString:@"WX"] ||
                        [clsName containsString:@"Cube"] || [clsName containsString:@"Operation"];
        if (nameHint && inWin.size.width > 200 && inWin.size.height > 20) {
            if (gViewInfo == nil) gViewInfo = [NSMutableString string];
            NSString *entry = [NSString stringWithFormat:@"[%@ y=%.0f h=%.0f] ", clsName, inWin.origin.y, inWin.size.height];
            if ([gViewInfo rangeOfString:entry].location == NSNotFound && [gViewInfo length] < 550) {
                [gViewInfo appendString:entry];
            }
        }
        if (inWin.size.width > 300 && inWin.size.height > 45 && inWin.size.height < 170 &&
            inWin.origin.y > 80 && inWin.origin.y < 330) {
            if (gViewInfo == nil) gViewInfo = [NSMutableString string];
            NSString *entry = [NSString stringWithFormat:@"%@(y=%.0f,h=%.0f) ",
                NSStringFromClass([view class]), inWin.origin.y, inWin.size.height];
            if ([gViewInfo rangeOfString:entry].location == NSNotFound && [gViewInfo length] < 550) {
                [gViewInfo appendString:entry];
            }
        }
        NSArray *subs = ((id (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"subviews"));
        for (id sv in subs) ECWalkViews(sv, window, depth + 1);
    } @catch (NSException *e) { }
}
static void ECProbeHomeViews(void) {
    Class appCls = objc_getClass("UIApplication");
    if (appCls == Nil) return;
    id app = ((id (*)(id, SEL))objc_msgSend)(appCls, NSSelectorFromString(@"sharedApplication"));
    NSArray *windows = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"windows"));
    for (id w in windows) {
        ECWalkViews(w, w, 0);
    }
}

static void ECShowDiag(void) {
    // Fully dynamic UIKit access: the CI link line only has Foundation.
    ECProbeHomeViews();
    NSString *msg = [NSString stringWithFormat:
        @"pass=%d vc=%@\ncollapsed: %@\ntree:\n%@",
        gEnforcePasses, gPageVCs ?: @"?",
        gCollapsed ?: @"(none)",
        gTreeDump ?: @"(none)"];
    Class acCls = objc_getClass("UIAlertController");
    Class aaCls = objc_getClass("UIAlertAction");
    Class appCls = objc_getClass("UIApplication");
    if (acCls == Nil || aaCls == Nil || appCls == Nil) return;
    id ac = ((id (*)(id, SEL, id, id, long))objc_msgSend)(acCls,
        NSSelectorFromString(@"alertControllerWithTitle:message:preferredStyle:"),
        @"EleClean v19 诊断", msg, 1L);
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
        ECInstallSerHook();
        ECInstallMusJsonHook();
        ECInstallMusBridgeHook();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ ECStartEnforcer(); });
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
                ECInstallSerHook();
                ECInstallMusJsonHook();
                ECInstallMusBridgeHook();
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

// v6 build retrigger
