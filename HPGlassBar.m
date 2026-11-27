// HPGlassBar.m — 虎扑悬浮底栏 v13.1 (2026-11-27)
// 本版以 v12 为基线（用户指定「那个可用的插件」），只加两件、其余逐字不动：
// ①嫁接 v14 起的场景桥接 HPSceneBridge——现行改包带 UIScene 清单，缺桥接会黑屏；
// ②首页信息流上滑隐藏底栏（下滑或回到顶部恢复；渐隐渐显 + 下沉/回位，0.15 秒快动效；只在首页根页面生效，切 tab/进帖子页强制显示）。
// 沿革：v1 挂错类零反应；v2 挂对 Swift 真底栏但玻璃自拼、槽位自算差 34pt；v3 修位置；v4 照 XHSNative
//   plateOn 配方重做玻璃盘并过滤隐藏 button；v5 按用户定的做法重构按钮层（同 XHSNative 的 rebuildTabs 路线）：
//   自建按钮复制原按钮的图标/标题/颜色/内部布局，原按钮隐藏；点击不走原按钮的触摸，直接调底栏自己的
//   didClickedWithButton:(原按钮) —— 与真实点击同一入口，其后 hp_delegate 的 shouleSelectedAt /
//   willSelectedAt / didSelectedAt、容器 VC 切页、重选刷新全部由 App 原链路完成，插件不碰路由本身。
// 玻璃盘 = XHS 配方：UIVisualEffectView(UIGlassEffect Regular) + UICornerConfiguration capsuleConfiguration
//   + contentView 掩角 + 动态填充（浅 白α.50 / 深 RGB .13,.13,.15 α.50）；选区为无填充玻璃透镜。
// 挂点：HPUITabBar layoutSubviews / updateButtonWithButton:selected:（ObjC 旧栏保留 v4 覆盖式布局兼容）。
// 纯运行时 swizzle + +load 安装，无 substrate 依赖；玻璃类全部动态解析。本文件按 MRC 编写。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static char kCapsuleKey;
static char kLensKey;
static char kSelBtnKey;
static char kRowKey;
static char kRowSigKey;
static char kMyHiddenKey;

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

static id HPGetObj(id obj, NSString *selName) {
    SEL s = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, s);
}

static void HPCollectButtons(UIView *root, Class btnCls, NSMutableArray *out) {
    for (UIView *v in root.subviews) {
        if (btnCls && [v isKindOfClass:btnCls]) [out addObject:v];
        else HPCollectButtons(v, btnCls, out);
    }
}
// 可见性：被本插件隐藏的原按钮（kMyHiddenKey 标记）视为可见；其余按 hidden/alpha/尺寸/位置过滤
static BOOL HPButtonVisible(UIView *bar, UIView *b) {
    if ([objc_getAssociatedObject(b, &kMyHiddenKey) boolValue]) {
        CGRect f0 = [bar convertRect:b.bounds fromView:b];
        return f0.size.width >= 1 && f0.size.height >= 1;
    }
    if (b.hidden || b.alpha < 0.01) return NO;
    UIView *p = b.superview;
    while (p && p != bar) {
        if (p.hidden || p.alpha < 0.01) return NO;
        p = p.superview;
    }
    CGRect f = [bar convertRect:b.bounds fromView:b];
    if (f.size.width < 1 || f.size.height < 1) return NO;
    CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    return CGRectContainsPoint(CGRectInset(bar.bounds, -20, -20), c);
}
static NSArray *HPBarButtons(UIView *bar, Class btnCls) {
    NSMutableArray *all = [NSMutableArray array];
    HPCollectButtons(bar, btnCls, all);
    NSMutableArray *out = [NSMutableArray array];
    for (UIView *b in all) if (HPButtonVisible(bar, b)) [out addObject:b];
    [out sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        CGFloat ax = CGRectGetMidX([bar convertRect:a.bounds fromView:a]);
        CGFloat bx = CGRectGetMidX([bar convertRect:b.bounds fromView:b]);
        return ax < bx ? NSOrderedAscending : (ax > bx ? NSOrderedDescending : NSOrderedSame);
    }];
    return out;
}

// 视图在底栏坐标系中的真实矩形
static CGRect HPRectInBar(UIView *bar, UIView *v) {
    return [bar convertRect:v.bounds fromView:v];
}
// 按钮内容（图标+文字+边框）并集
static CGRect HPButtonContentRect(UIView *bar, UIView *btn) {
    CGRect u = CGRectNull;
    NSArray<NSString *> *names = @[@"label", @"tabImageView", @"tabImageBorderView", @"titleLabel", @"imageView"];
    for (NSString *name in names) {
        UIView *v = HPGetObj(btn, name);
        if (v && [v isKindOfClass:[UIView class]] && [v isDescendantOfView:bar]) {
            CGRect r = HPRectInBar(bar, v);
            if (r.size.width > 0 && r.size.height > 0)
                u = CGRectIsNull(u) ? r : CGRectUnion(u, r);
        }
    }
    if (CGRectIsNull(u)) u = HPRectInBar(bar, btn);
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
// 透镜填充：无填充的玻璃盘在深色下只剩一块黑（采样的是身后胶囊的深色填充），浅色下又几乎看不见；
// 给透镜一层轻动态填充（浅 黑8% / 深 白18%），让它在两种模式下都读得出是高亮
static UIColor *HPLensFillColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark)
            return [UIColor colorWithWhite:1.0 alpha:0.18];
        return [UIColor colorWithWhite:0.0 alpha:0.08];
    }];
}

