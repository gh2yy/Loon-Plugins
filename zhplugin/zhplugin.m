// zhplugin.m — 知乎 11.15.0 插件合集（2026-11-26）
// 同一个 dylib 两项功能，各有独立开关（设置页 contactsCellInfo 行正上方连插两行）：
//   1) 玻璃底栏：iOS 27 式清透玻璃悬浮底栏（原 ZHGlassBar v3 并入）
//   2) 纯黑背景：夜间模式下整体画布背景改纯黑 #000000（仿 WCBlack 路线，但走知乎主题发色点）
//
// 玻璃底栏口径（2026-11-26 按 WCTabBarGlass 本体取证重做，废弃 UIGlassEffect 路线）：
//   基线为 v2 改包（ZHTabBarNew 只剩首页/我的两项、stack 宽约束内收，两项中心 33.3%/66.7%）。
//   只做视觉层：原底栏背景/顶线清掉，在 stackView 之下放两块玻璃盘（胶囊盘 + 选中透镜盘），
//   按钮沿用原 ZHTabBarItemNormalView 与原点击路由，插件不新增任何拦截视图/手势到盘上。
//   构造定案（WCTabBarGlass 本体取证）：三方玻璃不用 UIGlassEffect——知乎带
//   UIDesignRequiresCompatibility 兼容标志，UIGlassEffect（Clear/Regular 两版）真机
//   均为实心，已废弃。采样核心是 UIBlurEffect SystemUltraThinMaterial（style 6，
//   iOS 13 经典材质通道、不受 SDK/兼容标志门控），液态感靠装饰层堆：
//   baseFill 透色 / wash 渐变光泽 / rim 边缘高光 / shadow 投影 / selection 透镜。
//   盘分层（阴影与裁剪分层）：外壳 wrapper 只承阴影、不裁剪、无背景色；内嵌裁剪
//   容器（cornerRadius=盘高/2、cornerCurve=continuous、masksToBounds）依次垫
//   材质效果视图、baseFill、wash（CAGradientLayer 对角渐变）；rim 描边叠最上。
//   透镜同配方小胶囊（fill 略强于盘）。全链 userInteractionEnabled=NO。
//   几何只认实测 frame（XHS 全部 plateOn 调用点均为真实内容视图 frame 的并集/内缩）：
//   胶囊横向 = 可见 item 槽位并集 ±8，纵向 = 图标+标题内容并集定高；透镜 = 选中 item
//   槽位 ±4、胶囊内居中。不再读 stackView.frame 推导（旧版盘错位/压 feed 的根源），
//   可见性过滤：hidden / alpha<0.01 / 零尺寸的 item 一律不算（v2 改包隐藏项残余同理）。
//   坐标纪律（本轮加固）：item 的 .frame 是 stackView 坐标系，禁止直接拼到 bar 坐标系，
//   一律 [bar convertRect:item.bounds fromView:item] 换算；换算结果逐项校验（空/越界/
//   尺寸不合常理 → item 中心点换算兜底 → 仍不可信则整轮不画、有限次下一拍重试），
//   胶囊/透镜落盘前再过一道 ZHClampRectToBounds 夹回 bar 内——任何路径都不许出界。
//
// 纯黑背景口径（本轮静态定案，详见 PATCH_NOTES v3 段）：
//   知乎颜色总发色点是 ZHThemeManage（ZHCoreTheme）：
//     +colorWithName:ignoreNight: 先把名字经 performSelector 解析成 ZHColorModel 单例
//     （+[ZHColorModel Map<Name>]），再统一走 +colorWithModel:ignoreNight:；
//     后者内部按 +[ZHThemeManage isNightMode]（读 NSUserDefaults NIGHT_MODE_KEY）
//     在 model.colorLight / model.colorNight 间二选一返回。
//   故只 swizzle +colorWithModel:ignoreNight: 一个点即覆盖全部原生取色路径。
//   画布 token（ZHColorModel 单例，light/night）：
//     MapUIFrame99A = #FFFFFF / #191B1F（主画布，与主文本 MapText02A 恰为反相，约 190 处引用）
//     MapUIFrame10A = #F8F8FA / #212429（二级/分组画布，约 150 处引用）
//   命中规则（身份制，不是色值制）：夜间 && 开关开 && !ignoreNight && model 为上述两单例之一
//     → 返回纯黑。其余层级一律不动：卡片 MapUIFrame99C(#282B30)、分隔/边框
//     MapUIFrame08A/08B/09A/09B（其中 08B/09B 夜值同为 #212429，靠身份制避开误伤）、
//     文本/VIP/品牌色全不碰。MapUIFrame10C 夜值本就是 #000000，无需处理。
//   日间零改动：isNightMode 为假时原样透传（含 ignoreNight=YES 的强制日间取色）。
//   可逆：hook 每次取色实时判定，不改模型存量、不存档快照；关开关或切回日间，
//     后续取色立即恢复主题原色。开关切换时补发知乎自己的主题刷新通知
//     （kNSObjectUpdateThemeHighNotification / kNSObjectUpdateThemeNormalNotification /
//      kRNUpdateThemeNormalNotification，即 +setNightMode: 内部同款三连，不动 NIGHT_MODE_KEY、
//      不调 +changeTheme——那是带快照动画的日夜翻转，误调会把日夜模式翻过去），
//     让已在屏的页面按原渠道重新取色重绘。
//   安装时机（本轮定案改为源头提前）：主题发色点 hook 在 +load 即装——赶在任何页面
//     建成取色之前。内容区画布色是基类 ZHViewController 在 viewDidLoad 一次性取走
//     的存量，+1s 延迟装钩时首页早已建成、事后补救（主题通知/窗口清扫）都够不着它
//     （清扫还误伤过底栏附近的画布色容器，已整段删除）。+load 里只做发色点类方法
//     swizzle 这一件最小动作；画布模型保持懒解析（首次取色时 dispatch_once 解析，
//     +load 里绝不碰 ZHColorModel——首版闪退的嫌疑正是 +load 期急切解析）。
//     底栏/设置两段仍维持 didFinishLaunching + 1s 延迟安装，与本段无关。
//
// 开关与入口：
//   玻璃：NSUserDefaults 键 ZHPlugin.GlassBar（新键不存在时回读旧键 ZHGlassBar.Enabled 迁移），默认开。
//   纯黑：NSUserDefaults 键 ZHPlugin.BlackBG，默认开。
//   设置页入口：ZHCommonSettingViewController 里锚定 contactsCellInfo（「查看通讯录好友」行模型对象），
//     在其所在组数组内插到它正上方，连插三行（自上而下：玻璃底栏、纯黑背景、诊断信息），开关行用
//     ZHSettingCellInfo 官方工厂 +switchCellInfoForTitle:subTitle:action:on: 构造（原生 cell 渲染），
//     诊断行用 +normalCellInfoForTitle:subTitle:target:selector: 构造（点击复制诊断文本到剪贴板，纯读取）；
//     另留长按底栏 0.8s 切换玻璃作兜底入口。
// 纯运行时 swizzle + 类动态加方法，无 substrate 依赖；玻璃类全部动态解析。本文件按 MRC 编写：
//   凡赋给 associated/全局的对象一律 alloc/init 或 RETAIN 持有（WCBlack v3 首启闪退教训）。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static char kCapsuleKey;   // 玻璃胶囊盘（分层构造的外壳 UIView）
static char kLensKey;      // 选中透镜盘（同配方小胶囊外壳 UIView）
static char kSelIdxKey;    // 上次选中序号（NSNumber, RETAIN）
static char kSchedKey;     // 已排队布局标记
static char kLayoutLockKey; // layoutSubviews 重入锁（per-instance）
static char kOrigBgKey;    // 原始 bar 背景色（RETAIN，关玻璃时恢复）
static char kGeoRetryKey;  // 几何不可信时的有限重试计数（NSNumber, RETAIN）
static char kGestureKey;   // 长按兜底手势（RETAIN）

#pragma mark - 工具

static id ZHGetObj(id obj, NSString *selName) {
    SEL s = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:s]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, s);
}
static BOOL ZHGetBool(id obj, NSString *selName, BOOL dflt) {
    SEL s = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:s]) return dflt;
    return ((BOOL (*)(id, SEL))objc_msgSend)(obj, s);
}
static void ZHSetBool(id obj, NSString *selName, BOOL v) {
    SEL s = NSSelectorFromString(selName);
    if (!obj || ![obj respondsToSelector:s]) return;
    ((void (*)(id, SEL, BOOL))objc_msgSend)(obj, s, v);
}

#pragma mark - 开关状态（集中读写，与入口解耦）

static NSString * const kZPGlassKey = @"ZHPlugin.GlassBar";
static NSString * const kZPGlassLegacyKey = @"ZHGlassBar.Enabled";
static NSString * const kZPBlackKey = @"ZHPlugin.BlackBG";

static BOOL ZHGlassEnabled(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:kZPGlassKey] == nil) {
        // 迁移：新键没写过时读一次旧键（旧 ZHGlassBar 时代的存档）
        if ([ud objectForKey:kZPGlassLegacyKey] != nil)
            return [ud boolForKey:kZPGlassLegacyKey];
        return YES; // 默认开
    }
    return [ud boolForKey:kZPGlassKey];
}

