// WCBlack.m — 微信深色模式纯黑背景 v8.8 还原版 (2026-11-26)
// 用户拍板收线：只保留三件事，其余全部还原微信原样——
//   1) 背景变色（含置顶行）：钩 WCColorMgr 的 getColor:/getColorValueForName: 与
//      MMDynamicColor toColor、WCColorProxy 解析，在发色处按色名把深色值
//      换成模块色（bg 主背景 / cell 置顶行与卡片；置顶行色名
//      Table_ChatRow_Pinned_BG 与 BG_0 都归 bg）。浅色一律原样，深浅切换
//      由动态色自行重解析。本机制即 v6.0 定案版，内容区自此零问题。
//   2) 首页分割线开关：只认 MainFrame 主列表，存档原样式后置 None 并藏
//      cell 底部发丝线，关开关即还原。
//   3) 设置页（我→设置→插件→WCBlack 纯黑背景）：总开关 + bg/cell 两模块
//      选色 + 分割线开关。改完即时生效（动态色 provider 实时读配置）。
// 用户追加保留：聊天页底栏（MMInputToolView/InputToolContainerView，仅
// 聊天页）强涂 chatbar 色 + 输入框底色（v5.2 色板 + 话筒按类名藏，field
// 模块）。做法回到 v5/v6.1 的存档强涂，但深浅只看栏自己的 trait——没有
// 状态机、没有探针、没有巡逻钉制。一级页面的顶栏明确不碰；底部 tab 栏按用户要求单独做纯黑（v8.5 新增，
// 做法同聊天底栏：只对玻璃栏本体钉 trait + 强涂）：
// v6.1–v7.6 的顶栏/底栏钉制强涂、状态机与探针、colorDic 实验、键盘处理、
// 诊断页全部删除，恢复微信（含玻璃插件）原生表现。
// 安全纪律：+load/WCInstall 只做 swizzle，绝不给微信的类发消息（v7.2 闪退教训）。


#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>

static os_log_t WCLog(void) {
    static os_log_t l; static dispatch_once_t once;
    dispatch_once(&once, ^{ l = os_log_create("com.nova.wcblack", "v8.8"); });
    return l;
}

#pragma mark - 配置

static NSString *const kWCEnabledKey = @"WCBlack.enabled";
static NSArray<NSString *> *WCModules(void) { return @[@"bg", @"cell", @"chatbar", @"field", @"tab"]; }
static NSString *WCModuleTitle(NSString *m) {
    if ([m isEqualToString:@"bg"]) return @"主背景（列表 / 聊天）";
    if ([m isEqualToString:@"nav"]) return @"顶部导航栏";
    if ([m isEqualToString:@"tab"]) return @"底部标签栏";
    if ([m isEqualToString:@"chatbar"]) return @"聊天底部栏";
    if ([m isEqualToString:@"cell"]) return @"置顶行 / 卡片";
    if ([m isEqualToString:@"field"]) return @"输入框底色";
    return m;
}
static BOOL WCEnabled(void) {
    NSNumber *v = [[NSUserDefaults standardUserDefaults] objectForKey:kWCEnabledKey];
    return v ? v.boolValue : YES;
}
static NSString *const kWCHideSepKey = @"WCBlack.hideSep";
// 首页分割线开关：默认隐藏（用户 v5.0 要求去掉），关掉开关或总开关关闭时恢复原样
static BOOL WCHideSep(void) {
    if (!WCEnabled()) return NO;
    NSNumber *v = [[NSUserDefaults standardUserDefaults] objectForKey:kWCHideSepKey];
    return v ? v.boolValue : YES;
}
static UIColor *WCColorFromHex(NSString *hex) {
    if (!hex || hex.length < 7 || ![hex hasPrefix:@"#"]) return nil;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0 alpha:1.0];
}
static NSString *WCConfigHex(NSString *module) {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:[@"WCBlack." stringByAppendingString:module]];
    if (hex && [hex isEqualToString:@"off"]) return nil;
    if (hex) return hex;
    // 输入框模块默认 #1A1A1A（v4.9 用户定的压暗值），其余模块默认纯黑
    return @"#000000";
}
static UIColor *WCConfigColor(NSString *module) {
    if (!WCEnabled()) return nil;
    return WCColorFromHex(WCConfigHex(module));
}
static void WCSetConfigHex(NSString *module, NSString *hex) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (hex) [ud setObject:hex forKey:[@"WCBlack." stringByAppendingString:module]];
    else [ud setObject:@"off" forKey:[@"WCBlack." stringByAppendingString:module]];
    [ud synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WCBlackConfigChanged" object:nil];
}

static UITraitCollection *WCDarkTrait(void) { return [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]; }
static UITraitCollection *WCLightTrait(void) { return [UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleLight]; }

static NSString *WCModuleForGray(int v) {
    switch (v) {
        case 0x11: case 0x12: case 0x19: return @"bg";
        case 0x0F: return @"nav";
        case 0x1D: return @"tab";
        case 0x1C: return @"chatbar";
        case 0x20: return @"cell";
        default: return nil;
    }
}

// 把颜色按深色解析判定：命中目标灰阶返回所属模块名，否则 nil。outWhite/outAlpha 供靶向逻辑参考。
static NSString *WCModuleForColor(UIColor *color) {
    if (!color || color == [UIColor blackColor] || color == [UIColor clearColor]) return nil;
    UIColor *d = [color resolvedColorWithTraitCollection:WCDarkTrait()];
    CGFloat w = 0, r = 0, g = 0, b = 0, a = 0;
    if ([d getWhite:&w alpha:&a]) {
        if (a > 0.95) return WCModuleForGray((int)lrint(w * 255.0));
        return nil;
    }
    if ([d getRed:&r green:&g blue:&b alpha:&a]) {
        if (a > 0.95 && fabs(r - g) < 0.004 && fabs(g - b) < 0.004) return WCModuleForGray((int)lrint(r * 255.0));
    }
    return nil;
}

// 浅色回退净化：微信有些颜色是「只在深色下被赋值的静态深灰」（如导航 #0F0F0F），
// 直接拿它当浅色回退，切到浅色后动态色会解析成深灰——v3.1 真机实测浅色模式顶部一条黑带就是这个坑。
// 规则：回退色在浅色下若仍是暗色（亮度<0.5 且不透明），一律换成白色（五模块的浅色本色都是浅面）。
static UIColor *WCSanitizeLightFallback(UIColor *fb) {
    if (!fb) return [UIColor clearColor];
    UIColor *l = [fb resolvedColorWithTraitCollection:WCLightTrait()];
    // v3.4：微信主题灰多为单色（monochrome）空间色，getRed 取不到值——v3.3 只查 getRed，
    // 净化被整段跳过，深灰回退原样漏过，浅色模式顶部黑带就是这么来的。改 getWhite 优先；
    // 透明度门槛从 0.9 放宽到 0.03，命中时保留原 alpha 只换亮度。
    CGFloat r = 0, g = 0, b = 0, a = 0, w = 0, lum = -1;
    if ([l getWhite:&w alpha:&a]) lum = w;
    else if ([l getRed:&r green:&g blue:&b alpha:&a]) lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    if (lum >= 0 && lum < 0.5 && a > 0.03) return [UIColor colorWithWhite:1.0 alpha:a];
    return fb;
}

// 我方造过的动态色 / 纯色图登记（弱引用）：微信在明暗切换时会重建主框架并把旧栏的
// backgroundImage 等属性拷到新栏上，新栏从没被强涂过、还原无从下手；靠登记认出
// 「这是我的东西」，在浅色下直接回收（v6.4）。
static NSHashTable *WCMyColors(void) {
    static NSHashTable *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory] retain]; });
    return t;
}
static NSHashTable *WCMyImages(void) {
    static NSHashTable *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [[NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory] retain]; });
    return t;
}

static UIColor *WCDynamicColor(NSString *module, UIColor *lightFallback) {
    UIColor *fb = WCSanitizeLightFallback(lightFallback);
    UIColor *dyn = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) {
            UIColor *c = WCConfigColor(module);
            return c ?: fb;
        }
        return fb;
    }];
    [WCMyColors() addObject:dyn];
    return dyn;
}

// 分割线存档键（仅此一组）
static char kWCSepOrigStyleKey, kWCSepOrigColorKey, kWCSepHiddenKey;
static char kWCSepMainKey;

static char kWCOrigBGKey, kWCPatchHiddenKey, kWCUnderlayKey;
static char kWCFallbackKey, kWCDynKey, kWCForcedKey, kWCOrigEffectKey, kWCHiddenViewsKey, kWCOrigNavImageKey, kWCOrigTintKey;
static int gWCRestoreDepth = 0;
static NSHashTable<UIView *> *gBarsInput, *gBarsTab;
// v8.5：栏的深浅状态不看视图 trait（玻璃栏的 trait 一直是浅的——微信深色是
// 色板内部状态、跟 trait 两套系统，v8.1/v8.2 因此对底栏全程没生效）。状态由
// 探针问微信自己（BG_0 的 toColor 定值与深色值比对，v6.1 定案法），只在取色
// 钩子/主题切换钩子/家务 tick 里刷新；栏钩子只读状态、不当场探（防 v7.4 污染）。
static BOOL gWCWeChatDark = NO;
static void WCRefreshDarkState(BOOL fresh);
static void WCApplyBarsState(void);

