// HPGlassBar.m — 虎扑液态玻璃悬浮底栏 v1 (2026-11-25)
// 目标类：HPTabBar（自绘底栏）+ HPTabBarButton + HPBaseTabBarController（主题切换）
// 做法：不动 App 自己的布局契约，只在 HPTabBar layoutSubviews 之后：
//   1) 藏原背景（backgroundView + 全宽顶线），底栏自身背景透明
//   2) 在按钮下垫一层悬浮胶囊：容器(投影) + UIVisualEffectView(UIGlassEffect，无则 UIBlurEffect 兜底)
//   3) 按钮按原左右顺序等分重排进胶囊内（递归找按钮，坐标换算回各自父视图）
//   4) 选中项背后加一颗高亮胶囊（白天黑 9% / 夜间白 18%），切换时 0.25s 滑动
//   5) 日/夜跟随虎扑自己的 transferToNight:/transferToDay:（虎扑是 App 内主题、不等于系统外观）；
//      首次布局前用原背景色明度猜初始主题
// 纯运行时 swizzle，无 substrate 依赖；UIGlassEffect 全部走 NSClassFromString 动态解析（编译 SDK 无此符号）。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL gNightKnown = NO;
static BOOL gNight = NO;

static char kGlassBoxKey;
static char kGlassFxKey;
static char kPillKey;

#pragma mark - 小工具

static UIVisualEffect *HPMakeGlassEffect(void) {
    Class glassCls = NSClassFromString(@"UIGlassEffect");
    if (glassCls && [glassCls respondsToSelector:@selector(effectWithStyle:)]) {
        // UIGlassEffectStyleClear = 1（清透款，对齐小红书插件截图的通透感；Regular=0 更雾）
        UIVisualEffect *fx = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, @selector(effectWithStyle:), 1);
        if (fx) {
            if ([fx respondsToSelector:@selector(setInteractive:)])
                ((void (*)(id, SEL, BOOL))objc_msgSend)(fx, @selector(setInteractive:), NO);
            return fx;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
}

// 递归收集 HPTabBarButton（可能不在底栏的直接子层），按在底栏坐标系里的中心 x 排序
static void HPCollectButtons(UIView *root, UIView *bar, NSMutableArray *out) {
    Class btnCls = NSClassFromString(@"HPTabBarButton");
    for (UIView *v in root.subviews) {
        if (btnCls && [v isKindOfClass:btnCls]) [out addObject:v];
        else HPCollectButtons(v, bar, out);
    }
}
static NSArray *HPBarButtons(UIView *bar) {
    NSMutableArray *out = [NSMutableArray array];
    HPCollectButtons(bar, bar, out);
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = CGRectGetMidX([bar convertRect:a.bounds fromView:a]);
        CGFloat bx = CGRectGetMidX([bar convertRect:b.bounds fromView:b]);
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return out;
}

static void HPGuessInitialTheme(UIView *bar) {
    if (gNightKnown) return;
    if ([bar respondsToSelector:@selector(backgroundView)]) {
        UIView *bg = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(backgroundView));
        UIColor *c = bg.backgroundColor;
        if (c) {
            CGFloat w = 0, a = 0;
            if ([c getWhite:&w alpha:&a] && a > 0.3) { gNight = w < 0.35; gNightKnown = YES; return; }
        }
    }
    gNight = (bar.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    gNightKnown = YES;
}

#pragma mark - 样式

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
    HPGuessInitialTheme(bar);
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

static void HPLayoutBar(UIView *bar) {
    CGRect bounds = bar.bounds;
    if (bounds.size.width < 50 || bounds.size.height < 30) return;
    HPEnsureViews(bar);

    if ([bar respondsToSelector:@selector(backgroundView)]) {
        UIView *bg = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(backgroundView));
        if (bg) bg.hidden = YES;
    }
    bar.backgroundColor = [UIColor clearColor];
    UIView *box = objc_getAssociatedObject(bar, &kGlassBoxKey);
    UIView *pill = objc_getAssociatedObject(bar, &kPillKey);
    Class btnCls = NSClassFromString(@"HPTabBarButton");
    for (UIView *v in bar.subviews) {
        if (v == box || v == pill) continue;
        if (btnCls && [v isKindOfClass:btnCls]) continue;
        CGRect f = v.frame;
        if (f.size.height <= 1.0 && f.size.width >= bounds.size.width * 0.9) v.hidden = YES; // 全宽顶线
    }

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

    NSArray *btns = HPBarButtons(bar);
    if (btns.count == 0) { pill.hidden = YES; return; }
    CGFloat slot = capsule.size.width / btns.count;
    NSMutableArray *barFrames = [NSMutableArray array];
    for (NSUInteger i = 0; i < btns.count; i++) {
        UIView *b = btns[i];
        CGRect cur = [bar convertRect:b.bounds fromView:b]; // 底栏坐标系
        CGSize s = cur.size;
        if (s.width <= 0 || s.width > slot) s.width = MIN(slot, 76);
        if (s.height <= 0 || s.height > capH - 6) s.height = capH - 10;
        CGFloat cx = capsule.origin.x + slot * (i + 0.5);
        CGFloat cy = capsule.origin.y + capH / 2;
        CGRect nf = CGRectMake(cx - s.width / 2, cy - s.height / 2, s.width, s.height);
        [barFrames addObject:[NSValue valueWithCGRect:nf]];
        if (b.superview) b.frame = [b.superview convertRect:nf fromView:bar];
    }

    NSInteger sel = 0;
    if ([bar respondsToSelector:@selector(selectedIndex)])
        sel = ((NSInteger (*)(id, SEL))objc_msgSend)(bar, @selector(selectedIndex));
    if (sel < 0 || sel >= (NSInteger)btns.count) sel = 0;
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

static void HPRestyleBarsInView(UIView *root) {
    if ([root isKindOfClass:NSClassFromString(@"HPTabBar")]) { HPApplyTheme(root); HPLayoutBar(root); }
    for (UIView *v in root.subviews) HPRestyleBarsInView(v);
}

#pragma mark - Hook 安装

static IMP gOrigLayoutSubviews, gOrigSetSelected, gOrigSetupSelected, gOrigReload, gOrigTrait;
static IMP gOrigToNight, gOrigToDay;

static void HP_HPTabBar_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigLayoutSubviews)(self, _cmd);
    HPLayoutBar(self);
}
static void HP_HPTabBar_setSelectedIndex(UIView *self, SEL _cmd, NSInteger idx) {
    ((void (*)(id, SEL, NSInteger))gOrigSetSelected)(self, _cmd, idx);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        HPLayoutBar(self);
    } completion:nil];
}
static void HP_HPTabBar_setupSelectedIndex(UIView *self, SEL _cmd, NSInteger idx) {
    ((void (*)(id, SEL, NSInteger))gOrigSetupSelected)(self, _cmd, idx);
    HPLayoutBar(self);
}
static void HP_HPTabBar_reload(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigReload)(self, _cmd);
    HPLayoutBar(self);
}
static void HP_HPTabBar_trait(UIView *self, SEL _cmd, UITraitCollection *prev) {
    ((void (*)(id, SEL, UITraitCollection *))gOrigTrait)(self, _cmd, prev);
    HPApplyTheme(self);
}
static void HP_TabCtrl_transfer(UIViewController *self, SEL _cmd, id arg) {
    BOOL toNight = (_cmd == @selector(transferToNight:));
    IMP orig = toNight ? gOrigToNight : gOrigToDay;
    if (orig) ((void (*)(id, SEL, id))orig)(self, _cmd, arg);
    gNight = toNight; gNightKnown = YES;
    if (self.view) HPRestyleBarsInView(self.view);
}