// 玻璃盘构造（v11 按用户要求恢复 v9 的玻璃版、不用 v10 的毛玻璃）：UIGlassEffect Clear +
// 效果视图自身 layer 圆角裁剪。在 8.1.9 的兼容模式下玻璃不采样背景、渲染为随深浅色变色的
// 不透明片（v7/v9/v10 像素定案），用户知情后仍指定用这版。
// fillKind: 0 无填充 / 2 透镜填充。胶囊（kind 0）返回带投影的外壳视图（tag 1001），内嵌效果视图。
static UIView *HPMakePlate(int fillKind) {
    UIVisualEffect *fx = nil;
    Class glassCls = NSClassFromString(@"UIGlassEffect");
    if (glassCls && [glassCls respondsToSelector:@selector(effectWithStyle:)])
        fx = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, @selector(effectWithStyle:), 1); // Clear
    if (!fx) fx = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:fx];
    v.userInteractionEnabled = NO;
    v.layer.masksToBounds = YES;
    if (fillKind == 2) {
        v.contentView.backgroundColor = HPLensFillColor();
        return v;
    }
    UIView *shell = [[UIView alloc] initWithFrame:CGRectZero];
    shell.backgroundColor = [UIColor clearColor];
    shell.userInteractionEnabled = NO;
    shell.tag = 1001;
    [shell addSubview:v];
    [v release];
    return shell;
}

static void HPSetPlateFrame(UIView *plate, CGRect f) {
    plate.frame = f;
    if (plate.tag == 1001) {
        UIView *fx = plate.subviews.firstObject;
        fx.frame = plate.bounds;
        fx.layer.cornerRadius = f.size.height / 2;
        // 夜间亮边（v12 用户定）：黑色阴影在黑底上显不出来，给胶囊加 0.5pt 淡白边定轮廓；
        // 白天不加（borderWidth 0），保持原样。trait 切换会触发重新布局、边随之刷新。
        BOOL dark = plate.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        fx.layer.borderWidth = dark ? 0.5 : 0.0;
        fx.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    } else {
        plate.layer.cornerRadius = f.size.height / 2;
    }
}

// 胶囊投影：挂在外壳层上（效果视图自身要 masksToBounds 裁剪，投影不能挂它身上）
static void HPApplyCapsuleShadow(UIView *plate) {
    CALayer *l = plate.layer;
    l.shadowColor = [UIColor blackColor].CGColor;
    l.shadowOpacity = 0.22;
    l.shadowRadius = 14;
    l.shadowOffset = CGSizeMake(0, 5);
    l.shadowPath = [UIBezierPath bezierPathWithRoundedRect:plate.bounds
                                              cornerRadius:plate.bounds.size.height / 2].CGPath;
}

#pragma mark - 自建按钮

// 透镜闪现（v11 用户定）：选中透镜不再常驻，只在按下按钮时在该槽位亮起（0.12s 淡入、
// 停留约 0.38s、0.3s 淡出后隐藏）。代数计数防连点时旧的淡出把新闪现掐掉；
// 布局函数见 kLensFlashActiveKey 为真时不碰透镜的 hidden/alpha。
static char kLensFlashGenKey;
static char kLensFlashActiveKey;
static void HPFlashLens(UIView *bar, CGRect lensFrame) {
    UIView *lens = objc_getAssociatedObject(bar, &kLensKey);
    if (!lens) return;
    NSNumber *g = objc_getAssociatedObject(bar, &kLensFlashGenKey);
    NSInteger gen = g ? g.integerValue + 1 : 1;
    objc_setAssociatedObject(bar, &kLensFlashGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kLensFlashActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    HPSetPlateFrame(lens, lensFrame);
    lens.hidden = NO;
    [UIView animateWithDuration:0.12 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ lens.alpha = 1.0; } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.38 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSNumber *cur = objc_getAssociatedObject(bar, &kLensFlashGenKey);
        if (!cur || cur.integerValue != gen) return; // 已被更新的点击接管
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn
                         animations:^{ lens.alpha = 0.0; }
                         completion:^(BOOL finished) {
            NSNumber *cur2 = objc_getAssociatedObject(bar, &kLensFlashGenKey);
            if (cur2 && cur2.integerValue == gen) {
                lens.hidden = YES;
                objc_setAssociatedObject(bar, &kLensFlashActiveKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }];
    });
}