static void WCStoreOrigBG(UIView *v) {
    if (v.backgroundColor && !objc_getAssociatedObject(v, &kWCOrigBGKey))
        objc_setAssociatedObject(v, &kWCOrigBGKey, v.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL WCGrayInRange(UIColor *color, int lo, int hi) {
    if (!color) return NO;
    UIColor *d = [color resolvedColorWithTraitCollection:WCDarkTrait()];
    CGFloat w = 0, a = 0;
    if (![d getWhite:&w alpha:&a] || a < 0.95) return NO;
    int v = (int)lrint(w * 255.0);
    return v >= lo && v <= hi;
}
static BOOL WCGrayInRange(UIColor *color, int lo, int hi); // 前向声明：定义在 Hooks 一节

// v5.1 输入框底色重做：v5.0 取证定案——底色是 MMGrowTextView 里一张专用底板视图
// （全幅、圆角 8），我们的动态色其实写上去了（诊断里 bg 已是 #1A1A1A），但它在图层
// 上的快照是透明的（layerBG=#000000 a0.00），渲染出来等于没涂，底下的图还在透。
// 动态色这条路对这张视图不可靠，改走静态色 + 登记表 + 每拍重申：
// 静态色没有 provider、没有快照歧义，写上就是这个色；登记表保证浅色/关模块时能还原。
static NSMutableSet *WCFieldViews(void) {
    static NSMutableSet *s = nil;
    if (!s) s = [[NSMutableSet alloc] init];
    return s;
}
static void WCFieldPaint(UIView *v) {
    UIColor *cfg = WCConfigColor(@"field");
    if (!cfg) return;
    WCStoreOrigBG(v);
    [WCFieldViews() addObject:v];
    if (v.backgroundColor != cfg) v.backgroundColor = cfg;
}
// v5.2：静态色涂在底板视图上仍不见效（v5.1 真机截图还是 #2C2C2C）——底板上面还压着
// 一张全幅背景图（UIImageView），键盘弹起时它多半被微信重新插回到底板之上，涂谁都
// 被它盖住。这次不跟它们抢：自己放一张色板，紧贴 MMTextView 正下方——文字层之下、
// 其余一切背景之上，这个位置除了文字本身没有任何东西能盖住。每拍检查位置，被
// 微信重排了就插回去。
static NSMutableSet *WCFieldPlates(void) {
    static NSMutableSet *s = nil;
    if (!s) s = [[NSMutableSet alloc] init];
    return s;
}
static void WCEnsureFieldPlate(UIView *grow) {
    UIColor *cfg = WCConfigColor(@"field");
    if (!cfg) return;
    UIView *plate = objc_getAssociatedObject(grow, &kWCUnderlayKey);
    if (!plate) {
        plate = [[UIView alloc] initWithFrame:grow.bounds];
        plate.userInteractionEnabled = NO;
        plate.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        plate.layer.cornerRadius = grow.layer.cornerRadius > 0 ? grow.layer.cornerRadius : 8;
        plate.clipsToBounds = YES;
        objc_setAssociatedObject(grow, &kWCUnderlayKey, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [WCFieldPlates() addObject:plate];
        [plate release];
    }
    NSInteger ti = -1;
    for (NSInteger i = 0; i < (NSInteger)grow.subviews.count; i++)
        if ([NSStringFromClass([grow.subviews[i] class]) isEqualToString:@"MMTextView"]) { ti = i; break; }
    NSUInteger pi = (plate.superview == grow) ? [grow.subviews indexOfObject:plate] : NSNotFound;
    BOOL placed = (plate.superview == grow) &&
                  ((ti >= 0 && (NSInteger)pi == ti - 1) || (ti < 0 && pi == grow.subviews.count - 1));
    if (!placed) {
        [plate removeFromSuperview];
        ti = -1;
        for (NSInteger i = 0; i < (NSInteger)grow.subviews.count; i++)
            if ([NSStringFromClass([grow.subviews[i] class]) isEqualToString:@"MMTextView"]) { ti = i; break; }
        [grow insertSubview:plate atIndex:(ti >= 0 ? ti : (NSInteger)grow.subviews.count)];
    }
    if (plate.backgroundColor != cfg) plate.backgroundColor = cfg;
    if (!CGRectEqualToRect(plate.frame, grow.bounds)) plate.frame = grow.bounds;
    plate.hidden = NO;
}
// v5.3：输入框右端话筒区残留原色（14:30 截图实测：框内其余全是 (26,26,26)，右端
// 约 30pt 仍是 (44,44,44)，且只在键盘弹起、编辑态出现，压在色板之上）。身份未明
// 就不点名：每拍在输入条整棵子树里按几何+渲染色猎——横向必须落在输入框框内、
// 伸进右端条带、尺寸不大于条带、垂直压在框身中段的视图：带灰底色的直接改静态
// 色（话筒按钮本体也照此办，图标不受影响）；纯图片/渐变渲染的先藏起来。全部
// 登记，浅色或关模块时逐个还原。命中名单写进诊断（gWCPatchInfo），猎错猎漏
// 都看得见；键盘弹起时另自动采一份诊断，万一没猎中也能当场点名。
static NSMutableSet *WCFieldPatchViews(void) {
    static NSMutableSet *s = nil;
    if (!s) s = [[NSMutableSet alloc] init];
    return s;
}
static NSString *gWCPatchInfo = nil;
static BOOL WCPatchIsGrayish(UIView *v) {
    if (WCGrayInRange(v.backgroundColor, 36, 52)) return YES;
    CGColorRef lc = v.layer.backgroundColor;
    if (lc && WCGrayInRange([UIColor colorWithCGColor:lc], 36, 52)) return YES;
    return NO;
}
static BOOL WCPatchIsImageLike(UIView *v) {
    if ([v isKindOfClass:[UIImageView class]] && [(UIImageView *)v image]) return YES;
    if (v.layer.contents) return YES;
    for (CALayer *l in v.layer.sublayers) if ([l isKindOfClass:[CAGradientLayer class]]) return YES;
    return NO;
}
static void WCPatchHide(UIView *v, NSMutableArray *hits, NSString *cn, CGRect vr) {
    objc_setAssociatedObject(v, &kWCPatchHiddenKey, @(v.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [WCFieldPatchViews() addObject:v];
    v.hidden = YES;
    [hits addObject:[NSString stringWithFormat:@"hide %@ f=%.0f,%.0f,%.0f,%.0f", cn, vr.origin.x, vr.origin.y, vr.size.width, vr.size.height]];
}
// v5.4：v5.3 只藏掉了话筒图标本体，底下那片毛玻璃/图片渲染的胶囊还在（44,44,44
// 软边一片）。用户拍板：话筒这一簇整个去掉。这版规则：完全落在右端条带里的
// 控件（话筒按钮）直接藏；带灰底的普通视图涂掉；其余只要在这一截里渲染了任何
// 东西（效果视图、图片、其它底色）一律藏。已登记的每拍维护，微信重新显示出来
// 就再按回去。多行输入态（框高 >56）右端是展开箭头，整场猎杀跳过。
static void WCFieldPatchHunt(UIView *grow) {
    UIColor *cfg = WCConfigColor(@"field");
    if (!cfg || !grow.window) return;
    for (UIView *v in WCFieldPatchViews().allObjects) {
        if (!v.window) continue;
        if (objc_getAssociatedObject(v, &kWCPatchHiddenKey)) { if (!v.hidden) v.hidden = YES; }
        else if (v.backgroundColor != cfg) v.backgroundColor = cfg;
    }
    CGRect gr = [grow convertRect:grow.bounds toView:nil];
    if (gr.size.height > 56) return;
    UIView *bar = grow.superview ?: grow;
    CGFloat stripX = gr.origin.x + gr.size.width * 0.70;
    NSMutableArray *stack = [NSMutableArray arrayWithObject:bar];
    NSMutableArray *hits = [NSMutableArray array];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        for (UIView *s in v.subviews) [stack addObject:s];
        if (v == grow || v == bar) continue;
        NSString *cn = NSStringFromClass([v class]);
        if ([cn isEqualToString:@"MMTextView"] || [cn isEqualToString:@"MMGrowTextView"]) continue;
        if ([WCFieldPlates() containsObject:v]) continue;
        if ([WCFieldPatchViews() containsObject:v]) continue;
        CGRect vr = [v convertRect:v.bounds toView:nil];
        if (vr.size.width <= 0 || vr.size.height <= 0) continue;
        if (vr.size.width > gr.size.width * 0.32 + 8 || vr.size.height > gr.size.height + 12) continue;
        if (vr.origin.x < gr.origin.x - 4) continue;
        if (vr.origin.x + vr.size.width > gr.origin.x + gr.size.width + 4) continue;
        if (vr.origin.x + vr.size.width < stripX) continue;
        if (vr.origin.y > gr.origin.y + gr.size.height * 0.75) continue;
        if (vr.origin.y + vr.size.height < gr.origin.y + gr.size.height * 0.25) continue;
        BOOL fullyInStrip = vr.origin.x >= stripX - 4;
        if ([v isKindOfClass:[UIControl class]] && fullyInStrip) {
            WCPatchHide(v, hits, cn, vr);
        } else if (WCPatchIsGrayish(v)) {
            WCStoreOrigBG(v);
            [WCFieldPatchViews() addObject:v];
            if (v.backgroundColor != cfg) v.backgroundColor = cfg;
            [hits addObject:[NSString stringWithFormat:@"paint %@ f=%.0f,%.0f,%.0f,%.0f", cn, vr.origin.x, vr.origin.y, vr.size.width, vr.size.height]];
        } else if ([v isKindOfClass:[UIVisualEffectView class]] || WCPatchIsImageLike(v) ||
                   (v.backgroundColor && CGColorGetAlpha(v.backgroundColor.CGColor) >= 0.03)) {
            WCPatchHide(v, hits, cn, vr);
        }
    }
    if (hits.count) {
        NSString *info = [hits componentsJoinedByString:@" | "];
        if (![info isEqualToString:gWCPatchInfo]) {
            [info retain];
            [gWCPatchInfo release];
            gWCPatchInfo = info;
        }
    }
}
static void WCFieldPlatesIn(UIView *root, int depth) {
    if (!root || depth < 0) return;
    if ([NSStringFromClass([root class]) isEqualToString:@"MMGrowTextView"]) { WCEnsureFieldPlate(root); WCFieldPatchHunt(root); }
    for (UIView *s in root.subviews) WCFieldPlatesIn(s, depth - 1);
}

// v5.5：话筒真身由 kbdup 诊断点名——MMGrowDictationIconView（输入框内 f=266,0,32,40），
// 它靠子图层与子视图拼出图标和光晕（本体 bg=nil），v5.3/v5.4 的颜色/图片规则全不匹配；
// 它那张 72×72 光晕图还探出输入框右界、被「必须落在框内」的护栏挡掉。既然已点名，
// 就按类名整个藏：登记进 patch 表，浅色/关模块时由 patch 还原统一放回，每拍重申。
static void WCFieldHideDictation(UIView *root, int depth) {
    if (!root || depth < 0) return;
    if ([NSStringFromClass([root class]) isEqualToString:@"MMGrowDictationIconView"]) {
        if (![WCFieldPatchViews() containsObject:root]) {
            objc_setAssociatedObject(root, &kWCPatchHiddenKey, @(root.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [WCFieldPatchViews() addObject:root];
            if (!gWCPatchInfo || ![gWCPatchInfo containsString:@"MMGrowDictationIconView"]) {
                NSString *info = gWCPatchInfo ? [gWCPatchInfo stringByAppendingString:@" | hide MMGrowDictationIconView (named)"] : @"hide MMGrowDictationIconView (named)";
                [info retain];
                [gWCPatchInfo release];
                gWCPatchInfo = info;
            }
        }
        if (!root.hidden) root.hidden = YES;
    }
    for (UIView *s in root.subviews) WCFieldHideDictation(s, depth - 1);
}
static void WCFieldScan(UIView *root, int depth) {
    if (!root || depth < 0) return;
    for (UIView *v in root.subviews) {
        if (![v isKindOfClass:[UIVisualEffectView class]] &&
            WCGrayInRange(v.backgroundColor, 42, 46))
            WCFieldPaint(v);
        WCFieldScan(v, depth - 1);
    }
}
// 深色+模块开：扫描新出现的底板并登记、已登记的逐个重申静态色；
// 浅色或模块关：把登记过的逐个还原并清表。
static void WCFieldSweep(UIView *bar) {
    BOOL dark = (bar.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
    NSMutableSet *views = WCFieldViews();
    if (WCConfigColor(@"field")) WCFieldHideDictation(bar, 8);  // v5.7：话筒不分深浅
    if (dark && WCConfigColor(@"field")) {
        WCFieldScan(bar, 5);
        WCFieldPlatesIn(bar, 6);
        UIColor *cfg = WCConfigColor(@"field");
        for (UIView *v in views.allObjects) {
            if (!v.window) { [views removeObject:v]; continue; }
            if (v.backgroundColor != cfg) v.backgroundColor = cfg;
        }
    } else {
        if (views.count) {
            for (UIView *v in views.allObjects) {
                UIColor *ob = objc_getAssociatedObject(v, &kWCOrigBGKey);
                if (ob) {
                    gWCRestoreDepth++;
                    v.backgroundColor = ob;
                    gWCRestoreDepth--;
                    objc_setAssociatedObject(v, &kWCOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
            [views removeAllObjects];
        }
        for (UIView *p in WCFieldPlates().allObjects) {
            if (!p.window) [WCFieldPlates() removeObject:p];
            else p.hidden = YES;
        }
        NSMutableSet *patches = WCFieldPatchViews();
        if (patches.count) {
            NSMutableSet *keepDic = nil;
            for (UIView *v in patches.allObjects) {
                if (WCConfigColor(@"field") &&
                    [NSStringFromClass([v class]) isEqualToString:@"MMGrowDictationIconView"]) {
                    if (!keepDic) keepDic = [NSMutableSet set];
                    [keepDic addObject:v];
                    continue;
                }
                UIColor *ob = objc_getAssociatedObject(v, &kWCOrigBGKey);
                if (ob) {
                    gWCRestoreDepth++;
                    v.backgroundColor = ob;
                    gWCRestoreDepth--;
                    objc_setAssociatedObject(v, &kWCOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                NSNumber *oh = objc_getAssociatedObject(v, &kWCPatchHiddenKey);
                if (oh) {
                    v.hidden = oh.boolValue;
                    objc_setAssociatedObject(v, &kWCPatchHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
            [patches removeAllObjects];
            if (keepDic) [patches unionSet:keepDic];
        }
    }
}


#pragma mark - 首页分割线

static void WCHideCellLineIn(UIView *root, UITableViewCell *cell, BOOL hide, int depth) {
    if (!root || depth < 0) return;
    for (UIView *v in root.subviews) {
        NSNumber *flag = objc_getAssociatedObject(v, &kWCSepHiddenKey);
        if (hide) {
            if (!flag.boolValue && v.bounds.size.height <= 1.0 &&
                v.bounds.size.width >= cell.bounds.size.width * 0.6 &&
                ![v isKindOfClass:[UILabel class]] && ![v isKindOfClass:[UIImageView class]] &&
                ![v isKindOfClass:[UIVisualEffectView class]]) {
                CGRect f = [v convertRect:v.bounds toView:cell];
                if (f.origin.y >= cell.bounds.size.height - 2.0) {
                    objc_setAssociatedObject(v, &kWCSepHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    v.hidden = YES;
                }
            }
        } else if (flag.boolValue) {
            v.hidden = NO;
            objc_setAssociatedObject(v, &kWCSepHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        WCHideCellLineIn(v, cell, hide, depth - 1);
    }
}

static void WCSepTryMarkViaResponder(UITableView *tv);
static void WCApplySeparators(UITableView *tv) {
    WCSepTryMarkViaResponder(tv);
    BOOL hide = WCHideSep();
    NSNumber *stored = objc_getAssociatedObject(tv, &kWCSepOrigStyleKey);
    if (hide) {
        if (!stored) {
            objc_setAssociatedObject(tv, &kWCSepOrigStyleKey, @(tv.separatorStyle), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (tv.separatorColor) objc_setAssociatedObject(tv, &kWCSepOrigColorKey, tv.separatorColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (tv.separatorStyle != UITableViewCellSeparatorStyleNone) tv.separatorStyle = UITableViewCellSeparatorStyleNone;
        for (UITableViewCell *cell in tv.visibleCells) WCHideCellLineIn(cell, cell, YES, 3);
    } else if (stored) {
        tv.separatorStyle = (UITableViewCellSeparatorStyle)stored.integerValue;
        UIColor *c = objc_getAssociatedObject(tv, &kWCSepOrigColorKey);
        if (c) tv.separatorColor = c;
        objc_setAssociatedObject(tv, &kWCSepOrigStyleKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(tv, &kWCSepOrigColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (UITableViewCell *cell in tv.visibleCells) WCHideCellLineIn(cell, cell, NO, 3);
    }
}

// 只认主列表：满屏 table 且 delegate/dataSource 是 MainFrame 体系（通讯录/设置/聊天列表都不碰）

static void WCEnsureRegistered(void);

// v8.5：分割线改源头拦截（用户点名不要扫描）：不遍历窗口、不等 tick。
// ① 钩 UITableView 的 setSeparatorStyle:——微信给 MainFrame 列表设样式的那
//    一下就把值改成 None，线根本没机会被设上；原值存档，关开关时放行还原。
// ② 钩 setDelegate:/setDataSource:——MainFrame 的 delegate 落到表上时打标
//    登记，并给该 delegate 类装 willDisplay 钩子。
// ③ willDisplay 在每个 cell 显示前那一下藏掉它自带的底部发丝线。
// 家务 tick 只遍历登记过的表做开关还原/补漏，不再扫窗口。
static NSHashTable<UITableView *> *gSepTables;
static BOOL WCSepNameMatch(UITableView *tv) {
    NSString *t = NSStringFromClass([tv class]) ?: @"";
    NSString *d = NSStringFromClass([tv.delegate class]) ?: @"";
    NSString *ds = NSStringFromClass([tv.dataSource class]) ?: @"";
    return [t containsString:@"MainFrame"] || [d containsString:@"MainFrame"] || [ds containsString:@"MainFrame"];
}
static IMP WCSwap(Class cls, SEL sel, IMP newImp);
static IMP WCSwapOwn(Class cls, SEL sel, IMP newImp);
static IMP gOrigSetSepStyle, gOrigSetDelegate, gOrigSetDataSource;
// v8.6：willDisplay 按类登记——v8.5 只装第一个类、且类没实现 willDisplay 就
// 直接放弃，cell 自带发丝线没人管、冷启动只能等 tick 补，这就是线还在闪的洞。
// 现在：每个 MainFrame delegate 类都装；自有实现就换、继承来的就在子类加覆盖、
// 整条链都没有就直接给它加一个方法，cell 显示前必经这一下。
static NSMutableSet<NSString *> *gWDInstalled;
static NSMutableDictionary<NSString *, NSValue *> *gWDOrigs;
static void WC_TV_setSepStyle(UITableView *s, SEL c, UITableViewCellSeparatorStyle style) {
    if (style != UITableViewCellSeparatorStyleNone && WCHideSep() &&
        (objc_getAssociatedObject(s, &kWCSepMainKey) || WCSepNameMatch(s))) {
        if (!objc_getAssociatedObject(s, &kWCSepOrigStyleKey))
            objc_setAssociatedObject(s, &kWCSepOrigStyleKey, @(style), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ((void (*)(id, SEL, NSInteger))gOrigSetSepStyle)(s, c, UITableViewCellSeparatorStyleNone);
        return;
    }
    ((void (*)(id, SEL, NSInteger))gOrigSetSepStyle)(s, c, style);
}
static void WC_Main_willDisplay(id self, SEL c, UITableView *tv, UITableViewCell *cell, NSIndexPath *ip) {
    NSValue *v = gWDOrigs[NSStringFromClass([self class])];
    if (v) ((void (*)(id, SEL, id, id, id))[v pointerValue])(self, c, tv, cell, ip);
    if (WCHideSep() && (objc_getAssociatedObject(tv, &kWCSepMainKey) || WCSepNameMatch(tv)))
        WCHideCellLineIn(cell, cell, YES, 3);
}
static void WCInstallWillDisplayHook(Class dc) {
    if (!dc) return;
    if (!gWDInstalled) { gWDInstalled = [[NSMutableSet alloc] init]; gWDOrigs = [[NSMutableDictionary alloc] init]; }
    NSString *name = NSStringFromClass(dc);
    if ([gWDInstalled containsObject:name]) return;
    [gWDInstalled addObject:name];
    SEL sel = @selector(tableView:willDisplayCell:forRowAtIndexPath:);
    if ([dc instancesRespondToSelector:sel]) {
        IMP orig = WCSwapOwn(dc, sel, (IMP)WC_Main_willDisplay);
        if (orig) gWDOrigs[name] = [NSValue valueWithPointer:orig];
        os_log(WCLog(), "[WCBlack] sep willDisplay hooked on %{public}@", name);
    } else {
        BOOL ok = class_addMethod(dc, sel, (IMP)WC_Main_willDisplay, "v@:@@@");
        os_log(WCLog(), "[WCBlack] sep willDisplay added on %{public}@ ok=%d", name, ok);
    }
}
// delegate/dataSource 命名都对不上时的兜底认定：沿响应链找拥有这张表的控制
// 器，类名含 MainFrame 就打标登记（tick 调 WCApplySeparators 时表已在层级里）。
static void WCSepTryMarkViaResponder(UITableView *tv) {
    if (objc_getAssociatedObject(tv, &kWCSepMainKey)) return;
    UIResponder *r = tv;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]] &&
            [NSStringFromClass([r class]) containsString:@"MainFrame"]) {
            objc_setAssociatedObject(tv, &kWCSepMainKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!gSepTables) gSepTables = [[NSHashTable weakObjectsHashTable] retain];
            if (![gSepTables containsObject:tv]) [gSepTables addObject:tv];
            if (tv.delegate) WCInstallWillDisplayHook([tv.delegate class]);
            os_log(WCLog(), "[WCBlack] sep marked via responder %{public}@", NSStringFromClass([r class]));
            return;
        }
        r = r.nextResponder;
    }
}
static void WCSepOnDelegate(UITableView *s, id d) {
    if (!d || ![NSStringFromClass([d class]) containsString:@"MainFrame"]) return;
    objc_setAssociatedObject(s, &kWCSepMainKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!gSepTables) gSepTables = [[NSHashTable weakObjectsHashTable] retain];
    if (![gSepTables containsObject:s]) [gSepTables addObject:s];
    WCInstallWillDisplayHook([d class]);
    WCApplySeparators(s);
}
static void WC_TV_setDelegate(UITableView *s, SEL c, id d) {
    ((void (*)(id, SEL, id))gOrigSetDelegate)(s, c, d);
    WCSepOnDelegate(s, d);
}
static void WC_TV_setDataSource(UITableView *s, SEL c, id d) {
    ((void (*)(id, SEL, id))gOrigSetDataSource)(s, c, d);
    WCSepOnDelegate(s, d);
}
static void WCInstallSepGate(void) {
    if (gOrigSetSepStyle) return;
    gOrigSetSepStyle = WCSwapOwn([UITableView class], @selector(setSeparatorStyle:), (IMP)WC_TV_setSepStyle);
    gOrigSetDelegate = WCSwapOwn([UITableView class], @selector(setDelegate:), (IMP)WC_TV_setDelegate);
    gOrigSetDataSource = WCSwapOwn([UITableView class], @selector(setDataSource:), (IMP)WC_TV_setDataSource);
}

// v8.8：二进制类转储定案（46,673 个类全量解析）——首页会话 cell
// NewMainFrameCell / FakeMainFrameCell 各自带一个 _separatorLine 视图，在
// cell 自己的 layoutSubviews 里摆出来。之前的防线都在表那一层：样式闸管
// 的是表的分隔线、管不到 cell 自带的线；willDisplay 在 layout 之前触发、
// 线还没摆出来，藏了个空；等 tick 巡查走到才消失——这就是冷启动线先闪、
// 过一会儿才没的完整机制。源头修法：钩这两个 cell 类自己的
// layoutSubviews，原实现跑完（线刚摆好）当场按 ivar 名藏掉，同一帧布局
// 内完成、根本不上屏。折叠区头 MainFrameSectionFoldView 的上下分隔视
// 图同理处理。
static IMP gOrigNMFLayout, gOrigFMFLayout, gOrigFoldLayout;
static void WCHideSepIvar(UIView *v, const char *ivarName) {
    Ivar iv = class_getInstanceVariable([v class], ivarName);
    if (!iv) return;
    id line = object_getIvar(v, iv);
    if ([line isKindOfClass:[UIView class]]) ((UIView *)line).hidden = YES;
}
static void WC_NMF_layout(id self, SEL c) {
    ((void (*)(id, SEL))gOrigNMFLayout)(self, c);
    if (WCHideSep()) WCHideSepIvar((UIView *)self, "_separatorLine");
}
static void WC_FMF_layout(id self, SEL c) {
    ((void (*)(id, SEL))gOrigFMFLayout)(self, c);
    if (WCHideSep()) WCHideSepIvar((UIView *)self, "_separatorLine");
}
static void WC_Fold_layout(id self, SEL c) {
    ((void (*)(id, SEL))gOrigFoldLayout)(self, c);
    if (!WCHideSep()) return;
    WCHideSepIvar((UIView *)self, "_topSeparatorView");
    WCHideSepIvar((UIView *)self, "_bottomSeparatorView");
}
static void WCInstallCellSepHooks(void) {
    Class nmf = NSClassFromString(@"NewMainFrameCell");
    if (nmf && !gOrigNMFLayout) gOrigNMFLayout = WCSwapOwn(nmf, @selector(layoutSubviews), (IMP)WC_NMF_layout);
    Class fmf = NSClassFromString(@"FakeMainFrameCell");
    if (fmf && !gOrigFMFLayout) gOrigFMFLayout = WCSwapOwn(fmf, @selector(layoutSubviews), (IMP)WC_FMF_layout);
    Class fold = NSClassFromString(@"MainFrameSectionFoldView");
    if (fold && !gOrigFoldLayout) gOrigFoldLayout = WCSwapOwn(fold, @selector(layoutSubviews), (IMP)WC_Fold_layout);
}

static NSString *WCHexOfColorIn(UIColor *c, UITraitCollection *tc) {
    if (!c) return @"nil";
    UIColor *d = [c resolvedColorWithTraitCollection:tc];
    CGFloat r = 0, g = 0, b = 0, a = 0, w = 0;
    if ([d getWhite:&w alpha:&a])
        return [NSString stringWithFormat:@"#%02X%02X%02X a%.2f", (int)lrint(w * 255), (int)lrint(w * 255), (int)lrint(w * 255), a];
    if (![d getRed:&r green:&g blue:&b alpha:&a]) return @"pat";
    return [NSString stringWithFormat:@"#%02X%02X%02X a%.2f", (int)lrint(r * 255), (int)lrint(g * 255), (int)lrint(b * 255), a];
}
static NSString *WCHexOfColor(UIColor *c) { return WCHexOfColorIn(c, WCDarkTrait()); }
static IMP WCSwap(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NULL;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { os_log(WCLog(), "[WCBlack] missing %{public}@ on %{public}@", NSStringFromSelector(sel), NSStringFromClass(cls)); return NULL; }
    return method_setImplementation(m, newImp);
}

// 只换本类自己实现的方法：若 sel 只是继承来的，直接 method_setImplementation 会污染父类
// （如把 UIView 的 layoutSubviews 全局换掉）。继承来的改为在本类 addMethod 覆盖，返回父类 IMP 作 orig。
static IMP WCSwapOwn(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NULL;
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    BOOL own = NO;
    for (unsigned int i = 0; i < count; i++) if (method_getName(list[i]) == sel) { own = YES; break; }
    if (list) free(list);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { os_log(WCLog(), "[WCBlack] missing %{public}@ on %{public}@", NSStringFromSelector(sel), NSStringFromClass(cls)); return NULL; }
    if (own) return method_setImplementation(m, newImp);
    IMP inherited = method_getImplementation(m);
    class_addMethod(cls, sel, newImp, method_getTypeEncoding(m));
    return inherited;
}

// v4.1：v4.0 的 DesignToken 拦截已整体移除。真机诊断定案：运行时 hook 到的 getColorByName:
// 是旧主题/十六进制色名解析（查到的名字全是 "#1C1C1C" 这类色值串与 navigator_btn_text_color
// 等旧主题键，module 一项都没命中），微信原生界面的令牌色不走字符串查询这条路；且 v4.0
// 真机进聊天页后聊天记录整页空白——该 hook 位于消息渲染的热路径上，是唯一新增的全局侵入点，
static void WCRegisterBar(NSHashTable<UIView *> *table, UIView *bar) {
    if (table && bar && ![table containsObject:bar]) [table addObject:bar];
}
static UIImage *WCSolidImage(UIColor *color) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [[NSMutableDictionary alloc] init]; });
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    NSString *key = [NSString stringWithFormat:@"%d-%d-%d", (int)lrint(r * 255), (int)lrint(g * 255), (int)lrint(b * 255)];
    UIImage *img = cache[key];
    if (img) return img;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, 2), YES, 1);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, 2, 2));
    img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (img) cache[key] = img;
    if (img) [WCMyImages() addObject:img];
    return img;
}
static BOOL WCIsOpaqueDarkNeutral(UIColor *c) {
    if (!c) return NO;
    UIColor *d = [c resolvedColorWithTraitCollection:WCDarkTrait()];
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![d getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 0;
        if (![d getWhite:&w alpha:&a]) return NO;
        r = g = b = w;
    }
    if (a < 0.95) return NO;
    CGFloat mx = MAX(r, MAX(g, b)), mn = MIN(r, MIN(g, b));
    CGFloat lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    return (mx - mn) < 0.05 && lum > 0.005 && lum < 0.40;
}

static void WCApplyStrong(UIView *root, UIView *bar, UIColor *dyn, int depth) {
    if (depth < 0) return;
    for (UIView *v in root.subviews) {
        if ([v isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *ev = (UIVisualEffectView *)v;
            if (ev.effect) {
                if (!objc_getAssociatedObject(ev, &kWCOrigEffectKey))
                    objc_setAssociatedObject(ev, &kWCOrigEffectKey, ev.effect, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                ev.effect = nil;
            }
            if (ev.contentView.backgroundColor != dyn) { WCStoreOrigBG(ev.contentView); ev.contentView.backgroundColor = dyn; }
            if (v.backgroundColor != dyn) { WCStoreOrigBG(v); v.backgroundColor = dyn; }
        } else if ([v isKindOfClass:[UIImageView class]] &&
                   v.frame.size.width >= bar.bounds.size.width * 0.9 &&
                   v.frame.size.height >= bar.bounds.size.height * 0.85) {
            if (!v.hidden) {
                NSMutableArray *hidden = objc_getAssociatedObject(bar, &kWCHiddenViewsKey);
                if (!hidden) { hidden = [NSMutableArray array]; objc_setAssociatedObject(bar, &kWCHiddenViewsKey, hidden, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
                if (![hidden containsObject:v]) [hidden addObject:v];
                v.hidden = YES;
            }
        } else {
            UIColor *bg = v.backgroundColor;
            if (bg && bg != dyn) {
                NSString *m = WCModuleForColor(bg);
                BOOL translucentOverlay = NO;
                if (!m) {
                    UIColor *d = [bg resolvedColorWithTraitCollection:WCDarkTrait()];
                    CGFloat w = 0, al = 0;
                    if ([d getWhite:&w alpha:&al] && al > 0.03 && al < 0.95) translucentOverlay = YES;
                }
                if (m || translucentOverlay) { WCStoreOrigBG(v); v.backgroundColor = dyn; }
            }
        }
        WCApplyStrong(v, bar, dyn, depth - 1);
    }
}

static void WCRestoreStrong(UIView *root, int depth) {
    if (depth < 0 || !root) return;
    gWCRestoreDepth++;
    for (UIView *v in root.subviews) {
        if ([v isKindOfClass:[UIVisualEffectView class]]) {
            UIVisualEffectView *ev = (UIVisualEffectView *)v;
            UIVisualEffect *orig = objc_getAssociatedObject(ev, &kWCOrigEffectKey);
            if (orig) {
                ev.effect = orig;
                objc_setAssociatedObject(ev, &kWCOrigEffectKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            UIColor *cb = objc_getAssociatedObject(ev.contentView, &kWCOrigBGKey);
            if (cb) {
                ev.contentView.backgroundColor = cb;
                objc_setAssociatedObject(ev.contentView, &kWCOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        UIColor *ob = objc_getAssociatedObject(v, &kWCOrigBGKey);
        if (ob) {
            v.backgroundColor = ob;
            objc_setAssociatedObject(v, &kWCOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        WCRestoreStrong(v, depth - 1);
    }
    gWCRestoreDepth--;
}

static void WCRestoreBar(UIView *bar) {
    NSNumber *forced = objc_getAssociatedObject(bar, &kWCForcedKey);
    if (!forced.boolValue) return;
    if (bar.overrideUserInterfaceStyle == UIUserInterfaceStyleDark) bar.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
    UIColor *fb = objc_getAssociatedObject(bar, &kWCFallbackKey);
    UIColor *dyn = objc_getAssociatedObject(bar, &kWCDynKey);
    if (fb && bar.backgroundColor == dyn) bar.backgroundColor = fb;
    for (UIView *v in (NSMutableArray *)objc_getAssociatedObject(bar, &kWCHiddenViewsKey)) v.hidden = NO;
    objc_setAssociatedObject(bar, &kWCHiddenViewsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WCRestoreStrong(bar, 4);
    if ([bar isKindOfClass:[UINavigationBar class]]) {
        UIImage *orig = objc_getAssociatedObject(bar, &kWCOrigNavImageKey);
        [(UINavigationBar *)bar setBackgroundImage:orig forBarMetrics:UIBarMetricsDefault];
        UIColor *tint = objc_getAssociatedObject(bar, &kWCOrigTintKey);
        [(UINavigationBar *)bar setBarTintColor:tint];
    }
    objc_setAssociatedObject(bar, &kWCForcedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void WCForceBar(UIView *bar, NSString *module, int depth) {
    if (!bar) return;
    // v8.5：深浅认微信自己的状态（探针维护的 gWCWeChatDark），不看栏的 trait
    BOOL dark = gWCWeChatDark;
    if ([module isEqualToString:@"chatbar"]) WCFieldSweep(bar);
    if (!dark || !WCConfigColor(module)) { WCRestoreBar(bar); return; }
    if (bar.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    NSNumber *forced = objc_getAssociatedObject(bar, &kWCForcedKey);
    UIColor *dyn = objc_getAssociatedObject(bar, &kWCDynKey);
    if (!forced.boolValue) {
        UIColor *cur = bar.backgroundColor;
        UIColor *fb = cur ? [cur resolvedColorWithTraitCollection:WCLightTrait()] : [UIColor clearColor];
        objc_setAssociatedObject(bar, &kWCFallbackKey, fb, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dyn = WCDynamicColor(module, fb);
        objc_setAssociatedObject(bar, &kWCDynKey, dyn, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([bar isKindOfClass:[UINavigationBar class]]) {
            UIImage *orig = [(UINavigationBar *)bar backgroundImageForBarMetrics:UIBarMetricsDefault];
            if (orig) objc_setAssociatedObject(bar, &kWCOrigNavImageKey, orig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            UIColor *tint = [(UINavigationBar *)bar barTintColor];
            if (tint) objc_setAssociatedObject(bar, &kWCOrigTintKey, tint, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(bar, &kWCForcedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // 全屏宿主（MMInputToolView 440×956）绝不涂根：透明覆盖层涂了会盖死消息页（v3.4 定案）
    if (bar.bounds.size.height > 200) {
        UIColor *fb = objc_getAssociatedObject(bar, &kWCFallbackKey);
        if (fb && bar.backgroundColor == dyn) bar.backgroundColor = fb;
    } else if (bar.backgroundColor != dyn) {
        bar.backgroundColor = dyn;
    }
    if ([bar isKindOfClass:[UINavigationBar class]]) {
        UIColor *cfg = WCConfigColor(module);
        UIImage *img = cfg ? WCSolidImage(cfg) : nil;
        UINavigationBar *nb = (UINavigationBar *)bar;
        if (img && [nb backgroundImageForBarMetrics:UIBarMetricsDefault] != img)
            [nb setBackgroundImage:img forBarMetrics:UIBarMetricsDefault];
        if (nb.barTintColor != dyn) nb.barTintColor = dyn;
    }
    WCApplyStrong(bar, bar, dyn, depth);
    for (UIView *v in bar.subviews) {
        if ([v isKindOfClass:[UIVisualEffectView class]]) continue;
        UIColor *bg = v.backgroundColor;
        if (bg && bg != dyn && WCIsOpaqueDarkNeutral(bg)) { WCStoreOrigBG(v); v.backgroundColor = dyn; }
    }
}


#pragma mark - 聊天底栏钩子（仅 MMInputToolView / InputToolContainerView）

static IMP gO_InT, gO_InW, gO_ContT, gO_ContW;
static void WC_In_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_InT)(s, c, p); if (s.window) WCForceBar(s, @"chatbar", 4); }
static void WC_In_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_InW)(s, c); if (!gBarsInput) gBarsInput = [[NSHashTable weakObjectsHashTable] retain]; if (s.window) { WCRegisterBar(gBarsInput, s); WCForceBar(s, @"chatbar", 4); } }
static void WC_Cont_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_ContT)(s, c, p); if (s.window) WCForceBar(s, @"chatbar", 4); }
static void WC_Cont_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_ContW)(s, c); if (!gBarsInput) gBarsInput = [[NSHashTable weakObjectsHashTable] retain]; if (s.window) { WCRegisterBar(gBarsInput, s); WCForceBar(s, @"chatbar", 4); } }

static void WCInstallChatbarHooks(void) {
    Class c;
    c = NSClassFromString(@"MMInputToolView");
    if (c && !gO_InT) { gO_InT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_In_trait); gO_InW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_In_window); }
    c = NSClassFromString(@"InputToolContainerView");
    if (c && !gO_ContT) { gO_ContT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_Cont_trait); gO_ContW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_Cont_window); }
}

static IMP gOrigDicSetHidden, gOrigDicWindow;
static BOOL WCDicShouldHide(UIView *v) {
    // v5.7：话筒去掉不分深浅（用户要求白色下也没有）；只剩 field 模块这一道总闸，
    // 模块设为原色或总开关关时，钩子透传、巡逻还原，图标回到原样
    (void)v;
    return WCConfigColor(@"field") != nil;
}
static void WC_Dic_setHidden(UIView *self, SEL _cmd, BOOL hidden) {
    // v5.6：话筒图标的显隐开关直接拦——深色+输入框模块开时，微信怎么设都按隐藏走，
    // 不给它在状态切换瞬间闪现的机会（v5.5 靠 0.4 秒巡逻去藏，切换时总慢一拍，
    // 视频末尾那一下闪跳就是这么来的）
    if (!hidden && WCDicShouldHide(self)) hidden = YES;
    ((void (*)(id, SEL, BOOL))gOrigDicSetHidden)(self, _cmd, hidden);
}
static void WC_Dic_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigDicWindow)(self, _cmd);
    if (self.window && WCDicShouldHide(self) && !self.hidden)
        ((void (*)(id, SEL, BOOL))gOrigDicSetHidden)(self, _cmd, YES);
}



#pragma mark - 底部 tab 栏钩子（仅玻璃栏本体，v8.5：用户要纯黑）
// 可见底栏是包内玻璃插件 WCTabBarGlass 自己造的 UITabBar（WCGNativeTabBar），
// 不走微信色板、只认 trait；源头 remap 够不到它。做法同聊天底栏：钩 trait 翻面
// 与入窗，深浅只看栏自己的 trait，无状态机、无探针、无巡逻。

static IMP gO_TabT, gO_TabW, gO_TabViewT, gO_TabViewW, gO_MMTabT, gO_MMTabW;
static void WC_Tab_reg(UIView *s) { if (!gBarsTab) gBarsTab = [[NSHashTable weakObjectsHashTable] retain]; WCRegisterBar(gBarsTab, s); }
static void WC_Tab_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_TabT)(s, c, p); if (s.window) WCForceBar(s, @"tab", 4); }
static void WC_Tab_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_TabW)(s, c); if (s.window) { WC_Tab_reg(s); WCForceBar(s, @"tab", 4); } }
static void WC_TabView_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_TabViewT)(s, c, p); if (s.window) WCForceBar(s, @"tab", 4); }
static void WC_TabView_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_TabViewW)(s, c); if (s.window) { WC_Tab_reg(s); WCForceBar(s, @"tab", 4); } }
static void WC_MMTab_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_MMTabT)(s, c, p); if (s.window) WCForceBar(s, @"tab", 4); }
static void WC_MMTab_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_MMTabW)(s, c); if (s.window) { WC_Tab_reg(s); WCForceBar(s, @"tab", 4); } }

static void WCInstallTabHooks(void) {
    Class c;
    c = NSClassFromString(@"WCGNativeTabBar");
    if (c && !gO_TabT) { gO_TabT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_Tab_trait); gO_TabW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_Tab_window); }
    c = NSClassFromString(@"WCTabBarView");
    if (c && !gO_TabViewT) { gO_TabViewT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_TabView_trait); gO_TabViewW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_TabView_window); }
    c = NSClassFromString(@"MMTabBar");
    if (c && !gO_MMTabT) { gO_MMTabT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_MMTab_trait); gO_MMTabW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_MMTab_window); }
}

#pragma mark - v6 底层色源（WCColorMgr 按名发色，在发色处换深色值）

// 微信全 App 的深色出自包内 DesignToken 色板（weui_color*.xml，178 个色名），
// 运行时由 WCColorMgr 按名发色：getColor: / getColorValueForName: 是仅有的两个
// 按名取色入口，MMDynamicColor 是它发出的明暗对载体（toColor 解析当前模式），
// WCColorProxy 是品牌色的按模式解析代理。v6 只钩这三处：按色名（或 BG 家族的
// 深色值）把深色换成模块色，浅色原样。视图拿到手就是换好的动态色，深浅切换
// 由系统自己重解析——不再有注册表、强刷定时器和设色拦截。
static NSDictionary *WCNameModuleMap(void) {
    static NSDictionary *map = nil;
    if (!map) {
        map = [[NSDictionary alloc] initWithObjectsAndKeys:
                        @"bg", @"BG_0",
            @"bg", @"BG_1",
            @"bg", @"BG_2",
            @"cell", @"BG_3",
            @"field", @"ActionSheet_BG",
            @"field", @"BG_5",
            @"field", @"Dialog_BG",
            @"field", @"SearchBar_ForHomepage_SearchBox_BG",
            @"field", @"Sheet_BG",
                                    @"bg", @"Filter_DropDown_DarkerBG",
            @"bg", @"Filter_DropDown_DefaultBG",
            @"bg", @"Filter_Option_DarkerBG",
            @"bg", @"Filter_Option_DefaultBG",
            @"bg", @"Filter_Option_SelectedBG",
                        @"bg", @"SearchBar_HomepageBG",
            @"bg", @"SearchBar_WhiteBG",
                        @"bg", @"TabGroup_BG",
            @"bg", @"TabGroup_White_BG",
            @"bg", @"Table_ButtonRow_BG",
            @"bg", @"Table_ChatRow_BG",
            @"bg", @"Table_ChatRow_Pinned_BG",
            @"bg", @"Table_ProfileRow_BG",
            @"bg", @"Table_Row_BG",
            @"bg", @"Table_Row_Card_GreyCard_BG",
            @"bg", @"Table_TextField_BG",
            @"bg", @"Table_TextField_Card_GreyCard_BG",
            @"bg", @"Toolbar_Chat_Input_BG",
            @"bg", @"Toolbar_OfficialAccount_Input_BG",
                                                                                    nil];
    }
    return map;
}

static NSMutableDictionary *gWCNameCache, *gWCNameHits;
static NSMutableDictionary *gWCSeenNames, *gWCSeenValueNames;
static long gWCToColorHits, gWCProxyHits, gWCValueStrHits;

static void WCNoteSeen(NSMutableDictionary *dict, NSString *name) {
    if (!dict || !name) return;
    @synchronized (dict) {
        dict[name] = @([dict[name] longValue] + 1);
    }
}

static NSString *WCValueModuleForDark(UIColor *color) {
    if (!color) return nil;
    NSString *hex = WCHexOfColor(color); // 已按深色 trait 解析
    if (hex.length < 7 || [hex characterAtIndex:0] != '#') return nil;
    unsigned int v = 0;
    [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(1, 6)]] scanHexInt:&v];
    int gray = (v >> 16) & 0xFF;
    if (((v >> 8) & 0xFF) != gray || (v & 0xFF) != gray) return nil;
    switch (gray) {
        case 0x11: case 0x12: case 0x19: case 0x1E: return @"bg";   // BG_0/BG_2/BG_1
        case 0x20: return @"cell";                                   // BG_3
        case 0x2C: return @"field";                                  // BG_5
        default: return nil;
    }
}

// 换色包装：深色取当前模块配置（实时读，改设置即时生效），浅色与关模块时回原值
static UIColor *WCSourceDynamic(NSString *module, UIColor *orig) {
    UIColor *light = [orig resolvedColorWithTraitCollection:WCLightTrait()];
    UIColor *darkOrig = [orig resolvedColorWithTraitCollection:WCDarkTrait()];
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) {
            UIColor *cfg = WCConfigColor(module);
            if (cfg) return cfg;
            return darkOrig;
        }
        return light;
    }];
}

