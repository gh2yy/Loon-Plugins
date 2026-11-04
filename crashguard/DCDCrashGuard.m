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
