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
            if (ECNodeContainsFingerprint(el, 0, &b)) continue;
            [out addObject:ECStripFingerprinted(el, depth + 1)];
        }
        return out;
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        for (id k in node) {
            out[k] = ECStripFingerprinted(node[k], depth + 1);
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



// v30: order detail page filter, ported from v21 (formal build, no popup).
//   main  mtop.alsc.eleme.order.detail.build -> strip elements whose subtree
//          mentions a target section (本单限时福利/安心权益/常见问题/食无忧)
//          or whose bizCode carries welfare/benefit/faq/question/recommend/
//          rights/insurance/privilege — unless the subtree also mentions a
//          core-order marker (订单号/价格明细/...), so a shared container
//          holding real order data is never taken out (2026-11-09 lesson).
//   feeds mtop.alsc.eleme.order.detail.secondPage.adjust (scene=feeds)
//          -> empty the payload like the personal feeds: kills the
//          recommendation waterfall below the order.
static BOOL ECSubtreeContainsAny(id obj, NSArray *markers, int depth) {
    if (obj == nil || depth > 10) return NO;
    if ([obj isKindOfClass:[NSString class]]) {
        for (NSString *m in markers) {
            if ([(NSString *)obj containsString:m]) return YES;
        }
        return NO;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            if (ECSubtreeContainsAny(k, markers, depth + 1)) return YES;
            if (ECSubtreeContainsAny(((NSDictionary *)obj)[k], markers, depth + 1)) return YES;
        }
        return NO;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) {
            if (ECSubtreeContainsAny(e, markers, depth + 1)) return YES;
        }
        return NO;
    }
    return NO;
}
static NSArray *ECOrderMarkers(void) {
    return @[@"本单限时福利", @"安心权益", @"常见问题", @"食无忧"];
}
static NSArray *ECCoreMarkers(void) {
    return @[@"订单号", @"价格明细", @"订单信息", @"确认送达", @"配送信息",
             @"联系商家", @"确认收货", @"订单备注"];
}
static BOOL ECBizCodeIsOrderJunk(id obj) {
    if (![obj isKindOfClass:[NSDictionary class]]) return NO;
    id biz = [(NSDictionary *)obj objectForKey:@"bizCode"];
    if (![biz isKindOfClass:[NSString class]]) return NO;
    NSString *b = [(NSString *)biz lowercaseString];
    for (NSString *f in @[@"welfare", @"benefit", @"faq", @"question",
                          @"recommend", @"rights", @"insurance", @"privilege"]) {
        if ([b containsString:f]) return YES;
    }
    return NO;
}
static BOOL ECElementIsOrderJunk(id el) {
    if (![el isKindOfClass:[NSDictionary class]]) return NO;
    if (ECBizCodeIsOrderJunk(el)) return YES;
    return ECSubtreeContainsAny(el, ECOrderMarkers(), 0) &&
           !ECSubtreeContainsAny(el, ECCoreMarkers(), 0);
}
static int gOrderStripCount = 0;
static id ECOrderStrip(id obj, int depth) {
    if (obj == nil || depth > 10) return obj;
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:((NSArray *)obj).count];
        for (id e in (NSArray *)obj) {
            if (ECElementIsOrderJunk(e)) { gOrderStripCount++; continue; }
            [out addObject:ECOrderStrip(e, depth + 1)];
        }
        return out;
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        for (id k in (NSDictionary *)obj) {
            id v = ((NSDictionary *)obj)[k];
            if ([v isKindOfClass:[NSDictionary class]] && ECElementIsOrderJunk(v)) {
                gOrderStripCount++;
                continue;
            }
            out[k] = ECOrderStrip(v, depth + 1);
        }
        return out;
    }
    return obj;
}
static id ECProcessOrderResult(NSString *api, id payload) {
    if (![payload isKindOfClass:[NSDictionary class]]) return payload;
    NSString *apiL = [api lowercaseString];
    @try {
        if ([apiL containsString:@"secondpage"]) {
            id data = payload[@"data"];
            if (data != nil) {
                NSMutableDictionary *res = [payload mutableCopy];
                res[@"data"] = ELEmptyFeedsData(data);
                return res;
            }
            return ELEmptyFeedsData(payload);
        }
        int before = gOrderStripCount;
        id data = payload[@"data"];
        if (data != nil) {
            id stripped = ECOrderStrip(data, 0);
            if (gOrderStripCount == before) return payload;
            NSMutableDictionary *res = [payload mutableCopy];
            res[@"data"] = stripped;
            return res;
        }
        id stripped = ECOrderStrip(payload, 0);
        if (gOrderStripCount == before) return payload;
        return stripped;
    } @catch (NSException *e) {
        return payload;
    }
}

