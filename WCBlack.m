// WCBlack.m — 微信深色模式纯黑背景 v6.2 (2026-11-26)
// v4.0（按用户要求改底层，废弃「先灰后黑」的定时强刷作为主力）：用户录屏指出首页顶部与
//   聊天底栏进页面时先灰、片刻才被强刷成黑——那是 0.4 秒定时器后手赋色的固有延迟。静态定案
//   微信 8.0.80 的原生界面颜色来自 DesignToken 设计令牌（包内 weui_color_new.xml，值与采样
//   逐一对上：BG_0 深色 #111111=主背景、BG_2 #191919=列表、BG_3 #202020=置顶/卡片、
//   Material_NavigationBar #121212E5=导航材质、Material_Toolbar #232323ED=工具栏材质）。
//   v4 改在令牌解析处拦截：运行时扫描全部类、hook getColorByName:/colorByName: 的属主类，
//   命中令牌映射（BG_0/1/2→bg、BG_3→cell、Material_NavigationBar→nav、Material_Toolbar/
//   Material_Thick→chatbar）时直接返回「深色=配置色、浅色=原令牌浅色值」的动态色——所有界面
//   在创建时第一帧就是目标色，无闪烁、不依赖后手强刷。被查询过的令牌名+原始深色值记入诊断，
//   映射漏了哪个令牌下版照单补。原有 setter 替换/注册表强刷/扫描保留作兜底（玻璃插件的
//   WCTabBarView 不是微信令牌体系，仍靠扫描）；键盘窗口处理（v3.5）保留。
// v3.5：v3.4 真机（视频+快照）确认深色下列表/聊天/顶栏/输入栏/tab 已全黑、扫描注册生效
//   （registry input=3，InputToolContainerView 与 InputToolViewBar 均 #000000）。用户新指出：
//   键盘升起时键盘面板的灰底（#222 采样）也要纯黑。键盘窗口 UIRemoteKeyboardWindow 同在本
//   进程的 windows 列表里——新增键盘窗口处理：窗口自身与其子视图按 chatbar 模块强刷
//   （窗口背景+ApplyStrong 遍历，含进程内的 dock/特效视图），浅色按存档恢复；首次见到键盘
//   窗口时把它的视图树存进诊断，万一灰底是键盘进程远程渲染的，树里只有占位视图即可见分晓。
// v3.4：据 v3.3 真机诊断快照定案与修复（快照证实可见底栏是玻璃插件的 WCTabBarView、
//   原生 MMTabBar 不存在，tab 已被扫描强刷刷黑；聊天顶栏已黑）。剩三件事：
//   ①浅色模式顶部黑带——定案在 WCSanitizeLightFallback 的单色空间漏洞：微信主题灰是
//     monochrome 色，getRed 取不到值、净化被整段跳过，动态色浅色回退仍是深灰。改 getWhite
//     优先判定 + 透明度门槛放宽到 0.03（保留原 alpha 换白）。
//   ②聊天底栏：MMInputToolView 的 didMoveToWindow 钩子从未触发（三次快照 registry input
//     恒为 0），改扫描注册——每 2 秒扫全部窗口，类名含 InputTool 者登记进注册表由强刷接管，
//     含 MsgContentNavBar 者登记进 nav 表；首次找到输入栏后补采 chat 快照。
//   ③诊断升级：查找改为遍历全部窗口；新增注册表导航栏转储（含 appearance/背景图/barTint）、
//     顶部与底部条带 hitTest 祖先链、明暗切换后自动补采；设置页诊断改全屏页（可滚动+一键复制），
//     点开时即时重采。另：tab 候选与栏的子视图在浅色下按存档原件恢复（WCRestoreStrong/恢复
//     tab 的 appearance/barTint/背景图），深→浅切换不留残影。
// v3.3：并入 v3.2 全部内容，另修浅色模式顶部黑带（用户 09:07 截图）：动态色的浅色回退取自
//   深色下被赋值的静态深灰，切浅色后解析成 #17 左右的暗色。修：WCSanitizeLightFallback——
//   回退色在浅色下仍暗（亮度<0.5）一律换白；导航恢复时一并还原 barTintColor。
// v3.2：v3.1 真机导航（列表页）已黑、闪退已修；剩底部 tab、聊天底栏、聊天顶栏未变。
//   查玻璃插件字符串定案其有自有底栏类 WCGNativeTabBar/WCTabBarView，可见底栏可能不是 MMTabBar——
//   新增按类族+几何的兜底扫描强刷（UITabBar appearance 路径）；聊天顶栏补挂 MMMsgContentNavBar/
//   MMNewMsgContentNavBar；另加诊断快照（启动后与首次进聊天时各采一次窗口树条带链，存 defaults、
//   设置页底部展示），底栏/聊天栏若仍不动，靠快照定真身，不再盲猜。
// v2 真机结论：主背景/置顶行（setter 路径）已生效、设置页可达；但三栏靶向 layoutSubviews 零效果——
//   导航仍 #0F0F0F、tab 仍 #181818、聊天底栏仍 #1A~#1C。判定：栏的背景不是在 layout 里由
//   setBackgroundColor 定的（导航疑似背景图/图层，tab 有玻璃插件在同一布局链后手重绘），
//   一次性 layout 强制斗不过后手。v3 改为：三栏实例注册表 + 0.4s 定时强刷（谁最后画就再覆盖谁），
//   导航另强制 setBackgroundImage 为模块色纯色图；特效视图摘除前先存档原 effect，浅色时还原。
//   设置页自定义颜色新增系统色谱选择器（UIColorPickerViewController），保留输 hex。
// v3.1 修闪退（2026-11-26 崩溃日志 WeChat-2026-11-26-083637.ips 定案）：构建无 -fobjc-arc（MRC），
//   v3 把 [NSHashTable weakObjectsHashTable] 这类 autorelease 对象直接赋给全局变量、没 retain，
//   +load 阶段的自动释放池一排空表就被释放，指针指向的内存被回收复用——定时强刷遍历时撞上一个
//   UIViewController，对它发 window 直接 doesNotRecognizeSelector 崩溃（栈：WCEnforceRegistered）。
//   修：三表与色图缓存改 alloc/init 永久持有；cfgObserver token 补 retain；强刷遍历加 UIView 类型守卫。
// v1 真机结论（用户 2026-11-26 实测）：列表/聊天主背景已纯黑；但顶部导航、底部 tab、聊天底栏仍灰。
//   采样定案：导航实际 #0F0F0F（不在 v1 目标表内）；tab 渲染 #181818——包内 WCTabBarGlass.dylib
//   在 MMTabBar 上压了一层 UIVisualEffectView 毛玻璃，背景色改了也被它盖住；聊天底栏为
//   #1A~#1C 的半透明合成色，setter 精确匹配抓不到。置顶行 #202020 用户也要可调。
// v2 方案：模块化 + 可调。五个模块，各自在「我→设置→插件→WCBlack 纯黑背景」里选颜色：
//   主背景 bg（#111/#112/#191 系）、顶部导航 nav（#0F0F0F + MMUINavigationBar 靶向）、
//   底部 tab tab（MMTabBar 靶向，含摘毛玻璃）、聊天底栏 chatbar（MMInputToolView 靶向）、
//   置顶行/卡片 cell（#202020）。默认全部纯黑，选「原色」即关闭该模块。
// 机制：颜色层 hook（UIView setBackgroundColor / 系统栏 barTint）按目标灰阶分派到模块，
//   替换为动态色（深色=用户所选色，浅色=原色，切模式不残留）；三个栏类另走 layoutSubviews
//   靶向强制（含 UIVisualEffectView 摘除/上色），设置变更后全窗重扫一遍即时生效。
// 设置页注册走包内 wcplugins.dylib 的 WCPluginsMgr（registerControllerWithTitle:version:controller:，
//   controller 为类名字符串——已核 wcplugins 里 WCPluginModel.controller 的类型编码为 NSString）。
// 纯运行时 swizzle + +load，无 substrate 依赖。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>

