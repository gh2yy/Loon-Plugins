// TBDiag3 — in-process PROBE build on the formal4 filter base (TBClean 1.4)
// for Taobao 10.69.0 (com.taobao.taobao4iphone).
//
// Why this build exists: the formal4 session's Loon capture (428) proved
// that the cart / MyTaobao / home-container / searchdoor traffic rides the
// xnet/SPDY private channel and never traverses the proxy, so no capture
// can supply the in-process shapes the four still-failing surfaces need
// (work/CAP428_ANALYSIS.md). This build settles them in ONE session with
// read-only probes, feeding the formal6 construction.
//
// Filter base: IDENTICAL to formal4/5 (TBClean 1.3/1.4) with ONE change:
//   - MyTaobao: the containerType 3->2 downgrade write is DISABLED so the
//     probe reads the factory's native output values. Everything else
//     (PopLayer block, cart/bag response filters, float getter nil,
//     search parser filter, tab slot removal) is byte-for-byte the
//     formal4 logic.
// Probes (read-only, zero data modification):
//   P1 cart/bag: at -[MtopService getResponse:mrequest:], for the target
//      API set (awesome.get / awesome.recommend / WirelessRecommend
//      family / mtop.trade.query.bag) record the api's real value, the
//      request biz/ext parameter key sets, the containerParams value's
//      actual type + top-level keys + recommend_cart_main/_sxc substring
//      presence, and a step-by-step replay of the formal4 discrimination
//      (wouldMatch + which step fails). For query.bag additionally: the
//      response data top-level keys and the key path at which
//      topAdBanner_1 (and the icart_top_banner template string) appears.
//   P2 MyTaobao: at +[MTComponentModel creatComponent:componentData:]
//      record, for moduleName==basementTip, the component's real
//      containerType, the componentData key set, and call counts.
//   P3 home float bar: TBHRContainerContentModel -floatLayerSection
//      getter call count + caller return addresses (as offsets into the
//      main binary, symbolizable later); -setFloatLayerSection: records
//      the class + key/property outline of the first non-nil value set.
//   P4 search: at TBXSearchActivationTppParser -getProcessedData: exit,
//      record every itemsArray entry's tItemType + name (pre-filter).
// Presentation: TBDiag-proven alert (title "诊断3", anti-loss retry,
// re-show on new captures) + the same content written to
// Documents/TBDiag3.txt on every show.
//
// Safety: every probe body is @try/@catch wrapped and fail-open; typed
// getters only (isSucceed/containerType NEVER go through the
// id-returning TBM — formal1 crash lesson); recording is bounded
// (per-API samples, capped lists) and lock-guarded; probes never alter
// any value they read.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>
#import <mach-o/dyld.h>

// Build identity, verifiable in the compiled artifact (strings).
__attribute__((used)) static const char kTD3Version[] = "TBDiag3/1.0";

// ------------------------------------------------------------ utilities ----
// (Identical to TBClean 1.4 — see its header for the isSucceed warning.)
static id TBM(id obj, const char *selName) {
    if (obj == nil) return nil;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
static BOOL TBMBool(id obj, const char *selName, BOOL *out) {
    if (obj == nil || out == NULL) return NO;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return NO;
    *out = ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
    return YES;
}
static BOOL TBMInt(id obj, const char *selName, long long *out) {
    if (obj == nil || out == NULL) return NO;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return NO;
    *out = ((long long (*)(id, SEL))objc_msgSend)(obj, sel);
    return YES;
}
static void TBMSet(id obj, const char *selName, id val) {
    if (obj == nil) return;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, val);
}

static void TCAppendSerialized(id obj, NSMutableString *out, int depth) {
    if (obj == nil || depth > 6 || [out length] > 65536) return;
    if ([obj isKindOfClass:[NSString class]]) { [out appendString:(NSString *)obj]; [out appendString:@" "]; return; }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            TCAppendSerialized(k, out, depth + 1);
            TCAppendSerialized(((NSDictionary *)obj)[k], out, depth + 1);
        }
        return;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) TCAppendSerialized(e, out, depth + 1);
        return;
    }
    if ([obj isKindOfClass:[NSData class]]) {
        NSString *s = [[NSString alloc] initWithData:(NSData *)obj encoding:NSUTF8StringEncoding];
        if (s) { [out appendString:s]; [out appendString:@" "]; }
        return;
    }
    return;
}

static id TCMutableCopy(id obj, int depth) {
    if (obj == nil || depth > 12) return obj;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithCapacity:[(NSDictionary *)obj count]];
        for (id k in (NSDictionary *)obj) d[k] = TCMutableCopy(((NSDictionary *)obj)[k], depth + 1);
        return d;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray arrayWithCapacity:[(NSArray *)obj count]];
        for (id e in (NSArray *)obj) [a addObject:TCMutableCopy(e, depth + 1)];
        return a;
    }
    return obj;
}

// ------------------------------------------------------------- diag state --
static NSDate *gStart = nil;
static id gLock = nil;
static NSMutableArray *gEvents = nil;
static NSMutableString *gHookOK = nil, *gHookMiss = nil;
static int gShows = 0;
static BOOL gPending = NO;
static double gLastShowAt = 0;
static uintptr_t gMainBase = 0;

