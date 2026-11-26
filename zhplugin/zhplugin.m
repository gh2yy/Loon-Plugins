// zhplugin.m — 知乎 11.15.0 插件合集（2026-11-26）
// 同一个 dylib 两项功能，各有独立开关（设置页 contactsCellInfo 行正上方连插两行）：
//   1) 玻璃底栏：iOS 27 式清透玻璃悬浮底栏（原 ZHGlassBar v3 并入）
//   2) 纯黑背景：夜间模式下整体画布背景改纯黑 #000000（仿 WCBlack 路线，但走知乎主题发色点）
//
// 玻璃底栏口径（2026-11-26 按 XHSNative-1.4.dylib 反汇编逐项对齐重做）：
//   基线为 v2 改包（ZHTabBarNew 只剩首页/我的两项、stack 宽约束内收，两项中心 33.3%/66.7%）。
//   只做视觉层：原底栏背景/顶线清掉，在 stackView 之下放两块玻璃盘（胶囊盘 + 选中透镜盘），
//   按钮沿用原 ZHTabBarItemNormalView 与原点击路由，插件不新增任何拦截视图/手势到盘上。
//   玻璃盘构造 = XHSNative 工厂 plateOn:key:below:frame:bar: 本体（@0x9b34 逐指令核对）：
//   UIVisualEffectView(initWithEffect:[UIGlassEffect effectWithStyle:0=Regular])，无 tint；
//   setCornerConfiguration:[UICornerConfiguration capsuleConfiguration] 设在效果视图本体；
//   contentView.layer.masksToBounds=YES、cornerRadius=盘高/2（每次布局都设）；
//   userInteractionEnabled=NO；零填充（主页栏 fill=0 定案，fillForBar: @0x12c64 只有
//   noteBottom 默认 50）；无投影外壳、无阴影、无边框；透镜同样是无填充玻璃盘。
//   几何只认实测 frame（XHS 全部 plateOn 调用点均为真实内容视图 frame 的并集/内缩）：
//   胶囊横向 = 可见 item 槽位并集 ±8，纵向 = 图标+标题内容并集定高；透镜 = 选中 item
//   槽位 ±4、胶囊内居中。不再读 stackView.frame 推导（旧版盘错位/压 feed 的根源），
//   可见性过滤：hidden / alpha<0.01 / 零尺寸的 item 一律不算（v2 改包隐藏项残余同理）。
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
//   边界铁律（WCBlack v3.4 教训）：不整树刷色、不涂全屏覆盖层/透明宿主根背景；
//     本功能只在发色点换返回值，一个视图都不碰。
//
// 开关与入口：
//   玻璃：NSUserDefaults 键 ZHPlugin.GlassBar（新键不存在时回读旧键 ZHGlassBar.Enabled 迁移），默认开。
//   纯黑：NSUserDefaults 键 ZHPlugin.BlackBG，默认开。
//   设置页入口：ZHCommonSettingViewController 里锚定 contactsCellInfo（「查看通讯录好友」行模型对象），
//     在其所在组数组内插到它正上方，连插两行（自上而下：玻璃底栏、纯黑背景），行模型用
//     ZHSettingCellInfo 官方工厂 +switchCellInfoForTitle:subTitle:action:on: 构造（原生 cell 渲染）；
//     另留长按底栏 0.8s 切换玻璃作兜底入口。
// 纯运行时 swizzle + 类动态加方法，无 substrate 依赖；玻璃类全部动态解析。本文件按 MRC 编写：
//   凡赋给 associated/全局的对象一律 alloc/init 或 RETAIN 持有（WCBlack v3 首启闪退教训）。

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static char kCapsuleKey;   // 玻璃胶囊盘（UIVisualEffectView 本体，无外壳）
static char kLensKey;      // 选中透镜盘（同配方无填充玻璃盘）
static char kSelIdxKey;    // 上次选中序号（NSNumber, RETAIN）
static char kSchedKey;     // 已排队布局标记
static char kLayoutLockKey; // layoutSubviews 重入锁（per-instance）
static char kOrigBgKey;    // 原始 bar 背景色（RETAIN，关玻璃时恢复）
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
        ZPPostThemeRefresh();
        for (UIView *bar in [gLiveBars allObjects]) ZHApplyBar(bar);
    };
    if ([NSThread isMainThread]) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
    NSLog(@"[zhplugin] blackbg switch -> %@", on ? @"ON" : @"OFF");
}