static os_log_t WCLog(void) {
    static os_log_t l; static dispatch_once_t once;
    dispatch_once(&once, ^{ l = os_log_create("com.nova.wcblack", "v6.2"); });
    return l;
}

#pragma mark - 配置

static NSString *const kWCEnabledKey = @"WCBlack.enabled";
static NSArray<NSString *> *WCModules(void) { return @[@"bg", @"nav", @"tab", @"chatbar", @"cell", @"field"]; }
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
    return [module isEqualToString:@"field"] ? @"#1A1A1A" : @"#000000";
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

static UIColor *WCDynamicColor(NSString *module, UIColor *lightFallback) {
    UIColor *fb = WCSanitizeLightFallback(lightFallback);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) {
            UIColor *c = WCConfigColor(module);
            return c ?: fb;
        }
        return fb;
    }];
}

// setter 路径的替换：命中模块 -> 动态色（浅色回退为原色浅色解析值）

// ===== v6 瘦身声明（原注册表只供诊断查看，不再参与上色）=====
static char kWCOrigBGKey, kWCSepOrigStyleKey, kWCSepOrigColorKey, kWCSepHiddenKey, kWCPatchHiddenKey, kWCUnderlayKey;
static char kWCFallbackKey, kWCDynKey, kWCForcedKey, kWCOrigEffectKey, kWCHiddenViewsKey, kWCOrigNavImageKey, kWCOrigTintKey, kWCOrigStdAppKey, kWCOrigEdgeAppKey, kWCAlignTsKey;
static int gWCRestoreDepth = 0;
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
static BOOL WCIsTabCandidate(UIView *v) {
    if ([v isKindOfClass:[UITabBar class]]) return YES;
    NSString *cls = NSStringFromClass([v class]);
    return [cls isEqualToString:@"WCGNativeTabBar"] || [cls isEqualToString:@"WCTabBarView"] || [cls isEqualToString:@"MMTabBar"];
}
static NSHashTable<UIView *> *gBarsTab, *gBarsNav, *gBarsInput;

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

// v5.1 明暗切换时的存档作废（nav/input 栏用）：只清存档、不写背景值——切换瞬间微信
// 已经把自家背景写成新模式的值了，我们若按旧存档还原就会把它的新值盖掉（浅色顶部
// 黑带的核心成因之一）。导航背景图、tint、被替换的 effect、被藏起来的视图与明暗
// 无关，照常还原。清完后强刷会在新模式里重新存档。
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