static IMP gOrigGetColor, gOrigGetColorValue, gOrigToColor, gOrigProxyResolve, gOrigSetCurrentType;
static id gWCMgr = nil;

static id WC_WCColorMgr_getColor(id self, SEL _cmd, NSString *name) {
    gWCMgr = self;
    WCRefreshDarkState(NO);
    WCNoteSeen(gWCSeenNames, name);
    id orig = ((id (*)(id, SEL, id))gOrigGetColor)(self, _cmd, name);
    if (!orig || !name || !WCEnabled()) return orig;
    NSString *module = WCNameModuleMap()[name];
    if (!module || !WCConfigColor(module)) return orig;
    @synchronized (gWCNameCache) {
        id cached = gWCNameCache[name];
        if (cached) return cached;
    }
    id remapped = nil;
    Class dynCls = NSClassFromString(@"MMDynamicColor");
    if (dynCls && [orig isKindOfClass:dynCls]) {
        UIColor *newDark = WCSourceDynamic(module, [orig darkmodeColor]);
        remapped = [dynCls DynamicColorWithNormalColor:[orig normalColor] darkmodeColor:newDark];
    } else if ([orig isKindOfClass:[UIColor class]]) {
        remapped = WCSourceDynamic(module, (UIColor *)orig);
    }
    if (!remapped) return orig;
    @synchronized (gWCNameCache) {
        gWCNameCache[name] = remapped;
        gWCNameHits[name] = @([gWCNameHits[name] longValue] + 1);
    }
    return remapped;
}