@interface HPGlassButton : UIControl
@property (nonatomic, retain) UIImageView *iconView;
@property (nonatomic, retain) UIImageView *borderView;
@property (nonatomic, retain) UILabel *textLabel;
@property (nonatomic, retain) UIView *badgeDot;
@property (nonatomic, assign) UIView *origButton;
@property (nonatomic, assign) UIView *bar;
@property (nonatomic, retain) UIImage *normalImage;
@property (nonatomic, retain) UIImage *selectedImage;
@property (nonatomic, retain) UIColor *normalColor;
@property (nonatomic, retain) UIColor *selectedColor;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL hpSelected;
- (void)refreshAppearance;
@end

@implementation HPGlassButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];
        _borderView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _borderView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_borderView];
        _textLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _textLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_textLabel];
        _badgeDot = [[UIView alloc] initWithFrame:CGRectZero];
        _badgeDot.hidden = YES;
        _badgeDot.userInteractionEnabled = NO;
        [self addSubview:_badgeDot];
        [self addTarget:self action:@selector(hpTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(hpDown) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(hpUp) forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    }
    return self;
}
- (void)dealloc {
    [_iconView release];
    [_borderView release];
    [_textLabel release];
    [_badgeDot release];
    [_normalImage release];
    [_selectedImage release];
    [_normalColor release];
    [_selectedColor release];
    [_title release];
    [super dealloc];
}
- (void)refreshAppearance {
    UIImage *img = self.hpSelected ? (self.selectedImage ?: self.normalImage) : self.normalImage;
    self.iconView.image = img;
    self.textLabel.text = self.title;
    self.textLabel.textColor = self.hpSelected ? (self.selectedColor ?: self.normalColor) : self.normalColor;
}
- (void)hpDown {
    self.iconView.alpha = 0.55;
    if (self.bar) HPFlashLens(self.bar, CGRectInset(self.frame, 4, 5)); // 焦点只在点击时展示
}
- (void)hpUp { self.iconView.alpha = 1.0; }
- (void)hpTapped {
    self.iconView.alpha = 1.0;
    UIView *bar = self.bar;
    UIView *orig = self.origButton;
    if (bar && orig && [bar respondsToSelector:@selector(didClickedWithButton:)])
        ((void (*)(id, SEL, id))objc_msgSend)(bar, @selector(didClickedWithButton:), orig);
}
@end

// 从原按钮只取数据（标题/两态图标/两态颜色/字体），内部布局用自有固定规格，不再量原按钮的几何：
// 图标框 27pt 居中在上、文字在下成组居中；红点只借原按钮判「有没有」，位置自定于图标右上角。
// （v9 起与原按钮脱钩——v5–v8 的槽位/摆位都量自原按钮，长度与焦点问题反复，系此耦合。）
static void HPSyncGlassButton(HPGlassButton *gb, UIView *bar, UIView *orig) {
    gb.normalImage = HPGetObj(orig, @"normalImage");
    gb.selectedImage = HPGetObj(orig, @"hightlightImage");
    gb.normalColor = HPGetObj(orig, @"normalTitleColor");
    gb.selectedColor = HPGetObj(orig, @"highlightTitleColor");
    gb.title = HPGetObj(orig, @"title");

    CGFloat W = gb.bounds.size.width, H = gb.bounds.size.height;
    CGFloat iconS = 27.0;
    CGRect iconF = CGRectMake((W - iconS) / 2, 7.0, iconS, iconS);
    gb.iconView.frame = iconF;
    UIView *oIcon = HPGetObj(orig, @"tabImageView");
    if (!oIcon) oIcon = HPGetObj(orig, @"imageView");
    gb.iconView.hidden = oIcon ? oIcon.hidden : NO;
    UIView *oLabel = HPGetObj(orig, @"label");
    if (!oLabel) oLabel = HPGetObj(orig, @"titleLabel");
    gb.textLabel.frame = CGRectMake(0, CGRectGetMaxY(iconF) + 2.0, W, 15.0);
    if (oLabel) gb.textLabel.font = [(UILabel *)oLabel font];
    gb.textLabel.hidden = gb.title.length == 0;
    UIView *oBorder = HPGetObj(orig, @"tabImageBorderView");
    if (oBorder && [oBorder isDescendantOfView:bar]) {
        gb.borderView.frame = iconF;
        gb.borderView.image = [(UIImageView *)oBorder image];
        gb.borderView.hidden = oBorder.hidden || gb.borderView.image == nil;
    } else {
        gb.borderView.hidden = YES;
    }
    // 红点：原按钮上有小尺寸可见子视图（非图标/文字/边框）即视为有红点，自画 8pt 点于图标右上
    gb.badgeDot.hidden = YES;
    for (UIView *sub in orig.subviews) {
        if (sub == oIcon || sub == oLabel || sub == oBorder) continue;
        if (sub.hidden || sub.alpha < 0.01) continue;
        if (sub.frame.size.width > 20 || sub.frame.size.height > 20) continue;
        if (sub.frame.size.width < 2 || sub.frame.size.height < 2) continue;
        gb.badgeDot.frame = CGRectMake(CGRectGetMaxX(iconF) - 4.0, iconF.origin.y - 2.0, 8.0, 8.0);
        gb.badgeDot.backgroundColor = sub.backgroundColor ?: [UIColor redColor];
        gb.badgeDot.layer.cornerRadius = 4.0;
        gb.badgeDot.hidden = NO;
        break;
    }
    [gb refreshAppearance];
}