static IMP HPSwap(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NULL;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { NSLog(@"[HPGlass] missing method %@ on %@", NSStringFromSelector(sel), NSStringFromClass(cls)); return NULL; }
    return method_setImplementation(m, newImp);
}

__attribute__((constructor)) static void HPGlassBarInit(void) {
    @autoreleasepool {
        Class barCls = NSClassFromString(@"HPTabBar");
        Class ctrlCls = NSClassFromString(@"HPBaseTabBarController");
        gOrigLayoutSubviews = HPSwap(barCls, @selector(layoutSubviews), (IMP)HP_HPTabBar_layoutSubviews);
        gOrigSetSelected = HPSwap(barCls, @selector(setSelectedIndex:), (IMP)HP_HPTabBar_setSelectedIndex);
        gOrigSetupSelected = HPSwap(barCls, @selector(setupSelectedIndex:), (IMP)HP_HPTabBar_setupSelectedIndex);
        gOrigReload = HPSwap(barCls, @selector(reloadImageAndTitles), (IMP)HP_HPTabBar_reload);
        gOrigTrait = HPSwap(barCls, @selector(traitCollectionDidChange:), (IMP)HP_HPTabBar_trait);
        gOrigToNight = HPSwap(ctrlCls, @selector(transferToNight:), (IMP)HP_TabCtrl_transfer);
        gOrigToDay = HPSwap(ctrlCls, @selector(transferToDay:), (IMP)HP_TabCtrl_transfer);
        NSLog(@"[HPGlass] v1 hooks installed (bar=%@ ctrl=%@)", barCls, ctrlCls);
    }
}
