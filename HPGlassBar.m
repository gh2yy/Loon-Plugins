// HPGlassBar.m — 虎扑液态玻璃悬浮底栏 v5 (2026-11-26)
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
static BOOL gInSpringSync = NO; // 弹簧动画中的同步才许动透镜 frame，普通布局同步不许抢
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
            return [UIColor colorWithWhite:1.0 alpha:0.22];
        return [UIColor colorWithWhite:0.0 alpha:0.16];
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
    l.shadowOpacity = 0.14;
    l.shadowRadius = 10;
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
// v22：透镜显形管理（只管 hidden/alpha 与代数，不再瞬移 frame——位置由 updateButton 的弹簧同步驱动，
// 这样点选时透镜是「滑」到目标槽而不是先瞬移再假装滑；重选当前 tab 时它就在原地亮一下，正合焦点语义）
static void HPShowLens(UIView *host, NSTimeInterval hold) {
    UIView *lens = objc_getAssociatedObject(host, &kLensKey);
    if (!lens) return;
    NSNumber *g = objc_getAssociatedObject(host, &kLensFlashGenKey);
    NSInteger gen = g ? g.integerValue + 1 : 1;
    objc_setAssociatedObject(host, &kLensFlashGenKey, @(gen), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host, &kLensFlashActiveKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    lens.hidden = NO;
    [UIView animateWithDuration:0.12 delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ lens.alpha = 1.0; } completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(hold * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSNumber *cur = objc_getAssociatedObject(host, &kLensFlashGenKey);
        if (!cur || cur.integerValue != gen) return;
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn
                         animations:^{ lens.alpha = 0.0; }
                         completion:^(BOOL finished) {
            NSNumber *cur2 = objc_getAssociatedObject(host, &kLensFlashGenKey);
            if (cur2 && cur2.integerValue == gen) {
                lens.hidden = YES;
                objc_setAssociatedObject(host, &kLensFlashActiveKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
@property (nonatomic, assign) UIView *hostView;
@property (nonatomic, retain) UIImage *normalImage;
@property (nonatomic, retain) UIImage *selectedImage;
@property (nonatomic, retain) UIImage *snapNormal;
@property (nonatomic, retain) UIImage *snapSelected;
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
    [_snapNormal release];
    [_snapSelected release];
    [_normalColor release];
    [_selectedColor release];
    [_title release];
    [super dealloc];
}
- (void)refreshAppearance {
    UIImage *img = self.hpSelected ? (self.snapSelected ?: self.selectedImage ?: self.snapNormal ?: self.normalImage)
                                   : (self.snapNormal ?: self.normalImage);
    self.iconView.image = img;
    self.textLabel.text = self.title;
    self.textLabel.textColor = self.hpSelected ? (self.selectedColor ?: self.normalColor) : self.normalColor;
}
- (void)hpDown {
    self.iconView.alpha = 0.55;
    if (self.hostView) HPShowLens(self.hostView, 0.95); // 焦点只在点击时展示
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

// v22：图标改走层快照——把原按钮图标视图的实际渲染截下来用，像素级照搬 App 自己的画法
//（借属性里的 UIImage 会丢掉它内部的着色/合成，用户实测图标不对）。按状态各存一份，源图指针变了才重截。
static char kSnapNormSrcKey;
static char kSnapSelSrcKey;
static UIImage *HPSnapshotView(UIView *v) {
    CGSize sz = v.bounds.size;
    if (sz.width < 2 || sz.height < 2) return nil;
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
    [v.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

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
    UIView *oIcon = HPGetObj(orig, @"tabImageView");
    if (!oIcon) oIcon = HPGetObj(orig, @"imageView");
    gb.iconView.hidden = oIcon ? oIcon.hidden : NO;
    // 层快照采集：原按钮当前处于哪个状态就截哪个状态（选中态由栏的 kSelBtnKey 判定）
    BOOL origIsSel = (objc_getAssociatedObject(bar, &kSelBtnKey) == orig);
    if (oIcon && [oIcon isKindOfClass:[UIImageView class]]) {
        UIImage *srcImg = [(UIImageView *)oIcon image];
        char *srcKey = origIsSel ? &kSnapSelSrcKey : &kSnapNormSrcKey;
        if (srcImg && objc_getAssociatedObject(gb, srcKey) != (id)srcImg) {
            UIImage *snap = HPSnapshotView(oIcon);
            if (snap) {
                if (origIsSel) gb.snapSelected = snap; else gb.snapNormal = snap;
                objc_setAssociatedObject(gb, srcKey, srcImg, OBJC_ASSOCIATION_ASSIGN);
            }
        }
    }
    UIImage *snapForState = origIsSel ? (gb.snapSelected ?: gb.snapNormal) : gb.snapNormal;
    if (snapForState) {
        CGSize ss = snapForState.size;
        if (ss.width > 1 && ss.height > 1 && ss.width <= 44 && ss.height <= 44)
            iconF = CGRectMake((W - ss.width) / 2, 7.0 + (iconS - ss.height) / 2, ss.width, ss.height);
    }
    gb.iconView.frame = iconF;
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
    // mixView：App 自己的混合层（v45 实测它在胶囊下留了一层灰底、还把玻璃蒙灰），一并隐藏
    if ([bar respondsToSelector:@selector(mixView)]) {
        UIView *mv = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(mixView));
        if (mv && !HPIsAncestorOfAny(mv, btns)) mv.hidden = YES;
    }
    // 白名单（v17）：底栏里只许有原按钮、自建行和玻璃。App 在 Loon 砍掉 tab 后会重建底栏、
    // 把自带的灰底胶囊（宽度约栏宽 78%、躲过旧的尺寸过滤）铺回来垫在玻璃下面成双层——
    // 不再按尺寸猜，非按钮非我方的一律藏。
    for (UIView *v in [bar.subviews copy]) {
        if (v == capsule || v == lens) continue;
        if ([mine containsObject:v]) continue;
        if ([btns containsObject:v]) continue;
        if (HPIsAncestorOfAny(v, btns)) continue;
        v.hidden = YES;
    }
    bar.backgroundColor = [UIColor clearColor];
    // 栏外同级底板：App 也可能把底板铺在栏的父视图里、垫在栏身后（尺寸与栏相仿、居于栏内）
    UIView *sup = bar.superview;
    if (sup) {
        CGRect bf = bar.frame;
        NSArray *sibs = sup.subviews;
        NSUInteger bi = [sibs indexOfObject:bar];
        if (bi != NSNotFound) {
            for (NSUInteger i = 0; i < bi; i++) {
                UIView *v = sibs[i];
                if (HPIsAncestorOfAny(v, btns)) continue;
                CGRect f = v.frame;
                BOOL sized = f.size.width >= bf.size.width * 0.4 && f.size.width <= bf.size.width * 1.05 &&
                             f.size.height >= bf.size.height * 0.4 && f.size.height <= bf.size.height * 1.3;
                BOOL centered = CGRectContainsPoint(bf, CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f)));
                if (sized && centered) v.hidden = YES;
            }
        }
    }
}

// v21 重构（用户定）：玻璃栏整体搬出原底栏——自有悬浮层盖在原栏位置、原栏整栏隐藏
//（系统 platter、背景、mixView 全在原栏里，一并消失，不再逐个打地鼠）；
// 自建按钮住在悬浮层里，点击仍调原栏 didClickedWithButton:(原按钮) 走原路由。
static char kOverlayKey;
static UIView *HPOverlayForBar(UIView *bar) {
    UIView *ov = objc_getAssociatedObject(bar, &kOverlayKey);
    if (!ov) {
        ov = [[UIView alloc] initWithFrame:bar.frame];
        ov.backgroundColor = [UIColor clearColor];
        objc_setAssociatedObject(bar, &kOverlayKey, ov, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [ov release];
        ov = objc_getAssociatedObject(bar, &kOverlayKey);
    }
    UIView *sup = bar.superview;
    if (sup && ov.superview != sup) {
        [ov removeFromSuperview];
        NSUInteger idx = [sup.subviews indexOfObject:bar];
        if (idx != NSNotFound) [sup insertSubview:ov atIndex:idx + 1];
        else [sup addSubview:ov];
    }
    if (sup) [sup bringSubviewToFront:ov];
    ov.frame = bar.frame;
    return ov;
}

static void HPSyncOverlayBar(UIView *bar, Class btnCls) {
    CGRect bounds = bar.bounds;
    if (bounds.size.width < 50 || bounds.size.height < 30) return;
    if (!bar.superview) return;
    NSArray *btns = HPBarButtons(bar, btnCls);
    if (btns.count == 0) return;
    UIView *host = HPOverlayForBar(bar);
    HPEnsurePlates(host);

    NSMutableString *sig = [NSMutableString string];
    for (UIView *b in btns) [sig appendFormat:@"%p;", (void *)b];
    NSString *oldSig = objc_getAssociatedObject(host, &kRowSigKey);
    NSMutableArray *row = objc_getAssociatedObject(host, &kRowKey);
    if (!row || ![sig isEqualToString:oldSig]) {
        if (row) for (HPGlassButton *gb in row) [gb removeFromSuperview];
        row = [NSMutableArray array];
        for (UIView *orig in btns) {
            HPGlassButton *gb = [[HPGlassButton alloc] initWithFrame:CGRectZero];
            gb.origButton = orig;
            gb.bar = bar;
            gb.hostView = host;
            [host addSubview:gb];
            [row addObject:gb];
            [gb release];
            objc_setAssociatedObject(orig, &kMyHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(host, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(host, &kRowSigKey, [sig copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

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

    for (NSUInteger i = 0; i < btns.count; i++) {
        UIView *orig = btns[i];
        HPGlassButton *gb = row[i];
        gb.frame = CGRectMake(capX + 12 + (CGFloat)i * slotW, capY, slotW, capH);
        HPSyncGlassButton(gb, bar, orig);
    }

    UIView *selBtn = objc_getAssociatedObject(bar, &kSelBtnKey);
    NSUInteger sel = selBtn ? [btns indexOfObject:selBtn] : NSNotFound;
    if (sel == NSNotFound) sel = 0;
    for (NSUInteger i = 0; i < row.count; i++) {
        HPGlassButton *gb = row[i];
        BOOL s = (i == sel);
        if (gb.hpSelected != s) { gb.hpSelected = s; [gb refreshAppearance]; }
    }

    UIView *capsule = objc_getAssociatedObject(host, &kCapsuleKey);
    UIView *lens = objc_getAssociatedObject(host, &kLensKey);
    HPSetPlateFrame(capsule, capRect);
    HPApplyCapsuleShadow(capsule);
    CGFloat lensH = capH - 10;
    BOOL flashing = [objc_getAssociatedObject(host, &kLensFlashActiveKey) boolValue];
    if (!flashing || gInSpringSync) {
        HPSetPlateFrame(lens, CGRectMake(capX + 12 + (CGFloat)sel * slotW + 4,
                                         capY + (capH - lensH) / 2, slotW - 8, lensH));
    }
    if (!flashing) { lens.hidden = YES; lens.alpha = 0.0; }

    [host bringSubviewToFront:lens];
    for (HPGlassButton *gb in row) [host bringSubviewToFront:gb];

    bar.hidden = YES; // 原栏整栏隐藏：platter/背景/mixView 随它一起消失
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
    HPSyncOverlayBar(self, gSwiftBtnCls);
}
static void HP_SwiftBar_updateButton(UIView *self, SEL _cmd, UIView *btn, BOOL selected) {
    ((void (*)(id, SEL, id, BOOL))gOrigSwiftUpdateBtn)(self, _cmd, btn, selected);
    if (selected && btn) {
        objc_setAssociatedObject(self, &kSelBtnKey, btn, OBJC_ASSOCIATION_ASSIGN);
        UIView *host = objc_getAssociatedObject(self, &kOverlayKey);
        if (host) HPShowLens(host, 1.05); // 透镜先显形，再由下面的弹簧同步把它滑到新槽
        gInSpringSync = YES;
        [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0.6
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ HPSyncOverlayBar(self, gSwiftBtnCls); }
                         completion:^(BOOL finished) { gInSpringSync = NO; }];
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

static CGRect (*gOrigStatusBarFrame)(id, SEL) = NULL;
static CGRect HP_UIApp_statusBarFrame(id self, SEL _cmd) {
    UIApplication *app = (UIApplication *)self;
    for (UIScene *s in app.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            return ((UIWindowScene *)s).statusBarManager.statusBarFrame;
        }
    }
    CGRect orig = gOrigStatusBarFrame ? gOrigStatusBarFrame(self, _cmd) : CGRectZero;
    if (orig.size.height > 0) return orig;
    // 场景还没连上时系统给 0；App 启动时读到 0 就会把顶部排到灵动岛下面，先按机型给真值兜底
    CGFloat h = (UIScreen.mainScreen.bounds.size.height >= 852) ? 59 : 44;
    return CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, h);
}

static BOOL gInstalled = NO;
static void HPInstall(void) {
    if (!gOrigStatusBarFrame) {
        gOrigStatusBarFrame = (CGRect (*)(id, SEL))HPSwap([UIApplication class],
            @selector(statusBarFrame), (IMP)HP_UIApp_statusBarFrame);
    }
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
    NSLog(@"[HPGlass] v22 install: swiftBar=%@ swiftBtn=%@ objcBar=%@ installed=%d",
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

// 场景清单一旦声明，系统就不再向 AppDelegate 投递链接/通用链接事件（掘金适配清单的「深链静默失效」），
// 而虎扑的分享回跳等正走 AppDelegate 的 openURL——桥接必须转发。冷启动的事件在 willConnect 就到达、
// 业务还没就绪，先暂存，首次 sceneDidBecomeActive 后统一补发（同一 URL 只发一次，防双发）。
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
    id appDelegate = [[UIApplication sharedApplication] delegate];
    UIWindow *w = self.window;
    if (!w && appDelegate && [appDelegate respondsToSelector:@selector(window)]) {
        w = [appDelegate performSelector:@selector(window)];
    }
    if (!w) return;
    if (w.windowScene != (UIWindowScene *)scene) {
        w.windowScene = (UIWindowScene *)scene;
        self.window = w;
        [w makeKeyAndVisible];
        NSLog(@"[HPGlass] scene bridge attached window: %@", w);
    }
    [self hpFixSafeArea:w scene:scene];
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self hpAttachWindowToScene:scene]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self hpAttachWindowToScene:scene]; });
}

- (void)sceneDidBecomeActive:(UIScene *)scene {
    [self hpAttachWindowToScene:scene];
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

