// HPGlassBar.m — 虎扑液态玻璃悬浮底栏 v37-diag (2026-11-27)
// v32：容器路线（用户点选）——不再借系统盘当选中指示：系统盘整盘隐藏，改在原栏内嵌
//   UIGlassContainerEffect 容器，底座与选中药丸都是自己的玻璃（药丸 Regular + interactive），
//   选中态插件自管（点击即定、药丸位置只作程序切换时的跟随校验）。几何与图标管线沿 v31。
// v33（v32 实测两修）：①底板没了——光一个容器效果不渲染底，剩一层灰膜；容器内加回一层
//   Clear 玻璃当底板（与药丸同在 contentView 里才能融合）。②点首页/专区时「我的」闪——
//   排版/跟随读到的系统药丸位置是旧值（隐藏盘内药丸停在上一个槽），把刚点的选中覆盖了
//   一拍；加点击优先窗：点击后 1.2 秒内药丸读数不得与点击结果相左。
// v34（v33 实测两修）：底板已回来；但①「我的」还闪——1.2 秒窗过了之后，排版照样采信停在
//   旧槽的药丸读数、把选中改回去：改「待确认」状态机，点击后药丸读数与点击一致（系统
//   追上了）才解除待确认、恢复采信，期间读数一律不采。②点击时出现两个焦点、一个还畸形——
//   系统盘又活了（疑似新实例，旧的藏了、新的没藏）：畸形那个是系统透镜在目标槽的弹簧
//   中途形变、窜出胶囊上沿（我们的药丸被容器裁剪、物理上出不了胶囊）；改每轮排版全栏
//   扫一遍、所有 PlatterView 实例一律藏，药丸跟随改读最后一个（最新）盘。
// v35（v64 实测回滚）：全藏 PlatterView 把 tab 点击弄死了——用户裁图定案：栏里是两层
//   胶囊叠着，点击焦点在下层（系统盘那层）、不在上层；且多藏的那只盘是 App 切页链路的
//   承重件，藏了就切不动。盘处理整段回滚 v33 原样（只藏 HPFindPlatter 找到的那一只、
//   几何也用它），待确认状态机保留（纯显示逻辑、不碰路由）。双焦点问题改走别的路再议。
// v36（v65 实测三点同源）：①按住滑动时有焦点在栏后面移动；②点首页时「我的」图标闪；
//   ③有规律——按住或点击首页/专区，焦点必先跳进「我的」。逐帧验她的录屏：点首页后药丸
//   先正确落首页、约 0.3 秒后自己弹回「我的」，同时真焦点（波纹透镜）一直在首页那层。
//   定案：栏里两只盘——我们藏的那只里的「药丸」是静态摆设、读数恒为最后一格（「我的」），
//   我们的跟随一直在读它；App 真正的透镜在另一只活盘里，没被藏、在栏后面跟着手指和
//   选中移动，就是那个第二焦点。改法：活盘本身一概不动（承重件），只藏它内部的透镜
//   本体（纯视觉叶子）；跟随源改读这枚活透镜的位置（藏了照样读 frame）。
// v37-diag（v66 实测更差、路线纠正）：点了没选中态、双焦点还在、一个还藏在后面——v36 的
//   「活盘透镜」判断错了：藏的那枚不是真透镜（真焦点不在那只盘里），换的跟随源反而把
//   选中显示弄坏。停止猜结构：本版行为整段回滚 v35，只加一个视图树 HUD——把底栏完整
//   子树（类名/frame/hidden，Lens/Platter 行加 >>> 标记）打出来，点任意 tab 后 0.8 秒
//   自动刷新，右上角小按钮「树」开关。拿到真实层级再定下一版方案。
// v25：以 v14 原码（v45 黄金版、用户实测原生 duang）为底逐字回滚，底栏全部代码一字未动；
//   仅在场景桥接补三件与底栏动效无关的事——深链转发（场景清单会停发 AppDelegate 的
//   openURL/continueUserActivity）、状态栏高度修正、安全区补差（后两件治顶部被灵动岛压）。
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
static char kPlateTreatedKey;
static char kTapSelKey;
static char kPillKey;
static char kPillObsKey;
static char kGridXKey;
static char kGridWKey;
static char kContainerKey;
static char kMyPillKey;
static char kCurSelKey;
static char kCapRectKey;
static char kPillAnimKey;
static char kTapTimeKey;
static char kTapPendingKey;
static char kTreeViewKey;
static char kTreeBtnKey;
static void HPRefreshSelectionFromPill(UIView *bar, BOOL animated);
static void HPRefreshTree(UIView *bar);
static void HPSetSelection(UIView *bar, NSUInteger sel, BOOL animated);
static void HPSchedulePillSync(UIView *bar);
static UIView *HPFindPlatter(UIView *root, int *depthOut, NSString **supOut);
static int gHUDLayoutCalls = 0;
static int gHUDUpdateCalls = 0;


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
    l.shadowOpacity = 0.10;
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
@property (nonatomic, assign) NSInteger hpIndex;
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
}
- (void)hpUp { self.iconView.alpha = 1.0; }
- (void)hpTapped {
    self.iconView.alpha = 1.0;
    UIView *bar = self.bar;
    UIView *orig = self.origButton;
    // v28：点击即选中——把槽位记在栏上。updateButton 钩子切换时根本不响（HUD 实测 ub 只在
    // 启动时响 3 次），图标选中态以后以这份点击记录为准，比任何推断都直接。
    if (bar) {
        // v32：选中态自管——点击当场定选中并驱动自有药丸滑动，不再等任何外部信号。
        // v33：同时记点击时刻——点击优先窗内，系统药丸的读数不许推翻点击结果。
        objc_setAssociatedObject(bar, &kTapSelKey, @(self.hpIndex), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &kTapTimeKey, @([[NSDate date] timeIntervalSince1970]), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &kTapPendingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        HPSetSelection(bar, (NSUInteger)self.hpIndex, YES);
    }
    if (bar && orig && [bar respondsToSelector:@selector(didClickedWithButton:)])
        ((void (*)(id, SEL, id))objc_msgSend)(bar, @selector(didClickedWithButton:), orig);
    // v30/v31：路由回来后等药丸弹簧落定，再按它的位置复核一次
    if (bar) HPSchedulePillSync(bar);
    // v37-diag：点击后 0.8 秒刷新视图树（抓切换落定后的层级）
    if (bar) {
        UIView *b = bar;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ HPRefreshTree(b); });
    }
}
@end

