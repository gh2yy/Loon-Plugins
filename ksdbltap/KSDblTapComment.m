// KSDblTapComment — Kuaishou 14.9.10: double-tap on a slide-feed video opens
// the comment panel instead of double-tap-liking.
//
// Hook (verified against the 14.9.10.10022 binary's ObjC metadata):
//   -[KSTabBarGestureLogicComponent slideDetailPageHandleDoubleTapGestureWithLocation:]
// is the slide page's double-tap entry (its original body forwards into the
// like path: postLikeEventWithLocation: + heart effect). We replace it and
// do NOT call the original, so no like is posted.
//
// Comment path (the exact route a tap on the toolbar comment item takes):
//   self.processorManager -> -[KSTangramProcessorManager boardCombinationProcessor]
//   -> -[KSTabbarBoardCombination processor_showPanelWithToolBarTapComment]
// All three selectors exist in 14.9.10.10022 (checked in the ObjC class dump).
//
// Plain ObjC + runtime swizzle, no substrate dependency, so it loads fine
// alongside ElleKit tweaks. Install is deferred to the main queue after
// launch; swizzle happens once the class is registered (it is a main-binary
// class, so it is present immediately, but deferring avoids init-order issues
// with the other injected tweaks).

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

typedef struct { double x; double y; } KSPoint;

static void KSOpenCommentPanel(id gestureComponent) {
    @try {
        if (![gestureComponent respondsToSelector:@selector(processorManager)]) return;
        id manager = ((id (*)(id, SEL))objc_msgSend)(gestureComponent, @selector(processorManager));
        if (!manager || ![manager respondsToSelector:@selector(boardCombinationProcessor)]) return;
        id board = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(boardCombinationProcessor));
        if (!board) return;
        // Prefer the plain no-arg variant; fall back to the one-arg variant.
        if ([board respondsToSelector:@selector(processor_showPanelWithToolBarTapComment)]) {
            ((void (*)(id, SEL))objc_msgSend)(board, @selector(processor_showPanelWithToolBarTapComment));
        } else if ([board respondsToSelector:@selector(processor_showPanelWithToolBarTapComment:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(board, @selector(processor_showPanelWithToolBarTapComment:), nil);
        }
    } @catch (NSException *e) {
        // Never let a comment-open failure crash the host app.
    }
}

static void KSDblTapReplacement(id self, SEL _cmd, KSPoint location) {
    // Intentionally do not call the original implementation:
    // the original posts a like + plays the heart effect.
    KSOpenCommentPanel(self);
}

static void KSInstall(void) {
    Class cls = objc_getClass("KSTabBarGestureLogicComponent");
    if (!cls) return;
    SEL sel = @selector(slideDetailPageHandleDoubleTapGestureWithLocation:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    // Only replace if the class itself (not a superclass) defines it.
    BOOL own = NO;
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(list[i]) == sel) { own = YES; break; }
    }
    if (list) free(list);
    if (!own) return;
    method_setImplementation(m, (IMP)KSDblTapReplacement);
}

__attribute__((constructor)) static void KSEntry(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        KSInstall();
    });
}
