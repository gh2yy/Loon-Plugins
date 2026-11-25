// HPGlassBar.m — 虎扑液态玻璃悬浮底栏 v2 (2026-11-25)
// v1 教训：8.1.9 真底栏不是 ObjC 的 HPTabBar（旧系统），而是 Swift 类 _TtC4HPUI10HPUITabBar（模块 HPUI），
// v1 挂错类、真机零反应。本版改挂真底栏，并以 dylib 单文件交付（用户自行注入，不再出整包）。
// 挂点（均为 ObjC 可见方法）：
//   HPUITabBar layoutSubviews                      —— orig 后重排
//   HPUITabBar updateButtonWithButton:selected:  —— 选中变化时滑动高亮胶囊
//   HPTabBar（ObjC 旧底栏）layoutSubviews 等       —— 保留 v1 挂点，次级场景兼容
// 做法：藏原背景（全尺寸非按钮子视图 + backgroundColor），按钮层下垫悬浮胶囊
//   （容器投影 + UIVisualEffectView，UIGlassEffectStyleClear 清透款），按钮按原序等分重排进胶囊，
//   选中项后加高亮胶囊（白天黑 9% / 夜间白 18%）。日/夜在每次布局时按底栏原背景色明度推断（虎扑 App 内主题）。
// 纯运行时 swizzle + +load 安装，无 substrate 依赖；UIGlassEffect 走 NSClassFromString 动态解析。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gNightKnown = NO;
static BOOL gNight = NO;

static char kGlassBoxKey;
static char kGlassFxKey;
static char kPillKey;
static char kSelBtnKey;

#pragma mark - 工具