// 从原按钮只取数据（标题/两态图标/两态颜色/字体），内部布局用自有固定规格，不再量原按钮的几何：
// 图标框 27pt 居中在上、文字在下成组居中；红点只借原按钮判「有没有」，位置自定于图标右上角。
// （v9 起与原按钮脱钩——v5–v8 的槽位/摆位都量自原按钮，长度与焦点问题反复，系此耦合。）
// v29 去白底：原按钮给的图标若画在不透明白底上（四角不透明且近白），把亮度转成透明度——
// 白底变透明、黑字形保持不透明、灰边按比例半透明（正好是抗锯齿该有的样子）。
// 四角只要有一角是透明的，就认定是正常透明图标、原样返回，绝不误伤。结果按源图指针缓存。
static UIImage *HPDeWhiteImage(UIImage *img) {
    if (!img) return nil;
    static NSMutableDictionary *cache = nil;
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    NSValue *key = [NSValue valueWithPointer:(const void *)img];
    UIImage *hit = [cache objectForKey:key];
    if (hit) return hit;
    UIImage *result = img;
    CGImageRef cg = img.CGImage;
    if (cg) {
        size_t w = CGImageGetWidth(cg), h = CGImageGetHeight(cg);
        if (w >= 8 && h >= 8 && w <= 240 && h <= 240) {
            NSMutableData *px = [NSMutableData dataWithLength:w * h * 4];
            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef ctx = CGBitmapContextCreate([px mutableBytes], w, h, 8, w * 4, cs,
                                                     kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(cs);
            if (ctx) {
                CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), cg);
                unsigned char *p = (unsigned char *)[px mutableBytes];
                BOOL whiteBacked = YES;
                const size_t cxs[4] = {0, w - 3, 0, w - 3};
                const size_t cys[4] = {0, 0, h - 3, h - 3};
                for (int c = 0; c < 4 && whiteBacked; c++) {
                    int sr = 0, sg = 0, sb = 0, sa = 0;
                    for (size_t yy = 0; yy < 3; yy++) for (size_t xx = 0; xx < 3; xx++) {
                        size_t o = ((cys[c] + yy) * w + (cxs[c] + xx)) * 4;
                        sr += p[o]; sg += p[o + 1]; sb += p[o + 2]; sa += p[o + 3];
                    }
                    if (sa / 9 < 250 || sr / 9 < 235 || sg / 9 < 235 || sb / 9 < 235) whiteBacked = NO;
                }
                if (whiteBacked) {
                    for (size_t i = 0; i < w * h; i++) {
                        size_t o = i * 4;
                        int lum = (p[o] * 299 + p[o + 1] * 587 + p[o + 2] * 114) / 1000;
                        int a = 255 - lum; if (a < 0) a = 0;
                        p[o]     = (unsigned char)(p[o]     * a / 255);
                        p[o + 1] = (unsigned char)(p[o + 1] * a / 255);
                        p[o + 2] = (unsigned char)(p[o + 2] * a / 255);
                        p[o + 3] = (unsigned char)a;
                    }
                    CGImageRef outCG = CGBitmapContextCreateImage(ctx);
                    if (outCG) {
                        result = [UIImage imageWithCGImage:outCG scale:img.scale
                                               orientation:img.imageOrientation];
                        CGImageRelease(outCG);
                    }
                }
                CGContextRelease(ctx);
            }
        }
    }
    [cache setObject:result forKey:key];
    return result;
}

