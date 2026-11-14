// TBClean — formal ad-filter dylib for Taobao 10.69.0 (com.taobao.taobao4iphone).
//
// No UI, no logging UI, no popups. All filters are process-internal,
// data-side disposals applied AFTER data arrives; nothing blocks, rejects
// or reroutes any request, and no signing / routing / search-result /
// product-detail / order path is touched (ANALYSIS §7.3 red lines).
// The splash fix is NOT in this dylib: it is the main-binary patch set
// P1+P3+P4 (work/patches6.json, see FORMAL_NOTES "formal6" / F below).
//
// Modules:
//   1. PopLayer class-wide block (unchanged from formal4): TBPLLayerFactory
//      (variant 1) layer creation re-check by request event uri slot
//      (Page_Home / Page_MyTaobao popup_* modal slots only), returning nil,
//      which the sole caller treats as a native "filtered" cancellation.
//   2. Cart recommend (REWRITTEN in formal6). Formal4 discrimination
//      (serialize biz+ext+... into one 64K-capped, depth-6 blob and test
//      the containerId substring) failed 6/6 recorded samples at the
//      substring step in the diag3 in-process probe (isSucceed passed on
//      all 6). The blob test's survival depended on NSDictionary
//      iteration order against a shared length cap, and its samples were
//      dominated by same-API-set non-cart traffic. Formal6 replaces it
//      with three independent layers, each fail-open:
//      (a) Object-level recursive match at the getResponse point: DFS
//          over the request's biz/ext parameter objects (depth 12, node
//          budget, JSON-string values parsed and re-walked), matching
//          key "containerId" == recommend_cart_main/recommend_cart_sxc,
//          the ids as dictionary KEYS (the gateway containerParams
//          morphology), and any string key/value containing either id.
//          No global serialization, no shared cap.
//      (b) Weex bridge tagging: at -[WXMtopRequest generateMtopRequest]
//          exit, the freshly built MtopExtRequest still carries the JS
//          data verbatim; if the same object-level match hits there, the
//          request instance is tagged (associated object). getResponse
//          accepts the tag on response.request as a match (the response
//          provably stores the very MtopExtRequest that was sent —
//          CAP428 instruction-level check). If MTOP ever clones the
//          request, the tag is simply absent and layer (a) still applies.
//      (c) Native consumption guard: -[TBRecmdContentDataRepo
//          processResData:success:error:oriDic:page:] — for a repo whose
//          own containerId is a cart id, a successful TBRecmdLoadDataResData
//          gets its sections emptied before processing, which is exactly
//          the shape of a native empty page (the method itself merges
//          resData.sections into the repo's contentData). Covers the
//          classic (non-gateway) TBRecmd path; the dosa gateway path's
//          model conversion is not hooked (see FORMAL_NOTES formal6 A).
//      The response-side action is unchanged: empty the cart container's
//      arrays / the data payload of this one matched request, envelope
//      scalars preserved.
//   3. Cart top activity banner (target 7, UNCHANGED from formal4 —
//      status-quo per formal6 B): api=mtop.trade.query.bag response-side
//      pruning by the structural anchors data field "topAdBanner_1" /
//      DinamicX template "icart_top_banner". Diag3 evidence: neither
//      anchor appeared in the one recorded real query.bag response
//      (the probe's key-path DFS was node-budgeted, so deep presence is
//      not fully excluded), and tracing the wlm 1.255.0 constant pool
//      shows both names are JS-side model/template identifiers with no
//      other wire-key candidate in the pool — the wire field feeding
//      topAdBanner_1 could not be pinned from the compiled bundle, so
//      no new anchor is guessed. Dual anchor, fail open when absent.
//   4. Search landing sections (UNCHANGED from formal4 — status-quo per
//      formal6 E): exit filter at TBXSearchActivationTppParser
//      -getProcessedData:. History sections (tItemType nt_history /
//      nt_combine_history / nt_multimodal_history) are kept
//      unconditionally; sections whose own "name" contains 猜你想搜 /
//      淘宝热榜 and whose tItemType is not a history type are dropped;
//      fail-open on any shape mismatch. Formal6 static work found NO
//      ObjC-visible assembly exit equivalent to getProcessedData: in
//      the Swift/XSL new door (SearchDoor BodyComponent exposes only
//      init; its data assembly is Swift-internal, rendering goes
//      through Meta/Muise models built inside Swift), so there is no
//      second point to dual-hook — this module remains UNVERIFIED
//      (diag3 recorded parser x0, but the user was on the suggestion
//      page; whether the landing page fully triggered the parser is
//      undetermined, as is whether 10.69 serves this account the new
//      door). The two sections' tItemType values remain unknown.
//   5. Home floating bar (UNCHANGED behavior from formal4, diagnosis
//      completed in formal6 D): TBHRContainerContentModel
//      -floatLayerSection getter forced to nil. Diag3 recorded the
//      getter being read exactly twice with the hook active: caller 1
//      symbolizes to TBHRGwLoadCacheAction -deepCopyBaseAsTotal: (the
//      cache deepCopy — the only app-code caller), caller 2's return
//      address lands outside the main binary's __text (it resolves
//      into a system-framework frame, consistent with a KVC
//      valueForKey: read). The bar still renders with the getter
//      returning nil on every read, so the rendering consumer does
//      NOT depend on this property's value (it reads the model's
//      originalData or a remote-module model instead). The true
//      consumption point could not be pinned statically; the getter
//      hook is kept as-is (it provably neutralizes the deepCopy path)
//      and this surface is explicitly NOT claimed fixed.
//   6. MyTaobao bottom section (basementTip) (REWRITTEN in formal6;
//      the formal4 factory-exit containerType 3->2 downgrade is
//      REMOVED — diag3 proved the factory and the native value 3 are
//      exactly as designed, yet the section still rendered, i.e. the
//      downgrade is ineffective on the rendering side). Formal6 removes
//      the section at the two points where the consumer's OWN data
//      structures are populated — never a parallel copy:
//      (a) Full assembly: -[MTMainPageDataModel setComponents:] is the
//          single entry through which every model instance receives
//          its module list (+creatMainPageDataModel:global:
//          mainPageDataSource: only calls the setters). The incoming
//          array is filtered of moduleName == "basementTip" before the
//          original setter stores it, so the model's one and only
//          components list — the list Dojo assembly consumes — simply
//          never contains the module. Every model in the process
//          (full build, prefetch build) passes this same setter, so no
//          two ObjC models can disagree about the module's presence
//          (buildSnapshotData's new-vs-prefetched comparison compares
//          two identically filtered lists).
//      (b) Incremental updates: -[MTMainPageUserDataService
//          listenComponentsChange:] wraps the registered block so a
//          change dictionary carrying "basementTip" is forwarded
//          without that entry (a basementTip-only change becomes an
//          empty dictionary, which the VC's block natively treats as
//          "no change" and posts no Dojo event for). This closes the
//          one channel formal2 left open: the C++ diff force-pushes
//          basementTip (nativeBasementTipForceDiff) into an assembly
//          that — under formal2's transform-only removal — had no such
//          component. Formal6 cuts that delivery at the boundary.
//      Why this is not formal2 again: formal2 removed the element at
//      the transform exit ONLY, leaving the incremental force-diff
//      channel delivering a phantom component to the Dojo layer; its
//      exact ANR mechanism was never proven (no hang log), but the
//      open channel is a hard fact of the binary. Formal6 filters at
//      the model's own setter (uniform across all builds) AND at the
//      incremental delivery boundary; nothing is removed from any
//      list after a consumer has seen it, and the page's native
//      refresh flow proceeds with the filtered model exactly as if
//      the server had not sent the module (server-driven pages add
//      and drop modules through this same model routinely).
//      Residuals: the listenLayerData* channels and getFieldData:
//      can still carry basementTip DATA, but data without an assembled
//      component has nothing to render into (the section's existence
//      comes from components alone).
//   7. Tab bar slot 2 (guangguang/video) (unchanged from formal4):
//      filter the return value of +[TBAppUIStyle currentTabbarVCItems]
//      (count==5 and element[1] matches by url "taobao://guangguang/root"
//      or attractBiz "tab2" only; tags not renumbered; fail-open
//      otherwise). Verified on device in formal4 — 定版.
//
//   F. Splash (main-binary patches P1+P3+P4, NOT in this dylib):
//      formal4 shipped P1 (validate first check always fails) + P3
//      (Launcher selection always empty). User report 2026-11-14
//      16:27: after ~10 minutes in the background, foregrounding showed
//      a splash again — with a DOWNLOADED ordinary creative, not the
//      preset 超级88 image. Instruction-level trace of the hot path:
//      showBootImageAtHotStart (gates: hasEnteredBackgroundSinceLaunch,
//      isHotStartSplashLimited, backgroundWaitSeconds vs
//      enterBackgroundTime) -> prepareForSplash: -> prepareForNewArch:
//      -> TBBootImageItemSelector chooseNewArchSplashDataForStart:
//      completion: — which fetches the four bizCodes PLUS
//      fetchAllDynamicPriorityItems (downloaded creatives) and calls
//      processCommercialSplash:completion:. That function assembles
//      candidates from the classic fetch AND from the external data
//      service (ext_bootImageItems under enableExtSplash, setting
//      activateNewCommercialSplash); only one of its branches funnels
//      into chooseValid (hence validate/P1), and no validate/chooseValid
//      call exists on the ext/dynamic-priority branch. The downloaded
//      creative matches that branch's inventory exactly. So P1/P3 guard
//      the classic + Launcher selection funnels, but the new-arch
//      commercial branch can still hand an item to the completion.
//      Fix (strategy: convergence point, not whack-a-mole): P4 forces
//      -[TBBootImageManager showCurrentItem:isOpenUrlLaunch:
//      configuration:] to return NO at its header. That method is the
//      BootImage stack's single display convergence — its only two
//      call sites are the cold path (showBootImageAtColdStart:) and
//      the hot-start completion block, and the Launcher fallback's
//      display also ends here. NO is a design-native return (nil
//      current item -> NO), and both callers' NO teardown is verified
//      instruction-level: cold sends FLASHVIEWDISDISAPPEARED and
//      proceeds to the home page; hot removes the placeholder image
//      and sends BootImageDidFinishNotification. The success-only
//      hide callback is installed inside exposeSplashDisplay only on
//      the success path; no caller waits on it, and all completion
//      signaling is synchronous on the caller side — nothing can hang
//      waiting for a display that never happened. TX-flavored
//      interactive items render through this same BootImage display
//      path (TXSplashInteractUtil is file/image utilities and
//      TXSplashInteractRequestUtil only performs post-click claim /
//      add-to-cart requests), so they are covered by the same point.
//      Residual: SPSplashController (WMCore Weex snapshot) is a launch
//      snapshot host with no ad selection of its own — not an
//      independent ad presenter on current evidence (diag1's shown
//      creative traced to BootImage); if a non-BootImage creative ever
//      appears, that channel is the remaining suspect. The hot-start
//      threshold is the fatigue client's backgroundWaitSeconds server
//      config (observed trigger ≈ 10 min in this session).
//
// Marker: TBClean/1.6 (formal7)
// formal6 changes vs formal4/5 (1.3/1.4): module 2 rewritten (object-
// level recursive match + Weex bridge tagging + repo consumption
// guard; blob serializer removed); module 6 rewritten (model setter
// filter + listenComponentsChange: wrapper; factory downgrade hook
// removed); modules 1, 3, 4, 5, 7 logic unchanged (3/4/5 comments
// updated with diag3/formal6 findings); main binary patch set grows
// from P1+P3 to P1+P3+P4 (splash display convergence, face F).
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// Build identity, verifiable in the compiled artifact (strings).
__attribute__((used)) static const char kTCVersion[] = "TBClean/1.6";