static void WCApplySeparators(UITableView *tv) {
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
static void WCScanTablesInWindow(UIView *root, UIWindow *win, int depth) {
    if (!root || depth < 0) return;
    if ([root isKindOfClass:[UITableView class]]) {
        UITableView *tv = (UITableView *)root;
        NSString *d = NSStringFromClass([tv.delegate class]) ?: @"";
        NSString *ds = NSStringFromClass([tv.dataSource class]) ?: @"";
        if ([d containsString:@"MainFrame"] || [ds containsString:@"MainFrame"]) {
            CGRect f = [tv convertRect:tv.bounds toView:win];
            if (f.size.height >= win.bounds.size.height * 0.8 && f.size.width >= win.bounds.size.width * 0.9)
                WCApplySeparators(tv);
        }
    }
    for (UIView *s in root.subviews) WCScanTablesInWindow(s, win, depth - 1);
}


static void WCCollectDiag(NSString *scene);
static void WCEnsureRegistered(void);
static void WCAppendSourceStats(NSMutableString *out);

#pragma mark - 诊断快照（设置页展示，用户截图/复制即可，不用连电脑抓日志）

static NSString *WCHexOfColor(UIColor *c) {
    if (!c) return @"nil";
    UIColor *d = [c resolvedColorWithTraitCollection:WCDarkTrait()];
    CGFloat r = 0, g = 0, b = 0, a = 0, w = 0;
    if ([d getWhite:&w alpha:&a])
        return [NSString stringWithFormat:@"#%02X%02X%02X a%.2f", (int)lrint(w * 255), (int)lrint(w * 255), (int)lrint(w * 255), a];
    if (![d getRed:&r green:&g blue:&b alpha:&a]) return @"pat";
    return [NSString stringWithFormat:@"#%02X%02X%02X a%.2f", (int)lrint(r * 255), (int)lrint(g * 255), (int)lrint(b * 255), a];
}
static void WCDumpView(NSMutableString *out, UIView *v, int depth, int maxDepth) {
    if (!v || depth > maxDepth) return;
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    CGRect f = v.frame;
    [out appendFormat:@"%@%@ f=%.0f,%.0f,%.0f,%.0f bg=%@ now=%@ hid=%d\n", indent, NSStringFromClass([v class]),
        f.origin.x, f.origin.y, f.size.width, f.size.height, WCHexOfColor(v.backgroundColor),
        WCHexOfColor([v.backgroundColor resolvedColorWithTraitCollection:v.traitCollection]), v.hidden];
    if ([v isKindOfClass:[UIVisualEffectView class]]) {
        UIVisualEffectView *ev = (UIVisualEffectView *)v;
        [out appendFormat:@"%@  effect=%@\n", indent, ev.effect ? NSStringFromClass([ev.effect class]) : @"nil"];
    }
    for (UIView *s in v.subviews) WCDumpView(out, s, depth + 1, maxDepth);
}
// v5.0 输入框取证专用：连图层背景、圆角、子图层一起打——底色若是图层画的，这里见分晓
static void WCDumpFieldHunt(NSMutableString *out, UIView *v, int depth, int maxDepth) {
    if (!v || depth > maxDepth) return;
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    CGRect f = v.frame;
    UIColor *lbg = v.layer.backgroundColor ? [UIColor colorWithCGColor:v.layer.backgroundColor] : nil;
    [out appendFormat:@"%@%@ f=%.0f,%.0f,%.0f,%.0f bg=%@ layerBG=%@ radius=%.1f clips=%d sublayers=%lu\n",
        indent, NSStringFromClass([v class]), f.origin.x, f.origin.y, f.size.width, f.size.height,
        WCHexOfColor(v.backgroundColor), WCHexOfColor(lbg), v.layer.cornerRadius, (int)v.clipsToBounds,
        (unsigned long)v.layer.sublayers.count];
    for (CALayer *l in v.layer.sublayers) {
        UIColor *lc = l.backgroundColor ? [UIColor colorWithCGColor:l.backgroundColor] : nil;
        [out appendFormat:@"%@  layer %@ bg=%@\n", indent, NSStringFromClass([l class]), WCHexOfColor(lc)];
    }
    for (UIView *s in v.subviews) WCDumpFieldHunt(out, s, depth + 1, maxDepth);
}
static void WCDumpAncestors(NSMutableString *out, UIView *v) {
    [out appendString:@"-- ancestors --\n"];
    UIView *p = v.superview;
    int i = 0;
    while (p && i < 5) {
        CGRect f = p.frame;
        [out appendFormat:@"^ %@ f=%.0f,%.0f,%.0f,%.0f bg=%@\n", NSStringFromClass([p class]), f.origin.x, f.origin.y, f.size.width, f.size.height, WCHexOfColor(p.backgroundColor)];
        p = p.superview; i++;
    }
}
static UIView *WCFindInTree(UIView *root, BOOL (^pred)(UIView *), int depth) {
    if (!root || depth < 0) return nil;
    if (pred(root)) return root;
    for (UIView *s in root.subviews) { UIView *r = WCFindInTree(s, pred, depth - 1); if (r) return r; }
    return nil;
}
static void WCAppendDiagText(NSString *text) {
    NSString *old = [[NSUserDefaults standardUserDefaults] stringForKey:@"WCBlack.diag"];
    NSString *merged = old ? [NSString stringWithFormat:@"%@\n%@", old, text] : text;
    if (merged.length > 12000) merged = [merged substringFromIndex:merged.length - 12000];
    [[NSUserDefaults standardUserDefaults] setObject:merged forKey:@"WCBlack.diag"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

// 键盘窗口（UIRemoteKeyboardWindow）：同在本进程 windows 列表里。窗口自身背景与进程内
// 子视图（dock、占位/特效视图）按 chatbar 模块强刷；按键本体若是键盘进程远程渲染的图层，
// 本进程树里只会看到占位视图——首次见到时整树存进诊断，是不是远程渲染一眼可见。
static void WCForceKeyboardWindow(UIWindow *win) {
    if (!win) return;
    static BOOL kbdDiagDone = NO;
    if (!kbdDiagDone) {
        kbdDiagDone = YES;
        NSMutableString *out = [NSMutableString stringWithString:@"== WCBlack kbd window ==\n"];
        WCDumpView(out, win, 0, 7);
        // 存独立键、整段覆盖：共享诊断有 12000 字上限、快照多了会把这段从头部挤掉
        // （v4.2 真机粘贴里 kbd 段缺失就是这么丢的），独立键不受挤。
        [[NSUserDefaults standardUserDefaults] setObject:out forKey:@"WCBlack.kbd"];
    }
    // v4.6 紧急修正：这个窗口只存树、绝不上色。v4.5 把 UITextEffectsWindow 当键盘窗口强刷、
    // 给它涂了不透明黑背景——它是覆盖全屏、位于主窗口之上的系统窗口，键盘一弹起就整页
    // 盖黑（用户实测：开键盘页面卡住、内容消失）。而且树已证明面板是远程渲染：进程内只有
    // _UIRemoteKeyboardPlaceholderView 占位视图，没有任何本地底板可涂，涂它纯有害无益。
    // v6 起本插件不再给任何窗口上色，这段只剩存树。
}

static void WCCollectDiag(NSString *scene) {
    NSMutableString *out = [NSMutableString stringWithFormat:@"== WCBlack diag (%@) ==\n", scene];
    WCAppendSourceStats(out);
    [out appendFormat:@"registry tab=%lu nav=%lu input=%lu\n",
        (unsigned long)gBarsTab.count, (unsigned long)gBarsNav.count, (unsigned long)gBarsInput.count];
    // 窗口按 key 优先排序，查找遍历全部窗口（v3.3 只查 keyWindow，输入栏在别的窗口就找不到）
    NSMutableArray<UIWindow *> *wins = [NSMutableArray array];
    for (UIWindow *w in [UIApplication sharedApplication].windows) if (w.isKeyWindow) [wins addObject:w];
    for (UIWindow *w in [UIApplication sharedApplication].windows) if (!w.isKeyWindow) [wins addObject:w];
    // 注册表里的导航栏逐个转储：浅色黑带到底是哪根栏、什么状态，看这里
    [out appendString:@"-- NAV registry --\n"];
    BOOL anyNav = NO;
    for (id b in gBarsNav.allObjects) {
        if (![b isKindOfClass:[UIView class]]) continue;
        UIView *bar = (UIView *)b;
        if (!bar.window) continue;
        anyNav = YES;
        WCDumpView(out, bar, 0, 2);
        if ([bar isKindOfClass:[UINavigationBar class]]) {
            UINavigationBar *nb = (UINavigationBar *)bar;
            [out appendFormat:@"  [appearance bg=%@ tint=%@ bgImage=%@]\n",
                WCHexOfColor(nb.standardAppearance.backgroundColor),
                WCHexOfColor(nb.barTintColor),
                [nb backgroundImageForBarMetrics:UIBarMetricsDefault] ? @"set" : @"nil"];
        }
    }
    if (!anyNav) [out appendString:@"(none in window)\n"];
    UIWindow *tabWin = nil;
    UIView *tabFound = nil;
    for (UIWindow *win in wins) {
        UIView *tab = WCFindInTree(win, ^BOOL(UIView *v) {
            if (!WCIsTabCandidate(v)) return NO;
            CGRect f = [v convertRect:v.bounds toView:nil];
            return f.origin.y > win.bounds.size.height * 0.7;
        }, 12);
        [out appendString:@"-- TAB strip --\n"];
        if (tab) { WCDumpView(out, tab, 0, 2); WCDumpAncestors(out, tab); tabWin = win; tabFound = tab; }
        else [out appendString:@"(not found)\n"];
        UIView *input = WCFindInTree(win, ^BOOL(UIView *v) { return [NSStringFromClass([v class]) containsString:@"InputTool"]; }, 16);
        [out appendString:@"-- INPUT strip --\n"];
        if (input) { WCDumpView(out, input, 0, 2); WCDumpAncestors(out, input); } else [out appendString:@"(not found)\n"];
        UIView *hdr = WCFindInTree(win, ^BOOL(UIView *v) { NSString *c = NSStringFromClass([v class]); return [c containsString:@"MsgContentNavBar"]; }, 16);
        [out appendString:@"-- CHAT header --\n"];
        if (hdr) { WCDumpView(out, hdr, 0, 2); WCDumpAncestors(out, hdr); } else [out appendString:@"(not found)\n"];
        if (tab) break;
    }
    // 顶部/底部条带 hitTest：不管类名是什么，点到谁就顺祖先链看谁在画
    UIWindow *hw = tabWin ?: wins.firstObject;
    if (hw) {
        CGFloat W = hw.bounds.size.width, H = hw.bounds.size.height;
        [out appendString:@"-- TOP hit --\n"];
        UIView *hitT = [hw hitTest:CGPointMake(W / 2, 64) withEvent:nil];
        if (hitT) { WCDumpView(out, hitT, 0, 0); WCDumpAncestors(out, hitT); } else [out appendString:@"(none)\n"];
        [out appendString:@"-- BOTTOM hit --\n"];
        UIView *hitB = [hw hitTest:CGPointMake(W / 2, H - 44) withEvent:nil];
        if (hitB) { WCDumpView(out, hitB, 0, 0); WCDumpAncestors(out, hitB); } else [out appendString:@"(none)\n"];
        (void)tabFound;
    }
    // v5.0 专项取证：分割线（主列表 table 的 delegate 与分隔线状态）+ 输入框底色（带图层）
    {
        UIWindow *kw = wins.firstObject;
        [out appendString:@"-- SEP / FIELD hunt --\n"];
        if (gWCPatchInfo) [out appendFormat:@"PATCH hits: %@\n", gWCPatchInfo];
        UITableView *mt = kw ? (UITableView *)WCFindInTree(kw, ^BOOL(UIView *v) {
            if (![v isKindOfClass:[UITableView class]]) return NO;
            UITableView *t = (UITableView *)v;
            NSString *d = NSStringFromClass([t.delegate class]) ?: @"";
            NSString *ds = NSStringFromClass([t.dataSource class]) ?: @"";
            return [d containsString:@"MainFrame"] || [ds containsString:@"MainFrame"];
        }, 12) : nil;
        if (mt) [out appendFormat:@"mainTable delegate=%@ style=%ld sepColor=%@\n",
            NSStringFromClass([mt.delegate class]), (long)mt.separatorStyle, WCHexOfColor(mt.separatorColor)];
        else [out appendString:@"mainTable (not found)\n"];
        UIView *grow = kw ? WCFindInTree(kw, ^BOOL(UIView *v) { return [NSStringFromClass([v class]) isEqualToString:@"MMGrowTextView"]; }, 16) : nil;
        if (grow) WCDumpFieldHunt(out, grow, 0, 4);
        else [out appendString:@"growText (not found)\n"];
    }
    WCAppendDiagText(out);
}

// 配置变更后：全窗重扫，动态色重新解析、栏重新强制
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
// 收益为零、代价不可接受，故回退。v4.1 = v3.5 已验证基线 + 防闪与键盘捕获的非侵入改进。


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
            @"field", @"ActionSheet_BG",
            @"bg", @"BG_0",
            @"bg", @"BG_1",
            @"bg", @"BG_2",
            @"cell", @"BG_3",
            @"field", @"BG_5",
            @"field", @"Dialog_BG",
            @"bg", @"Filter_DropDown_DarkerBG",
            @"bg", @"Filter_DropDown_DefaultBG",
            @"bg", @"Filter_Option_DarkerBG",
            @"bg", @"Filter_Option_DefaultBG",
            @"bg", @"Filter_Option_SelectedBG",
            @"field", @"SearchBar_ForHomepage_SearchBox_BG",
            @"bg", @"SearchBar_HomepageBG",
            @"bg", @"SearchBar_WhiteBG",
            @"field", @"Sheet_BG",
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
static long gWCToColorHits, gWCProxyHits, gWCValueStrHits;

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

static IMP gOrigGetColor, gOrigGetColorValue, gOrigToColor, gOrigProxyResolve;
static id gWCMgr = nil;

static id WC_WCColorMgr_getColor(id self, SEL _cmd, NSString *name) {
    gWCMgr = self;
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

static UIColor *WC_Proxy_colorInStyle(id self, SEL _cmd, long style) {
    UIColor *orig = ((UIColor *(*)(id, SEL, long))gOrigProxyResolve)(self, _cmd, style);
    if (!orig || style != UIUserInterfaceStyleDark || !WCEnabled()) return orig;
    NSString *module = WCValueModuleForDark(orig);
    UIColor *cfg = module ? WCConfigColor(module) : nil;
    if (!cfg) return orig;
    gWCProxyHits++;
    return cfg;
}

static void WCAppendSourceStats(NSMutableString *out) {
    [out appendString:@"== WCBlack v6 source ==\n"];
    @synchronized (gWCNameCache) {
        NSArray *names = [gWCNameHits.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [gWCNameHits[b] compare:gWCNameHits[a]];
        }];
        [out appendFormat:@"getColor remaps: %lu names\n", (unsigned long)names.count];
        for (NSString *n in names) {
            if ([names indexOfObject:n] >= 20) break;
            [out appendFormat:@"  %@ x%@ -> %@\n", n, gWCNameHits[n], WCNameModuleMap()[n]];
        }
    }
    [out appendFormat:@"valueStr remaps: %ld | toColor remaps: %ld | proxy remaps: %ld\n", gWCValueStrHits, gWCToColorHits, gWCProxyHits];
}

#pragma mark - 设置页

// 诊断全文页：可滚动、可全选复制，右上角一键复制全部（v3.3 的页脚小框滚不动，废弃）
@interface WCDiagViewController : UIViewController
@property (nonatomic, strong) UITextView *textView;
@end
@implementation WCDiagViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"诊断信息";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    NSString *diag = [[NSUserDefaults standardUserDefaults] stringForKey:@"WCBlack.diag"];
    NSString *kbd = [[NSUserDefaults standardUserDefaults] stringForKey:@"WCBlack.kbd"];
    NSString *full = diag.length ? diag : @"（暂无诊断数据：先回首页停几秒、再随便进一个聊天页，然后回到本页点诊断）";
    if (kbd.length) full = [full stringByAppendingFormat:@"\n%@", kbd];
    self.textView.text = full;
    [self.view addSubview:self.textView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"复制全部" style:UIBarButtonItemStyleDone target:self action:@selector(wcCopyAll)];
}
- (void)wcCopyAll {
    [UIPasteboard generalPasteboard].string = self.textView.text;
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"已复制" message:@"切回聊天，长按输入框粘贴发我即可" preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}
@end

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

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 2) return 1;
    if (s == 3) return 1;
    return (NSInteger)WCModules().count;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"总开关";
    if (s == 2) return @"其他";
    if (s == 3) return @"诊断";
    return @"各模块颜色（仅深色模式生效）";
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) return @"点模块选颜色：纯黑 / 深灰 / 石墨 / 色谱选择 / 输入色值 / 原色（关闭该模块）。改完即时生效，不用重启微信。";
    if (s == 2) return @"去掉首页会话列表里每行下面的分割线，只对首页生效，关掉开关即恢复。";
    if (s == 3) return @"还有哪处不变色：先回首页停几秒、再随便进一个聊天页停两秒，回到本页点开诊断，用右上角「复制全部」粘贴发我。";
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
    } else if (ip.section == 3) {
        cell.textLabel.text = @"诊断信息";
        cell.detailTextLabel.text = @"点开查看 / 复制";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
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
    if (ip.section == 3) {
        WCCollectDiag(@"settings"); // 点开即重采当前状态
        WCDiagViewController *dvc = [[WCDiagViewController alloc] init];
        [self.navigationController pushViewController:dvc animated:YES];
        [dvc release];
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
        @"WCBlack 纯黑背景", @"6.2", @"WCBlackSettingsViewController");
    NSArray *after = nil;
    @try { after = [inst valueForKey:@"plugins"]; } @catch (id e) { after = nil; }
    for (id p in after) {
        NSString *t = nil;
        @try { t = [p valueForKey:@"title"]; } @catch (id e) { t = nil; }
        if ([t containsString:@"WCBlack"]) {
            gRegistered = YES;
            os_log(WCLog(), "[WCBlack] v6.0 registered in plugin list");
            break;
        }
    }
}
#pragma mark - v6.1 栏对齐（顶栏/底栏/聊天底栏不走色板，单独对齐）