// v28: search landing page filter. The landing content (history / discovery
// words / shop columns / boards) all rides in ONE response:
// mtop.relationrecommend.elemetinyapprecommend.recommend, shaped as
// data.result[0].blocks = [block, ...]. Each block is a section. We keep a
// block only when it carries the history section (subtree contains 历史搜索)
// or when it is a pure layout/meta block (no title and no entities); every
// content block without the history title is dropped. Payloads of this api
// that do not contain the discovery section at all pass untouched.
static BOOL ECNodeHasToken(id node, NSString *token, int depth, int *budget) {
    if (node == nil || depth > 8 || *budget <= 0) return NO;
    (*budget)--;
    if ([node isKindOfClass:[NSString class]]) {
        return [(NSString *)node containsString:token];
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)node) {
            if (ECNodeHasToken(k, token, depth + 1, budget)) return YES;
            if (ECNodeHasToken(((NSDictionary *)node)[k], token, depth + 1, budget)) return YES;
        }
        return NO;
    }
    if ([node isKindOfClass:[NSArray class]]) {
        for (id v in (NSArray *)node) {
            if (ECNodeHasToken(v, token, depth + 1, budget)) return YES;
        }
    }
    return NO;
}
static BOOL ECBlockIsContent(id block) {
    if (![block isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary *d = (NSDictionary *)block;
    if (d[@"title"] != nil) return YES;
    id ent = d[@"entities"];
    if ([ent isKindOfClass:[NSArray class]] && [(NSArray *)ent count] > 0) return YES;
    if ([ent isKindOfClass:[NSDictionary class]] && [(NSDictionary *)ent count] > 0) return YES;
    return NO;
}
static id ECFilterSearchPayload(id payload) {
    @try {
        if (![payload isKindOfClass:[NSDictionary class]]) return payload;
        id data = ((NSDictionary *)payload)[@"data"];
        id result = [data isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)data)[@"result"] : nil;
        if (![result isKindOfClass:[NSArray class]]) return payload;
        // Gate: this payload must be the search landing assembly — some item's
        // blocks mention the discovery section.
        BOOL gated = NO;
        for (id item in (NSArray *)result) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            id blocks = ((NSDictionary *)item)[@"blocks"];
            if (![blocks isKindOfClass:[NSArray class]]) continue;
            int b = 6000;
            if (ECNodeHasToken(blocks, @"搜索发现", 0, &b)) { gated = YES; break; }
        }
        if (!gated) return payload;
        NSMutableArray *newResult = [NSMutableArray array];
        BOOL changed = NO;
        for (id item in (NSArray *)result) {
            if (![item isKindOfClass:[NSDictionary class]]) { [newResult addObject:item]; continue; }
            id blocks = ((NSDictionary *)item)[@"blocks"];
            if (![blocks isKindOfClass:[NSArray class]]) { [newResult addObject:item]; continue; }
            NSMutableArray *kept = [NSMutableArray array];
            for (id block in (NSArray *)blocks) {
                int b = 6000;
                // v29: keep ONLY the history block. v28 also kept meta/layout
                // blocks, and the shop-columns block (no top-level title or
                // entities key) slipped through that exemption.
                if (ECNodeHasToken(block, @"历史搜索", 0, &b)) [kept addObject:block];
            }
            if ([kept count] != [(NSArray *)blocks count]) {
                changed = YES;
                NSMutableDictionary *newItem = [(NSDictionary *)item mutableCopy];
                newItem[@"blocks"] = kept;
                [newResult addObject:newItem];
            } else {
                [newResult addObject:item];
            }
        }
        if (!changed) return payload;
        NSMutableDictionary *newData = [(NSDictionary *)data mutableCopy];
        newData[@"result"] = newResult;
        NSMutableDictionary *newPayload = [(NSDictionary *)payload mutableCopy];
        newPayload[@"data"] = newData;
        return newPayload;
    } @catch (NSException *e) {
        return payload;
    }
}