static UIVisualEffect *HPMakeGlassEffect(void) {
    Class glassCls = NSClassFromString(@"UIGlassEffect");
    if (glassCls && [glassCls respondsToSelector:@selector(effectWithStyle:)]) {
        // UIGlassEffectStyleClear = 1（清透款；Regular = 0 更雾）
        UIVisualEffect *fx = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, @selector(effectWithStyle:), 1);
        if (fx) {
            if ([fx respondsToSelector:@selector(setInteractive:)])
                ((void (*)(id, SEL, BOOL))objc_msgSend)(fx, @selector(setInteractive:), NO);
            return fx;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

static Class HPFindClass(NSString *exact, NSString *contains, NSArray<NSString *> *excludes) {
    Class c = NSClassFromString(exact);
    if (c) return c;
    int n = objc_getClassList(NULL, 0);
    if (n <= 0) return nil;
    Class *list = (__unsafe_unretained Class *)malloc(sizeof(Class) * n);
    objc_getClassList(list, n);
    Class found = nil;
    for (int i = 0; i < n; i++) {
        NSString *name = NSStringFromClass(list[i]);
        if (![name containsString:contains]) continue;
        BOOL bad = NO;
        for (NSString *ex in excludes) if ([name containsString:ex]) { bad = YES; break; }
        if (!bad) { found = list[i]; break; }
    }
    free(list);
    return found;
}

static void HPCollectButtons(UIView *root, Class btnCls, NSMutableArray *out) {
    for (UIView *v in root.subviews) {
        if (btnCls && [v isKindOfClass:btnCls]) [out addObject:v];
        else HPCollectButtons(v, btnCls, out);
    }
}
static NSArray *HPBarButtons(UIView *bar, Class btnCls) {
    NSMutableArray *out = [NSMutableArray array];
    HPCollectButtons(bar, btnCls, out);
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = CGRectGetMidX([bar convertRect:a.bounds fromView:a]);
        CGFloat bx = CGRectGetMidX([bar convertRect:b.bounds fromView:b]);
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return out;
}

// 每次布局先读底栏当前背景色明度推断日/夜（App 会在切主题时重设背景色），再动手清掉
static void HPInferTheme(UIView *bar) {
    UIColor *c = bar.backgroundColor;
    if (c) {
        CGFloat w = 0, a = 0;
        if ([c getWhite:&w alpha:&a] && a > 0.3) { gNight = w < 0.35; gNightKnown = YES; return; }
    }
    if (!gNightKnown) {
        gNight = (bar.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
        gNightKnown = YES;
    }
}

#pragma mark - 样式与布局

static void HPApplyTheme(UIView *bar) {
    UIView *box = objc_getAssociatedObject(bar, &kGlassBoxKey);
    UIView *pill = objc_getAssociatedObject(bar, &kPillKey);
    if (!box) return;
    UIUserInterfaceStyle style = gNight ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    box.overrideUserInterfaceStyle = style;
    box.layer.shadowColor = [UIColor blackColor].CGColor;
    box.layer.shadowOpacity = gNight ? 0.45 : 0.18;
    if (pill) {
        pill.overrideUserInterfaceStyle = style;
        pill.backgroundColor = gNight ? [UIColor colorWithWhite:1.0 alpha:0.18]
                                      : [UIColor colorWithWhite:0.0 alpha:0.09];
        pill.layer.borderColor = (gNight ? [UIColor colorWithWhite:1.0 alpha:0.10]
                                         : [UIColor colorWithWhite:0.0 alpha:0.04]).CGColor;
    }
}

static void HPEnsureViews(UIView *bar) {
    UIView *box = objc_getAssociatedObject(bar, &kGlassBoxKey);
    if (!box) {
        box = [[UIView alloc] initWithFrame:CGRectZero];
        box.backgroundColor = [UIColor clearColor];
        box.userInteractionEnabled = NO;
        box.layer.shadowOffset = CGSizeMake(0, 6);
        box.layer.shadowRadius = 16;
        UIVisualEffectView *fx = [[UIVisualEffectView alloc] initWithEffect:HPMakeGlassEffect()];
        fx.userInteractionEnabled = NO;
        fx.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [box addSubview:fx];
        [bar insertSubview:box atIndex:0];
        objc_setAssociatedObject(bar, &kGlassBoxKey, box, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &kGlassFxKey, fx, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIView *pill = [[UIView alloc] initWithFrame:CGRectZero];
        pill.userInteractionEnabled = NO;
        pill.layer.borderWidth = 0.5;
        [bar insertSubview:pill atIndex:1];
        objc_setAssociatedObject(bar, &kPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    HPApplyTheme(bar);
}

static void HPLayoutBar(UIView *bar, Class btnCls) {
    CGRect bounds = bar.bounds;
    if (bounds.size.width < 50 || bounds.size.height < 30) return;
    HPInferTheme(bar);
    HPEnsureViews(bar);

    UIView *box = objc_getAssociatedObject(bar, &kGlassBoxKey);
    UIView *pill = objc_getAssociatedObject(bar, &kPillKey);

    // 藏原背景：ObjC 旧栏的 backgroundView + 两代通用的「全尺寸非按钮子视图」+ 全宽顶线
    if ([bar respondsToSelector:@selector(backgroundView)]) {
        UIView *bg = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(backgroundView));
        if (bg) bg.hidden = YES;
    }
    NSArray *btns = HPBarButtons(bar, btnCls);
    for (UIView *v in bar.subviews) {
        if (v == box || v == pill) continue;
        if (btnCls && [v isKindOfClass:btnCls]) continue;
        CGRect f = v.frame;
        BOOL fullBg = f.size.width >= bounds.size.width * 0.9 && f.size.height >= bounds.size.height * 0.9;
        BOOL topLine = f.size.height <= 1.0 && f.size.width >= bounds.size.width * 0.9;
        if (fullBg || topLine) v.hidden = YES;
    }
    bar.backgroundColor = [UIColor clearColor];

    CGFloat h = bounds.size.height;
    CGFloat capH = MIN(58.0, h - 6);
    CGFloat bottomGap = (h >= 70) ? 12.0 : 6.0;
    CGRect capsule = CGRectMake(14, h - bottomGap - capH, bounds.size.width - 28, capH);
    box.frame = capsule;
    box.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:box.bounds cornerRadius:capH / 2].CGPath;
    UIVisualEffectView *fx = objc_getAssociatedObject(bar, &kGlassFxKey);
    fx.frame = box.bounds;
    fx.layer.cornerRadius = capH / 2;
    fx.clipsToBounds = YES;

    if (btns.count == 0) { pill.hidden = YES; return; }
    CGFloat slot = capsule.size.width / btns.count;
    NSMutableArray *barFrames = [NSMutableArray array];
    for (NSUInteger i = 0; i < btns.count; i++) {
        UIView *b = btns[i];
        CGRect cur = [bar convertRect:b.bounds fromView:b];
        CGSize s = cur.size;
        if (s.width <= 0 || s.width > slot) s.width = MIN(slot, 76);
        if (s.height <= 0 || s.height > capH - 6) s.height = capH - 10;
        CGFloat cx = capsule.origin.x + slot * (i + 0.5);
        CGFloat cy = capsule.origin.y + capH / 2;
        CGRect nf = CGRectMake(cx - s.width / 2, cy - s.height / 2, s.width, s.height);
        [barFrames addObject:[NSValue valueWithCGRect:nf]];
        if (b.superview) b.frame = [b.superview convertRect:nf fromView:bar];
    }

    UIView *selBtn = objc_getAssociatedObject(bar, &kSelBtnKey);
    NSUInteger sel = selBtn ? [btns indexOfObject:selBtn] : NSNotFound;
    if (sel == NSNotFound) {
        sel = 0;
        if ([bar respondsToSelector:@selector(selectedIndex)]) {
            NSInteger si = ((NSInteger (*)(id, SEL))objc_msgSend)(bar, @selector(selectedIndex));
            if (si >= 0 && si < (NSInteger)btns.count) sel = (NSUInteger)si;
        }
    }
    CGRect sbf = [barFrames[sel] CGRectValue];
    CGFloat pillH = capH - 18;
    pill.frame = CGRectMake(CGRectGetMidX(sbf) - (sbf.size.width + 14) / 2,
                            capsule.origin.y + (capH - pillH) / 2,
                            sbf.size.width + 14, pillH);
    pill.layer.cornerRadius = pillH / 2;
    pill.hidden = NO;
    [bar bringSubviewToFront:pill];
    for (UIView *b in btns) if (b.superview == bar) [bar bringSubviewToFront:b];
}

#pragma mark - Hook

static IMP gOrigSwiftLayout, gOrigSwiftUpdateBtn;
static IMP gOrigObjcLayout, gOrigObjcSetSel, gOrigObjcSetupSel, gOrigObjcReload;
static Class gSwiftBarCls, gSwiftBtnCls, gObjcBarCls, gObjcBtnCls;

static void HP_SwiftBar_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigSwiftLayout)(self, _cmd);
    HPLayoutBar(self, gSwiftBtnCls);
}
static void HP_SwiftBar_updateButton(UIView *self, SEL _cmd, UIView *btn, BOOL selected) {
    ((void (*)(id, SEL, id, BOOL))gOrigSwiftUpdateBtn)(self, _cmd, btn, selected);
    if (selected && btn) {
        objc_setAssociatedObject(self, &kSelBtnKey, btn, OBJC_ASSOCIATION_ASSIGN);
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            HPLayoutBar(self, gSwiftBtnCls);
        } completion:nil];
    }
}
static void HP_ObjcBar_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigObjcLayout)(self, _cmd);
    HPLayoutBar(self, gObjcBtnCls);
}
static void HP_ObjcBar_setSelectedIndex(UIView *self, SEL _cmd, NSInteger idx) {
    ((void (*)(id, SEL, NSInteger))gOrigObjcSetSel)(self, _cmd, idx);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        HPLayoutBar(self, gObjcBtnCls);
    } completion:nil];
}
static void HP_ObjcBar_setupSelectedIndex(UIView *self, SEL _cmd, NSInteger idx) {
    ((void (*)(id, SEL, NSInteger))gOrigObjcSetupSel)(self, _cmd, idx);
    HPLayoutBar(self, gObjcBtnCls);
}
static void HP_ObjcBar_reload(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigObjcReload)(self, _cmd);
    HPLayoutBar(self, gObjcBtnCls);
}