static id WC_WCColorMgr_getColorValue(id self, SEL _cmd, NSString *name) {
    WCNoteSeen(gWCSeenValueNames, name);
    id orig = ((id (*)(id, SEL, id))gOrigGetColorValue)(self, _cmd, name);
    if (!orig || !name || !WCEnabled()) return orig;
    NSString *module = WCNameModuleMap()[name];
    UIColor *cfg = module ? WCConfigColor(module) : nil;
    if (!cfg) return orig;
    NSArray *parts = [(NSString *)orig componentsSeparatedByString:@","];
    if (parts.count != 2) return orig;
    NSString *dark = parts[1];
    if (dark.length < 7 || [dark characterAtIndex:0] != '#') return orig;
    NSString *hex = [WCHexOfColor(cfg) substringFromIndex:1]; // RRGGBB
    NSString *newDark = [@"#" stringByAppendingString:(dark.length > 7 ? [hex stringByAppendingString:[dark substringFromIndex:7]] : hex)];
    gWCValueStrHits++;
    return [NSString stringWithFormat:@"%@,%@", parts[0], newDark];
}

static UIColor *WC_MMDynamicColor_toColor(id self, SEL _cmd) {
    UIColor *orig = ((UIColor *(*)(id, SEL))gOrigToColor)(self, _cmd);
    if (!orig || !WCEnabled()) return orig;
    if ([UITraitCollection currentTraitCollection].userInterfaceStyle != UIUserInterfaceStyleDark) return orig;
    NSString *module = WCValueModuleForDark(orig);
    UIColor *cfg = module ? WCConfigColor(module) : nil;
    if (!cfg) return orig;
    gWCToColorHits++;
    return cfg;
}

