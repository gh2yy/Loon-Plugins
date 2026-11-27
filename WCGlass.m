// WCGlass.m — 自研微信液态玻璃底栏 v1.0 (2026-11-26)
// 替代第三方 WCTabBarGlass：它用暂停动画器顶着模糊层，退后台后模糊被系统
// 丢弃、回前台无人刷新，底栏变平灰直到点一下。本插件从构造上不用动画器：
// 玻璃盘与选中透镜都是静态 UIVisualEffectView（系统托管、退后台不丢状态），
// 没有任何需要在回前台补刷的东西。
// 集成方式：找到微信自家的 WCTabBarView，抄它的图标/标题/角标与选中态，
// 在原位置上方盖一层自建玻璃栏；原栏隐藏但保留（选择与角标的状态仍走原
// 链），点击转发回 WCTabBarController 的用户选择入口。
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>

static os_log_t NGLog(void) {
    static os_log_t l;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ l = os_log_create("com.nova.wcglass", "v1.0"); });
    return l;
}

// ---------- 工具 ----------
static IMP NGSwapOwn(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NULL;
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL own = NO;
    for (unsigned int i = 0; i < count; i++) if (method_getName(list[i]) == sel) { own = YES; break; }
    if (list) free(list);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return NULL;
    if (own) return method_setImplementation(m, newImp);
    IMP inherited = method_getImplementation(m);
    class_addMethod(cls, sel, newImp, method_getTypeEncoding(m));
    return inherited;
}
static id NGSend0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
static void NGFindInView(UIView *v, Class cls, UIView **out) {
    if (*out) return;
    if ([v isKindOfClass:cls]) { *out = v; return; }
    for (UIView *s in v.subviews) NGFindInView(s, cls, out);
}

// ---------- 微信深色探针（无钩直查：WCColorMgr sharedInstance → BG_0） ----------
static BOOL NGProbeWeChatDark(BOOL *okOut) {
    if (okOut) *okOut = NO;
    @try {
        Class mgrCls = NSClassFromString(@"WCColorMgr");
        if (!mgrCls) return NO;
        id mgr = NGSend0(mgrCls, @selector(sharedInstance));
        if (!mgr || ![mgr respondsToSelector:@selector(getColor:)]) return NO;
        id dyn = ((id (*)(id, SEL, id))objc_msgSend)(mgr, @selector(getColor:), @"BG_0");
        if (!dyn || ![dyn respondsToSelector:@selector(toColor)]) return NO;
        UIColor *cur = NGSend0(dyn, @selector(toColor));
        UIColor *darkC = NGSend0(dyn, @selector(darkmodeColor));
        UIColor *normC = NGSend0(dyn, @selector(normalColor));
        if (!cur || !darkC || !normC) return NO;
        if (okOut) *okOut = YES;
        if ([cur isEqual:darkC]) return YES;
        if ([cur isEqual:normC]) return NO;
        return YES; // 两个都不等（不该发生）时按深色兜底，与她现行环境一致
    } @catch (NSException *e) { return NO; }
}
static BOOL gNGDark = YES;
static void NGRefreshDark(void) {
    BOOL ok = NO;
    BOOL d = NGProbeWeChatDark(&ok);
    if (ok) gNGDark = d;
}

// ---------- 角标状态（钩控制器 setter 维护，事件驱动） ----------
static NSMutableDictionary<NSNumber *, NSString *> *gNGBadgeText; // idx -> 文本（@"" 表示红点）
static void NGSetBadge(NSInteger idx, NSString *text) {
    if (!gNGBadgeText) gNGBadgeText = [[NSMutableDictionary alloc] init];
    if (text) gNGBadgeText[@(idx)] = text;
    else [gNGBadgeText removeObjectForKey:@(idx)];
}