static void HPSyncGlassButton(HPGlassButton *gb, UIView *bar, UIView *orig) {
    gb.normalImage = HPDeWhiteImage(HPGetObj(orig, @"normalImage"));
    gb.selectedImage = HPDeWhiteImage(HPGetObj(orig, @"hightlightImage"));
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
        gb.borderView.hidden = YES;  // v29：边框图不再显示——也是图标白底的嫌疑来源之一
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

#pragma mark - v30 药丸跟随（选中态换源：不再靠点击/钩子推断，直接跟系统药丸本体）

static NSInteger gHPLayCount = 0;
static NSInteger gHPKvoCount = 0;

static void HPApplySel(UIView *bar, NSUInteger sel) {
    NSArray *row = objc_getAssociatedObject(bar, &kRowKey);
    for (NSUInteger i = 0; i < row.count; i++) {
        HPGlassButton *gb = row[i];
        BOOL s = (i == sel);
        if (gb.hpSelected != s) { gb.hpSelected = s; [gb refreshAppearance]; }
    }
}

// 在盘的子树里找药丸本体：槽位大小的视图（排除铺满盘的玻璃背景），取最深、最小的一只
static UIView *HPFindPill(UIView *plate) {
    UIView *best = nil; CGFloat bestArea = CGFLOAT_MAX; NSInteger bestDepth = -1;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:plate];
    NSMutableArray *depths = [NSMutableArray arrayWithObject:@0];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        NSNumber *dn = depths.lastObject; [depths removeLastObject];
        NSInteger dep = dn.integerValue;
        for (UIView *s in v.subviews) { [stack addObject:s]; [depths addObject:@(dep + 1)]; }
        if (v == plate) continue;
        CGRect f = v.frame;
        BOOL full = f.size.width >= plate.bounds.size.width * 0.9 && f.size.height >= plate.bounds.size.height * 0.9;
        if (full) continue;
        if (f.size.width >= 50 && f.size.width <= 135 && f.size.height >= 26 && f.size.height <= 62) {
            CGFloat area = f.size.width * f.size.height;
            if (dep > bestDepth || (dep == bestDepth && area < bestArea)) { best = v; bestDepth = dep; bestArea = area; }
        }
    }
    return best;
}

static void HPShowHUD(UIView *bar) {
    UIWindow *win = bar.window; if (!win) return;
    UILabel *lab = (UILabel *)[win viewWithTag:9901];
    if (!lab) {
        lab = [[UILabel alloc] initWithFrame:CGRectMake(6, 54, 428, 46)];
        lab.tag = 9901; lab.numberOfLines = 2; lab.font = [UIFont systemFontOfSize:10];
        lab.textColor = [UIColor greenColor];
        lab.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        lab.userInteractionEnabled = NO;
        [win addSubview:lab]; [lab release];
    }
    [win bringSubviewToFront:lab];
    UIView *pill = objc_getAssociatedObject(bar, &kPillKey);
    NSString *pillDesc = pill ? [NSString stringWithFormat:@"%@ (%.0f,%.0f,%.0f,%.0f)",
        NSStringFromClass(pill.class), pill.frame.origin.x, pill.frame.origin.y,
        pill.frame.size.width, pill.frame.size.height] : @"none";
    int pd = 0; NSString *ps = nil;
    UIView *plate = HPFindPlatter(bar, &pd, &ps);
    NSMutableString *subs = [NSMutableString string];
    if (plate) for (UIView *s in plate.subviews) {
        [subs appendFormat:@"%@(%.0f,%.0f,%.0f,%.0f) ", NSStringFromClass(s.class),
         s.frame.origin.x, s.frame.origin.y, s.frame.size.width, s.frame.size.height];
        if (subs.length > 140) break;
    }
    NSNumber *tapSel = objc_getAssociatedObject(bar, &kTapSelKey);
    lab.text = [NSString stringWithFormat:@"HP v30 lay#%ld kvo#%ld tap=%@ pill=%@\nsubs: %@",
        (long)gHPLayCount, (long)gHPKvoCount, tapSel ?: @"-", pillDesc, subs];
}