#pragma mark - 首页滑动隐藏底栏（v13.1 新增）
// v13 首版按系统 UITabBarController 找首页，真机无反应：虎扑的标签控制器是 App 自写的，
// 既不是 UITabBarController 子类、bar 的 controller 属性也拿不到它，滚动源根本没绑上。
// v13.1 不再依赖标签控制器类型：沿响应链找托管底栏的 VC、按子 VC 可见性定当前标签页，
// 再叠加插件自己记录的选中序号（选中态钩子所得）把关；VC 路线找不到时整窗兜底扫描。

static char kBarHiddenKey;
static char kFeedObsKey;
static char kFeedSVsKey;
static char kFeedVCKey;
static char kSVLastOffKey;
static char kSelIdxKey;
static char kBindRetryKey;

@interface HPFeedObserver : NSObject
@property (nonatomic, assign) UIView *bar;
@end

static void HPSetBarHidden(UIView *bar, BOOL hidden, BOOL animated) {
    NSNumber *cur = objc_getAssociatedObject(bar, &kBarHiddenKey);
    if (cur && cur.boolValue == hidden) return;
    objc_setAssociatedObject(bar, &kBarHiddenKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // 渐隐渐显 + 下沉/回位，快动效 0.15 秒（用户定）
    CGFloat ty = hidden ? (bar.bounds.size.height + 40.0) : 0.0;
    CGFloat targetAlpha = hidden ? 0.0 : 1.0;
    [UIView animateWithDuration:animated ? 0.15 : 0.0 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         bar.transform = CGAffineTransformMakeTranslation(0, ty);
                         bar.alpha = targetAlpha;
                     }
                     completion:nil];
}

static UIViewController *HPHostVC(UIView *bar) {
    id r = bar;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) return (UIViewController *)r;
        r = [r respondsToSelector:@selector(nextResponder)] ? [r nextResponder] : nil;
    }
    return nil;
}

// 当前停在首页根页面时返回首页根 VC，否则 nil
static UIViewController *HPHomeRootVC(UIView *bar) {
    UIViewController *host = HPHostVC(bar);
    if (!host) return nil;
    UIViewController *active = nil;
    if ([host isKindOfClass:[UITabBarController class]]) {
        UITabBarController *t = (UITabBarController *)host;
        if ([t selectedIndex] != 0) return nil;
        active = [t selectedViewController];
    } else {
        NSArray *kids = [host childViewControllers];
        if (kids.count == 0) return nil;
        for (UIViewController *k in kids) {
            UIView *v = k.view;
            if (v && v.window && !v.hidden && v.alpha > 0.01) { active = k; break; }
        }
        if (!active || active != kids.firstObject) return nil;
    }
    if ([active isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)active;
        if (nav.viewControllers.count > 1) return nil; // 已推入子页面，不在首页根
        return nav.viewControllers.firstObject;
    }
    return active;
}

@implementation HPFeedObserver
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if (![object isKindOfClass:[UIScrollView class]] || !self.bar) return;
    UIScrollView *sv = (UIScrollView *)object;
    NSNumber *selIdx = objc_getAssociatedObject(self.bar, &kSelIdxKey);
    if (selIdx && selIdx.integerValue != 0) return;
    if (!sv.window) return;
    CGFloat y = sv.contentOffset.y;
    NSNumber *last = objc_getAssociatedObject(sv, &kSVLastOffKey);
    CGFloat dy = last ? y - last.doubleValue : 0;
    objc_setAssociatedObject(sv, &kSVLastOffKey, @(y), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (y <= 50) HPSetBarHidden(self.bar, NO, YES);
    else if (dy > 4 && y > 140) HPSetBarHidden(self.bar, YES, YES);
    else if (dy < -4) HPSetBarHidden(self.bar, NO, YES);
}
@end

static void HPCollectFeedSVs(UIView *v, UIView *skip, NSMutableArray *out) {
    if (out.count >= 4 || v == skip) return;
    if ([v isKindOfClass:[UIScrollView class]]) {
        UIScrollView *sv = (UIScrollView *)v;
        CGRect f = sv.frame;
        if (f.size.width >= 200 && f.size.height >= 300 &&
            sv.contentSize.height > f.size.height * 1.15)
            [out addObject:sv];
    }
    for (UIView *s in v.subviews) HPCollectFeedSVs(s, skip, out);
}