// ---------- 自建栏视图 ----------
@interface NGBItemButton : UIControl
@property (nonatomic, retain) UIImageView *iconView;
@property (nonatomic, retain) UILabel *titleLabel;
@property (nonatomic, retain) UIView *badgeView;
@property (nonatomic, retain) UILabel *badgeLabel;
@property (nonatomic, assign) NSInteger index;
@end
@implementation NGBItemButton
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat iconS = 25;
    self.iconView.frame = CGRectMake((w - iconS) / 2, 7, iconS, iconS);
    self.titleLabel.frame = CGRectMake(0, 7 + iconS + 1, w, 13);
    NSString *bt = self.badgeLabel.text;
    if (self.badgeView && !self.badgeView.hidden) {
        CGFloat bw = (bt.length > 0) ? MAX(16, [self.badgeLabel sizeThatFits:CGSizeMake(60, 16)].width + 8) : 9;
        CGFloat bh = (bt.length > 0) ? 16 : 9;
        CGFloat bx = (w + iconS) / 2 - 3;
        self.badgeView.frame = CGRectMake(bx, 3, bw, bh);
        self.badgeView.layer.cornerRadius = bh / 2;
        self.badgeLabel.frame = self.badgeView.bounds;
    }
}
@end

@interface NGBBarView : UIView
@property (nonatomic, retain) UIVisualEffectView *plateBlur;
@property (nonatomic, retain) UIView *plateTint;
@property (nonatomic, retain) UIVisualEffectView *lensBlur;
@property (nonatomic, retain) UIView *lensTint;
@property (nonatomic, retain) NSMutableArray<NGBItemButton *> *buttons;
@property (nonatomic, assign) NSInteger selectedIndex;
@property (nonatomic, assign) BOOL darkApplied;
- (void)applyTheme;
- (void)layoutLensAnimated:(BOOL)animated;
@end
@implementation NGBBarView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _selectedIndex = 0;
        _buttons = [[NSMutableArray alloc] init];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.28;
        self.layer.shadowRadius = 16;
        self.layer.shadowOffset = CGSizeMake(0, 4);
        _plateBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
        _plateBlur.layer.cornerRadius = 31;
        _plateBlur.layer.masksToBounds = YES;
        _plateBlur.layer.borderWidth = 0.5;
        [self addSubview:_plateBlur];
        _plateTint = [[UIView alloc] init];
        _plateTint.layer.cornerRadius = 31;
        _plateTint.layer.masksToBounds = YES;
        [self addSubview:_plateTint];
        _lensBlur = [[UIVisualEffectView alloc] initWithEffect:nil];
        _lensBlur.layer.cornerRadius = 26;
        _lensBlur.layer.masksToBounds = YES;
        _lensBlur.layer.borderWidth = 0.5;
        [self addSubview:_lensBlur];
        _lensTint = [[UIView alloc] init];
        _lensTint.layer.cornerRadius = 26;
        _lensTint.layer.masksToBounds = YES;
        [self addSubview:_lensTint];
        [self applyTheme];
    }
    return self;
}
- (void)applyTheme {
    BOOL dark = gNGDark;
    self.darkApplied = dark;
    if (dark) {
        self.plateBlur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        self.plateTint.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.30];
        self.plateBlur.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.16].CGColor;
        self.lensBlur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        self.lensTint.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10];
        self.lensBlur.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.14].CGColor;
    } else {
        self.plateBlur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialLight];
        self.plateTint.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.25];
        self.plateBlur.layer.borderColor = [[UIColor blackColor] colorWithAlphaComponent:0.05].CGColor;
        self.lensBlur.effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialLight];
        self.lensTint.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22];
        self.lensBlur.layer.borderColor = [[UIColor blackColor] colorWithAlphaComponent:0.04].CGColor;
    }
}
- (CGRect)lensFrameForIndex:(NSInteger)idx {
    NSInteger n = (NSInteger)self.buttons.count;
    if (n <= 0) return CGRectZero;
    CGFloat slot = self.bounds.size.width / n;
    CGFloat w = slot - 10;
    return CGRectMake(idx * slot + (slot - w) / 2, 4, w, self.bounds.size.height - 8);
}
- (void)layoutLensAnimated:(BOOL)animated {
    CGRect f = [self lensFrameForIndex:self.selectedIndex];
    void (^apply)(void) = ^{
        self.lensBlur.frame = f;
        self.lensTint.frame = f;
    };
    if (animated) {
        [UIView animateWithDuration:0.38 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.4 options:UIViewAnimationOptionBeginFromCurrentState animations:apply completion:nil];
    } else apply();
}
- (void)layoutSubviews {
    [super layoutSubviews];
    self.plateBlur.frame = self.bounds;
    self.plateTint.frame = self.bounds;
    NSInteger n = (NSInteger)self.buttons.count;
    if (n > 0) {
        CGFloat slot = self.bounds.size.width / n;
        for (NSInteger i = 0; i < n; i++) {
            self.buttons[i].frame = CGRectMake(i * slot, 0, slot, self.bounds.size.height);
        }
    }
    [self layoutLensAnimated:NO];
}
@end