// v31 diag (READ-ONLY additions on top of v30): find WHERE the order page
// sections actually flow. For every payload through the shared response
// path: record api names containing "order"; scan the subtree for the
// order markers (安心权益/食无忧) and record which api carries them; dump
// the structure of the first marker-carrying payload.
static NSMutableString *gD31OrderApis = nil;
static NSMutableString *gD31MarkerApis = nil;
static NSString *gD31Struct = nil;
static void ECD31Note(NSMutableString *slot, NSString *text, NSUInteger cap) {
    if (text == nil || slot == nil) return;
    if ([slot rangeOfString:text].location == NSNotFound && [slot length] < cap) {
        [slot appendFormat:@"%@ ", text];
    }
}
static void ECD31Walk(id node, int depth, int *budget, NSMutableString *out) {
    if (node == nil || *budget <= 0) return;
    (*budget)--;
    if ([node isKindOfClass:[NSDictionary class]]) {
        [out appendString:@"{"];
        int n = 0;
        for (id k in (NSDictionary *)node) {
            if (n++ > 0) [out appendString:@" "];
            [out appendFormat:@"%@:", k];
            ECD31Walk(((NSDictionary *)node)[k], depth + 1, budget, out);
            if (*budget <= 0) break;
        }
        [out appendString:@"}"];
        return;
    }
    if ([node isKindOfClass:[NSArray class]]) {
        [out appendFormat:@"[%lu]", (unsigned long)[(NSArray *)node count]];
        if (depth < 4 && [(NSArray *)node count] > 0) {
            ECD31Walk([(NSArray *)node firstObject], depth + 1, budget, out);
        }
        return;
    }
    if ([node isKindOfClass:[NSString class]]) {
        NSString *v = (NSString *)node;
        if ([v length] > 0 && [v length] <= 24) [out appendFormat:@"'%@'", v];
        return;
    }
}
static BOOL ECD31Scan(id obj, int depth, int *budget) {
    if (obj == nil || depth > 10 || *budget <= 0) return NO;
    (*budget)--;
    if ([obj isKindOfClass:[NSString class]]) {
        return [(NSString *)obj containsString:@"安心权益"] ||
               [(NSString *)obj containsString:@"食无忧"];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            if (ECD31Scan(k, depth + 1, budget)) return YES;
            if (ECD31Scan(((NSDictionary *)obj)[k], depth + 1, budget)) return YES;
        }
        return NO;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) {
            if (ECD31Scan(e, depth + 1, budget)) return YES;
        }
    }
    return NO;
}
static void ECD31Inspect(NSString *api, id payload) {
    if (api != nil && [[api lowercaseString] containsString:@"order"]) {
        ECD31Note(gD31OrderApis, api, 600);
    }
    if (![payload isKindOfClass:[NSDictionary class]]) return;
    int budget = 5000;
    if (ECD31Scan(payload, 0, &budget)) {
        ECD31Note(gD31MarkerApis, api ?: @"(nil-api)", 400);
        if (gD31Struct == nil) {
            NSMutableString *out = [NSMutableString string];
            int b = 200;
            id d = ((NSDictionary *)payload)[@"data"];
            ECD31Walk(d != nil ? d : payload, 0, &b, out);
            gD31Struct = out;
        }
    }
}
static id ECD31TopVC(void) {
    // Fully dynamic UIKit access: the CI link line only has Foundation.
    Class appCls = objc_getClass("UIApplication");
    if (appCls == Nil) return nil;
    id app = ((id (*)(id, SEL))objc_msgSend)(appCls, NSSelectorFromString(@"sharedApplication"));
    NSArray *windows = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"windows"));
    id key = nil;
    for (id w in windows) {
        char isKey = ((char (*)(id, SEL))objc_msgSend)(w, NSSelectorFromString(@"isKeyWindow"));
        if (isKey) { key = w; break; }
    }
    if (key == nil) key = [windows firstObject];
    if (key == nil) return nil;
    id top = ((id (*)(id, SEL))objc_msgSend)(key, NSSelectorFromString(@"rootViewController"));
    while (top != nil) {
        id presented = ((id (*)(id, SEL))objc_msgSend)(top, NSSelectorFromString(@"presentedViewController"));
        if (presented == nil) break;
        top = presented;
    }
    return top;
}
static void ECShowOrderDiag31(void) {
    NSString *msg = [NSString stringWithFormat:@"json=%d body=%d strip=%d\norderApis: %@\nmarkerApis: %@\nstruct: %@",
        gJsonCalls, gBodyCalls, gOrderStripCount,
        gD31OrderApis ?: @"", gD31MarkerApis ?: @"", gD31Struct ?: @""];
    if ([msg length] > 2900) msg = [msg substringToIndex:2900];
    Class acCls = objc_getClass("UIAlertController");
    Class aaCls = objc_getClass("UIAlertAction");
    if (acCls == Nil || aaCls == Nil) return;
    id ac = ((id (*)(id, SEL, id, id, long))objc_msgSend)(acCls,
        NSSelectorFromString(@"alertControllerWithTitle:message:preferredStyle:"),
        @"EleClean v31 订单诊断", msg, 1L);
    id ok = ((id (*)(id, SEL, id, long, id))objc_msgSend)(aaCls,
        NSSelectorFromString(@"actionWithTitle:style:handler:"), @"知道了", 0L, nil);
    ((void (*)(id, SEL, id))objc_msgSend)(ac, NSSelectorFromString(@"addAction:"), ok);
    id top = ECD31TopVC();
    if (top != nil) {
        ((void (*)(id, SEL, id, char, id))objc_msgSend)(top,
            NSSelectorFromString(@"presentViewController:animated:completion:"), ac, 1, nil);
    }
}
static BOOL gD31Shown = NO;
static void ECD31Schedule(int attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        if (gD31Shown) return;
        if (ECD31TopVC() != nil) {
            gD31Shown = YES;
            ECShowOrderDiag31();
        } else if (attempt < 8) {
            ECD31Schedule(attempt + 1);
        }
    });
}