// P1: per-api seen counts, recorded samples, would-match tallies.
static NSMutableDictionary *gApiSeen = nil;    // api -> NSNumber count
static NSMutableDictionary *gApiRecN = nil;    // api -> NSNumber recorded
static NSMutableArray *gCartRecs = nil;        // NSString records (cart set)
static NSMutableArray *gBagRecs = nil;         // NSString records (query.bag)
static int gCartMatch = 0, gCartFailOk = 0, gCartFailSub = 0;
static int gBagAct = 0;                        // of recorded bag samples
static NSString *gBagAnchorLine = @"";
// P2: MyTaobao factory.
static int gFactoryTotal = 0, gBaseCalls = 0;
static NSString *gBaseFirst = @"", *gBaseLast = @"";
// P3: float getter/setter.
static int gFloatGetCalls = 0, gFloatSetCalls = 0;
static NSMutableDictionary *gFloatCallers = nil; // "0xOFFSET" -> count
static NSString *gFloatSetVal = @"";
// P4: search parser.
static int gParserCalls = 0, gSearchDroppedLast = -1;
static NSString *gSearchSnap = @"", *gSearchTypes = @"";

static double TDNow(void) { return [[NSDate date] timeIntervalSinceDate:gStart]; }

static void TDEvent(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    @synchronized (gLock) {
        [gEvents addObject:[NSString stringWithFormat:@"[+%.1fs] %@", TDNow(), msg]];
        while ([gEvents count] > 120) [gEvents removeObjectAtIndex:0];
    }
}

static NSString *TDShort(id obj, NSUInteger cap) {
    if (obj == nil) return @"(nil)";
    NSString *s = nil;
    @try { s = [obj description]; } @catch (NSException *e) { s = @"<desc-fail>"; }
    if (s == nil) s = @"";
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if ([s length] > cap) s = [[s substringToIndex:cap] stringByAppendingString:@"…"];
    return s;
}

