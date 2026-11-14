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
// DCDPanelFilter (permanent): the search panel's section list lives in
// DCDSearchPanelViewController.dataList (verified on device 2026-11-12:
// numberOfSectionsInTableView: returns [dataList count], and the panel
// builds type 0 = history, type 4 = discovery, type 5 = rank sections).
// Data-level patches starve the rank section but the discovery section is
// created unconditionally and its cell is vended fully populated by
// +[DCDSearchPanelDiscoveryRecommends getDiscoverCell:mapInfo:tempInfo:],
// so the reliable choke point is the section list itself: drop type 4/5
// sections whenever the panel is about to appear. Fail-open throughout.
// ============================================================================

@interface DCDPanelFilterHooks : NSObject
- (NSMutableArray *)dataList;
- (void)dcdpf_viewWillAppear:(BOOL)animated;
- (void)dcdpf_viewDidAppear:(BOOL)animated;
@end

static void DCDPanelFilterApply(id vc) {
    @try {
        NSMutableArray *list = [vc dataList];
        if (![list isKindOfClass:[NSMutableArray class]]) return;
        NSMutableIndexSet *drop = [NSMutableIndexSet indexSet];
        NSUInteger i = 0;
        for (id sec in list) {
            @try {
                NSUInteger t = (NSUInteger)[sec type];
                if (t == 4 || t == 5) [drop addIndex:i];
            } @catch (id e) {}
            i++;
        }
        if (drop.count == 0) return;
        [list removeObjectsAtIndexes:drop];
        @try {
            id tv = [vc valueForKey:@"tableView"];
            if ([tv respondsToSelector:@selector(reloadData)]) [tv reloadData];
        } @catch (id e) {}
    } @catch (id e) {}
}

@implementation DCDPanelFilterHooks
- (void)dcdpf_viewWillAppear:(BOOL)animated {
    DCDPanelFilterApply(self);
    [self dcdpf_viewWillAppear:animated];
}
- (void)dcdpf_viewDidAppear:(BOOL)animated {
    [self dcdpf_viewDidAppear:animated];
    DCDPanelFilterApply(self);
}
@end

static void PanelFilterHook(NSString *className, SEL orig, SEL repl) {
    Class c = NSClassFromString(className);
    if (!c) return;
    Method dummy = class_getInstanceMethod([DCDPanelFilterHooks class], repl);
    if (!dummy) return;
    if (!class_addMethod(c, repl, method_getImplementation(dummy), method_getTypeEncoding(dummy))) {
        if (!class_getInstanceMethod(c, repl)) return;
    }
    Method a = class_getInstanceMethod(c, orig);
    Method b = class_getInstanceMethod(c, repl);
    if (a && b) method_exchangeImplementations(a, b);
}

__attribute__((constructor)) static void DCDPanelFilterInit(void) {
    @try {
        PanelFilterHook(@"DCDSearchPanelViewController", @selector(viewWillAppear:), @selector(dcdpf_viewWillAppear:));
        PanelFilterHook(@"DCDSearchPanelViewController", @selector(viewDidAppear:), @selector(dcdpf_viewDidAppear:));
    } @catch (id e) {
    }
}