// 这三处在 v6 实测里是浅的：它们不从 WCColorMgr 取色（色板里也没有它们的色），
// 由玻璃插件与系统外观那条线决定。判深浅不用视图自己的 trait（那正是它们跟不上的
// 原因），而是直接问微信自己的取色：BG_0 经原始 toColor 解析后等于它的深色值，
// 微信就是深色。探针结果每拍刷新，栏的强制/还原都以它为准；同时把栏容器的
// overrideUserInterfaceStyle 钉到同侧，让栏内的图标、材质、tint 自己按深色解析。
static BOOL gWCWeChatDark = NO;
static BOOL WCProbeWeChatDark(void) {
    static NSTimeInterval last = 0;
    static BOOL cached = NO;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - last < 0.5) return cached;
    last = now;
    BOOL dark = ([UITraitCollection currentTraitCollection].userInterfaceStyle == UIUserInterfaceStyleDark);
    Class dynCls = NSClassFromString(@"MMDynamicColor");
    if (gWCMgr && gOrigGetColor && gOrigToColor && dynCls) {
        id c = ((id (*)(id, SEL, id))gOrigGetColor)(gWCMgr, @selector(getColor:), @"BG_0");
        if (c && [c isKindOfClass:dynCls]) {
            UIColor *resolved = ((UIColor *(*)(id, SEL))gOrigToColor)(c, @selector(toColor));
            NSString *a = WCHexOfColor(resolved);
            if ([a isEqualToString:WCHexOfColor([c darkmodeColor])]) dark = YES;
            else if ([a isEqualToString:WCHexOfColor([c normalColor])]) dark = NO;
        }
    }
    cached = dark;
    return dark;
}

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