#pragma mark - 玻璃盘构造（XHSNative plateOn 本体配方，逐项对齐）

// effectWithStyle: 实参 = 0（Regular）——XHS @0x9bcc `mov x2,#0` 后调 effectWithStyle: 定案；
// 旧版传 1（Clear）为差异①。取不到 UIGlassEffect 时回落系统薄材质（仅旧系统兜底）。
static UIVisualEffect *ZHGlassEffect(void) {
    Class glassCls = NSClassFromString(@"UIGlassEffect");
    if (glassCls && [glassCls respondsToSelector:@selector(effectWithStyle:)]) {
        id fx = ((id (*)(id, SEL, NSInteger))objc_msgSend)(glassCls, @selector(effectWithStyle:), 0); // Regular
        if (fx) return fx;
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
}

// 盘本体：UIVisualEffectView 直接就是盘（XHS 无外壳/无投影/无边框/无 tint/零填充）。
// cornerConfiguration 胶囊设在效果视图本体（@0x9c18 setCornerConfiguration:），
// contentView.layer 只开 masksToBounds；cornerRadius 在 ZHSetPlateFrame 里按盘高/2 每轮设。
static UIVisualEffectView *ZHMakePlate(void) {
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:ZHGlassEffect()];
    v.userInteractionEnabled = NO; // XHS @0x9c2c setUserInteractionEnabled:NO——盘永不吃点击
    Class ccCls = NSClassFromString(@"UICornerConfiguration");
    if (ccCls && [v respondsToSelector:@selector(setCornerConfiguration:)] &&
        [ccCls respondsToSelector:@selector(capsuleConfiguration)]) {
        id cfg = ((id (*)(id, SEL))objc_msgSend)(ccCls, @selector(capsuleConfiguration));
        if (cfg) ((void (*)(id, SEL, id))objc_msgSend)(v, @selector(setCornerConfiguration:), cfg);
    }
    v.contentView.layer.masksToBounds = YES;
    return v;
}

// XHS plateOn 的 frame 语义：空 frame ⇒ 盘隐藏；非空 ⇒ 显示、frame 变了才 setFrame、
// contentView.layer.cornerRadius = 高/2 每轮重申。填充恒为零（不碰 contentView.backgroundColor）。
static void ZHSetPlateFrame(UIVisualEffectView *plate, CGRect f) {
    if (!plate) return;
    if (CGRectIsEmpty(f)) { plate.hidden = YES; return; }
    plate.hidden = NO;
    if (!CGRectEqualToRect(plate.frame, f)) plate.frame = f;
    CGFloat r = f.size.height / 2;
    if (plate.contentView.layer.cornerRadius != r) plate.contentView.layer.cornerRadius = r;
}

#pragma mark - 开关回调（单例 handler，静态 RETAIN）

@interface ZHPluginHandler : NSObject
- (void)zhPluginGlassSwitchChanged:(id)sender;
- (void)zhPluginBlackSwitchChanged:(id)sender;
- (void)zhPluginLongPress:(UILongPressGestureRecognizer *)g;
@end

static ZHPluginHandler *gHandler = nil;
static ZHPluginHandler *ZPHandler(void) {
    if (!gHandler) gHandler = [[ZHPluginHandler alloc] init];
    return gHandler;
}

static id gGlassCellInfo = nil;  // 设置页「玻璃底栏」行模型（静态 RETAIN，全程一份）
static id gBlackCellInfo = nil;  // 设置页「纯黑背景」行模型（静态 RETAIN，全程一份）
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
@end

#pragma mark - 布局（apply 幂等：开 -> 玻璃布局；关 -> 恢复原样）

