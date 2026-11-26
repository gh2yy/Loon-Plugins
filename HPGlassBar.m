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

// 玻璃盘构造（v8 改回 v2 已在真机验证会采样背景的构造）：Clear 玻璃 + 效果视图自身 layer 圆角裁剪。
// 教训：v4 起照 XHS 用 UICornerConfiguration + contentView 掩角，在虎扑里渲染成不透明（v7 浅色截图：
// 压在深色照片上仍是纯白 255、无任何透过）——XHS 的盘活在它自家 App 的玻璃体系里，虎扑没有这层环境。
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
- (void)hpDown { self.iconView.alpha = 0.55; }
- (void)hpUp { self.iconView.alpha = 1.0; }
- (void)hpTapped {
    self.iconView.alpha = 1.0;
    UIView *bar = self.bar;
    UIView *orig = self.origButton;
    if (bar && orig && [bar respondsToSelector:@selector(didClickedWithButton:)])
        ((void (*)(id, SEL, id))objc_msgSend)(bar, @selector(didClickedWithButton:), orig);
}
@end

// 从原按钮同步数据到自建按钮；内部布局按原内容并集整体平移 (dx,dy) 后居中进槽位
// （每轮布局都同步，远程图标迟到也能跟上）
static void HPSyncGlassButton(HPGlassButton *gb, UIView *bar, UIView *orig, CGFloat dx, CGFloat dy) {
    gb.normalImage = HPGetObj(orig, @"normalImage");
    gb.selectedImage = HPGetObj(orig, @"hightlightImage");
    gb.normalColor = HPGetObj(orig, @"normalTitleColor");
    gb.selectedColor = HPGetObj(orig, @"highlightTitleColor");
    gb.title = HPGetObj(orig, @"title");

    CGRect of = gb.frame;
    UIView *oIcon = HPGetObj(orig, @"tabImageView");
    if (!oIcon) oIcon = HPGetObj(orig, @"imageView");
    UIView *oLabel = HPGetObj(orig, @"label");
    if (!oLabel) oLabel = HPGetObj(orig, @"titleLabel");
    UIView *oBorder = HPGetObj(orig, @"tabImageBorderView");
    if (oIcon && [oIcon isDescendantOfView:bar]) {
        CGRect r = HPRectInBar(bar, oIcon);
        gb.iconView.frame = CGRectMake(r.origin.x + dx - of.origin.x, r.origin.y + dy - of.origin.y, r.size.width, r.size.height);
        gb.iconView.hidden = oIcon.hidden;
    }
    if (oLabel && [oLabel isDescendantOfView:bar]) {
        CGRect r = HPRectInBar(bar, oLabel);
        gb.textLabel.frame = CGRectMake(r.origin.x + dx - of.origin.x, r.origin.y + dy - of.origin.y, r.size.width, r.size.height);
        gb.textLabel.font = [(UILabel *)oLabel font];
        gb.textLabel.hidden = oLabel.hidden || gb.title.length == 0;
    } else {
        gb.textLabel.hidden = YES;
    }
    if (oBorder && [oBorder isDescendantOfView:bar]) {
        CGRect r = HPRectInBar(bar, oBorder);
        gb.borderView.frame = CGRectMake(r.origin.x + dx - of.origin.x, r.origin.y + dy - of.origin.y, r.size.width, r.size.height);
        gb.borderView.image = [(UIImageView *)oBorder image];
        gb.borderView.hidden = oBorder.hidden || gb.borderView.image == nil;
    } else {
        gb.borderView.hidden = YES;
    }
    // 红点镜像：原按钮上除图标/文字/边框外的小尺寸可见子视图
    gb.badgeDot.hidden = YES;
    for (UIView *sub in orig.subviews) {
        if (sub == oIcon || sub == oLabel || sub == oBorder) continue;
        if (sub.hidden || sub.alpha < 0.01) continue;
        if (sub.frame.size.width > 20 || sub.frame.size.height > 20) continue;
        if (sub.frame.size.width < 2 || sub.frame.size.height < 2) continue;
        CGRect r = HPRectInBar(bar, sub);
        gb.badgeDot.frame = CGRectMake(r.origin.x + dx - of.origin.x, r.origin.y + dy - of.origin.y, r.size.width, r.size.height);
        gb.badgeDot.backgroundColor = sub.backgroundColor ?: [UIColor redColor];
        gb.badgeDot.layer.cornerRadius = MIN(r.size.width, r.size.height) / 2;
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

    // 槽位几何：按内容宽度定槽，胶囊只包住槽位组并居中——按钮少时不再拉满整宽（照 XHS 重构后的自适应长度）
    NSMutableArray *contents = [NSMutableArray array];
    CGFloat maxContentW = 0;
    CGRect rowRect = CGRectNull;
    for (UIView *orig in btns) {
        CGRect cr = HPButtonContentRect(bar, orig);
        [contents addObject:[NSValue valueWithCGRect:cr]];
        if (cr.size.width > maxContentW) maxContentW = cr.size.width;
        CGRect f = HPRectInBar(bar, orig);
        rowRect = CGRectIsNull(rowRect) ? f : CGRectUnion(rowRect, f);
    }
    CGFloat slotW = MIN(MAX(maxContentW + 56, 82.0), 112.0);
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

    // 同步 + 隐藏原按钮：内容并集整体平移进槽位中心
    for (NSUInteger i = 0; i < btns.count; i++) {
        UIView *orig = btns[i];
        HPGlassButton *gb = row[i];
        CGRect slot = CGRectMake(capX + 12 + (CGFloat)i * slotW, capY, slotW, capH);
        gb.frame = slot;
        CGRect cr = [contents[i] CGRectValue];
        HPSyncGlassButton(gb, bar, orig,
                          CGRectGetMidX(slot) - CGRectGetMidX(cr),
                          CGRectGetMidY(slot) - CGRectGetMidY(cr));
        orig.hidden = YES;
    }

    // 选中态：以 updateButton 钩子记录的原按钮为准
    UIView *selBtn = objc_getAssociatedObject(bar, &kSelBtnKey);
    NSUInteger sel = selBtn ? [btns indexOfObject:selBtn] : NSNotFound;
    if (sel == NSNotFound) sel = 0;
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
    lens.hidden = NO;

    // 层级：胶囊 < 透镜 < 自建按钮
    [bar bringSubviewToFront:lens];
    for (HPGlassButton *gb in row) [bar bringSubviewToFront:gb];
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
    lens.hidden = NO;
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
    NSLog(@"[HPGlass] v8 install: swiftBar=%@ swiftBtn=%@ objcBar=%@ installed=%d",
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