static BOOL ZPBlackEnabled(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud objectForKey:kZPBlackKey] == nil) return YES; // 默认开
    return [ud boolForKey:kZPBlackKey];
}

static NSHashTable *gLiveBars = nil; // weak 持有所有见过的 ZHTabBarNew（alloc/init 持有表本身）
static void ZHRegisterBar(UIView *bar) {
    if (!gLiveBars) gLiveBars = [[NSHashTable alloc] initWithOptions:NSPointerFunctionsWeakMemory capacity:0];
    if (bar) [gLiveBars addObject:bar];
}

static void ZHApplyBar(UIView *bar); // 前置声明，定义在布局节
static void ZHRequestApply(UIView *bar); // 前置声明，定义在布局节
static NSString *ZPBuildDiagnostics(void); // 前置声明，定义在设置页节（诊断行）
static BOOL gThemeHookInstalled = NO; // 主题段已装标记：+load 期即安装，诊断行也要读，故在此声明（安装节不再重复定义）

static void ZHSetGlassEnabled(BOOL on) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:on forKey:kZPGlassKey];
    [ud synchronize];
    for (UIView *bar in [gLiveBars allObjects]) ZHApplyBar(bar);
    NSLog(@"[zhplugin] glass switch -> %@", on ? @"ON" : @"OFF");
}

#pragma mark - 纯黑背景（主题发色点）

// 颜色系统的夜间权威：+[ZHThemeManage isNightMode]（与发色点内部判定同源）；
// 取不到时回落 ZHTabBarNewTheme.share.isDark，再回落 keyWindow 的 trait。
static BOOL ZPAppIsNight(void) {
    Class tmCls = NSClassFromString(@"ZHThemeManage");
    if (tmCls && [tmCls respondsToSelector:@selector(isNightMode)])
        return ((BOOL (*)(id, SEL))objc_msgSend)(tmCls, @selector(isNightMode));
    Class themeCls = NSClassFromString(@"ZHTabBarNewTheme");
    if (themeCls && [themeCls respondsToSelector:@selector(share)]) {
        id share = ((id (*)(id, SEL))objc_msgSend)(themeCls, @selector(share));
        if (share && [share respondsToSelector:@selector(isDark)])
            return ZHGetBool(share, @"isDark", NO);
    }
    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].windows.firstObject;
    return win.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
}

// 画布 token 单例（身份制命中）：MapUIFrame99A 主画布、MapUIFrame10A 二级画布。
// 懒解析 + 静态 RETAIN（MRC）：只在取色 hook 命中路径（ZPIsCanvasModel，且纯黑已开）
// 首次真正需要时经 dispatch_once 解析；安装路径绝不预先解析——安装期触发
// ZHColorModel 的 +initialize/单例构造曾疑致启动闪退（2026-11-26 对照实验定性）。
// 解析失败（类/方法不存在）则两单例保持 nil，纯黑静默不生效，不崩。
static id gCanvasMain = nil;      // MapUIFrame99A (#FFFFFF / #191B1F)
static id gCanvasSecondary = nil; // MapUIFrame10A (#F8F8FA / #212429)
static void ZPResolveCanvasModels(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cmCls = NSClassFromString(@"ZHColorModel");
        if (!cmCls) return;
        if ([cmCls respondsToSelector:@selector(MapUIFrame99A)])
            gCanvasMain = [((id (*)(id, SEL))objc_msgSend)(cmCls, @selector(MapUIFrame99A)) retain];
        if ([cmCls respondsToSelector:@selector(MapUIFrame10A)])
            gCanvasSecondary = [((id (*)(id, SEL))objc_msgSend)(cmCls, @selector(MapUIFrame10A)) retain];
    });
}
static BOOL ZPIsCanvasModel(id model) {
    if (!model) return NO;
    ZPResolveCanvasModels();
    return model == gCanvasMain || model == gCanvasSecondary;
}

static IMP gOrigColorWithModel = NULL;
static id ZP_Theme_colorWithModel(id self, SEL _cmd, id model, BOOL ignoreNight) {
    id color = ((id (*)(id, SEL, id, BOOL))gOrigColorWithModel)(self, _cmd, model, ignoreNight);
    if (!ignoreNight && ZPBlackEnabled() && ZPAppIsNight() && ZPIsCanvasModel(model))
        return [UIColor blackColor];
    return color;
}

// 开关切换后让已在屏页面按知乎原渠道重新取色：补发 +setNightMode: 内部同款三条主题通知
// （只发通知，不动 NIGHT_MODE_KEY、不调 +changeTheme 的日夜翻转动画路径）。
static void ZPPostThemeRefresh(void) {
    BOOL night = ZPAppIsNight();
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:@"kNSObjectUpdateThemeHighNotification" object:nil];
    [nc postNotificationName:@"kNSObjectUpdateThemeNormalNotification" object:nil];
    [nc postNotificationName:@"kRNUpdateThemeNormalNotification" object:nil
                    userInfo:@{ @"isNight": @(night) }];
}

static void ZPSetBlackEnabled(BOOL on) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:on forKey:kZPBlackKey];
    [ud synchronize];
    void (^apply)(void) = ^{
        // 主题钩已在 +load 源头装好：切换后补发主题通知，让已在屏页面按原渠道重取色
        ZPPostThemeRefresh();
        for (UIView *bar in [gLiveBars allObjects]) ZHApplyBar(bar);
    };
    if ([NSThread isMainThread]) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
    NSLog(@"[zhplugin] blackbg switch -> %@", on ? @"ON" : @"OFF");
}

#pragma mark - 玻璃盘构造（WCTabBarGlass 本体配方：系统材质采样 + 装饰层堆液态感）

// 采样核心：UIBlurEffect SystemUltraThinMaterial（style 6）——iOS 13 经典材质
// 通道，不申请 UIGlassEffect、不受知乎 UIDesignRequiresCompatibility 兼容标志
// 门控（UIGlassEffect 路线已两版真机实心，废弃）。液态感靠装饰层堆出来：
// baseFill 透色 / wash 渐变光泽 / rim 边缘高光 / shadow 投影 / selection 透镜。
// 分层（阴影与裁剪必须分层，合在一层会互相杀）：
//   外壳 wrapper UIView：只承阴影（黑 α0.25 / radius 16 / offset (0,6)），
//     不裁剪、无背景色；
//   裁剪容器 UIView（外壳内）：cornerRadius=盘高/2、cornerCurve=continuous、
//     masksToBounds=YES，内依次垫 材质效果视图 → baseFill → wash；
//   rim 描边 UIView（外壳内、裁剪容器之上）：同圆角、半透明白 1px 边。
// 透镜同配方小胶囊，仅 fill 略强于盘。盘内部件以关联对象挂在外壳上（MRC 均 RETAIN 持有）。
static char kPlateClipKey;  // 裁剪容器（RETAIN）
static char kPlateFxKey;    // 材质效果视图 UIVisualEffectView（RETAIN）
static char kPlateFillKey;  // baseFill 透色层（RETAIN）
static char kPlateWashKey;  // wash 视图（RETAIN）
static char kPlateGradKey;  // wash 内的 CAGradientLayer（RETAIN）
static char kPlateRimKey;   // rim 描边层（RETAIN）
static char kPlateLensKey;  // 是否透镜（NSNumber, RETAIN）——决定 fill 取值

