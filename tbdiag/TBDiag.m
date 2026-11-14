// TBDiag v1 — READ-ONLY diagnostic dylib for Taobao 10.69.0 (com.taobao.taobao4iphone).
//
// Purpose: attribute four surfaces without changing ANY behavior:
//   1. Splash stack attribution: TBBootImage (selector + gates + manager show)
//      vs SPSplashController vs TXSplashInteract.
//   2. Home PopLayer popup: TBHomePopLayerManager events + TBPL inventory /
//      layer-factory show path (popId / templateId probing).
//   3. Cart recommend: +[AliXDetailCollectionService getCartRecommendMessage:...]
//      params + response structure, hasCartRecommend read/write timing.
//   4. MyTaobao second screen: TBMyTaobaoSecScreenApiModel data landing,
//      TBRecmdEmbedTabContentService tab fetch (tabId), main-screen key list.
//
// HARD RULE: every hook calls the original implementation and returns its
// result untouched. Block arguments are only wrapped for the cart-recommend
// call (first 2 calls), and the wrapper forwards the result object as-is.
// Nothing here touches AMDC / MTOP / SecurityGuard / search / browse paths.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// ---------------------------------------------------------------- state ----
static NSDate *gStart = nil;
static id gLock = nil;
static NSMutableArray *gEvents = nil;       // timestamped event lines (capped)
static NSMutableDictionary *gCaptures = nil; // name -> long text (for file)
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
static void TBSetCapture(NSString *key, NSString *text) { // always overwrite
    if (key == nil || text == nil) return;
    @synchronized (gLock) { gCaptures[key] = text; }
}
static void TBEvent(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    @synchronized (gLock) {
        [gEvents addObject:[NSString stringWithFormat:@"[+%.1fs] %@", TBNow(), msg]];
        while ([gEvents count] > 160) [gEvents removeObjectAtIndex:0];
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

// Probe a candidate key list on an object (KVC), return "k=v k=v" for hits.
static NSString *TBProbe(id obj, NSArray *keys) {
    if (obj == nil) return @"";
    NSMutableString *out = [NSMutableString string];
    for (NSString *k in keys) {
        @try {
            id v = [obj valueForKey:k];
            if (v != nil) {
                [out appendFormat:@"%@=%@ ", k, TBShort(v, 60)];
            }
        } @catch (NSException *e) { }
    }
    return out;
}

// Find a "scene"-ish value inside a params dict (bounded scan).
static NSString *TBFindScene(id obj, int depth, int *budget) {
    if (obj == nil || depth > 4 || *budget <= 0) return nil;
    (*budget)--;
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            NSString *ks = [k description];
            id v = ((NSDictionary *)obj)[k];
            if (([ks isEqualToString:@"scene"] || [ks isEqualToString:@"sceneName"] ||
                 [ks isEqualToString:@"pageName"] || [ks isEqualToString:@"bizCode"]) &&
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

// ============================================================== GROUP 1 =====
// Splash attribution.
// ---- TBBootImageManager gates / show ----
static int gGateColdCalls = 0, gGateColdYes = 0, gGateHotCalls = 0, gGateHotYes = 0;
static int gMgrCold = 0, gMgrHot = 0, gMgrCur = 0, gMgrExp = 0;
typedef BOOL (*BoolIMP)(id, SEL);
static BoolIMP gOrigGateColdI = NULL, gOrigGateColdC = NULL, gOrigGateHotC = NULL, gOrigMgrHot = NULL;
static BOOL TBDGateColdI(id self, SEL _cmd) {
    BOOL r = gOrigGateColdI ? gOrigGateColdI(self, _cmd) : NO;
    gGateColdCalls++; if (r) gGateColdYes++;
    TBEvent(@"gate -isColdTaobaoSplashAdvWillShow -> %d", r);
    return r;
}
static BOOL TBDGateColdC(id self, SEL _cmd) {
    BOOL r = gOrigGateColdC ? gOrigGateColdC(self, _cmd) : NO;
    gGateColdCalls++; if (r) gGateColdYes++;
    TBEvent(@"gate +isColdTaobaoSplashAdvWillShow -> %d", r);
    return r;
}
static BOOL TBDGateHotC(id self, SEL _cmd) {
    BOOL r = gOrigGateHotC ? gOrigGateHotC(self, _cmd) : NO;
    gGateHotCalls++; if (r) gGateHotYes++;
    TBEvent(@"gate +isHotStartTaobaoSplashAdvWillShow -> %d", r);
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
    TBEvent(@"TBBootImageManager showCurrentItem openUrl=%d -> %d", b, r);
    return r;
}
static BOOL TBDExpose(id self, SEL _cmd, BOOL a, BOOL b, id cfg) {
    BOOL r = gOrigExpose ? gOrigExpose(self, _cmd, a, b, cfg) : NO;
    gMgrExp++;
    TBEvent(@"TBBootImageManager exposeSplashDisplay openUrl=%d -> %d", b, r);
    return r;
}
// ---- TBBootImageItemSelector ----
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
    TBEvent(@"ItemSelector traceShow reason=%@ item: %@", TBShort(reason, 40), probe);
    if (gOrigTrace) gOrigTrace(self, _cmd, isDegrade, reason, item);
}
// ---- SPSplashController ----
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
// ---- TXSplashInteract ----
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
    TBEvent(@"TX getTBAnimatedImageWithItem: %@", TBShort(item, 100));
    if (gOrigTXAnim) gOrigTXAnim(self, _cmd, item, block);
}

// ============================================================== GROUP 2 =====
// Home PopLayer popup + Awesome containers.
static int gPopNotify = 0, gPopEvt = 0, gPopCold = 0, gPopBack = 0, gInvQ = 0, gFactory = 0, gAwesomeTrig = 0;
static NSString *gPopProbe = @"", *gFactoryType = @"";
typedef void (*VoidIMP)(id, SEL);
static VoidIMP gOrigPopNotify = NULL, gOrigPopCold = NULL, gOrigPopBack = NULL;
static void TBDPopNotify(id self, SEL _cmd) {
    gPopNotify++;
    TBEvent(@"TBHomePopLayerManager notifyPopLayer");
    if (gOrigPopNotify) gOrigPopNotify(self, _cmd);
}
static void TBDPopCold(id self, SEL _cmd) {
    gPopCold++;
    TBEvent(@"TBHomePopLayerManager handleColdStartSceneChange");
    if (gOrigPopCold) gOrigPopCold(self, _cmd);
}
static void TBDPopBack(id self, SEL _cmd) {
    gPopBack++;
    TBEvent(@"TBHomePopLayerManager handleNormalBackToHomeScene");
    if (gOrigPopBack) gOrigPopBack(self, _cmd);
}
typedef void (*PopEvtIMP)(id, SEL, id, id, id);
static PopEvtIMP gOrigPopEvt = NULL;
static void TBDPopEvt(id self, SEL _cmd, id evt, id src, id params) {
    gPopEvt++;
    TBEvent(@"TBHomePopLayerManager notifyPopLayerEvent src=%@", TBShort(src, 60));
    TBCapture(@"popEvtParams", TBStruct(params, 120));
    if (gOrigPopEvt) gOrigPopEvt(self, _cmd, evt, src, params);
}
typedef id (*InvIMP)(id, SEL, id);
static InvIMP gOrigInvC = NULL, gOrigInvI = NULL;
static id TBDInvC(id self, SEL _cmd, id arg) {
    id r = gOrigInvC ? gOrigInvC(self, _cmd, arg) : nil;
    gInvQ++;
    TBEvent(@"TBPLInventoryManager +queryInventory: arg=%@", TBShort(arg, 60));
    TBCapture(@"invArg", TBStruct(arg, 80));
    TBCapture(@"invRet", TBStruct(r, 200));
    return r;
}
static id TBDInvI(id self, SEL _cmd, id arg) {
    id r = gOrigInvI ? gOrigInvI(self, _cmd, arg) : nil;
    gInvQ++;
    TBEvent(@"TBPLInventoryManager -queryInventory: arg=%@", TBShort(arg, 60));
    TBCapture(@"invArg", TBStruct(arg, 80));
    TBCapture(@"invRet", TBStruct(r, 200));
    return r;
}
typedef struct { double x, y, w, h; } TBRect;
typedef id (*FactoryIMP)(id, SEL, TBRect, id, id, id);
static FactoryIMP gOrigFactory = NULL;
static id TBDFactory(id self, SEL _cmd, TBRect fr, id type, id popReq, id vc) {
    gFactory++;
    gFactoryType = TBShort(type, 60);
    NSString *probe = TBProbe(popReq, @[@"popId", @"templateId", @"id", @"name",
                                        @"type", @"popName", @"layerId", @"configId", @"popKey"]);
    if ([probe length] == 0) probe = TBShort(popReq, 150);
    gPopProbe = probe;
    TBEvent(@"TBPLLayerFactory createLayer type=%@ pop: %@", gFactoryType, probe);
    TBCapture(@"popRequest", TBStruct(popReq, 150));
    return gOrigFactory ? gOrigFactory(self, _cmd, fr, type, popReq, vc) : nil;
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
    TBEvent(@"TBHomeAwesomeAdapter trigger event=%@", e);
    TBCapture(@"awesomeParams", TBStruct(params, 100));
    if (gOrigTrig) gOrigTrig(self, _cmd, params, event);
}
typedef id (*ContainersIMP)(id, SEL, id);
static ContainersIMP gOrigContainers = NULL;
static NSString *gContainers = @"";
static id TBDContainers(id self, SEL _cmd, id pageId) {
    id r = gOrigContainers ? gOrigContainers(self, _cmd, pageId) : nil;
    NSString *s = TBShort(r, 200);
    if (![s isEqualToString:gContainers]) {
        gContainers = s;
        TBEvent(@"Awesome currentContainerIds page=%@ -> %@", TBShort(pageId, 40), s);
    }
    return r;
}

// ============================================================== GROUP 3 =====
// Cart recommend (AliXDetailCollectionService / AliXDetailFeatureModel).
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
    TBEvent(@"getCartRecommendMessage #=%d scene=%@", gCartCalls, scene ?: @"?");
    TBCapture(@"cartParams", TBStruct(params, 250));
    if (gCartCalls <= 2 && (ok != nil || fail != nil)) {
        TBDBlock1 okW = nil, failW = nil;
        if (ok) {
            TBDBlock1 origOk = ok;
            okW = ^(id result) {
                gCartOK++;
                TBEvent(@"getCartRecommendMessage success");
                TBCapture(@"cartResp", TBStruct(result, 250));
                origOk(result);
            };
        }
        if (fail) {
            TBDBlock1 origFail = fail;
            failW = ^(id err) {
                gCartFail++;
                TBEvent(@"getCartRecommendMessage failed: %@", TBShort(err, 80));
                origFail(err);
            };
        }
        if (gOrigCart) gOrigCart(self, _cmd, a, params, okW ?: ok, failW ?: fail);
        return;
    }
    if (gOrigCart) gOrigCart(self, _cmd, a, params, ok, fail);
}
static BoolIMP gOrigHas = NULL;
static BOOL TBDHas(id self, SEL _cmd) {
    BOOL r = gOrigHas ? gOrigHas(self, _cmd) : NO;
    gHasRead++;
    gHasLast = [NSString stringWithFormat:@"read->%d @%.0fs", r, TBNow()];
    return r;
}
typedef void (*SetBoolIMP)(id, SEL, BOOL);
static SetBoolIMP gOrigSetHas = NULL;
static void TBDSetHas(id self, SEL _cmd, BOOL v) {
    gHasWrite++;
    gHasLast = [NSString stringWithFormat:@"write=%d @%.0fs", v, TBNow()];
    TBEvent(@"AliXDetailFeatureModel setHasCartRecommend: %d", v);
    if (gOrigSetHas) gOrigSetHas(self, _cmd, v);
}

// ============================================================== GROUP 4 =====
// MyTaobao second screen.
static int gSecData = 0, gFetchTab = 0, gEmbedTab = 0, gTabReq = 0, gCacheTab = 0;
static NSString *gSecApi = @"", *gTabIds = @"", *gMainKeys = @"";
static VoidIdIMP gOrigSecData = NULL, gOrigSecApi = NULL;
static void TBDSecApi(id self, SEL _cmd, id name) {
    gSecApi = TBShort(name, 80);
    TBEvent(@"SecScreenApiModel setApiName: %@", gSecApi);
    if (gOrigSecApi) gOrigSecApi(self, _cmd, name);
}
static void TBDSecData(id self, SEL _cmd, id data) {
    gSecData++;
    TBEvent(@"SecScreenApiModel setData: api=%@", gSecApi);
    TBCapture(@"secData", TBStruct(data, 300));
    if (gOrigSecData) gOrigSecData(self, _cmd, data);
}
typedef void (*FetchTabIMP)(id, SEL, id, id, id);
static FetchTabIMP gOrigFetchTab = NULL;
static void TBDFetchTab(id self, SEL _cmd, id tab, id content, id completion) {
    gFetchTab++;
    NSString *tid = TBProbe(tab, @[@"tabId", @"id", @"name", @"title"]);
    TBEvent(@"EmbedTabContentService fetchTab: %@ content=%@", tid, TBShort(content, 60));
    if (gOrigFetchTab) gOrigFetchTab(self, _cmd, tab, content, completion);
}
typedef id (*EmbedIMP)(id, SEL, id, id, long long, double);
static EmbedIMP gOrigEmbed = NULL;
static id TBDEmbed(id self, SEL _cmd, id content, id container, long long idx, double offY) {
    id r = gOrigEmbed ? gOrigEmbed(self, _cmd, content, container, idx, offY) : nil;
    gEmbedTab++;
    NSString *tid = @"";
    @try {
        if (r && [r respondsToSelector:NSSelectorFromString(@"tabId")]) {
            id v = ((id (*)(id, SEL))objc_msgSend)(r, NSSelectorFromString(@"tabId"));
            tid = TBShort(v, 60);
        }
    } @catch (NSException *e) { }
    if ([tid length] && [gTabIds rangeOfString:tid].location == NSNotFound && [gTabIds length] < 300) {
        gTabIds = [gTabIds stringByAppendingFormat:@"%@ ", tid];
    }
    TBEvent(@"EmbedTabContentService embeddedTab idx=%lld tabId=%@", idx, tid);
    return r;
}
typedef void (*CacheTabIMP)(id, SEL, id, id);
static CacheTabIMP gOrigCacheTab = NULL;
static void TBDCacheTab(id self, SEL _cmd, id tab, id content) {
    gCacheTab++;
    NSString *probe = TBProbe(content, @[@"tabId", @"containerId", @"title", @"name"]);
    TBEvent(@"EmbedTabContentService cacheTab: tab=%@ content: %@", TBShort(tab, 40), probe);
    TBCapture(@"embedContent", TBStruct(content, 200));
    if (gOrigCacheTab) gOrigCacheTab(self, _cmd, tab, content);
}
typedef void (*TabReqIMP)(id, SEL, id, id, id, long long, id, id);
static TabReqIMP gOrigTabReq = NULL;
static NSString *gTabReqInfo = @"";
static void TBDTabReq(id self, SEL _cmd, id tabId, id appId, id channel, long long page, id param, id block) {
    gTabReq++;
    gTabReqInfo = [NSString stringWithFormat:@"tabId=%@ appId=%@ ch=%@ page=%lld",
                   TBShort(tabId, 50), TBShort(appId, 40), TBShort(channel, 30), page];
    TBEvent(@"TBRecmdTabContentService old_request %@", gTabReqInfo);
    TBCapture(@"tabParam", TBStruct(param, 120));
    if (gOrigTabReq) gOrigTabReq(self, _cmd, tabId, appId, channel, page, param, block);
}
static VoidIdIMP gOrigMTBData = NULL, gOrigMTBModule = NULL;
static void TBDMTBData(id self, SEL _cmd, id data) {
    if ([gMainKeys length] == 0 && [data isKindOfClass:[NSDictionary class]]) {
        gMainKeys = TBShort([(NSDictionary *)data allKeys], 250);
        TBEvent(@"TBMTBDataSource setData keys: %@", gMainKeys);
    }
    if (gOrigMTBData) gOrigMTBData(self, _cmd, data);
}
static void TBDMTBModule(id self, SEL _cmd, id data) {
    TBCapture(@"mainModuleData", TBStruct(data, 150));
    if (gOrigMTBModule) gOrigMTBModule(self, _cmd, data);
}

// ------------------------------------------------------------ reporting ----
static NSMutableString *gHookOK = nil, *gHookMiss = nil;

static NSString *TBDSummary(void) {
    NSMutableString *s = [NSMutableString string];
    [s appendString:@"TBDiag v1 淘宝10.69 只读诊断\n"];
    [s appendFormat:@"[开屏] 选片cold=%d hot=%d proc=%d | 门控cold %d次(是%d) hot %d次(是%d) | 展示 cold=%d hot=%d cur=%d exp=%d | SP start=%d shown=%d | TX req=%d anim=%d | trace=%d\n",
        gSelCold, gSelHot, gSelProc, gGateColdCalls, gGateColdYes, gGateHotCalls, gGateHotYes,
        gMgrCold, gMgrHot, gMgrCur, gMgrExp, gSPStart, gSPShown, gTXReq, gTXAnim, gTraceShow];
    if ([gTraceItem length]) [s appendFormat:@"  traceItem: %@\n", gTraceItem];
    [s appendFormat:@"[弹窗] notify=%d evt=%d cold=%d back=%d | invQ=%d factory=%d type=%@\n  pop: %@\n",
        gPopNotify, gPopEvt, gPopCold, gPopBack, gInvQ, gFactory, gFactoryType, gPopProbe];
    [s appendFormat:@"[首页] awesomeTrig=%d events: %@\n  containers: %@\n",
        gAwesomeTrig, gAwesomeEvents, gContainers];
    [s appendFormat:@"[购物车] getCartRecommend=%d ok=%d fail=%d scene=%@ | hasCartRecommend 读=%d 写=%d %@\n",
        gCartCalls, gCartOK, gCartFail, gCartScene, gHasRead, gHasWrite, gHasLast];
    [s appendFormat:@"[我的] secApi=%@ setData=%d | fetchTab=%d cacheTab=%d embed=%d tabReq=%d %@\n  tabIds: %@\n  主屏keys: %@\n",
        gSecApi, gSecData, gFetchTab, gCacheTab, gEmbedTab, gTabReq, gTabReqInfo, gTabIds, gMainKeys];
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
            for (NSString *k in gCaptures) {
                [out appendFormat:@"\n--- capture %@ ---\n%@\n", k, gCaptures[k]];
            }
            [out appendString:@"\n--- events ---\n"];
            for (NSString *e in gEvents) [out appendFormat:@"%@\n", e];
        }
        [out writeToFile:[dir stringByAppendingPathComponent:@"TBDiag-v1.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) { }
}

// -------------------------------------------------------- presentation -----
static id TBDTopVC(void) {
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
        @"TBDiag v1", TBDSummary(), 1L);
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
    // First show: retry every 15 s for ~3 min (12 ticks). After that, keep
    // ticking for ~20 min total and re-show only when new data arrived and
    // at least 45 s passed since the last show (user reaching cart / my page).
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
    if (*origOut != NULL) return YES; // already installed
    *origOut = method_getImplementation(m);
    method_setImplementation(m, repl);
    @synchronized (gLock) { [gHookOK appendFormat:@"%s ", tag]; }
    return YES;
}

static void TBDInstallAll(void) {
    // Group 1
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
    // Group 2
    TBDHook("TBHomePopLayerManager", "notifyPopLayer", NO, (IMP)TBDPopNotify, (IMP *)&gOrigPopNotify, "popNotify");
    TBDHook("TBHomePopLayerManager", "notifyPopLayerEvent:sourceName:params:", NO, (IMP)TBDPopEvt, (IMP *)&gOrigPopEvt, "popEvt");
    TBDHook("TBHomePopLayerManager", "handleColdStartSceneChange", NO, (IMP)TBDPopCold, (IMP *)&gOrigPopCold, "popCold");
    TBDHook("TBHomePopLayerManager", "handleNormalBackToHomeScene", NO, (IMP)TBDPopBack, (IMP *)&gOrigPopBack, "popBack");
    TBDHook("TBPLInventoryManager", "queryInventory:", YES, (IMP)TBDInvC, (IMP *)&gOrigInvC, "invC");
    TBDHook("TBPLInventoryManager", "queryInventory:", NO, (IMP)TBDInvI, (IMP *)&gOrigInvI, "invI");
    TBDHook("TBPLLayerFactory", "createLayerWithFrame:type:popRequest:attachVC:", NO, (IMP)TBDFactory, (IMP *)&gOrigFactory, "factory");
    TBDHook("TBHomeAwesomeAdapter", "triggerWithContainerParams:event:", NO, (IMP)TBDTrig, (IMP *)&gOrigTrig, "awesomeTrig");
    TBDHook("TBHomeAwesomeAdapter", "currentContainerIdsWithPageId:", YES, (IMP)TBDContainers, (IMP *)&gOrigContainers, "containers");
    // Group 3
    TBDHook("AliXDetailCollectionService", "getCartRecommendMessage:params:withSuccessBlock:failedBlock:", YES, (IMP)TBDCart, (IMP *)&gOrigCart, "cartRecmd");
    TBDHook("AliXDetailFeatureModel", "hasCartRecommend", NO, (IMP)TBDHas, (IMP *)&gOrigHas, "hasCartR");
    TBDHook("AliXDetailFeatureModel", "setHasCartRecommend:", NO, (IMP)TBDSetHas, (IMP *)&gOrigSetHas, "setHasCartR");
    // Group 4
    TBDHook("TBMyTaobaoSecScreenApiModel", "setApiName:", NO, (IMP)TBDSecApi, (IMP *)&gOrigSecApi, "secApi");
    TBDHook("TBMyTaobaoSecScreenApiModel", "setData:", NO, (IMP)TBDSecData, (IMP *)&gOrigSecData, "secData");
    TBDHook("TBRecmdEmbedTabContentService", "fetchTab:forContent:completion:", NO, (IMP)TBDFetchTab, (IMP *)&gOrigFetchTab, "fetchTab");
    TBDHook("TBRecmdEmbedTabContentService", "embeddedTabWithContent:containerModel:tabIndex:offsetY:", NO, (IMP)TBDEmbed, (IMP *)&gOrigEmbed, "embedTab");
    TBDHook("TBRecmdEmbedTabContentService", "cacheTab:withContent:", NO, (IMP)TBDCacheTab, (IMP *)&gOrigCacheTab, "cacheTab");
    TBDHook("TBRecmdTabContentService", "old_requestTabContentTabId:appId:channel:page:param:block:", YES, (IMP)TBDTabReq, (IMP *)&gOrigTabReq, "tabReq");
    TBDHook("TBMTBDataSource", "setData:", NO, (IMP)TBDMTBData, (IMP *)&gOrigMTBData, "mtbData");
    TBDHook("TBMTBDataSource", "setModuleData:", NO, (IMP)TBDMTBModule, (IMP *)&gOrigMTBModule, "mtbModule");
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
        // One retry pass for anything not yet registered at load time.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ TBDInstallAll(); TBDWriteFile(); });
        TBDTick(0);
    }
}