static id ECFilterResponseObject(id self, id payload) {
    if (![payload isKindOfClass:[NSDictionary class]]) return payload;
    ECD31Inspect(ECApiNameFromObject(self, 0), payload);
    NSString *api = ECApiNameFromObject(self, 0);
    ECNoteApi(api);
    NSString *apiL = [api lowercaseString];
    if (api != nil && [apiL hasPrefix:@"mtop.alsc.personal."]) {
        ECNotePersonalApi(api);
        ECNotePersonalVia(NSStringFromClass([self class]));
        id out = ELProcessResult(api, payload);
        if (out != payload) gFilteredCount++;
        return out;
    }
    if (api != nil && [apiL isEqualToString:@"mtop.relationrecommend.elemetinyapprecommend.recommend"]) {
        return ECFilterSearchPayload(payload);
    }
    if (api != nil && [apiL hasPrefix:@"mtop.alsc.eleme.order.detail."]) {
        return ECProcessOrderResult(api, payload);
    }
    // v10clean2: the banner fingerprint trap is REMOVED. Stripping elements
    // from the tsfm home-build payload took out the header section with it
    // (status-bar bleed-through seen 2026-11-09). Home payloads pass through
    // untouched; only the proven personal.* module filter remains.
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
        @"json=%d filt=%d\nbannerHits: %@",
        gJsonCalls, gFilteredCount,
        gBannerHits ?: @"(none)"];
    Class acCls = objc_getClass("UIAlertController");
    Class aaCls = objc_getClass("UIAlertAction");
    Class appCls = objc_getClass("UIApplication");
    if (acCls == Nil || aaCls == Nil || appCls == Nil) return;
    id ac = ((id (*)(id, SEL, id, id, long))objc_msgSend)(acCls,
        NSSelectorFromString(@"alertControllerWithTitle:message:preferredStyle:"),
        @"EleClean v10 诊断", msg, 1L);
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
    gD31OrderApis = [NSMutableString string];
    gD31MarkerApis = [NSMutableString string];
    ECD31Schedule(0);
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