// 系统药丸中心落在哪个槽（纯计算、无副作用）；定位不到返回 -1
static NSInteger HPSelectionFromPill(UIView *bar) {
    UIView *pill = objc_getAssociatedObject(bar, &kPillKey);
    if (!pill || !pill.superview) return -1;
    NSNumber *gx = objc_getAssociatedObject(bar, &kGridXKey);
    NSNumber *gw = objc_getAssociatedObject(bar, &kGridWKey);
    NSArray *row = objc_getAssociatedObject(bar, &kRowKey);
    if (!gx || !gw || !row.count) return -1;
    CGRect pf = [pill.superview convertRect:pill.frame toView:bar];
    CGFloat cx = CGRectGetMidX(pf);
    NSInteger sel = 0; CGFloat bestD = CGFLOAT_MAX;
    for (NSUInteger i = 0; i < row.count; i++) {
        CGFloat c = gx.doubleValue + gw.doubleValue * ((CGFloat)i + 0.5);
        CGFloat dd = fabs(cx - c); if (dd < bestD) { bestD = dd; sel = (NSInteger)i; }
    }
    return sel;
}

// 点击优先窗：刚点击过（1.2 秒内）时返回 YES 并带出点击的槽位。这段时间里系统药丸的
// 位置是旧值（盘被藏后它停在上一个槽，v32 实测点首页/专区时「我的」被它刷亮一拍），
// 任何与点击结果相左的药丸读数都作废；程序切页没有点击、不受此窗影响。
static BOOL HPRecentTap(UIView *bar, NSInteger *tapSelOut) {
    NSNumber *tt = objc_getAssociatedObject(bar, &kTapTimeKey);
    NSNumber *ts = objc_getAssociatedObject(bar, &kTapSelKey);
    if (!tt || !ts) return NO;
    if ([[NSDate date] timeIntervalSince1970] - tt.doubleValue > 1.2) return NO;
    if (tapSelOut) *tapSelOut = ts.integerValue;
    return YES;
}

static void HPRefreshSelectionFromPill(UIView *bar, BOOL animated) {
    NSInteger sel = HPSelectionFromPill(bar);
    if (sel < 0) return;
    // v34 待确认状态机：点击后系统药丸的读数先一律不采，直到它与点击的槽位一致
    // （说明系统追上了）才解除待确认并恢复采信——v33 的 1.2 秒时间窗不够，
    // 窗一过排版就又被停在旧槽的读数把选中改回去（「我的」闪的根源）。
    NSNumber *pend = objc_getAssociatedObject(bar, &kTapPendingKey);
    if (pend.boolValue) {
        NSNumber *ts = objc_getAssociatedObject(bar, &kTapSelKey);
        if (ts && sel == ts.integerValue) {
            objc_setAssociatedObject(bar, &kTapPendingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            HPSetSelection(bar, (NSUInteger)sel, animated);
        }
        return;
    }
    HPSetSelection(bar, (NSUInteger)sel, animated);
}

// 药丸的弹簧是逐帧驱动的，位置变化会连珠炮一样报过来——等它静下来 0.28 秒再对一次，
// 不然图标跟着药丸的过冲来回翻（v30 的「点这个、其他图标在闪」就是这么来的）。
static NSInteger gHPSettleGen = 0;
static void HPSchedulePillSync(UIView *bar) {
    NSInteger gen = ++gHPSettleGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (gen == gHPSettleGen) HPRefreshSelectionFromPill(bar, YES);
    });
}

