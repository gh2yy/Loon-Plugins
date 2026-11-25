// WCBlack.m — 微信深色模式纯黑背景 v1 (2026-11-26)
// 目标包：微信 8.0.80（秋名山大礼包 LC 签名版），插件形式交付，用户自行注入。
// 依据（用户 2026-11-26 两张真机截图逐像素采样）：
//   聊天页背景/导航栏 #111111、会话列表背景 #191919、底部 tab #1D1D1D、聊天底部输入栏 #1C1C1C。
//   气泡 #2C2C2C、置顶/卡片类 #202020 不动，保留层次。
// 方案（不赌单个类名，走颜色层）：
//   1) swizzle -[UIView setBackgroundColor:]：传入色在深色下解析为上述目标灰阶时，
//      替换为动态色——深色返回纯黑 #000000，浅色返回原色浅色解析值（切回浅色模式不残留黑）。
//   2) swizzle UINavigationBar / UITabBar 的 setBarTintColor:，同口径处理系统栏（子页面用系统栏时兜底）。
//   3) 靶向 MMTabBar（已在 8.0.80 二进制中确认存在）：layoutSubviews 后遍历两层子视图，
//      把仍呈目标灰阶的背景强制过一遍替换逻辑，防 tab 内部子视图绕过 setter 的情况。
// 纯运行时 swizzle + +load 安装，无 substrate 依赖（与包内已有 libsubstrate 共存不冲突）。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>

static os_log_t WCLog(void) {
    static os_log_t l; static dispatch_once_t once;
    dispatch_once(&once, ^{ l = os_log_create("com.nova.wcblack", "v1"); });
    return l;
}

// 目标灰阶（深色背景族）：0x11 聊天/导航、0x12 导航下沿、0x19 列表、0x1C 聊天底栏、0x1D 主 tab
static BOOL WCIsTargetGray(CGFloat w) {
    int v = (int)lrint(w * 255.0);
    return v == 0x11 || v == 0x12 || v == 0x19 || v == 0x1C || v == 0x1D;
}

static UITraitCollection *WCDarkTrait(void) {
    return [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark];
}
static UITraitCollection *WCLightTrait(void) {
    return [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight];
}

// 不做指针缓存：瞬时 UIColor 释放后指针可能被复用，缓存判定会误伤；解析本身足够便宜，逐次判定。
static UIColor *WCSubstituteForColor(UIColor *color) {
    if (!color) return nil;
    if (color == [UIColor blackColor] || color == [UIColor clearColor]) return nil;
    UIColor *darkResolved = [color resolvedColorWithTraitCollection:WCDarkTrait()];
    CGFloat dw = 0, dr = 0, dg = 0, db = 0, da = 0;
    BOOL gray = [darkResolved getWhite:&dw alpha:&da];
    if (!gray) { [darkResolved getRed:&dr green:&dg blue:&db alpha:&da]; }
    BOOL target = NO;
    if (da > 0.95) {
        if (gray) target = WCIsTargetGray(dw);
        else if (fabs(dr - dg) < 0.004 && fabs(dg - db) < 0.004) target = WCIsTargetGray(dr);
    }
    if (!target) return nil;
    UIColor *lightResolved = [color resolvedColorWithTraitCollection:WCLightTrait()];
    UIColor *dyn = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? [UIColor blackColor] : lightResolved;
    }];
    return dyn;
}

#pragma mark - Hooks

static IMP gOrigSetBG, gOrigNavBarTint, gOrigTabBarTint, gOrigMMTabLayout;

static void WC_View_setBackgroundColor(UIView *self, SEL _cmd, UIColor *color) {
    UIColor *sub = WCSubstituteForColor(color);
    ((void (*)(id, SEL, id))gOrigSetBG)(self, _cmd, sub ?: color);
}
static void WC_NavBar_setBarTintColor(UINavigationBar *self, SEL _cmd, UIColor *color) {
    UIColor *sub = WCSubstituteForColor(color);
    ((void (*)(id, SEL, id))gOrigNavBarTint)(self, _cmd, sub ?: color);
}
static void WC_TabBar_setBarTintColor(UITabBar *self, SEL _cmd, UIColor *color) {
    UIColor *sub = WCSubstituteForColor(color);
    ((void (*)(id, SEL, id))gOrigTabBarTint)(self, _cmd, sub ?: color);
}

static void WCForceBlackInTree(UIView *root, int depth) {
    if (depth < 0) return;
    for (UIView *v in root.subviews) {
        UIColor *bg = v.backgroundColor;
        if (bg) {
            UIColor *sub = WCSubstituteForColor(bg);
            if (sub) v.backgroundColor = sub; // 走已 hook 的 setter，替代色深色解析为黑、不会二次命中
        }
        WCForceBlackInTree(v, depth - 1);
    }
}
static void WC_MMTabBar_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigMMTabLayout)(self, _cmd);
    UIColor *sub = WCSubstituteForColor(self.backgroundColor);
    if (sub) self.backgroundColor = sub;
    WCForceBlackInTree(self, 2);
}

static IMP WCSwap(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NULL;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { os_log(WCLog(), "[WCBlack] missing %{public}@ on %{public}@", NSStringFromSelector(sel), NSStringFromClass(cls)); return NULL; }
    return method_setImplementation(m, newImp);
}

static BOOL gInstalled = NO;
static void WCInstall(void) {
    if (gInstalled) return;
    gOrigSetBG = WCSwap([UIView class], @selector(setBackgroundColor:), (IMP)WC_View_setBackgroundColor);
    if (!gOrigSetBG) return;
    gOrigNavBarTint = WCSwap([UINavigationBar class], @selector(setBarTintColor:), (IMP)WC_NavBar_setBarTintColor);
    gOrigTabBarTint = WCSwap([UITabBar class], @selector(setBarTintColor:), (IMP)WC_TabBar_setBarTintColor);
    Class mmTab = NSClassFromString(@"MMTabBar");
    if (mmTab) gOrigMMTabLayout = WCSwap(mmTab, @selector(layoutSubviews), (IMP)WC_MMTabBar_layoutSubviews);
    gInstalled = YES;
    os_log(WCLog(), "[WCBlack] v1 installed, MMTabBar=%{public}@", mmTab);
}

@interface WCBlackLoader : NSObject
@end
@implementation WCBlackLoader
+ (void)load {
    WCInstall();
    dispatch_async(dispatch_get_main_queue(), ^{ WCInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ WCInstall(); });
}
@end
