// DCDCrashGuard — anti-crash guard for Dongchedi (AutoMobile) on iOS 27.3 beta.
//
// Crash (ips 2026-11-04): ~0.4s after launch, SDK init code running on a
// background dispatch queue calls -[UIStatusBarManager statusBarFrame].
// That call flushes pending status-bar appearance updates into an FBSScene
// client-settings update, and BoardServices traps in
// -[BSServiceMainRunLoopQueue assertBarrierOnQueue] (EXC_BREAKPOINT).
// The pristine app hits the same trap intermittently on this beta.
//
// Guard: swizzle the two UIStatusBarManager entry points of that chain.
//   - On the main thread: call the original implementation and cache the
//     returned values (behavior identical to stock).
//   - Off the main thread: return the cached values WITHOUT entering
//     UIKit's scene-update path at all, so the assertion can never trip.
// Fail-open: any setup failure leaves the stock implementations untouched.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// UIStatusBarManager is declared in the public UIKit headers; the category
// below attaches to the real class at runtime.

static CGRect gFrame;
static BOOL gFrameValid = NO;
static BOOL gHidden = NO;
static BOOL gHiddenValid = NO;

@implementation UIStatusBarManager (DCDCrashGuard)

- (CGRect)dcd_statusBarFrame {
    if ([NSThread isMainThread]) {
        CGRect r = [self dcd_statusBarFrame]; // original after exchange
        gFrame = r;
        gFrameValid = YES;
        return r;
    }
    if (gFrameValid) return gFrame;
    // Cold default before any main-thread call cached the real frame:
    // full-width, standard status-bar height. Advisory metrics only.
    CGFloat w = [UIScreen mainScreen].bounds.size.width;
    return CGRectMake(0, 0, w, 54.0);
}

- (BOOL)dcd_isStatusBarHidden {
    if ([NSThread isMainThread]) {
        BOOL b = [self dcd_isStatusBarHidden]; // original after exchange
        gHidden = b;
        gHiddenValid = YES;
        return b;
    }
    return gHiddenValid ? gHidden : NO;
}

@end

__attribute__((constructor)) static void DCDCrashGuardInit(void) {
    @try {
        Class c = NSClassFromString(@"UIStatusBarManager");
        if (!c) return;
        Method a = class_getInstanceMethod(c, @selector(statusBarFrame));
        Method b = class_getInstanceMethod(c, @selector(dcd_statusBarFrame));
        if (a && b) method_exchangeImplementations(a, b);
        Method x = class_getInstanceMethod(c, @selector(isStatusBarHidden));
        Method y = class_getInstanceMethod(c, @selector(dcd_isStatusBarHidden));
        if (x && y) method_exchangeImplementations(x, y);
    } @catch (id e) {
        // Fail open: stock behavior.
    }
}

// ============================================================================
// DCDProbe v1 (DIAGNOSTIC BUILD — remove after the search-panel data flow is
// pinned down). Counts calls to candidate setters / assemblers in the search
// panel and logs every DCDSearchPanelSectionModel creation (type + title),
// then copies a summary to the pasteboard so it can be pasted into chat.
// NOTE: the hooked classes are app-private and do not exist at link time, so
// the replacement IMPs live on a dummy class and are grafted onto the real
// classes at runtime with class_addMethod + method_exchangeImplementations.
// ============================================================================

static NSMutableString *gProbeLog;
static NSMutableDictionary *gProbeCounts;