// ------------------------------------------------------------ utilities ----
// WARNING: TBM is ONLY for selectors whose return type is an object (id).
// Passing a primitive-returning selector (BOOL/int/...) makes the msgSend
// result register be read as an object pointer; under ARC that value is
// then retained, which is exactly the formal1 launch crash: -isSucceed
// returns BOOL, TBM(resp,"isSucceed") produced the "pointer" 0x1 and
// objc_retain(0x1) faulted. Primitive getters MUST go through TBMBool /
// a correctly-typed cast instead.
static id TBM(id obj, const char *selName) {
    if (obj == nil) return nil;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
// Typed getter for BOOL-returning selectors. Returns YES when the value
// was actually read into *out.
static BOOL TBMBool(id obj, const char *selName, BOOL *out) {
    if (obj == nil || out == NULL) return NO;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return NO;
    *out = ((BOOL (*)(id, SEL))objc_msgSend)(obj, sel);
    return YES;
}
static void TBMSet(id obj, const char *selName, id val) {
    if (obj == nil) return;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, val);
}

// Deep-copy a JSON-shaped object into mutable containers.
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

// ============================================================ MTOP core ====
// Single response-side point: -[MtopService getResponse:mrequest:]
// (IMP 0x1002e1e18) builds the MtopExtResponse that requestFinished:
// then dispatches to the caller delegate (succeed:response: /
// failed:response:). The response carries its own request, so api name
// + params are read from the response itself; no send-side state is kept.
typedef id (*GetRespIMP)(id, SEL, id, id);
static GetRespIMP gOrigGetResp = NULL;

static NSString *TCApiOfResponse(id resp) {
    id req = TBM(resp, "request");
    id n = TBM(req, "getApiName");
    return [n isKindOfClass:[NSString class]] ? n : nil;
}

// ---- cart recommend -----------------------------------------------------
// API set (V4_A_CART.md): the two real cart paths are the native
// TBRecmd gateway (awesome.get) and the Weex CartFeeds component
// (awesome.recommend); the WirelessRecommend family is kept for the
// sibling containers that share the gateway. Case-insensitive because
// the family ships both capitalizations.
static BOOL TCCartAPI(NSString *api) {
    if (![api isKindOfClass:[NSString class]]) return NO;
    return [api caseInsensitiveCompare:@"mtop.taobao.wireless.home.awesome.get"] == NSOrderedSame ||
           [api caseInsensitiveCompare:@"mtop.taobao.wireless.home.awesome.recommend"] == NSOrderedSame ||
           [api caseInsensitiveCompare:@"mtop.relationrecommend.WirelessRecommend.recommend"] == NSOrderedSame ||
           [api caseInsensitiveCompare:@"mtop.relationrecommend.WirelessRecommend.recommendstream"] == NSOrderedSame ||
           [api caseInsensitiveCompare:@"mtop.relationrecommend.wirelessrecommend.recommend"] == NSOrderedSame;
}

// Object-level recursive cart-container match (formal6 module 2a/2b).
// Walks the actual parameter objects — no serialization, no shared
// length cap, no dependence on dictionary iteration order. Matches:
//   * a "containerId" key whose string value is a cart id;
//   * a cart id appearing as a dictionary KEY (gateway containerParams
//     morphology: the id keys the per-container parameter dict);
//   * any string key or value CONTAINING a cart id (covers the ids
//     embedded in JSON-string values at any nesting level);
//   * JSON-string values are parsed and re-walked (escaped forms).
// Bounded: depth 12, node budget per call. Scalars are never sent
// -description; only genuine string content is inspected.
static BOOL TCStrHasCartId(NSString *s) {
    return [s rangeOfString:@"recommend_cart_main"].location != NSNotFound ||
           [s rangeOfString:@"recommend_cart_sxc"].location != NSNotFound;
}
static BOOL TCStrIsCartId(NSString *s) {
    return [s isEqualToString:@"recommend_cart_main"] ||
           [s isEqualToString:@"recommend_cart_sxc"];
}

static BOOL TCDeepCartWalk(id node, int depth, int *budget) {
    if (node == nil || depth > 12 || *budget <= 0) return NO;
    (*budget)--;
    if ([node isKindOfClass:[NSString class]]) {
        NSString *s = (NSString *)node;
        if (TCStrHasCartId(s)) return YES;
        NSUInteger len = [s length];
        if (len >= 2 && len <= 262144) {
            // JSON-string value? Parse and re-walk the object graph.
            NSRange ws = [s rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
            NSUInteger first = (ws.location == 0) ? 1 : 0;
            unichar c = [s characterAtIndex:first];
            if (c == '{' || c == '[') {
                NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
                id parsed = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
                if (parsed != nil && parsed != node) {
                    return TCDeepCartWalk(parsed, depth + 1, budget);
                }
            }
        }
        return NO;
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)node;
        for (id k in d) {
            if ([k isKindOfClass:[NSString class]]) {
                NSString *ks = (NSString *)k;
                id v = d[k];
                if ([ks isEqualToString:@"containerId"] &&
                    [v isKindOfClass:[NSString class]] && TCStrIsCartId((NSString *)v)) return YES;
                if (TCStrHasCartId(ks)) return YES;
            }
            if (TCDeepCartWalk(d[k], depth + 1, budget)) return YES;
            if (*budget <= 0) return NO;
        }
        return NO;
    }
    if ([node isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)node) {
            if (TCDeepCartWalk(e, depth + 1, budget)) return YES;
            if (*budget <= 0) return NO;
        }
        return NO;
    }
    if ([node isKindOfClass:[NSData class]]) {
        NSString *s = [[NSString alloc] initWithData:(NSData *)node encoding:NSUTF8StringEncoding];
        if (s) return TCDeepCartWalk(s, depth + 1, budget);
        return NO;
    }
    return NO;
}

// Tag set on MtopExtRequest instances built by the Weex bridge whose
// own (verbatim JS) params matched the cart containers.
static char TCCartTagKey;

static BOOL TCCartParamsMatch(id req) {
    if (req == nil) return NO;
    if (objc_getAssociatedObject(req, &TCCartTagKey) != nil) return YES;
    @try {
        int budget = 4000;
        if (TCDeepCartWalk(TBM(req, "getBizParameters"), 0, &budget)) return YES;
        budget = 4000;
        if (TCDeepCartWalk(TBM(req, "getExtParameters"), 0, &budget)) return YES;
    } @catch (NSException *e) { }
    return NO;
}

// Empty every array value inside a (mutable) dict, recursing into
// nested dicts; scalars (ret codes, totals, paging flags) stay intact
// so the consumer's native "empty result" path runs.
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

// Returns the emptied body, or nil to fail open. Gateway-shaped
// responses keyed by containerId are emptied surgically (only the cart
// container's subtree); other shapes fall back to emptying the whole
// `data` payload of this one matched request (formal3 behavior).
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

// ---- cart top activity banner (target 7) --------------------------------
// Identity (V4_A_CART.md §7, formal6 B status-quo): the banner card
// inside the query.bag HIERARCHY structure — data field
// "topAdBanner_1", rendered by the DinamicX template
// "icart_top_banner". Copy text / amounts are server content and are
// never used as keys. Checkout, the cart body and the JS filter rows
// (降价/分组/常购/失效) are different nodes/fields and are not touched;
// the API itself is never blocked.
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
        // A dict that directly carries the banner template id IS the
        // banner node; empty it (never the root envelope itself).
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