// 顶栏背景条兜底识别：不限亮度（它当前正是浅的），只认不透明中性色
static BOOL WCIsOpaqueNeutralAny(UIColor *c) {
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
    return (mx - mn) < 0.05;
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
    BOOL dark = gWCWeChatDark;
    if ([module isEqualToString:@"chatbar"]) WCFieldSweep(bar);
    if (!dark || !WCConfigColor(module)) { WCRestoreBar(bar); return; }
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

static void WCRestoreTabView(UIView *v) {
    NSNumber *forced = objc_getAssociatedObject(v, &kWCForcedKey);
    if (!forced.boolValue) return;
    if ([v isKindOfClass:[UITabBar class]]) {
        UITabBar *tb = (UITabBar *)v;
        tb.standardAppearance = objc_getAssociatedObject(v, &kWCOrigStdAppKey);
        tb.scrollEdgeAppearance = objc_getAssociatedObject(v, &kWCOrigEdgeAppKey);
        tb.barTintColor = objc_getAssociatedObject(v, &kWCOrigTintKey);
        tb.backgroundImage = objc_getAssociatedObject(v, &kWCOrigNavImageKey);
    }
    UIColor *ob = objc_getAssociatedObject(v, &kWCOrigBGKey);
    if (ob) v.backgroundColor = ob;
    for (UIView *hv in (NSMutableArray *)objc_getAssociatedObject(v, &kWCHiddenViewsKey)) hv.hidden = NO;
    objc_setAssociatedObject(v, &kWCHiddenViewsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    WCRestoreStrong(v, 3);
    objc_setAssociatedObject(v, &kWCForcedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void WCForceTabView(UIView *v) {
    UIColor *cfg = WCConfigColor(@"tab");
    if (!cfg || !gWCWeChatDark) { WCRestoreTabView(v); return; }
    UIColor *dyn = WCDynamicColor(@"tab", [UIColor whiteColor]);
    NSNumber *forced = objc_getAssociatedObject(v, &kWCForcedKey);
    if (!forced.boolValue) {
        if (v.backgroundColor) objc_setAssociatedObject(v, &kWCOrigBGKey, v.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([v isKindOfClass:[UITabBar class]]) {
            UITabBar *tb0 = (UITabBar *)v;
            if (tb0.standardAppearance) objc_setAssociatedObject(v, &kWCOrigStdAppKey, tb0.standardAppearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (tb0.scrollEdgeAppearance) objc_setAssociatedObject(v, &kWCOrigEdgeAppKey, tb0.scrollEdgeAppearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (tb0.barTintColor) objc_setAssociatedObject(v, &kWCOrigTintKey, tb0.barTintColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (tb0.backgroundImage) objc_setAssociatedObject(v, &kWCOrigNavImageKey, tb0.backgroundImage, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(v, &kWCForcedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([v isKindOfClass:[UITabBar class]]) {
        UITabBar *tb = (UITabBar *)v;
        UITabBarAppearance *ap = tb.standardAppearance;
        if (ap && ![ap.backgroundColor isEqual:cfg]) {
            UITabBarAppearance *cp = [ap copy];
            cp.backgroundColor = cfg;
            cp.backgroundEffect = nil;
            cp.shadowColor = [UIColor clearColor];
            tb.standardAppearance = cp;
            tb.scrollEdgeAppearance = cp;
            [cp release];
        }
        if (tb.barTintColor != dyn) tb.barTintColor = dyn;
        UIImage *img = WCSolidImage(cfg);
        if (img && tb.backgroundImage != img) tb.backgroundImage = img;
    }
    if (v.backgroundColor != dyn) v.backgroundColor = dyn;
    WCApplyStrong(v, v, dyn, 3);
}

#pragma mark - v6.2 栏出生钩子（对齐从轮询提前到栏自己的布局回调，消进入/退出闪白）

// v6.1 实测：稳态全黑，但进入/退出聊天时顶栏、底栏、输入条会闪白 0.1–0.2 秒——
// 逐帧验过：白只出现在栏区、内容区从不白。那是新栏出生时自带浅色，要等维护 tick
// （0.4 秒一拍）才被对齐。改法：钩这些栏自己的 layoutSubviews/didMoveToWindow，
// 原实现跑完立刻在同一轮布局里对齐，赶在转场第一帧渲染之前。稳态重复调用按
// 每视图 0.1 秒节流，tick 保留作兜底。
static void WCAlignBandIn(UIView *root, int depth) {
    if (!root || depth < 0 || !gWCWeChatDark) return;
    if (root.window && root.bounds.size.width >= root.window.bounds.size.width * 0.95 &&
        root.bounds.size.height >= 20 && root.bounds.size.height <= 140) {
        CGRect wf = [root convertRect:root.bounds toView:nil];
        if (wf.origin.y < 70 && wf.origin.y > -70) {
            if (WCIsOpaqueNeutralAny(root.backgroundColor)) {
                WCRegisterBar(gBarsNav, root);
                WCForceBar(root, @"nav", 3);
            } else if ([root isKindOfClass:[UIVisualEffectView class]] && ((UIVisualEffectView *)root).effect &&
                       root.superview && [root.superview isKindOfClass:[UIView class]]) {
                WCRegisterBar(gBarsNav, root.superview);
                WCForceBar(root.superview, @"nav", 3);
            }
        }
    }
    for (UIView *s in root.subviews) WCAlignBandIn(s, depth - 1);
}

static void WCChromeAlignForView(UIView *v, int kind) {
    if (!v || !v.window) return;
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSNumber *ts = objc_getAssociatedObject(v, &kWCAlignTsKey);
    if (ts && now - ts.doubleValue < 0.1) return;
    objc_setAssociatedObject(v, &kWCAlignTsKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    gWCWeChatDark = WCEnabled() && WCProbeWeChatDark();
    UIUserInterfaceStyle want = gWCWeChatDark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
    if (v.overrideUserInterfaceStyle != want) v.overrideUserInterfaceStyle = want;
    if (!gBarsNav) gBarsNav = [[NSHashTable weakObjectsHashTable] retain];
    if (!gBarsTab) gBarsTab = [[NSHashTable weakObjectsHashTable] retain];
    if (!gBarsInput) gBarsInput = [[NSHashTable weakObjectsHashTable] retain];
    if (kind == 0) {
        WCRegisterBar(gBarsNav, v);
        WCForceBar(v, @"nav", 3);
        UIView *scope = v;
        for (int i = 0; i < 3 && scope.superview; i++) scope = scope.superview;
        WCAlignBandIn(scope, 8);
    } else if (kind == 1) {
        CGRect f = [v convertRect:v.bounds toView:nil];
        if (f.origin.y > v.window.bounds.size.height * 0.7) { WCRegisterBar(gBarsTab, v); WCForceTabView(v); }
    } else {
        WCRegisterBar(gBarsInput, v);
        WCForceBar(v, @"chatbar", 4);
    }
}

static IMP gO_MMNavL, gO_MMNavW, gO_MsgNavL, gO_MsgNavW, gO_NewMsgNavL, gO_NewMsgNavW;
static IMP gO_GTabL, gO_GTabW, gO_GNTabL, gO_GNTabW, gO_MMTabL, gO_MMTabW;
static IMP gO_InL, gO_InW, gO_ContL, gO_ContW;

static void WC_MMNav_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_MMNavL)(s, c); WCChromeAlignForView(s, 0); }
static void WC_MMNav_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_MMNavW)(s, c); WCChromeAlignForView(s, 0); }
static void WC_MsgNav_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_MsgNavL)(s, c); WCChromeAlignForView(s, 0); }
static void WC_MsgNav_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_MsgNavW)(s, c); WCChromeAlignForView(s, 0); }
static void WC_NewMsgNav_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_NewMsgNavL)(s, c); WCChromeAlignForView(s, 0); }
static void WC_NewMsgNav_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_NewMsgNavW)(s, c); WCChromeAlignForView(s, 0); }
static void WC_GTab_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_GTabL)(s, c); WCChromeAlignForView(s, 1); }
static void WC_GTab_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_GTabW)(s, c); WCChromeAlignForView(s, 1); }
static void WC_GNTab_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_GNTabL)(s, c); WCChromeAlignForView(s, 1); }
static void WC_GNTab_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_GNTabW)(s, c); WCChromeAlignForView(s, 1); }
static void WC_MMTab_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_MMTabL)(s, c); WCChromeAlignForView(s, 1); }
static void WC_MMTab_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_MMTabW)(s, c); WCChromeAlignForView(s, 1); }
static void WC_In_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_InL)(s, c); WCChromeAlignForView(s, 2); }
static void WC_In_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_InW)(s, c); WCChromeAlignForView(s, 2); }
static void WC_Cont_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_ContL)(s, c); WCChromeAlignForView(s, 2); }
static void WC_Cont_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_ContW)(s, c); WCChromeAlignForView(s, 2); }

