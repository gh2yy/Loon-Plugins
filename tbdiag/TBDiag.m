// TBClean — formal ad-filter dylib for Taobao 10.69.0 (com.taobao.taobao4iphone).
//
// No UI, no logging UI, no popups. All filters are process-internal,
// data-side disposals applied AFTER data arrives; nothing blocks, rejects
// or reroutes any request, and no signing / routing / search-result /
// product-detail / order path is touched (ANALYSIS §7.3 red lines).
//
// Modules:
//   1. PopLayer class-wide block: TBPLLayerFactory (variant 1) layer
//      creation re-check by request event uri slot (Page_Home /
//      Page_MyTaobao popup_* modal slots only), returning nil, which the
//      sole caller treats as a native "filtered" cancellation.
//      (queryInventory: turned out to be a freq gate with no candidate
//      set; it is deliberately NOT touched.)
//   2. Cart recommend: MtopService getResponse:mrequest: response-side
//      emptying. Discrimination (V4_A_CART.md): api in the awesome /
//      WirelessRecommend set (case-insensitive) AND the request's full
//      serialized params (biz+ext+pageName+pageUrl+bizID+openBizData)
//      contain the TBRecmd containerId "recommend_cart_main" (or the
//      fresh-cart sibling "recommend_cart_sxc"). Formal3's api name was
//      wrong: wirelessrecommend.recommend belongs to shop-search/TTD,
//      never to the cart; the cart value itself was right but is a
//      containerId key inside the biz params' containerParams JSON.
//   3. Cart top activity banner (target 7): same response point,
//      api=mtop.trade.query.bag (cart body API — the response is only
//      ever pruned, never blocked). The banner card is identified
//      structurally (V4_A_CART.md §7): data field "topAdBanner_1" /
//      DinamicX template "icart_top_banner". Dual anchor: act only if
//      at least one anchor is present, else fail open. Cart body,
//      checkout and the filter/function rows live in other fields and
//      are never touched.
//   4. Search landing sections: NOT at the MTOP point any more.
//      Formal3's api (mtop.xsd.searchbar.info.get) is the hour-delivery
//      home search-box API and never carries SearchDoor data
//      (V4_B_SEARCH.md §1.1, instruction-level). The landing page runs
//      on the XSearch/TPP Activation chain; the filter sits at the
//      exit of TBXSearchActivationTppParser -getProcessedData:, where
//      the section list (itemsArray) is fully assembled and both the
//      network and cache paths converge. Sections whose tItemType is a
//      history type (nt_history / nt_combine_history /
//      nt_multimodal_history) are kept unconditionally — history is
//      identified by type, never by title. Sections whose own "name"
//      contains 猜你想搜 / 淘宝热榜 and whose tItemType is NOT a
//      history type are dropped; everything else passes. Fail-open on
//      any shape mismatch. (The two sections' tItemType values are
//      server-side pass-through constants that never appear literally
//      in the client; the name field is the only client-visible key
//      today — see V4_B_SEARCH.md §2.4 for the probe that would pin
//      the type values.)
//   5. Home floating bar: TBHRContainerContentModel -floatLayerSection
//      getter forced to nil. The property lives on the container content
//      model (NOT on TBHRGatewayDataService — the v2 probe read the wrong
//      object). Static xref found no direct consumer in the main binary;
//      the getter is the single convergence point of both producers
//      (JSON parse init and cache deepCopy), and the property is a leaf
//      parallel to sections/popDatas/splashSection.
//   6. MyTaobao bottom section (basementTip): at the exit of the single
//      component factory +[MTComponentModel creatComponent:componentData:],
//      the built component whose moduleName == "basementTip" gets its
//      containerType rewritten 3 (native) -> 2 (weex) — exactly the
//      downgrade the app's own +disableNativeBasement gate performs at
//      the same point in the same factory, restricted to this one
//      module by name so no other native module can be affected. No
//      element is removed from any list: the component stays in
//      `components` with its moduleName / diffLoadIdentify / order
//      intact, so the C++ diff and every by-name consumer keep finding
//      it; the native basement component is simply never instantiated.
//      Full and incremental models share this one factory (only two
//      selref loads in the binary), so refresh pushes are covered.
//      The formal2 transform-removal route stays CLOSED: V4_C_MY.md
//      disproved its premise (layoutList is a C++-internal JSON key,
//      not an MTMainPageDataModel property; there is no second ObjC
//      list to reconcile) and vetoes element removal outright.
//   7. Tab bar slot 2 (guangguang/video): filter the return value of
//      +[TBAppUIStyle currentTabbarVCItems], the single source from
//      which VCItems / viewControllers / tab items / ItemConfig /
//      attract bizMap are all derived in one init loop (V4_D_TAB.md).
//      The slot is removed only when count==5 and element[1] matches
//      by identity (url == "taobao://guangguang/root" or
//      attractBiz == "tab2"); titles are never matched (the slot's
//      artwork/title/badge rotate via UCP overlays; url/tag/biz/spm
//      never change). Tags of the remaining items are NOT renumbered:
//      routing is positional over the same derived arrays (consistent
//      after source removal) and badges are located by biz string,
//      with tag used only as a bounds gate (2,3 < 4 still passes).
//      Fail-open on any other shape (old/i18n branches).
//
// Marker: TBClean/1.4 (formal5)
// formal5 vs formal4 (1.3): NO filter logic change. The formal4 test
// session's Loon capture (428, 199 records, full inventory in
// work/CAP428_ANALYSIS.md) contains NONE of the four failing surfaces'
// MTOP responses — home container / cart / MyTaobao / search traffic
// rides the xnet/SPDY private channel and never traverses the proxy,
// so the capture cannot supply response shapes and no discrimination
// string was re-guessed. Two candidate miss causes were refuted with
// hard evidence (wlm version drift: every formal4 anchor is byte-
// identical in the cart wlm 1.255.0 the phone actually downloaded in
// that session vs the bundled 1.243.0; response.request readout:
// instruction-level proof that the async path stores the
// MtopExtRequest there and that the api/params getters exist only on
// that class). The remaining unknowns are exactly the ones the
// in-process probe designed in V4_A_CART.md §6 settles; see
// FORMAL_NOTES.md "formal5" section. This build only bumps the
// version marker so the artifact is distinguishable.
// formal4 changes vs formal3 (1.2): module 2 discrimination rewritten
// (API set + containerId, surgical keyed emptying); module 3 added
// (cart top banner); module 4 moved to the TppParser exit with type-key
// history protection; module 6 re-implemented at the component factory
// (no element removal); module 7 added (tab slot 2). Modules 1 and 5
// are unchanged in logic. The old MTOP-point search filter and the
// never-installed transform hook are removed from the source.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// Build identity, verifiable in the compiled artifact (strings).
__attribute__((used)) static const char kTCVersion[] = "TBClean/1.4";

