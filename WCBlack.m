// WCBlack.m — 微信深色模式纯黑背景 v3 (2026-11-26)
// v2 真机结论：主背景/置顶行（setter 路径）已生效、设置页可达；但三栏靶向 layoutSubviews 零效果——
//   导航仍 #0F0F0F、tab 仍 #181818、聊天底栏仍 #1A~#1C。判定：栏的背景不是在 layout 里由
//   setBackgroundColor 定的（导航疑似背景图/图层，tab 有玻璃插件在同一布局链后手重绘），
//   一次性 layout 强制斗不过后手。v3 改为：三栏实例注册表 + 0.4s 定时强刷（谁最后画就再覆盖谁），
//   导航另强制 setBackgroundImage 为模块色纯色图；特效视图摘除前先存档原 effect，浅色时还原。
//   设置页自定义颜色新增系统色谱选择器（UIColorPickerViewController），保留输 hex。
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
    dispatch_once(&once, ^{ l = os_log_create("com.nova.wcblack", "v3"); });
    return l;
}

#pragma mark - 配置

static NSString *const kWCEnabledKey = @"WCBlack.enabled";
static NSArray<NSString *> *WCModules(void) { return @[@"bg", @"nav", @"tab", @"chatbar", @"cell"]; }
static NSString *WCModuleTitle(NSString *m) {
    if ([m isEqualToString:@"bg"]) return @"主背景（列表 / 聊天）";
    if ([m isEqualToString:@"nav"]) return @"顶部导航栏";
    if ([m isEqualToString:@"tab"]) return @"底部标签栏";
    if ([m isEqualToString:@"chatbar"]) return @"聊天底部栏";
    if ([m isEqualToString:@"cell"]) return @"置顶行 / 卡片";
    return m;
}
static BOOL WCEnabled(void) {
    NSNumber *v = [[NSUserDefaults standardUserDefaults] objectForKey:kWCEnabledKey];
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
    return hex ?: @"#000000";
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

#pragma mark - 颜色判定与动态替代

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

static UIColor *WCDynamicColor(NSString *module, UIColor *lightFallback) {
    UIColor *fb = lightFallback ?: [UIColor clearColor];
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        if (tc.userInterfaceStyle == UIUserInterfaceStyleDark) {
            UIColor *c = WCConfigColor(module);
            return c ?: fb;
        }
        return fb;
    }];
}

// setter 路径的替换：命中模块 -> 动态色（浅色回退为原色浅色解析值）
static UIColor *WCSubstituteForColor(UIColor *color) {
    NSString *module = WCModuleForColor(color);
    if (!module) return nil;
    UIColor *lightResolved = [color resolvedColorWithTraitCollection:WCLightTrait()];
    return WCDynamicColor(module, lightResolved);
}

#pragma mark - 靶向栏强制（注册表 + 定时强刷）

static char kWCFallbackKey, kWCDynKey, kWCForcedKey, kWCOrigEffectKey, kWCHiddenViewsKey, kWCOrigNavImageKey;

static NSHashTable<UIView *> *gBarsTab, *gBarsNav, *gBarsInput;
static void WCRegisterBar(NSHashTable<UIView *> *table, UIView *bar) {
    if (table && bar) [table addObject:bar];
}

// 1x1 纯色图（导航背景图强制用），按 hex 缓存
static UIImage *WCSolidImage(UIColor *color) {
    static NSMutableDictionary<NSString *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
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
            if (ev.contentView.backgroundColor != dyn) ev.contentView.backgroundColor = dyn;
            if (v.backgroundColor != dyn) v.backgroundColor = dyn;
        } else if ([v isKindOfClass:[UIImageView class]] &&
                   v.frame.size.width >= bar.bounds.size.width * 0.9 &&
                   v.frame.size.height >= bar.bounds.size.height * 0.85) {
            // 全尺寸背景图视图：藏掉（恢复时按存档放回）
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
                // 栏内子视图：命中任一模块灰阶、或半透明黑/白蒙层，都刷成该栏模块色
                BOOL translucentOverlay = NO;
                if (!m) {
                    UIColor *d = [bg resolvedColorWithTraitCollection:WCDarkTrait()];
                    CGFloat w = 0, al = 0;
                    if ([d getWhite:&w alpha:&al] && al > 0.03 && al < 0.95) translucentOverlay = YES;
                }
                if (m || translucentOverlay) v.backgroundColor = dyn;
            }
        }
        WCApplyStrong(v, bar, dyn, depth - 1);
    }
}