static void WCInstallChromeHooks(void) {
    Class c;
    c = NSClassFromString(@"MMUINavigationBar");
    if (c && !gO_MMNavL) { gO_MMNavL = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_MMNav_layout); gO_MMNavW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_MMNav_window); }
    c = NSClassFromString(@"MMMsgContentNavBar");
    if (c && !gO_MsgNavL) { gO_MsgNavL = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_MsgNav_layout); gO_MsgNavW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_MsgNav_window); }
    c = NSClassFromString(@"MMNewMsgContentNavBar");
    if (c && !gO_NewMsgNavL) { gO_NewMsgNavL = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_NewMsgNav_layout); gO_NewMsgNavW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_NewMsgNav_window); }
    c = NSClassFromString(@"WCTabBarView");
    if (c && !gO_GTabW) { gO_GTabL = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_GTab_layout); gO_GTabW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_GTab_window); }
    c = NSClassFromString(@"WCGNativeTabBar");
    if (c && !gO_GNTabW) { gO_GNTabL = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_GNTab_layout); gO_GNTabW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_GNTab_window); }
    c = NSClassFromString(@"MMTabBar");
    if (c && !gO_MMTabL) { gO_MMTabL = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_MMTab_layout); gO_MMTabW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_MMTab_window); }
    c = NSClassFromString(@"MMInputToolView");
    if (c && !gO_InL) { gO_InL = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_In_layout); gO_InW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_In_window); }
    c = NSClassFromString(@"InputToolContainerView");
    if (c && !gO_ContL) { gO_ContL = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_Cont_layout); gO_ContW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_Cont_window); }
}

