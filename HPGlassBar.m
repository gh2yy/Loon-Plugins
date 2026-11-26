// HPGlassBar.m — 虎扑液态玻璃悬浮底栏 v3 (2026-11-26)
// 沿革：v1 挂错类（ObjC 旧栏 HPTabBar）真机零反应；v2 改挂 Swift 真底栏 _TtC4HPUI10HPUITabBar 生效，
//   但真机录屏逐帧量出：高亮胶囊停在自算的槽位中心，按钮图标却在 App 自己布局的位置（整行均匀右移约 34pt），
//   两者对不齐、右 tab 差最多。v3 改法：绝不移动按钮，只读按钮的真实位置——
//   胶囊按按钮行实际范围贴合，高亮按选中按钮内容（label + tabImageView 并集）的真实中心与宽度定位。
// 挂点：HPUITabBar layoutSubviews / updateButtonWithButton:selected:；ObjC 旧栏 HPTabBar 挂点保留兼容。
// 玻璃：UIGlassEffectStyleClear 清透款（用户指定，不要可调设置）；日/夜按底栏原背景色明度推断。
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

// 按钮内容（图标+文字）在底栏坐标系中的真实矩形：Swift 按钮取 label/tabImageView，ObjC 按钮取 titleLabel/imageView
static CGRect HPButtonContentRect(UIView *bar, UIView *btn) {
    CGRect u = CGRectNull;
    NSArray<NSString *> *names = @[@"label", @"tabImageView", @"titleLabel", @"imageView"];
    for (NSString *name in names) {
        SEL s = NSSelectorFromString(name);
        if (![btn respondsToSelector:s]) continue;
        UIView *v = ((id (*)(id, SEL))objc_msgSend)(btn, s);
        if (v && [v isKindOfClass:[UIView class]] && [v isDescendantOfView:bar]) {
            CGRect r = [bar convertRect:v.bounds fromView:v];
            if (r.size.width > 0 && r.size.height > 0)
                u = CGRectIsNull(u) ? r : CGRectUnion(u, r);
        }
    }
    if (CGRectIsNull(u)) u = [bar convertRect:btn.bounds fromView:btn];
    return u;
}

static BOOL HPIsAncestorOfAny(UIView *v, NSArray *btns) {
    for (UIView *b in btns) if ([b isDescendantOfView:v]) return YES;
    return NO;
}

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
    NSArray *btns = HPBarButtons(bar, btnCls);
    if (btns.count == 0) return;
    HPInferTheme(bar);
    HPEnsureViews(bar);

    UIView *box = objc_getAssociatedObject(bar, &kGlassBoxKey);
    UIView *pill = objc_getAssociatedObject(bar, &kPillKey);

    // 藏原背景（不藏任何装着按钮的容器）
    if ([bar respondsToSelector:@selector(backgroundView)]) {
        UIView *bg = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(backgroundView));
        if (bg && !HPIsAncestorOfAny(bg, btns)) bg.hidden = YES;
    }
    for (UIView *v in bar.subviews) {
        if (v == box || v == pill) continue;
        if (HPIsAncestorOfAny(v, btns)) continue;
        CGRect f = v.frame;
        BOOL fullBg = f.size.width >= bounds.size.width * 0.9 && f.size.height >= bounds.size.height * 0.9;
        BOOL topLine = f.size.height <= 1.0 && f.size.width >= bounds.size.width * 0.9;
        if (fullBg || topLine) v.hidden = YES;
    }
    bar.backgroundColor = [UIColor clearColor];

    // 按钮真实矩形（底栏坐标系）——只读，绝不改
    NSMutableArray *frames = [NSMutableArray array];
    NSMutableArray *contents = [NSMutableArray array];
    CGRect row = CGRectNull;
    for (UIView *b in btns) {
        CGRect f = [bar convertRect:b.bounds fromView:b];
        [frames addObject:[NSValue valueWithCGRect:f]];
        [contents addObject:[NSValue valueWithCGRect:HPButtonContentRect(bar, b)]];
        row = CGRectIsNull(row) ? f : CGRectUnion(row, f);
    }

    // 胶囊：贴合按钮行——横向 = 行范围左右各扩 12 并夹进 [10, W-10]；纵向高 58、中心对齐行中心、底边不超界
    CGFloat capH = 58.0;
    CGFloat capX = MAX(10.0, row.origin.x - 12);
    CGFloat capR = MIN(bounds.size.width - 10, CGRectGetMaxX(row) + 12);
    CGFloat capCY = CGRectGetMidY(row);
    CGFloat capY = capCY - capH / 2;
    if (capY < 2) capY = 2;
    if (capY + capH > bounds.size.height - 4) capY = bounds.size.height - 4 - capH;
    CGRect capsule = CGRectMake(capX, capY, capR - capX, capH);
    box.frame = capsule;
    box.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:box.bounds cornerRadius:capH / 2].CGPath;
    UIVisualEffectView *fx = objc_getAssociatedObject(bar, &kGlassFxKey);
    fx.frame = box.bounds;
    fx.layer.cornerRadius = capH / 2;
    fx.clipsToBounds = YES;

    // 高亮：贴选中按钮的内容中心，宽 = 内容宽 + 30（夹在 60..110）
    UIView *selBtn = objc_getAssociatedObject(bar, &kSelBtnKey);
    NSUInteger sel = selBtn ? [btns indexOfObject:selBtn] : NSNotFound;
    if (sel == NSNotFound) {
        sel = 0;
        if ([bar respondsToSelector:@selector(selectedIndex)]) {
            NSInteger si = ((NSInteger (*)(id, SEL))objc_msgSend)(bar, @selector(selectedIndex));
            if (si >= 0 && si < (NSInteger)btns.count) sel = (NSUInteger)si;
        }
    }
    CGRect cr = [contents[sel] CGRectValue];
    CGFloat pillW = MIN(MAX(cr.size.width + 30, 60.0), 110.0);
    CGFloat pillH = capH - 16;
    pill.frame = CGRectMake(CGRectGetMidX(cr) - pillW / 2, capsule.origin.y + (capH - pillH) / 2, pillW, pillH);
    pill.layer.cornerRadius = pillH / 2;
    pill.hidden = NO;

    // 层级：玻璃 < 高亮 < 按钮（按钮若在容器里，把容器整体提到高亮之上）
    [bar bringSubviewToFront:pill];
    for (UIView *b in btns) {
        UIView *top = b;
        while (top.superview && top.superview != bar) top = top.superview;
        if (top.superview == bar) [bar bringSubviewToFront:top];
    }
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
    NSLog(@"[HPGlass] v3 install: swiftBar=%@ swiftBtn=%@ objcBar=%@ installed=%d",
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
