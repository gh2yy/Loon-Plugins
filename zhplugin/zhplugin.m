// zhplugin.m — 知乎 11.15.0 插件合集（2026-11-26）
// 同一个 dylib 两项功能，各有独立开关（设置页 contactsCellInfo 行正上方连插行）：
//   1) 玻璃探针·照抄配方版（本轮）：一只悬浮胶囊直挂 keyWindow 顶层，按
//      RECIPE_DIFF.md 第四节配方重做构造（ZPGlassView 子类吞 setEffect: +
//      空身入树 + applyEffect: 后装、停写盘本体 bg、维护改两家式幂等），
//      一只胶囊验真（自建底部导航仍待命、本轮不建；原底栏完全不动）
//   2) 纯黑背景：夜间模式下整体画布背景改纯黑 #000000（仿 WCBlack 路线，但走知乎主题发色点）
//
// 玻璃探针口径（2026-11-26 照抄配方版；全栏自建导航仍待命、本轮不建）：
//   v2 真机已定罪：两只胶囊（甲挂原栏父视图窗口锚定、乙直挂 keyWindow
//   ZHRootWindow）诊断全绿——effect 类名实测 UIGlassEffect 真身、类查找
//   全命中、窗口坐标分毫不差、bg 被外部写黑 2 次已被钉制压住、hidden=0/
//   alpha=1/style 钉住——却双双渲染为实心黑药丸（乙压在照片上纯黑零
//   折射）。构造、落位、层级、背景已全排除。其后逐行对照两家成功样本
//   （XHSNative / DYKiller）定案三条构造差异（RECIPE_DIFF.md），本轮同
//   批落地、一只胶囊验真：
//     ①停写盘本体 backgroundColor——两家对玻璃视图本体 bg 一指不碰；
//       我们独有的每轮写 nil 钉制是在和外部写入方反复抢同一属性。本
//       轮删 ZPCheckAndPinBg 的回写动作、只记录（ZPRecordBg）。
//     ②删每轮 bringSubviewToFront 与全量重申——维护改两家式幂等：
//       hidden 同步、位置核查（不在当前 keyWindow 才重插一次、已在位
//       永不重排）、frame 变更才写、contentView 圆角每轮重设、风格钉
//       住变更才写。
//     ③DYKiller 防线整套：ZPGlassView（UIVisualEffectView 子类）覆写
//       setEffect: 为空实现+计数（外部调用一律吞掉、只记次数与最近传
//       入类名）；真装走自有 applyEffect:（[super setEffect:] 直调父
//       类原实现、计数安装数）；视图 initWithFrame: 空身先入树，随后
//       才 applyEffect: 装入 UIGlassEffect Regular（interactive 装入
//       前在 effect 上设 YES，Regular 无 tint）。
//   胶囊规格：一只，keyWindow 顶层，frame {90,300,260,64} 窗口坐标；
//   不用容器（两家单元素均不用）；塑形仅创建时一次（本体 capsule
//   cornerConfiguration + contentView.layer masksToBounds +
//   cornerRadius=高/2）；装入前 overrideUserInterfaceStyle 钉知乎主题；
//   userInteractionEnabled=NO；玻璃开关同控显隐；触发链仍走
//   ZHRequestApply 下一拍 ZHApplyBar。
//   诊断新增三计数：setEffect: 外部调用次数 + 最近一次传入类名、
//   applyEffect: 安装次数、bg 外部写入次数（只记不钉，既有记录口径）；
//   UIAccessibility 三开关实读行保留。判读表见 PATCH_NOTES 照抄配方版
//   段。原栏仍完全不动。
//
// 纯黑背景口径（本轮静态定案，详见 PATCH_NOTES v3 段）：
//   知乎颜色总发色点是 ZHThemeManage（ZHCoreTheme）：
//     +colorWithName:ignoreNight: 先把名字经 performSelector 解析成 ZHColorModel 单例
//     （+[ZHColorModel Map<Name>]），再统一走 +colorWithModel:ignoreNight:；
//     后者内部按 +[ZHThemeManage isNightMode]（读 NSUserDefaults NIGHT_MODE_KEY）
//     在 model.colorLight / model.colorNight 间二选一返回。
//   故只 swizzle +colorWithModel:ignoreNight: 一个点即覆盖全部原生取色路径。
//   画布 token（ZHColorModel 全部令牌逐个反汇编其 builder 提取 light/night
//   色值；setter 桩经 selref 核实为 setColorLight:/setColorNight:，以 99A 已知
//   值校验通过）：夜值命中 #191B1F / #212429 的令牌全集（身份制命中集，9 个）：
//     MapUIFrame99A = #FFFFFF / #191B1F（主画布，与主文本 MapText02A 恰为反相，约 190 处引用）
//     GBK99A        = #FFFFFF / #191B1F（GB 新色板主画布孪生——feed 疑走此令牌）
//     MapUIFrame10A = #F8F8FA / #212429（二级/分组画布，约 150 处引用）
//     GBK10A        = #F8F8FA / #212429（10A 的 GB 孪生）
//     GBK09B = #EBECED / #212429、GBK12A = #F8F8FA / #212429、GBL10A = #F8F8FA / #212429
//     MapUIFrame08B = #C4C7CE / #212429、MapUIFrame09B = #EBECED / #212429
//       （08/09 边框族：旧版以「夜值同为 #212429、身份制避开误伤」为由排除；
//        本轮逐令牌反汇编核对后按夜值全集口径纳入，在此标注以便回溯）
//   命中规则（身份制，不是色值制）：夜间 && 开关开 && !ignoreNight && model 为
//     上述 9 令牌单例之一 → 返回纯黑。其余令牌一律不动（全表已枚举：卡片
//     MapUIFrame99C/GBK99C 夜 #282B30、MapUIFrame10C/GBK10C 夜 #000000、
//     文本/VIP/品牌色夜值均非此二值，不在集内）。旧版只认 99A/10A 时 feed 仍
//     #191B1F——feed 取色不走这两令牌，本轮扩集收口（GBK99A 为头号嫌疑）。
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