#pragma mark - 维护 tick（注册重试、输入框维护、分割线、栏对齐）

static void WCScanChrome(UIView *root, UIWindow *win, int depth) {
    if (!root || depth < 0) return;
    NSString *cn = NSStringFromClass([root class]);
    UIUserInterfaceStyle want = (WCEnabled() && gWCWeChatDark) ? UIUserInterfaceStyleDark : UIUserInterfaceStyleUnspecified;
    if ([cn containsString:@"InputTool"]) {
        if (root.overrideUserInterfaceStyle != want) root.overrideUserInterfaceStyle = want;
        WCRegisterBar(gBarsInput, root);
        WCForceBar(root, @"chatbar", 4);
    } else if (WCIsTabCandidate(root)) {
        CGRect f = [root convertRect:root.bounds toView:nil];
        if (win && f.origin.y > win.bounds.size.height * 0.7) {
            if (root.overrideUserInterfaceStyle != want) root.overrideUserInterfaceStyle = want;
            WCRegisterBar(gBarsTab, root);
            WCForceTabView(root);
            return;
        }
    }
    if ([root isKindOfClass:[UINavigationBar class]] || [cn containsString:@"MsgContentNavBar"]) {
        if (root.overrideUserInterfaceStyle != want) root.overrideUserInterfaceStyle = want;
        WCRegisterBar(gBarsNav, root);
        WCForceBar(root, @"nav", 3);
    } else if (gWCWeChatDark && root.window && root.bounds.size.width >= root.window.bounds.size.width * 0.95 &&
               root.bounds.size.height >= 20 && root.bounds.size.height <= 140) {
        CGRect wf = [root convertRect:root.bounds toView:nil];
        if (wf.origin.y < 70 && wf.origin.y > -70) {
            if (WCIsOpaqueNeutralAny(root.backgroundColor)) {
                WCRegisterBar(gBarsNav, root);
                WCForceBar(root, @"nav", 3);
            } else if ([root isKindOfClass:[UIVisualEffectView class]] && ((UIVisualEffectView *)root).effect &&
                       root.superview && [root.superview isKindOfClass:[UIView class]]) {
                WCRegisterBar(gBarsNav, root.superview);
                WCForceBar(root.superview, @"nav", 3);
            }
        }
    }
    for (UIView *s in root.subviews) WCScanChrome(s, win, depth - 1);
}

