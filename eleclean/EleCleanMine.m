// DYCommentClean — Douyin 41.1.0 comment panel header cleanup.
// Removes, visually only (hide + disable interaction; views stay in the
// hierarchy so later layout/reference calls still see them):
//   1. the two small buttons beside the "N条评论" title (expand / close)
//   2. the thin separator line directly under the title (same view in
//      light and dark mode, so hiding it covers both)
//
// Anchors (any one can trigger a cleanup):
//   A. UILabel setText:/setAttributedText: with a "…条评论" title.
//   B. layoutSubviews / didMoveToWindow of the known header classes
//      (AWECommentVCHeaderBarView, CommentVCHeaderCloseBar) when the
//      runtime resolves them.
// Cleanup walks from the title (or the bar view) up through ancestor
// containers near the top of the panel and scans their subtrees:
//   - thin & wide views (h <= 1.6, w >= 120)            -> separator
//   - thin sublayers hugging a container's bottom edge  -> layer line
//   - controls / tappable / small leaf views centred well right of
//     the title centre                                  -> the buttons
//   - right-side wrappers left with all children hidden -> hidden too
// Label-anchored cleanup re-runs at +0.1/+0.35/+0.8s to cover buttons
// that enter the hierarchy after the title text. Fail-open throughout.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gCleaning = NO;

// The build pipeline links Foundation only, so UIKit/CoreGraphics
// symbols must not be referenced directly: classes are resolved by
// name at runtime and geometry helpers are computed inline.
static Class DYCls(const char *name) {
    return NSClassFromString([NSString stringWithUTF8String:name]);
}

static BOOL DYIsCommentTitle(NSString *t) {
    if (![t isKindOfClass:[NSString class]]) return NO;
    NSUInteger n = [t length];
    if (n == 0 || n > 24) return NO;
    if (![t containsString:@"条评论"]) return NO;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [t characterAtIndex:i];
        if (c >= '0' && c <= '9') return YES;
    }
    return NO;
}

static void DYHide(UIView *v) {
    if (!v) return;
    if (!v.hidden) v.hidden = YES;
    if (v.userInteractionEnabled) v.userInteractionEnabled = NO;
}

// Recursive scan of one container's subtree. Geometry is judged in the
// container's own coordinate space; titleCX is the title centre X there
// (or the container mid X when no title reference is available).
static void DYScan(UIView *root, UIView *node, CGFloat titleCX, int depth) {
    if (!node || depth > 6) return;
    for (UIView *sub in [node.subviews copy]) {
        if ([sub isKindOfClass:DYCls("UILabel")]) continue; // never touch labels
        CGRect f = [sub convertRect:sub.bounds toView:root];
        CGFloat cx = (f.origin.x + f.size.width / 2.0);
        CGFloat w = f.size.width, h = f.size.height;
        BOOL thinLine = (h > 0 && h <= 1.6 && w >= 120);
        BOOL isControl = [sub isKindOfClass:DYCls("UIControl")];
        BOOL tappable = ([sub gestureRecognizers].count > 0);
        BOOL leaf = ([sub subviews].count == 0);
        BOOL smallBtn = (w >= 14 && w <= 72 && h >= 14 && h <= 72);
        BOOL rightSide = (cx > titleCX + 44);
        if (thinLine) { DYHide(sub); continue; }
        if (rightSide && smallBtn && (isControl || tappable || leaf)) {
            DYHide(sub); continue;
        }
        DYScan(root, sub, titleCX, depth + 1);
        if (rightSide && w <= 140 && h <= 72 && [sub subviews].count > 0) {
            BOOL allHidden = YES;
            for (UIView *c in sub.subviews) if (!c.hidden) { allHidden = NO; break; }
            if (allHidden) DYHide(sub);
        }
    }
    for (CALayer *l in [node.layer.sublayers copy]) {
        CGRect lf = l.frame;
        if (lf.size.height > 0 && lf.size.height <= 1.6 && lf.size.width >= 120 &&
            ((lf.origin.y + lf.size.height) - node.bounds.size.height <= 3.0 && (lf.origin.y + lf.size.height) - node.bounds.size.height >= -3.0)) {
            if (!l.hidden) l.hidden = YES;
            if (l.opacity != 0.0f) l.opacity = 0.0f;
        }
    }
}

// Clean every short (<=140pt) container on the path from `anchor` up,
// plus a shallow pass over a tall ancestor's short direct children
// (covers a sibling bar that shares a tall panel parent).
static void DYCleanFromAnchor(UIView *anchor, UILabel *title) {
    if (!anchor || gCleaning) return;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ DYCleanFromAnchor(anchor, title); });
        return;
    }
    gCleaning = YES;
    // the anchor itself first (matters when the anchor is a bar view
    // whose own subviews hold the buttons / the line)
    {
        CGFloat refX = (title && title != anchor)
            ? [title.superview convertPoint:title.center toView:anchor].x
            : anchor.bounds.size.width / 2.0;
        DYScan(anchor, anchor, refX, 0);
    }
    UIView *v = anchor;
    for (int i = 0; i < 6 && v.superview; i++) {
        v = v.superview;
        CGFloat h = v.frame.size.height;
        CGFloat refX;
        if (title) {
            refX = [title.superview convertPoint:title.center toView:v].x;
        } else {
            refX = v.bounds.size.width / 2.0;
        }
        if (h <= 140) {
            DYScan(v, v, refX, 0);
        } else {
            for (UIView *child in [v.subviews copy]) {
                if (child.frame.size.height > 0 && child.frame.size.height <= 140 &&
                    child.frame.origin.y < 160) {
                    CGFloat cx = title ? [title.superview convertPoint:title.center toView:child].x
                                       : child.bounds.size.width / 2.0;
                    DYScan(child, child, cx, 0);
                }
            }
            // separator could be a bottom layer of the tall ancestor's
            // short header area; the per-child scan above covers the
            // common shapes, so stop climbing here.
            break;
        }
    }
    gCleaning = NO;
}