static void WCRestoreBar(UIView *bar) {
    NSNumber *forced = objc_getAssociatedObject(bar, &kWCForcedKey);
    if (!forced.boolValue) return;
    UIColor *fb = objc_getAssociatedObject(bar, &kWCFallbackKey);
    UIColor *dyn = objc_getAssociatedObject(bar, &kWCDynKey);
    if (fb && bar.backgroundColor == dyn) bar.backgroundColor = fb;
    for (UIView *v in (NSMutableArray *)objc_getAssociatedObject(bar, &kWCHiddenViewsKey)) v.hidden = NO;
    objc_setAssociatedObject(bar, &kWCHiddenViewsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if ([bar isKindOfClass:[UINavigationBar class]]) {
        UIImage *orig = objc_getAssociatedObject(bar, &kWCOrigNavImageKey);
        [(UINavigationBar *)bar setBackgroundImage:orig forBarMetrics:UIBarMetricsDefault];
    }
    objc_setAssociatedObject(bar, &kWCForcedKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 深色+模块开启时把整栏刷成模块色；否则恢复。layout 与定时器都调用，幂等。
static void WCForceBar(UIView *bar, NSString *module, int depth) {
    if (!bar) return;
    BOOL dark = (bar.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark);
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
        }
        objc_setAssociatedObject(bar, &kWCForcedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (bar.backgroundColor != dyn) bar.backgroundColor = dyn;
    if ([bar isKindOfClass:[UINavigationBar class]]) {
        UIColor *cfg = WCConfigColor(module);
        UIImage *img = cfg ? WCSolidImage(cfg) : nil;
        UINavigationBar *nb = (UINavigationBar *)bar;
        if (img && [nb backgroundImageForBarMetrics:UIBarMetricsDefault] != img)
            [nb setBackgroundImage:img forBarMetrics:UIBarMetricsDefault];
        if (nb.barTintColor != dyn) nb.barTintColor = dyn;
    }
    WCApplyStrong(bar, bar, dyn, depth);
}

static void WCEnforceRegistered(void) {
    for (UIView *b in gBarsTab.allObjects) if (b.window) WCForceBar(b, @"tab", 3);
    for (UIView *b in gBarsNav.allObjects) if (b.window) WCForceBar(b, @"nav", 3);
    for (UIView *b in gBarsInput.allObjects) if (b.window) WCForceBar(b, @"chatbar", 2);
}
static dispatch_source_t gEnforcerTimer; // 必须静态持有，否则定时器被释放
static void WCStartEnforcer(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        gEnforcerTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(gEnforcerTimer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                                  (uint64_t)(0.4 * NSEC_PER_SEC), (uint64_t)(0.05 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(gEnforcerTimer, ^{ WCEnforceRegistered(); });
        dispatch_resume(gEnforcerTimer);
    });
}

// 配置变更后：全窗重扫，动态色重新解析、栏重新强制
static void WCSweep(void) {
    for (UIWindow *win in [UIApplication sharedApplication].windows) {
        [win setNeedsLayout];
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:win];
        while (stack.count) {
            UIView *v = stack.lastObject; [stack removeLastObject];
            UIColor *bg = v.backgroundColor;
            if (bg) v.backgroundColor = bg; // 触发 hook/重解析
            [stack addObjectsFromArray:v.subviews];
        }
    }
}

#pragma mark - Hooks

static IMP gOrigSetBG, gOrigNavBarTint, gOrigTabBarTint;
static IMP gOrigMMTabLayout, gOrigMMTabWindow, gOrigNavLayout, gOrigInputLayout;

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
static void WC_MMTabBar_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigMMTabLayout)(self, _cmd);
    WCRegisterBar(gBarsTab, self);
    WCForceBar(self, @"tab", 3);
}
static void WC_MMTabBar_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigMMTabWindow)(self, _cmd);
    if (self.window) WCRegisterBar(gBarsTab, self);
}
static IMP gOrigNavWindow, gOrigInputWindow;
static void WC_NavBar_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigNavLayout)(self, _cmd);
    WCRegisterBar(gBarsNav, self);
    WCForceBar(self, @"nav", 3);
}
static void WC_NavBar_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigNavWindow)(self, _cmd);
    if (self.window) WCRegisterBar(gBarsNav, self);
}
static void WC_InputTool_layoutSubviews(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigInputLayout)(self, _cmd);
    WCRegisterBar(gBarsInput, self);
    WCForceBar(self, @"chatbar", 2);
    // 输入框本体（#2C2C2C 内容色）不在目标内不会被刷；这里只补刷全宽底板子视图
    UIColor *dyn = objc_getAssociatedObject(self, &kWCDynKey);
    NSNumber *forced = objc_getAssociatedObject(self, &kWCForcedKey);
    if (dyn && forced.boolValue) {
        for (UIView *v in self.subviews) {
            if (v.frame.size.width >= self.bounds.size.width * 0.9 && v.backgroundColor && v.backgroundColor != dyn) {
                NSString *cls = NSStringFromClass([v class]);
                if (![cls containsString:@"Text"]) v.backgroundColor = dyn;
            }
        }
    }
}
static void WC_InputTool_didMoveToWindow(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigInputWindow)(self, _cmd);
    if (self.window) WCRegisterBar(gBarsInput, self);
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