// ---------- 每个原栏一份的运行时状态 ----------
static NSMapTable<UIView *, NGBBarView *> *gNGOverlays;      // 原栏 -> 自建栏
static NSMapTable<UIView *, NSMutableArray *> *gNGNormImg, *gNGSelImg;   // 每项常态/选中图标
static NSMapTable<UIView *, NSMutableArray *> *gNGNormTint, *gNGSelTint; // 每项常态/选中色
static NSMapTable<UIView *, NSMutableArray *> *gNGTitles;
static BOOL gNGHidingOriginal = NO;

static UIView *NGItemViewAt(UIView *bar, NSInteger idx) {
    if (![bar respondsToSelector:@selector(itemViewAtIndex:)])
        return nil;
    return ((id (*)(id, SEL, NSInteger))objc_msgSend)(bar, @selector(itemViewAtIndex:), idx);
}
static NSInteger NGItemCount(UIView *bar) {
    if ([bar respondsToSelector:@selector(tabBarItemCount)])
        return (NSInteger)((long (*)(id, SEL))objc_msgSend)(bar, @selector(tabBarItemCount));
    return 0;
}
static NSInteger NGSelectedIndex(UIView *bar) {
    if ([bar respondsToSelector:@selector(selectedIndex)])
        return (NSInteger)((long (*)(id, SEL))objc_msgSend)(bar, @selector(selectedIndex));
    return 0;
}
static NSMutableArray *NGStore(NSMapTable *table, UIView *bar, NSInteger n) {
    NSMutableArray *a = [table objectForKey:bar];
    if (!a) {
        a = [NSMutableArray array];
        for (NSInteger i = 0; i < n; i++) [a addObject:[NSNull null]];
        [table setObject:a forKey:bar];
    }
    while ((NSInteger)a.count < n) [a addObject:[NSNull null]];
    return a;
}
// 从原栏某一项里抄当前的图标/标题/颜色（按它此刻是否被选中存进对应槽）
static void NGCaptureItem(UIView *bar, NSInteger idx, BOOL asSelected) {
    UIView *iv = NGItemViewAt(bar, idx);
    if (!iv) return;
    NSInteger n = NGItemCount(bar);
    UIView *imgV = nil, *labV = nil;
    NGFindInView(iv, [UIImageView class], &imgV);
    NGFindInView(iv, [UILabel class], &labV);
    UIImageView *img = (UIImageView *)imgV;
    UILabel *lab = (UILabel *)labV;
    NSMutableArray *imgs = NGStore(asSelected ? gNGSelImg : gNGNormImg, bar, n);
    NSMutableArray *tints = NGStore(asSelected ? gNGSelTint : gNGNormTint, bar, n);
    NSMutableArray *titles = NGStore(gNGTitles, bar, n);
    if (img.image) {
        // 图标与其渲染模式/染色打包存：[image, tintColor 或 null]
        UIColor *tc = img.tintColor ?: [UIColor clearColor];
        imgs[idx] = @[img.image, tc];
    }
    if (lab) {
        if (lab.text) titles[idx] = lab.text;
        if (lab.textColor) tints[idx] = lab.textColor;
    }
}
static void NGCaptureAll(UIView *bar) {
    NSInteger n = NGItemCount(bar);
    NSInteger sel = NGSelectedIndex(bar);
    for (NSInteger i = 0; i < n; i++) NGCaptureItem(bar, i, i == sel);
}
static id NGFindController(UIView *bar) {
    Class cbc = NSClassFromString(@"WCTabBarController");
    UIResponder *r = bar;
    while (r) {
        if (cbc && [r isKindOfClass:cbc]) return r;
        r = r.nextResponder;
    }
    return nil;
}
static void NGRefreshBadges(NGBBarView *ov) {
    for (NGBItemButton *b in ov.buttons) {
        NSString *t = gNGBadgeText[@(b.index)];
        BOOL show = (t != nil);
        if (!b.badgeView) {
            UIView *bv = [[UIView alloc] init];
            bv.backgroundColor = [UIColor colorWithRed:0.98 green:0.32 blue:0.32 alpha:1.0];
            bv.hidden = YES;
            UILabel *bl = [[UILabel alloc] init];
            bl.textColor = [UIColor whiteColor];
            bl.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
            bl.textAlignment = NSTextAlignmentCenter;
            [bv addSubview:bl];
            b.badgeView = bv;
            b.badgeLabel = bl;
            [b addSubview:bv];
            [bv release];
            [bl release];
        }
        b.badgeView.hidden = !show;
        b.badgeLabel.text = show ? t : nil;
        [b setNeedsLayout];
    }
}
static void NGRenderItems(UIView *bar, NGBBarView *ov) {
    NSInteger n = NGItemCount(bar);
    if (n <= 0) return;
    while ((NSInteger)ov.buttons.count > n) {
        [ov.buttons.lastObject removeFromSuperview];
        [ov.buttons removeLastObject];
    }
    while ((NSInteger)ov.buttons.count < n) {
        NGBItemButton *b = [[NGBItemButton alloc] init];
        b.index = (NSInteger)ov.buttons.count;
        UIImageView *iv = [[UIImageView alloc] init];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        b.iconView = iv;
        [b addSubview:iv];
        [iv release];
        UILabel *lab = [[UILabel alloc] init];
        lab.font = [UIFont systemFontOfSize:10];
        lab.textAlignment = NSTextAlignmentCenter;
        b.titleLabel = lab;
        [b addSubview:lab];
        [lab release];
        [b addTarget:ov action:@selector(ng_itemTap:) forControlEvents:UIControlEventTouchUpInside];
        UITapGestureRecognizer *dbl = [[UITapGestureRecognizer alloc] initWithTarget:ov action:@selector(ng_itemDoubleTap:)];
        dbl.numberOfTapsRequired = 2;
        [b addGestureRecognizer:dbl];
        [dbl release];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:ov action:@selector(ng_itemLongPress:)];
        [b addGestureRecognizer:lp];
        [lp release];
        [ov addSubview:b];
        [ov.buttons addObject:b];
        [b release];
    }
    NSInteger sel = NGSelectedIndex(bar);
    NSMutableArray *nImg = NGStore(gNGNormImg, bar, n), *sImg = NGStore(gNGSelImg, bar, n);
    NSMutableArray *nTint = NGStore(gNGNormTint, bar, n), *sTint = NGStore(gNGSelTint, bar, n);
    NSMutableArray *titles = NGStore(gNGTitles, bar, n);
    for (NSInteger i = 0; i < n; i++) {
        NGBItemButton *b = ov.buttons[i];
        BOOL isSel = (i == sel);
        id pack = (isSel && sImg[i] != [NSNull null]) ? sImg[i] : (nImg[i] != [NSNull null] ? nImg[i] : sImg[i]);
        if (pack != [NSNull null] && [pack isKindOfClass:[NSArray class]]) {
            UIImage *im = pack[0];
            UIColor *tc = pack[1];
            b.iconView.image = [im imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            b.iconView.tintColor = tc;
        }
        id tc2 = (isSel && sTint[i] != [NSNull null]) ? sTint[i] : (nTint[i] != [NSNull null] ? nTint[i] : sTint[i]);
        if (tc2 != [NSNull null]) b.titleLabel.textColor = (UIColor *)tc2;
        if (titles[i] != [NSNull null]) b.titleLabel.text = (NSString *)titles[i];
        [b setNeedsLayout];
    }
    ov.selectedIndex = sel;
    [ov setNeedsLayout];
    [ov layoutLensAnimated:NO];
    NGRefreshBadges(ov);
}