static void ProbeCount(NSString *key) {
    @synchronized (gProbeLog) {
        NSNumber *n = gProbeCounts[key];
        gProbeCounts[key] = @((n ? n.intValue : 0) + 1);
    }
}
static void ProbeEvent(NSString *line) {
    @synchronized (gProbeLog) {
        if (gProbeLog.length < 12000) {
            [gProbeLog appendString:line];
            [gProbeLog appendString:@"\n"];
        }
    }
}
static void ProbeDumpToPasteboard(void) {
    @synchronized (gProbeLog) {
        NSMutableString *out = [NSMutableString stringWithString:@"== DCDProbe v1 ==\n-- counts --\n"];
        for (NSString *k in [gProbeCounts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [out appendFormat:@"%@ = %@\n", k, gProbeCounts[k]];
        }
        [out appendString:@"-- events --\n"];
        [out appendString:gProbeLog];
        [UIPasteboard generalPasteboard].string = out;
    }
}

@interface DCDProbeHooks : NSObject
@end
@implementation DCDProbeHooks
// --- DCDSearchPanelInfosModel hooks ---
- (void)dcdp_setDiscovery_recommends:(id)v { ProbeCount(@"setDiscovery_recommends:"); [self dcdp_setDiscovery_recommends:v]; }
- (id)dcdp_discovery_recommends { ProbeCount(@"getDiscovery_recommends"); return [self dcdp_discovery_recommends]; }
- (void)dcdp_setHot_topic:(id)v { ProbeCount(@"setHot_topic:"); [self dcdp_setHot_topic:v]; }
- (void)dcdp_setRankList:(id)v { ProbeCount(@"setRankList:"); [self dcdp_setRankList:v]; }
- (void)dcdp_setRankNewList:(id)v { ProbeCount(@"setRankNewList:"); [self dcdp_setRankNewList:v]; }
- (void)dcdp_setCarRankList:(id)v { ProbeCount(@"setCarRankList:"); [self dcdp_setCarRankList:v]; }
- (void)dcdp_setHot_series:(id)v { ProbeCount(@"setHot_series:"); [self dcdp_setHot_series:v]; }
- (void)dcdp_setActivityInfo:(id)v { ProbeCount(@"setActivityInfo:"); [self dcdp_setActivityInfo:v]; }
- (void)dcdp_setRollInfos:(id)v { ProbeCount(@"setRollInfos:"); [self dcdp_setRollInfos:v]; }
- (void)dcdp_setSearchHistories:(id)v { ProbeCount(@"setSearchHistories:"); [self dcdp_setSearchHistories:v]; }
// --- DCDSearchPanelSectionModel hook ---
- (id)dcdp_initWithType:(NSUInteger)t title:(id)title datas:(id)datas {
    id r = [self dcdp_initWithType:t title:title datas:datas];
    ProbeCount(@"initWithType");
    ProbeEvent([NSString stringWithFormat:@"initWithType type=%lu title=%@ datas=%lu", (unsigned long)t, title, (unsigned long)[datas count]]);
    return r;
}
// --- DCDSearchPanelViewController hooks ---
- (void)dcdp_setDataList:(id)v {
    [self dcdp_setDataList:v];
    ProbeCount(@"setDataList:");
    NSMutableString *s = [NSMutableString stringWithFormat:@"setDataList count=%lu [", (unsigned long)[v count]];
    for (id sec in v) {
        @try { [s appendFormat:@" (type=%lu,title=%@)", (unsigned long)[sec type], [sec title]]; } @catch (id e) {}
    }
    [s appendString:@" ]"];
    ProbeEvent(s);
}
- (void)dcdp_refreshSearchRankHotList:(id)v { ProbeCount(@"refreshSearchRankHotList:"); [self dcdp_refreshSearchRankHotList:v]; }
- (void)dcdp_reloadHotTopicList:(id)v { ProbeCount(@"reloadHotTopicList:"); [self dcdp_reloadHotTopicList:v]; }
- (void)dcdp_setupCQPanelData { ProbeCount(@"setupCQPanelData"); [self dcdp_setupCQPanelData]; }
- (void)dcdp_initTableViewData { ProbeCount(@"initTableViewData"); [self dcdp_initTableViewData]; }
- (void)dcdp_reloadHistorySection { ProbeCount(@"reloadHistorySection"); [self dcdp_reloadHistorySection]; }
- (void)dcdp_viewDidAppear:(BOOL)a {
    [self dcdp_viewDidAppear:a];
    ProbeCount(@"panelViewDidAppear");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ProbeDumpToPasteboard();
    });
}
@end

static void ProbeHook(NSString *className, SEL orig, SEL repl) {
    Class c = NSClassFromString(className);
    if (!c) return;
    Method dummy = class_getInstanceMethod([DCDProbeHooks class], repl);
    if (!dummy) return;
    if (!class_addMethod(c, repl, method_getImplementation(dummy), method_getTypeEncoding(dummy))) {
        // Method already present under the probe name; still try to exchange.
        if (!class_getInstanceMethod(c, repl)) return;
    }
    Method a = class_getInstanceMethod(c, orig);
    Method b = class_getInstanceMethod(c, repl);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor)) static void DCDProbeInit(void) {
    @try {
        gProbeLog = [[NSMutableString alloc] init];
        gProbeCounts = [[NSMutableDictionary alloc] init];
        NSString *infos = @"DCDSearchPanelInfosModel";
        ProbeHook(infos, @selector(setDiscovery_recommends:), @selector(dcdp_setDiscovery_recommends:));
        ProbeHook(infos, @selector(discovery_recommends), @selector(dcdp_discovery_recommends));
        ProbeHook(infos, @selector(setHot_topic:), @selector(dcdp_setHot_topic:));
        ProbeHook(infos, @selector(setRankList:), @selector(dcdp_setRankList:));
        ProbeHook(infos, @selector(setRankNewList:), @selector(dcdp_setRankNewList:));
        ProbeHook(infos, @selector(setCarRankList:), @selector(dcdp_setCarRankList:));
        ProbeHook(infos, @selector(setHot_series:), @selector(dcdp_setHot_series:));
        ProbeHook(infos, @selector(setActivityInfo:), @selector(dcdp_setActivityInfo:));
        ProbeHook(infos, @selector(setRollInfos:), @selector(dcdp_setRollInfos:));
        ProbeHook(infos, @selector(setSearchHistories:), @selector(dcdp_setSearchHistories:));
        ProbeHook(@"DCDSearchPanelSectionModel", @selector(initWithType:title:datas:), @selector(dcdp_initWithType:title:datas:));
        NSString *vc = @"DCDSearchPanelViewController";
        ProbeHook(vc, @selector(setDataList:), @selector(dcdp_setDataList:));
        ProbeHook(vc, @selector(refreshSearchRankHotList:), @selector(dcdp_refreshSearchRankHotList:));
        ProbeHook(vc, @selector(reloadHotTopicList:), @selector(dcdp_reloadHotTopicList:));
        ProbeHook(vc, @selector(setupCQPanelData), @selector(dcdp_setupCQPanelData));
        ProbeHook(vc, @selector(initTableViewData), @selector(dcdp_initTableViewData));
        ProbeHook(vc, @selector(reloadHistorySection), @selector(dcdp_reloadHistorySection));
        ProbeHook(vc, @selector(viewDidAppear:), @selector(dcdp_viewDidAppear:));
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ProbeDumpToPasteboard();
        });
    } @catch (id e) {
    }
}