static IMP HPSwap(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NULL;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { NSLog(@"[HPGlass] missing %@ on %@", NSStringFromSelector(sel), NSStringFromClass(cls)); return NULL; }
    return method_setImplementation(m, newImp);
}

static BOOL gInstalled = NO;
static void HPInstall(void) {
    if (gInstalled) return;
    gSwiftBarCls = HPFindClass(@"_TtC4HPUI10HPUITabBar", @"HPUITabBar", @[@"Button", @"Config"]);
    gSwiftBtnCls = HPFindClass(@"_TtC4HPUI16HPUITabBarButton", @"HPUITabBarButton", @[]);
    gObjcBarCls = NSClassFromString(@"HPTabBar");
    gObjcBtnCls = NSClassFromString(@"HPTabBarButton");
    BOOL any = NO;
    if (gSwiftBarCls) {
        gOrigSwiftLayout = HPSwap(gSwiftBarCls, @selector(layoutSubviews), (IMP)HP_SwiftBar_layoutSubviews);
        gOrigSwiftUpdateBtn = HPSwap(gSwiftBarCls, @selector(updateButtonWithButton:selected:), (IMP)HP_SwiftBar_updateButton);
        any = (gOrigSwiftLayout != NULL);
    }
    if (gObjcBarCls) {
        gOrigObjcLayout = HPSwap(gObjcBarCls, @selector(layoutSubviews), (IMP)HP_ObjcBar_layoutSubviews);
        gOrigObjcSetSel = HPSwap(gObjcBarCls, @selector(setSelectedIndex:), (IMP)HP_ObjcBar_setSelectedIndex);
        gOrigObjcSetupSel = HPSwap(gObjcBarCls, @selector(setupSelectedIndex:), (IMP)HP_ObjcBar_setupSelectedIndex);
        gOrigObjcReload = HPSwap(gObjcBarCls, @selector(reloadImageAndTitles), (IMP)HP_ObjcBar_reload);
    }
    gInstalled = any;
    NSLog(@"[HPGlass] v2 install: swiftBar=%@ swiftBtn=%@ objcBar=%@ installed=%d",
          gSwiftBarCls, gSwiftBtnCls, gObjcBarCls, gInstalled);
}

@interface HPGlassLoader : NSObject
@end
@implementation HPGlassLoader
+ (void)load {
    HPInstall();
    dispatch_async(dispatch_get_main_queue(), ^{ HPInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ HPInstall(); });
}
@end