// Sorted top-level keys of a dict, bounded; "(not-dict:<class>)" otherwise.
static NSString *TDKeysOf(id obj) {
    if (obj == nil) return @"(nil)";
    if (![obj isKindOfClass:[NSDictionary class]]) {
        return [NSString stringWithFormat:@"(not-dict:%@)", NSStringFromClass([obj class])];
    }
    NSArray *keys = [[(NSDictionary *)obj allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString *out = [NSMutableString string];
    NSUInteger n = 0;
    for (id k in keys) {
        if (n++ > 0) [out appendString:@","];
        NSString *ks = [k isKindOfClass:[NSString class]] ? (NSString *)k : TDShort(k, 30);
        if ([ks length] > 40) ks = [[ks substringToIndex:40] stringByAppendingString:@"…"];
        [out appendString:ks];
        if (n >= 40) { [out appendString:@",…"]; break; }
    }
    return out;
}

// ============================================================ MTOP core ====
// Formal4 point, unchanged: -[MtopService getResponse:mrequest:].
typedef id (*GetRespIMP)(id, SEL, id, id);
static GetRespIMP gOrigGetResp = NULL;

static NSString *TCApiOfResponse(id resp) {
    id req = TBM(resp, "request");
    id n = TBM(req, "getApiName");
    return [n isKindOfClass:[NSString class]] ? n : nil;
}

static BOOL TCCartAPI(NSString *api) {
    if (![api isKindOfClass:[NSString class]]) return NO;
    return [api caseInsensitiveCompare:@"mtop.taobao.wireless.home.awesome.get"] == NSOrderedSame ||
           [api caseInsensitiveCompare:@"mtop.taobao.wireless.home.awesome.recommend"] == NSOrderedSame ||
           [api caseInsensitiveCompare:@"mtop.relationrecommend.WirelessRecommend.recommend"] == NSOrderedSame ||
           [api caseInsensitiveCompare:@"mtop.relationrecommend.WirelessRecommend.recommendstream"] == NSOrderedSame ||
           [api caseInsensitiveCompare:@"mtop.relationrecommend.wirelessrecommend.recommend"] == NSOrderedSame;
}

// Formal4 discrimination, unchanged (read-only replay is used by P1).
static BOOL TCCartMatched(id resp) {
    id req = TBM(resp, "request");
    if (req == nil) return NO;
    NSMutableString *blob = [NSMutableString string];
    @try {
        TCAppendSerialized(TBM(req, "getBizParameters"), blob, 0);
        TCAppendSerialized(TBM(req, "getExtParameters"), blob, 0);
        TCAppendSerialized(TBM(req, "pageName"), blob, 0);
        TCAppendSerialized(TBM(req, "pageUrl"), blob, 0);
        TCAppendSerialized(TBM(req, "bizID"), blob, 0);
        TCAppendSerialized(TBM(req, "openBizData"), blob, 0);
    } @catch (NSException *e) { return NO; }
    return [blob rangeOfString:@"recommend_cart_main"].location != NSNotFound ||
           [blob rangeOfString:@"recommend_cart_sxc"].location != NSNotFound;
}

static void TCEmptyArraysDeep(NSMutableDictionary *d, int depth) {
    if (depth > 3) return;
    for (id k in [d allKeys]) {
        id v = d[k];
        if ([v isKindOfClass:[NSArray class]]) {
            d[k] = [NSMutableArray array];
        } else if ([v isKindOfClass:[NSMutableDictionary class]]) {
            TCEmptyArraysDeep((NSMutableDictionary *)v, depth + 1);
        }
    }
}

static id TCEmptiedCartBody(id body) {
    if (![body isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *b = TCMutableCopy(body, 0);
    id data = b[@"data"];
    if ([data isKindOfClass:[NSArray class]]) {
        b[@"data"] = [NSMutableArray array];
        return b;
    }
    if (![data isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *d = (NSMutableDictionary *)data;
    BOOL keyed = NO;
    for (NSString *cid in @[@"recommend_cart_main", @"recommend_cart_sxc"]) {
        id sub = d[cid];
        if ([sub isKindOfClass:[NSMutableDictionary class]]) {
            TCEmptyArraysDeep((NSMutableDictionary *)sub, 0);
            keyed = YES;
        } else if ([sub isKindOfClass:[NSArray class]]) {
            d[cid] = [NSMutableArray array];
            keyed = YES;
        }
    }
    if (keyed) return b;
    TCEmptyArraysDeep(d, 0);
    return b;
}

// ---- cart top activity banner (target 7) — formal4, unchanged -----------
static BOOL TCDictHasBannerTemplate(NSDictionary *d) {
    for (id k in d) {
        id v = d[k];
        if ([v isKindOfClass:[NSString class]] &&
            [(NSString *)v rangeOfString:@"icart_top_banner"].location != NSNotFound) return YES;
    }
    return NO;
}

static void TCStripBannerInNode(id node, int depth, BOOL *acted) {
    if (node == nil || depth > 8) return;
    if ([node isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *d = (NSMutableDictionary *)node;
        if (d[@"topAdBanner_1"] != nil) {
            d[@"topAdBanner_1"] = [NSMutableDictionary dictionary];
            *acted = YES;
        }
        for (id k in [d allKeys]) TCStripBannerInNode(d[k], depth + 1, acted);
        if (depth > 0 && TCDictHasBannerTemplate(d)) {
            [d removeAllObjects];
            *acted = YES;
        }
        return;
    }
    if ([node isKindOfClass:[NSMutableArray class]]) {
        NSMutableArray *a = (NSMutableArray *)node;
        for (NSInteger i = (NSInteger)[a count] - 1; i >= 0; i--) {
            id e = a[(NSUInteger)i];
            if ([e isKindOfClass:[NSDictionary class]] && TCDictHasBannerTemplate((NSDictionary *)e)) {
                [a removeObjectAtIndex:(NSUInteger)i];
                *acted = YES;
            } else {
                TCStripBannerInNode(e, depth + 1, acted);
            }
        }
    }
}

static id TCFilteredBagBody(id body) {
    if (![body isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *b = TCMutableCopy(body, 0);
    BOOL acted = NO;
    TCStripBannerInNode(b, 0, &acted);
    return acted ? b : nil;
}

static void TCSetBody(id resp, id newBody) {
    @try {
        if (![newBody isKindOfClass:[NSDictionary class]]) return;
        NSData *jd = [NSJSONSerialization dataWithJSONObject:newBody options:0 error:nil];
        if (jd == nil) return;
        NSString *js = [[NSString alloc] initWithData:jd encoding:NSUTF8StringEncoding];
        if (js == nil) return;
        TBMSet(resp, "setBody:", newBody);
        TBMSet(resp, "setJson:", js);
        TBMSet(resp, "setRawbody:", jd);
    } @catch (NSException *e) { }
}

// ============================================================ P1 probes ====
// containerParams morphology: actual type, top-level keys (string form
// parsed when possible), recommend_cart_main/_sxc presence.
static NSString *TDContainerParamsInfo(id paramsDict) {
    if (![paramsDict isKindOfClass:[NSDictionary class]]) return @"params-not-dict";
    id cp = ((NSDictionary *)paramsDict)[@"containerParams"];
    if (cp == nil) return @"absent";
    if ([cp isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)cp;
        BOOL hasMain = [s rangeOfString:@"recommend_cart_main"].location != NSNotFound;
        BOOL hasSxc = [s rangeOfString:@"recommend_cart_sxc"].location != NSNotFound;
        NSString *keys = @"unparsed";
        @try {
            NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
            id parsed = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            if ([parsed isKindOfClass:[NSDictionary class]]) keys = TDKeysOf(parsed);
            else if (parsed != nil) keys = [NSString stringWithFormat:@"(json:%@)", NSStringFromClass([parsed class])];
        } @catch (NSException *e) { keys = @"parse-exc"; }
        return [NSString stringWithFormat:@"NSString len=%lu main=%d sxc=%d keys=[%@]",
                (unsigned long)[s length], hasMain, hasSxc, keys];
    }
    if ([cp isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)cp;
        return [NSString stringWithFormat:@"NSDictionary main=%d sxc=%d keys=[%@]",
                d[@"recommend_cart_main"] != nil, d[@"recommend_cart_sxc"] != nil, TDKeysOf(d)];
    }
    return [NSString stringWithFormat:@"other:%@", NSStringFromClass([cp class])];
}

// Bounded DFS collecting key paths at which `keyName` occurs as a dict
// key, or at which a string value contains `needle`. Keys only — values
// are never recorded.
static void TDSearchPaths(id node, NSString *path, int depth, int *budget,
                          NSString *keyName, NSString *needle,
                          NSMutableArray *keyPaths, NSMutableArray *strPaths) {
    if (node == nil || depth > 8 || *budget <= 0) return;
    (*budget)--;
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)node;
        for (id k in d) {
            NSString *ks = [k isKindOfClass:[NSString class]] ? (NSString *)k : TDShort(k, 24);
            NSString *child = [path length] ? [path stringByAppendingFormat:@".%@", ks] : ks;
            if (keyName != nil && [ks isEqualToString:keyName] && [keyPaths count] < 3) {
                [keyPaths addObject:child];
            }
            TDSearchPaths(d[k], child, depth + 1, budget, keyName, needle, keyPaths, strPaths);
            if (*budget <= 0) return;
        }
        return;
    }
    if ([node isKindOfClass:[NSArray class]]) {
        NSArray *a = (NSArray *)node;
        NSUInteger n = MIN([a count], (NSUInteger)60);
        for (NSUInteger i = 0; i < n; i++) {
            TDSearchPaths(a[i], [path stringByAppendingFormat:@"[%lu]", (unsigned long)i],
                          depth + 1, budget, keyName, needle, keyPaths, strPaths);
            if (*budget <= 0) return;
        }
        return;
    }
    if (needle != nil && [node isKindOfClass:[NSString class]] &&
        [(NSString *)node rangeOfString:needle].location != NSNotFound && [strPaths count] < 3) {
        [strPaths addObject:path];
    }
}

// Read-only probe at the getResponse point. Runs BEFORE the formal4
// filter rewrites anything; every value is read through the proven
// getters; any exception aborts the probe only.
static void TDProbeMTOP(id resp, NSString *api, BOOL isCart, BOOL isBag) {
    @try {
        BOOL full = NO;
        @synchronized (gLock) {
            int seen = [gApiSeen[api] intValue] + 1;
            gApiSeen[api] = @(seen);
            int recN = [gApiRecN[api] intValue];
            if (recN < 3) { gApiRecN[api] = @(recN + 1); full = YES; }
        }
        if (!full) return;
        id req = TBM(resp, "request");
        if (req == nil) {
            @synchronized (gLock) {
                [(isBag ? gBagRecs : gCartRecs) addObject:
                    [NSString stringWithFormat:@"api=%@ request=nil", api]];
                gPending = YES;
            }
            return;
        }
        // apiVersion: best-effort, guarded (getter existence unproven).
        NSString *ver = @"?";
        id v1 = TBM(req, "getApiVersion");
        if ([v1 isKindOfClass:[NSString class]]) ver = (NSString *)v1;
        else {
            id v2 = TBM(req, "apiVersion");
            if ([v2 isKindOfClass:[NSString class]]) ver = (NSString *)v2;
        }
        BOOL ok = YES; BOOL okRead = TBMBool(resp, "isSucceed", &ok);
        BOOL okEff = (!okRead || ok); // formal4 proceeds when unread/false->skip
        id biz = TBM(req, "getBizParameters");
        id ext = TBM(req, "getExtParameters");
        NSString *pageName = TBM(req, "pageName");
        if (![pageName isKindOfClass:[NSString class]]) pageName = @"-";
        else if ([pageName length] > 60) pageName = [[pageName substringToIndex:60] stringByAppendingString:@"…"];

        if (isCart) {
            BOOL sub = TCCartMatched(resp);
            NSString *cpInfo = TDContainerParamsInfo(biz);
            if ([cpInfo isEqualToString:@"absent"]) {
                NSString *alt = TDContainerParamsInfo(ext);
                if (![alt isEqualToString:@"absent"]) cpInfo = [@"(in ext) " stringByAppendingString:alt];
            }
            NSString *failStep = sub ? @"-" : (okEff ? @"substring" : @"isSucceed");
            BOOL would = okEff && sub;
            NSString *rec = [NSString stringWithFormat:
                @"api=%@ ver=%@ ok=%@ bizKeys=[%@] extKeys=[%@] pageName=%@ containerParams={%@} steps: api=1 ok=%d sub=%d => wouldMatch=%@ failStep=%@",
                api, ver, okRead ? (ok ? @"1" : @"0") : @"?",
                TDKeysOf(biz), TDKeysOf(ext), pageName, cpInfo,
                okEff, sub, would ? @"YES" : @"NO", failStep];
            @synchronized (gLock) {
                [gCartRecs addObject:rec];
                if (would) gCartMatch++;
                else if (!okEff) gCartFailOk++;
                else gCartFailSub++;
                gPending = YES;
            }
            TDEvent(@"P1 cart %@", rec);
        } else if (isBag) {
            id body = TBM(resp, "body");
            NSString *dataKeys = @"-";
            NSMutableArray *kp = [NSMutableArray array], *sp = [NSMutableArray array];
            if ([body isKindOfClass:[NSDictionary class]]) {
                id data = ((NSDictionary *)body)[@"data"];
                if ([data isKindOfClass:[NSDictionary class]]) dataKeys = TDKeysOf(data);
                else if (data != nil) dataKeys = [NSString stringWithFormat:@"(data:%@)", NSStringFromClass([data class])];
                int budget = 4000;
                TDSearchPaths(body, @"body", 0, &budget, @"topAdBanner_1", @"icart_top_banner", kp, sp);
            }
            BOOL wouldAct = (TCFilteredBagBody(body) != nil);
            NSString *rec = [NSString stringWithFormat:
                @"api=%@ ver=%@ ok=%@ dataKeys=[%@] topAdBanner_1@[%@] icart_top_banner@[%@] formal4WouldAct=%@",
                api, ver, okRead ? (ok ? @"1" : @"0") : @"?", dataKeys,
                [kp componentsJoinedByString:@" ; "], [sp componentsJoinedByString:@" ; "],
                wouldAct ? @"YES" : @"NO"];
            @synchronized (gLock) {
                [gBagRecs addObject:rec];
                if (wouldAct) gBagAct++;
                gBagAnchorLine = [NSString stringWithFormat:@"字段@%@ 模板@%@",
                    [kp firstObject] ?: @"-", [sp firstObject] ?: @"-"];
                gPending = YES;
            }
            TDEvent(@"P1 bag %@", rec);
        }
    } @catch (NSException *e) { }
}

static id TCGetResponse(id self, SEL _cmd, id raw, id mreq) {
    id resp = gOrigGetResp ? gOrigGetResp(self, _cmd, raw, mreq) : nil;
    if (resp == nil) return resp;
    @try {
        NSString *api = TCApiOfResponse(resp);
        if (api == nil) return resp;
        BOOL isCart = TCCartAPI(api);
        BOOL isBag = [api isEqualToString:@"mtop.trade.query.bag"];
        if (!isCart && !isBag) return resp;
        // Probe first, on the untouched response; filter after (formal4).
        TDProbeMTOP(resp, api, isCart, isBag);
        BOOL ok = YES;
        if (TBMBool(resp, "isSucceed", &ok) && !ok) return resp;
        if (isCart) {
            if (TCCartMatched(resp)) {
                id nb = TCEmptiedCartBody(TBM(resp, "body"));
                if (nb != nil) TCSetBody(resp, nb);
            }
        } else {
            id nb = TCFilteredBagBody(TBM(resp, "body"));
            if (nb != nil) TCSetBody(resp, nb);
        }
    } @catch (NSException *e) { }
    return resp;
}

// ========================================================== PopLayer =====
// Formal4 module 1, unchanged (the probe build keeps the block so the
// session matches the formal environment).
typedef struct { double x, y, w, h; } TCFrame;
typedef id (*FactoryIMP)(id, SEL, TCFrame, id, id, id);
static FactoryIMP gOrigFactory = NULL;

static BOOL TCUriIsBlockedPop(NSString *uri) {
    if (![uri isKindOfClass:[NSString class]]) return NO;
    return [uri hasPrefix:@"poplayer://Page_Home@popup_"] ||
           [uri hasPrefix:@"poplayer://Page_MyTaobao@popup_"];
}

static id TCFactoryCreate(id self, SEL _cmd, TCFrame fr, id type, id popReq, id vc) {
    @try {
        id evt = TBM(popReq, "event");
        id uri = TBM(evt, "uri");
        if (TCUriIsBlockedPop(uri)) return nil;
    } @catch (NSException *e) { }
    return gOrigFactory ? gOrigFactory(self, _cmd, fr, type, popReq, vc) : nil;
}

// ============================================== P3: home float bar =======
// Getter: formal4 forces nil (unchanged) + probe records call count and
// caller return addresses as offsets from the main binary base, for
// after-the-fact symbolization. Setter: pure pass-through + records the
// first non-nil value's class and key/property outline.
typedef id (*FloatGetterIMP)(id, SEL);
static FloatGetterIMP gOrigFloatGetter = NULL;
typedef void (*FloatSetterIMP)(id, SEL, id);
static FloatSetterIMP gOrigFloatSetter = NULL;

static NSString *TDValueOutline(id val) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"类=%@", NSStringFromClass([val class])];
    @try {
        if ([val isKindOfClass:[NSDictionary class]]) {
            [out appendFormat:@" 键=[%@]", TDKeysOf(val)];
        } else if ([val isKindOfClass:[NSArray class]]) {
            NSArray *a = (NSArray *)val;
            [out appendFormat:@" 数组×%lu 首元类=%@", (unsigned long)[a count],
             [a count] ? NSStringFromClass([[a firstObject] class]) : @"-"];
        } else {
            // Model object: its property names are the "key outline".
            unsigned int n = 0;
            objc_property_t *props = class_copyPropertyList([val class], &n);
            NSMutableString *names = [NSMutableString string];
            for (unsigned int i = 0; i < n && i < 48; i++) {
                if (i) [names appendString:@","];
                [names appendString:[NSString stringWithUTF8String:property_getName(props[i])]];
            }
            if (props) free(props);
            [out appendFormat:@" 属性=[%@]", names];
        }
    } @catch (NSException *e) { [out appendString:@" (outline-exc)"]; }
    return out;
}

static id TDFloatLayerSection(id self, SEL _cmd) {
    @try {
        void *ra = __builtin_return_address(0);
        uintptr_t off = (uintptr_t)ra - gMainBase;
        @synchronized (gLock) {
            gFloatGetCalls++;
            NSString *key = [NSString stringWithFormat:@"0x%lx", (unsigned long)off];
            int c = [gFloatCallers[key] intValue] + 1;
            if (c == 1 && [gFloatCallers count] >= 12) {
                // cap distinct callers; keep counting the total only
            } else {
                gFloatCallers[key] = @(c);
            }
        }
    } @catch (NSException *e) { }
    return nil; // formal4 behavior, unchanged
}

static void TDFloatSetLayerSection(id self, SEL _cmd, id val) {
    @try {
        @synchronized (gLock) {
            gFloatSetCalls++;
            if (val != nil && [gFloatSetVal length] == 0) {
                gFloatSetVal = TDValueOutline(val);
                gPending = YES;
            }
        }
    } @catch (NSException *e) { }
    if (gOrigFloatSetter) gOrigFloatSetter(self, _cmd, val);
}

// ============================================== P4: search sections ======
// Formal4 module 4 (parser-exit filter) + probe recording the pre-filter
// itemsArray's tItemType/name list.
typedef id (*ParserIMP)(id, SEL, id);
static ParserIMP gOrigParser = NULL;

static BOOL TCHistoryType(id t) {
    if (![t isKindOfClass:[NSString class]]) return NO;
    NSString *s = (NSString *)t;
    return [s isEqualToString:@"nt_history"] ||
           [s isEqualToString:@"nt_combine_history"] ||
           [s isEqualToString:@"nt_multimodal_history"];
}

static void TDProbeSearchItems(id out) {
    @try {
        if (![out isKindOfClass:[NSDictionary class]]) return;
        id items = ((NSDictionary *)out)[@"itemsArray"];
        if (![items isKindOfClass:[NSArray class]]) return;
        NSArray *a = (NSArray *)items;
        NSMutableString *snap = [NSMutableString string];
        NSMutableString *types = [NSMutableString string];
        NSUInteger n = 0;
        for (id sec in a) {
            if (n++ > 0) { [snap appendString:@"\n"]; }
            if ([sec isKindOfClass:[NSDictionary class]]) {
                NSDictionary *sd = (NSDictionary *)sec;
                id t = sd[@"tItemType"], nm = sd[@"name"];
                NSString *ts = [t isKindOfClass:[NSString class]] ? (NSString *)t
                    : [NSString stringWithFormat:@"<%@>", t ? NSStringFromClass([t class]) : @"nil"];
                NSString *ns = [nm isKindOfClass:[NSString class]] ? (NSString *)nm
                    : [NSString stringWithFormat:@"<%@>", nm ? NSStringFromClass([nm class]) : @"nil"];
                if ([ns length] > 30) ns = [[ns substringToIndex:30] stringByAppendingString:@"…"];
                [snap appendFormat:@"%@ | %@", ts, ns];
                if ([types length] < 700) {
                    if ([types length]) [types appendString:@","];
                    [types appendString:ts];
                }
            } else {
                [snap appendFormat:@"<%@>", NSStringFromClass([sec class])];
            }
            if (n >= 40) { [snap appendString:@"\n…(截断)"]; break; }
        }
        @synchronized (gLock) {
            gParserCalls++;
            if (![snap isEqualToString:gSearchSnap]) {
                gSearchSnap = [snap copy];
                gSearchTypes = [types copy];
                gPending = YES;
            }
        }
    } @catch (NSException *e) { }
}

static id TCGetProcessedData(id self, SEL _cmd, id raw) {
    id out = gOrigParser ? gOrigParser(self, _cmd, raw) : nil;
    if (out == nil) return out;
    TDProbeSearchItems(out); // pre-filter snapshot
    @try {
        if (![out isKindOfClass:[NSDictionary class]]) return out;
        id items = ((NSDictionary *)out)[@"itemsArray"];
        if (![items isKindOfClass:[NSArray class]]) return out;
        NSArray *a = (NSArray *)items;
        NSMutableArray *keep = nil;
        NSUInteger idx = 0;
        int dropped = 0;
        for (id sec in a) {
            BOOL drop = NO;
            if ([sec isKindOfClass:[NSDictionary class]]) {
                NSDictionary *sd = (NSDictionary *)sec;
                if (!TCHistoryType(sd[@"tItemType"])) {
                    id nm = sd[@"name"];
                    if ([nm isKindOfClass:[NSString class]] &&
                        ([(NSString *)nm rangeOfString:@"猜你想搜"].location != NSNotFound ||
                         [(NSString *)nm rangeOfString:@"淘宝热榜"].location != NSNotFound)) {
                        drop = YES;
                    }
                }
            }
            if (drop) {
                dropped++;
                if (keep == nil) keep = [[a subarrayWithRange:NSMakeRange(0, idx)] mutableCopy];
            } else if (keep != nil) {
                [keep addObject:sec];
            }
            idx++;
        }
        @synchronized (gLock) { gSearchDroppedLast = dropped; }
        if (keep == nil) return out;
        NSMutableDictionary *o = [out mutableCopy];
        o[@"itemsArray"] = keep;
        return o;
    } @catch (NSException *e) { return out; }
}

// ============================================== P2: MyTaobao factory =====
// Formal4 hooked +[MTComponentModel creatComponent:componentData:] to
// rewrite basementTip's containerType 3->2. IN THIS BUILD THE REWRITE
// IS DISABLED: the hook only records the native values (real
// containerType, componentData keys, call counts) and returns the
// component untouched.
typedef id (*CreateCompIMP)(id, SEL, id, id);
static CreateCompIMP gOrigCreateComp = NULL;

static id TDCreateComponent(id self, SEL _cmd, id name, id data) {
    id comp = gOrigCreateComp ? gOrigCreateComp(self, _cmd, name, data) : nil;
    if (comp == nil) return comp;
    @try {
        @synchronized (gLock) { gFactoryTotal++; }
        id mn = TBM(comp, "moduleName");
        BOOL byComp = [mn isKindOfClass:[NSString class]] && [(NSString *)mn isEqualToString:@"basementTip"];
        BOOL byName = [name isKindOfClass:[NSString class]] && [(NSString *)name isEqualToString:@"basementTip"];
        if (byComp || byName) {
            int idx = 0;
            @synchronized (gLock) { idx = ++gBaseCalls; }
            long long ct = -9999;
            BOOL ctRead = TBMInt(comp, "containerType", &ct);
            NSString *rec = [NSString stringWithFormat:
                @"#%d name参数=%@ comp.moduleName=%@ containerType=%@ data类=%@ data键=[%@]",
                idx,
                [name isKindOfClass:[NSString class]] ? TDShort(name, 40) : TDShort(name, 24),
                [mn isKindOfClass:[NSString class]] ? (NSString *)mn : TDShort(mn, 24),
                ctRead ? [NSString stringWithFormat:@"%lld", ct] : @"读不到",
                NSStringFromClass([data class]), TDKeysOf(data)];
            @synchronized (gLock) {
                if (idx == 1) gBaseFirst = [rec copy];
                gBaseLast = [rec copy];
                gPending = YES;
            }
            TDEvent(@"P2 %@", rec);
        }
    } @catch (NSException *e) { }
    return comp;
}

// ======================================================== tab bar slot ====
// Formal4 module 7, unchanged.
typedef id (*VCItemsIMP)(id, SEL);
static VCItemsIMP gOrigVCItems = NULL;

static id TCVCItems(id self, SEL _cmd) {
    id items = gOrigVCItems ? gOrigVCItems(self, _cmd) : nil;
    if (items == nil) return items;
    @try {
        if (![items isKindOfClass:[NSArray class]]) return items;
        NSArray *a = (NSArray *)items;
        if ([a count] != 5) return items;
        id item = a[1];
        Class vcItemCls = objc_getClass("TBVCItem");
        if (vcItemCls != Nil && ![item isKindOfClass:vcItemCls]) return items;
        id url = TBM(item, "url");
        id biz = TBM(item, "attractBiz");
        BOOL hit = ([url isKindOfClass:[NSString class]] &&
                    [(NSString *)url isEqualToString:@"taobao://guangguang/root"]) ||
                   ([biz isKindOfClass:[NSString class]] &&
                    [(NSString *)biz isEqualToString:@"tab2"]);
        if (!hit) return items;
        NSMutableArray *m = [a mutableCopy];
        [m removeObjectAtIndex:1];
        return m;
    } @catch (NSException *e) { return items; }
}

// ============================================================ summary ======
static NSString *TD3Summary(void) {
    NSMutableString *s = [NSMutableString string];
    @synchronized (gLock) {
        [s appendFormat:@"TBDiag3/1.0 · 运行%.0fs · 基线=正式版4过滤(我的页降级已关)\n", TDNow()];
        // P1 cart
        NSMutableString *seen = [NSMutableString string];
        for (NSString *api in [gApiSeen allKeys]) {
            NSString *short4 = api;
            if ([short4 hasPrefix:@"mtop.taobao.wireless.home."]) short4 = [short4 substringFromIndex:26];
            else if ([short4 hasPrefix:@"mtop.relationrecommend."]) short4 = [short4 substringFromIndex:23];
            else if ([short4 hasPrefix:@"mtop."]) short4 = [short4 substringFromIndex:5];
            [seen appendFormat:@"%@×%@ ", short4, gApiSeen[api]];
        }
        [s appendFormat:@"[购] 见:{%@} 判读样本%d: 命中%d ok失败%d 串失败%d\n",
         seen, (int)[gCartRecs count], gCartMatch, gCartFailOk, gCartFailSub];
        // P1 bag
        [s appendFormat:@"[⑦] bag样本%d 正式版4会动手%d %@\n",
         (int)[gBagRecs count], gBagAct, gBagAnchorLine];
        // P2
        [s appendFormat:@"[我] 工厂总%d basementTip×%d\n", gFactoryTotal, gBaseCalls];
        if (gBaseCalls > 0) {
            NSString *b = gBaseLast;
            if ([b length] > 300) b = [[b substringToIndex:300] stringByAppendingString:@"…"];
            [s appendFormat:@"  末次:%@\n", b];
        }
        // P3
        NSMutableString *callers = [NSMutableString string];
        for (NSString *k in gFloatCallers) [callers appendFormat:@"%@×%@ ", k, gFloatCallers[k]];
        [s appendFormat:@"[横] getter×%d 调用方[%@] setter×%d\n", gFloatGetCalls, callers, gFloatSetCalls];
        if ([gFloatSetVal length]) {
            NSString *fv = gFloatSetVal;
            if ([fv length] > 260) fv = [[fv substringToIndex:260] stringByAppendingString:@"…"];
            [s appendFormat:@"  首次非空置入:%@\n", fv];
        }
        // P4
        [s appendFormat:@"[搜] parser×%d 最近剔除%d\n", gParserCalls, gSearchDroppedLast];
        if ([gSearchTypes length]) {
            NSString *t = gSearchTypes;
            if ([t length] > 300) t = [[t substringToIndex:300] stringByAppendingString:@"…"];
            [s appendFormat:@"  types:%@\n", t];
        }
        if ([gHookMiss length]) [s appendFormat:@"[hook失败] %@\n", gHookMiss];
    }
    if ([s length] > 1900) return [s substringToIndex:1900];
    return s;
}

static void TDWriteFile(void) {
    @try {
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (dir == nil) return;
        NSMutableString *out = [NSMutableString string];
        [out appendString:TD3Summary()];
        @synchronized (gLock) {
            [out appendFormat:@"\n[hook成功] %@\n[主二进制基址] 0x%lx\n",
             gHookOK ?: @"", (unsigned long)gMainBase];
            [out appendString:@"\n--- P1 cart records ---\n"];
            for (NSString *r in gCartRecs) [out appendFormat:@"%@\n", r];
            [out appendString:@"\n--- P1 bag records ---\n"];
            for (NSString *r in gBagRecs) [out appendFormat:@"%@\n", r];
            [out appendString:@"\n--- P2 basementTip first ---\n"];
            [out appendFormat:@"%@\n--- P2 basementTip last ---\n%@\n", gBaseFirst, gBaseLast];
            [out appendString:@"\n--- P4 search itemsArray (tItemType | name, 最近一次) ---\n"];
            [out appendFormat:@"%@\n", gSearchSnap];
            [out appendString:@"\n--- events ---\n"];
            for (NSString *e in gEvents) [out appendFormat:@"%@\n", e];
        }
        [out writeToFile:[dir stringByAppendingPathComponent:@"TBDiag3.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) { }
}

// -------------------------------------------------------- presentation -----
// TBDiag-proven presentation (v1/v2): top-VC walk, alert, 15s tick with
// anti-loss retry, re-show when new captures land (>=45s apart, <=10).
static id TDTopVC(void) {
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

static BOOL TDTryShow(void) {
    id top = TDTopVC();
    if (top == nil) return NO;
    if ([NSStringFromClass([top class]) containsString:@"Alert"]) return NO;
    id view = ((id (*)(id, SEL))objc_msgSend)(top, NSSelectorFromString(@"view"));
    id win = view ? ((id (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"window")) : nil;
    if (win == nil) return NO;
    Class acCls = objc_getClass("UIAlertController");
    Class aaCls = objc_getClass("UIAlertAction");
    if (acCls == Nil || aaCls == Nil) return NO;
    TDWriteFile();
    id ac = ((id (*)(id, SEL, id, id, long))objc_msgSend)(acCls,
        NSSelectorFromString(@"alertControllerWithTitle:message:preferredStyle:"),
        @"诊断3", TD3Summary(), 1L);
    id ok = ((id (*)(id, SEL, id, long, id))objc_msgSend)(aaCls,
        NSSelectorFromString(@"actionWithTitle:style:handler:"), @"知道了", 0L, nil);
    ((void (*)(id, SEL, id))objc_msgSend)(ac, NSSelectorFromString(@"addAction:"), ok);
    ((void (*)(id, SEL, id, char, id))objc_msgSend)(top,
        NSSelectorFromString(@"presentViewController:animated:completion:"), ac, 1, nil);
    gShows++;
    @synchronized (gLock) { gPending = NO; }
    gLastShowAt = TDNow();
    return YES;
}

static void TDTick(int tick) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        BOOL want = NO;
        @synchronized (gLock) {
            want = (gShows == 0) || (gPending && (TDNow() - gLastShowAt) >= 45.0 && gShows < 10);
        }
        if (want) TDTryShow();
        else {
            BOOL pend = NO;
            @synchronized (gLock) { pend = gPending; }
            if (pend) TDWriteFile(); // keep the file fresh even between shows
        }
        if (tick < 80) TDTick(tick + 1);
    });
}

// -------------------------------------------------------------- install ----
static BOOL TDHook(const char *clsName, const char *selName, BOOL isClass,
                   IMP repl, IMP *origOut, const char *tag) {
    Class cls = objc_getClass(clsName);
    if (cls == Nil) {
        @synchronized (gLock) { [gHookMiss appendFormat:@"%s(no-class) ", tag]; }
        return NO;
    }
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    Method m = isClass ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (m == NULL) {
        @synchronized (gLock) { [gHookMiss appendFormat:@"%s(no-method) ", tag]; }
        return NO;
    }
    if (*origOut != NULL) return YES;
    *origOut = method_getImplementation(m);
    method_setImplementation(m, repl);
    @synchronized (gLock) { [gHookOK appendFormat:@"%s ", tag]; }
    return YES;
}

static void TDInstallAll(void) {
    TDHook("MtopService", "getResponse:mrequest:", NO, (IMP)TCGetResponse, (IMP *)&gOrigGetResp, "getResp");
    TDHook("TBPLLayerFactory", "createLayerWithFrame:type:popRequest:attachVC:", NO, (IMP)TCFactoryCreate, (IMP *)&gOrigFactory, "factory");
    TDHook("TBHRContainerContentModel", "floatLayerSection", NO, (IMP)TDFloatLayerSection, (IMP *)&gOrigFloatGetter, "floatGet");
    TDHook("TBHRContainerContentModel", "setFloatLayerSection:", NO, (IMP)TDFloatSetLayerSection, (IMP *)&gOrigFloatSetter, "floatSet");
    TDHook("TBXSearchActivationTppParser", "getProcessedData:", NO, (IMP)TCGetProcessedData, (IMP *)&gOrigParser, "parser");
    TDHook("MTComponentModel", "creatComponent:componentData:", YES, (IMP)TDCreateComponent, (IMP *)&gOrigCreateComp, "createComp");
    TDHook("TBAppUIStyle", "currentTabbarVCItems", YES, (IMP)TCVCItems, (IMP *)&gOrigVCItems, "vcItems");
}

__attribute__((constructor)) static void TD3Entry(void) {
    @autoreleasepool {
        gStart = [NSDate date];
        gLock = [[NSObject alloc] init];
        gEvents = [NSMutableArray array];
        gHookOK = [NSMutableString string];
        gHookMiss = [NSMutableString string];
        gApiSeen = [NSMutableDictionary dictionary];
        gApiRecN = [NSMutableDictionary dictionary];
        gCartRecs = [NSMutableArray array];
        gBagRecs = [NSMutableArray array];
        gFloatCallers = [NSMutableDictionary dictionary];
        gMainBase = (uintptr_t)_dyld_get_image_header(0);
        TDInstallAll();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ TDInstallAll(); TDWriteFile(); });
        TDTick(0);
    }
}