// Returns the pruned body, or nil to fail open (neither anchor present
// anywhere — the banner is not in this response shape).
static id TCFilteredBagBody(id body) {
    if (![body isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *b = TCMutableCopy(body, 0);
    BOOL acted = NO;
    TCStripBannerInNode(b, 0, &acted);
    return acted ? b : nil;
}

// ---- shared: write a new body back into the response ------------------
// All-or-nothing: serialize FIRST; only when the new body serializes
// cleanly are body/json/rawbody written (together, consistently). Any
// failure leaves the original response completely untouched (fail-open).
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

static id TCGetResponse(id self, SEL _cmd, id raw, id mreq) {
    id resp = gOrigGetResp ? gOrigGetResp(self, _cmd, raw, mreq) : nil;
    if (resp == nil) return resp;
    @try {
        // Step 1: read ONLY the api name — a single object-typed getter,
        // class-checked in TCApiOfResponse. Non-target APIs return here:
        // for them NOT ONE other field of the response is read or touched.
        NSString *api = TCApiOfResponse(resp);
        if (api == nil) return resp;
        BOOL isCart = TCCartAPI(api);
        BOOL isBag = [api isEqualToString:@"mtop.trade.query.bag"];
        if (!isCart && !isBag) return resp;
        // Step 2 (target APIs only): failure responses pass untouched.
        // isSucceed returns BOOL, so it is read through the typed helper —
        // NEVER through the id-returning TBM (formal1 crash root cause).
        BOOL ok = YES;
        if (TBMBool(resp, "isSucceed", &ok) && !ok) return resp;
        // Step 3: each filter validates every level it touches and
        // returns nil (fail-open) on any shape mismatch.
        if (isCart) {
            if (TCCartParamsMatch(TBM(resp, "request"))) {
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

// ---- cart layer (b): Weex bridge tagging --------------------------------
// -[WXMtopRequest generateMtopRequest] (IMP 0x101254058) builds the
// MtopExtRequest out of the JS-supplied parameters. At this exit the
// request's biz/ext parameters are the JS data verbatim — before any
// TBSDK/MtopService-side copying — so the object-level match is run
// here too, and a hit tags the request instance. The response-side
// point (layer a) honors the tag; if the instance does not survive to
// the response, the tag is simply never seen (fail-open).
typedef id (*GenMtopIMP)(id, SEL);
static GenMtopIMP gOrigGenMtop = NULL;

static id TCGenerateMtopRequest(id self, SEL _cmd) {
    id req = gOrigGenMtop ? gOrigGenMtop(self, _cmd) : nil;
    if (req == nil) return req;
    @try {
        int budget = 4000;
        BOOL hit = TCDeepCartWalk(TBM(req, "getBizParameters"), 0, &budget);
        if (!hit) {
            budget = 4000;
            hit = TCDeepCartWalk(TBM(req, "getExtParameters"), 0, &budget);
        }
        if (hit) {
            objc_setAssociatedObject(req, &TCCartTagKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *e) { }
    return req;
}

// ---- cart layer (c): native repo consumption guard ----------------------
// -[TBRecmdContentDataRepo processResData:success:error:oriDic:page:]
// (IMP 0x104b93cfc) is where a fetched page's parsed model is merged
// into the repo: for the TBRecmdLoadDataResData shape it reads
// resData.sections and appends them into the repo's contentData, then
// runs the normal update/refresh funnel (loading status is reset at
// its head, so the state machine completes exactly as for a native
// empty page). For a repo whose own containerId is a cart id, a
// successful resData gets its sections emptied before the original
// implementation runs. Arguments are forwarded verbatim; page is only
// passed through, never interpreted.
typedef void (*ProcessResIMP)(id, SEL, id, BOOL, id, id, long long);
static ProcessResIMP gOrigProcessRes = NULL;

static void TCProcessResData(id self, SEL _cmd, id resData, BOOL success,
                             id error, id oriDic, long long page) {
    @try {
        if (success && resData != nil) {
            id cid = TBM(self, "containerId");
            if ([cid isKindOfClass:[NSString class]] && TCStrIsCartId((NSString *)cid)) {
                Class rc = objc_getClass("TBRecmdLoadDataResData");
                if (rc != Nil && [resData isKindOfClass:rc]) {
                    TBMSet(resData, "setSections:", [NSArray array]);
                }
            }
        }
    } @catch (NSException *e) { }
    if (gOrigProcessRes) gOrigProcessRes(self, _cmd, resData, success, error, oriDic, page);
}

// ============================================================ install ======
static BOOL TCHook(const char *clsName, const char *selName, BOOL isClass,
                   IMP repl, IMP *origOut) {
    Class cls = objc_getClass(clsName);
    if (cls == Nil) return NO;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    Method m = isClass ? class_getClassMethod(cls, sel) : class_getInstanceMethod(cls, sel);
    if (m == NULL) return NO;
    if (*origOut != NULL) return YES;
    *origOut = method_getImplementation(m);
    method_setImplementation(m, repl);
    return YES;
}

// ========================================================== PopLayer =====
// Class-wide block for marketing modals on Page_Home / Page_MyTaobao.
// (Unchanged from formal4; see FORMAL_NOTES §1 for the full evidence.)
// - The single funnel for layer creation in the main binary is
//   TBPLLayerFactory -createLayerWithFrame:type:popRequest:attachVC:.
//   Its only real caller (TBPLPageTriggerService -p_onReadyOperation:)
//   explicitly nil-checks the result and cancels cleanly via the native
//   "OnViewCustomFilter" lose path, and the factory itself returns nil
//   by design for unregistered types. Returning nil for matched
//   requests is a native-shaped outcome.
// - Discrimination key: the request's event uri
//   ([popRequest event] -> uri), matched by slot prefix:
//     poplayer://Page_Home@popup_*
//     poplayer://Page_MyTaobao@popup_*
//   popup_guide_float_* is included: its config entries are
//   field-identical to the modal slots; genuine float/resident/guide
//   slots use float_* / resident prefixes and are untouched.
// - Variant 2 (config:targetUrl:) has no caller in the main binary and
//   its event.uri is always nil, so no point is set there.
// - queryInventory: is a freq-control gate with no candidate set;
//   deliberately NOT touched.
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

// ===================================================== home float bar ====
// TBHRContainerContentModel -floatLayerSection (IMP 0x10453af5c in the
// pristine binary) forced to nil — formal4 behavior, kept as-is.
// Formal6 D findings (diag3 caller symbolization): the getter IS read
// (x2 in the probe session) — once from TBHRGwLoadCacheAction
// -deepCopyBaseAsTotal: (return address in function 0x10453d564, the
// only app-code caller) and once through a system-framework frame
// (return address outside the main binary __text, consistent with a
// KVC valueForKey: read). With the getter returning nil on every read
// the bar still renders, so the rendering consumer does not depend on
// this property (originalData is stored independently at parse time);
// the true consumption point is not statically pinnable. This hook
// provably neutralizes the deepCopy path; the surface is NOT claimed
// fixed (see FORMAL_NOTES formal6 D).
typedef id (*FloatGetterIMP)(id, SEL);
static FloatGetterIMP gOrigFloatGetter = NULL;
static id TCFloatLayerSection(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return nil;
}

// ============================================== search landing sections ====
// TBXSearchActivationTppParser -getProcessedData: (IMP 0x104731210)
// exit filter — unchanged from formal4 (formal6 E status-quo: no
// ObjC-visible equivalent assembly exit exists in the Swift/XSL new
// door, so there is no second point to dual-hook; this module remains
// unverified). At this point the section list (itemsArray) is fully
// assembled and network + cache paths have converged. History
// protection is by tItemType (a stable client-compared constant), NOT
// by title: the three history types are the only tItemType values the
// client itself ever compares literally. The two target sections'
// tItemType values are server-side pass-through constants that never
// appear literally in the client; the section "name" field remains
// the only client-visible key.
typedef id (*ParserIMP)(id, SEL, id);
static ParserIMP gOrigParser = NULL;

static BOOL TCHistoryType(id t) {
    if (![t isKindOfClass:[NSString class]]) return NO;
    NSString *s = (NSString *)t;
    return [s isEqualToString:@"nt_history"] ||
           [s isEqualToString:@"nt_combine_history"] ||
           [s isEqualToString:@"nt_multimodal_history"];
}

static id TCGetProcessedData(id self, SEL _cmd, id raw) {
    id out = gOrigParser ? gOrigParser(self, _cmd, raw) : nil;
    if (out == nil) return out;
    @try {
        if (![out isKindOfClass:[NSDictionary class]]) return out;
        id items = ((NSDictionary *)out)[@"itemsArray"];
        if (![items isKindOfClass:[NSArray class]]) return out;
        NSArray *a = (NSArray *)items;
        NSMutableArray *keep = nil; // built lazily at the first drop
        NSUInteger idx = 0;
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
                if (keep == nil) keep = [[a subarrayWithRange:NSMakeRange(0, idx)] mutableCopy];
            } else if (keep != nil) {
                [keep addObject:sec];
            }
            idx++;
        }
        if (keep == nil) return out; // nothing dropped: original untouched
        NSMutableDictionary *o = [out mutableCopy];
        o[@"itemsArray"] = keep;
        return o;
    } @catch (NSException *e) { return out; }
}

// ===================================================== MyTaobao bottom ====
// Formal6 module 6 (see the header for the full rationale). The
// formal4 factory-exit downgrade hook on
// +[MTComponentModel creatComponent:componentData:] is REMOVED: diag3
// proved the factory fires for basementTip with native containerType 3,
// yet the downgraded build still rendered the section.
//
// (a) -[MTMainPageDataModel setComponents:] — every model instance is
// built by +creatMainPageDataModel:global:mainPageDataSource:, whose
// implementation only calls the three setters; filtering here means
// the model's own (only) components list never contains basementTip,
// for full and prefetch builds alike.
typedef void (*SetComponentsIMP)(id, SEL, id);
static SetComponentsIMP gOrigSetComponents = NULL;

static BOOL TCIsBasementTip(id comp) {
    id mn = TBM(comp, "moduleName");
    return [mn isKindOfClass:[NSString class]] &&
           [(NSString *)mn isEqualToString:@"basementTip"];
}

static void TCMySetComponents(id self, SEL _cmd, id components) {
    id pass = components;
    @try {
        if ([components isKindOfClass:[NSArray class]]) {
            NSArray *a = (NSArray *)components;
            NSMutableArray *keep = nil; // built lazily at the first drop
            NSUInteger idx = 0;
            for (id comp in a) {
                if (TCIsBasementTip(comp)) {
                    if (keep == nil) keep = [[a subarrayWithRange:NSMakeRange(0, idx)] mutableCopy];
                } else if (keep != nil) {
                    [keep addObject:comp];
                }
                idx++;
            }
            if (keep != nil) pass = keep;
        }
    } @catch (NSException *e) { pass = components; }
    if (gOrigSetComponents) gOrigSetComponents(self, _cmd, pass);
}

// (b) -[MTMainPageUserDataService listenComponentsChange:] — the sole
// registration point for component-change blocks (its only caller is
// TBMyTaobaoViewController -listenComponentsChange). The block
// receives an NSDictionary<moduleName, MTComponentModel> of CHANGED
// components (C++ diff output; basementTip is force-diffed via
// nativeBasementTipForceDiff). The wrapper forwards the dictionary
// without the basementTip entry; a basementTip-only change becomes an
// empty dictionary, which the VC block treats as "no change" (it
// posts the Dojo component-changed event only for a non-empty array
// built from the dictionary). The wrapper is heap-copied before
// registration, matching the lifetime the C++ listener table expects.
//
// LIFETIME (formal7 fix): the incoming block is a STACK block literal
// built in the caller's own frame (TBMyTaobaoViewController
// -listenComponentsChange constructs it on its stack, invoke
// 0x104090c28). It must be heap-copied HERE, synchronously, while
// that frame is alive. Formal6 captured it as a plain `id`, whose
// block-copy helper degenerates to objc_storeStrong (retain) — and
// retain is a no-op on a stack block — so the wrapper dangled the
// moment the registering frame returned; when the change event later
// fired on the main queue, the dead block's invoke field read back
// as 0 and the call jumped to address 0 (crash log
// Taobao4iPhone-2026-11-14-170611.ips: PC=0, LR = wrapper block
// invoke +532, exactly the origBlock call site). Declaring the
// variable block-typed and assigning an explicit [block copy] makes
// the wrapper's copy helper use BLOCK_FIELD_IS_BLOCK semantics, so
// the heap copy's lifetime is tied to the wrapper's.
typedef void (*ListenIMP)(id, SEL, id);
static ListenIMP gOrigListenComponents = NULL;

static void TCMyListenComponentsChange(id self, SEL _cmd, id block) {
    id pass = block;
    @try {
        if (block != nil) {
            void (^origBlock)(NSDictionary *) =
                (void (^)(NSDictionary *))[block copy];
            void (^wrapper)(NSDictionary *) = ^(NSDictionary *change) {
                NSDictionary *out = change;
                @try {
                    if ([change isKindOfClass:[NSDictionary class]] &&
                        ((NSDictionary *)change)[@"basementTip"] != nil) {
                        if ([change count] == 1) {
                            out = [NSDictionary dictionary];
                        } else {
                            NSMutableDictionary *m = [change mutableCopy];
                            [m removeObjectForKey:@"basementTip"];
                            out = m;
                        }
                    }
                } @catch (NSException *e) { out = change; }
                ((void (^)(NSDictionary *))origBlock)(out);
            };
            pass = [wrapper copy];
        }
    } @catch (NSException *e) { pass = block; }
    if (gOrigListenComponents) gOrigListenComponents(self, _cmd, pass);
}

// ======================================================== tab bar slot ====
// +[TBAppUIStyle currentTabbarVCItems] (IMP 0x10012ba80) — unchanged
// from formal4, verified on device. The slot-2 (guangguang) item is
// removed at this single source; every derived array (viewControllers,
// tab items, ItemConfig, attract bizMap) shortens together, so
// positional routing stays consistent and badges (located by biz
// string, tag only a bounds gate) are unaffected. Identity is by code
// literals (url / attractBiz), never by the rotating title/artwork.
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

static void TCInstallAll(void) {
    TCHook("MtopService", "getResponse:mrequest:", NO, (IMP)TCGetResponse, (IMP *)&gOrigGetResp);
    TCHook("WXMtopRequest", "generateMtopRequest", NO, (IMP)TCGenerateMtopRequest, (IMP *)&gOrigGenMtop);
    TCHook("TBRecmdContentDataRepo", "processResData:success:error:oriDic:page:", NO, (IMP)TCProcessResData, (IMP *)&gOrigProcessRes);
    TCHook("TBPLLayerFactory", "createLayerWithFrame:type:popRequest:attachVC:", NO, (IMP)TCFactoryCreate, (IMP *)&gOrigFactory);
    TCHook("TBHRContainerContentModel", "floatLayerSection", NO, (IMP)TCFloatLayerSection, (IMP *)&gOrigFloatGetter);
    TCHook("TBXSearchActivationTppParser", "getProcessedData:", NO, (IMP)TCGetProcessedData, (IMP *)&gOrigParser);
    TCHook("MTMainPageDataModel", "setComponents:", NO, (IMP)TCMySetComponents, (IMP *)&gOrigSetComponents);
    TCHook("MTMainPageUserDataService", "listenComponentsChange:", NO, (IMP)TCMyListenComponentsChange, (IMP *)&gOrigListenComponents);
    TCHook("TBAppUIStyle", "currentTabbarVCItems", YES, (IMP)TCVCItems, (IMP *)&gOrigVCItems);
}

// TBDiag4 view-probe overlay (defined at the end of this file). The
// formal7 filter code above is byte-for-byte TBClean 1.6; the overlay
// adds ONLY read-only view introspection + the diag presentation.
static void TD4Start(void);

__attribute__((constructor)) static void TCEntry(void) {
    @autoreleasepool {
        TCInstallAll();
        TD4Start();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ TCInstallAll(); });
    }
}

// ============================================================ TBDiag4 ======
// TBDiag4.1 — READ-ONLY view-layer probe overlay on the formal7 base
// (TBClean 1.6, filters byte-for-byte identical, main binary P1+P3+P4
// untouched). Why: the four remaining surfaces (cart recommend flow,
// cart top activity banner ⑦, search-door sections, home floating bar)
// all survived data-side filtering because their in-process data shapes
// were never directly observed (diag3 / formal6 findings). Formal8
// switches to a VIEW-layer approach, so this build photographs, once
// per page visit, the view/component identity of each surface:
// V1 home float bar: text-clue leaf ("超级88"/"领635元") -> ancestor
// chain to the home root view, top-level container identity,
// close-button presence, TBHomeViewController root children list.
// V2 cart (Weex page): (a) UIKit layer — cart VC root children and
// the Weex canvas (WXRootView); (b) Weex component tree via
// runtime introspection (side-effect-free ivar graph walk from
// the VC / canvas), root 3-layer skeleton, and the component
// PATHS of the ⑦ banner component and the recommend-flow
// component, located by text/attribute clues.
// V3 search door (WHITELIST enumeration, user 2026-11-14 17:30:
// the landing page keeps ONLY history; every other section is a
// removal target): FULL section enumeration of every scroll
// container on the door VC — per section: index, header view
// class, header text, first-cell class, row count — each section
// classified /, and sections
// that are neither history nor the two known targets additionally
// flagged. (The search box and the scan/voice/image
// tool row are functional UI, not sections, and are excluded.)
// Presentation (4.1 trigger rework — the 4.0 build popped an overview
// at cold start and re-armed per visit, which fought the user's
// delete-reinstall login flow): NO overview popup; alert pages titled
// 「诊断4」 (one page per face, key identity lines first) are QUEUED
// and shown one at a time, only while no alert/modal is currently
// presented; every dump is written to Documents/TBDiag4.txt BEFORE
// its page is queued, so a late popup never loses data (the overview
// text survives only as that file's header).
//
// Safety: the overlay installs NO hooks and mutates NOTHING. Trigger
// discipline (4.1): a 120s startup grace period (probe fully
// disarmed — no classification, no dumps, no popups — so a fresh
// install's login/guide flow is never disturbed); after that, a 1s
// main-queue watcher classifies the visible page and a face must
// stay CONTINUOUSLY frontmost for >=8s before its dump runs; each
// face dumps AT MOST ONCE per process (no re-arm). Dumps are bounded
// (node budgets, depth caps, @try everywhere, typed getters only —
// the formal1 isSucceed lesson applies to every primitive read
// here too).

__attribute__((used)) static const char kTD4Version[] = "TBDiag4.1/1.0";

// ------------------------------------------------------------- state -----
static NSDate *gD4Start = nil;
static id gD4Lock = nil;
static NSMutableArray *gD4Events = nil; // short event lines
static NSMutableArray *gD4FileParts = nil; // full dump records
static NSString *gD4PageHome = nil; // popup page texts
static NSString *gD4PageCart = nil;
static NSString *gD4PageSearch = nil;
static NSMutableArray *gD4PendingPages = nil; // page keys awaiting show
static int gD4Shows = 0;
static double gD4LastShowAt = -1000;
// watcher state
static int gD4CurKind = 0; // 0 none 1 home 2 cart 3 search
static double gD4KindSince = 0;
static BOOL gD4DumpedHome = NO, gD4DumpedCart = NO, gD4DumpedSearch = NO;
static int gD4AbsentTicks = 0;

static double D4Now(void) { return [[NSDate date] timeIntervalSinceDate:gD4Start];}

static void D4Event(NSString *fmt,...) {
va_list ap; va_start(ap, fmt);
NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
va_end(ap);
@synchronized (gD4Lock) {
[gD4Events addObject:[NSString stringWithFormat:@"[+%.0fs] %@", D4Now(), msg]];
while ([gD4Events count] > 60) [gD4Events removeObjectAtIndex:0];
}
}

static NSString *D4Short(id obj, NSUInteger cap) {
if (obj == nil) return @"(nil)";
NSString *s = nil;
@try { s = [obj description];} @catch (NSException *e) { s = @"<desc-fail>";}
if (s == nil) s = @"";
s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
if ([s length] > cap) s = [[s substringToIndex:cap] stringByAppendingString:@"…"];
return s;
}

static NSString *D4Cls(id obj) {
return obj? NSStringFromClass([obj class]): @"(nil)";
}

// ------------------------------------------------- typed primitive reads --
// CGRect is returned as an HFA of 4 doubles on arm64, so a struct-cast
// msgSend is ABI-correct; declared locally to avoid any UIKit header
// dependency (this dylib links Foundation only, like its predecessors).
typedef struct D4Rect { double x, y, w, h;} D4Rect;
static BOOL D4GetFrame(id v, D4Rect *out) {
if (v == nil || out == NULL) return NO;
SEL sel = @selector(frame);
if (![v respondsToSelector:sel]) return NO;
*out = ((D4Rect (*)(id, SEL))objc_msgSend)(v, sel);
return YES;
}
static NSString *D4FrameStr(id v) {
D4Rect r;
if (!D4GetFrame(v, &r)) return @"f=?";
return [NSString stringWithFormat:@"f=%.0f,%.0f %.0fx%.0f", r.x, r.y, r.w, r.h];
}
static BOOL D4GetBool(id obj, const char *selName, BOOL *out) {
return TBMBool(obj, selName, out);
}
static BOOL D4GetInt(id obj, const char *selName, long long *out) {
if (obj == nil || out == NULL) return NO;
SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
if (![obj respondsToSelector:sel]) return NO;
*out = ((long long (*)(id, SEL))objc_msgSend)(obj, sel);
return YES;
}

// ------------------------------------------------------- view utilities ---
static NSArray *D4Subviews(id v) {
id s = TBM(v, "subviews");
return [s isKindOfClass:[NSArray class]]? (NSArray *)s: @[];
}
static id D4Superview(id v) { return TBM(v, "superview");}

// Visible text of a single view (label / button / text field), or nil.
static NSString *D4ViewText(id v) {
if (v == nil) return nil;
@try {
NSString *cls = NSStringFromClass([v class]);
id t = nil;
if ([cls isEqualToString:@"UILabel"] || [v respondsToSelector:NSSelectorFromString(@"text")] &&
([cls containsString:@"Label"] || [cls containsString:@"TextField"] || [cls containsString:@"TextView"])) {
t = TBM(v, "text");
}
if (![t isKindOfClass:[NSString class]] || [(NSString *)t length] == 0) {
if ([cls containsString:@"Button"]) {
id tl = TBM(v, "titleLabel");
id tt = TBM(tl, "text");
if ([tt isKindOfClass:[NSString class]] && [(NSString *)tt length]) t = tt;
else {
id ct = TBM(v, "currentTitle");
if ([ct isKindOfClass:[NSString class]] && [(NSString *)ct length]) t = ct;
}
}
}
if ([t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) {
NSString *s = [(NSString *)t stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}
} @catch (NSException *e) {}
return nil;
}

// DFS (bounded) collecting "Class「text」" entries for text-bearing
// leaves, in tree order.
static void D4CollectTexts(id v, int depth, int *budget, NSMutableArray *out, NSUInteger maxOut) {
if (v == nil || depth > 16 || *budget <= 0 || [out count] >= maxOut) return;
(*budget)--;
@try {
NSString *t = D4ViewText(v);
if (t!= nil) {
NSString *show = [t length] > 42? [[t substringToIndex:42] stringByAppendingString:@"…"]: t;
[out addObject:[NSString stringWithFormat:@"%@「%@」", D4Cls(v), show]];
}
for (id sub in D4Subviews(v)) {
D4CollectTexts(sub, depth + 1, budget, out, maxOut);
if (*budget <= 0 || [out count] >= maxOut) return;
}
} @catch (NSException *e) {}
}

// DFS (bounded) finding leaf views whose text contains any needle;
// results appended to `hits` (views retained by the array).
static void D4FindTextLeaves(id v, NSArray *needles, int depth, int *budget,
NSMutableArray *hits, NSUInteger maxHits) {
if (v == nil || depth > 18 || *budget <= 0 || [hits count] >= maxHits) return;
(*budget)--;
@try {
NSString *t = D4ViewText(v);
if (t!= nil) {
for (NSString *n in needles) {
if ([t rangeOfString:n].location!= NSNotFound) { [hits addObject:v]; return;}
}
}
for (id sub in D4Subviews(v)) {
D4FindTextLeaves(sub, needles, depth + 1, budget, hits, maxHits);
if (*budget <= 0 || [hits count] >= maxHits) return;
}
} @catch (NSException *e) {}
}

// DFS (bounded) finding the first view whose class name equals `name`.
static id D4FindClass(id v, NSString *name, int depth, int *budget) {
if (v == nil || depth > 18 || *budget <= 0) return nil;
(*budget)--;
@try {
if ([NSStringFromClass([v class]) isEqualToString:name]) return v;
for (id sub in D4Subviews(v)) {
id hit = D4FindClass(sub, name, depth + 1, budget);
if (hit!= nil) return hit;
if (*budget <= 0) return nil;
}
} @catch (NSException *e) {}
return nil;
}

// DFS (bounded) collecting all views of the given exact classes.
static void D4FindAllClass(id v, NSSet *names, int depth, int *budget,
NSMutableArray *out, NSUInteger maxOut) {
if (v == nil || depth > 18 || *budget <= 0 || [out count] >= maxOut) return;
(*budget)--;
@try {
if ([names containsObject:NSStringFromClass([v class])]) [out addObject:v];
for (id sub in D4Subviews(v)) {
D4FindAllClass(sub, names, depth + 1, budget, out, maxOut);
if (*budget <= 0 || [out count] >= maxOut) return;
}
} @catch (NSException *e) {}
}

// Comma-joined names of properties (class + up to 2 superclasses),
// bounded. Used to expose the exact accessor names formal8 needs.
static NSString *D4PropertyOutline(Class cls) {
NSMutableArray *names = [NSMutableArray array];
@try {
Class c = cls;
for (int lvl = 0; c!= Nil && lvl < 3; lvl++, c = class_getSuperclass(c)) {
unsigned int n = 0;
objc_property_t *props = class_copyPropertyList(c, &n);
for (unsigned int i = 0; i < n && [names count] < 70; i++) {
[names addObject:[NSString stringWithUTF8String:property_getName(props[i])]];
}
if (props) free(props);
}
} @catch (NSException *e) {}
return [names componentsJoinedByString:@","];
}

// Object-typed ivar names of a class (+1 superclass level), bounded.
static NSArray *D4ObjectIvarNames(Class cls) {
NSMutableArray *names = [NSMutableArray array];
@try {
Class c = cls;
for (int lvl = 0; c!= Nil && lvl < 2; lvl++, c = class_getSuperclass(c)) {
unsigned int n = 0;
Ivar *ivars = class_copyIvarList(c, &n);
for (unsigned int i = 0; i < n && [names count] < 90; i++) {
const char *enc = ivar_getTypeEncoding(ivars[i]);
if (enc!= NULL && enc[0] == '@') {
[names addObject:[NSString stringWithUTF8String:ivar_getName(ivars[i])]];
}
}
if (ivars) free(ivars);
}
} @catch (NSException *e) {}
return names;
}

static id D4GetIvar(id obj, const char *name) {
if (obj == nil) return nil;
@try {
Ivar iv = class_getInstanceVariable([obj class], name);
if (iv == NULL) return nil;
const char *enc = ivar_getTypeEncoding(iv);
if (enc == NULL || enc[0]!= '@') return nil;
return object_getIvar(obj, iv);
} @catch (NSException *e) { return nil;}
}

// -------------------------------------------------- visible VC resolve ----
// Walk key window -> tab selection -> nav visible -> presented chain
// (skipping alert controllers). Returns the deepest visible VC; the
// tab-root VC is returned via outRoot when resolvable.
static id D4TopVC(id *outRoot) {
    if (outRoot) *outRoot = nil;
    Class appCls = objc_getClass("UIApplication");
    if (appCls == Nil) return nil;
    id app = ((id (*)(id, SEL))objc_msgSend)(appCls, NSSelectorFromString(@"sharedApplication"));
    NSArray *windows = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"windows"));
    id key = nil;
    for (id w in windows) {
        BOOL k = NO;
        if (D4GetBool(w, "isKeyWindow", &k) && k) { key = w; break; }
    }
    if (key == nil) key = [windows firstObject];
    if (key == nil) return nil;
    id root = TBM(key, "rootViewController");
    if (root == nil) return nil;
    id cur = root;
    // Unwrap the tab selection once, remembering the tab-root VC.
    Class tabCls = objc_getClass("UITabBarController");
    if (tabCls != Nil && [cur isKindOfClass:tabCls]) {
        id sel = TBM(cur, "selectedViewController");
        if (sel != nil) {
            cur = sel;
            Class navCls = objc_getClass("UINavigationController");
            id r = sel;
            if (navCls != Nil && [sel isKindOfClass:navCls]) {
                NSArray *stack = TBM(sel, "viewControllers");
                if ([stack isKindOfClass:[NSArray class]] && [stack count]) r = [stack firstObject];
            }
            if (outRoot) *outRoot = r;
        }
    }
    // Follow nav-visible + presented to the visible leaf VC.
    for (int guard = 0; guard < 12; guard++) {
        id next = nil;
        Class navCls = objc_getClass("UINavigationController");
        if (navCls != Nil && [cur isKindOfClass:navCls]) {
            next = TBM(cur, "visibleViewController");
        }
        if (next == nil) {
            id presented = TBM(cur, "presentedViewController");
            if (presented != nil && ![NSStringFromClass([presented class]) containsString:@"Alert"]) {
                next = presented;
            }
        }
        if (next == nil || next == cur) break;
        cur = next;
    }
    if (outRoot && *outRoot == nil) *outRoot = cur;
    return cur;
}

// ============================================================ V1: home ====
// Float bar: locate by text clue, walk the ancestor chain to the home
// root view, identify the top-level container (the direct root child
// on that chain), its constraint outline, and close-button presence.
static NSString *D4DumpHome(id vc) {
    NSMutableString *s = [NSMutableString string];
    @try {
        id rootView = TBM(vc, "view");
        [s appendFormat:@"VC=%@\n", D4Cls(vc)];
        NSArray *children = D4Subviews(rootView);
        [s appendFormat:@"根视图直子×%lu:\n", (unsigned long)[children count]];
        NSUInteger ci = 0;
        for (id ch in children) {
            BOOL hid = NO; D4GetBool(ch, "isHidden", &hid);
            [s appendFormat:@" %lu %@ %@%@\n", (unsigned long)ci++, D4Cls(ch),
             D4FrameStr(ch), hid ? @" hidden" : @""];
            if (ci >= 24) { [s appendString:@" …(截断)\n"]; break; }
        }
        int budget = 6000;
        NSMutableArray *hits = [NSMutableArray array];
        D4FindTextLeaves(rootView, @[@"超级88", @"领635"], 0, &budget, hits, 3);
        if ([hits count] == 0) {
            [s appendString:@"横条叶子:未找到「超级88/领635元」文本(条可能未展示)\n"];
            int b2 = 4000;
            NSMutableArray *texts = [NSMutableArray array];
            D4CollectTexts(rootView, 0, &b2, texts, 30);
            [s appendFormat:@"页面文本样本:[%@]\n", [texts componentsJoinedByString:@" | "]];
            return s;
        }
        id leaf = [hits firstObject];
        NSString *lt = D4ViewText(leaf);
        if ([lt length] > 34) lt = [[lt substringToIndex:34] stringByAppendingString:@"…"];
        [s appendFormat:@"横条叶子:%@「%@」\n", D4Cls(leaf), lt ?: @""];
        // Ancestor chain, leaf -> root view.
        NSMutableArray *chain = [NSMutableArray array];
        id node = leaf;
        for (int g = 0; node != nil && g < 24; g++) {
            [chain addObject:node];
            if (node == rootView) break;
            node = D4Superview(node);
        }
        [s appendString:@"祖先链(叶→根):\n"];
        NSUInteger li = 0;
        id topContainer = nil;
        for (id n in chain) {
            [s appendFormat:@" L%lu %@ %@\n", (unsigned long)li++, D4Cls(n), D4FrameStr(n)];
            if (D4Superview(n) == rootView) topContainer = n;
        }
        if (topContainer == nil && [chain count] > 1) topContainer = chain[[chain count] - 2];
        if (topContainer != nil) {
            BOOL tam = YES; D4GetBool(topContainer, "translatesAutoresizingMaskIntoConstraints", &tam);
            id cons = TBM(topContainer, "constraints");
            NSUInteger ncons = [cons isKindOfClass:[NSArray class]] ? [cons count] : 0;
            [s appendFormat:@"顶层容器:%@ %@ mask自动=%@ 约束×%lu\n",
             D4Cls(topContainer), D4FrameStr(topContainer), tam ? @"Y" : @"N",
             (unsigned long)ncons];
            if ([cons isKindOfClass:[NSArray class]]) {
                NSUInteger shown = 0;
                for (id c in (NSArray *)cons) {
                    if (shown++ >= 3) break;
                    [s appendFormat:@" 约束:%@\n", D4Short(c, 76)];
                }
            }
            // Close button inside the same container?
            int b3 = 2500;
            NSMutableArray *closeHits = [NSMutableArray array];
            D4FindTextLeaves(topContainer, @[@"×", @"✕", @"✖"], 0, &b3, closeHits, 2);
            int nb = 0;
            NSMutableArray *btnClasses = [NSMutableArray array];
            int b4 = 2500;
            NSMutableArray *btns = [NSMutableArray array];
            D4FindAllClass(topContainer, [NSSet setWithObject:@"UIButton"], 0, &b4, btns, 12);
            nb = (int)[btns count];
            for (id b in btns) if (![btnClasses containsObject:D4Cls(b)]) [btnClasses addObject:D4Cls(b)];
            // Buttons in Taobao are often custom classes; count any view
            // whose class name contains "Button" or "Close" as well.
            NSString *closeInfo = [closeHits count]
                ? [NSString stringWithFormat:@"有(×文本叶 %@)", D4Cls([closeHits firstObject])]
                : @"未见×文本";
            [s appendFormat:@"容器内UIButton×%d%@ 关闭线索:%@\n",
             nb, [btnClasses count] ? [NSString stringWithFormat:@"[%@]", [btnClasses componentsJoinedByString:@","]] : @"",
             closeInfo];
        }
    } @catch (NSException *e) {
        [s appendFormat:@"(dump异常:%@)\n", [e name]];
    }
    return s;
}

// ============================================================ V2: cart ====
// Weex component accessors are read defensively: Alibaba's fork may
// name them differently, so every read tries selector -> ivar, and the
// root component's full property outline is recorded for formal8.
static NSString *D4CompType(id comp) {
    id t = TBM(comp, "type");
    if ([t isKindOfClass:[NSString class]] && [(NSString *)t length]) return (NSString *)t;
    id iv = D4GetIvar(comp, "_type");
    if ([iv isKindOfClass:[NSString class]]) return (NSString *)iv;
    return @"?";
}
static NSString *D4CompRef(id comp) {
    id t = TBM(comp, "ref");
    if ([t isKindOfClass:[NSString class]] && [(NSString *)t length]) return (NSString *)t;
    id iv = D4GetIvar(comp, "_ref");
    if ([iv isKindOfClass:[NSString class]]) return (NSString *)iv;
    return @"?";
}
static NSArray *D4CompChildren(id comp, NSString **usedSel) {
    static const char *cands[] = {"childComponents", "subcomponents", "children", "components", NULL};
    for (int i = 0; cands[i] != NULL; i++) {
        id v = TBM(comp, cands[i]);
        if ([v isKindOfClass:[NSArray class]]) {
            if (usedSel) *usedSel = [NSString stringWithUTF8String:cands[i]];
            return (NSArray *)v;
        }
    }
    static const char *ivars[] = {"_childComponents", "_subcomponents", "_children", NULL};
    for (int i = 0; ivars[i] != NULL; i++) {
        id v = D4GetIvar(comp, ivars[i]);
        if ([v isKindOfClass:[NSArray class]]) {
            if (usedSel) *usedSel = [NSString stringWithFormat:@"ivar:%s", ivars[i]];
            return (NSArray *)v;
        }
    }
    if (usedSel) *usedSel = @"无";
    return @[];
}
static id D4CompLoadedView(id comp) {
    // Only the already-materialized view; never trigger a lazy load.
    id v = D4GetIvar(comp, "_view");
    if (v != nil && [v isKindOfClass:objc_getClass("UIView")]) return v;
    return nil;
}
// Concatenated string content of attributes/styles (bounded DFS) for
// clue scanning; also returns the top-level key list via outKeys.
static NSString *D4CompAttrBlob(id comp, NSString **outKeys) {
    NSMutableString *blob = [NSMutableString string];
    NSMutableArray *keyList = [NSMutableArray array];
    static const char *attrSels[] = {"attributes", "styles", NULL};
    for (int ai = 0; attrSels[ai] != NULL; ai++) {
        const char *selName = attrSels[ai];
        id d = TBM(comp, selName);
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        if (selName[0] == 'a') {
            for (id k in (NSDictionary *)d) {
                if ([k isKindOfClass:[NSString class]]) [keyList addObject:(NSString *)k];
            }
        }
        int budget = 160;
        NSMutableArray *stack = [NSMutableArray arrayWithObject:d];
        while ([stack count] && budget > 0) {
            id cur = [stack lastObject]; [stack removeLastObject];
            budget--;
            if ([cur isKindOfClass:[NSString class]]) {
                [blob appendString:(NSString *)cur]; [blob appendString:@" "];
            } else if ([cur isKindOfClass:[NSDictionary class]]) {
                for (id k in (NSDictionary *)cur) {
                    if ([k isKindOfClass:[NSString class]]) { [blob appendString:(NSString *)k]; [blob appendString:@" "]; }
                    [stack addObject:((NSDictionary *)cur)[k]];
                }
            } else if ([cur isKindOfClass:[NSArray class]]) {
                for (id e in (NSArray *)cur) [stack addObject:e];
            }
            if ([blob length] > 20000) break;
        }
    }
    if (outKeys) *outKeys = [keyList componentsJoinedByString:@","];
    return blob;
}

// Side-effect-free ivar graph walk from the seeds, hunting a
// WXComponent (root candidate), a WXSDKInstance, or a
// WXComponentManager. Records the discovery path for formal8.
static void D4HuntWeex(id seedVC, id seedCanvas,
                       id *outComp, id *outInstance, NSString **outRoute) {
    *outComp = nil; *outInstance = nil; *outRoute = @"未找到";
    Class compCls = objc_getClass("WXComponent");
    NSMutableArray *queue = [NSMutableArray array];
    NSMutableDictionary *paths = [NSMutableDictionary dictionary];
    NSMutableSet *visited = [NSMutableSet set];
    if (seedVC != nil) {
        [queue addObject:seedVC];
        paths[[NSValue valueWithPointer:(__bridge void *)seedVC]] = @"VC";
    }
    if (seedCanvas != nil) {
        [queue addObject:seedCanvas];
        paths[[NSValue valueWithPointer:(__bridge void *)seedCanvas]] = @"WXRootView";
    }
    // Direct selector attempts on the seeds first (cheap, common names).
    static const char *seedSels[] = {"rootComponent", "wxInstance", "sdkInstance", "weexInstance", "instance", "componentManager", NULL};
    for (id seed in @[seedVC ?: (id)[NSNull null], seedCanvas ?: (id)[NSNull null]]) {
        if ([seed isEqual:[NSNull null]]) continue;
        for (int si = 0; seedSels[si] != NULL; si++) {
            const char *selName = seedSels[si];
            id v = TBM(seed, selName);
            if (v == nil) continue;
            if (compCls != Nil && [v isKindOfClass:compCls] && *outComp == nil) {
                *outComp = v;
                *outRoute = [NSString stringWithFormat:@"%@ -[%s]→ %@", (seed == seedVC) ? @"VC" : @"WXRootView", selName, D4Cls(v)];
            }
            if ([NSStringFromClass([v class]) isEqualToString:@"WXSDKInstance"] && *outInstance == nil) {
                *outInstance = v;
            }
            if (![queue containsObject:v]) {
                [queue addObject:v];
                paths[[NSValue valueWithPointer:(__bridge void *)v]] =
                    [NSString stringWithFormat:@"%@.%s", (seed == seedVC) ? @"VC" : @"WXRootView", selName];
            }
        }
    }
    int budget = 260;
    NSUInteger qi = 0;
    while (qi < [queue count] && budget > 0) {
        id obj = queue[qi++];
        NSValue *key = [NSValue valueWithPointer:(__bridge void *)obj];
        if ([visited containsObject:key]) continue;
        [visited addObject:key];
        NSString *myPath = paths[key] ?: @"?";
        if (compCls != Nil && [obj isKindOfClass:compCls] && *outComp == nil && obj != seedVC) {
            *outComp = obj;
            *outRoute = myPath;
        }
        if ([NSStringFromClass([obj class]) isEqualToString:@"WXSDKInstance"] && *outInstance == nil) {
            *outInstance = obj;
        }
        // From an instance/manager, a direct rootComponent read wins.
        if (*outComp == nil &&
            ([NSStringFromClass([obj class]) containsString:@"WXSDKInstance"] ||
             [NSStringFromClass([obj class]) containsString:@"ComponentManager"])) {
            id rc = TBM(obj, "rootComponent");
            if (rc != nil && compCls != Nil && [rc isKindOfClass:compCls]) {
                *outComp = rc;
                *outRoute = [myPath stringByAppendingString:@" -[rootComponent]"];
            }
        }
        if (*outComp != nil && *outInstance != nil) break;
        // Expand object-typed ivars only (passive storage, no getters).
        for (NSString *ivName in D4ObjectIvarNames([obj class])) {
            if (budget-- <= 0) break;
            id v = D4GetIvar(obj, [ivName UTF8String]);
            if (v == nil) continue;
            NSValue *vk = [NSValue valueWithPointer:(__bridge void *)v];
            if ([visited containsObject:vk] || paths[vk] != nil) continue;
            // Do not wander into view/controller graphs from here —
            // the canvas subtree is handled by the UIKit dump.
            NSString *vcn = NSStringFromClass([v class]);
            if ([vcn isEqualToString:@"WXRootView"]) continue;
            [queue addObject:v];
            paths[vk] = [NSString stringWithFormat:@"%@ -ivar:%@→ %@", myPath, ivName, vcn];
            if (compCls != Nil && [v isKindOfClass:compCls] && *outComp == nil) {
                *outComp = v;
                *outRoute = paths[vk];
            }
            if ([vcn isEqualToString:@"WXSDKInstance"] && *outInstance == nil) *outInstance = v;
        }
    }
}

// Recursive component walk: 3-layer skeleton + clue-based target
// location (banner by 超级88 containment, recommend by type/ref/attr).
static void D4WalkComponents(id comp, NSString *path, int depth, int *budget,
                             NSMutableString *skeleton, NSMutableArray *targets) {
    if (comp == nil || *budget <= 0) return;
    (*budget)--;
    @try {
        NSString *type = D4CompType(comp);
        NSString *ref = D4CompRef(comp);
        NSString *myPath = [path length] ? [path stringByAppendingFormat:@">%@", type] : type;
        if (depth <= 3 && [skeleton length] < 2600) {
            for (int i = 0; i < depth; i++) [skeleton appendString:@" "];
            [skeleton appendFormat:@"%@(ref=%@)%@\n", type, ref,
             depth == 0 ? [NSString stringWithFormat:@" 类=%@", D4Cls(comp)] : @""];
        }
        // Clue checks (bounded, once per node).
        NSString *keys = nil;
        NSString *blob = D4CompAttrBlob(comp, &keys);
        BOOL bannerAttr = [blob rangeOfString:@"超级88"].location != NSNotFound ||
                          [blob rangeOfString:@"icart_top_banner"].location != NSNotFound ||
                          [blob rangeOfString:@"topAdBanner"].location != NSNotFound;
        BOOL bannerView = NO;
        if (!bannerAttr) {
            id lv = D4CompLoadedView(comp);
            if (lv != nil) {
                int b = 900;
                NSMutableArray *hits = [NSMutableArray array];
                D4FindTextLeaves(lv, @[@"超级88"], 0, &b, hits, 1);
                bannerView = [hits count] > 0;
            }
        }
        NSString *lowType = [type lowercaseString];
        NSString *lowRef = [ref lowercaseString];
        BOOL recLike = [lowType rangeOfString:@"feed"].location != NSNotFound ||
                       [lowType rangeOfString:@"recommend"].location != NSNotFound ||
                       [lowType rangeOfString:@"banner"].location != NSNotFound ||
                       [lowRef rangeOfString:@"feed"].location != NSNotFound ||
                       [lowRef rangeOfString:@"recommend"].location != NSNotFound ||
                       [blob rangeOfString:@"recommend_cart"].location != NSNotFound;
        if (bannerAttr || bannerView) {
            // Every ancestor of the banner view also "contains" it;
            // cap the banner lines so the leaf-most entries survive
            // (DFS reaches ancestors first, so keep the cap generous
            // and rely on the file copy for the full chain).
            NSUInteger nb = 0;
            for (NSString *t in targets) if ([t hasPrefix:@"⑦路径:"]) nb++;
            if (nb < 10) {
                [targets addObject:[NSString stringWithFormat:@"⑦路径:%@ 类=%@ ref=%@ 命中=%@ attr键=[%@]",
                    myPath, D4Cls(comp), ref, bannerAttr ? @"attr" : @"view", keys ?: @""]];
            }
        } else if (recLike && [targets count] < 16) {
            [targets addObject:[NSString stringWithFormat:@"荐候选:%@ 类=%@ ref=%@ attr键=[%@]",
                myPath, D4Cls(comp), ref,
                keys != nil && [keys length] > 90 ? [[keys substringToIndex:90] stringByAppendingString:@"…"] : (keys ?: @"")]];
        }
        NSString *used = nil;
        NSArray *kids = D4CompChildren(comp, &used);
        for (id k in kids) {
            D4WalkComponents(k, myPath, depth + 1, budget, skeleton, targets);
            if (*budget <= 0) return;
        }
    } @catch (NSException *e) { }
}

static NSString *D4DumpCart(id vc, id visibleVC) {
    NSMutableString *s = [NSMutableString string];
    @try {
        id rootView = TBM(vc, "view");
        [s appendFormat:@"VC=%@ 可见VC=%@\n", D4Cls(vc), D4Cls(visibleVC)];
        NSArray *children = D4Subviews(rootView);
        [s appendFormat:@"UIKit根直子×%lu:\n", (unsigned long)[children count]];
        NSUInteger ci = 0;
        for (id ch in children) {
            [s appendFormat:@" %lu %@ %@\n", (unsigned long)ci++, D4Cls(ch), D4FrameStr(ch)];
            if (ci >= 20) { [s appendString:@" …(截断)\n"]; break; }
        }
        int budget = 5000;
        id canvas = D4FindClass(rootView, @"WXRootView", 0, &budget);
        if (canvas == nil) {
            // Fallback: any class whose name contains "RootView" + Weex.
            int b2 = 5000;
            NSMutableArray *cands = [NSMutableArray array];
            D4FindAllClass(rootView, [NSSet setWithObjects:@"WXRootView", nil], 0, &b2, cands, 1);
            canvas = [cands firstObject];
        }
        [s appendFormat:@"Weex画布:%@\n", canvas ? [NSString stringWithFormat:@"%@ %@", D4Cls(canvas), D4FrameStr(canvas)] : @"未找到WXRootView"];
        // VC ivar names are recorded in every case — on failure they
        // are formal8's map to the right accessor.
        [s appendFormat:@"VC对象ivar:[%@]\n",
         [D4ObjectIvarNames([vc class]) componentsJoinedByString:@","]];
        id comp = nil, instance = nil;
        NSString *route = nil;
        D4HuntWeex(vc, canvas, &comp, &instance, &route);
        [s appendFormat:@"实例:%@ 路径:%@\n",
         instance ? D4Cls(instance) : @"未找到", route ?: @"-"];
        if (comp == nil) {
            [s appendString:@"组件树:未拿到(内省路径已试:种子选择器+ivar图遍历)\n"];
            if (canvas != nil) {
                [s appendFormat:@"画布对象ivar:[%@]\n",
                 [D4ObjectIvarNames([canvas class]) componentsJoinedByString:@","]];
            }
            if (instance != nil) {
                [s appendFormat:@"实例属性:[%@]\n", D4PropertyOutline([instance class])];
                [s appendFormat:@"实例ivar:[%@]\n",
                 [D4ObjectIvarNames([instance class]) componentsJoinedByString:@","]];
            }
            return s;
        }
        NSString *usedSel = nil;
        NSArray *rootKids = D4CompChildren(comp, &usedSel);
        (void)rootKids;
        NSString *rootKeys = nil;
        (void)D4CompAttrBlob(comp, &rootKeys);
        [s appendFormat:@"根组件:类=%@ type=%@ ref=%@ 子访问器=%@ attr键=[%@]\n",
         D4Cls(comp), D4CompType(comp), D4CompRef(comp), usedSel ?: @"?",
         rootKeys != nil && [rootKeys length] > 120 ? [[rootKeys substringToIndex:120] stringByAppendingString:@"…"] : (rootKeys ?: @"")];
        [s appendFormat:@"根组件属性:[%@]\n", D4PropertyOutline([comp class])];
        NSMutableString *skeleton = [NSMutableString string];
        NSMutableArray *targets = [NSMutableArray array];
        int wbudget = 420;
        D4WalkComponents(comp, @"", 0, &wbudget, skeleton, targets);
        // Targets first: the alert page is truncated at ~1900 chars and
        // the component paths are the key identity formal8 needs.
        if ([targets count]) {
            [s appendString:@"定位结果:\n"];
            for (NSString *t in targets) [s appendFormat:@" %@\n", t];
        } else {
            [s appendString:@"定位结果:⑦/推荐候选均未命中(见组件树与attr键)\n"];
        }
        [s appendString:@"组件树(根3层):\n"];
        [s appendString:skeleton];
    } @catch (NSException *e) {
        [s appendFormat:@"(dump异常:%@)\n", [e name]];
    }
    return s;
}

// ========================================================== V3: search ====
// WHITELIST enumeration (user 2026-11-14 17:30): the landing page
// keeps ONLY the history section; every other section is a removal
// target for formal8. So this dump enumerates EVERY section of every
// scroll container on the door VC — index, header class, header text,
// first-cell class, row count — and classifies each: history text ->
//; anything else ->, plus
// when it is neither of the two known targets. (The search box and
// the scan/voice/image tool row are functional UI, not sections.)
static NSString *D4SectionVerdict(NSString *headerText) {
if (headerText == nil || [headerText length] == 0) return @"";
if ([headerText rangeOfString:@"历史"].location!= NSNotFound) return @"";
NSString *v = @"";
if ([headerText rangeOfString:@"猜你想搜"].location == NSNotFound &&
[headerText rangeOfString:@"淘宝热榜"].location == NSNotFound) {
v = [v stringByAppendingString:@""];
}
return v;
}

static NSString *D4HeaderText(id headerView) {
if (headerView == nil) return @"";
int budget = 500;
NSMutableArray *texts = [NSMutableArray array];
D4CollectTexts(headerView, 0, &budget, texts, 6);
NSMutableArray *plain = [NSMutableArray array];
for (NSString *t in texts) {
// strip the leading "Class「" and trailing "」" added by the
// collector — for section lines the raw text reads better.
NSString *p = t;
NSRange open = [p rangeOfString:@"「"];
NSRange close = [p rangeOfString:@"」" options:NSBackwardsSearch];
if (open.location!= NSNotFound && close.location!= NSNotFound &&
close.location > open.location) {
p = [p substringWithRange:NSMakeRange(open.location + 1, close.location - open.location - 1)];
}
[plain addObject:p];
}
return [plain componentsJoinedByString:@"/"];
}

static id D4IndexPath(long item, long section) {
Class ipCls = objc_getClass("NSIndexPath");
if (ipCls == Nil) return nil;
SEL sel = NSSelectorFromString(@"indexPathForItem:inSection:");
if (![ipCls respondsToSelector:sel]) return nil;
return ((id (*)(id, SEL, long, long))objc_msgSend)(ipCls, sel, item, section);
}

// Enumerate one UICollectionView: returns lines + tallies via out args.
static void D4EnumCollection(id cv, NSMutableString *s, int *nHist, int *nDrop, int *nUnknown) {
long long sections = 0;
if (!D4GetInt(cv, "numberOfSections", &sections)) {
[s appendString:@" numberOfSections 读不到\n"];
return;
}
if (sections > 30) sections = 30;
id ds = TBM(cv, "dataSource");
for (long long sec = 0; sec < sections; sec++) {
long long items = -1;
SEL nItemsSel = NSSelectorFromString(@"numberOfItemsInSection:");
if ([cv respondsToSelector:nItemsSel]) {
items = ((long long (*)(id, SEL, long long))objc_msgSend)(cv, nItemsSel, sec);
}
// Header: dataSource-created view first (works offscreen),
// then the collection view's own materialized view.
id header = nil;
id ipath = D4IndexPath(0, sec);
if (ds!= nil && ipath!= nil) {
SEL dsSel = NSSelectorFromString(@"collectionView:viewForSupplementaryElementOfKind:atIndexPath:");
if ([ds respondsToSelector:dsSel]) {
@try {
header = ((id (*)(id, SEL, id, id, id))objc_msgSend)(ds, dsSel, cv,
@"UICollectionElementKindSectionHeader", ipath);
} @catch (NSException *e) { header = nil;}
}
}
if (header == nil && ipath!= nil) {
SEL svSel = NSSelectorFromString(@"supplementaryViewForElementKind:atIndexPath:");
if ([cv respondsToSelector:svSel]) {
@try {
header = ((id (*)(id, SEL, id, id))objc_msgSend)(cv, svSel,
@"UICollectionElementKindSectionHeader", ipath);
} @catch (NSException *e) { header = nil;}
}
}
NSString *htext = D4HeaderText(header);
NSString *verdict = D4SectionVerdict(htext);
if ([verdict containsString:@"保留"]) (*nHist)++;
else if ([verdict containsString:@"去除目标"]) {
(*nDrop)++;
if ([verdict containsString:@"未知段"]) (*nUnknown)++;
}
id cell0 = nil;
if (ipath!= nil) {
SEL cSel = NSSelectorFromString(@"cellForItemAtIndexPath:");
if ([cv respondsToSelector:cSel]) {
@try { cell0 = ((id (*)(id, SEL, id))objc_msgSend)(cv, cSel, ipath);}
@catch (NSException *e) { cell0 = nil;}
}
}
[s appendFormat:@" #%lld rows=%lld header=%@ 文本「%@」 cell0=%@ %@\n",
sec, items,
header? D4Cls(header): @"未物化",
[htext length]? htext: @"",
cell0? D4Cls(cell0): @"未物化",
verdict];
}
}

static void D4EnumTable(id tv, NSMutableString *s, int *nHist, int *nDrop, int *nUnknown) {
long long sections = 0;
if (!D4GetInt(tv, "numberOfSections", &sections)) {
[s appendString:@" numberOfSections 读不到\n"];
return;
}
if (sections > 30) sections = 30;
id delegate = TBM(tv, "delegate");
for (long long sec = 0; sec < sections; sec++) {
long long rows = -1;
SEL nrSel = NSSelectorFromString(@"numberOfRowsInSection:");
if ([tv respondsToSelector:nrSel]) {
rows = ((long long (*)(id, SEL, long long))objc_msgSend)(tv, nrSel, sec);
}
id header = nil;
if (delegate!= nil) {
SEL dSel = NSSelectorFromString(@"tableView:viewForHeaderInSection:");
if ([delegate respondsToSelector:dSel]) {
@try {
header = ((id (*)(id, SEL, id, long long))objc_msgSend)(delegate, dSel, tv, sec);
} @catch (NSException *e) { header = nil;}
}
}
NSString *htext = D4HeaderText(header);
NSString *verdict = D4SectionVerdict(htext);
if ([verdict containsString:@"保留"]) (*nHist)++;
else if ([verdict containsString:@"去除目标"]) {
(*nDrop)++;
if ([verdict containsString:@"未知段"]) (*nUnknown)++;
}
id cell0 = nil;
id ipath = nil;
Class ipCls = objc_getClass("NSIndexPath");
if (ipCls!= Nil) {
SEL ipSel = NSSelectorFromString(@"indexPathForRow:inSection:");
if ([ipCls respondsToSelector:ipSel]) {
ipath = ((id (*)(id, SEL, long, long))objc_msgSend)(ipCls, ipSel, 0, sec);
}
}
if (ipath!= nil) {
SEL cSel = NSSelectorFromString(@"cellForRowAtIndexPath:");
if ([tv respondsToSelector:cSel]) {
@try { cell0 = ((id (*)(id, SEL, id))objc_msgSend)(tv, cSel, ipath);}
@catch (NSException *e) { cell0 = nil;}
}
}
[s appendFormat:@" #%lld rows=%lld header=%@ 文本「%@」 cell0=%@ %@\n",
sec, rows,
header? D4Cls(header): @"未物化",
[htext length]? htext: @"",
cell0? D4Cls(cell0): @"未物化",
verdict];
}
}

// Bounded skeleton dump for the non-list (Swift/Muise) fallback.
static void D4Skeleton(id v, int depth, int *budget, NSMutableString *s) {
if (v == nil || depth > 4 || *budget <= 0 || [s length] > 2400) return;
(*budget)--;
@try {
for (int i = 0; i < depth; i++) [s appendString:@" "];
NSString *t = D4ViewText(v);
[s appendFormat:@"%@ %@%@\n", D4Cls(v), D4FrameStr(v),
t? [NSString stringWithFormat:@"「%@」", [t length] > 24? [[t substringToIndex:24] stringByAppendingString:@"…"]: t]: @""];
for (id sub in D4Subviews(v)) {
D4Skeleton(sub, depth + 1, budget, s);
if (*budget <= 0 || [s length] > 2400) return;
}
} @catch (NSException *e) {}
}

static NSString *D4DumpSearch(id vc) {
NSMutableString *s = [NSMutableString string];
@try {
id rootView = TBM(vc, "view");
[s appendFormat:@"VC=%@\n", D4Cls(vc)];
Class cvCls = objc_getClass("UICollectionView");
Class tvCls = objc_getClass("UITableView");
NSMutableArray *containers = [NSMutableArray array];
int budget = 6000;
// Collect scroll containers in tree order (bounded DFS inline).
NSMutableArray *stack = [NSMutableArray arrayWithObject:rootView];
while ([stack count] && budget > 0) {
id cur = [stack lastObject]; [stack removeLastObject];
budget--;
@try {
BOOL isCV = cvCls!= Nil && [cur isKindOfClass:cvCls];
BOOL isTV = tvCls!= Nil && [cur isKindOfClass:tvCls];
if ((isCV || isTV) && ![containers containsObject:cur]) {
[containers addObject:cur];
if ([containers count] >= 3) break;
continue; // do not descend into a found container
}
NSArray *subs = D4Subviews(cur);
for (NSUInteger i = [subs count]; i-- > 0;) [stack addObject:subs[i]];
} @catch (NSException *e) {}
}
int nHist = 0, nDrop = 0, nUnknown = 0;
if ([containers count] == 0) {
[s appendString:@"列表容器:未找到 UICollectionView/UITableView(疑 Swift/Muise 门)\n"];
int b1 = 3000;
NSMutableArray *hosting = [NSMutableArray array];
D4FindAllClass(rootView, [NSSet setWithObject:@"UIHostingView"], 0, &b1, hosting, 1);
// UIHostingView is generic; also scan by name fragment.
[s appendFormat:@"UIHostingView:%@\n", [hosting count]? @"有": @"未检出(按类名精确匹配)"];
Class svCls = objc_getClass("UIScrollView");
id scroll = nil;
int b2 = 4000;
if (svCls!= Nil) {
// first UIScrollView in tree order
NSMutableArray *stack2 = [NSMutableArray arrayWithObject:rootView];
while ([stack2 count] && b2 > 0 && scroll == nil) {
id cur = [stack2 lastObject]; [stack2 removeLastObject];
b2--;
if ([cur isKindOfClass:svCls]) { scroll = cur; break;}
NSArray *subs = D4Subviews(cur);
for (NSUInteger i = [subs count]; i-- > 0;) [stack2 addObject:subs[i]];
}
}
if (scroll!= nil) {
[s appendFormat:@"滚动视图:%@ %@\n结构骨架:\n", D4Cls(scroll), D4FrameStr(scroll)];
int b3 = 90;
D4Skeleton(scroll, 0, &b3, s);
} else {
[s appendString:@"滚动视图:未找到\n"];
}
int b4 = 5000;
NSMutableArray *texts = [NSMutableArray array];
D4CollectTexts(rootView, 0, &b4, texts, 50);
[s appendFormat:@"页面文本序:[%@]\n", [texts componentsJoinedByString:@" | "]];
return s;
}
NSUInteger ci = 0;
for (id c in containers) {
[s appendFormat:@"容器%lu:%@ %@\n", (unsigned long)ci++, D4Cls(c), D4FrameStr(c)];
if (cvCls!= Nil && [c isKindOfClass:cvCls]) D4EnumCollection(c, s, &nHist, &nDrop, &nUnknown);
else D4EnumTable(c, s, &nHist, &nDrop, &nUnknown);
}
[s appendFormat:@"汇总:历史×%d 去除目标×%d 其中未知段×%d\n", nHist, nDrop, nUnknown];
} @catch (NSException *e) {
[s appendFormat:@"(dump异常:%@)\n", [e name]];
}
return s;
}

// ------------------------------------------------------------ output -----
static NSString *D4Overview(void) {
    NSMutableString *s = [NSMutableString string];
    @synchronized (gD4Lock) {
        [s appendFormat:@"TBDiag4.1 · 运行%.0fs · 基线=正式版7过滤(只读视图探针)\n", D4Now()];
        [s appendFormat:@"[首页横条] %@\n", gD4DumpedHome ? @"已dump" : @"待触发(停在首页)"] ;
        [s appendFormat:@"[购物车] %@\n", gD4DumpedCart ? @"已dump" : @"待触发(停在购物车)"] ;
        [s appendFormat:@"[搜索] %@\n", gD4DumpedSearch ? @"已dump" : @"待触发(停在搜索落地页,不输词)"] ;
        [s appendString:@"每面dump后自动补弹该面页,逐页截图即可。\n"];
        NSUInteger from = [gD4Events count] > 5 ? [gD4Events count] - 5 : 0;
        for (NSUInteger i = from; i < [gD4Events count]; i++) {
            [s appendFormat:@"%@\n", gD4Events[i]];
        }
    }
    return s;
}

static void D4WriteFile(void) {
    @try {
        NSString *dir = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        if (dir == nil) return;
        NSMutableString *out = [NSMutableString string];
        [out appendString:D4Overview()];
        @synchronized (gD4Lock) {
            for (NSString *part in gD4FileParts) [out appendFormat:@"\n==== %@\n", part];
            [out appendString:@"\n--- events ---\n"];
            for (NSString *e in gD4Events) [out appendFormat:@"%@\n", e];
        }
        [out writeToFile:[dir stringByAppendingPathComponent:@"TBDiag4.txt"]
              atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) { }
}

static void D4StoreDump(NSString *pageKey, NSString *text) {
    @synchronized (gD4Lock) {
        if ([pageKey isEqualToString:@"首页"]) gD4PageHome = [text copy];
        else if ([pageKey isEqualToString:@"购物车"]) gD4PageCart = [text copy];
        else if ([pageKey isEqualToString:@"搜索"]) gD4PageSearch = [text copy];
        [gD4FileParts addObject:[NSString stringWithFormat:@"[+%.0fs] %@\n%@", D4Now(), pageKey, text]];
        while ([gD4FileParts count] > 8) [gD4FileParts removeObjectAtIndex:0];
        [gD4PendingPages removeObject:pageKey];
        [gD4PendingPages addObject:pageKey];
    }
    D4Event(@"dump完成:%@", pageKey);
    D4WriteFile();
}

// -------------------------------------------------------- presentation -----
static NSString *D4PageText(NSString *key) {
    NSString *t = nil;
    @synchronized (gD4Lock) {
        if ([key isEqualToString:@"首页"]) t = gD4PageHome;
        else if ([key isEqualToString:@"购物车"]) t = gD4PageCart;
        else if ([key isEqualToString:@"搜索"]) t = gD4PageSearch;
    }
    if ([key isEqualToString:@"总览"] || t == nil) t = D4Overview();
    if ([t length] > 1900) t = [t substringToIndex:1900];
    return t;
}

// 4.1: is the screen already occupied by a presentation? YES when
// anything is presented above the visible page's own lineage (an
// alert, a sheet, or our own previous diag alert — which is what
// keeps the three face pages strictly serial, one at a time), or
// when an Alert-class VC is presented in ANY window (system prompts
// live in their own window). The lineage itself is exempt: a page
// that was presented modally (e.g. a presented search door) does not
// count as occupied merely for being presented.
static BOOL D4ModalBusy(id top) {
    @try {
        id child = nil;
        id node = top;
        for (int g = 0; g < 12 && node != nil; g++) {
            id p = TBM(node, "presentedViewController");
            if (p != nil && p != child) return YES;
            child = node;
            node = TBM(node, "parentViewController");
        }
        Class appCls = objc_getClass("UIApplication");
        if (appCls != Nil) {
            id app = ((id (*)(id, SEL))objc_msgSend)(appCls, NSSelectorFromString(@"sharedApplication"));
            NSArray *windows = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"windows"));
            for (id w in windows) {
                id cur = TBM(w, "rootViewController");
                for (int g = 0; g < 12 && cur != nil; g++) {
                    if ([NSStringFromClass([cur class]) containsString:@"Alert"]) return YES;
                    cur = TBM(cur, "presentedViewController");
                }
            }
        }
    } @catch (NSException *e) { }
    return NO;
}

static BOOL D4TryShow(void) {
    NSString *key = nil;
    @synchronized (gD4Lock) {
        if ([gD4PendingPages count] == 0) return NO;
        if (D4Now() < 120.0) return NO; // 4.1 startup grace: never pop
        if (gD4Shows > 0 && (D4Now() - gD4LastShowAt) < 25.0) return NO;
        if (gD4Shows >= 16) return NO;
        key = [gD4PendingPages firstObject];
    }
    id top = D4TopVC(NULL);
    if (top == nil) return NO;
    if ([NSStringFromClass([top class]) containsString:@"Alert"]) return NO;
    if (D4ModalBusy(top)) return NO; // 4.1: queue behind any live modal
    id view = TBM(top, "view");
    id win = view ? TBM(view, "window") : nil;
    if (win == nil) return NO;
    Class acCls = objc_getClass("UIAlertController");
    Class aaCls = objc_getClass("UIAlertAction");
    if (acCls == Nil || aaCls == Nil) return NO;
    NSString *title = [key isEqualToString:@"总览"] ? @"诊断4"
        : [NSString stringWithFormat:@"诊断4·%@", key];
    id ac = ((id (*)(id, SEL, id, id, long))objc_msgSend)(acCls,
        NSSelectorFromString(@"alertControllerWithTitle:message:preferredStyle:"),
        title, D4PageText(key), 1L);
    id ok = ((id (*)(id, SEL, id, long, id))objc_msgSend)(aaCls,
        NSSelectorFromString(@"actionWithTitle:style:handler:"), @"知道了", 0L, nil);
    ((void (*)(id, SEL, id))objc_msgSend)(ac, NSSelectorFromString(@"addAction:"), ok);
    ((void (*)(id, SEL, id, char, id))objc_msgSend)(top,
        NSSelectorFromString(@"presentViewController:animated:completion:"), ac, 1, nil);
    @synchronized (gD4Lock) {
        [gD4PendingPages removeObject:key];
        gD4Shows++;
    }
    gD4LastShowAt = D4Now();
    return YES;
}

static void D4PresentTick(int tick) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        if (!D4TryShow()) D4WriteFile();
        if (tick < 260) D4PresentTick(tick + 1);
    });
}