#pragma mark - v8.5 微信深浅探针（问微信自己，不看视图 trait）

static BOOL WCProbeWeChatDarkIn(BOOL fresh) {
    static NSTimeInterval last = 0;
    static BOOL cached = NO;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!fresh && now - last < 0.5) return cached;
    last = now;
    BOOL dark = ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark);
    Class dynCls = NSClassFromString(@"MMDynamicColor");
    if (gWCMgr && gOrigGetColor && gOrigToColor && dynCls) {
        id c = ((id (*)(id, SEL, id))gOrigGetColor)(gWCMgr, @selector(getColor:), @"BG_0");
        if (c && [c isKindOfClass:dynCls]) {
            UIColor *resolved = ((UIColor *(*)(id, SEL))gOrigToColor)(c, @selector(toColor));
            NSString *aD = WCHexOfColorIn(resolved, WCDarkTrait());
            NSString *aL = WCHexOfColorIn(resolved, WCLightTrait());
            if ([aD isEqualToString:aL]) dark = [aD isEqualToString:WCHexOfColor([c darkmodeColor])];
        }
    }
    cached = dark;
    return dark;
}
static BOOL WCProbeWeChatDark(void) { return WCProbeWeChatDarkIn(NO); }
static BOOL WCProbeWeChatDarkNow(void) { return WCProbeWeChatDarkIn(YES); }