// 自建栏上的手势/点击都长在 NGBBarView 上（按钮 target 指到它），转发回控制器
@interface NGBBarView (ActionDecls)
- (void)ng_itemTap:(NGBItemButton *)b;
- (void)ng_itemDoubleTap:(UITapGestureRecognizer *)g;
- (void)ng_itemLongPress:(UILongPressGestureRecognizer *)g;
@end
@implementation NGBBarView (ActionImpls)
- (UIView *)ng_originalBar {
    for (UIView *bar in gNGOverlays) if ([gNGOverlays objectForKey:bar] == self) return bar;
    return nil;
}
- (void)ng_forwardTap:(NSInteger)idx doubleTap:(BOOL)dbl longPress:(BOOL)lp {
    UIView *bar = [self ng_originalBar];
    id ctl = bar ? NGFindController(bar) : nil;
    if (!ctl) return;
    NSInteger cur = bar ? NGSelectedIndex(bar) : -1;
    BOOL was = (idx == cur);
    SEL sel = lp ? @selector(didLongPressTabBarItemAtIndex:wasSelected:)
                 : (dbl ? @selector(didDoubleTapTabBarItemAtIndex:wasSelected:)
                        : @selector(didSingleTapTabBarItemAtIndex:wasSelected:));
    if (!lp && !dbl && [ctl respondsToSelector:@selector(handleUserSelectionAtIndex:)]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(ctl, @selector(handleUserSelectionAtIndex:), idx);
        return;
    }
    if ([ctl respondsToSelector:sel]) {
        ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(ctl, sel, idx, was);
        return;
    }
    if (!lp && !dbl && [ctl respondsToSelector:@selector(setSelectedIndex:)])
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(ctl, @selector(setSelectedIndex:), idx);
}
- (void)ng_itemTap:(NGBItemButton *)b { [self ng_forwardTap:b.index doubleTap:NO longPress:NO]; }
- (void)ng_itemDoubleTap:(UITapGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateRecognized && [g.view isKindOfClass:[NGBItemButton class]])
        [self ng_forwardTap:((NGBItemButton *)g.view).index doubleTap:YES longPress:NO];
}
- (void)ng_itemLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan && [g.view isKindOfClass:[NGBItemButton class]])
        [self ng_forwardTap:((NGBItemButton *)g.view).index doubleTap:NO longPress:YES];
}
@end