static void HPUnbindFeedSVs(UIView *bar, HPFeedObserver *obs) {
    NSMutableArray *bound = objc_getAssociatedObject(bar, &kFeedSVsKey);
    for (UIScrollView *sv in bound) {
        @try { [sv removeObserver:obs forKeyPath:@"contentOffset"]; } @catch (NSException *e) {}
    }
    [bound removeAllObjects];
    objc_setAssociatedObject(bar, &kFeedVCKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static void HPBindFeedScrollViews(UIView *bar) {
    HPFeedObserver *obs = objc_getAssociatedObject(bar, &kFeedObsKey);
    if (!obs) {
        obs = [[HPFeedObserver alloc] init];
        obs.bar = bar;
        objc_setAssociatedObject(bar, &kFeedObsKey, obs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [obs release];
    }
    NSMutableArray *bound = objc_getAssociatedObject(bar, &kFeedSVsKey);
    if (!bound) {
        bound = [NSMutableArray array];
        objc_setAssociatedObject(bar, &kFeedSVsKey, bound, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSNumber *selIdx = objc_getAssociatedObject(bar, &kSelIdxKey);
    BOOL homeTab = !selIdx || selIdx.integerValue == 0;
    UIViewController *rootVC = HPHomeRootVC(bar);
    NSMutableArray *found = [NSMutableArray array];
    if (rootVC && rootVC.view) HPCollectFeedSVs(rootVC.view, nil, found);
    if (found.count == 0 && homeTab && bar.window)
        HPCollectFeedSVs(bar.window, bar, found); // 兜底：整窗找（跳过底栏自身）
    if (found.count == 0) {
        HPUnbindFeedSVs(bar, obs);
        HPSetBarHidden(bar, NO, YES);
        // 还在首页标签却没找到滚动源，多半是信息流数据还没加载完，隔一会重试几次
        NSNumber *rc = objc_getAssociatedObject(bar, &kBindRetryKey);
        NSInteger n = rc ? rc.integerValue : 0;
        if (homeTab && n < 5) {
            objc_setAssociatedObject(bar, &kBindRetryKey, @(n + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ HPBindFeedScrollViews(bar); });
        }
        return;
    }
    objc_setAssociatedObject(bar, &kBindRetryKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIViewController *boundVC = objc_getAssociatedObject(bar, &kFeedVCKey);
    if (boundVC == rootVC && bound.count == found.count) {
        BOOL same = YES;
        for (UIScrollView *sv in found) if (![bound containsObject:sv]) { same = NO; break; }
        if (same) return;
    }
    HPUnbindFeedSVs(bar, obs);
    for (UIScrollView *sv in found) {
        [sv addObserver:obs forKeyPath:@"contentOffset"
                options:NSKeyValueObservingOptionNew context:NULL];
        objc_setAssociatedObject(sv, &kSVLastOffKey, @(sv.contentOffset.y), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bound addObject:sv];
    }
    objc_setAssociatedObject(bar, &kFeedVCKey, rootVC, OBJC_ASSOCIATION_ASSIGN);
}

#pragma mark - 布局（Swift 真底栏：重构按钮层）

static void HPEnsurePlates(UIView *bar) {
    if (objc_getAssociatedObject(bar, &kCapsuleKey)) return;
    UIView *capsule = HPMakePlate(0); // 胶囊无填充：XHS fillForBar 默认仅 noteBottom 为 50、其余（含主页栏）为 0（v7 复查二进制定案）
    [bar insertSubview:capsule atIndex:0];
    objc_setAssociatedObject(bar, &kCapsuleKey, capsule, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIView *lens = HPMakePlate(2);
    [bar insertSubview:lens atIndex:1];
    objc_setAssociatedObject(bar, &kLensKey, lens, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void HPHideBarBackground(UIView *bar, NSArray *btns) {
    UIView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    UIView *lens = objc_getAssociatedObject(bar, &kLensKey);
    NSArray *mine = objc_getAssociatedObject(bar, &kRowKey);
    if ([bar respondsToSelector:@selector(backgroundView)]) {
        UIView *bg = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(backgroundView));
        if (bg && !HPIsAncestorOfAny(bg, btns)) bg.hidden = YES;
    }
    CGRect bounds = bar.bounds;
    for (UIView *v in bar.subviews) {
        if (v == capsule || v == lens) continue;
        if ([mine containsObject:v]) continue;
        if (HPIsAncestorOfAny(v, btns)) continue;
        CGRect f = v.frame;
        BOOL fullBg = f.size.width >= bounds.size.width * 0.9 && f.size.height >= bounds.size.height * 0.9;
        BOOL topLine = f.size.height <= 1.0 && f.size.width >= bounds.size.width * 0.9;
        if (fullBg || topLine) v.hidden = YES;
    }
    bar.backgroundColor = [UIColor clearColor];
}

static void HPLayoutSwiftBar(UIView *bar, Class btnCls) {
    CGRect bounds = bar.bounds;
    if (bounds.size.width < 50 || bounds.size.height < 30) return;
    NSArray *btns = HPBarButtons(bar, btnCls);
    if (btns.count == 0) return;
    HPEnsurePlates(bar);
    HPHideBarBackground(bar, btns);

    // 按钮集合签名（指针序列）变了才重建自建行
    NSMutableString *sig = [NSMutableString string];
    for (UIView *b in btns) [sig appendFormat:@"%p;", (void *)b];
    NSString *oldSig = objc_getAssociatedObject(bar, &kRowSigKey);
    NSMutableArray *row = objc_getAssociatedObject(bar, &kRowKey);
    if (!row || ![sig isEqualToString:oldSig]) {
        if (row) for (HPGlassButton *gb in row) [gb removeFromSuperview];
        row = [NSMutableArray array];
        for (UIView *orig in btns) {
            HPGlassButton *gb = [[HPGlassButton alloc] initWithFrame:CGRectZero];
            gb.origButton = orig;
            gb.bar = bar;
            [bar addSubview:gb];
            [row addObject:gb];
            [gb release];
            objc_setAssociatedObject(orig, &kMyHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(bar, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &kRowSigKey, [sig copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 槽位几何：固定规格（槽宽 86、高 58、端部留白 12），只借原按钮行定纵向位置；宽度只随按钮数变
    CGRect rowRect = CGRectNull;
    for (UIView *orig in btns) {
        CGRect f = HPRectInBar(bar, orig);
        rowRect = CGRectIsNull(rowRect) ? f : CGRectUnion(rowRect, f);
    }
    CGFloat slotW = 86.0;
    CGFloat capH = 58.0;
    CGFloat capW = slotW * (CGFloat)btns.count + 24;
    if (capW > bounds.size.width - 20) {
        capW = bounds.size.width - 20;
        slotW = (capW - 24) / (CGFloat)btns.count;
    }
    CGFloat capX = (bounds.size.width - capW) / 2;
    CGFloat capY = CGRectGetMidY(rowRect) - capH / 2;
    if (capY < 2) capY = 2;
    if (capY + capH > bounds.size.height - 4) capY = bounds.size.height - 4 - capH;
    CGRect capRect = CGRectMake(capX, capY, capW, capH);

    // 同步数据 + 隐藏原按钮
    for (NSUInteger i = 0; i < btns.count; i++) {
        UIView *orig = btns[i];
        HPGlassButton *gb = row[i];
        gb.frame = CGRectMake(capX + 12 + (CGFloat)i * slotW, capY, slotW, capH);
        HPSyncGlassButton(gb, bar, orig);
        orig.hidden = YES;
    }

    // 选中态：以 updateButton 钩子记录的原按钮为准
    UIView *selBtn = objc_getAssociatedObject(bar, &kSelBtnKey);
    NSUInteger sel = selBtn ? [btns indexOfObject:selBtn] : NSNotFound;
    if (sel == NSNotFound) sel = 0;
    objc_setAssociatedObject(bar, &kSelIdxKey, @(sel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSUInteger i = 0; i < row.count; i++) {
        HPGlassButton *gb = row[i];
        BOOL s = (i == sel);
        if (gb.hpSelected != s) { gb.hpSelected = s; [gb refreshAppearance]; }
    }

    // 胶囊 + 透镜：透镜贴合整个槽位（横向内缩 4、纵向内缩 5），不再比按钮小一圈
    UIView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    UIView *lens = objc_getAssociatedObject(bar, &kLensKey);
    HPSetPlateFrame(capsule, capRect);
    HPApplyCapsuleShadow(capsule);
    CGFloat lensH = capH - 10;
    HPSetPlateFrame(lens, CGRectMake(capX + 12 + (CGFloat)sel * slotW + 4,
                                     capY + (capH - lensH) / 2, slotW - 8, lensH));
    // 透镜不常驻：布局只管把它放到选中槽位，显隐由点击闪现控制（闪现中则不干预）
    NSNumber *flashing = objc_getAssociatedObject(bar, &kLensFlashActiveKey);
    if (!flashing.boolValue) { lens.hidden = YES; lens.alpha = 0.0; }

    // 层级：胶囊 < 透镜 < 自建按钮
    [bar bringSubviewToFront:lens];
    for (HPGlassButton *gb in row) [bar bringSubviewToFront:gb];

    HPBindFeedScrollViews(bar); // v13.1：首页滑动隐藏底栏的滚动源绑定
}

#pragma mark - 布局（ObjC 旧栏：v4 覆盖式，仅兼容）

static void HPLayoutObjcBar(UIView *bar, Class btnCls) {
    CGRect bounds = bar.bounds;
    if (bounds.size.width < 50 || bounds.size.height < 30) return;
    NSArray *btns = HPBarButtons(bar, btnCls);
    if (btns.count == 0) return;
    HPEnsurePlates(bar);
    HPHideBarBackground(bar, btns);
    CGRect rowRect = CGRectNull;
    NSMutableArray *contents = [NSMutableArray array];
    for (UIView *b in btns) {
        CGRect f = HPRectInBar(bar, b);
        [contents addObject:[NSValue valueWithCGRect:HPButtonContentRect(bar, b)]];
        rowRect = CGRectIsNull(rowRect) ? f : CGRectUnion(rowRect, f);
    }
    UIView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    UIView *lens = objc_getAssociatedObject(bar, &kLensKey);
    CGFloat capH = 58.0;
    CGFloat capX = MAX(10.0, rowRect.origin.x - 12);
    CGFloat capR = MIN(bounds.size.width - 10, CGRectGetMaxX(rowRect) + 12);
    CGFloat capY = CGRectGetMidY(rowRect) - capH / 2;
    if (capY < 2) capY = 2;
    if (capY + capH > bounds.size.height - 4) capY = bounds.size.height - 4 - capH;
    CGRect capRect = CGRectMake(capX, capY, capR - capX, capH);
    HPSetPlateFrame(capsule, capRect);
    HPApplyCapsuleShadow(capsule);
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
    lens.hidden = YES; // 旧栏无点击拦截点，透镜同样不常驻（与 Swift 栏口径一致）
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
    HPLayoutSwiftBar(self, gSwiftBtnCls);
}
static void HP_SwiftBar_updateButton(UIView *self, SEL _cmd, UIView *btn, BOOL selected) {
    ((void (*)(id, SEL, id, BOOL))gOrigSwiftUpdateBtn)(self, _cmd, btn, selected);
    if (selected && btn) {
        objc_setAssociatedObject(self, &kSelBtnKey, btn, OBJC_ASSOCIATION_ASSIGN);
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
            HPLayoutSwiftBar(self, gSwiftBtnCls);
        } completion:nil];
    }
}
static void HP_ObjcBar_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigObjcLayout)(self, _cmd);
    HPLayoutObjcBar(self, gObjcBtnCls);
}
static void HP_ObjcBar_setSelectedIndex(UIView *self, SEL _cmd, NSInteger idx) {
    ((void (*)(id, SEL, NSInteger))gOrigObjcSetSel)(self, _cmd, idx);
    [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        HPLayoutObjcBar(self, gObjcBtnCls);
    } completion:nil];
}
static void HP_ObjcBar_setupSelectedIndex(UIView *self, SEL _cmd, NSInteger idx) {
    ((void (*)(id, SEL, NSInteger))gOrigObjcSetupSel)(self, _cmd, idx);
    HPLayoutObjcBar(self, gObjcBtnCls);
}
static void HP_ObjcBar_reload(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigObjcReload)(self, _cmd);
    HPLayoutObjcBar(self, gObjcBtnCls);
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
    NSLog(@"[HPGlass] v13.1 install: swiftBar=%@ swiftBtn=%@ objcBar=%@ installed=%d",
          gSwiftBarCls, gSwiftBtnCls, gObjcBarCls, gInstalled);
}

// ===== 场景桥接（v14 新增）：改戳包带 UIScene 清单启动时，App 仍按老式在 AppDelegate 里建 window，
// 没挂到场景上会黑屏（v44 实测）。本类在清单里被指名为场景委托，场景连接时把 AppDelegate 的
// window 挂到该场景并 makeKeyAndVisible。无清单的老包永远不会实例化本类，无副作用。MRC。
@interface HPSceneBridge : NSObject <UISceneDelegate>
@property (nonatomic, retain) UIWindow *window;
@property (nonatomic, retain) NSMutableSet *hpPendingURLs;
@property (nonatomic, retain) NSMutableSet *hpPendingActs;
@property (nonatomic, assign) BOOL hpFlushed;
@end

@implementation HPSceneBridge

- (void)hpFixSafeArea:(UIWindow *)w scene:(UIScene *)scene {
    // App 在场景存在前读到的安全区是 0、顶部按 0 排版被灵动岛压住（v45/v46 实测，
    // 全树重排无效——它读的是启动那一刻的值）。这里用场景的真实状态栏高度补差：
    // 自然安全区涨上来后补差自动收回，不会叠加。
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    UIViewController *root = w.rootViewController;
    if (!root) return;
    CGFloat targetTop = ((UIWindowScene *)scene).statusBarManager.statusBarFrame.size.height;
    if (targetTop <= 0) targetTop = 59;
    CGFloat targetBottom = (w.bounds.size.height >= 812) ? 34 : 0;
    UIEdgeInsets nat = w.safeAreaInsets;
    CGFloat needTop = targetTop - nat.top; if (needTop < 0) needTop = 0;
    CGFloat needBottom = targetBottom - nat.bottom; if (needBottom < 0) needBottom = 0;
    UIEdgeInsets add = root.additionalSafeAreaInsets;
    if (fabs(add.top - needTop) > 0.5 || fabs(add.bottom - needBottom) > 0.5) {
        add.top = needTop; add.bottom = needBottom;
        root.additionalSafeAreaInsets = add;
        NSLog(@"[HPGlass] safe area fix: natural top=%.0f bottom=%.0f -> add top=%.0f bottom=%.0f",
              nat.top, nat.bottom, needTop, needBottom);
    }
}

- (void)hpForwardURL:(NSURL *)url sourceApp:(NSString *)sourceApp {
    if (!url) return;
    id ad = [[UIApplication sharedApplication] delegate];
    SEL sel = @selector(application:openURL:options:);
    if (!ad || ![ad respondsToSelector:sel]) return;
    NSDictionary *opts = sourceApp ? @{UIApplicationOpenURLOptionsSourceApplicationKey: sourceApp} : @{};
    ((BOOL (*)(id, SEL, id, id, id))objc_msgSend)(ad, sel, [UIApplication sharedApplication], url, opts);
    NSLog(@"[HPGlass] bridge forwarded openURL: %@", url);
}

- (void)hpForwardActivity:(NSUserActivity *)act {
    if (!act) return;
    id ad = [[UIApplication sharedApplication] delegate];
    SEL sel = @selector(application:continueUserActivity:restorationHandler:);
    if (!ad || ![ad respondsToSelector:sel]) return;
    ((BOOL (*)(id, SEL, id, id, id))objc_msgSend)(ad, sel, [UIApplication sharedApplication], act,
        (id)^(NSArray *restorableObjects) { (void)restorableObjects; });
    NSLog(@"[HPGlass] bridge forwarded userActivity: %@", act.activityType);
}

// 场景清单一旦声明，系统就不再向 AppDelegate 投递链接/通用链接事件（深链静默失效），
// 而虎扑的分享回跳等正走 AppDelegate 的 openURL——桥接必须转发。冷启动事件先暂存，
// 首次 sceneDidBecomeActive 后统一补发（同一 URL 只发一次，防双发）。
- (void)hpFlushPending {
    if (self.hpFlushed) return;
    self.hpFlushed = YES;
    NSMutableSet *seen = [NSMutableSet set];
    for (UIOpenURLContext *c in [[self.hpPendingURLs copy] autorelease]) {
        NSString *k = c.URL.absoluteString ?: @"";
        if ([seen containsObject:k]) continue;
        [seen addObject:k];
        [self hpForwardURL:c.URL sourceApp:c.options.sourceApplication];
    }
    [self.hpPendingURLs removeAllObjects];
    for (NSUserActivity *a in [[self.hpPendingActs copy] autorelease]) [self hpForwardActivity:a];
    [self.hpPendingActs removeAllObjects];
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts {
    if (!self.hpFlushed) {
        if (!self.hpPendingURLs) self.hpPendingURLs = [NSMutableSet set];
        [self.hpPendingURLs unionSet:URLContexts];
        return;
    }
    for (UIOpenURLContext *c in URLContexts) [self hpForwardURL:c.URL sourceApp:c.options.sourceApplication];
}

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity {
    if (!self.hpFlushed) {
        if (!self.hpPendingActs) self.hpPendingActs = [NSMutableSet set];
        [self.hpPendingActs addObject:userActivity];
        return;
    }
    [self hpForwardActivity:userActivity];
}

- (void)hpAttachWindowToScene:(UIScene *)scene {
    if (![scene isKindOfClass:[UIWindowScene class]]) return;
    if (self.window && self.window.windowScene == (UIWindowScene *)scene) return;
    id appDelegate = [[UIApplication sharedApplication] delegate];
    UIWindow *w = nil;
    if (appDelegate && [appDelegate respondsToSelector:@selector(window)]) {
        w = [appDelegate performSelector:@selector(window)];
    }
    if (!w) w = self.window;
    if (w) {
        w.windowScene = (UIWindowScene *)scene;
        self.window = w;
        [w makeKeyAndVisible];
        NSLog(@"[HPGlass] scene bridge attached window: %@", w);
    }
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (connectionOptions.URLContexts.count) {
        if (!self.hpPendingURLs) self.hpPendingURLs = [NSMutableSet set];
        [self.hpPendingURLs unionSet:connectionOptions.URLContexts];
    }
    if (connectionOptions.userActivities.count) {
        if (!self.hpPendingActs) self.hpPendingActs = [NSMutableSet set];
        [self.hpPendingActs unionSet:connectionOptions.userActivities];
    }
    [self hpAttachWindowToScene:scene];
    if (self.window) [self hpFixSafeArea:self.window scene:scene];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self hpAttachWindowToScene:scene]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self hpAttachWindowToScene:scene]; });
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self hpAttachWindowToScene:scene];
    if (self.window) [self hpFixSafeArea:self.window scene:scene];
    [self hpFlushPending];
}

- (void)dealloc {
    [_window release];
    [_hpPendingURLs release];
    [_hpPendingActs release];
    [super dealloc];
}

@end

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