static void WCApplyBarsState(void) {
    if (gBarsTab) for (UIView *b in gBarsTab.allObjects) if (b.window) WCForceBar(b, @"tab", 4);
    if (gBarsInput) for (UIView *b in gBarsInput.allObjects) if (b.window) WCForceBar(b, @"chatbar", 4);
}

// v8.7：从后台切回微信时玻璃底栏卡平灰（视频逐帧采样：全栏均匀约 37、透视感
// 全无），点任意按钮即恢复。定性：玻璃插件的模糊状态在退后台后失效，它自己
// 没在回前台时刷新；首页/通讯录回前台时页面本身会刷新一遍、顺带把它带活，
// 发现/我两个静态页不会，所以只在这两页犯。修法：回前台事件一到，替它补那
// 一下——它自带的 refresh/applyParameters 在就调，再强制走一遍它的布局（它
// 的参数重申就挂在布局里），最后重申我方栏状态。一次性事件触发，无常驻开销。
static void WCGlassResumeRefresh(void) {
    if (gBarsTab) for (UIView *bar in gBarsTab.allObjects) {
        if (!bar.window) continue;
        if ([bar respondsToSelector:@selector(refresh)]) [bar performSelector:@selector(refresh)];
        if ([bar respondsToSelector:@selector(applyParameters)]) [bar performSelector:@selector(applyParameters)];
        [bar setNeedsLayout];
        [bar layoutIfNeeded];
    }
    WCApplyBarsState();
}
static void WCOnDidBecomeActive(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCGlassResumeRefresh(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCGlassResumeRefresh(); });
}