static void ZHEnsurePlates(UIView *bar, UIView *stack) {
    UIVisualEffectView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    if (!capsule) {
        capsule = ZHMakePlate();
        [bar insertSubview:capsule belowSubview:stack];
        objc_setAssociatedObject(bar, &kCapsuleKey, capsule, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [capsule release];
    }
    UIVisualEffectView *lens = objc_getAssociatedObject(bar, &kLensKey);
    if (!lens) {
        lens = ZHMakePlate();
        [bar insertSubview:lens belowSubview:stack];
        objc_setAssociatedObject(bar, &kLensKey, lens, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [lens release];
    }
    // 层级（XHS plateOn 语义：盘是内容的同层兄弟、压在内容之下）：
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

// item 的内容并集（图标+标题）在 bar 坐标系中的矩形；取不到内容视图时回落 item 自身 frame
static CGRect ZHItemContentRect(UIView *bar, UIView *item) {
    CGRect u = CGRectNull;
    for (NSString *name in @[@"iconImageView", @"titleLable"]) {
        UIView *v = ZHGetObj(item, name);
        if (v && [v isKindOfClass:[UIView class]] && [v isDescendantOfView:bar]) {
            CGRect r = [bar convertRect:v.bounds fromView:v];
            if (r.size.width > 0 && r.size.height > 0)
                u = CGRectIsNull(u) ? r : CGRectUnion(u, r);
        }
    }
    if (CGRectIsNull(u)) u = [bar convertRect:item.bounds fromView:item];
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
    UIVisualEffectView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    UIVisualEffectView *lens = objc_getAssociatedObject(bar, &kLensKey);
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

    // 几何全部来自实测 frame（bar 坐标系）：横向认 item 槽位、纵向认图标+标题内容并集，
    // 选中序号以 item 的 themeSelected 为准（取不到回落 0）。
    CGRect slotU = CGRectNull;    // 可见 item 槽位并集（横向）
    CGRect contentU = CGRectNull; // 可见 item 内容并集（纵向）
    NSUInteger sel = NSNotFound;
    CGRect selSlot = CGRectNull;
    for (NSUInteger i = 0; i < items.count; i++) {
        UIView *it = items[i];
        CGRect slot = [bar convertRect:it.bounds fromView:it];
        slotU = CGRectIsNull(slotU) ? slot : CGRectUnion(slotU, slot);
        CGRect cr = ZHItemContentRect(bar, it);
        contentU = CGRectIsNull(contentU) ? cr : CGRectUnion(contentU, cr);
        if (sel == NSNotFound && ZHGetBool(it, @"themeSelected", NO)) { sel = i; selSlot = slot; }
    }
    if (sel == NSNotFound) {
        sel = 0;
        UIView *it = items[0];
        selSlot = [bar convertRect:it.bounds fromView:it];
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
    CGRect capRect = CGRectMake(capX, capY, capW, capH);
    ZHSetPlateFrame(capsule, capRect);

    // 透镜：锚定选中 item 本人——横向 = 其槽位左右各扩 4（XHS 主页透镜 = item 宽+16 同路数，
    // 此处取 +8 并夹在胶囊内），纵向在胶囊内居中、高 = 胶囊高 - 10；无填充玻璃盘。
    CGFloat lensH = capH - 10;
    if (lensH < 8) lensH = capH;
    CGFloat lensW = selSlot.size.width + 8;
    CGFloat lensX = CGRectGetMidX(selSlot) - lensW / 2;
    if (lensX < capX + 2) lensX = capX + 2;
    if (lensX + lensW > capX + capW - 2) lensX = capX + capW - 2 - lensW;
    CGRect lensRect = CGRectMake(lensX, capY + (capH - lensH) / 2, lensW, lensH);

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

#pragma mark - 设置页插行（锚点：contactsCellInfo 行模型对象本身，连插两行）

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
    NSUInteger glassIdx = NSNotFound, blackIdx = NSNotFound;
    for (NSUInteger i = 0; i < arr.count; i++) {
        id el = arr[i];
        if (![el respondsToSelector:@selector(title)]) continue;
        NSString *t = [el title];
        if ([t isEqualToString:@"玻璃底栏"]) glassIdx = i;
        else if ([t isEqualToString:@"纯黑背景"]) blackIdx = i;
    }
    if (glassIdx != NSNotFound && blackIdx != NSNotFound) { gSettingsDone = YES; return; }

    id glassInfo = ZPMakeSwitchInfo(infoCls, @"玻璃底栏", @"开启后，底部栏使用清透玻璃效果",
                                    ZHGlassEnabled(), YES, &gGlassBlock, &gGlassCellInfo);
    id blackInfo = ZPMakeSwitchInfo(infoCls, @"纯黑背景", @"开启后，夜间模式下背景使用纯黑",
                                    ZPBlackEnabled(), NO, &gBlackBlock, &gBlackCellInfo);
    if (!glassInfo || !blackInfo) { NSLog(@"[zhplugin] settings: factory returned nil"); return; }
    // 与锚点同 section 登记（照原生行的簿记方式）
    for (id info in @[glassInfo, blackInfo]) {
        if (section && [info respondsToSelector:@selector(addWeakSection:)])
            ((void (*)(id, SEL, id))objc_msgSend)(info, @selector(addWeakSection:), section);
    }

    // 目标顺序：[.., 玻璃底栏, 纯黑背景, contactsCellInfo(锚点), ..]
    NSMutableArray *work = [arr mutableCopy];
    if (glassIdx == NSNotFound && blackIdx == NSNotFound) {
        [work insertObject:blackInfo atIndex:anchorIdx];
        [work insertObject:glassInfo atIndex:anchorIdx];
    } else if (glassIdx == NSNotFound) { // 已有纯黑行（排在锚点上方），玻璃插到它前面
        [work insertObject:glassInfo atIndex:blackIdx];
    } else { // 已有玻璃行，纯黑插到锚点正上方（玻璃之下、锚点之上）
        NSUInteger ai = [work indexOfObjectIdenticalTo:anchor];
        if (ai != NSNotFound) [work insertObject:blackInfo atIndex:ai];
    }
    if ([arr isKindOfClass:[NSMutableArray class]]) {
        [(NSMutableArray *)arr removeAllObjects];
        [(NSMutableArray *)arr addObjectsFromArray:work];
    } else {
        ZHSetContainerValue(hit, work);
    }
    [work release];
    gSettingsDone = YES;
    NSLog(@"[zhplugin] settings: rows inserted above contacts at index %lu", (unsigned long)anchorIdx);

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
static BOOL gThemeHookInstalled = NO;
static BOOL gSettingsHookInstalled = NO;

// 段1：纯黑——主题发色点 hook（与底栏/设置两段解耦，互不拖累）
static void ZPInstallThemeHook(void) {
    if (gThemeHookInstalled) return;
    Class tmCls = NSClassFromString(@"ZHThemeManage");
    if (!tmCls) { NSLog(@"[zhplugin] install segment theme: ZHThemeManage missing, skip"); return; }
    gOrigColorWithModel = ZHSwapClassMethod(tmCls, @selector(colorWithModel:ignoreNight:),
                                            (IMP)ZP_Theme_colorWithModel);
    gThemeHookInstalled = (gOrigColorWithModel != NULL);
    // 注意：这里不再预先解析画布模型；改由取色 hook 首次命中时懒解析（见 ZPResolveCanvasModels）。
    NSLog(@"[zhplugin] install segment theme: colorHook=%p installed=%d", gOrigColorWithModel, gThemeHookInstalled);
    // 纯黑没生效的根因（本轮定案）：钩子在 didFinishLaunching+1s 才装上，而首页 feed 等
    // 首屏视图的画布色在启动建视图时早已取走存量 UIColor 对象——发色点只改「后续取色」，
    // 存量视图不会自己回头重取。故安装成功后立刻补发一次知乎自家主题通知三连（与开关
    // 切换同款），让已在屏页面按原渠道重取色；之后新建页面走钩子天然命中。
    if (gThemeHookInstalled && ZPBlackEnabled()) {
        ZPPostThemeRefresh();
        NSLog(@"[zhplugin] install segment theme: posted theme refresh for already-built views");
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
// +load 只登记启动完成通知：不在 +load 期装任何钩子、不碰任何 ZH 类、不解析画布模型。
// 教训（2026-11-26 对照实验定性）：旧版在 +load 里立即 ZPInstall 并在安装期触发
// ZHColorModel 的 +initialize/单例构造，此时宿主自身 +load 尚未跑完、UIApplication
// 未建，疑致启动即闪退（空插件对照版同法注入不退，已排除镜像检测与注入/签名问题）。
+ (void)load {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(zp_didFinishLaunching:)
                                                 name:UIApplicationDidFinishLaunchingNotification
                                               object:nil];
    NSLog(@"[zhplugin] load: observer registered, install deferred to didFinishLaunching + 1s");
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