// ------------------------------------------------------------- watcher -----
static const int D4K_NONE = 0, D4K_HOME = 1, D4K_CART = 2, D4K_SEARCH = 3;
static id gD4LastRoot = nil;
static int gD4CachedKind = 0;

static int D4Classify(id rootVC, id visibleVC) {
    if (visibleVC != nil &&
        [NSStringFromClass([visibleVC class]) containsString:@"SearchDoor"]) {
        return D4K_SEARCH;
    }
    Class homeCls = objc_getClass("TBHomeViewController");
    if (rootVC != nil && homeCls != Nil && [rootVC isKindOfClass:homeCls]) {
        return D4K_HOME;
    }
    if (rootVC == nil) return D4K_NONE;
    if (rootVC == gD4LastRoot) return gD4CachedKind;
    // Cart test (bounded): Weex canvas + 购物车 text in the tab root.
    int kind = D4K_NONE;
    @try {
        id rv = TBM(rootVC, "view");
        if (rv != nil) {
            int b1 = 2600;
            id canvas = D4FindClass(rv, @"WXRootView", 0, &b1);
            if (canvas != nil) {
                int b2 = 2600;
                NSMutableArray *hits = [NSMutableArray array];
                D4FindTextLeaves(rv, @[@"购物车"], 0, &b2, hits, 1);
                if ([hits count]) kind = D4K_CART;
            }
        }
    } @catch (NSException *e) { }
    gD4LastRoot = rootVC;
    gD4CachedKind = kind;
    return kind;
}