static void WCRefreshDarkState(BOOL fresh) {
    BOOL d = fresh ? WCProbeWeChatDarkNow() : WCProbeWeChatDark();
    if (d == gWCWeChatDark) return;
    gWCWeChatDark = d;
    if ([NSThread isMainThread]) WCApplyBarsState();
    else dispatch_async(dispatch_get_main_queue(), ^{ WCApplyBarsState(); });
}

static void WC_WCColorMgr_setCurrentType(id self, SEL _cmd, long type) {
    ((void (*)(id, SEL, long))gOrigSetCurrentType)(self, _cmd, type);
    WCRefreshDarkState(YES);
}

static UIColor *WC_Proxy_colorInStyle(id self, SEL _cmd, long style) {
    UIColor *orig = ((UIColor *(*)(id, SEL, long))gOrigProxyResolve)(self, _cmd, style);
    if (!orig || style != UIUserInterfaceStyleDark || !WCEnabled()) return orig;
    NSString *module = WCValueModuleForDark(orig);
    UIColor *cfg = module ? WCConfigColor(module) : nil;
    if (!cfg) return orig;
    gWCProxyHits++;
    return cfg;
}

// v7：微信自己的主题切换事件（WCColorMgr 的类型 setter）。只钉栏，不配色。
@interface WCBlackSettingsViewController : UIViewController <UITableViewDataSource, UITableViewDelegate, UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *pickingModule;
@end

