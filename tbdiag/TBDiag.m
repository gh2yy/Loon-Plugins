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
// Marker: TBClean/1.5 (formal6)
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
__attribute__((used)) static const char kTCVersion[] = "TBClean/1.5";

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
// built from the dictionary). The original block is retained by the
// wrapper; the wrapper is heap-copied before registration, matching
// the lifetime the C++ listener table expects.
typedef void (*ListenIMP)(id, SEL, id);
static ListenIMP gOrigListenComponents = NULL;

static void TCMyListenComponentsChange(id self, SEL _cmd, id block) {
    id pass = block;
    @try {
        if (block != nil) {
            id origBlock = block;
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

__attribute__((constructor)) static void TCEntry(void) {
    @autoreleasepool {
        TCInstallAll();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ TCInstallAll(); });
    }
}