// 参数初值（均为真机微调项）：
//   blur style = 6（SystemUltraThinMaterial）；
//   盘 fill：夜间 白 α0.06、日间 白 α0.30；透镜 fill：夜间 白 α0.10、日间 白 α0.18；
//   wash：白色对角渐变 α 0.10 → 0.02；rim：白 α0.15、宽 1/scale；
//   shadow：黑、opacity 0.25、radius 16、offset (0,6)。
static UIView *ZHMakePlate(BOOL lens) {
    UIView *shell = [[UIView alloc] initWithFrame:CGRectZero];
    shell.userInteractionEnabled = NO; // 盘永不吃点击（全链 NO，含所有子层）
    shell.backgroundColor = nil;
    shell.layer.shadowColor = [UIColor blackColor].CGColor;
    shell.layer.shadowOpacity = 0.25;
    shell.layer.shadowRadius = 16;
    shell.layer.shadowOffset = CGSizeMake(0, 6);

    UIView *clip = [[UIView alloc] initWithFrame:CGRectZero];
    clip.userInteractionEnabled = NO;
    clip.layer.cornerCurve = kCACornerCurveContinuous;
    clip.layer.masksToBounds = YES;
    [shell addSubview:clip];

    UIVisualEffectView *fx = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
    fx.userInteractionEnabled = NO;
    [clip addSubview:fx];

    UIView *fill = [[UIView alloc] initWithFrame:CGRectZero];
    fill.userInteractionEnabled = NO;
    [clip addSubview:fill];

    UIView *wash = [[UIView alloc] initWithFrame:CGRectZero];
    wash.userInteractionEnabled = NO;
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.colors = @[ (id)[UIColor colorWithWhite:1.0 alpha:0.10].CGColor,
                     (id)[UIColor colorWithWhite:1.0 alpha:0.02].CGColor ];
    grad.startPoint = CGPointMake(0, 0);
    grad.endPoint = CGPointMake(1, 1);
    [wash.layer addSublayer:grad];
    [clip addSubview:wash];

    UIView *rim = [[UIView alloc] initWithFrame:CGRectZero];
    rim.userInteractionEnabled = NO;
    rim.layer.cornerCurve = kCACornerCurveContinuous;
    rim.layer.borderWidth = 1.0 / [UIScreen mainScreen].scale;
    [shell addSubview:rim];

    objc_setAssociatedObject(shell, &kPlateClipKey, clip, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(shell, &kPlateFxKey, fx, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(shell, &kPlateFillKey, fill, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(shell, &kPlateWashKey, wash, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(shell, &kPlateGradKey, grad, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(shell, &kPlateRimKey, rim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(shell, &kPlateLensKey, @(lens), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [clip release]; [fx release]; [fill release]; [wash release]; [rim release];
    return shell;
}

// 明暗着色：fill/rim 按当前明暗重设（明暗判定走 ZPAppIsNight 既有口径）。
// ZHSetPlateFrame 每轮布局都会调用本函数，而主题切换（notifyThemeSwitch /
// updateTheme: / trait 变化）最终都经 ZHApplyBar→ZHLayoutBar→ZHSetPlateFrame
// 走到这里，故主题切换自动跟随、无需另挂刷新点。逐项先比对现值再写，保持幂等。
// 明暗数据源定案（本轮）：ZPAppIsNight 改前改后都是同一口径——优先 ZHThemeManage
// +isNightMode（知乎自有主题权威），次选 ZHTabBarNewTheme.share.isDark，系统 trait
// 仅末位兜底；fill 的明暗取值本来就走它、没脱节。真正脱节的是材质层本身：
// UIBlurEffect 的明暗由效果视图的 traitCollection（系统外观）解析，知乎主题与
// 系统外观不一致时（如知乎夜间+系统浅色），材质会按系统那侧渲染（真机暗色图里
// 胶囊呈浅灰即此）。修法照 DYKiller 对其 Regular 槽位的做法：给盘/透镜外壳钉
// overrideUserInterfaceStyle（夜→Dark、日→Light），外壳的 trait 覆盖会传给整棵
// 子树（材质/fill/wash/rim 一并按知乎主题解析）；本函数每轮布局都会跑到，
// 主题切换时在既有刷新路径里自然同步更新，无需另挂刷新点。
static void ZHPlateApplyTheme(UIView *plate) {
    BOOL lens = [objc_getAssociatedObject(plate, &kPlateLensKey) boolValue];
    BOOL dark = ZPAppIsNight();
    UIUserInterfaceStyle wantStyle = dark ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    if (plate.overrideUserInterfaceStyle != wantStyle)
        plate.overrideUserInterfaceStyle = wantStyle;
    UIView *fill = objc_getAssociatedObject(plate, &kPlateFillKey);
    // 透镜日间 fill：0.45 在浅色图里读作实心灰片（采样 (222,220,221)），降到 0.18；夜间 0.10 不动
    CGFloat fa = lens ? (dark ? 0.10 : 0.18) : (dark ? 0.06 : 0.30);
    UIColor *fc = [UIColor colorWithWhite:1.0 alpha:fa];
    if (fill && ![fill.backgroundColor isEqual:fc]) fill.backgroundColor = fc;
    UIView *rim = objc_getAssociatedObject(plate, &kPlateRimKey);
    UIColor *rc = [UIColor colorWithWhite:1.0 alpha:0.15];
    if (rim && !CGColorEqualToColor(rim.layer.borderColor, rc.CGColor))
        rim.layer.borderColor = rc.CGColor;
}

// frame 语义沿用旧版：空 frame ⇒ 整盘（含外壳与其阴影）隐藏；非空 ⇒ 显示、
// frame 变了才 setFrame，并把内部各层 frame / 圆角 / shadowPath 同步到新
// bounds（逐项比对现值后才写，保持 apply 幂等收敛）。
static void ZHSetPlateFrame(UIView *plate, CGRect f) {
    if (!plate) return;
    if (CGRectIsEmpty(f)) { plate.hidden = YES; return; }
    plate.hidden = NO;
    if (!CGRectEqualToRect(plate.frame, f)) plate.frame = f;
    CGRect b = plate.bounds;
    CGFloat r = f.size.height / 2;
    UIView *clip = objc_getAssociatedObject(plate, &kPlateClipKey);
    if (clip) {
        if (!CGRectEqualToRect(clip.frame, b)) clip.frame = b;
        if (clip.layer.cornerRadius != r) clip.layer.cornerRadius = r;
        CGRect cb = clip.bounds;
        UIView *fx = objc_getAssociatedObject(plate, &kPlateFxKey);
        UIView *fill = objc_getAssociatedObject(plate, &kPlateFillKey);
        UIView *wash = objc_getAssociatedObject(plate, &kPlateWashKey);
        if (fx && !CGRectEqualToRect(fx.frame, cb)) fx.frame = cb;
        if (fill && !CGRectEqualToRect(fill.frame, cb)) fill.frame = cb;
        if (wash && !CGRectEqualToRect(wash.frame, cb)) wash.frame = cb;
        CAGradientLayer *grad = objc_getAssociatedObject(plate, &kPlateGradKey);
        if (grad && wash && !CGRectEqualToRect(grad.frame, wash.bounds)) grad.frame = wash.bounds;
    }
    UIView *rim = objc_getAssociatedObject(plate, &kPlateRimKey);
    if (rim) {
        if (!CGRectEqualToRect(rim.frame, b)) rim.frame = b;
        if (rim.layer.cornerRadius != r) rim.layer.cornerRadius = r;
    }
    CGPathRef path = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:r].CGPath;
    if (!plate.layer.shadowPath || !CGPathEqualToPath(plate.layer.shadowPath, path))
        plate.layer.shadowPath = path;
    ZHPlateApplyTheme(plate);
}

// 合法性夹取（最后一道闸）：rect 必须完整落在 bounds 内（四边各留 2pt），
// 尺寸过大先收尺寸再夹原点——任何路径算出的 rect 都不许带出界值上盘。
static CGRect ZHClampRectToBounds(CGRect r, CGRect bounds) {
    CGFloat maxW = bounds.size.width - 4, maxH = bounds.size.height - 4;
    if (r.size.width > maxW) r.size.width = maxW;
    if (r.size.height > maxH) r.size.height = maxH;
    if (r.origin.x < 2) r.origin.x = 2;
    if (r.origin.y < 2) r.origin.y = 2;
    if (CGRectGetMaxX(r) > bounds.size.width - 2) r.origin.x = bounds.size.width - 2 - r.size.width;
    if (CGRectGetMaxY(r) > bounds.size.height - 2) r.origin.y = bounds.size.height - 2 - r.size.height;
    return r;
}

#pragma mark - 开关回调（单例 handler，静态 RETAIN）

@interface ZHPluginHandler : NSObject
- (void)zhPluginGlassSwitchChanged:(id)sender;
- (void)zhPluginBlackSwitchChanged:(id)sender;
- (void)zhPluginLongPress:(UILongPressGestureRecognizer *)g;
- (void)zhPluginDiagTapped:(id)sender;
@end

static ZHPluginHandler *gHandler = nil;
static ZHPluginHandler *ZPHandler(void) {
    if (!gHandler) gHandler = [[ZHPluginHandler alloc] init];
    return gHandler;
}

static id gGlassCellInfo = nil;  // 设置页「玻璃底栏」行模型（静态 RETAIN，全程一份）
static id gBlackCellInfo = nil;  // 设置页「纯黑背景」行模型（静态 RETAIN，全程一份）
static id gDiagCellInfo = nil;   // 设置页「诊断信息」行模型（静态 RETAIN，全程一份）
static id gGlassBlock = nil;     // 玻璃行模型的 action block（copy 后静态持有，MRC 防悬空）
static id gBlackBlock = nil;     // 纯黑行模型的 action block（同上）

@implementation ZHPluginHandler
// sender 为 UISwitch 时以其 isOn 为准；为 cellInfo 时读其 isSwitchOn 并与当前状态比对取反兜底
- (void)zpHandleSwitch:(id)sender isGlass:(BOOL)isGlass {
    BOOL cur = isGlass ? ZHGlassEnabled() : ZPBlackEnabled();
    BOOL target;
    if ([sender isKindOfClass:[UISwitch class]]) {
        target = [(UISwitch *)sender isOn];
    } else if (sender && [sender respondsToSelector:@selector(isSwitchOn)]) {
        BOOL modelOn = ZHGetBool(sender, @"isSwitchOn", cur);
        target = (modelOn != cur) ? modelOn : !cur;
    } else {
        target = !cur;
    }
    id info = isGlass ? gGlassCellInfo : gBlackCellInfo;
    if (info) ZHSetBool(info, @"setSwitchOn:", target);
    if (isGlass) ZHSetGlassEnabled(target);
    else ZPSetBlackEnabled(target);
}
- (void)zhPluginGlassSwitchChanged:(id)sender { [self zpHandleSwitch:sender isGlass:YES]; }
- (void)zhPluginBlackSwitchChanged:(id)sender { [self zpHandleSwitch:sender isGlass:NO]; }
- (void)zhPluginLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    BOOL target = !ZHGlassEnabled();
    if (gGlassCellInfo) ZHSetBool(gGlassCellInfo, @"setSwitchOn:", target);
    ZHSetGlassEnabled(target);
}
// 诊断行点击：纯读取拼诊断文本 → 复制到剪贴板 → 行副标题改「已复制」并 best-effort 刷新该表。
// sender 可能是行模型/cell/无参，方法本体不依赖它（数据从 gDiagCellInfo 与 gLiveBars 取）。
- (void)zhPluginDiagTapped:(id)sender {
    (void)sender;
    NSString *text = ZPBuildDiagnostics();
    [UIPasteboard generalPasteboard].string = text;
    NSLog(@"[zhplugin] diagnostics copied (%lu chars)", (unsigned long)text.length);
    if (gDiagCellInfo && [gDiagCellInfo respondsToSelector:@selector(setSubTitle:)]) {
        ((void (*)(id, SEL, id))objc_msgSend)(gDiagCellInfo, @selector(setSubTitle:), @"已复制");
        @try {
            id cell = ZHGetObj(gDiagCellInfo, @"cell");
            UIView *v = [cell isKindOfClass:[UIView class]] ? (UIView *)cell : nil;
            while (v && ![v isKindOfClass:[UITableView class]]) v = v.superview;
            if (v) [(UITableView *)v reloadData];
        } @catch (NSException *e) { /* 副标题刷新失败无碍，剪贴板已写入 */ }
    }
}
@end

#pragma mark - 布局（apply 幂等：开 -> 玻璃布局；关 -> 恢复原样）

static void ZHEnsurePlates(UIView *bar, UIView *stack) {
    UIView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    if (!capsule) {
        capsule = ZHMakePlate(NO);
        [bar insertSubview:capsule belowSubview:stack];
        objc_setAssociatedObject(bar, &kCapsuleKey, capsule, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [capsule release];
    }
    UIView *lens = objc_getAssociatedObject(bar, &kLensKey);
    if (!lens) {
        lens = ZHMakePlate(YES);
        [bar insertSubview:lens belowSubview:stack];
        objc_setAssociatedObject(bar, &kLensKey, lens, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [lens release];
    }
    // 层级（盘是内容的同层兄弟、压在内容之下）：
    // bar 内自下而上须为 capsule < lens < stack(items)；顺序不对才重排，就位时不动层级。
    NSArray *subs = bar.subviews;
    NSUInteger ci = [subs indexOfObject:capsule];
    NSUInteger li = [subs indexOfObject:lens];
    NSUInteger si = [subs indexOfObject:stack];
    if (ci != NSNotFound && li != NSNotFound && si != NSNotFound && !(ci < li && li < si)) {
        [capsule removeFromSuperview];
        [lens removeFromSuperview];
        [bar insertSubview:capsule belowSubview:stack];
        [bar insertSubview:lens belowSubview:stack];
    }
}

static NSArray *ZHBackgroundViews(UIView *bar) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *name in @[@"seperatorView", @"leftImageView", @"centerImageView", @"rightImageView"]) {
        UIView *v = ZHGetObj(bar, name);
        if (v && [v isKindOfClass:[UIView class]]) [out addObject:v];
    }
    return out;
}

// 关：盘与透镜隐藏、原背景/顶线/背景图恢复、背景色按存档原值恢复
static void ZHRestoreBar(UIView *bar) {
    UIView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    UIView *lens = objc_getAssociatedObject(bar, &kLensKey);
    capsule.hidden = YES;
    lens.hidden = YES;
    for (UIView *v in ZHBackgroundViews(bar)) v.hidden = NO;
    UIColor *orig = objc_getAssociatedObject(bar, &kOrigBgKey);
    if (orig) bar.backgroundColor = orig;
}

// item 的内容并集（图标+标题）在 bar 坐标系中的矩形；取不到内容视图时回落 item 自身槽位。
// 坐标一律换算（[bar convertRect:… fromView:…]），绝不直接读 .frame 拼算——item 的
// .frame 是其父视图（stackView）坐标系，与 bar 坐标系差一个 stack 原点偏移。
static CGRect ZHItemContentRect(UIView *bar, UIView *item, CGRect slotFallback) {
    CGRect u = CGRectNull;
    for (NSString *name in @[@"iconImageView", @"titleLable"]) {
        UIView *v = ZHGetObj(item, name);
        if (v && [v isKindOfClass:[UIView class]] && [v isDescendantOfView:bar]) {
            if (v.hidden || v.alpha < 0.01) continue; // 隐藏的内容视图（如被头像 customView 顶替的图标）不进几何
            CGRect r = [bar convertRect:v.bounds fromView:v];
            if (r.size.width > 0 && r.size.height > 0)
                u = CGRectIsNull(u) ? r : CGRectUnion(u, r);
        }
    }
    if (CGRectIsNull(u)) u = slotFallback;
    return u;
}

static void ZHLayoutBar(UIView *bar) {
    ZHRegisterBar(bar);
    CGRect bounds = bar.bounds;
    UIView *stack = ZHGetObj(bar, @"stackView");
    if (!stack || ![stack isKindOfClass:[UIView class]]) return;
    // 可见 item 只认实测状态：hidden / alpha 近 0 / 零尺寸一律剔除
    // （v2 改包被隐藏的 3 项即使有残余视图也不许进几何，XHS isVisible: 同口径）。
    NSArray *arranged = ZHGetObj(stack, @"arrangedSubviews");
    NSMutableArray *items = [NSMutableArray array];
    for (UIView *v in arranged) {
        if (![v isKindOfClass:[UIView class]]) continue;
        if (v.hidden || v.alpha < 0.01) continue;
        if (v.bounds.size.width < 1 || v.bounds.size.height < 1) continue;
        [items addObject:v];
    }

    ZHEnsurePlates(bar, stack);
    UIView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    UIView *lens = objc_getAssociatedObject(bar, &kLensKey);
    if (items.count == 0 || bounds.size.width < 50 || bounds.size.height < 30) {
        // 暂无可见项/几何未就绪：盘先建好并隐藏（XHS 空 frame 即隐藏语义），
        // 等选中/页面切换后的下一轮 layout 再按实测 frame 亮出——不留旧 frame 残影，
        // 也不出现「盘从未创建、之后再也不补」的死状态（旧版图2 无盘的成因之一）。
        ZHSetPlateFrame(capsule, CGRectZero);
        ZHSetPlateFrame(lens, CGRectZero);
        return;
    }

    // 存档原始背景色（只存第一次、且不是我们清过的透明色）
    if (!objc_getAssociatedObject(bar, &kOrigBgKey)) {
        UIColor *bg = bar.backgroundColor;
        CGFloat a = 0;
        if (bg && [bg getWhite:NULL alpha:&a] && a > 0.01)
            objc_setAssociatedObject(bar, &kOrigBgKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        else if (bg && ![bg isEqual:[UIColor clearColor]])
            objc_setAssociatedObject(bar, &kOrigBgKey, bg, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (![bar.backgroundColor isEqual:[UIColor clearColor]]) bar.backgroundColor = [UIColor clearColor];
    for (UIView *v in ZHBackgroundViews(bar)) if (!v.hidden) v.hidden = YES;

    // 几何全部来自实测 frame 的坐标换算（bar 坐标系）：横向认 item 槽位、纵向认图标+标题
    // 内容并集，选中序号以 item 的 themeSelected 为准（取不到回落 0）。
    // 坐标铁律：item 的 .frame 是父视图（stackView）坐标系，禁止直接拼到 bar 坐标系；
    // 一律 [bar convertRect:item.bounds fromView:item] 换算。换算结果逐项做合法性校验：
    // 槽位为空/宽高不合常理/越出 bar → 改用 item 中心点（同样换算）+ 实测尺寸重拼；
    // 中心点也不可信 → 整轮几何作废：不画出界 rect，盘先隐藏、有限次（≤3）下一拍重试，
    // 等布局落定后再算（旧版把某一时刻的错位 rect 直接画上盘，是盘出界的成因之一）。
    CGRect slotU = CGRectNull;    // 可见 item 槽位并集（横向）
    CGRect contentU = CGRectNull; // 可见 item 内容并集（纵向）
    NSUInteger sel = NSNotFound;
    CGRect selSlot = CGRectNull;
    NSMutableArray *slots = [NSMutableArray arrayWithCapacity:items.count];
    BOOL geoOK = YES;
    for (NSUInteger i = 0; i < items.count; i++) {
        UIView *it = items[i];
        CGRect slot = [bar convertRect:it.bounds fromView:it];
        if (CGRectIsEmpty(slot) || slot.size.width < 8 || slot.size.height < 8 ||
            slot.origin.x < -1 || slot.origin.y < -1 ||
            CGRectGetMaxX(slot) > bounds.size.width + 1 || CGRectGetMaxY(slot) > bounds.size.height + 1) {
            CGPoint c = [bar convertPoint:CGPointMake(CGRectGetMidX(it.bounds), CGRectGetMidY(it.bounds))
                                 fromView:it];
            CGFloat w = it.bounds.size.width, h = it.bounds.size.height;
            if (w < 8 || h < 8 || c.x < 0 || c.y < 0 ||
                c.x > bounds.size.width || c.y > bounds.size.height) { geoOK = NO; break; }
            slot = CGRectMake(c.x - w / 2, c.y - h / 2, w, h);
        }
        [slots addObject:[NSValue valueWithCGRect:slot]];
        slotU = CGRectIsNull(slotU) ? slot : CGRectUnion(slotU, slot);
        CGRect cr = ZHItemContentRect(bar, it, slot);
        contentU = CGRectIsNull(contentU) ? cr : CGRectUnion(contentU, cr);
        if (sel == NSNotFound && ZHGetBool(it, @"themeSelected", NO)) { sel = i; selSlot = slot; }
    }
    if (!geoOK) {
        NSNumber *retry = objc_getAssociatedObject(bar, &kGeoRetryKey);
        ZHSetPlateFrame(capsule, CGRectZero);
        ZHSetPlateFrame(lens, CGRectZero);
        if (retry.unsignedIntegerValue < 3) {
            objc_setAssociatedObject(bar, &kGeoRetryKey, @(retry.unsignedIntegerValue + 1),
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ZHRequestApply(bar);
        }
        return;
    }
    objc_setAssociatedObject(bar, &kGeoRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (sel == NSNotFound) {
        sel = 0;
        selSlot = [slots[0] CGRectValue];
    }

    // 胶囊：横向 = 槽位并集左右各扩 8；高 = 内容并集高 + 14，纵向以内容并集中心对齐；全程夹回栏内
    CGFloat capW = slotU.size.width + 16;
    if (capW > bounds.size.width - 8) capW = bounds.size.width - 8;
    CGFloat capH = contentU.size.height + 14;
    if (capH > bounds.size.height - 8) capH = bounds.size.height - 8;
    CGFloat capX = CGRectGetMidX(slotU) - capW / 2;
    if (capX < 4) capX = 4;
    if (capX + capW > bounds.size.width - 4) capX = bounds.size.width - 4 - capW;
    CGFloat capY = CGRectGetMidY(contentU) - capH / 2;
    CGFloat maxY = bounds.size.height - 4 - capH;
    if (capY < 2) capY = 2;
    if (capY > maxY) capY = maxY < 2 ? 2 : maxY;
    CGRect capRect = ZHClampRectToBounds(CGRectMake(capX, capY, capW, capH), bounds);
    ZHSetPlateFrame(capsule, capRect);

    // 透镜：锚定选中 item 本人——横向 = 其槽位左右各扩 4（此处取 +8 并夹在
    // 胶囊内），纵向在胶囊内居中、高 = 胶囊高 - 10；同配方材质盘、fill 略强于盘。
    CGFloat lensH = capH - 10;
    if (lensH < 8) lensH = capH;
    CGFloat lensW = selSlot.size.width + 8;
    CGFloat lensX = CGRectGetMidX(selSlot) - lensW / 2;
    if (lensX < capX + 2) lensX = capX + 2;
    if (lensX + lensW > capX + capW - 2) lensX = capX + capW - 2 - lensW;
    CGRect lensRect = ZHClampRectToBounds(
        CGRectMake(lensX, capY + (capH - lensH) / 2, lensW, lensH), bounds);

    NSNumber *prev = objc_getAssociatedObject(bar, &kSelIdxKey);
    BOOL selChanged = (!prev || prev.unsignedIntegerValue != sel);
    if (selChanged && !lens.hidden && lens.frame.size.width > 0) {
        // 选中切换：透镜滑到新选中项（0.25s，与知乎原切换动画同拍）
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseInOut
                         animations:^{ ZHSetPlateFrame(lens, lensRect); } completion:nil];
    } else {
        ZHSetPlateFrame(lens, lensRect);
    }
    if (selChanged)
        objc_setAssociatedObject(bar, &kSelIdxKey, @(sel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void ZHApplyBar(UIView *bar) {
    ZHRegisterBar(bar);
    // 长按兜底手势只装一次（开关与玻璃盘无关，关着时也要能长按打开）
    if (!objc_getAssociatedObject(bar, &kGestureKey)) {
        UILongPressGestureRecognizer *lp =
            [[UILongPressGestureRecognizer alloc] initWithTarget:ZPHandler()
                                                          action:@selector(zhPluginLongPress:)];
        lp.minimumPressDuration = 0.8;
        lp.cancelsTouchesInView = NO;
        [bar addGestureRecognizer:lp];
        objc_setAssociatedObject(bar, &kGestureKey, lp, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [lp release];
    }
    if (ZHGlassEnabled()) ZHLayoutBar(bar);
    else ZHRestoreBar(bar);
}

static void ZHRequestApply(UIView *bar) {
    if (objc_getAssociatedObject(bar, &kSchedKey)) return;
    objc_setAssociatedObject(bar, &kSchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(bar, &kSchedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([bar isKindOfClass:NSClassFromString(@"ZHTabBarNew")]) ZHApplyBar(bar);
    });
}

// 选中变化不再同步施工：统一走 ZHRequestApply 的下一拍 apply——selectItem: 调用当刻
// item 的 themeSelected 可能尚未更新，同步读会让透镜落到旧选中项（旧版「点击有 bug」成因之一）；
// 下一拍状态已定，透镜动画在 ZHLayoutBar 内按选中序号变化触发。

#pragma mark - 设置页插行（锚点：contactsCellInfo 行模型对象本身，连插三行）

// 在 owner 对象的全部 object 型属性/ivar 里找「装着 anchor 的数组」，返回定位信息
// 结果字典：owner / key（属性名或 ivar 名）/ array / index / viaIvar(BOOL)
static NSDictionary *ZHFindContainer(id root, id anchor, int depth) {
    if (!root || !anchor || depth < 0) return nil;
    NSMutableArray *names = [NSMutableArray array];
    NSMutableArray *viaIvarFlags = [NSMutableArray array];
    Class cls = object_getClass(root);
    for (Class c = cls; c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int pn = 0;
        objc_property_t *plist = class_copyPropertyList(c, &pn);
        for (unsigned int i = 0; i < pn; i++) {
            const char *n = property_getName(plist[i]);
            if (n) { [names addObject:[NSString stringWithUTF8String:n]]; [viaIvarFlags addObject:@NO]; }
        }
        if (plist) free(plist);
        unsigned int in = 0;
        Ivar *ilist = class_copyIvarList(c, &in);
        for (unsigned int i = 0; i < in; i++) {
            const char *n = ivar_getName(ilist[i]);
            const char *t = ivar_getTypeEncoding(ilist[i]);
            if (n && t && t[0] == '@') { [names addObject:[NSString stringWithUTF8String:n]]; [viaIvarFlags addObject:@YES]; }
        }
        if (ilist) free(ilist);
    }

    for (NSUInteger i = 0; i < names.count; i++) {
        NSString *name = names[i];
        BOOL viaIvar = [viaIvarFlags[i] boolValue];
        id val = nil;
        @try {
            val = viaIvar ? object_getIvar(root, class_getInstanceVariable(cls, [name UTF8String]))
                          : [root valueForKey:name];
        } @catch (NSException *e) { val = nil; }
        if (!val) continue;
        if ([val isKindOfClass:[NSArray class]]) {
            NSUInteger idx = [(NSArray *)val indexOfObjectIdenticalTo:anchor];
            if (idx != NSNotFound)
                return @{ @"owner": root, @"key": name, @"array": val,
                          @"index": @(idx), @"viaIvar": @(viaIvar) };
            if (depth > 0) { // 数组里装的是 section 对象时，逐个下钻一层
                for (id el in (NSArray *)val) {
                    if ([el isKindOfClass:[NSArray class]] || [el isKindOfClass:[NSDictionary class]]) continue;
                    NSDictionary *hit = ZHFindContainer(el, anchor, depth - 1);
                    if (hit) return hit;
                }
            }
        }
    }
    return nil;
}

static void ZHSetContainerValue(NSDictionary *hit, NSArray *newArr) {
    id owner = hit[@"owner"];
    NSString *key = hit[@"key"];
    BOOL viaIvar = [hit[@"viaIvar"] boolValue];
    @try {
        if (viaIvar) {
            Ivar iv = class_getInstanceVariable(object_getClass(owner), [key UTF8String]);
            if (iv) object_setIvar(owner, iv, newArr);
        } else {
            [owner setValue:newArr forKey:key];
        }
    } @catch (NSException *e) {
        NSLog(@"[zhplugin] settings container set failed: %@", e);
    }
}

static UISwitch *ZHFindSwitch(UIView *v) {
    if ([v isKindOfClass:[UISwitch class]]) return (UISwitch *)v;
    for (UIView *s in v.subviews) {
        UISwitch *r = ZHFindSwitch(s);
        if (r) return r;
    }
    return nil;
}

static UITableView *ZHFindTable(UIView *v) {
    if ([v isKindOfClass:[UITableView class]]) return (UITableView *)v;
    for (UIView *s in v.subviews) {
        UITableView *r = ZHFindTable(s);
        if (r) return r;
    }
    return nil;
}

// 用官方工厂造一行开关行模型；blockStorage 静态持有 block（MRC 防悬空）
static id ZPMakeSwitchInfo(Class infoCls, NSString *title, NSString *sub,
                           BOOL on, BOOL isGlass, id *blockStorage, id *infoStorage) {
    if (*infoStorage) return *infoStorage;
    __block id capturedInfo = nil;
    void (^action)(id) = ^(id senderInfo) {
        (void)senderInfo;
        id info = capturedInfo ?: *infoStorage;
        if (isGlass) [ZPHandler() zhPluginGlassSwitchChanged:info];
        else [ZPHandler() zhPluginBlackSwitchChanged:info];
    };
    *blockStorage = [action copy];
    id info = ((id (*)(id, SEL, id, id, id, BOOL))objc_msgSend)(
        infoCls, @selector(switchCellInfoForTitle:subTitle:action:on:),
        title, sub, *blockStorage, on);
    if (!info) return nil;
    *infoStorage = [info retain];
    capturedInfo = *infoStorage;
    return *infoStorage;
}

// 双保险：直接给某行 cell 里的 UISwitch 挂回调并同步状态（不依赖框架对 action 的调用约定）
static void ZPAttachSwitch(id cellInfo, SEL action, BOOL on) {
    id cell = ZHGetObj(cellInfo, @"cell");
    UISwitch *sw = cell ? ZHFindSwitch(cell) : nil;
    if (!sw) return;
    [sw removeTarget:ZPHandler() action:action forControlEvents:UIControlEventValueChanged];
    [sw addTarget:ZPHandler() action:action forControlEvents:UIControlEventValueChanged];
    [sw setOn:on animated:NO];
}

#pragma mark - 诊断行（纯读取取证，点一次复制到剪贴板，避免再靠截图猜）

// 颜色读数格式化（诊断专用；读不出分量时回落 description）
static NSString *ZPColorDesc(UIColor *c) {
    if (!c) return @"nil";
    CGFloat r, g, b, a;
    if ([c getRed:&r green:&g blue:&b alpha:&a])
        return [NSString stringWithFormat:@"rgba(%.0f,%.0f,%.0f,%.2f)", r * 255, g * 255, b * 255, a];
    CGFloat w;
    if ([c getWhite:&w alpha:&a])
        return [NSString stringWithFormat:@"white(%.0f,%.2f)", w * 255, a];
    return [c description];
}

static void ZPDiagWalk(UIView *v, NSMutableString *out, int depth) {
    if (depth > 6) return;
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    [out appendFormat:@"%@%@ frame=%@ bg=%@ hidden=%d alpha=%.2f style=%ld\n",
         indent, NSStringFromClass(object_getClass(v)), NSStringFromCGRect(v.frame),
         ZPColorDesc(v.backgroundColor), (int)v.hidden, v.alpha,
         (long)v.overrideUserInterfaceStyle];
    for (UIView *s in v.subviews) ZPDiagWalk(s, out, depth + 1);
}

// 诊断文本：知乎主题值 / 系统 trait / 盘与透镜 frame（bar 坐标）/ 盘子树逐层
// （类名+frame+背景色读数）/ 底栏 item 列表（类名/frame/hidden/alpha）/ 颜色钩已装。
// 全程只读，不改任何状态；临时对象均为 autorelease，MRC 安全。
static NSString *ZPBuildDiagnostics(void) {
    NSMutableString *s = [NSMutableString stringWithString:@"[zhplugin 诊断]\n"];
    Class tmCls = NSClassFromString(@"ZHThemeManage");
    NSString *tmVal = @"n/a";
    if (tmCls && [tmCls respondsToSelector:@selector(isNightMode)])
        tmVal = ((BOOL (*)(id, SEL))objc_msgSend)(tmCls, @selector(isNightMode)) ? @"YES" : @"NO";
    [s appendFormat:@"知乎主题 isNightMode=%@ / ZPAppIsNight=%@\n",
         tmVal, ZPAppIsNight() ? @"YES" : @"NO"];
    UIWindow *win = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) { win = w; break; }
    }
    if (!win) win = [UIApplication sharedApplication].windows.firstObject;
    [s appendFormat:@"系统 trait=%ld (0未定/1浅/2深)\n", (long)win.traitCollection.userInterfaceStyle];
    [s appendFormat:@"颜色钩已装=%@ / 纯黑开关=%@ / 玻璃开关=%@\n",
         gThemeHookInstalled ? @"YES" : @"NO",
         ZPBlackEnabled() ? @"ON" : @"OFF", ZHGlassEnabled() ? @"ON" : @"OFF"];
    UIView *bar = [gLiveBars allObjects].firstObject;
    if (!bar) { [s appendString:@"底栏: 尚无实例\n"]; return s; }
    [s appendFormat:@"底栏 %@ bounds=%@ frame=%@ bg=%@\n",
         NSStringFromClass(object_getClass(bar)), NSStringFromCGRect(bar.bounds),
         NSStringFromCGRect(bar.frame), ZPColorDesc(bar.backgroundColor)];
    UIView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    UIView *lens = objc_getAssociatedObject(bar, &kLensKey);
    if (capsule)
        [s appendFormat:@"胶囊 frame=%@ hidden=%d\n", NSStringFromCGRect(capsule.frame), (int)capsule.hidden];
    else
        [s appendString:@"胶囊: 未创建\n"];
    if (lens)
        [s appendFormat:@"透镜 frame=%@ hidden=%d\n", NSStringFromCGRect(lens.frame), (int)lens.hidden];
    else
        [s appendString:@"透镜: 未创建\n"];
    if (capsule) { [s appendString:@"胶囊子树:\n"]; ZPDiagWalk(capsule, s, 1); }
    if (lens) { [s appendString:@"透镜子树:\n"]; ZPDiagWalk(lens, s, 1); }
    UIView *stack = ZHGetObj(bar, @"stackView");
    NSArray *arranged = ZHGetObj(stack, @"arrangedSubviews");
    [s appendFormat:@"items(%lu):\n", (unsigned long)arranged.count];
    for (UIView *v in arranged) {
        if (![v isKindOfClass:[UIView class]]) continue;
        CGRect r = [bar convertRect:v.bounds fromView:v];
        [s appendFormat:@"  %@ frame(bar坐标)=%@ hidden=%d alpha=%.2f selected=%@\n",
             NSStringFromClass(object_getClass(v)), NSStringFromCGRect(r),
             (int)v.hidden, v.alpha, ZHGetBool(v, @"themeSelected", NO) ? @"YES" : @"NO"];
    }
    return s;
}

// 诊断行模型：官方普通行工厂（target/selector 式）。工厂签名已在二进制核实：
// ZHSettingCellInfo +normalCellInfoForTitle:subTitle:target:selector:
// 类型编码 @48@0:8@16@24@32:40（title, subTitle, target, SEL）。
static id ZPMakeDiagInfo(Class infoCls) {
    if (gDiagCellInfo) return gDiagCellInfo;
    SEL fac = @selector(normalCellInfoForTitle:subTitle:target:selector:);
    if (![infoCls respondsToSelector:fac]) return nil;
    id info = ((id (*)(id, SEL, id, id, id, SEL))objc_msgSend)(
        infoCls, fac, @"诊断信息", @"点击复制诊断信息", ZPHandler(), @selector(zhPluginDiagTapped:));
    if (!info) return nil;
    gDiagCellInfo = [info retain];
    return gDiagCellInfo;
}

static BOOL gSettingsDone = NO;
static void ZHSettingsEnsureRows(id vc) {
    if (gSettingsDone) return;
    Class infoCls = NSClassFromString(@"ZHSettingCellInfo");
    if (!infoCls) return;
    id anchor = ZHGetObj(vc, @"contactsCellInfo");
    if (!anchor) return;

    // 定位锚点所在组数组：先走 anchor 自己的 section，再走 adapter，最后 VC 本人
    NSDictionary *hit = nil;
    id section = ZHGetObj(anchor, @"section");
    if (section) hit = ZHFindContainer(section, anchor, 0);
    if (!hit) {
        id adapter = ZHGetObj(vc, @"adapter");
        if (adapter) hit = ZHFindContainer(adapter, anchor, 1);
    }
    if (!hit) hit = ZHFindContainer(vc, anchor, 1);
    if (!hit) { NSLog(@"[zhplugin] settings: container for contactsCellInfo not found"); return; }

    NSArray *arr = hit[@"array"];
    NSUInteger anchorIdx = [hit[@"index"] unsignedIntegerValue];
    // 幂等：按标题逐行核对，缺哪行补哪行
    NSUInteger glassIdx = NSNotFound, blackIdx = NSNotFound, diagIdx = NSNotFound;
    for (NSUInteger i = 0; i < arr.count; i++) {
        id el = arr[i];
        if (![el respondsToSelector:@selector(title)]) continue;
        NSString *t = [el title];
        if ([t isEqualToString:@"玻璃底栏"]) glassIdx = i;
        else if ([t isEqualToString:@"纯黑背景"]) blackIdx = i;
        else if ([t isEqualToString:@"诊断信息"]) diagIdx = i;
    }
    if (glassIdx != NSNotFound && blackIdx != NSNotFound && diagIdx != NSNotFound) {
        gSettingsDone = YES;
        return;
    }

    id glassInfo = ZPMakeSwitchInfo(infoCls, @"玻璃底栏", @"开启后，底部栏使用清透玻璃效果",
                                    ZHGlassEnabled(), YES, &gGlassBlock, &gGlassCellInfo);
    id blackInfo = ZPMakeSwitchInfo(infoCls, @"纯黑背景", @"开启后，夜间模式下背景使用纯黑",
                                    ZPBlackEnabled(), NO, &gBlackBlock, &gBlackCellInfo);
    if (!glassInfo || !blackInfo) { NSLog(@"[zhplugin] settings: factory returned nil"); return; }
    id diagInfo = ZPMakeDiagInfo(infoCls);
    if (!diagInfo) NSLog(@"[zhplugin] settings: diag factory unavailable, switches still inserted");
    // 与锚点同 section 登记（照原生行的簿记方式）
    for (id info in @[glassInfo, blackInfo]) {
        if (section && [info respondsToSelector:@selector(addWeakSection:)])
            ((void (*)(id, SEL, id))objc_msgSend)(info, @selector(addWeakSection:), section);
    }
    if (diagInfo && section && [diagInfo respondsToSelector:@selector(addWeakSection:)])
        ((void (*)(id, SEL, id))objc_msgSend)(diagInfo, @selector(addWeakSection:), section);

    // 目标顺序：[.., 玻璃底栏, 纯黑背景, 诊断信息, contactsCellInfo(锚点), ..]
    // 收敛式插入：先把已在数组里的我方行（就是上面三个单例本人）摘下，
    // 再在锚点正上方按序整组插入——无论此前插到哪一步，本轮都收敛到同一形态。
    NSMutableArray *work = [arr mutableCopy];
    NSMutableArray *ours = [NSMutableArray arrayWithObjects:glassInfo, blackInfo, nil];
    if (diagInfo) [ours addObject:diagInfo];
    for (id info in ours) [work removeObjectIdenticalTo:info];
    NSUInteger ai = [work indexOfObjectIdenticalTo:anchor];
    if (ai == NSNotFound) { [work release]; return; }
    for (NSUInteger k = 0; k < ours.count; k++)
        [work insertObject:ours[k] atIndex:ai + k];
    if ([arr isKindOfClass:[NSMutableArray class]]) {
        [(NSMutableArray *)arr removeAllObjects];
        [(NSMutableArray *)arr addObjectsFromArray:work];
    } else {
        ZHSetContainerValue(hit, work);
    }
    [work release];
    // 诊断行没插成时不置 done：下次进设置页（loadData/viewDidAppear）再补一次
    gSettingsDone = (diagInfo != nil);
    NSLog(@"[zhplugin] settings: rows inserted above contacts at index %lu (diag=%@)",
          (unsigned long)anchorIdx, diagInfo ? @"YES" : @"NO");

    dispatch_async(dispatch_get_main_queue(), ^{
        UITableView *tv = ZHFindTable([vc view]);
        [tv reloadData];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UITableView *tv2 = ZHFindTable([vc view]);
            [tv2 reloadData];
            ZPAttachSwitch(gGlassCellInfo, @selector(zhPluginGlassSwitchChanged:), ZHGlassEnabled());
            ZPAttachSwitch(gBlackCellInfo, @selector(zhPluginBlackSwitchChanged:), ZPBlackEnabled());
        });
    });
}

#pragma mark - Hook（底栏）

static IMP gOrigSetupUI, gOrigLayoutItems, gOrigSetItems, gOrigSelect, gOrigUnselect;
static IMP gOrigNotifyTheme, gOrigUpdateTheme;

static void ZH_Bar_setupUI(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigSetupUI)(self, _cmd);
    ZHRequestApply(self);
}
static void ZH_Bar_layoutItems(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigLayoutItems)(self, _cmd);
    ZHRequestApply(self);
}
static void ZH_Bar_setItems(UIView *self, SEL _cmd, id items) {
    ((void (*)(id, SEL, id))gOrigSetItems)(self, _cmd, items);
    ZHRequestApply(self);
}
static void ZH_Bar_selectItem(UIView *self, SEL _cmd, id item) {
    ((void (*)(id, SEL, id))gOrigSelect)(self, _cmd, item);
    ZHRequestApply(self);
}
static void ZH_Bar_unselectItem(UIView *self, SEL _cmd, id item) {
    ((void (*)(id, SEL, id))gOrigUnselect)(self, _cmd, item);
    ZHRequestApply(self);
}
static void ZH_Bar_notifyThemeSwitch(UIView *self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigNotifyTheme)(self, _cmd);
    ZHRequestApply(self);
}
static void ZH_Bar_updateTheme(UIView *self, SEL _cmd, BOOL dark, id appearance) {
    ((void (*)(id, SEL, BOOL, id))gOrigUpdateTheme)(self, _cmd, dark, appearance);
    ZHRequestApply(self);
}

// ZHTabBarNew 自身方法表里没有 layoutSubviews / traitCollectionDidChange:，
// 用 class_addMethod 给它加子类级覆盖，不污染 UIView 全局。
// super 起点必须钉死在 ZHTabBarNew 的父类链上（安装时解析 IMP），绝不能在调用时用
// class_getSuperclass(object_getClass(self)) 现算：真机日志定案（osee…-144302.ips）——
// 底栏实例的动态类是 ZHTabBarNew 的子类（或 KVO 动态子类）时，现算出的 superclass 恰好
// 等于 ZHTabBarNew，objc_msgSendSuper 的查找起点落回我们 class_addMethod 加的方法本身，
// ZH_Bar_layoutSubviews 在同一调用栈内无条件自调用，栈溢出 EXC_BAD_ACCESS（点 tab 即崩）。
static IMP gOrigLayoutSubviews = NULL;
static Class gBarClass = nil;              // 安装时的 ZHTabBarNew 本尊
static IMP gSuperLayoutSubviews = NULL;    // ZHTabBarNew 父类链真正的 layoutSubviews IMP（安装时解析）
static void ZH_Bar_layoutSubviews(UIView *self, SEL _cmd) {
    BOOL reentered = (objc_getAssociatedObject(self, &kLayoutLockKey) != nil);
    if (!reentered)
        objc_setAssociatedObject(self, &kLayoutLockKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // super：三个来源都保证是父类链的真 IMP，不存在回到自身 IMP 的路径
    if (gOrigLayoutSubviews) {
        ((void (*)(id, SEL))gOrigLayoutSubviews)(self, _cmd);
    } else if (gSuperLayoutSubviews) {
        ((void (*)(id, SEL))gSuperLayoutSubviews)(self, _cmd);
    } else {
        struct objc_super sup = { self, gBarClass ? class_getSuperclass(gBarClass)
                                                  : class_getSuperclass(object_getClass(self)) };
        ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    }
    if (reentered) return; // 重入：只走 super，不再登记、不施工
    // 布局内不施工：只登记一次，ZHApplyBar 由 ZHRequestApply（kSchedKey 合并）
    // 经 dispatch_async 在主队列下一拍执行，彻底脱离当前 layout 调用栈
    ZHRequestApply(self);
    objc_setAssociatedObject(self, &kLayoutLockKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void ZH_Bar_traitChanged(UIView *self, SEL _cmd, UITraitCollection *prev) {
    // super 起点同 layoutSubviews：钉死 ZHTabBarNew 的父类，不用实例动态类现算
    struct objc_super sup = { self, gBarClass ? class_getSuperclass(gBarClass)
                                              : class_getSuperclass(object_getClass(self)) };
    ((void (*)(struct objc_super *, SEL, id))objc_msgSendSuper)(&sup, _cmd, prev);
    ZHRequestApply(self);
}

// didMoveToWindow：页面切换/栏重新入窗是 layout 之外最可靠的补触发——旧版在某些页面
// 状态下 apply 从未跑到、盘整场缺席（真机图2）。super 同 layoutSubviews 铁律：
// 安装时解析父类链 IMP 直调（gOrigDidMoveToWindow 存的就是可直调的真 IMP：
// 类自有实现被 swizzle 时存原 IMP，class_addMethod 成功时存父类链 IMP）。
static IMP gOrigDidMoveToWindow = NULL;
static void ZH_Bar_didMoveToWindow(UIView *self, SEL _cmd) {
    if (gOrigDidMoveToWindow) {
        ((void (*)(id, SEL))gOrigDidMoveToWindow)(self, _cmd);
    } else {
        struct objc_super sup = { self, gBarClass ? class_getSuperclass(gBarClass)
                                                  : class_getSuperclass(object_getClass(self)) };
        ((void (*)(struct objc_super *, SEL))objc_msgSendSuper)(&sup, _cmd);
    }
    if (self.window) ZHRequestApply(self);
}

#pragma mark - Hook（设置页）

static IMP gOrigSetLoadData, gOrigSetDidAppear;
static void ZH_Set_loadData(id self, SEL _cmd) {
    ((void (*)(id, SEL))gOrigSetLoadData)(self, _cmd);
    ZHSettingsEnsureRows(self);
}
static void ZH_Set_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))gOrigSetDidAppear)(self, _cmd, animated);
    ZHSettingsEnsureRows(self);
}

#pragma mark - 安装

static IMP ZHSwap(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NULL;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { NSLog(@"[zhplugin] missing %@ on %@", NSStringFromSelector(sel), NSStringFromClass(cls)); return NULL; }
    return method_setImplementation(m, newImp);
}

static IMP ZHSwapClassMethod(Class cls, SEL sel, IMP newImp) {
    if (!cls) return NULL;
    Method m = class_getClassMethod(cls, sel);
    if (!m) { NSLog(@"[zhplugin] missing class method %@ on %@", NSStringFromSelector(sel), NSStringFromClass(cls)); return NULL; }
    return method_setImplementation(m, newImp);
}

static BOOL gInstalled = NO;
static BOOL gSettingsHookInstalled = NO;

// 段1：纯黑——主题发色点 hook（与底栏/设置两段解耦，互不拖累）
static void ZPInstallThemeHook(void) {
    if (gThemeHookInstalled) return;
    Class tmCls = NSClassFromString(@"ZHThemeManage");
    if (!tmCls) { NSLog(@"[zhplugin] install segment theme: ZHThemeManage missing, skip"); return; }
    gOrigColorWithModel = ZHSwapClassMethod(tmCls, @selector(colorWithModel:ignoreNight:),
                                            (IMP)ZP_Theme_colorWithModel);
    gThemeHookInstalled = (gOrigColorWithModel != NULL);
    // 注意：这里绝不预先解析画布模型；改由取色 hook 首次命中时懒解析（见 ZPResolveCanvasModels）。
    NSLog(@"[zhplugin] install segment theme: colorHook=%p installed=%d", gOrigColorWithModel, gThemeHookInstalled);
    // 本段由 +load 调用（见 ZHPluginLoader）：赶在任何页面建成取色之前装好，
    // 首页等启动即建的页面在 viewDidLoad 取画布色时就走钩子，内容区直接纯黑，
    // 不再需要事后补救（+1s 延迟装钩 + 窗口清扫的老路已废弃删除）。
    // 装后补发一次知乎自家主题通知三连保留：+load 时刻尚无观察者时为空转，无害。
    if (gThemeHookInstalled && ZPBlackEnabled()) {
        ZPPostThemeRefresh();
        NSLog(@"[zhplugin] install segment theme: posted theme refresh after install");
    }
}

// 段2：玻璃底栏 hook（ZHTabBarNew）
static void ZPInstallBarHooks(void) {
    if (gInstalled) return;
    Class cls = NSClassFromString(@"ZHTabBarNew");
    if (!cls) { NSLog(@"[zhplugin] install segment bar: ZHTabBarNew missing, skip"); return; }
    gBarClass = cls;
    // 安装时一次性解析父类链的 layoutSubviews IMP，供钩子直调真 super（见 ZH_Bar_layoutSubviews 注释）
    Method superLayout = class_getInstanceMethod(class_getSuperclass(cls), @selector(layoutSubviews));
    gSuperLayoutSubviews = superLayout ? method_getImplementation(superLayout) : NULL;
    gOrigSetupUI = ZHSwap(cls, @selector(setupUI), (IMP)ZH_Bar_setupUI);
    gOrigLayoutItems = ZHSwap(cls, @selector(layoutItems), (IMP)ZH_Bar_layoutItems);
    gOrigSetItems = ZHSwap(cls, @selector(setItems:), (IMP)ZH_Bar_setItems);
    gOrigSelect = ZHSwap(cls, @selector(selectItem:), (IMP)ZH_Bar_selectItem);
    gOrigUnselect = ZHSwap(cls, @selector(unselectItem:), (IMP)ZH_Bar_unselectItem);
    gOrigNotifyTheme = ZHSwap(cls, @selector(notifyThemeSwitch), (IMP)ZH_Bar_notifyThemeSwitch);
    gOrigUpdateTheme = ZHSwap(cls, @selector(updateTheme:tabBarAppearance:), (IMP)ZH_Bar_updateTheme);
    BOOL addedLayout = class_addMethod(cls, @selector(layoutSubviews),
                                       (IMP)ZH_Bar_layoutSubviews, "v16@0:8");
    BOOL addedTrait = class_addMethod(cls, @selector(traitCollectionDidChange:),
                                      (IMP)ZH_Bar_traitChanged, "v24@0:8@16");
    if (!addedLayout) // 类自己已有 layoutSubviews 时退回 swizzle，并保留原 IMP 由钩子转调
        gOrigLayoutSubviews = ZHSwap(cls, @selector(layoutSubviews), (IMP)ZH_Bar_layoutSubviews);
    // didMoveToWindow 补触发：先备好父类链 IMP（addMethod 成功时钩子靠它调 super），再挂钩
    Method superMove = class_getInstanceMethod(class_getSuperclass(cls), @selector(didMoveToWindow));
    gOrigDidMoveToWindow = superMove ? method_getImplementation(superMove) : NULL;
    BOOL addedMove = class_addMethod(cls, @selector(didMoveToWindow),
                                     (IMP)ZH_Bar_didMoveToWindow, "v16@0:8");
    if (!addedMove) // 类自有实现：swizzle，原 IMP 覆盖父类链 IMP（直调它即真 super 行为）
        gOrigDidMoveToWindow = ZHSwap(cls, @selector(didMoveToWindow), (IMP)ZH_Bar_didMoveToWindow);
    gInstalled = (gOrigSetupUI != NULL && gOrigLayoutItems != NULL);
    NSLog(@"[zhplugin] install segment bar: setupUI=%p layoutItems=%p select=%p theme=%p addLayout=%d addTrait=%d addMove=%d installed=%d",
          gOrigSetupUI, gOrigLayoutItems, gOrigSelect, gOrigNotifyTheme, addedLayout, addedTrait, addedMove, gInstalled);
}

// 段3：设置页两行开关 hook（ZHCommonSettingViewController）
static void ZPInstallSettingsHooks(void) {
    if (gSettingsHookInstalled) return;
    Class setCls = NSClassFromString(@"ZHCommonSettingViewController");
    if (!setCls) { NSLog(@"[zhplugin] install segment settings: ZHCommonSettingViewController missing, skip"); return; }
    // loadData / viewDidAppear: 均在该类自身方法表内（静态已核），可安全 swizzle；
    // viewWillAppear: 它没自有实现，绝不能 swizzle（会改到 UIViewController 全局）。
    gOrigSetLoadData = ZHSwap(setCls, @selector(loadData), (IMP)ZH_Set_loadData);
    gOrigSetDidAppear = ZHSwap(setCls, @selector(viewDidAppear:), (IMP)ZH_Set_viewDidAppear);
    gSettingsHookInstalled = (gOrigSetLoadData != NULL && gOrigSetDidAppear != NULL);
    NSLog(@"[zhplugin] install segment settings: loadData=%p didAppear=%p installed=%d",
          gOrigSetLoadData, gOrigSetDidAppear, gSettingsHookInstalled);
}

// 三段独立安装：一段抛异常不许拖累其它段（WCBlack v4.7 教训）。
// 主题段通常已在 +load 装好，这里的调用是未装成时的补装/无操作（函数内有已装守卫）。
static void ZPInstall(void) {
    @try {
        ZPInstallThemeHook();
        NSLog(@"[zhplugin] install segment theme: OK");
    } @catch (NSException *e) {
        NSLog(@"[zhplugin] install segment theme: FAILED: %@", e);
    }
    @try {
        ZPInstallBarHooks();
        NSLog(@"[zhplugin] install segment bar: OK");
    } @catch (NSException *e) {
        NSLog(@"[zhplugin] install segment bar: FAILED: %@", e);
    }
    @try {
        ZPInstallSettingsHooks();
        NSLog(@"[zhplugin] install segment settings: OK");
    } @catch (NSException *e) {
        NSLog(@"[zhplugin] install segment settings: FAILED: %@", e);
    }
}

@interface ZHPluginLoader : NSObject
@end
@implementation ZHPluginLoader
// +load 分工（本轮定案）：主题段在此即装，底栏/设置两段仍延迟到启动后 +1s。
// 为什么主题段必须提前：内容区画布色是页面在 viewDidLoad 建成时一次性取走的存量，
// 钩子若等 +1s 再装，首页早已建成、取色已过，事后通知/清扫都够不着（上一版实测
// 顶部黑了、feed 仍灰，清扫还误伤底栏附近容器）。赶在 +load 装好，任何页面建成
// 取色时都走钩子，源头即纯黑。
// 安全边界（与首版闪退教训的区分）：首版嫌疑动作是 +load 期「急切解析画布模型」
// （触发 ZHColorModel +initialize/单例构造）外加整段全量安装；本轮 +load 只做
// 一件最小动作——对 ZHThemeManage 的 +colorWithModel:ignoreNight: 做类方法
// swizzle，不碰 ZHColorModel、画布模型保持首次取色时 dispatch_once 懒解析，
// 底栏段的布局钩子（递归修复所在段）与设置段一律不动、维持 +1s 延迟。
// 若 +load 期解析不到 ZHThemeManage（理论兜底），gThemeHookInstalled 保持 NO，
// +1s 的 ZPInstall 会再调一次 ZPInstallThemeHook 补装。
+ (void)load {
    @try {
        ZPInstallThemeHook();
        NSLog(@"[zhplugin] load: theme segment installed at +load (hook=%d)", gThemeHookInstalled);
    } @catch (NSException *e) {
        NSLog(@"[zhplugin] load: theme segment at +load FAILED (will retry at +1s): %@", e);
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(zp_didFinishLaunching:)
                                                 name:UIApplicationDidFinishLaunchingNotification
                                               object:nil];
    NSLog(@"[zhplugin] load: observer registered, bar/settings install deferred to didFinishLaunching + 1s");
}

+ (void)zp_didFinishLaunching:(NSNotification *)note {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIApplicationDidFinishLaunchingNotification
                                                  object:nil];
    // 启动已完成、宿主类与 UIApplication 均就绪，再延迟约 1 秒分三段独立安装。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ZPInstall(); });
}
@end