// ------------------------------------------------------------ utilities ----
// WARNING: TBM is ONLY for selectors whose return type is an object (id).
// Passing a primitive-returning selector (BOOL/int/...) makes the msgSend
// result register be read as an object pointer; under ARC that value is
// then retained, which is exactly the formal1 launch crash: -isSucceed
// returns BOOL, TBM(resp,"isSucceed") produced the "pointer" 0x1 and
// objc_retain(0x1) faulted. Primitive getters MUST go through TBMBool /
// TBMInt / a correctly-typed cast instead.
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
// Typed getter/setter for long long-returning selectors (e.g.
// MTComponentModel -containerType / -setContainerType:).
static BOOL TBMInt(id obj, const char *selName, long long *out) {
    if (obj == nil || out == NULL) return NO;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return NO;
    *out = ((long long (*)(id, SEL))objc_msgSend)(obj, sel);
    return YES;
}
static void TBMSetInt(id obj, const char *selName, long long v) {
    if (obj == nil) return;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, long long))objc_msgSend)(obj, sel, v);
}
static void TBMSet(id obj, const char *selName, id val) {
    if (obj == nil) return;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, val);
}

// Serialize a params object (dict/array/string mix) to a searchable string.
// Used only for the cart containerId substring test; bounded work.
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
    // Scalars (NSNumber/NSNull/...) carry no searchable string content,
    // and unknown object types are deliberately NOT sent -description:
    // the substring test runs over genuine string content only, and no
    // arbitrary object's code is invoked on an unvalidated value.
    return;
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
// (IMP 0x1002e1e18; FORMAL_NOTES' earlier 0x1002e1b68 is requestFinished:)
// builds the MtopExtResponse that requestFinished: then dispatches to
// the caller delegate (succeed:response:/failed:response:). The response
// carries its own request, so api name + params are read from the
// response itself; no send-side state is kept.
typedef id (*GetRespIMP)(id, SEL, id, id);
static GetRespIMP gOrigGetResp = NULL;