static void WCSlimTick(void) {
    WCEnsureRegistered();
    gWCWeChatDark = WCEnabled() && WCProbeWeChatDark();
    if (!gBarsNav) gBarsNav = [[NSHashTable weakObjectsHashTable] retain];
    if (!gBarsTab) gBarsTab = [[NSHashTable weakObjectsHashTable] retain];
    if (!gBarsInput) gBarsInput = [[NSHashTable weakObjectsHashTable] retain];
    if (!gWCWeChatDark) {
        // 非深色（含关插件）：把登记过的顶栏背景条逐个还原（它只在深色时才被扫描命中）
        for (UIView *b in gBarsNav.allObjects) WCRestoreBar(b);
    }
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) containsString:@"TextEffects"]) { WCForceKeyboardWindow(w); continue; }
        WCScanChrome(w, w, 16);
        WCScanTablesInWindow(w, w, 16);
    }
}

static dispatch_source_t gSlimTimer;
static void WCStartSlimTimer(void) {
    if (gSlimTimer) return;
    gSlimTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(gSlimTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                              (uint64_t)(0.4 * NSEC_PER_SEC), (uint64_t)(0.05 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(gSlimTimer, ^{ WCSlimTick(); });
    dispatch_resume(gSlimTimer);
}

#pragma mark - 安装与注册（v6）

static BOOL gSrcHooked = NO;
static void WCInstall(void) {
    if (!gWCNameCache) {
        gWCNameCache = [[NSMutableDictionary alloc] init];
        gWCNameHits = [[NSMutableDictionary alloc] init];
    }
    if (!gSrcHooked) {
        Class mgr = NSClassFromString(@"WCColorMgr");
        Class dyn = NSClassFromString(@"MMDynamicColor");
        Class proxy = NSClassFromString(@"WCColorProxy");
        if (mgr && dyn && proxy) {
            if (!gOrigGetColor) gOrigGetColor = WCSwap(mgr, @selector(getColor:), (IMP)WC_WCColorMgr_getColor);
            if (!gOrigGetColorValue) gOrigGetColorValue = WCSwap(mgr, @selector(getColorValueForName:), (IMP)WC_WCColorMgr_getColorValue);
            if (!gOrigToColor) gOrigToColor = WCSwap(dyn, @selector(toColor), (IMP)WC_MMDynamicColor_toColor);
            if (!gOrigProxyResolve) gOrigProxyResolve = WCSwap(proxy, @selector(colorInCurrentUserInterfaceStyle:), (IMP)WC_Proxy_colorInStyle);
            if (gOrigGetColor && gOrigGetColorValue && gOrigToColor && gOrigProxyResolve) {
                gSrcHooked = YES;
                os_log(WCLog(), "[WCBlack] v6.2 source hooks in");
            }
        }
    }
    // 话筒钩子（与 v5.6/v5.7 相同）
    static BOOL dicHooked = NO;
    if (!dicHooked) {
        Class dic = NSClassFromString(@"MMGrowDictationIconView");
        if (dic) {
            gOrigDicSetHidden = WCSwapOwn(dic, @selector(setHidden:), (IMP)WC_Dic_setHidden);
            gOrigDicWindow = WCSwapOwn(dic, @selector(didMoveToWindow), (IMP)WC_Dic_didMoveToWindow);
            if (gOrigDicSetHidden && gOrigDicWindow) {
                dicHooked = YES;
                os_log(WCLog(), "[WCBlack] v6.2 dictation icon hooks in");
            }
        }
    }
    WCInstallChromeHooks();
    WCEnsureRegistered();
    WCStartSlimTimer();
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
    // v4.7 长尾：管理器慢热或列表中途被重建时，10 秒、30 秒再各补一次安装+注册
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCInstall(); });
}
@end