static char kCapsuleKey;   // 配方探针胶囊（ZPGlassView + UIGlassEffect，直挂 keyWindow 顶层）
static char kSchedKey;     // 已排队布局标记
static char kLayoutLockKey; // layoutSubviews 重入锁（per-instance）
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
static UIWindow *ZPProbeKeyWindow(void); // 前置声明，定义在布局节（探针落位先用）
static NSString *ZPBuildDiagnostics(void); // 前置声明，定义在设置页节（诊断行）
static NSString *ZPColorDesc(UIColor *c); // 前置声明，定义在诊断行节（bg 侦测记录先用）
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

// 画布令牌命中集（身份制）：夜值 == #191B1F / #212429 的 ZHColorModel 令牌
// 全集（逐个反汇编 builder 提取 light/night 定集，清单与色值见文件头纯黑段）。
// 懒解析 + 静态持有（MRC）：只在取色 hook 命中路径（ZPIsCanvasModel，且纯黑已开）
// 首次真正需要时经 dispatch_once 解析；安装路径绝不预先解析——安装期触发
// ZHColorModel 的 +initialize/单例构造曾疑致启动闪退（2026-11-26 对照实验定性）。
// 解析失败（类/方法不存在）则集合为空，纯黑静默不生效，不崩。
static NSMutableSet *gCanvasSet = nil; // 命中令牌单例集（alloc/init 静态持有）
static void ZPResolveCanvasModels(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cmCls = NSClassFromString(@"ZHColorModel");
        if (!cmCls) return;
        gCanvasSet = [[NSMutableSet alloc] init];
        NSArray *names = @[@"MapUIFrame99A", @"GBK99A",
                           @"MapUIFrame10A", @"GBK10A",
                           @"GBK09B", @"GBK12A", @"GBL10A",
                           @"MapUIFrame08B", @"MapUIFrame09B"];
        for (NSString *name in names) {
            SEL s = NSSelectorFromString(name);
            if ([cmCls respondsToSelector:s]) {
                id m = ((id (*)(id, SEL))objc_msgSend)(cmCls, s);
                if (m) [gCanvasSet addObject:m];
            }
        }
    });
}
static BOOL ZPIsCanvasModel(id model) {
    if (!model) return NO;
    ZPResolveCanvasModels();
    // 指针身份比对（不走 isEqual:，防令牌类重写相等语义时误判）
    for (id m in gCanvasSet) if (m == model) return YES;
    return NO;
}
// 诊断用：命中集已解析个数（未解析返回 -1；纯读取，不触发解析）
static NSInteger ZPCanvasResolvedCount(void) {
    return gCanvasSet ? (NSInteger)gCanvasSet.count : -1;
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

#pragma mark - 玻璃盘构造（照抄配方版：ZPGlassView 防线 + 空身入树 + applyEffect: 后装）

// 本轮（照抄配方版）：按 RECIPE_DIFF.md 第四节配方重做构造。核心三条
// 同批落地：①停写盘本体 bg（只记录、不回写，见 ZPRecordBg）；②维护改
// 两家式幂等（在布局节 ZHLayoutRecipeProbe）；③DYKiller 防线——
// ZPGlassView 子类吞 setEffect:、空身入树、applyEffect: 后装。承载与
// 落位在布局节。
//
// iOS 26 玻璃类全部运行时取类、无硬链接（构建 SDK 不含其头文件）：
// UIGlassEffect / UICornerConfiguration。
// 取类失败（<iOS 26）时工厂返回 nil，布局节据此静默不建探针。

static id ZHMakeGlassEffect(BOOL interactive) {
    Class cls = NSClassFromString(@"UIGlassEffect");
    if (!cls || ![cls respondsToSelector:@selector(effectWithStyle:)]) return nil;
    // UIGlassEffectStyle: Regular = 0（本轮只用 Regular，XHSNative/DYKiller 主口径）
    id fx = ((id (*)(id, SEL, long))objc_msgSend)(cls, @selector(effectWithStyle:), 0L);
    if (fx && interactive && [fx respondsToSelector:@selector(setInteractive:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(fx, @selector(setInteractive:), YES);
    return fx; // 工厂方法返回值按惯例 autorelease，MRC 下调用方在池内即用，安全
}

static id ZHCapsuleCornerConfiguration(void) {
    Class cls = NSClassFromString(@"UICornerConfiguration");
    if (!cls || ![cls respondsToSelector:@selector(capsuleConfiguration)]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, @selector(capsuleConfiguration));
}

// effect 通道三计数之一/之二（诊断取证，本轮新增）：
//   gSetEffectExtCount —— ZPGlassView 的 setEffect: 被外部调用的次数（覆写
//     吞掉并计数；applyEffect: 走 super 通道、不经覆写，不计入此数）。
//   gSetEffectLastClass —— 最近一次外部传入 effect 的类名（RETAIN；从未
//     发生时为 nil，诊断显示「-」）。
//   gApplyEffectCount —— applyEffect: 真正安装 effect 的次数。
static NSUInteger gSetEffectExtCount = 0;
static NSString *gSetEffectLastClass = nil; // RETAIN
static NSUInteger gApplyEffectCount = 0;

// ZPGlassView（DYKiller 的 DKChatGlassView 防线同构）：把公开的
// setEffect: 覆写成空实现——任何外部代码（宿主或 UIKit）给这只视图赋
// effect 都被吞掉并计数，effect 只能经自有 applyEffect: 安装。知乎进程
// 已实测存在对外来 effect view 的外部写入（bg 写黑），此类干扰非假想。
@interface ZPGlassView : UIVisualEffectView
- (void)applyEffect:(UIVisualEffect *)effect;
@end

@implementation ZPGlassView
- (void)setEffect:(UIVisualEffect *)effect {
    // 空实现 + 计数：不调 super、不写任何状态，只记下这次外部调用。
    gSetEffectExtCount++;
    NSString *cls = effect ? NSStringFromClass(object_getClass(effect)) : @"nil";
    if (![cls isEqualToString:gSetEffectLastClass]) {
        [gSetEffectLastClass release];
        gSetEffectLastClass = [cls retain];
    }
}
- (void)applyEffect:(UIVisualEffect *)effect {
    gApplyEffectCount++;
    // [super setEffect:] 由编译器生成 objc_msgSendSuper2 直调父类原实现
    // （DYKiller 手写 msgSendSuper2 达同一通道），绕开上面的吞噬覆写。
    [super setEffect:effect];
}
@end

// 配方胶囊工厂：只负责「取或建 + 空身创建 + 一次性塑形」，不入树、不装
// effect（入树与后装在布局节 ZHLayoutRecipeProbe 按配方次序完成）。
// 空身：initWithFrame: 创建、出生无 effect。塑形仅此一次：本体 capsule
// cornerConfiguration + contentView.layer masksToBounds + cornerRadius
// =高/2。无外壳、无 shadow、无任何装饰层。UIGlassEffect 类取不到
// （<iOS 26）返回 nil，布局节据此静默不建探针。
static ZPGlassView *ZHRecipeCapsuleForBar(UIView *bar) {
    ZPGlassView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    if (capsule) return capsule;
    if (!NSClassFromString(@"UIGlassEffect")) return nil;
    capsule = [[ZPGlassView alloc] initWithFrame:CGRectMake(90, 300, 260, 64)];
    capsule.userInteractionEnabled = NO; // 探针永不吃点击
    id cc = ZHCapsuleCornerConfiguration();
    if (cc && [capsule respondsToSelector:@selector(setCornerConfiguration:)])
        ((void (*)(id, SEL, id))objc_msgSend)(capsule, @selector(setCornerConfiguration:), cc);
    capsule.contentView.layer.masksToBounds = YES;
    capsule.contentView.layer.cornerRadius = capsule.frame.size.height / 2;
    objc_setAssociatedObject(bar, &kCapsuleKey, capsule, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [capsule release];
    return capsule;
}

// 风格钉住：overrideUserInterfaceStyle 钉知乎主题（ZPAppIsNight 口径——优先
// ZHThemeManage isNightMode，与发色点同源）。知乎主题与系统外观不一致时，
// 玻璃的明暗必须跟知乎走（DYKiller 对其 Regular 槽位 setOverrideUserInterfaceStyle:
// 同款动作）。ZHLayoutRecipeProbe 每轮都会调用，主题切换经既有 apply 路径自动同步；
// 先比对现值再写，保持幂等。
static void ZHGlassApplyTheme(UIView *v) {
    if (!v) return;
    UIUserInterfaceStyle want = ZPAppIsNight() ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    if (v.overrideUserInterfaceStyle != want) v.overrideUserInterfaceStyle = want;
}

// bg 写入侦测（核心取证）：探针 v1 起实证胶囊的 backgroundColor 被外部
// 写成 rgba(0,0,0,1)（本插件源码无任何对玻璃视图 backgroundColor 的赋
// 值，定性为外部写入）。旧版每轮读到非 nil 就写 nil 钉制——逐行对照定
// 案（RECIPE_DIFF 嫌疑 1）：两家成功样本对玻璃视图本体 bg 一指不碰，我
// 们独有的回写是在和写入方反复抢同一属性。本轮删回写、只记录：每轮观
// 察 bg，非 nil 且与上轮观察值不同（或上轮为 nil）才计数一次（同值持
// 续存在不重复计——不回写后同一次写入会一直留存，按轮计数必然虚增）；
// 观察到 nil 时清上轮标记，下一次非 nil 重新计数。首次值/末次值/累计
// 次数进诊断（计数口径为「观察到的相异写入」，与旧版按轮钉制计数不可
// 直接比大小，在此标注）。
static NSString *gBgCapFirst = nil, *gBgCapLast = nil; // 配方胶囊被写入记录（RETAIN）
static NSUInteger gBgCapCount = 0;
static NSString *gBgCapSeen = nil; // 上轮观察到的 bg 描述（RETAIN；nil=上轮为 nil 或未观察）
static void ZPRecordBg(UIView *v) {
    if (!v) return;
    UIColor *bg = v.backgroundColor;
    if (!bg) {
        if (gBgCapSeen) { [gBgCapSeen release]; gBgCapSeen = nil; }
        return;
    }
    NSString *d = ZPColorDesc(bg);
    if ([d isEqualToString:gBgCapSeen]) return; // 同值持续存在：同一次写入，不重复计
    [gBgCapSeen release];
    gBgCapSeen = [d retain];
    if (!gBgCapFirst) gBgCapFirst = [d retain];
    [gBgCapLast release];
    gBgCapLast = [d retain];
    gBgCapCount++;
    // 只记录，绝不回写 v.backgroundColor（配方第 1 条）
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

#pragma mark - 布局（照抄配方版：apply 幂等：开 -> 配方胶囊落位；关 -> 隐藏）

// 配方胶囊落位（每轮 apply 走一遍，全程两家式幂等——RECIPE_DIFF 嫌疑 2）：
//   位置核查——胶囊不在当前 keyWindow 才重插一次（addSubview 到窗口顶
//   层）；已在位永不重排（删旧版每轮 bringSubviewToFront）。
//   hidden 同步——开则置 NO（变更才写）。
//   frame——与目标 {90,300,260,64} 不同才写（窗口直挂，frame 即窗口坐标）。
//   圆角——contentView.layer.cornerRadius 每轮重设（XHS plateOn 每轮唯一
//   必写项；塑形其余部分只在创建时做一次，见 ZHRecipeCapsuleForBar）。
//   风格——ZHGlassApplyTheme 钉知乎主题（内含比对、变更才写）；装 effect
//   前必须先钉好（配方次序），故排在后装之前。
//   bg——ZPRecordBg 只记录、不回写（配方第 1 条）。
//   effect 后装——胶囊已入树且 effect 尚为空时，才建 fx（Regular、
//   interactive 装入前在 effect 上设 YES、无 tint）经 applyEffect: 装入
//   一次；已装则永不重赋（DYKiller 只在参数真变时重建）。
// 原栏本身完全不动——不隐藏、不清场、不改背景。窗口未就绪时本轮不施工
// （不入树、不隐藏），等下一轮触发。
static void ZHLayoutRecipeProbe(UIView *bar) {
    ZHRegisterBar(bar);
    ZPGlassView *capsule = ZHRecipeCapsuleForBar(bar);
    if (!capsule) return; // 玻璃类不可用：静默不建探针
    UIWindow *win = ZPProbeKeyWindow();
    if (!win) return;
    if (capsule.superview != win) [win addSubview:capsule]; // 只插一次、永不重排
    if (capsule.hidden) capsule.hidden = NO;
    CGRect target = CGRectMake(90, 300, 260, 64);
    if (!CGRectEqualToRect(capsule.frame, target)) capsule.frame = target;
    capsule.contentView.layer.cornerRadius = target.size.height / 2; // 每轮重设（XHS 口径）
    ZHGlassApplyTheme(capsule);
    ZPRecordBg(capsule);
    if (!capsule.effect) {
        id fx = ZHMakeGlassEffect(YES);
        if (fx) [capsule applyEffect:fx];
    }
}

// 玻璃关：只隐藏胶囊（视图留树上、effect 不卸，下次开直接恢复显形）
static void ZHHideRecipeProbe(UIView *bar) {
    UIView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    if (capsule) capsule.hidden = YES;
}

// keyWindow 选取（与 ZPAppIsNight 同口径：windows 里找 isKeyWindow，回落第一只）
static UIWindow *ZPProbeKeyWindow(void) {
    for (UIWindow *w in [UIApplication sharedApplication].windows)
        if (w.isKeyWindow) return w;
    return [UIApplication sharedApplication].windows.firstObject;
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
    if (ZHGlassEnabled()) ZHLayoutRecipeProbe(bar);
    else ZHHideRecipeProbe(bar);
}

static void ZHRequestApply(UIView *bar) {
    if (objc_getAssociatedObject(bar, &kSchedKey)) return;
    objc_setAssociatedObject(bar, &kSchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(bar, &kSchedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([bar isKindOfClass:NSClassFromString(@"ZHTabBarNew")]) ZHApplyBar(bar);
    });
}

// 触发链统一走 ZHRequestApply 的下一拍 apply：底栏各 hook（setupUI/
// layoutItems/setItems/select/unselect/主题/layout/didMoveToWindow）只排队不
// 施工；每轮 apply 按配方幂等清单维护探针（位置核查/frame/圆角/风格/bg
// 只记录）——页面切换/主题切换/选中变化都会带来新一轮侦测样本。

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

// 子树全量遍历：列出 v 的全部子视图（含系统内部子视图，如材质/玻璃的
// 背板 _UIVisualEffectBackdropView——不只 contentView 分支），并附每视图
// 的 layer 类（背板视图的 layer 应为 CABackdropLayer，是「背板在不在」的
// 关键数据）。深度上限 8（自承载起算）。
static void ZPDiagWalk(UIView *v, NSMutableString *out, int depth) {
    if (depth > 8) return; // 玻璃改容器结构后子树变深（容器→contentView→盘→contentView），上限提到 8
    NSMutableString *indent = [NSMutableString string];
    for (int i = 0; i < depth; i++) [indent appendString:@"  "];
    [out appendFormat:@"%@%@ frame=%@ bg=%@ hidden=%d alpha=%.2f style=%ld layer=%@\n",
         indent, NSStringFromClass(object_getClass(v)), NSStringFromCGRect(v.frame),
         ZPColorDesc(v.backgroundColor), (int)v.hidden, v.alpha,
         (long)v.overrideUserInterfaceStyle, NSStringFromClass(object_getClass(v.layer))];
    for (UIView *s in v.subviews) ZPDiagWalk(s, out, depth + 1);
}

// effect 对象类名（运行时读 UIVisualEffectView.effect 的真实类；effect 为
// nil 时 effect view 全透明——v1 诊断缺此项，本轮列为决战项之一）
static NSString *ZPEffectClassName(UIVisualEffectView *v) {
    if (!v) return @"(无视图)";
    UIVisualEffect *fx = v.effect;
    if (!fx) return @"nil";
    return NSStringFromClass(object_getClass(fx));
}

// superview 类名链（自 v 起向上 3 级，近→远；不足 3 级有几级报几级）
static NSString *ZPSuperviewChain(UIView *v) {
    NSMutableArray *parts = [NSMutableArray array];
    UIView *cur = v ? v.superview : nil;
    for (int i = 0; i < 3 && cur; i++) {
        [parts addObject:NSStringFromClass(object_getClass(cur))];
        cur = cur.superview;
    }
    return parts.count ? [parts componentsJoinedByString:@" < "] : @"(无父视图)";
}

// 配方胶囊的诊断块：胶囊本值 frame + 窗口 frame 实测
// （convertRect:toView:nil）、superview 类名链、window 是否非空、effect
// 对象类名、本轮新增三计数（setEffect: 外部调用次数 + 最近传入类名 /
// applyEffect: 安装次数）、bg 写入记录（只记不钉）、完整子树（全部子
// 视图含系统内部背板，见 ZPDiagWalk）。承载即胶囊本人（无容器）。
static void ZPAppendRecipeDiag(NSMutableString *s, UIView *bar) {
    ZPGlassView *capsule = objc_getAssociatedObject(bar, &kCapsuleKey);
    [s appendString:@"配方胶囊（keyWindow 直挂·裸玻璃·ZPGlassView 防线）:\n"];
    if (!capsule) {
        [s appendString:@"  胶囊: 未创建（玻璃类不可用或尚未落位）\n"];
        return;
    }
    [s appendFormat:@"  胶囊 frame(本值)=%@ 窗口frame(实测)=%@ hidden=%d 容器=无（裸盘）\n",
         NSStringFromCGRect(capsule.frame),
         NSStringFromCGRect([capsule convertRect:capsule.bounds toView:nil]),
         (int)capsule.hidden];
    [s appendFormat:@"  承载 frame(本值)=%@ 窗口frame(实测)=%@ superview链=%@ window=%@\n",
         NSStringFromCGRect(capsule.frame),
         NSStringFromCGRect([capsule convertRect:capsule.bounds toView:nil]),
         ZPSuperviewChain(capsule), capsule.window ? @"非空" : @"nil"];
    [s appendFormat:@"  effect类名 胶囊=%@\n", ZPEffectClassName(capsule)];
    [s appendFormat:@"  effect通道计数 setEffect外部调用=%lu 最近传入=%@ applyEffect安装=%lu\n",
         (unsigned long)gSetEffectExtCount, gSetEffectLastClass ?: @"-",
         (unsigned long)gApplyEffectCount];
    [s appendFormat:@"  bg 写入记录 胶囊: 次数=%lu 首次=%@ 末次=%@（只记不钉）\n",
         (unsigned long)gBgCapCount, gBgCapFirst ?: @"-", gBgCapLast ?: @"-"];
    [s appendString:@"  配方胶囊子树（胶囊起）:\n"];
    ZPDiagWalk(capsule, s, 1);
}

// 诊断文本（照抄配方版）：知乎主题值 / 系统 trait / 颜色钩已装 / 纯黑命中集
// 解析数 / 原栏 hidden 状态（本插件不写此值）/ 三玻璃类 NSClassFromString
// 命中布尔 / UIAccessibility 三开关运行时实读 / 配方胶囊探针块（见
// ZPAppendRecipeDiag，含三计数与完整子树）。
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
    [s appendFormat:@"纯黑命中集: 已解析 %ld 个令牌（静态枚举全集 9）\n",
         (long)ZPCanvasResolvedCount()];
    [s appendFormat:@"原栏 hidden=%d（照抄配方版：原栏完全不动，本插件不写此值）\n", (int)bar.hidden];
    [s appendFormat:@"玻璃类命中 UIGlassEffect=%@ UIGlassContainerEffect=%@ UICornerConfiguration=%@\n",
         NSClassFromString(@"UIGlassEffect") ? @"YES" : @"NO",
         NSClassFromString(@"UIGlassContainerEffect") ? @"YES" : @"NO",
         NSClassFromString(@"UICornerConfiguration") ? @"YES" : @"NO"];
    // 辅助功能三开关运行时实读（UIAccessibility 公开 API）：任一为 YES 都会在
    // 系统层改写玻璃/材质的渲染（降低透明度让玻璃变厚重不透明、增强对比把
    // 元素推向黑白、色彩反转翻转合成结果），判读探针显形前必须先看这一行。
    [s appendFormat:@"辅助功能实读 降低透明度=%@ 增强对比=%@ 色彩反转=%@\n",
         UIAccessibilityIsReduceTransparencyEnabled() ? @"YES" : @"NO",
         UIAccessibilityDarkerSystemColorsEnabled() ? @"YES" : @"NO",
         UIAccessibilityIsInvertColorsEnabled() ? @"YES" : @"NO"];
    ZPAppendRecipeDiag(s, bar);
    if (!gBgCapCount)
        [s appendString:@"bg 写入记录: 未观察到非 nil 写入\n"];

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

    id glassInfo = ZPMakeSwitchInfo(infoCls, @"玻璃底栏", @"开启后，显示一只配方探针胶囊",
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