static NSString *TCApiOfResponse(id resp) {
    id req = TBM(resp, "request");
    id n = TBM(req, "getApiName");
    return [n isKindOfClass:[NSString class]] ? n : nil;
}

// ---- cart recommend -----------------------------------------------------
// API set (V4_A_CART.md §6): the two real cart paths are the native
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

// The containerId must appear in the request's own serialized params.
// Home traffic uses the same awesome APIs but with home containerIds
// (newface_home_sub etc.), so the substring keeps it untouched.
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
// Identity (V4_A_CART.md §7): the banner card inside the query.bag
// HIERARCHY structure — data field "topAdBanner_1", rendered by the
// DinamicX template "icart_top_banner". Copy text / amounts are server
// content and are never used as keys. Checkout, the cart body and the
// JS filter rows (降价/分组/常购/失效) are different nodes/fields and
// are not touched; the API itself is never blocked.
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
//
// Static evidence (see FORMAL_NOTES §1):
// - TBPLInventoryManager queryInventory: is a freq-control GATE returning
//   an NSString failure reason (nil = pass). There is no candidate set to
//   filter; DIAG2's primary point is void. Do NOT touch it.
// - The single funnel for layer creation in the main binary is
//   TBPLLayerFactory -createLayerWithFrame:type:popRequest:attachVC:.
//   Its only real caller (TBPLPageTriggerService -p_onReadyOperation:)
//   explicitly nil-checks the result and cancels cleanly via the native
//   "OnViewCustomFilter" lose path, and the factory itself returns nil by
//   design for unregistered types. Returning nil for matched requests is
//   a native-shaped outcome.
// - Discrimination key: the request's event uri
//   ([popRequest event] -> uri), matched by slot prefix:
//     poplayer://Page_Home@popup_*
//     poplayer://Page_MyTaobao@popup_*
//   popup_guide_float_* is included: its config entries are field-identical
//   to the modal slots (layerType=custom40, type=native, enqueue=true,
//   modalThreshold=0.8); genuine float/resident/guide slots use float_* /
//   resident prefixes and are untouched.
// - Variant 2 (config:targetUrl:) has no caller in the main binary and its
//   event.uri is always nil, so no point is set there.
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
// pristine binary) forced to nil. Static basis (FORMAL_NOTES §4):
// - The property's only static reader is the cache deepCopy (which copies
//   base -> total through this getter); both producers (JSON parse init,
//   deepCopy) pass through this getter/setter pair, so the getter is the
//   single convergence point.
// - The property is a leaf, parallel and independent of sections /
//   popDatas / splashSection; nil is its natural "no floating layer"
//   state. originalData (raw JSON) is stored independently at parse time.
// - No sectionBizCode matching is attempted: the floating layer model
//   carries no statically anchorable identifier, and the whole property
//   exists solely for this floating layer.
typedef id (*FloatGetterIMP)(id, SEL);
static FloatGetterIMP gOrigFloatGetter = NULL;
static id TCFloatLayerSection(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return nil;
}