static void DYScheduleClean(UILabel *label) {
    __weak UILabel *w = label;
    dispatch_async(dispatch_get_main_queue(), ^{ if (w) DYCleanFromAnchor(w, w); });
    for (NSNumber *d in @[@0.1, @0.35, @0.8]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ if (w) DYCleanFromAnchor(w, w); });
    }
}

// ---- Anchor A: UILabel text ----
static IMP gOrigSetText = NULL;
static void DYSetText(UILabel *self, SEL _cmd, NSString *text) {
    ((void (*)(id, SEL, id))gOrigSetText)(self, _cmd, text);
    if (DYIsCommentTitle(text)) DYScheduleClean(self);
}
static IMP gOrigSetAttrText = NULL;
static void DYSetAttrText(UILabel *self, SEL _cmd, NSAttributedString *text) {
    ((void (*)(id, SEL, id))gOrigSetAttrText)(self, _cmd, text);
    if (text && DYIsCommentTitle(text.string)) DYScheduleClean(self);
}

// ---- Anchor B: known header-bar classes ----
// Only methods a class defines ITSELF are swizzled in place (patching an
// inherited Method would patch the superclass for every subclass).
static NSMutableDictionary<NSString *, NSValue *> *gOrigLayout = nil;
static NSMutableDictionary<NSString *, NSValue *> *gOrigMove = nil;

static IMP DYFindOrig(NSDictionary<NSString *, NSValue *> *dict, id self) {
    Class c = object_getClass(self);
    while (c) {
        NSValue *v = dict[NSStringFromClass(c)];
        if (v) return [v pointerValue];
        c = class_getSuperclass(c);
    }
    return NULL;
}
static BOOL DYClassDefines(Class cls, SEL sel) {
    unsigned int n = 0;
    Method *list = class_copyMethodList(cls, &n);
    BOOL found = NO;
    for (unsigned int i = 0; i < n; i++) {
        if (method_getName(list[i]) == sel) { found = YES; break; }
    }
    if (list) free(list);
    return found;
}

static void DYBarLayout(UIView *self, SEL _cmd) {
    IMP orig = DYFindOrig(gOrigLayout, self);
    if (orig) ((void (*)(id, SEL))orig)(self, _cmd);
    DYCleanFromAnchor(self, nil);
}
static void DYBarMove(UIView *self, SEL _cmd) {
    IMP orig = DYFindOrig(gOrigMove, self);
    if (orig) ((void (*)(id, SEL))orig)(self, _cmd);
    if (self.window) DYCleanFromAnchor(self, nil);
}

// Swizzle only when the class defines the method itself; a class that
// merely inherits it needs no hook of its own — the label anchor and
// the first layout of any hooked ancestor still trigger cleanups.
static void DYHookOne(Class cls, SEL sel, IMP swizzled,
                      NSMutableDictionary<NSString *, NSValue *> *store) {
    NSString *key = NSStringFromClass(cls);
    if ([store objectForKey:key]) return;
    if (!DYClassDefines(cls, sel)) return;
    Method m = class_getInstanceMethod(cls, sel);
    store[key] = [NSValue valueWithPointer:method_getImplementation(m)];
    method_setImplementation(m, swizzled);
}

static void DYHookBarClass(Class cls) {
    if (!cls || ![cls isSubclassOfClass:DYCls("UIView")]) return;
    DYHookOne(cls, @selector(layoutSubviews), (IMP)DYBarLayout, gOrigLayout);
    DYHookOne(cls, @selector(didMoveToWindow), (IMP)DYBarMove, gOrigMove);
}

__attribute__((constructor)) static void DYInit(void) {
    @autoreleasepool {
        Method m1 = class_getInstanceMethod(DYCls("UILabel"), @selector(setText:));
        if (m1) {
            gOrigSetText = method_getImplementation(m1);
            method_setImplementation(m1, (IMP)DYSetText);
        }
        Method m2 = class_getInstanceMethod(DYCls("UILabel"), @selector(setAttributedText:));
        if (m2) {
            gOrigSetAttrText = method_getImplementation(m2);
            method_setImplementation(m2, (IMP)DYSetAttrText);
        }
        gOrigLayout = [NSMutableDictionary dictionary];
        gOrigMove = [NSMutableDictionary dictionary];
        NSArray<NSString *> *names = @[
            @"AWECommentVCHeaderBarView",
            @"AWECommentPanelContainerSwiftImpl.CommentVCHeaderCloseBar",
            @"CommentVCHeaderCloseBar",
        ];
        for (NSString *n in names) DYHookBarClass(NSClassFromString(n));
        // Classes in lazily loaded bundles may not exist yet at load
        // time; retry a few times during the first seconds after launch.
        for (NSNumber *d in @[@1.0, @3.0, @8.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                for (NSString *n in names) DYHookBarClass(NSClassFromString(n));
            });
        }
    }
}