#pragma mark - 设置页

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
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 1 : (NSInteger)WCModules().count;
}
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"总开关" : @"各模块颜色（仅深色模式生效）";
}
- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    return s == 1 ? @"点模块选颜色：纯黑 / 深灰 / 石墨 / 色谱选择 / 输入色值 / 原色（关闭该模块）。改完即时生效，不用重启微信。" : nil;
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

#pragma mark - 安装与注册

static BOOL gInstalled = NO, gRegistered = NO;
static void WCInstall(void) {
    if (!gInstalled) {
        gOrigSetBG = WCSwap([UIView class], @selector(setBackgroundColor:), (IMP)WC_View_setBackgroundColor);
        if (!gOrigSetBG) return;
        gOrigNavBarTint = WCSwap([UINavigationBar class], @selector(setBarTintColor:), (IMP)WC_NavBar_setBarTintColor);
        gOrigTabBarTint = WCSwap([UITabBar class], @selector(setBarTintColor:), (IMP)WC_TabBar_setBarTintColor);
        Class mmTab = NSClassFromString(@"MMTabBar");
        if (mmTab) {
            gOrigMMTabLayout = WCSwapOwn(mmTab, @selector(layoutSubviews), (IMP)WC_MMTabBar_layoutSubviews);
            gOrigMMTabWindow = WCSwapOwn(mmTab, @selector(didMoveToWindow), (IMP)WC_MMTabBar_didMoveToWindow);
        }
        Class mmNav = NSClassFromString(@"MMUINavigationBar");
        if (mmNav) {
            gOrigNavLayout = WCSwapOwn(mmNav, @selector(layoutSubviews), (IMP)WC_NavBar_layoutSubviews);
            gOrigNavWindow = WCSwapOwn(mmNav, @selector(didMoveToWindow), (IMP)WC_NavBar_didMoveToWindow);
        }
        Class mmInput = NSClassFromString(@"MMInputToolView");
        if (mmInput) {
            gOrigInputLayout = WCSwapOwn(mmInput, @selector(layoutSubviews), (IMP)WC_InputTool_layoutSubviews);
            gOrigInputWindow = WCSwapOwn(mmInput, @selector(didMoveToWindow), (IMP)WC_InputTool_didMoveToWindow);
        }
        if (!gBarsTab) {
            gBarsTab = [NSHashTable weakObjectsHashTable];
            gBarsNav = [NSHashTable weakObjectsHashTable];
            gBarsInput = [NSHashTable weakObjectsHashTable];
        }
        WCStartEnforcer();
        static id cfgObserver; // 必须持有 token，否则观察会被注销
        cfgObserver = [[NSNotificationCenter defaultCenter] addObserverForName:@"WCBlackConfigChanged" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) { WCSweep(); }];
        gInstalled = YES;
        os_log(WCLog(), "[WCBlack] v3 installed mmTab=%{public}@ mmNav=%{public}@ mmInput=%{public}@", mmTab, mmNav, mmInput);
    }
    if (!gRegistered) {
        Class mgr = NSClassFromString(@"WCPluginsMgr");
        if (mgr && [mgr respondsToSelector:@selector(sharedInstance)]) {
            id inst = ((id (*)(id, SEL))objc_msgSend)(mgr, @selector(sharedInstance));
            NSArray *existing = [inst valueForKey:@"plugins"];
            BOOL dup = NO;
            for (id p in existing) { if ([[p valueForKey:@"title"] containsString:@"WCBlack"]) { dup = YES; break; } }
            if (!dup && [inst respondsToSelector:@selector(registerControllerWithTitle:version:controller:)]) {
                ((void (*)(id, SEL, id, id, id))objc_msgSend)(inst, @selector(registerControllerWithTitle:version:controller:),
                    @"WCBlack 纯黑背景", @"3.0", @"WCBlackSettingsViewController");
                os_log(WCLog(), "[WCBlack] v3 registered in plugin list");
            }
            gRegistered = YES;
        }
    }
}

@interface WCBlackLoader : NSObject
@end
@implementation WCBlackLoader
+ (void)load {
    WCInstall();
    dispatch_async(dispatch_get_main_queue(), ^{ WCInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCInstall(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCInstall(); });
}
@end
