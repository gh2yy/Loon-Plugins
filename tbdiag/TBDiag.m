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
//      emptying for api=mtop.relationrecommend.wirelessrecommend.recommend
//      whose own request params serialize to contain "recommend_cart_main".
//   3. Search landing: same response point, api=mtop.xsd.searchbar.info.get,
//      title-anchored section removal with history positive-identification
//      and whole-response fail-open.
//   4. Home floating bar: TBHRContainerContentModel -floatLayerSection
//      getter forced to nil. The property lives on the container content
//      model (NOT on TBHRGatewayDataService — the v2 probe read the wrong
//      object). Static xref found no direct consumer in the main binary;
//      the getter is the single convergence point of both producers
//      (JSON parse init and cache deepCopy), and the property is a leaf
//      parallel to sections/popDatas/splashSection.
//   5. MyTaobao bottom section: MTMainPageUserDataService
//      -transformMainPageDataMode:snapshotSource: (the C++ -> ObjC
//      conversion point) — drop the components element whose
//      moduleName == "basementTip" (the native second screen holding the
//      feeds/collect/xProject tabs: 猜你喜欢/我的收藏/我的评价 + infoflow).
//      Middle modules (statistic etc.) are separate components, untouched.
//
// Marker: TBClean/1.0
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// ------------------------------------------------------------ utilities ----
static id TBM(id obj, const char *selName) {
    if (obj == nil) return nil;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
static void TBMSet(id obj, const char *selName, id val) {
    if (obj == nil) return;
    SEL sel = NSSelectorFromString([NSString stringWithUTF8String:selName]);
    if (![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, val);
}

// Serialize a params object (dict/array/string mix) to a searchable string.
// Used only for the cart scene substring test; bounded work.
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
    [out appendFormat:@"%@ ", [obj description]];
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
// Single response-side point: -[MtopService getResponse:mrequest:] builds
// the MtopExtResponse that requestFinished: then dispatches to the caller
// delegate (succeed:response:/failed:response:). The response carries its
// own request, so api name + params are read from the response itself;
// no send-side state is kept.
typedef id (*GetRespIMP)(id, SEL, id, id);
static GetRespIMP gOrigGetResp = NULL;

static NSString *TCApiOfResponse(id resp) {
    id req = TBM(resp, "request");
    id n = TBM(req, "getApiName");
    return [n isKindOfClass:[NSString class]] ? n : nil;
}

// ---- cart: empty the recommend payload -------------------------------
static BOOL TCCartMatched(id resp, NSString *api) {
    if (![api isEqualToString:@"mtop.relationrecommend.wirelessrecommend.recommend"]) return NO;
    id req = TBM(resp, "request");
    if (req == nil) return NO;
    NSMutableString *blob = [NSMutableString string];
    @try {
        TCAppendSerialized(TBM(req, "getBizParameters"), blob, 0);
        TCAppendSerialized(TBM(req, "getExtParameters"), blob, 0);
        id pn = TBM(req, "pageName");
        if ([pn isKindOfClass:[NSString class]]) [blob appendString:(NSString *)pn];
    } @catch (NSException *e) { return NO; }
    return [blob rangeOfString:@"recommend_cart_main"].location != NSNotFound;
}

// Replace every array value inside the MTOP `data` payload with an empty
// array (one level into nested dicts as well), keeping all scalar fields
// (ret codes, totals, paging flags) untouched, so the consumer's native
// "empty result" path runs. Returns the new body, or nil to fail open.
static id TCEmptiedBody(id body) {
    if (![body isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *b = TCMutableCopy(body, 0);
    id data = b[@"data"];
    if ([data isKindOfClass:[NSArray class]]) {
        b[@"data"] = [NSMutableArray array];
        return b;
    }
    if (![data isKindOfClass:[NSDictionary class]]) return nil;
    NSMutableDictionary *d = (NSMutableDictionary *)data;
    for (id k in [d allKeys]) {
        id v = d[k];
        if ([v isKindOfClass:[NSArray class]]) {
            d[k] = [NSMutableArray array];
        } else if ([v isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *sub = (NSMutableDictionary *)v;
            for (id k2 in [sub allKeys]) {
                if ([sub[k2] isKindOfClass:[NSArray class]]) sub[k2] = [NSMutableArray array];
            }
        }
    }
    return b;
}

// ---- search landing: title-anchored section removal -------------------
static BOOL TCSubtreeContainsString(id obj, NSString *needle, int depth) {
    if (obj == nil || depth > 4) return NO;
    if ([obj isKindOfClass:[NSString class]]) return [(NSString *)obj isEqualToString:needle];
    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)obj) {
            if ([k isKindOfClass:[NSString class]] && [(NSString *)k isEqualToString:needle]) return YES;
            if (TCSubtreeContainsString(((NSDictionary *)obj)[k], needle, depth + 1)) return YES;
        }
        return NO;
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        for (id e in (NSArray *)obj) if (TCSubtreeContainsString(e, needle, depth + 1)) return YES;
    }
    return NO;
}
static BOOL TCSubtreeContainsAny(id obj, NSArray *needles, int depth) {
    for (NSString *n in needles) if (TCSubtreeContainsString(obj, n, depth)) return YES;
    return NO;
}

// Find every "section container" (array of dicts, or dict of dicts) in the
// payload and confirm the history section is positively identified in at
// least one of them; without that, fail open.
static BOOL TCHistoryPresent(id node, int depth) {
    if (node == nil || depth > 6) return NO;
    if ([node isKindOfClass:[NSArray class]]) {
        BOOL dictArray = NO;
        for (id e in (NSArray *)node) if ([e isKindOfClass:[NSDictionary class]]) { dictArray = YES; break; }
        if (dictArray) {
            for (id e in (NSArray *)node) {
                if (TCSubtreeContainsString(e, @"历史搜索", 0)) return YES;
            }
        }
        for (id e in (NSArray *)node) if (TCHistoryPresent(e, depth + 1)) return YES;
        return NO;
    }
    if ([node isKindOfClass:[NSDictionary class]]) {
        for (id k in (NSDictionary *)node) if (TCHistoryPresent(((NSDictionary *)node)[k], depth + 1)) return YES;
    }
    return NO;
}

static void TCFilterSectionsInNode(id node, int depth) {
    if (node == nil || depth > 6) return;
    if ([node isKindOfClass:[NSMutableArray class]]) {
        NSMutableArray *a = (NSMutableArray *)node;
        BOOL dictArray = NO;
        for (id e in a) if ([e isKindOfClass:[NSDictionary class]]) { dictArray = YES; break; }
        if (dictArray) {
            NSMutableArray *keep = [NSMutableArray arrayWithCapacity:[a count]];
            for (id e in a) {
                BOOL isTarget = TCSubtreeContainsAny(e, @[@"猜你想搜", @"淘宝热榜"], 0);
                BOOL isHistory = TCSubtreeContainsString(e, @"历史搜索", 0);
                if (isTarget && !isHistory) continue;
                [keep addObject:e];
            }
            [a setArray:keep];
        }
        for (id e in a) TCFilterSectionsInNode(e, depth + 1);
        return;
    }
    if ([node isKindOfClass:[NSMutableDictionary class]]) {
        NSMutableDictionary *d = (NSMutableDictionary *)node;
        // dict-of-sections shape: drop values that are target sections.
        for (id k in [d allKeys]) {
            id v = d[k];
            if ([v isKindOfClass:[NSDictionary class]] &&
                TCSubtreeContainsAny(v, @[@"猜你想搜", @"淘宝热榜"], 0) &&
                !TCSubtreeContainsString(v, @"历史搜索", 0)) {
                [d removeObjectForKey:k];
            }
        }
        for (id k in [d allKeys]) TCFilterSectionsInNode(d[k], depth + 1);
    }
}

// Returns filtered body, or nil to fail open (history not identified or
// structure unrecognized).
static id TCFilteredSearchBody(id body) {
    if (![body isKindOfClass:[NSDictionary class]]) return nil;
    id data = ((NSDictionary *)body)[@"data"];
    id scope = data != nil ? data : body;
    if (!TCHistoryPresent(scope, 0)) return nil;
    NSMutableDictionary *b = TCMutableCopy(body, 0);
    id d2 = b[@"data"];
    TCFilterSectionsInNode(d2 != nil ? d2 : b, 0);
    return b;
}

// ---- shared: write a new body back into the response ------------------
static void TCSetBody(id resp, id newBody) {
    @try {
        TBMSet(resp, "setBody:", newBody);
        NSData *jd = [NSJSONSerialization dataWithJSONObject:newBody options:0 error:nil];
        if (jd != nil) {
            NSString *js = [[NSString alloc] initWithData:jd encoding:NSUTF8StringEncoding];
            if (js) TBMSet(resp, "setJson:", js);
            TBMSet(resp, "setRawbody:", jd);
        }
    } @catch (NSException *e) { }
}

static id TCGetResponse(id self, SEL _cmd, id raw, id mreq) {
    id resp = gOrigGetResp ? gOrigGetResp(self, _cmd, raw, mreq) : nil;
    if (resp == nil) return resp;
    @try {
        id ok = TBM(resp, "isSucceed");
        if (ok != nil && [ok respondsToSelector:@selector(boolValue)] && ![ok boolValue]) return resp;
        NSString *api = TCApiOfResponse(resp);
        if (api == nil) return resp;
        if (TCCartMatched(resp, api)) {
            id nb = TCEmptiedBody(TBM(resp, "body"));
            if (nb != nil) TCSetBody(resp, nb);
        } else if ([api isEqualToString:@"mtop.xsd.searchbar.info.get"]) {
            id nb = TCFilteredSearchBody(TBM(resp, "body"));
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

// ===================================================== MyTaobao bottom ====
// MTMainPageUserDataService -transformMainPageDataMode:snapshotSource:
// (IMP 0x1040b699c) is the single C++ -> ObjC conversion point producing
// MTMainPageDataModel; both local-cache and network page data pass it.
// Its `components` array (MTComponentModel, order = layoutList) is the
// page's module list. We remove exactly the element whose
// moduleName == "basementTip" — the native second screen whose
// nativeBasementData.dataList is the three tabs
//   feeds=猜你喜欢 / collect=我的收藏 / xProject=我的评价
// plus the feeds infoflow under the first tab. All other modules
// (header, benefit, statistic, order, game, couponCard) pass untouched;
// the mid-page statistic module is a separate component.
typedef id (*TransformIMP)(id, SEL, id, long long);
static TransformIMP gOrigTransform = NULL;
static id TCTransform(id self, SEL _cmd, id json, long long source) {
    id model = gOrigTransform ? gOrigTransform(self, _cmd, json, source) : nil;
    if (model == nil) return model;
    @try {
        id comps = TBM(model, "components");
        if ([comps isKindOfClass:[NSArray class]] && [(NSArray *)comps count] > 0) {
            NSMutableArray *keep = [NSMutableArray arrayWithCapacity:[(NSArray *)comps count]];
            BOOL removed = NO;
            for (id c in (NSArray *)comps) {
                id mn = TBM(c, "moduleName");
                if ([mn isKindOfClass:[NSString class]] && [(NSString *)mn isEqualToString:@"basementTip"]) {
                    removed = YES;
                    continue;
                }
                [keep addObject:c];
            }
            if (removed) {
                if ([comps isKindOfClass:[NSMutableArray class]]) {
                    [(NSMutableArray *)comps setArray:keep];
                } else {
                    TBMSet(model, "setComponents:", keep);
                }
            }
        }
    } @catch (NSException *e) { }
    return model;
}

static void TCInstallAll(void) {
    TCHook("MtopService", "getResponse:mrequest:", NO, (IMP)TCGetResponse, (IMP *)&gOrigGetResp);
    TCHook("TBPLLayerFactory", "createLayerWithFrame:type:popRequest:attachVC:", NO, (IMP)TCFactoryCreate, (IMP *)&gOrigFactory);
    TCHook("TBHRContainerContentModel", "floatLayerSection", NO, (IMP)TCFloatLayerSection, (IMP *)&gOrigFloatGetter);
    TCHook("MTMainPageUserDataService", "transformMainPageDataMode:snapshotSource:", NO, (IMP)TCTransform, (IMP *)&gOrigTransform);
}

__attribute__((constructor)) static void TCEntry(void) {
    @autoreleasepool {
        TCInstallAll();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
            dispatch_get_main_queue(), ^{ TCInstallAll(); });
    }
}
