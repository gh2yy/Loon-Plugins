// WCBlack.m — 微信深色模式纯黑背景 v8.0 还原版 (2026-11-26)
// 用户拍板收线：只保留三件事，其余全部还原微信原样——
//   1) 背景变色：钩 WCColorMgr 的 getColor:/getColorValueForName: 与
//      MMDynamicColor toColor、WCColorProxy 解析，在发色处按色名把深色值
//      换成模块色（bg 主背景 / cell 置顶行与卡片；置顶行色名
//      Table_ChatRow_Pinned_BG 与 BG_0 都归 bg）。浅色一律原样，深浅切换
//      由动态色自行重解析。本机制即 v6.0 定案版，内容区自此零问题。
//   2) 首页分割线开关：只认 MainFrame 主列表，存档原样式后置 None 并藏
//      cell 底部发丝线，关开关即还原。
//   3) 设置页（我→设置→插件→WCBlack 纯黑背景）：总开关 + bg/cell 两模块
//      选色 + 分割线开关。改完即时生效（动态色 provider 实时读配置）。
// 已全部删除（v6.1–v7.6 的三栏路线）：顶栏/玻璃底栏/聊天底栏的钉制、强涂、
// trait 钩子、状态机与探针、colorDic 实验、输入框色板、话筒隐藏、键盘处理、
// 诊断页。三栏恢复微信（含玻璃插件）原生表现。
// 安全纪律：+load/WCInstall 只做 swizzle，绝不给微信的类发消息（v7.2 闪退教训）。


#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>

static os_log_t WCLog(void) {
    static os_log_t l; static dispatch_once_t once;
    dispatch_once(&once, ^{ l = os_log_create("com.nova.wcblack", "v8.0"); });
    return l;
}

#pragma mark - 配置

static NSString *const kWCEnabledKey = @"WCBlack.enabled";
static NSArray<NSString *> *WCModules(void) { return @[@"bg", @"cell"]; }
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

static void WCEnsureRegistered(void);

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
        @"WCBlack 纯黑背景", @"8.0", @"WCBlackSettingsViewController");
    NSArray *after = nil;
    @try { after = [inst valueForKey:@"plugins"]; } @catch (id e) { after = nil; }
    for (id p in after) {
        NSString *t = nil;
        @try { t = [p valueForKey:@"title"]; } @catch (id e) { t = nil; }
        if ([t containsString:@"WCBlack"]) {
            gRegistered = YES;
            os_log(WCLog(), "[WCBlack] v8.0 registered in plugin list");
            break;
        }
    }
}

#pragma mark - 家务 tick（注册重试 + 分割线扫描，5 秒）

static void WCHousekeepingTick(void) {
    WCEnsureRegistered();
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass([w class]) containsString:@"TextEffects"]) continue;
        WCScanTablesInWindow(w, w, 16);
    }
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
            if (!gOrigGetColorValue) gOrigGetColorValue = WCSwap(mgr, @selector(getColorValueForName:), (IMP)WC_WCColorMgr_getColorValue);
            if (!gOrigToColor) gOrigToColor = WCSwap(dyn, @selector(toColor), (IMP)WC_MMDynamicColor_toColor);
            if (!gOrigProxyResolve) gOrigProxyResolve = WCSwap(proxy, @selector(colorInCurrentUserInterfaceStyle:), (IMP)WC_Proxy_colorInStyle);
            if (gOrigGetColor && gOrigGetColorValue && gOrigToColor && gOrigProxyResolve) {
                gSrcHooked = YES;
                os_log(WCLog(), "[WCBlack] v8.0 source hooks in");
            }
        }
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