// ---------- 挂接与同步 ----------
static void NGRenderItems(UIView *bar, NGBBarView *ov); // 前置声明（上文已实现，补动画参数版在下方重入）
static void NGSyncFrame(UIView *bar, NGBBarView *ov) {
    if (!bar.superview || ov.superview != bar.superview) return;
    CGRect bf = bar.frame;
    CGFloat w = bf.size.width - 28;
    CGFloat h = 62;
    CGFloat y = bf.origin.y + bf.size.height - 8 - h;
    if (y < bf.origin.y + 2) y = bf.origin.y + 2;
    ov.frame = CGRectMake(bf.origin.x + 14, y, w, h);
}
static void NGAttach(UIView *bar) {
    if (!bar.window || !bar.superview) return;
    NGRefreshDark();
    NGCaptureAll(bar);
    NGBBarView *ov = [gNGOverlays objectForKey:bar];
    if (!ov) {
        ov = [[NGBBarView alloc] initWithFrame:CGRectZero];
        [gNGOverlays setObject:ov forKey:bar];
        [ov release];
    }
    if (ov.superview != bar.superview) {
        [ov removeFromSuperview];
        [bar.superview addSubview:ov];
    }
    NGSyncFrame(bar, ov);
    // 初始角标：读控制器现成的角标视图
    id ctl = NGFindController(bar);
    if (ctl && [ctl respondsToSelector:@selector(badgeViewAtIndex:)]) {
        NSInteger n = NGItemCount(bar);
        for (NSInteger i = 0; i < n; i++) {
            UIView *bv = ((id (*)(id, SEL, NSInteger))objc_msgSend)(ctl, @selector(badgeViewAtIndex:), i);
            if (bv && !bv.hidden) {
                UIView *lab = nil;
                NGFindInView(bv, [UILabel class], &lab);
                NSString *t = ((UILabel *)lab).text;
                NGSetBadge(i, (t.length > 0) ? t : @"");
            }
        }
    }
    NGRenderItems(bar, ov);
    ov.hidden = bar.hidden;
    if (!bar.hidden) {
        gNGHidingOriginal = YES;
        bar.hidden = YES;
        gNGHidingOriginal = NO;
        ov.hidden = NO;
    }
}
static void NGOnSelectionChanged(UIView *bar) {
    NGBBarView *ov = [gNGOverlays objectForKey:bar];
    if (!ov) return;
    NSInteger old = ov.selectedIndex;
    NGCaptureAll(bar);
    NGRenderItems(bar, ov); // 内部会把透镜 snap 到新位置
    if (old != ov.selectedIndex && old >= 0 && old < (NSInteger)ov.buttons.count) {
        // 把透镜拨回旧位再弹过去，才有滑动动画
        CGRect cur = [ov lensFrameForIndex:old];
        ov.lensBlur.frame = cur;
        ov.lensTint.frame = cur;
        [ov layoutLensAnimated:YES];
    }
}
static void NGOnItemsChanged(UIView *bar) {
    if (![gNGOverlays objectForKey:bar]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ NGAttach(bar); });
}

