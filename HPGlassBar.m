// HPGlassBar.m — 虎扑液态玻璃悬浮底栏 v4 (2026-11-26)
// 沿革：v1 挂错类（ObjC 旧栏）零反应；v2 改挂 Swift 真底栏 _TtC4HPUI10HPUITabBar 生效，但玻璃是自拼的
//   （普通视图垫底 + 纯色半透明高亮），且自算槽位与 App 实际布局差约 34pt；v3 修位置（不动按钮、按真实
//   位置贴合）；v4 按用户要求照小红书 XHSNative-1.4 的 plateOn:key:below:frame:bar: 实现重做玻璃本体。
// XHS 玻璃盘配方（反汇编定案，逐项照搬）：
//   UIVisualEffectView(initWithEffect: [UIGlassEffect effectWithStyle:Regular(0)])
//   + cornerConfiguration = [UICornerConfiguration capsuleConfiguration]（设在效果视图上，不是 layer 圆角）
//   + contentView.layer.masksToBounds = YES、contentView.layer.cornerRadius = 高/2
//   + contentView 填充动态色（其主页底栏默认）：浅色 = 白 α0.50；深色 = RGB(0.13,0.13,0.15) α0.50
//   选区高亮同样是一块玻璃盘（无填充），不是纯色块。
// 位置沿用 v3：绝不移动按钮；胶囊按按钮行真实范围贴合，高亮按选中按钮内容（label+tabImageView 并集）定位。
// 挂点：HPUITabBar layoutSubviews / updateButtonWithButton:selected:；ObjC 旧栏 HPTabBar 挂点保留兼容。
// 纯运行时 swizzle + +load 安装，无 substrate 依赖；玻璃类全部 NSClassFromString 动态解析。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static char kCapsuleKey;
static char kLensKey;
static char kSelBtnKey;

#pragma mark - 工具

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

#pragma mark - 玻璃盘（照 XHSNative plateOn 配方）

static UIColor *HPPlateFillColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark)
            return [UIColor colorWithRed:0.13 green:0.13 blue:0.15 alpha:0.50];
        return [UIColor colorWithWhite:1.0 alpha:0.50];
    }];
}

static UIVisualEffectView *HPMakePlate(BOOL withFill) {
    UIVisualEffect *fx = nil;
    Class glassCls = NSClassFromString(@"UIGlassEffect");
    if (glassCls && [glassCls respondsToSelector:@selector(effectWithStyle:)])
        fx = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, @selector(effectWithStyle:), 0); // Regular
    if (!fx) fx = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:fx];
    Class cornerCls = NSClassFromString(@"UICornerConfiguration");
    if (cornerCls && [cornerCls respondsToSelector:@selector(capsuleConfiguration)] &&
        [v respondsToSelector:@selector(setCornerConfiguration:)]) {
        id cfg = ((id (*)(id, SEL))objc_msgSend)(cornerCls, @selector(capsuleConfiguration));
        ((void (*)(id, SEL, id))objc_msgSend)(v, @selector(setCornerConfiguration:), cfg);
    }
    v.userInteractionEnabled = NO;
    v.contentView.layer.masksToBounds = YES;
    if (withFill) v.contentView.backgroundColor = HPPlateFillColor();
    return v;
}

static void HPSetPlateFrame(UIVisualEffectView *plate, CGRect f) {
    plate.frame = f;
    plate.contentView.layer.cornerRadius = f.size.height / 2;
}

#pragma mark - 布局

static void HPLayoutBar(UIView *bar, Class btnCls) {
    CGRect bounds = bar.bounds;
    if (bounds.size.width < 50 || bounds.size.height < 30) return;
    NSArray *btns = HPBarButtons(bar, btnCls);
    if (btns.count == 0) return;

    UIVisualEffectView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    if (!capsule) {
        capsule = HPMakePlate(YES);
        [bar insertSubview:capsule atIndex:0];
        objc_setAssociatedObject(bar, &kCapsuleKey, capsule, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        UIVisualEffectView *lens = HPMakePlate(NO);
        [bar insertSubview:lens atIndex:1];
        objc_setAssociatedObject(bar, &kLensKey, lens, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIVisualEffectView *lens = objc_getAssociatedObject(bar, &kLensKey);

    // 藏原背景（不藏任何装着按钮的容器）
    if ([bar respondsToSelector:@selector(backgroundView)]) {
        UIView *bg = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(backgroundView));
        if (bg && !HPIsAncestorOfAny(bg, btns)) bg.hidden = YES;
    }
    for (UIView *v in bar.subviews) {
        if (v == capsule || v == lens) continue;
        if (HPIsAncestorOfAny(v, btns)) continue;
        CGRect f = v.frame;
        BOOL fullBg = f.size.width >= bounds.size.width * 0.9 && f.size.height >= bounds.size.height * 0.9;
        BOOL topLine = f.size.height <= 1.0 && f.size.width >= bounds.size.width * 0.9;
        if (fullBg || topLine) v.hidden = YES;
    }
    bar.backgroundColor = [UIColor clearColor];

    // 按钮真实矩形（底栏坐标系）——只读，绝不改
    NSMutableArray *contents = [NSMutableArray array];
    CGRect row = CGRectNull;
    for (UIView *b in btns) {
        CGRect f = [bar convertRect:b.bounds fromView:b];
        [contents addObject:[NSValue valueWithCGRect:HPButtonContentRect(bar, b)]];
        row = CGRectIsNull(row) ? f : CGRectUnion(row, f);
    }

    // 胶囊：贴合按钮行——横向 = 行范围左右各扩 12 并夹进 [10, W-10]；纵向高 58、中心对齐行中心、底边不超界
    CGFloat capH = 58.0;
    CGFloat capX = MAX(10.0, row.origin.x - 12);
    CGFloat capR = MIN(bounds.size.width - 10, CGRectGetMaxX(row) + 12);
    CGFloat capY = CGRectGetMidY(row) - capH / 2;
    if (capY < 2) capY = 2;
    if (capY + capH > bounds.size.height - 4) capY = bounds.size.height - 4 - capH;
    CGRect capRect = CGRectMake(capX, capY, capR - capX, capH);
    HPSetPlateFrame(capsule, capRect);

    // 选区透镜（玻璃）：贴选中按钮的内容中心，宽 = 内容宽 + 30（夹在 60..110）
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
    CGFloat lensW = MIN(MAX(cr.size.width + 30, 60.0), 110.0);
    CGFloat lensH = capH - 16;
    HPSetPlateFrame(lens, CGRectMake(CGRectGetMidX(cr) - lensW / 2,
                                     capRect.origin.y + (capH - lensH) / 2, lensW, lensH));
    lens.hidden = NO;

    // 层级：胶囊玻璃 < 透镜玻璃 < 按钮（按钮若在容器里，把容器整体提到透镜之上）
    [bar bringSubviewToFront:lens];
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
    NSLog(@"[HPGlass] v4 install: swiftBar=%@ swiftBtn=%@ objcBar=%@ installed=%d",
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
