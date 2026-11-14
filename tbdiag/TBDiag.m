// TBDiag v2 — READ-ONLY census dylib for Taobao 10.69.0 (com.taobao.taobao4iphone).
//
// Purpose (second round, merged with the formal splash binary patch):
//   1. Splash regression counters (same hooks as v1): after the binary patch
//      the ItemSelector choose / Manager show counts are EXPECTED to be 0.
//   2. MTOP native-bridge census at MtopService: count every API by name,
//      record biz-parameter keys + scene-ish fields, dump response-free
//      request structure for candidate APIs (cart / recommend / my / second /
//      tab / guess / prefilter / pop). Pure counting — NO request is altered,
//      delayed or filtered; original IMPs are called and results returned
//      untouched.
//   3. MyTaobao visit markers: TBMyTaobaoViewController (Dojo) vs
//      TBMyTaobaoUltronViewController viewWillAppear, plus the Ultron second
//      screen senders (handleSecondScreenRequest: / secScreenRequest:).
//   4. Home floating bar candidates: TBHomeViewController displayFloatView:,
//      TBIFHFloatingBarNotifyEventHandler, TBMyTaobaoLifeCycle linked
//      notification, TBHRGatewayDataService uiRefresh:/responseDidEnd:.
//   5. PopLayer prefilter decision layer: TBPLInventoryModel isPass:...,
//      TBPLPreCheckCacheManager sendNetworkRequest:..., TBPLBaseTriggerService
//      isMatchBlackList:poplayerUri:, plus the second TBPLLayerFactory
//      variant v1 missed. Goal: see whether popId 128928 enters the
//      candidate set and where it is stopped. Read-only.
//   6. v1 groups 3/4 kept as regression (expected to stay 0).
//
// HARD RULE: every hook calls the original implementation and returns its
// result untouched. Nothing here filters, blocks or rewrites any data.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// ---------------------------------------------------------------- state ----
static NSDate *gStart = nil;
static id gLock = nil;
static NSMutableArray *gEvents = nil;
static NSMutableDictionary *gCaptures = nil;
static int gShows = 0;
static BOOL gPending = NO;
static double gLastShowAt = 0;

static double TBNow(void) { return [[NSDate date] timeIntervalSinceDate:gStart]; }

static void TBCapture(NSString *key, NSString *text) {
    if (key == nil || text == nil) return;
    @synchronized (gLock) {
        if (gCaptures[key] == nil || [key hasSuffix:@"!"]) {
            gCaptures[[key stringByReplacingOccurrencesOfString:@"!" withString:@""]] = text;
            gPending = YES;
        }
    }
}
static void TBSetCapture(NSString *key, NSString *text) {
    if (key == nil || text == nil) return;
    @synchronized (gLock) { gCaptures[key] = text; }
}
static void TBEvent(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    @synchronized (gLock) {
        [gEvents addObject:[NSString stringWithFormat:@"[+%.1fs] %@", TBNow(), msg]];
        while ([gEvents count] > 200) [gEvents removeObjectAtIndex:0];
    }
}

// ------------------------------------------------------- describe helpers ----
static NSString *TBShort(id obj, NSUInteger cap) {
    if (obj == nil) return @"(nil)";
    NSString *s = nil;
    @try { s = [obj description]; } @catch (NSException *e) { s = @"<desc-fail>"; }
    if (s == nil) s = @"";
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    if ([s length] > cap) s = [[s substringToIndex:cap] stringByAppendingString:@"…"];
    return s;
}

static void TBStructWalk(id obj, int depth, int *budget, NSMutableString *out) {
    if (obj == nil || *budget <= 0) { [out appendString:@"~"]; return; }
    (*budget)--;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        [out appendString:@"{"];
        int n = 0;
        for (id k in (NSDictionary *)obj) {
            if (n++ > 0) [out appendString:@" "];
            [out appendFormat:@"%@:", k];
            TBStructWalk(((NSDictionary *)obj)[k], depth + 1, budget, out);
            if (*budget <= 0) break;
        }
        [out appendString:@"}"];
        return;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        [out appendFormat:@"[%lu]", (unsigned long)[(NSArray *)obj count]];
        if (depth < 3 && [(NSArray *)obj count] > 0) {
            TBStructWalk([(NSArray *)obj firstObject], depth + 1, budget, out);
        }
        return;
    }
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *v = (NSString *)obj;
        if ([v length] > 0 && [v length] <= 40) [out appendFormat:@"'%@'", v];
        else [out appendFormat:@"<s%lu>", (unsigned long)[v length]];
        return;
    }
    if ([obj isKindOfClass:[NSNumber class]]) { [out appendFormat:@"%@", obj]; return; }
    [out appendFormat:@"<%@>", NSStringFromClass([obj class])];
}
static NSString *TBStruct(id obj, int budgetN) {
    NSMutableString *out = [NSMutableString string];
    int b = budgetN;
    TBStructWalk(obj, 0, &b, out);
    return out;
}

static NSString *TBProbe(id obj, NSArray *keys) {
    if (obj == nil) return @"";
    NSMutableString *out = [NSMutableString string];
    for (NSString *k in keys) {
        @try {
            id v = [obj valueForKey:k];
            if (v != nil) [out appendFormat:@"%@=%@ ", k, TBShort(v, 60)];
        } @catch (NSException *e) { }
    }
    return out;
}

static NSString *TBFindScene(id obj, int depth, int *budget) {
    if (obj == nil || depth > 4 || *budget <= 0) return nil;
    (*budget)--;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            NSString *ks = [k description];
            id v = ((NSDictionary *)obj)[k];
            if (([ks isEqualToString:@"scene"] || [ks isEqualToString:@"sceneName"] ||
                 [ks isEqualToString:@"pageName"] || [ks isEqualToString:@"bizCode"] ||
                 [ks isEqualToString:@"tabId"]) &&
                [v isKindOfClass:[NSString class]]) {
                return [NSString stringWithFormat:@"%@=%@", ks, v];
            }
        }
        for (id k in (NSDictionary *)obj) {
            NSString *r = TBFindScene(((NSDictionary *)obj)[k], depth + 1, budget);
            if (r) return r;
        }
        return nil;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) {
            NSString *r = TBFindScene(e, depth + 1, budget);
            if (r) return r;
        }
    }
    return nil;
}