// ---------- WCTabBarView 钩子 ----------
static IMP gO_TBWindow, gO_TBLayout, gO_TBHidden, gO_TBSelIdx, gO_TBSelect, gO_TBSetItems, gO_TBSetTabItems, gO_TBReload, gO_TBTrait;
static void NG_TB_window(UIView *s, SEL c) {
    ((void (*)(id, SEL))gO_TBWindow)(s, c);
    if (s.window) dispatch_async(dispatch_get_main_queue(), ^{ NGAttach(s); });
}
static void NG_TB_layout(UIView *s, SEL c) {
    ((void (*)(id, SEL))gO_TBLayout)(s, c);
    NGBBarView *ov = [gNGOverlays objectForKey:s];
    if (ov) NGSyncFrame(s, ov);
}
static void NG_TB_hidden(UIView *s, SEL c, BOOL h) {
    ((void (*)(id, SEL, BOOL))gO_TBHidden)(s, c, h);
    if (gNGHidingOriginal) return;
    NGBBarView *ov = [gNGOverlays objectForKey:s];
    if (ov) ov.hidden = h;
}
static void NG_TB_selIdx(UIView *s, SEL c, NSInteger i) {
    ((void (*)(id, SEL, NSInteger))gO_TBSelIdx)(s, c, i);
    NGOnSelectionChanged(s);
}
static void NG_TB_select(UIView *s, SEL c, NSInteger i) {
    ((void (*)(id, SEL, NSInteger))gO_TBSelect)(s, c, i);
    NGOnSelectionChanged(s);
}
static void NG_TB_setItems(UIView *s, SEL c, id items) {
    ((void (*)(id, SEL, id))gO_TBSetItems)(s, c, items);
    NGOnItemsChanged(s);
}
static void NG_TB_setItemsAnim(UIView *s, SEL c, id items, BOOL a) {
    ((void (*)(id, SEL, id, BOOL))gO_TBSetItems)(s, c, items, a);
    NGOnItemsChanged(s);
}
static void NG_TB_setTabItems(UIView *s, SEL c, id items) {
    ((void (*)(id, SEL, id))gO_TBSetTabItems)(s, c, items);
    NGOnItemsChanged(s);
}
static void NG_TB_reload(UIView *s, SEL c) {
    ((void (*)(id, SEL))gO_TBReload)(s, c);
    NGOnItemsChanged(s);
}
static void NG_TB_trait(UIView *s, SEL c, id prev) {
    ((void (*)(id, SEL, id))gO_TBTrait)(s, c, prev);
    BOOL before = gNGDark;
    NGRefreshDark();
    NGBBarView *ov = [gNGOverlays objectForKey:s];
    if (ov && before != gNGDark) { [ov applyTheme]; NGCaptureAll(s); NGRenderItems(s, ov); }
}

// ---------- 控制器角标钩子 ----------
static IMP gO_BadgeVal, gO_BadgeStr, gO_DotShow, gO_DotRemove;
static void NGRefreshAllBadges(void) {
    for (UIView *bar in gNGOverlays) NGRefreshBadges([gNGOverlays objectForKey:bar]);
}
static void NG_Ctl_badgeVal(id s, SEL c, long v, NSInteger i) {
    ((void (*)(id, SEL, long, NSInteger))gO_BadgeVal)(s, c, v, i);
    NGSetBadge(i, v > 0 ? [NSString stringWithFormat:@"%ld", v] : nil);
    NGRefreshAllBadges();
}
static void NG_Ctl_badgeStr(id s, SEL c, NSString *t, NSInteger i) {
    ((void (*)(id, SEL, id, NSInteger))gO_BadgeStr)(s, c, t, i);
    NGSetBadge(i, t.length > 0 ? t : nil);
    NGRefreshAllBadges();
}
static void NG_Ctl_dotShow(id s, SEL c, NSInteger i) {
    ((void (*)(id, SEL, NSInteger))gO_DotShow)(s, c, i);
    if (!gNGBadgeText[@(i)]) NGSetBadge(i, @"");
    NGRefreshAllBadges();
}
static void NG_Ctl_dotRemove(id s, SEL c, NSInteger i) {
    ((void (*)(id, SEL, NSInteger))gO_DotRemove)(s, c, i);
    if ([gNGBadgeText[@(i)] isEqualToString:@""]) NGSetBadge(i, nil);
    NGRefreshAllBadges();
}