static void D4WatchTick(int tick) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), ^{
        @try {
            if (D4Now() < 120.0) {
                // 4.1 startup grace: probe fully disarmed for the
                // first 120s — no classification, no dumps, no
                // popups (fresh-install login/guide flow runs first).
            } else {
            id rootVC = nil;
            id visibleVC = D4TopVC(&rootVC);
            int kind = D4Classify(rootVC, visibleVC);
            double now = D4Now();
            if (kind != gD4CurKind) {
                gD4CurKind = kind;
                gD4KindSince = now;
                gD4AbsentTicks = 0;
            } else if (kind == D4K_NONE) {
                gD4AbsentTicks++;
            }
            // 4.1: NO re-arm — each face dumps at most once per
            // process; leaving a page never resets a completed dump.
            // The dwell is CONTINUOUS: any kind change above resets
            // gD4KindSince, so an interrupted stay restarts at zero.
            double stayed = now - gD4KindSince;
            if (kind == D4K_HOME && !gD4DumpedHome && stayed >= 8.0 && rootVC != nil) {
                gD4DumpedHome = YES;
                D4StoreDump(@"首页", D4DumpHome(rootVC));
            } else if (kind == D4K_CART && !gD4DumpedCart && stayed >= 8.0 && rootVC != nil) {
                gD4DumpedCart = YES;
                D4StoreDump(@"购物车", D4DumpCart(rootVC, visibleVC));
            } else if (kind == D4K_SEARCH && !gD4DumpedSearch && stayed >= 8.0 && visibleVC != nil) {
                gD4DumpedSearch = YES;
                D4StoreDump(@"搜索", D4DumpSearch(visibleVC));
            }
            }
        } @catch (NSException *e) { }
        if (tick < 1500) D4WatchTick(tick + 1);
    });
}

static void TD4Start(void) {
    @autoreleasepool {
        gD4Start = [NSDate date];
        gD4Lock = [[NSObject alloc] init];
        gD4Events = [NSMutableArray array];
        gD4FileParts = [NSMutableArray array];
        gD4PendingPages = [NSMutableArray array];
        // 4.1: NO overview page is seeded — nothing pops at cold
        // start; the overview text lives only as the header of
        // Documents/TBDiag4.txt (written by D4WriteFile).
        D4Event(@"TBDiag4.1 启动(基线正式版7, 只读视图探针; 宽限120s/驻留8s/每面一次)");
        D4WatchTick(0);
        D4PresentTick(0);
    }
}