static id TBMsg0(id obj, const char *selName) {
    if (obj == nil) return nil;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

// ============================================================== GROUP 1 =====
// Splash regression (v1 hooks, unchanged semantics).
static int gGateColdCalls = 0, gGateColdYes = 0, gGateHotCalls = 0, gGateHotYes = 0;
static int gMgrCold = 0, gMgrHot = 0, gMgrCur = 0, gMgrExp = 0;
typedef BOOL (*BoolIMP)(id, SEL);
static BoolIMP gOrigGateColdI = NULL, gOrigGateColdC = NULL, gOrigGateHotC = NULL, gOrigMgrHot = NULL;
static BOOL TBDGateColdI(id self, SEL _cmd) {
    BOOL r = gOrigGateColdI ? gOrigGateColdI(self, _cmd) : NO;
    gGateColdCalls++; if (r) gGateColdYes++;
    return r;
}
static BOOL TBDGateColdC(id self, SEL _cmd) {
    BOOL r = gOrigGateColdC ? gOrigGateColdC(self, _cmd) : NO;
    gGateColdCalls++; if (r) gGateColdYes++;
    return r;
}
static BOOL TBDGateHotC(id self, SEL _cmd) {
    BOOL r = gOrigGateHotC ? gOrigGateHotC(self, _cmd) : NO;
    gGateHotCalls++; if (r) gGateHotYes++;
    return r;
}
typedef void (*VoidIdIMP)(id, SEL, id);
static VoidIdIMP gOrigMgrCold = NULL;
static void TBDMgrCold(id self, SEL _cmd, id arg) {
    gMgrCold++;
    TBEvent(@"TBBootImageManager showBootImageAtColdStart:");
    if (gOrigMgrCold) gOrigMgrCold(self, _cmd, arg);
}
static BOOL TBDMgrHot(id self, SEL _cmd) {
    BOOL r = gOrigMgrHot ? gOrigMgrHot(self, _cmd) : NO;
    gMgrHot++;
    TBEvent(@"TBBootImageManager showBootImageAtHotStart -> %d", r);
    return r;
}
typedef BOOL (*ShowItemIMP)(id, SEL, BOOL, BOOL, id);
static ShowItemIMP gOrigShowCur = NULL, gOrigExpose = NULL;
static BOOL TBDShowCur(id self, SEL _cmd, BOOL a, BOOL b, id cfg) {
    BOOL r = gOrigShowCur ? gOrigShowCur(self, _cmd, a, b, cfg) : NO;
    gMgrCur++;
    TBEvent(@"TBBootImageManager showCurrentItem -> %d", r);
    return r;
}
static BOOL TBDExpose(id self, SEL _cmd, BOOL a, BOOL b, id cfg) {
    BOOL r = gOrigExpose ? gOrigExpose(self, _cmd, a, b, cfg) : NO;
    gMgrExp++;
    TBEvent(@"TBBootImageManager exposeSplashDisplay -> %d", r);
    return r;
}
static int gSelCold = 0, gSelHot = 0, gSelProc = 0, gTraceShow = 0;
static NSString *gTraceItem = @"";
typedef void (*ChooseVIMP)(id, SEL, id, BOOL, id);
static ChooseVIMP gOrigChooseV = NULL;
static void TBDChooseV(id self, SEL _cmd, id info, BOOL cold, id block) {
    if (cold) gSelCold++; else gSelHot++;
    TBEvent(@"ItemSelector chooseValid(completeBlock:) cold=%d", cold);
    if (gOrigChooseV) gOrigChooseV(self, _cmd, info, cold, block);
}
typedef BOOL (*ChooseBIMP)(id, SEL, id, BOOL, id);
static ChooseBIMP gOrigChooseB = NULL;
static BOOL TBDChooseB(id self, SEL _cmd, id info, BOOL cold, id block) {
    BOOL r = gOrigChooseB ? gOrigChooseB(self, _cmd, info, cold, block) : NO;
    if (cold) gSelCold++; else gSelHot++;
    TBEvent(@"ItemSelector chooseValid(completion:) cold=%d -> %d", cold, r);
    return r;
}
typedef void (*ProcIMP)(id, SEL, BOOL, id);
static ProcIMP gOrigProc = NULL;
static void TBDProc(id self, SEL _cmd, BOOL cold, id block) {
    gSelProc++;
    TBEvent(@"ItemSelector processCommercialSplash cold=%d", cold);
    if (gOrigProc) gOrigProc(self, _cmd, cold, block);
}
typedef void (*TraceIMP)(id, SEL, BOOL, id, id);
static TraceIMP gOrigTrace = NULL;
static void TBDTrace(id self, SEL _cmd, BOOL isDegrade, id reason, id item) {
    gTraceShow++;
    NSString *probe = TBProbe(item, @[@"bizCode", @"templateName", @"name", @"splashName",
                                      @"type", @"subType", @"picUrl", @"imgUrl", @"url"]);
    if ([probe length] == 0) probe = TBShort(item, 120);
    gTraceItem = probe;
    TBEvent(@"ItemSelector traceShow item: %@", probe);
    if (gOrigTrace) gOrigTrace(self, _cmd, isDegrade, reason, item);
}
static int gSPStart = 0, gSPShown = 0;
static VoidIdIMP gOrigSPStart = NULL, gOrigSPShown = NULL;
static id TBDSPStart(id self, SEL _cmd, id ctx) {
    gSPStart++;
    TBEvent(@"SPSplashController onStart:");
    return gOrigSPStart ? ((id (*)(id, SEL, id))gOrigSPStart)(self, _cmd, ctx) : nil;
}
static void TBDSPShown(id self, SEL _cmd, id ctx) {
    gSPShown++;
    TBEvent(@"SPSplashController onViewShown:");
    if (gOrigSPShown) gOrigSPShown(self, _cmd, ctx);
}
static int gTXReq = 0, gTXAnim = 0;
typedef void (*TXClaimIMP)(id, SEL, id, long long, BOOL, id);
static TXClaimIMP gOrigTXClaim = NULL;
static void TBDTXClaim(id self, SEL _cmd, id a, long long biz, BOOL cold, id block) {
    gTXReq++;
    TBEvent(@"TX startClaimedCouponRequest biz=%lld cold=%d", biz, cold);
    if (gOrigTXClaim) gOrigTXClaim(self, _cmd, a, biz, cold, block);
}
typedef void (*TXCartIMP)(id, SEL, id, long long, BOOL, id, id);
static TXCartIMP gOrigTXCart = NULL;
static void TBDTXCart(id self, SEL _cmd, id a, long long biz, BOOL cold, id s, id f) {
    gTXReq++;
    TBEvent(@"TX startAddToCartRequest biz=%lld cold=%d", biz, cold);
    if (gOrigTXCart) gOrigTXCart(self, _cmd, a, biz, cold, s, f);
}
typedef void (*TXAnimIMP)(id, SEL, id, id);
static TXAnimIMP gOrigTXAnim = NULL;
static void TBDTXAnim(id self, SEL _cmd, id item, id block) {
    gTXAnim++;
    TBEvent(@"TX getTBAnimatedImageWithItem");
    if (gOrigTXAnim) gOrigTXAnim(self, _cmd, item, block);
}

// ============================================================== GROUP 2 =====
// Home PopLayer popup (v1) + prefilter decision layer (v2).
static int gPopNotify = 0, gPopEvt = 0, gPopCold = 0, gPopBack = 0, gInvQ = 0, gFactory = 0, gAwesomeTrig = 0;
static NSString *gPopProbe = @"", *gFactoryType = @"";
typedef void (*VoidIMP)(id, SEL);
static VoidIMP gOrigPopNotify = NULL, gOrigPopCold = NULL, gOrigPopBack = NULL;
static void TBDPopNotify(id self, SEL _cmd) {
    gPopNotify++;
    if (gOrigPopNotify) gOrigPopNotify(self, _cmd);
}
static void TBDPopCold(id self, SEL _cmd) {
    gPopCold++;
    if (gOrigPopCold) gOrigPopCold(self, _cmd);
}
static void TBDPopBack(id self, SEL _cmd) {
    gPopBack++;
    if (gOrigPopBack) gOrigPopBack(self, _cmd);
}
typedef void (*PopEvtIMP)(id, SEL, id, id, id);
static PopEvtIMP gOrigPopEvt = NULL;
static void TBDPopEvt(id self, SEL _cmd, id evt, id src, id params) {
    gPopEvt++;
    TBCapture(@"popEvtParams", TBStruct(params, 120));
    if (gOrigPopEvt) gOrigPopEvt(self, _cmd, evt, src, params);
}
typedef id (*InvIMP)(id, SEL, id);
static InvIMP gOrigInvC = NULL, gOrigInvI = NULL;
static id TBDInvC(id self, SEL _cmd, id arg) {
    id r = gOrigInvC ? gOrigInvC(self, _cmd, arg) : nil;
    gInvQ++;
    TBCapture(@"invArg", TBStruct(arg, 80));
    TBSetCapture(@"invRetLast", TBStruct(r, 200));
    return r;
}
static id TBDInvI(id self, SEL _cmd, id arg) {
    id r = gOrigInvI ? gOrigInvI(self, _cmd, arg) : nil;
    gInvQ++;
    TBCapture(@"invArg", TBStruct(arg, 80));
    TBSetCapture(@"invRetLast", TBStruct(r, 200));
    return r;
}
typedef struct { double x, y, w, h; } TBRect;
typedef id (*FactoryIMP)(id, SEL, TBRect, id, id, id);
static FactoryIMP gOrigFactory = NULL, gOrigFactory2 = NULL;
static void TBDNoteFactory(id type, id popReq) {
    gFactory++;
    gFactoryType = TBShort(type, 60);
    NSString *probe = TBProbe(popReq, @[@"popId", @"templateId", @"id", @"name",
                                        @"type", @"popName", @"layerId", @"configId", @"popKey"]);
    if ([probe length] == 0) probe = TBShort(popReq, 150);
    gPopProbe = probe;
    TBEvent(@"TBPLLayerFactory createLayer type=%@ pop: %@", gFactoryType, probe);
    TBCapture(@"popRequest", TBStruct(popReq, 150));
}
static id TBDFactory(id self, SEL _cmd, TBRect fr, id type, id popReq, id vc) {
    TBDNoteFactory(type, popReq);
    return gOrigFactory ? gOrigFactory(self, _cmd, fr, type, popReq, vc) : nil;
}
static id TBDFactory2(id self, SEL _cmd, TBRect fr, id type, id config, id url) {
    TBDNoteFactory(type, config);
    TBEvent(@"TBPLLayerFactory createLayer(config:) url=%@", TBShort(url, 80));
    return gOrigFactory2 ? gOrigFactory2(self, _cmd, fr, type, config, url) : nil;
}
typedef void (*TrigIMP)(id, SEL, id, id);
static TrigIMP gOrigTrig = NULL;
static NSString *gAwesomeEvents = @"";
static void TBDTrig(id self, SEL _cmd, id params, id event) {
    gAwesomeTrig++;
    NSString *e = TBShort(event, 50);
    if ([gAwesomeEvents rangeOfString:e].location == NSNotFound && [gAwesomeEvents length] < 300) {
        gAwesomeEvents = [gAwesomeEvents stringByAppendingFormat:@"%@ ", e];
    }
    if (gOrigTrig) gOrigTrig(self, _cmd, params, event);
}
typedef id (*ContainersIMP)(id, SEL, id);
static ContainersIMP gOrigContainers = NULL;
static NSString *gContainers = @"";
static id TBDContainers(id self, SEL _cmd, id pageId) {
    id r = gOrigContainers ? gOrigContainers(self, _cmd, pageId) : nil;
    NSString *s = TBShort(r, 200);
    if (![s isEqualToString:gContainers]) gContainers = s;
    return r;
}
// ---- v2: prefilter decision layer ----
static int gIsPass = 0, gIsPassYes = 0, gPreCheck = 0, gBlackList = 0, gBlackHit = 0;
static NSString *gIsPassProbe = @"", *gPreCheckKeys = @"", *gBlackLast = @"";
typedef BOOL (*IsPassIMP)(id, SEL, id, id, id, long long);
static IsPassIMP gOrigIsPass = NULL;
static BOOL TBDIsPass(id self, SEL _cmd, id a, id param, id layer, long long ts) {
    BOOL r = gOrigIsPass ? gOrigIsPass(self, _cmd, a, param, layer, ts) : NO;
    gIsPass++; if (r) gIsPassYes++;
    NSString *probe = TBProbe(layer, @[@"popId", @"id", @"uri", @"poplayerUri", @"name", @"popName", @"templateId"]);
    if ([probe length] == 0) probe = TBProbe(param, @[@"popId", @"id", @"uri", @"poplayerUri"]);
    if ([probe length] == 0) probe = TBShort(layer, 100);
    gIsPassProbe = [NSString stringWithFormat:@"%@ ->%d", probe, r];
    TBEvent(@"TBPLInventoryModel isPass -> %d %@", r, probe);
    return r;
}
typedef void (*PreCheckIMP)(id, SEL, id, id, id);
static PreCheckIMP gOrigPreCheck = NULL;
static void TBDPreCheck(id self, SEL _cmd, id a, id indexMap, id block) {
    gPreCheck++;
    if ([indexMap isKindOfClass:[NSDictionary class]]) {
        gPreCheckKeys = TBShort([(NSDictionary *)indexMap allKeys], 200);
    } else {
        gPreCheckKeys = TBShort(indexMap, 120);
    }
    TBEvent(@"TBPLPreCheckCacheManager sendNetworkRequest indexKeys: %@", gPreCheckKeys);
    TBCapture(@"preCheckMap", TBStruct(indexMap, 200));
    if (gOrigPreCheck) gOrigPreCheck(self, _cmd, a, indexMap, block);
}
typedef BOOL (*BlackIMP)(id, SEL, id, id);
static BlackIMP gOrigBlack = NULL;
static BOOL TBDBlack(id self, SEL _cmd, id a, id uri) {
    BOOL r = gOrigBlack ? gOrigBlack(self, _cmd, a, uri) : NO;
    gBlackList++; if (r) gBlackHit++;
    gBlackLast = [NSString stringWithFormat:@"%@ ->%d", TBShort(uri, 80), r];
    TBEvent(@"TBPL isMatchBlackList uri=%@ -> %d", TBShort(uri, 80), r);
    return r;
}

// ============================================================== GROUP 3 =====
// MTOP census at MtopService (v2 core). Read-only counting.
static int gMtopSend = 0, gMtopAsync = 0, gMtopAsyncF = 0, gMtopSync = 0, gMtopPrefetch = 0;
static NSMutableDictionary *gApiCounts = nil;   // apiName -> NSNumber
static NSMutableDictionary *gApiScene = nil;    // apiName -> scene string (first found)
static NSMutableArray *gApiOrder = nil;         // first-seen order

static BOOL TBDIsKeywordApi(NSString *api) {
    if (api == nil) return NO;
    NSString *l = [api lowercaseString];
    static NSArray *kws = nil;
    if (kws == nil) kws = @[@"cart", @"recommend", @"recmd", @"mytaobao", @"second",
                            @"tab", @"guess", @"prefilter", @"pop", @"volvo", @"icart",
                            @"splash", @"awesome", @"newface"];
    for (NSString *k in kws) if ([l containsString:k]) return YES;
    return NO;
}

static void TBDNoteApi(NSString *entry, id req) {
    NSString *api = nil;
    id biz = nil;
    @try {
        id n = TBMsg0(req, "getApiName");
        if ([n isKindOfClass:[NSString class]]) api = n;
        biz = TBMsg0(req, "getBizParameters");
    } @catch (NSException *e) { }
    if (api == nil) api = req ? NSStringFromClass([req class]) : @"(nil-req)";
    int countNow = 0;
    BOOL first = NO;
    @synchronized (gLock) {
        if (gApiCounts == nil) {
            gApiCounts = [NSMutableDictionary dictionary];
            gApiScene = [NSMutableDictionary dictionary];
            gApiOrder = [NSMutableArray array];
        }
        NSNumber *c = gApiCounts[api];
        first = (c == nil);
        countNow = [c intValue] + 1;
        gApiCounts[api] = @(countNow);
        if (first) [gApiOrder addObject:api];
    }
    if (biz != nil) {
        int budget = 400;
        NSString *scene = TBFindScene(biz, 0, &budget);
        if (scene) {
            @synchronized (gLock) { if (gApiScene[api] == nil) gApiScene[api] = scene; }
        }
    }
    if (first) TBEvent(@"MTOP[%@] first: %@", entry, api);
    if (TBDIsKeywordApi(api) && countNow <= 2) {
        NSString *key = [NSString stringWithFormat:@"api:%@", api];
        NSMutableString *txt = [NSMutableString stringWithFormat:@"entry=%@ count=%d\n", entry, countNow];
        if (biz != nil) {
            [txt appendFormat:@"bizKeys: %@\n", [biz isKindOfClass:[NSDictionary class]] ? TBShort([(NSDictionary *)biz allKeys], 200) : TBShort(biz, 100)];
            [txt appendFormat:@"biz: %@\n", TBStruct(biz, 250)];
            @try {
                id ext = TBMsg0(req, "getExtParameters");
                if (ext) [txt appendFormat:@"ext: %@\n", TBStruct(ext, 120)];
                id pn = TBMsg0(req, "pageName");
                if (pn) [txt appendFormat:@"pageName: %@\n", TBShort(pn, 80)];
            } @catch (NSException *e) { }
        }
        TBCapture(key, txt);
    }
}

typedef void (*MtopSendIMP)(id, SEL, id, id, id);
static MtopSendIMP gOrigMtopSend = NULL;
static void TBDMtopSend(id self, SEL _cmd, id req, id del, id filter) {
    gMtopSend++;
    TBDNoteApi(@"sending", req);
    if (gOrigMtopSend) gOrigMtopSend(self, _cmd, req, del, filter);
}
typedef void (*MtopAsyncIMP)(id, SEL, id, id);
static MtopAsyncIMP gOrigMtopAsync = NULL;
static void TBDMtopAsync(id self, SEL _cmd, id req, id del) {
    gMtopAsync++;
    TBDNoteApi(@"async", req);
    if (gOrigMtopAsync) gOrigMtopAsync(self, _cmd, req, del);
}
static MtopSendIMP gOrigMtopAsyncF = NULL;
static void TBDMtopAsyncF(id self, SEL _cmd, id req, id del, id filter) {
    gMtopAsyncF++;
    TBDNoteApi(@"asyncF", req);
    if (gOrigMtopAsyncF) gOrigMtopAsyncF(self, _cmd, req, del, filter);
}
typedef id (*MtopSyncIMP)(id, SEL, id);
static MtopSyncIMP gOrigMtopSync = NULL;
static id TBDMtopSync(id self, SEL _cmd, id req) {
    gMtopSync++;
    TBDNoteApi(@"sync", req);
    return gOrigMtopSync ? gOrigMtopSync(self, _cmd, req) : nil;
}
typedef void (*MtopPrefetchIMP)(id, SEL, id, double, id, id);
static MtopPrefetchIMP gOrigMtopPrefetch = NULL;
static void TBDMtopPrefetch(id self, SEL _cmd, id req, double t, id cmp, id evt) {
    gMtopPrefetch++;
    TBDNoteApi(@"prefetch", req);
    if (gOrigMtopPrefetch) gOrigMtopPrefetch(self, _cmd, req, t, cmp, evt);
}

// ============================================================== GROUP 4 =====
// MyTaobao visit markers + Ultron second screen senders (v2) and v1 group 4.
static int gMyDojo = 0, gMyUltron = 0, gSecHandle = 0, gSecReq = 0;
static NSString *gMyLast = @"";
typedef void (*AppearIMP)(id, SEL, BOOL);
static AppearIMP gOrigMyDojo = NULL, gOrigMyUltron = NULL;
static void TBDMyDojo(id self, SEL _cmd, BOOL anim) {
    gMyDojo++;
    gMyLast = [NSString stringWithFormat:@"Dojo@%.0fs", TBNow()];
    TBEvent(@"MyTaobao(Dojo) viewWillAppear #%d", gMyDojo);
    if (gOrigMyDojo) gOrigMyDojo(self, _cmd, anim);
}
static void TBDMyUltron(id self, SEL _cmd, BOOL anim) {
    gMyUltron++;
    gMyLast = [NSString stringWithFormat:@"Ultron@%.0fs", TBNow()];
    TBEvent(@"MyTaobao(Ultron) viewWillAppear #%d", gMyUltron);
    if (gOrigMyUltron) gOrigMyUltron(self, _cmd, anim);
}
static VoidIdIMP gOrigSecHandle = NULL;
static void TBDSecHandle(id self, SEL _cmd, id arg) {
    gSecHandle++;
    TBEvent(@"UltronMainService handleSecondScreenRequest: %@", TBShort(arg, 80));
    TBCapture(@"secHandleArg", TBStruct(arg, 150));
    if (gOrigSecHandle) gOrigSecHandle(self, _cmd, arg);
}
typedef id (*SecReqIMP)(id, SEL, id);
static SecReqIMP gOrigSecReq = NULL;
static id TBDSecReq(id self, SEL _cmd, id arg) {
    id r = gOrigSecReq ? gOrigSecReq(self, _cmd, arg) : nil;
    gSecReq++;
    TBEvent(@"UltronMainService secScreenRequest: %@ -> %@", TBShort(arg, 60), TBShort(r, 60));
    TBCapture(@"secReqRet", TBStruct(r, 200));
    return r;
}
// v1 group 4 (regression, expected 0)
static int gSecData = 0, gFetchTab = 0, gEmbedTab = 0, gTabReq = 0, gCacheTab = 0;
static NSString *gSecApi = @"", *gTabIds = @"", *gMainKeys = @"";
static VoidIdIMP gOrigSecData = NULL, gOrigSecApi = NULL;
static void TBDSecApi(id self, SEL _cmd, id name) {
    gSecApi = TBShort(name, 80);
    if (gOrigSecApi) gOrigSecApi(self, _cmd, name);
}
static void TBDSecData(id self, SEL _cmd, id data) {
    gSecData++;
    TBCapture(@"secData", TBStruct(data, 300));
    if (gOrigSecData) gOrigSecData(self, _cmd, data);
}
typedef void (*FetchTabIMP)(id, SEL, id, id, id);
static FetchTabIMP gOrigFetchTab = NULL;
static void TBDFetchTab(id self, SEL _cmd, id tab, id content, id completion) {
    gFetchTab++;
    if (gOrigFetchTab) gOrigFetchTab(self, _cmd, tab, content, completion);
}
typedef id (*EmbedIMP)(id, SEL, id, id, long long, double);
static EmbedIMP gOrigEmbed = NULL;
static id TBDEmbed(id self, SEL _cmd, id content, id container, long long idx, double offY) {
    id r = gOrigEmbed ? gOrigEmbed(self, _cmd, content, container, idx, offY) : nil;
    gEmbedTab++;
    return r;
}
typedef void (*CacheTabIMP)(id, SEL, id, id);
static CacheTabIMP gOrigCacheTab = NULL;
static void TBDCacheTab(id self, SEL _cmd, id tab, id content) {
    gCacheTab++;
    if (gOrigCacheTab) gOrigCacheTab(self, _cmd, tab, content);
}
typedef void (*TabReqIMP)(id, SEL, id, id, id, long long, id, id);
static TabReqIMP gOrigTabReq = NULL;
static void TBDTabReq(id self, SEL _cmd, id tabId, id appId, id channel, long long page, id param, id block) {
    gTabReq++;
    if (gOrigTabReq) gOrigTabReq(self, _cmd, tabId, appId, channel, page, param, block);
}
static VoidIdIMP gOrigMTBData = NULL, gOrigMTBModule = NULL;
static void TBDMTBData(id self, SEL _cmd, id data) {
    if ([gMainKeys length] == 0 && [data isKindOfClass:[NSDictionary class]]) {
        gMainKeys = TBShort([(NSDictionary *)data allKeys], 250);
    }
    if (gOrigMTBData) gOrigMTBData(self, _cmd, data);
}
static void TBDMTBModule(id self, SEL _cmd, id data) {
    if (gOrigMTBModule) gOrigMTBModule(self, _cmd, data);
}

// ============================================================== GROUP 5 =====
// Cart recommend v1 (regression, expected 0; real cart APIs land in census).
static int gCartCalls = 0, gCartOK = 0, gCartFail = 0, gHasRead = 0, gHasWrite = 0;
static NSString *gCartScene = @"", *gHasLast = @"";
typedef void (^TBDBlock1)(id);
typedef void (*CartIMP)(id, SEL, id, id, TBDBlock1, TBDBlock1);
static CartIMP gOrigCart = NULL;
static void TBDCart(id self, SEL _cmd, id a, id params, TBDBlock1 ok, TBDBlock1 fail) {
    gCartCalls++;
    int budget = 400;
    NSString *scene = TBFindScene(params, 0, &budget);
    if (scene) gCartScene = scene;
    if (gOrigCart) gOrigCart(self, _cmd, a, params, ok, fail);
}
static BoolIMP gOrigHas = NULL;
static BOOL TBDHas(id self, SEL _cmd) {
    BOOL r = gOrigHas ? gOrigHas(self, _cmd) : NO;
    gHasRead++;
    return r;
}
typedef void (*SetBoolIMP)(id, SEL, BOOL);
static SetBoolIMP gOrigSetHas = NULL;
static void TBDSetHas(id self, SEL _cmd, BOOL v) {
    gHasWrite++;
    if (gOrigSetHas) gOrigSetHas(self, _cmd, v);
}

// ============================================================== GROUP 6 =====
// Home floating bar candidates (v2).
static int gFloatView = 0, gFloatEvt = 0, gFloatLink = 0, gGwUI = 0, gGwEnd = 0;
static NSString *gFloatProbe = @"", *gGwProbe = @"";
static VoidIdIMP gOrigFloatView = NULL;
static void TBDFloatView(id self, SEL _cmd, id v) {
    gFloatView++;
    gFloatProbe = [NSString stringWithFormat:@"%@ %@", NSStringFromClass([v class]), TBShort(v, 80)];
    TBEvent(@"TBHomeViewController displayFloatView: %@", gFloatProbe);
    TBCapture(@"floatView", TBStruct(v, 150));
    if (gOrigFloatView) gOrigFloatView(self, _cmd, v);
}
typedef void (*FloatEvtIMP)(id, SEL, id, id, id);
static FloatEvtIMP gOrigFloatEvt = NULL;
static void TBDFloatEvt(id self, SEL _cmd, id evt, id args, id ctx) {
    gFloatEvt++;
    TBEvent(@"TBIFHFloatingBarNotifyEventHandler handleEvent args=%@", TBShort(args, 80));
    TBCapture(@"floatEvtArgs", TBStruct(args, 200));
    if (gOrigFloatEvt) gOrigFloatEvt(self, _cmd, evt, args, ctx);
}
static VoidIdIMP gOrigFloatLink = NULL;
static void TBDFloatLink(id self, SEL _cmd, id note) {
    gFloatLink++;
    TBEvent(@"TBMyTaobaoLifeCycle handleHomePageFloatingBarLinkedNotification: %@", TBShort(note, 100));
    if (gOrigFloatLink) gOrigFloatLink(self, _cmd, note);
}
static VoidIdIMP gOrigGwUI = NULL, gOrigGwEnd = NULL;
static void TBDGwUI(id self, SEL _cmd, id arg) {
    gGwUI++;
    @try {
        id fl = [self valueForKey:@"floatLayerSection"];
        if (fl) gGwProbe = [NSString stringWithFormat:@"floatLayerSection=%@", TBShort(fl, 120)];
    } @catch (NSException *e) { }
    if (gOrigGwUI) gOrigGwUI(self, _cmd, arg);
}
static void TBDGwEnd(id self, SEL _cmd, id arg) {
    gGwEnd++;
    TBCapture(@"gwRespArg", TBStruct(arg, 150));
    if (gOrigGwEnd) gOrigGwEnd(self, _cmd, arg);
}

// ------------------------------------------------------------ reporting ----
static NSMutableString *gHookOK = nil, *gHookMiss = nil;

static NSArray *TBDSortedApis(void) {
    @synchronized (gLock) {
        if (gApiCounts == nil) return @[];
        return [gApiCounts keysSortedByValueUsingComparator:^NSComparisonResult(id a, id b) {
            return [b compare:a];
        }];
    }
}

static NSString *TBDSummary(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"TBDiag v2 淘宝10.69 只读普查\n"];
    [s appendFormat:@"[开屏回归] 选片cold=%d hot=%d proc=%d | 展示 cold=%d hot=%d cur=%d exp=%d | SP shown=%d | TX=%d/%d | trace=%d (补丁生效应全0)\n",
        gSelCold, gSelHot, gSelProc, gMgrCold, gMgrHot, gMgrCur, gMgrExp, gSPShown, gTXReq, gTXAnim, gTraceShow];
    int total = gMtopSend + gMtopAsync + gMtopAsyncF + gMtopSync + gMtopPrefetch;
    NSUInteger distinct = 0;
    @synchronized (gLock) { distinct = [gApiCounts count]; }
    [s appendFormat:@"[普查] MTOP总=%d (send=%d async=%d asyncF=%d sync=%d pre=%d) 不同API=%lu\n",
        total, gMtopSend, gMtopAsync, gMtopAsyncF, gMtopSync, gMtopPrefetch, (unsigned long)distinct];
    // keyword APIs first in summary
    int shown = 0;
    for (NSString *api in TBDSortedApis()) {
        if (!TBDIsKeywordApi(api)) continue;
        NSString *scene = nil;
        @synchronized (gLock) { scene = gApiScene[api]; }
        [s appendFormat:@"  %@ x%@%@\n", api, gApiCounts[api], scene ? [NSString stringWithFormat:@" [%@]", scene] : @""];
        if (++shown >= 9) break;
    }
    [s appendFormat:@"[弹窗] notify=%d invQ=%d factory=%d | isPass=%d(过%d) preCheck=%d black=%d(中%d)\n  isPass末: %@\n  preKeys: %@\n",
        gPopNotify, gInvQ, gFactory, gIsPass, gIsPassYes, gPreCheck, gBlackList, gBlackHit,
        gIsPassProbe, gPreCheckKeys];
    [s appendFormat:@"[横条] floatView=%d floatEvt=%d linked=%d gwUI=%d gwEnd=%d\n  float: %@\n",
        gFloatView, gFloatEvt, gFloatLink, gGwUI, gGwEnd, gFloatProbe];
    [s appendFormat:@"[我的] Dojo=%d Ultron=%d 末=%@ | secHandle=%d secReq=%d | v1组 setData=%d fetchTab=%d tabReq=%d\n",
        gMyDojo, gMyUltron, gMyLast, gSecHandle, gSecReq, gSecData, gFetchTab, gTabReq];
    [s appendFormat:@"[购物车v1组] getCartRecommend=%d has读=%d 写=%d (真实购物车API看普查)\n",
        gCartCalls, gHasRead, gHasWrite];
    [s appendFormat:@"[hook失败] %@\n", gHookMiss ?: @""];
    if ([s length] > 1900) return [s substringToIndex:1900];
    return s;
}