// ============================================== search landing sections ====
// TBXSearchActivationTppParser -getProcessedData: (IMP 0x104731210)
// exit filter. At this point the raw TPP dict has been assembled into
// the processed dict: top-level "itemsArray" holds the section dicts,
// history sections already carry their locally-filled content, and
// network + cache paths have converged (V4_B_SEARCH.md §1.2/§4.1).
// History protection is by tItemType (a stable client-compared
// constant), NOT by title: the three history types are the only
// tItemType values the client itself ever compares literally.
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
// +[MTComponentModel creatComponent:componentData:] (IMP 0x1040b3b18)
// is the ONLY component factory: its selref has exactly two loads in the
// binary — the transform enumeration block (full page builds) and one
// C++ bridge thunk (incremental diff builds). At its exit we apply, to
// the basementTip component only, the same containerType downgrade the
// app itself performs inside this factory when +disableNativeBasement
// is on (0x1040b3c90: containerType==3 -> read switch -> setContainerType:2):
// the native second screen (MtbNativeBasementComponent, holding the
// feeds/collect/xProject tabs 猜你喜欢/我的收藏/我的评价) is then never
// instantiated, while the component object itself remains in
// `components` at its original position with moduleName and
// diffLoadIdentify unchanged — nothing goes missing for the C++ diff,
// for buildSnapshotData's old/new comparison, or for by-name consumers
// (anchor navigation, ceiling checks). Name-scoping the rewrite means
// any other native-typed module on the page keeps its native type.
// containerType is a long long property: read/written ONLY through the
// typed helpers, never through the id-returning TBM (formal1 lesson).
typedef id (*CreateCompIMP)(id, SEL, id, id);
static CreateCompIMP gOrigCreateComp = NULL;

static id TCCreateComponent(id self, SEL _cmd, id name, id data) {
    id comp = gOrigCreateComp ? gOrigCreateComp(self, _cmd, name, data) : nil;
    if (comp == nil) return comp;
    @try {
        id mn = TBM(comp, "moduleName");
        if ([mn isKindOfClass:[NSString class]] && [(NSString *)mn isEqualToString:@"basementTip"]) {
            long long ct = 0;
            if (TBMInt(comp, "containerType", &ct) && ct == 3) {
                TBMSetInt(comp, "setContainerType:", 2);
            }
        }
    } @catch (NSException *e) { }
    return comp;
}

// ======================================================== tab bar slot ====
// +[TBAppUIStyle currentTabbarVCItems] (IMP 0x10012ba80) is the single
// source of the tab bar's item list: TBMainViewController's init loop
// derives viewControllers, tab items, ItemConfig and the attract bizMap
// from this one array, and revision switches rebuild through it too.
// Removing the guangguang (slot-2) item here shortens every derived
// array together, so positional routing stays consistent; nothing at
// the view layer is touched. Identity (V4_D_TAB.md §2): the item built
// by +guangguangItem carries url "taobao://guangguang/root" and
// attractBiz "tab2" as code literals; UCP rotations only swap its
// image/title/overlay/badge, never these fields. The check is pinned
// to index 1 of a 5-item array and to the TBVCItem class, so other
// branches (new-user uses the same guangguang slot; old/i18n branches
// have different slot-2 items) fail open. Remaining items' tags are
// left as built (0/2/3/4): routing never reads tag, and badge delivery
// locates items by biz string with tag only as a bounds gate.
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
    TCHook("TBPLLayerFactory", "createLayerWithFrame:type:popRequest:attachVC:", NO, (IMP)TCFactoryCreate, (IMP *)&gOrigFactory);
    TCHook("TBHRContainerContentModel", "floatLayerSection", NO, (IMP)TCFloatLayerSection, (IMP *)&gOrigFloatGetter);
    TCHook("TBXSearchActivationTppParser", "getProcessedData:", NO, (IMP)TCGetProcessedData, (IMP *)&gOrigParser);
    TCHook("MTComponentModel", "creatComponent:componentData:", YES, (IMP)TCCreateComponent, (IMP *)&gOrigCreateComp);
    TCHook("TBAppUIStyle", "currentTabbarVCItems", YES, (IMP)TCVCItems, (IMP *)&gOrigVCItems);
}

__attribute__((constructor)) static void TCEntry(void) {
    @autoreleasepool {
        TCInstallAll();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ TCInstallAll(); });
    }
}