// v37-diag：底栏视图树 HUD——把子树类名/frame/hidden 打到浮动文本框里，
// Lens/Platter/Glass 行加 >>> 标记。点 tab 后 0.8 秒自动刷新；小按钮「树」开关。
@interface HPTreeHandler : NSObject
@property (nonatomic, assign) UITextView *tv;
- (void)toggle:(id)sender;
@end
@implementation HPTreeHandler
- (void)toggle:(id)sender { self.tv.hidden = !self.tv.hidden; }
@end
static HPTreeHandler *gTreeHandler = nil;
static void HPDumpView(UIView *v, UIView *bar, int depth, NSMutableString *out, int *lines) {
    if (*lines > 220 || depth > 9) return;
    (*lines)++;
    NSMutableString *ind = [NSMutableString string];
    for (int i = 0; i < depth; i++) [ind appendString:@"  "];
    NSString *cls = NSStringFromClass([v class]);
    NSString *mark = ([cls containsString:@"Lens"] || [cls containsString:@"Platter"] ||
                       [cls containsString:@"Glass"] || [cls containsString:@"Liquid"]) ? @">>> " : @"";
    CGRect f = (v == bar) ? v.bounds : [v convertRect:v.bounds toView:bar];
    [out appendFormat:@"%@%@%@ f=(%.0f,%.0f,%.0f,%.0f)%@ a=%.2f\n", ind, mark, cls,
        f.origin.x, f.origin.y, f.size.width, f.size.height,
        v.hidden ? @" HIDDEN" : @"", v.alpha];
    for (UIView *s in v.subviews) HPDumpView(s, bar, depth + 1, out, lines);
}
static void HPRefreshTree(UIView *bar) {
    UITextView *tv = objc_getAssociatedObject(bar, &kTreeViewKey);
    if (!tv) return;
    NSMutableString *out = [NSMutableString stringWithFormat:@"BAR %@ bounds=(%.0f,%.0f)\n",
        NSStringFromClass([bar class]), bar.bounds.size.width, bar.bounds.size.height];
    int lines = 0;
    HPDumpView(bar, bar, 0, out, &lines);
    tv.text = out;
}
static void HPEnsureTreeHUD(UIView *bar) {
    if (objc_getAssociatedObject(bar, &kTreeViewKey)) return;
    UIView *host = bar.superview;
    if (!host) return;
    if (!gTreeHandler) gTreeHandler = [[HPTreeHandler alloc] init];
    UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 60, host.bounds.size.width, 300)];
    tv.backgroundColor = [UIColor colorWithWhite:0 alpha:0.78];
    tv.textColor = [UIColor whiteColor];
    tv.font = [UIFont systemFontOfSize:8];
    tv.editable = NO;
    tv.hidden = YES;
    tv.layer.zPosition = 9998;
    [host addSubview:tv];
    objc_setAssociatedObject(bar, &kTreeViewKey, tv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gTreeHandler.tv = tv;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(host.bounds.size.width - 46, 24, 40, 30);
    [btn setTitle:@"树" forState:UIControlStateNormal];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    btn.layer.cornerRadius = 6;
    btn.layer.zPosition = 9999;
    [btn addTarget:gTreeHandler action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:btn];
    objc_setAssociatedObject(bar, &kTreeBtnKey, btn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    HPRefreshTree(bar);
}

@interface HPSelectionObserver : NSObject
@property (nonatomic, assign) UIView *bar;
@end
@implementation HPSelectionObserver
- (void)observeValueForKeyPath:(NSString *)kp ofObject:(id)obj change:(NSDictionary *)chg context:(void *)ctx {
    (void)kp; (void)obj; (void)chg; (void)ctx;
    UIView *bar = self.bar; if (!bar) return;
    HPSchedulePillSync(bar);
}
@end

#pragma mark - v32 容器路线（UIGlassContainerEffect 内嵌原栏 + 自有药丸）

// 玻璃效果视图（动态解析 UIGlassEffect；style 0=Regular 1=Clear）。返回 +1，调用方持有。
static UIVisualEffectView *HPGlassView(NSInteger style, BOOL interactive) {
    UIVisualEffect *fx = nil;
    Class glassCls = NSClassFromString(@"UIGlassEffect");
    if (glassCls && [glassCls respondsToSelector:@selector(effectWithStyle:)])
        fx = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, @selector(effectWithStyle:), style);
    if (fx && interactive && [fx respondsToSelector:@selector(setInteractive:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(fx, @selector(setInteractive:), YES);
    if (!fx) fx = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:fx];
    v.userInteractionEnabled = NO;
    v.layer.masksToBounds = YES;
    return v;
}

// 容器只建一次：外壳（挂投影）→ UIGlassContainerEffect 视图 → contentView 里放自有药丸。
// 底座就是容器效果本身（照公开示例的做法，不再叠一层独立玻璃免得双份发灰）；
// 自建按钮行由排版函数随后加进 contentView。
static void HPEnsureContainer(UIView *bar) {
    if (objc_getAssociatedObject(bar, &kContainerKey)) return;
    UIView *shell = [[UIView alloc] initWithFrame:CGRectZero];
    shell.backgroundColor = [UIColor clearColor];
    shell.tag = 1002;
    UIVisualEffectView *cont = nil;
    Class contCls = NSClassFromString(@"UIGlassContainerEffect");
    if (contCls) {
        id cfx = [[contCls alloc] init];
        cont = [[UIVisualEffectView alloc] initWithEffect:cfx];
        [cfx release];
    }
    if (!cont) cont = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    cont.layer.masksToBounds = YES;
    [shell addSubview:cont];
    [cont release];
    // v33：底板——v32 只有容器效果本身、不渲染底，只剩一层灰膜（用户实测）。补一层 Clear
    // 玻璃铺满容器当底板，与药丸同住 contentView，容器的融合才有对象。
    UIVisualEffectView *base = HPGlassView(1, NO); // Clear
    base.layer.cornerRadius = 31;
    [cont.contentView addSubview:base];
    [base release];
    UIVisualEffectView *pill = HPGlassView(0, YES); // Regular + interactive（用户定的样本口径）
    pill.layer.cornerRadius = 26;
    [cont.contentView addSubview:pill];
    objc_setAssociatedObject(bar, &kMyPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [pill release];
    [bar insertSubview:shell atIndex:0];
    objc_setAssociatedObject(bar, &kContainerKey, shell, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [shell release];
}

static void HPSetContainerFrame(UIView *shell, CGRect f) {
    if (!shell) return;
    shell.frame = f;
    UIVisualEffectView *cont = (UIVisualEffectView *)shell.subviews.firstObject;
    if (!cont) return;
    cont.frame = shell.bounds;
    cont.layer.cornerRadius = f.size.height / 2;
    // 底板是 contentView 的第一个子视图（HPEnsureContainer 里先于药丸加入）
    UIVisualEffectView *base = (UIVisualEffectView *)cont.contentView.subviews.firstObject;
    if (base) {
        base.frame = cont.bounds;
        base.layer.cornerRadius = f.size.height / 2;
    }
    // 夜间亮边沿 v12 口径：深色给容器 0.5pt 淡白边定轮廓，白天不加
    BOOL dark = shell.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    cont.layer.borderWidth = dark ? 0.5 : 0.0;
    cont.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
}

// 选中态唯一入口：记当前槽、刷按钮两态、把自有药丸放到目标槽（可带弹簧动画）。
// 药丸几何走排版存下的格（栏坐标）减容器原点；动画进行中排版不抢它的 frame。
static void HPSetSelection(UIView *bar, NSUInteger sel, BOOL animated) {
    NSArray *row = objc_getAssociatedObject(bar, &kRowKey);
    if (row.count && sel >= row.count) sel = row.count - 1;
    objc_setAssociatedObject(bar, &kCurSelKey, @(sel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    HPApplySel(bar, sel);
    UIView *pill = objc_getAssociatedObject(bar, &kMyPillKey);
    NSNumber *gx = objc_getAssociatedObject(bar, &kGridXKey);
    NSNumber *gw = objc_getAssociatedObject(bar, &kGridWKey);
    NSValue *capV = objc_getAssociatedObject(bar, &kCapRectKey);
    if (!pill || !gx || !gw || !capV) return;
    CGRect cap = [capV CGRectValue];
    CGRect tf = CGRectMake(gx.doubleValue + gw.doubleValue * (CGFloat)sel + 4 - cap.origin.x,
                           5, gw.doubleValue - 8, cap.size.height - 10);
    pill.layer.cornerRadius = tf.size.height / 2;
    if (animated) {
        objc_setAssociatedObject(bar, &kPillAnimKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [UIView animateWithDuration:0.45 delay:0
             usingSpringWithDamping:0.72 initialSpringVelocity:0.5
             options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
             animations:^{ pill.frame = tf; }
             completion:^(BOOL finished) {
                 (void)finished;
                 objc_setAssociatedObject(bar, &kPillAnimKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
             }];
    } else {
        pill.frame = tf;
    }
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
    UIView *contShell = objc_getAssociatedObject(bar, &kContainerKey);
    NSArray *mine = objc_getAssociatedObject(bar, &kRowKey);
    if ([bar respondsToSelector:@selector(backgroundView)]) {
        UIView *bg = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(backgroundView));
        if (bg && !HPIsAncestorOfAny(bg, btns)) bg.hidden = YES;
    }
    // mixView：虎扑自己的混合层，跟虎扑主题走（浅色白、深色黑）、不跟系统外观——系统深色+
    // 虎扑浅色时它就是栏底下那块白板（用户实测：开虎扑深色后它变黑）。藏掉，少一层轮廓、
    // 也少一层蒙在玻璃上的灰（v15 同处理）。
    if ([bar respondsToSelector:@selector(mixView)]) {
        UIView *mv = ((id (*)(id, SEL))objc_msgSend)(bar, @selector(mixView));
        if (mv && !HPIsAncestorOfAny(mv, btns)) mv.hidden = YES;
    }
    CGRect bounds = bar.bounds;
    for (UIView *v in bar.subviews) {
        if (v == capsule || v == lens || v == contShell) continue;
        if ([mine containsObject:v]) continue;
        if (HPIsAncestorOfAny(v, btns)) continue;
        CGRect f = v.frame;
        BOOL fullBg = f.size.width >= bounds.size.width * 0.9 && f.size.height >= bounds.size.height * 0.9;
        BOOL topLine = f.size.height <= 1.0 && f.size.width >= bounds.size.width * 0.9;
        if (fullBg || topLine) v.hidden = YES;
    }
    bar.backgroundColor = [UIColor clearColor];
}

// 递归找系统选择盘（HUD 实测它就是底栏的直接子视图，递归只是保险）。
static UIView *HPFindPlatter(UIView *root, int *depthOut, NSString **supOut) {
    NSMutableArray *level = [NSMutableArray arrayWithObject:root];
    for (int d = 0; d < 6; d++) {
        NSMutableArray *next = [NSMutableArray array];
        for (UIView *v in level) {
            if (v != root && [NSStringFromClass([v class]) containsString:@"PlatterView"] &&
                v.frame.size.width > 30 && v.frame.size.height > 20) {
                if (depthOut) *depthOut = d;
                if (supOut) *supOut = NSStringFromClass([v.superview class]);
                return v;
            }
            [next addObjectsFromArray:v.subviews];
        }
        level = next;
    }
    return nil;
}
static void HPLayoutSwiftBar(UIView *bar, Class btnCls) {
    CGRect bounds = bar.bounds;
    if (bounds.size.width < 50 || bounds.size.height < 30) return;
    NSArray *btns = HPBarButtons(bar, btnCls);
    if (btns.count == 0) return;
    HPEnsureContainer(bar);
    HPHideBarBackground(bar, btns);

    // 系统选择盘（v32）：整盘隐藏——选中指示改由容器里的自有药丸承担。盘只剩两个用处：
    // 它的框仍是胶囊几何的定案来源（v28)；它内部的药丸在程序切页时仍会移动，
    // KVO 跟随它做程序切换的选中校验。藏视图不影响它内部排版与动画。
    // v35 回滚：v64 把所有 PlatterView 全藏之后 tab 点击失效——多藏的那只盘是 App
    // 切页链路的承重件。此段恢复 v33 原样：只藏找到的那一只、几何也用它。
    int hpPlateDepth = 0;
    NSString *hpPlateSup = @"-";
    UIView *hpPlate = HPFindPlatter(bar, &hpPlateDepth, &hpPlateSup);
    if (hpPlate) hpPlate.hidden = YES;
    CGRect plateInBar = hpPlate ? [bar convertRect:hpPlate.bounds fromView:hpPlate] : CGRectZero;

    // 按钮集合签名（指针序列）变了才重建自建行
    NSMutableString *sig = [NSMutableString string];
    for (UIView *b in btns) [sig appendFormat:@"%p;", (void *)b];
    NSString *oldSig = objc_getAssociatedObject(bar, &kRowSigKey);
    NSMutableArray *row = objc_getAssociatedObject(bar, &kRowKey);
    if (!row || ![sig isEqualToString:oldSig]) {
        if (row) for (HPGlassButton *gb in row) [gb removeFromSuperview];
        row = [NSMutableArray array];
        UIView *contShell = objc_getAssociatedObject(bar, &kContainerKey);
        UIVisualEffectView *cont = (UIVisualEffectView *)contShell.subviews.firstObject;
        for (UIView *orig in btns) {
            HPGlassButton *gb = [[HPGlassButton alloc] initWithFrame:CGRectZero];
            gb.origButton = orig;
            gb.bar = bar;
            [cont.contentView addSubview:gb];
            [row addObject:gb];
            [gb release];
            objc_setAssociatedObject(orig, &kMyHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(bar, &kRowKey, row, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &kRowSigKey, [sig copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // 槽位几何（v26 改）：按原按钮行实测。系统选择盘照原按钮框生成，v25 的固定 86/58 与它
    // 差着几 pt、两条轮廓错开就是「双层」；同源之后盘、透镜、自建按钮共用一套槽位。
    // 实测不可信（槽宽过窄/总宽超界）时整段回落 v25 固定规格。
    CGRect rowRect = CGRectNull;
    for (UIView *orig in btns) {
        CGRect f = HPRectInBar(bar, orig);
        rowRect = CGRectIsNull(rowRect) ? f : CGRectUnion(rowRect, f);
    }
    CGFloat slotW = rowRect.size.width / (CGFloat)btns.count;
    CGFloat capH = rowRect.size.height + 10;
    CGFloat capW = rowRect.size.width + 24;
    BOOL measured = (slotW >= 40 && capW <= bounds.size.width - 20 && rowRect.size.height >= 30);
    if (!measured) {
        slotW = 86.0; capH = 58.0; capW = slotW * (CGFloat)btns.count + 24;
        if (capW > bounds.size.width - 20) {
            capW = bounds.size.width - 20;
            slotW = (capW - 24) / (CGFloat)btns.count;
        }
    }
    CGFloat capX = measured ? (CGRectGetMinX(rowRect) - 12) : ((bounds.size.width - capW) / 2);
    CGFloat slotX0 = measured ? CGRectGetMinX(rowRect) : (capX + 12);
    CGFloat capY = CGRectGetMidY(rowRect) - capH / 2;
    if (capY < 2) capY = 2;
    if (capY + capH > bounds.size.height - 4) capY = bounds.size.height - 4 - capH;
    CGRect capRect = CGRectMake(capX, capY, capW, capH);
    // v28 治双层：HUD 实测系统盘是 (83,0,274,62)、我的胶囊是 (79,2,282,58)——两只近乎同大的
    // 圆角框错开 (4,-2) 叠在一起，两条轮廓全程贴着跑，就是「双层」。盘的框是常量（两次 HUD
    // 读数一致），胶囊直接取盘的框，两条轮廓并成一条；盘的 frame/动画一概不碰。
    if (hpPlate && plateInBar.size.width >= 200 && plateInBar.size.width <= 400 &&
        plateInBar.size.height >= 40 && plateInBar.size.height <= 80) {
        capRect = plateInBar;
        capX = capRect.origin.x; capY = capRect.origin.y; capW = capRect.size.width; capH = capRect.size.height;
    }
    // v30：存槽位格（药丸跟随换算用）+ 药丸定位/观察 + 盘背景玻璃换 Clear（去灰，只做一次）
    objc_setAssociatedObject(bar, &kGridXKey, @(slotX0), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kGridWKey, @(slotW), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (hpPlate) {
        UIView *pill = HPFindPill(hpPlate);
        UIView *oldPill = objc_getAssociatedObject(bar, &kPillKey);
        if (pill != oldPill) {
            HPSelectionObserver *obs = objc_getAssociatedObject(bar, &kPillObsKey);
            if (!obs) {
                obs = [[HPSelectionObserver alloc] init];
                obs.bar = bar;
                objc_setAssociatedObject(bar, &kPillObsKey, obs, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [obs release];
            }
            if (oldPill) {
                [oldPill removeObserver:obs forKeyPath:@"frame"];
                [oldPill removeObserver:obs forKeyPath:@"center"];
                [oldPill removeObserver:obs forKeyPath:@"bounds"];
            }
            if (pill) {
                [pill addObserver:obs forKeyPath:@"frame" options:0 context:NULL];
                [pill addObserver:obs forKeyPath:@"center" options:0 context:NULL];
                [pill addObserver:obs forKeyPath:@"bounds" options:0 context:NULL];
            }
            objc_setAssociatedObject(bar, &kPillKey, pill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (pill) HPRefreshSelectionFromPill(bar, NO);
    }
    // v30 对中：按钮格回 v14 的实测格（slotX0/slotW，盘覆盖不许动它）——v28 挪成 138、
    // v29 挪成盘三分格 128.7，她两次都判不居中；v45/v56 用的就是这套格、当时没这条意见。

    // 同步数据 + 隐藏原按钮（按钮住在容器 contentView 里，frame 用容器坐标 = 栏坐标 - 胶囊原点）
    for (NSUInteger i = 0; i < btns.count; i++) {
        UIView *orig = btns[i];
        HPGlassButton *gb = row[i];
        gb.frame = measured ? CGRectMake(slotX0 + (CGFloat)i * slotW - capX, rowRect.origin.y - capY, slotW, rowRect.size.height)
                            : CGRectMake(slotX0 + (CGFloat)i * slotW - capX, 2, slotW, capH - 4);
        gb.hpIndex = (NSInteger)i;
        HPSyncGlassButton(gb, bar, orig);
        orig.hidden = YES;
    }

    // 选中态（v32）：自管。排版时的优先级：系统药丸位置（程序切页的权威值）> 点击记录 >
    // 上次状态 > 0；定下后按钮两态与自有药丸位置都由 HPSetSelection 一并落位。
    objc_setAssociatedObject(bar, &kCapRectKey, [NSValue valueWithCGRect:capRect], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSNumber *tapSel = objc_getAssociatedObject(bar, &kTapSelKey);
    NSInteger selNow = -1;
    // v34 待确认：点击后、系统还没追上之前，排版一律以点击的槽位为准
    NSNumber *pend = objc_getAssociatedObject(bar, &kTapPendingKey);
    if (pend.boolValue && tapSel && tapSel.unsignedIntegerValue < row.count) {
        selNow = tapSel.integerValue;
        if (HPSelectionFromPill(bar) == selNow)
            objc_setAssociatedObject(bar, &kTapPendingKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (selNow < 0) selNow = HPSelectionFromPill(bar);
    if (selNow < 0 && tapSel && tapSel.unsignedIntegerValue < row.count) selNow = tapSel.integerValue;
    if (selNow < 0) {
        NSNumber *cur = objc_getAssociatedObject(bar, &kCurSelKey);
        if (cur && cur.unsignedIntegerValue < row.count) selNow = cur.integerValue;
    }
    if (selNow < 0) selNow = 0;

    // 容器落位 + 投影；自有药丸在没有动画进行时由 HPSetSelection 瞬时归位（动画中不抢 frame）
    UIView *contShell = objc_getAssociatedObject(bar, &kContainerKey);
    HPSetContainerFrame(contShell, capRect);
    HPApplyCapsuleShadow(contShell);
    NSNumber *anim = objc_getAssociatedObject(bar, &kPillAnimKey);
    if (!anim.boolValue) HPSetSelection(bar, (NSUInteger)selNow, NO);
    else HPApplySel(bar, (NSUInteger)selNow);
    [bar bringSubviewToFront:contShell];
    HPEnsureTreeHUD(bar); // v37-diag
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
    gHUDUpdateCalls++;
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
    NSLog(@"[HPGlass] v37-diag install: swiftBar=%@ swiftBtn=%@ objcBar=%@ installed=%d",
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