static void TBDWriteFile(void) {
    @try {
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (dir == nil) return;
        NSMutableString *out = [NSMutableString string];
        [out appendString:TBDSummary()];
        [out appendFormat:@"\n[hook成功] %@\n", gHookOK ?: @""];
        @synchronized (gLock) {
            [out appendString:@"\n--- API census (count desc) ---\n"];
            for (NSString *api in TBDSortedApis()) {
                NSString *scene = gApiScene[api];
                [out appendFormat:@"%@ x%@%@\n", api, gApiCounts[api], scene ? [NSString stringWithFormat:@" [%@]", scene] : @""];
            }
            for (NSString *k in gCaptures) {
                [out appendFormat:@"\n--- capture %@ ---\n%@\n", k, gCaptures[k]];
            }
            [out appendString:@"\n--- events ---\n"];
            for (NSString *e in gEvents) [out appendFormat:@"%@\n", e];
        }
        [out writeToFile:[dir stringByAppendingPathComponent:@"TBDiag-v2.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) { }
}

// -------------------------------------------------------- presentation -----
static id TBDTopVC(void) {
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

static BOOL TBDTryShow(void) {
    id top = TBDTopVC();
    if (top == nil) return NO;
    if ([NSStringFromClass([top class]) containsString:@"Alert"]) return NO;
    id view = ((id (*)(id, SEL))objc_msgSend)(top, NSSelectorFromString(@"view"));
    id win = view ? ((id (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"window")) : nil;
    if (win == nil) return NO;
    Class acCls = objc_getClass("UIAlertController");
    Class aaCls = objc_getClass("UIAlertAction");
    if (acCls == Nil || aaCls == Nil) return NO;
    TBDWriteFile();
    id ac = ((id (*)(id, SEL, id, id, long))objc_msgSend)(acCls,
        NSSelectorFromString(@"alertControllerWithTitle:message:preferredStyle:"),
        @"TBDiag v2", TBDSummary(), 1L);
    id ok = ((id (*)(id, SEL, id, long, id))objc_msgSend)(aaCls,
        NSSelectorFromString(@"actionWithTitle:style:handler:"), @"知道了", 0L, nil);
    ((void (*)(id, SEL, id))objc_msgSend)(ac, NSSelectorFromString(@"addAction:"), ok);
    ((void (*)(id, SEL, id, char, id))objc_msgSend)(top,
        NSSelectorFromString(@"presentViewController:animated:completion:"), ac, 1, nil);
    gShows++;
    gPending = NO;
    gLastShowAt = TBNow();
    return YES;
}

static void TBDTick(int tick) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        BOOL want = (gShows == 0) || (gPending && (TBNow() - gLastShowAt) >= 45.0 && gShows < 10);
        if (want) TBDTryShow();
        if (tick < 80) TBDTick(tick + 1);
    });
}

// -------------------------------------------------------------- install ----
static BOOL TBDHook(const char *clsName, const char *selName, BOOL isClass,
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

static void TBDInstallAll(void) {
    // Group 1: splash regression
    TBDHook("TBBootImageManager", "isColdTaobaoSplashAdvWillShow", NO, (IMP)TBDGateColdI, (IMP *)&gOrigGateColdI, "gateColdI");
    TBDHook("TBBootImageManager", "isColdTaobaoSplashAdvWillShow", YES, (IMP)TBDGateColdC, (IMP *)&gOrigGateColdC, "gateColdC");
    TBDHook("TBBootImageManager", "isHotStartTaobaoSplashAdvWillShow", YES, (IMP)TBDGateHotC, (IMP *)&gOrigGateHotC, "gateHotC");
    TBDHook("TBBootImageManager", "showBootImageAtColdStart:", NO, (IMP)TBDMgrCold, (IMP *)&gOrigMgrCold, "mgrCold");
    TBDHook("TBBootImageManager", "showBootImageAtHotStart", NO, (IMP)TBDMgrHot, (IMP *)&gOrigMgrHot, "mgrHot");
    TBDHook("TBBootImageManager", "showCurrentItem:isOpenUrlLaunch:configuration:", NO, (IMP)TBDShowCur, (IMP *)&gOrigShowCur, "showCur");
    TBDHook("TBBootImageManager", "exposeSplashDisplay:isOpenUrlLaunch:configuration:", NO, (IMP)TBDExpose, (IMP *)&gOrigExpose, "expose");
    TBDHook("TBBootImageItemSelector", "chooseValidBootImageInfo:isColdStart:completeBlock:", NO, (IMP)TBDChooseV, (IMP *)&gOrigChooseV, "chooseV");
    TBDHook("TBBootImageItemSelector", "chooseValidBootImageInfo:isColdStart:completion:", NO, (IMP)TBDChooseB, (IMP *)&gOrigChooseB, "chooseB");
    TBDHook("TBBootImageItemSelector", "processCommercialSplash:completion:", NO, (IMP)TBDProc, (IMP *)&gOrigProc, "procComm");
    TBDHook("TBBootImageItemSelector", "traceShow:reason:bootImageInfoItem:", NO, (IMP)TBDTrace, (IMP *)&gOrigTrace, "traceShow");
    TBDHook("SPSplashController", "onStart:", NO, (IMP)TBDSPStart, (IMP *)&gOrigSPStart, "spStart");
    TBDHook("SPSplashController", "onViewShown:", NO, (IMP)TBDSPShown, (IMP *)&gOrigSPShown, "spShown");
    TBDHook("TXSplashInteractRequestUtil", "startClaimedCouponRequest:bizType:isColdStart:finishedBlock:", NO, (IMP)TBDTXClaim, (IMP *)&gOrigTXClaim, "txClaim");
    TBDHook("TXSplashInteractRequestUtil", "startAddToCartRequest:bizType:isColdStart:successBlock:failBlock:", NO, (IMP)TBDTXCart, (IMP *)&gOrigTXCart, "txCart");
    TBDHook("TXSplashInteractUtil", "getTBAnimatedImageWithItem:block:", YES, (IMP)TBDTXAnim, (IMP *)&gOrigTXAnim, "txAnim");
    // Group 2: popup + prefilter
    TBDHook("TBHomePopLayerManager", "notifyPopLayer", NO, (IMP)TBDPopNotify, (IMP *)&gOrigPopNotify, "popNotify");
    TBDHook("TBHomePopLayerManager", "notifyPopLayerEvent:sourceName:params:", NO, (IMP)TBDPopEvt, (IMP *)&gOrigPopEvt, "popEvt");
    TBDHook("TBHomePopLayerManager", "handleColdStartSceneChange", NO, (IMP)TBDPopCold, (IMP *)&gOrigPopCold, "popCold");
    TBDHook("TBHomePopLayerManager", "handleNormalBackToHomeScene", NO, (IMP)TBDPopBack, (IMP *)&gOrigPopBack, "popBack");
    TBDHook("TBPLInventoryManager", "queryInventory:", YES, (IMP)TBDInvC, (IMP *)&gOrigInvC, "invC");
    TBDHook("TBPLInventoryManager", "queryInventory:", NO, (IMP)TBDInvI, (IMP *)&gOrigInvI, "invI");
    TBDHook("TBPLLayerFactory", "createLayerWithFrame:type:popRequest:attachVC:", NO, (IMP)TBDFactory, (IMP *)&gOrigFactory, "factory");
    TBDHook("TBPLLayerFactory", "createLayerWithFrame:type:config:targetUrl:", NO, (IMP)TBDFactory2, (IMP *)&gOrigFactory2, "factory2");
    TBDHook("TBHomeAwesomeAdapter", "triggerWithContainerParams:event:", NO, (IMP)TBDTrig, (IMP *)&gOrigTrig, "awesomeTrig");
    TBDHook("TBHomeAwesomeAdapter", "currentContainerIdsWithPageId:", YES, (IMP)TBDContainers, (IMP *)&gOrigContainers, "containers");
    TBDHook("TBPLInventoryModel", "isPass:andParam:layer:timestmap:", NO, (IMP)TBDIsPass, (IMP *)&gOrigIsPass, "isPass");
    TBDHook("TBPLPreCheckCacheManager", "sendNetworkRequest:indexMap:finishBlock:", NO, (IMP)TBDPreCheck, (IMP *)&gOrigPreCheck, "preCheck");
    TBDHook("TBPLBaseTriggerService", "isMatchBlackList:poplayerUri:", NO, (IMP)TBDBlack, (IMP *)&gOrigBlack, "blackList");
    // Group 3: MTOP census
    TBDHook("MtopService", "sendingRequest:delegate:startFilter:", NO, (IMP)TBDMtopSend, (IMP *)&gOrigMtopSend, "mtopSend");
    TBDHook("MtopService", "async_call:delegate:", NO, (IMP)TBDMtopAsync, (IMP *)&gOrigMtopAsync, "mtopAsync");
    TBDHook("MtopService", "async_call:delegate:startFilter:", NO, (IMP)TBDMtopAsyncF, (IMP *)&gOrigMtopAsyncF, "mtopAsyncF");
    TBDHook("MtopService", "sync_call:", NO, (IMP)TBDMtopSync, (IMP *)&gOrigMtopSync, "mtopSync");
    TBDHook("MtopService", "prefetch_call:productionTimeout:compareDelegate:eventDelegate:", NO, (IMP)TBDMtopPrefetch, (IMP *)&gOrigMtopPrefetch, "mtopPrefetch");
    // Group 4: my page markers + second screen senders + v1 group 4
    TBDHook("TBMyTaobaoViewController", "viewWillAppear:", NO, (IMP)TBDMyDojo, (IMP *)&gOrigMyDojo, "myDojo");
    TBDHook("TBMyTaobaoUltronViewController", "viewWillAppear:", NO, (IMP)TBDMyUltron, (IMP *)&gOrigMyUltron, "myUltron");
    TBDHook("TBMyTaobaoUltronMainService", "handleSecondScreenRequest:", NO, (IMP)TBDSecHandle, (IMP *)&gOrigSecHandle, "secHandle");
    TBDHook("TBMyTaobaoUltronMainService", "secScreenRequest:", NO, (IMP)TBDSecReq, (IMP *)&gOrigSecReq, "secReq");
    TBDHook("TBMyTaobaoSecScreenApiModel", "setApiName:", NO, (IMP)TBDSecApi, (IMP *)&gOrigSecApi, "secApi");
    TBDHook("TBMyTaobaoSecScreenApiModel", "setData:", NO, (IMP)TBDSecData, (IMP *)&gOrigSecData, "secData");
    TBDHook("TBRecmdEmbedTabContentService", "fetchTab:forContent:completion:", NO, (IMP)TBDFetchTab, (IMP *)&gOrigFetchTab, "fetchTab");
    TBDHook("TBRecmdEmbedTabContentService", "embeddedTabWithContent:containerModel:tabIndex:offsetY:", NO, (IMP)TBDEmbed, (IMP *)&gOrigEmbed, "embedTab");
    TBDHook("TBRecmdEmbedTabContentService", "cacheTab:withContent:", NO, (IMP)TBDCacheTab, (IMP *)&gOrigCacheTab, "cacheTab");
    TBDHook("TBRecmdTabContentService", "old_requestTabContentTabId:appId:channel:page:param:block:", YES, (IMP)TBDTabReq, (IMP *)&gOrigTabReq, "tabReq");
    TBDHook("TBMTBDataSource", "setData:", NO, (IMP)TBDMTBData, (IMP *)&gOrigMTBData, "mtbData");
    TBDHook("TBMTBDataSource", "setModuleData:", NO, (IMP)TBDMTBModule, (IMP *)&gOrigMTBModule, "mtbModule");
    // Group 5: cart v1 regression
    TBDHook("AliXDetailCollectionService", "getCartRecommendMessage:params:withSuccessBlock:failedBlock:", YES, (IMP)TBDCart, (IMP *)&gOrigCart, "cartRecmd");
    TBDHook("AliXDetailFeatureModel", "hasCartRecommend", NO, (IMP)TBDHas, (IMP *)&gOrigHas, "hasCartR");
    TBDHook("AliXDetailFeatureModel", "setHasCartRecommend:", NO, (IMP)TBDSetHas, (IMP *)&gOrigSetHas, "setHasCartR");
    // Group 6: home floating bar candidates
    TBDHook("TBHomeViewController", "displayFloatView:", NO, (IMP)TBDFloatView, (IMP *)&gOrigFloatView, "floatView");
    TBDHook("TBIFHFloatingBarNotifyEventHandler", "handleEvent:args:context:", NO, (IMP)TBDFloatEvt, (IMP *)&gOrigFloatEvt, "floatEvt");
    TBDHook("TBMyTaobaoLifeCycle", "handleHomePageFloatingBarLinkedNotification:", NO, (IMP)TBDFloatLink, (IMP *)&gOrigFloatLink, "floatLink");
    TBDHook("TBHRGatewayDataService", "uiRefresh:", NO, (IMP)TBDGwUI, (IMP *)&gOrigGwUI, "gwUI");
    TBDHook("TBHRGatewayDataService", "responseDidEnd:", NO, (IMP)TBDGwEnd, (IMP *)&gOrigGwEnd, "gwEnd");
}

__attribute__((constructor)) static void TBDEntry(void) {
    @autoreleasepool {
        gStart = [NSDate date];
        gLock = [[NSObject alloc] init];
        gEvents = [NSMutableArray array];
        gCaptures = [NSMutableDictionary dictionary];
        gHookOK = [NSMutableString string];
        gHookMiss = [NSMutableString string];
        TBDInstallAll();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ TBDInstallAll(); TBDWriteFile(); });
        TBDTick(0);
    }
}