@implementation WCBlackSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WCBlack 纯黑背景";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(wcReload) name:@"WCBlackConfigChanged" object:nil];
}
- (void)wcReload { [self.tableView reloadData]; }
- (void)wcToggleSep:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kWCHideSepKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"WCBlackConfigChanged" object:nil];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 2) return 1;
    return (NSInteger)WCModules().count;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"总开关";
    if (s == 2) return @"其他";
    return @"各模块颜色（仅深色模式生效）";
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) return @"点模块选颜色：纯黑 / 深灰 / 石墨 / 色谱选择 / 输入色值 / 原色（关闭该模块）。改完即时生效，不用重启微信。";
    if (s == 2) return @"去掉首页会话列表里每行下面的分割线，只对首页生效，关掉开关即恢复。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    if (ip.section == 0) {
        cell.textLabel.text = @"启用 WCBlack";
        cell.detailTextLabel.text = WCEnabled() ? @"开" : @"关";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
    } else if (ip.section == 2) {
        cell.textLabel.text = @"隐藏首页分割线";
        cell.detailTextLabel.text = WCHideSep() ? @"开" : @"关";
        cell.accessoryType = UITableViewCellAccessoryNone;
        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
        sw.on = WCHideSep();
        [sw addTarget:self action:@selector(wcToggleSep:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        [sw release];
    } else {
        NSString *m = WCModules()[ip.row];
        cell.textLabel.text = WCModuleTitle(m);
        NSString *hex = WCConfigHex(m);
        cell.detailTextLabel.text = hex ?: @"原色（关）";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        UIView *sw = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 18, 18)];
        sw.layer.cornerRadius = 9;
        sw.layer.borderWidth = 0.5;
        sw.layer.borderColor = [UIColor separatorColor].CGColor;
        sw.backgroundColor = hex ? WCColorFromHex(hex) : [UIColor clearColor];
        cell.accessoryView = sw;
    }
    return cell;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 2) {
        BOOL on = !WCHideSep();
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:kWCHideSepKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WCBlackConfigChanged" object:nil];
        return;
    }
    if (ip.section == 0) {
        BOOL on = !WCEnabled();
        [[NSUserDefaults standardUserDefaults] setBool:on forKey:kWCEnabledKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"WCBlackConfigChanged" object:nil];
        return;
    }
    NSString *m = WCModules()[ip.row];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:WCModuleTitle(m) message:@"选一个颜色，或输自定义色值（如 #1A1A1A）" preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *presets = @[@"#000000", @"#1A1A1A", @"#242424"];
    NSArray *names = @[@"纯黑 #000000", @"深灰 #1A1A1A", @"石墨 #242424"];
    for (NSUInteger i = 0; i < presets.count; i++) {
        NSString *hex = presets[i];
        [ac addAction:[UIAlertAction actionWithTitle:names[i] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { WCSetConfigHex(m, hex); }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"色谱选择…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self wcOpenPickerForModule:m]; }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"输入色值…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [self wcCustomHexForModule:m]; }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"原色（关闭此模块）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { WCSetConfigHex(m, nil); }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}
- (void)wcOpenPickerForModule:(NSString *)m {
    self.pickingModule = m;
    UIColorPickerViewController *picker = [[UIColorPickerViewController alloc] init];
    picker.delegate = self;
    picker.supportsAlpha = NO;
    NSString *hex = WCConfigHex(m);
    if (hex) picker.selectedColor = WCColorFromHex(hex);
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)vc {
    if (!self.pickingModule) return;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if ([vc.selectedColor getRed:&r green:&g blue:&b alpha:&a]) {
        NSString *hex = [NSString stringWithFormat:@"#%02X%02X%02X", (int)lrint(r * 255), (int)lrint(g * 255), (int)lrint(b * 255)];
        WCSetConfigHex(self.pickingModule, hex);
    }
    self.pickingModule = nil;
}
- (void)wcCustomHexForModule:(NSString *)m {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:WCModuleTitle(m) message:@"输入 #RRGGBB" preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"#000000"; tf.text = WCConfigHex(m); }];
    [ac addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *t = ac.textFields.firstObject.text;
        if (t.length == 7 && [t hasPrefix:@"#"]) WCSetConfigHex(m, [t uppercaseString]);
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}
@end
static BOOL gInstalled = NO, gRegistered = NO;
// 插件列表注册改「在列确认制」：注册后回读管理器列表，确认有 WCBlack 条目才算数；
// 没确认就由强刷每约 2 秒重试。旧写法只在启动 4 秒内试几次、且试一次就置 gRegistered，
// 管理器（wcplugins）初始化稍慢或列表被重建，注册就永久丢失——v4.3 真机列表里没了
// WCBlack 就是这么来的（插件本体一直在跑，顶部照样刷黑，只是入口没了）。
static void WCEnsureRegistered(void) {
    if (gRegistered) return;
    Class mgr = NSClassFromString(@"WCPluginsMgr");
    if (!mgr || ![mgr respondsToSelector:@selector(sharedInstance)]) return;
    id inst = ((id (*)(id, SEL))objc_msgSend)(mgr, @selector(sharedInstance));
    if (!inst) return;
    NSArray *existing = nil;
    @try { existing = [inst valueForKey:@"plugins"]; } @catch (id e) { existing = nil; }
    for (id p in existing) {
        NSString *t = nil;
        @try { t = [p valueForKey:@"title"]; } @catch (id e) { t = nil; }
        if ([t containsString:@"WCBlack"]) { gRegistered = YES; return; }
    }
    if (![inst respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) return;
    ((void (*)(id, SEL, id, id, id))objc_msgSend)(inst, @selector(registerControllerWithTitle:version:controller:),
        @"WCBlack 纯黑背景", @"8.5", @"WCBlackSettingsViewController");
    NSArray *after = nil;
    @try { after = [inst valueForKey:@"plugins"]; } @catch (id e) { after = nil; }
    for (id p in after) {
        NSString *t = nil;
        @try { t = [p valueForKey:@"title"]; } @catch (id e) { t = nil; }
        if ([t containsString:@"WCBlack"]) {
            gRegistered = YES;
            os_log(WCLog(), "[WCBlack] v8.8 registered in plugin list");
            break;
        }
    }
}

#pragma mark - 家务 tick（注册重试 + 分割线扫描，5 秒）

static void WCHousekeepingTick(void) {
    WCEnsureRegistered();
    WCRefreshDarkState(NO);
    if (gBarsInput) for (UIView *b in gBarsInput.allObjects) if (b.window) WCFieldSweep(b);
    if (gBarsTab) for (UIView *b in gBarsTab.allObjects) if (b.window) WCForceBar(b, @"tab", 4);
    if (gSepTables) for (UITableView *tv in gSepTables.allObjects) if (tv.window) WCApplySeparators(tv);
}

static dispatch_source_t gHouseTimer;
static void WCStartHousekeepingTimer(void) {
    if (gHouseTimer) return;
    gHouseTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gHouseTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)),
                              (uint64_t)(5.0 * NSEC_PER_SEC), (uint64_t)(0.5 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(gHouseTimer, ^{ WCHousekeepingTick(); });
    dispatch_resume(gHouseTimer);
}

#pragma mark - 安装（只做 swizzle）

static BOOL gSrcHooked = NO;
static void WCInstall(void) {
    if (!gWCNameCache) {
        gWCNameCache = [[NSMutableDictionary alloc] init];
        gWCNameHits = [[NSMutableDictionary alloc] init];
        gWCSeenNames = [[NSMutableDictionary alloc] init];
        gWCSeenValueNames = [[NSMutableDictionary alloc] init];
    }
    if (!gSrcHooked) {
        Class mgr = NSClassFromString(@"WCColorMgr");
        Class dyn = NSClassFromString(@"MMDynamicColor");
        Class proxy = NSClassFromString(@"WCColorProxy");
        if (mgr && dyn && proxy) {
            if (!gOrigGetColor) gOrigGetColor = WCSwap(mgr, @selector(getColor:), (IMP)WC_WCColorMgr_getColor);
            if (!gOrigSetCurrentType) gOrigSetCurrentType = WCSwap(mgr, @selector(setCurrentType:), (IMP)WC_WCColorMgr_setCurrentType);
            if (!gOrigGetColorValue) gOrigGetColorValue = WCSwap(mgr, @selector(getColorValueForName:), (IMP)WC_WCColorMgr_getColorValue);
            if (!gOrigToColor) gOrigToColor = WCSwap(dyn, @selector(toColor), (IMP)WC_MMDynamicColor_toColor);
            if (!gOrigProxyResolve) gOrigProxyResolve = WCSwap(proxy, @selector(colorInCurrentUserInterfaceStyle:), (IMP)WC_Proxy_colorInStyle);
            if (gOrigGetColor && gOrigGetColorValue && gOrigToColor && gOrigProxyResolve) {
                gSrcHooked = YES;
                os_log(WCLog(), "[WCBlack] v8.8 source hooks in");
            }
        }
    }
    // 话筒钩子（v5.6/v5.7 定案：按类名当即按回隐藏，只受 field 总闸）
    static BOOL dicHooked = NO;
    if (!dicHooked) {
        Class dic = NSClassFromString(@"MMGrowDictationIconView");
        if (dic) {
            gOrigDicSetHidden = WCSwapOwn(dic, @selector(setHidden:), (IMP)WC_Dic_setHidden);
            gOrigDicWindow = WCSwapOwn(dic, @selector(didMoveToWindow), (IMP)WC_Dic_didMoveToWindow);
            if (gOrigDicSetHidden && gOrigDicWindow) dicHooked = YES;
        }
    }
    WCInstallChatbarHooks();
    WCInstallSepGate();
    WCInstallCellSepHooks();
    WCInstallTabHooks();
    static id wcActiveToken = nil;
    if (!wcActiveToken) {
        wcActiveToken = [[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { WCOnDidBecomeActive(); }] retain];
    }
    WCEnsureRegistered();
    WCStartHousekeepingTimer();
    gInstalled = YES;
}

@interface WCBlackLoader : NSObject
@end
@implementation WCBlackLoader
+ (void)load {
    WCInstall();
    dispatch_async(dispatch_get_main_queue(), ^{ WCInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCInstall(); });
}
@end