// ---------- 安装 ----------
static void NGInstall(void) {
    if (!gNGOverlays) {
        gNGOverlays = [[NSMapTable weakToStrongObjectsMapTable] retain];
        gNGNormImg = [[NSMapTable weakToStrongObjectsMapTable] retain];
        gNGSelImg = [[NSMapTable weakToStrongObjectsMapTable] retain];
        gNGNormTint = [[NSMapTable weakToStrongObjectsMapTable] retain];
        gNGSelTint = [[NSMapTable weakToStrongObjectsMapTable] retain];
        gNGTitles = [[NSMapTable weakToStrongObjectsMapTable] retain];
    }
    Class tb = NSClassFromString(@"WCTabBarView");
    if (tb) {
        if (!gO_TBWindow) gO_TBWindow = NGSwapOwn(tb, @selector(didMoveToWindow), (IMP)NG_TB_window);
        if (!gO_TBLayout) gO_TBLayout = NGSwapOwn(tb, @selector(layoutSubviews), (IMP)NG_TB_layout);
        if (!gO_TBHidden) gO_TBHidden = NGSwapOwn(tb, @selector(setHidden:), (IMP)NG_TB_hidden);
        if (!gO_TBSelIdx) gO_TBSelIdx = NGSwapOwn(tb, @selector(setSelectedIndex:), (IMP)NG_TB_selIdx);
        if (!gO_TBSelect) gO_TBSelect = NGSwapOwn(tb, @selector(selectIndex:), (IMP)NG_TB_select);
        if (!gO_TBReload) gO_TBReload = NGSwapOwn(tb, @selector(reloadItemViews), (IMP)NG_TB_reload);
        if (!gO_TBTrait) gO_TBTrait = NGSwapOwn(tb, @selector(traitCollectionDidChange:), (IMP)NG_TB_trait);
        if (!gO_TBSetItems && [tb instancesRespondToSelector:@selector(setItems:animated:)])
            gO_TBSetItems = NGSwapOwn(tb, @selector(setItems:animated:), (IMP)NG_TB_setItemsAnim);
        else if (!gO_TBSetItems && [tb instancesRespondToSelector:@selector(setItems:)])
            gO_TBSetItems = NGSwapOwn(tb, @selector(setItems:), (IMP)NG_TB_setItems);
        if (!gO_TBSetTabItems && [tb instancesRespondToSelector:@selector(setTabItems:)])
            gO_TBSetTabItems = NGSwapOwn(tb, @selector(setTabItems:), (IMP)NG_TB_setTabItems);
    }
    Class ctl = NSClassFromString(@"NewMainTabBarViewController");
    if (!ctl) ctl = NSClassFromString(@"WCTabBarController");
    if (ctl) {
        if (!gO_BadgeVal) gO_BadgeVal = NGSwapOwn(ctl, @selector(setTabBarBadgeValue:forIndex:), (IMP)NG_Ctl_badgeVal);
        if (!gO_BadgeStr) gO_BadgeStr = NGSwapOwn(ctl, @selector(setTabBarBadgeString:forIndex:), (IMP)NG_Ctl_badgeStr);
        if (!gO_DotShow) gO_DotShow = NGSwapOwn(ctl, @selector(showRedDotOnTabBarItemAtIndex:), (IMP)NG_Ctl_dotShow);
        if (!gO_DotRemove) gO_DotRemove = NGSwapOwn(ctl, @selector(removeRedDotOnTabBarItemAtIndex:), (IMP)NG_Ctl_dotRemove);
    }
    if (tb && ctl) os_log(NGLog(), "[WCGlass] v1.0 hooks in");
}

@interface WCGlassLoader : NSObject
@end
@implementation WCGlassLoader
+ (void)load {
    NGInstall();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NGInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NGInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ NGInstall(); });
}
@end
