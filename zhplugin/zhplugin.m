// zhplugin.m — 知乎 11.15.0 插件合集（2026-11-26）
// 同一个 dylib 两项功能，各有独立开关（设置页 contactsCellInfo 行正上方连插行）：
//   1) 液态玻璃底部导航（正式版）：探针已验真（总闸 = 宿主
//      UIDesignRequiresCompatibility，删键的 A/B 包真机实测胶囊成
//      真玻璃），本轮探针整段退场、换正式导航：原栏 ZHTabBarNew
//      摘除保留，插件在窗口底部自建悬浮玻璃胶囊导航，只留首页/我的两
//      入口——玻璃面沿用 SJJ 全序列（ZPGlassView 旗标门控 +
//      zpUpdateMaterial: 公开通道自装、空身入树、host 容器 index 0
//      垫底、样式先钉），按钮数据从原栏 item 抄（图标/头像/标题/
//      字体/色值），点击回原栏真实点选链 didClickTabBarItem:，选
//      中透镜由既有 select/unselect 钩子驱动滑动。玻璃关时还原原
//      栏、移除自建栏。
//   2) 纯黑背景：夜间模式下整体画布背景改纯黑 #000000（仿 WCBlack 路线，但走知乎主题发色点）
//
// 玻璃导航口径（正式版，2026-11-26 晚）：
//   已定案前提（勿再验证）：知乎玻璃不渲染的总闸是宿主 Info.plist
//   的 UIDesignRequiresCompatibility（App 级 UI 兼容模式）——只删
//   此键的 A/B 包真机实测：同一只 SJJ 序列胶囊立即成真玻璃、折射
//   身后内容。构造（SJJ 全序列）与成品 SDK 戳修正（27.2）均保留。
//   导航形态（用户 2026-11-26 16:09 拍板）：原栏整体隐藏、插件自
//   建一套液态玻璃底部导航，只保留首页/我的两入口（照虎扑
//   HPGlassBar v5 模式：按钮数据复制 + 几何全自定 + 点击回原链）。
//     ①原栏：玻璃开 → 出生钩在入窗同一轮摘除（removeFromSuperview）
//       并由插件强引用保留作数据源（v3.3）；玻璃关 → 按记录的原父
//       视图/位次放回、hidden=NO，并把自建栏移出窗口。
//     ②自建栏：透明 host 容器挂当前 keyWindow，底部居中贴底（底
//       边距屏幕底部 8pt，v3.2 起，参照微博悬浮栏），尺寸由两槽
//       决定：槽宽 86、栏高 58、两侧内边距 10 → 192×58。host 子
//       视图序：玻璃容器（index 0）
//       → 两按钮；容器 = UIVisualEffectView + UIGlassContainer-
//       Effect（spacing 2.0，v3.1 起），其 contentView 内依次是
//       玻璃面 → 选中透镜（容器类取不到时回落玻璃面/透镜直挂
//       host 的旧形态）。玻璃面/透镜均为 ZPGlassView（SJJ 序
//       列：空身入树、先钉 overrideUserInterfaceStyle 跟知乎夜间
//       模式、Regular、无 tint、zpUpdateMaterial: 装入）。
//     ③按钮数据：从原栏可见 item 视图抄——首页取 iconImageView
//       的图与 titleLable 的文/字体/色；我的优先 avatarImageView
//       的头像图（圆形）。槽位按 model.identifier 定（0=首页、
//       5=我的，取不到回落可见序首/尾）。每轮维护同步当前图与色
//       （原栏选中态/主题变化后图色随之变，两态图标自动跟随）。
//     ④点击：回原栏真实点选链——静态实证 itemControlClick 的链
//       是 [item.delegate didClickTabBarItem:item.model]，delegate
//       即原栏本人；自建按钮点击同调 [bar didClickTabBarItem:model]
//       （登录拦截、delegate 切换、model selected 更新全在原链内）。
//     ⑤选中与透镜：选中态读 item 的 themeSelected；既有 select/
//       unselect/setItems/主题/layout 钩子触发下一拍维护，透镜
//       滑到选中槽，按钮选中态同步。维护幂等：hidden 同步
//       / frame 变更才写 / 已在位不重排 / effect 为 nil 才装。
//   v3.1（真机反馈两修）：①冷启直达——建成前 apply 若发现 item
//     未就绪，不再干等事件：以 0.1s 一拍、最长约 3s 快重试（外加
//     安装后一只启动清扫链在窗口树里找栏），item 视图一就绪立即
//     建栏、按原栏当前选中态无动画落位透镜、隐藏原栏；按钮内容
//     （头像等异步资源）仍每轮同步补齐、不作建栏前置。点选钩子
//     只负责建成后的切换。②动效弹性——玻璃面与透镜同入一只
//     UIGlassContainerEffect（spacing 2.0）聚合：透镜位移只由弹
//     簧（0.5s / damping 0.75）驱动 center，移动中的形变由容器
//     morph 承担（灵动来自系统能力本身，不在玻璃视图上叠手工
//     拉伸 transform），以「目标槽位」记忆防维护轮次反复重启弹
//     簧；两 effect 保持 interactive=YES；按钮按压时图标缩
//     0.9、松开弹簧回弹，用户点选驱动的选中切换时图标做一次
//     1.15 弹簧弹跳（冷启首落位不弹；图标是普通 UIImageView、
//     不进玻璃合成，与容器形变不冲突）。
//   v3.2（真机反馈三修）：①冷启闪原栏——v3.1 是「数据就绪才隐
//     藏原栏」，就绪前原栏先露 1–2 秒再被换掉；改原栏出生即藏：
//     didMoveToWindow 钩子在栏入窗同一轮（首帧绘制前）就置
//     hidden=YES（ZHNavPreHideBar，记 kNavPreHideKey 认领这次隐
//     藏），apply 首触与启动清扫发现栏时同口径补藏；建栏流程不
//     变（数据就绪才建）；兜底——重试窗口（约 3s）内始终没建成
//     则在重试链到顶时恢复 hidden=NO，绝不让用户无栏可用（知乎
//     自己藏的栏不认领、不恢复）。②弹簧动效消失——审计定案见
//     PATCH_NOTES v3.2：透镜几何收敛为单一写者 ZHNavDriveLens
//     （首落位/弹簧/空闲校正全经它），在途标记 kNavLensAnimKey
//     期间维护轮次零触碰透镜几何，动画 completion 清标记并补排
//     一轮核对；空闲轮次发现 frame 与目标偏差 >0.5pt 才直写校
//     正（自愈）。弹簧改回写 frame（与 v3.0 已验可见的写形一
//     致），容器 morph 保留。③栏太高太浮——栏高 64→54（透镜内
//     缩 (6,6) → 74×42、按钮图标框 24pt、排布收紧），底边距由
//     「安全区底+12」改贴底：胶囊底边距屏幕底部 8pt（参照微博
//     悬浮栏：高约 52、底边几乎贴着小横条上方）。
//   v3.3（真机反馈两修 + 方向修正）：①冷启仍见切换过程——两个时
//     机缺口：藏栏出生钩装在 +1s 延迟段、原栏启动早期已出生扑空；
//     胶囊又要等 item 数据全齐才肯建、中间空窗。用户拍板方向修
//     正：不再「藏」原栏——出生钩提前到 +load 期装（只此一只钩
//     子，其余底栏段仍延迟），钩子在入窗同一轮直接摘除原栏并由
//     插件强引用保留作数据源、记其原父视图与子视图位次；删认领
//     旗与「3 秒未建成自动还原」兜底（不再复活原栏）；知乎重建
//     新原栏实例时出生钩同口径摘除并换保留引用。玻璃关时按记录
//     放回并 hidden=NO、自建栏移出，开关语义完整。②胶囊先到位：
//     原栏一被发现即建并显示胶囊（几何现行规格），槽位以
//     identifier 0/5 双双命中为「识别」；未识别先按可见序占位映
//     射、按钮禁用（userInteractionEnabled=NO），识别完成即启用，
//     数据后续每轮同步补齐/纠正；重试到顶仍无 item 就留空槽胶囊
//     在位、不复活原栏。③栏高 54→58（透镜内缩 (6,6) → 74×46、按
//     钮图标 y 6→8 / 标题 y 33→37）。
//   v3.4（真机反馈单修）：栏高 58→62（58 版仍觉不够、用户拍板直
//     接推到 62）。透镜内缩 (6,6) 不变 → 74×50、按钮图标 y 8→10 /
//     标题 y 37→41；总宽 192、槽宽 86、底边距 8 不变，自建栏
//     frame y = 956−8−62 = 886。其余逐字未动。
//   v3.5（真机反馈单修）：栏高 62→72（62 版仍觉不够、再往上调
//     10）。透镜内缩 (6,6) 不变 → 74×60、按钮图标 y 10→15 /
//     标题 y 41→46；总宽 192、槽宽 86、底边距 8 不变，自建栏
//     frame y = 956−8−72 = 876。其余逐字未动。
//   v3.6（口径纠正版）：用户所指「高度」实为整栏距屏幕底部的
//     距离、非栏高——v3.4/v3.5 两版误读只涨栏高。本版定案：栏高
//     回到 62（透镜内缩 (6,6) → 74×50、按钮图标 y 15→10 / 标题
//     y 46→41，即 v3.4 排布），底边距 8→15（整栏上抬 7）；总宽
//     192、槽宽 86 不变，自建栏 frame y = 956−15−62 = 879。
//     其余逐字未动。
//   v3.7（真机反馈单修）：底边距 15→23（整栏再往上抬 8）。栏高
//     62、透镜 74×50、按钮排布全不变，自建栏 frame y =
//     956−23−62 = 871。其余逐字未动。
//   v3.8（真机反馈单修）：按钮内图标与文字间隔 7→3（微博式收
//     紧排布）：图标 y 10→11、标题 y 41→38，整组在 62 高内垂直
//     居中（上下边距同为 11）。栏高、底边距 23、透镜全不变。
//     其余逐字未动。
//   v3.9（修已知边界：二级页自建栏不消失、压住答案页自带底
//     栏）：知乎原栏显隐信号静态定案——总漏斗是控制器
//     ZHInitialTabBarController 的 -showTabBar:animated:（反汇
//     编实证：navigationController:willShow:animated: 里
//     needHideTabBar: 命中即 showTabBar:NO animated:YES；
//     showTabBar: 内先 [tabBar setHidden:!show] 再
//     setIsTabBarShown:，随后 animate 块调
//     updateTabBarShownState 切 tabbarHiddenConstraint——约束
//     只管内容区停靠，栏本体的显隐就是 setHidden:）。原栏被摘
//     除不在层级内，但控制器对它的 setHidden: 照常发（方法调
//     用与在不在树无关）。故给 ZHTabBarNew 加 setHidden: 覆盖
//     （class_addMethod，super 钉父类链 IMP，同 layoutSubviews
//     铁律）：记录跟随状态（值/来源/计数），玻璃开时同轮把自
//     建 host 的 hidden 对齐（host 隐藏即不显形、也不吃触摸），
//     并排一轮 apply 对账；ZHLayoutGlassNav 每轮再以原栏当前
//     hidden 实值对账 host.hidden（实值为准、自愈任何漏记）。
//     转场不另做动画：知乎对原栏本体也是即时置 hidden（动画
//     只在内容区约束上），同轮对齐即同语义。几何与形态全保
//     v3.8 定档（栏 192×62、底边距 23、透镜 74×50、间距 3）。
//   诊断「玻璃导航」块：自建栏 frame、玻璃子树全量（背板在不
//   在）、原栏 hidden、当前选中项、effect 通道计数与 bg 写入记
//   录（保留探针时代的取证字段）。
//   v3.10（去掉压在导航栏区域的浮动推广横幅）：用户 2026-11-27
//     07:56 截图实证——首页底部一条蓝色浮动推广横幅（文案「是
//     我！我想给…一个见面礼」，服务端下发）原浮在原栏上方，原
//     栏摘除后掉到屏幕底部与自建胶囊重叠打架。用户拍板遍历普
//     查、同类全去。静态普查定案（详见 PATCH_NOTES v3.10 段）：
//     这类横幅是「应用内推广通知」（InAppNotification /
//     PromoReach）一家——服务端下发 icon+文案+链接，经请求漏斗
//     取回后以独立窗口贴底展示：
//       · 请求漏斗：ZHFloatNoticeManager 的 getFloatNotice… 四
//         方法（ObjC 侧，+shareManager 单例）；
//       · 模块漏斗：ZHInAppNotificationModuleAPI 的
//         getFloatNoticeView… 三方法 + showFloatNoticeView… 一
//         方法（模块系统按名调用，故二进制内无直接 xref）；
//       · 展示漏斗：ZHFloatNoticeView（UIWindow 子类，
//         +noticeView 以应用窗口 bounds+状态栏高建窗、
//         setWindowLevel:，show/showUpAnimation 贴底升起，
//         shouldDownToUpAnimate/swipeDown: 均证贴底）与 Swift
//         FloatNoticeView / FloatNewNoticeView（同模块新实现，
//         父类 ZHPromoWindow 亦 UIWindow，bindWithTitle:icon:
//         nightIcon:content:buttonText: + show）。
//     拦法（新段4，ZPInstall 内独立安装、与玻璃开关无关、常开）：
//     上述请求/模块方法一律换成空转实现（不调原实现、不触发完
//     成回调——回调不来即无物可展示、无状态待清理），三只窗口
//     的 show/makeKeyAndVisible/makeVisible 换成空转 + 顺手
//     hidden=YES。同轮生效、无巡逻。每次拦截按「类 名」计数，
//     诊断尾部新增「横幅拦截」块（各类计数 + 合计）供核对覆盖
//     面。不动：ZHPromoWindow 基类本身（其另一子类是等级引导
//     弹窗 LevelGuideAlertView，不属横幅）、二级页自带底栏、页
//     内 inline 推广卡、居中弹窗、功能性小窗（音频/视频 PiP）。
//
//// 纯黑背景口径（本轮静态定案，详见 PATCH_NOTES v3 段）：
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
#import <dlfcn.h>
#import <execinfo.h>

static char kNavHostKey;   // 自建导航容器（透明 UIView，挂 keyWindow）
static char kNavGlassKey;  // 导航玻璃面（ZPGlassView，垫在容器内 index 0）
static char kNavLensKey;   // 选中透镜（ZPGlassView，玻璃面之上、按钮之下）
static char kNavBtnHomeKey; // 首页按钮（ZPNavButton）
static char kNavBtnMineKey; // 我的按钮（ZPNavButton）
static char kNavSelKey;    // 最近一次选中槽位（NSNumber，透镜落位兜底）
static char kNavPlacedKey; // 透镜已落位过（首次落位不做滑动动画）
static char kNavContainerKey; // 玻璃容器（UIVisualEffectView + UIGlassContainerEffect，聚合玻璃面+透镜）
static char kNavLensSlotKey;  // 透镜当前/正在滑向的槽位（NSNumber，防维护轮次反复重启弹簧）
static char kNavRetryKey;     // 冷启直达重试计数（NSNumber，0.1s 一拍、上限 30 ≈ 3s）
static char kNavRetryPendKey; // 冷启直达重试在途标记（防并行重试链）
static char kNavOrigParentKey; // 被摘原栏的原父视图（RETAIN，v3.3：关玻璃时按记录放回）
static char kNavOrigIndexKey;  // 被摘原栏在原父视图中的子视图位次（NSNumber，v3.3）
static char kNavIdentifiedKey; // 槽位已确切识别（identifier 0/5 双中，v3.3：此前按钮禁用、胶囊占位）
static char kNavLensAnimKey;  // 透镜弹簧在途标记（v3.2：单写者纪律，置位期间维护不碰透镜几何）
static char kNavFollowKey;    // 跟随状态：知乎最近一次要求原栏隐藏与否（NSNumber BOOL，v3.9）
static char kNavFollowSrcKey; // 最近一次跟随信号来源（NSString，v3.9，诊断用）
static char kNavFollowCntKey; // 跟随信号计数（NSNumber，v3.9，诊断用）
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
static void ZHNavDetachBar(UIView *bar); // 前置声明，定义在布局节（出生钩摘除原栏用）
static BOOL ZHNavIsBuilt(UIView *bar); // 前置声明，定义在布局节（安装段启动清扫用）
static void ZHNavKickRetry(UIView *bar); // 前置声明，定义在布局节（安装段启动清扫用）
static UIWindow *ZPKeyWindow(void); // 前置声明，定义在布局节（导航落位用）
static NSString *ZPBuildDiagnostics(void); // 前置声明，定义在设置页节（诊断行）
static void ZPAppendBannerDiag(NSMutableString *s); // 前置声明，定义在横幅拦截节（v3.10）
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

#pragma mark - 玻璃构造（SJJ 全序列：旗标门控 + 公开通道自装 + host 层级内垫底）

// 按 SAMPLE41_ANALYSIS.md 的 SJJChatGlassStore 全序列构造（A/B 包
// 真机验真通过）：①安装路径——不用「吞噬 setEffect: + applyEffect:
// 绕行 super」，用 SJJ 的旗标门控：setEffect: 在旗标开时就是真通
// 道，安装统一经 zpUpdateMaterial:（置旗→公开通道自装→清旗）+ 变
// 更门控；②挂载形态——玻璃长在自建透明 host 内部 index 0（层级
// 内部，三家样本的共同形态），不直挂窗口当浮岛。外加 bg 写入方
// 身份捕获（ZPGlassView 覆写 setBackgroundColor: 记调用方，诊断
// 保留）。承载与落位在布局节。
//
// iOS 26 玻璃类全部运行时取类、无硬链接（构建 SDK 不含其头文件）：
// UIGlassEffect / UICornerConfiguration。
// 取类失败（<iOS 26）时工厂返回 nil，布局节据此静默不建导航。

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

// effect 通道计数（诊断取证）：
//   gSetEffectExtCount —— ZPGlassView 的 setEffect: 在旗标关时被外部调
//     用的次数（吞掉并计数；zpUpdateMaterial: 置旗后自装走放行支路、
//     不计入此数）。
//   gSetEffectLastClass —— 最近一次外部传入 effect 的类名（RETAIN；从
//     未发生时为 nil，诊断显示「-」）。
//   gZPInstallCount —— zpUpdateMaterial: 真正装入 effect 的次数（变更
//     门控跳过的调用不计）。
static NSUInteger gSetEffectExtCount = 0;
static NSString *gSetEffectLastClass = nil; // RETAIN
static NSUInteger gZPInstallCount = 0;

// bg 写入方捕获（诊断取证，本轮第二使命）：ZPGlassView 覆写
// setBackgroundColor: 时，除值外再记调用方——返回地址经 dladdr 解析
// 所属镜像名与镜像内偏移（主程序报 osee2unifiedRelease+0x…、系统库
// 报库名），至多留前 4 次详细记录。记录函数 ZPRecordBgWrite 定义在
// 本节下方（bg 捕获段），此处先声明。
static void ZPRecordBgWrite(UIColor *color, void *retAddr);

// 取一只 effect 的 style（UIGlassEffect 的 style 属性，运行时读；非
// 玻璃 effect 或读不到返回 -1）——zpUpdateMaterial: 变更门控用。
static long ZPEffectStyle(id fx) {
    if (!fx) return -1;
    Class glassCls = NSClassFromString(@"UIGlassEffect");
    if (!glassCls || ![fx isKindOfClass:glassCls]) return -1;
    if (![fx respondsToSelector:@selector(style)]) return -1;
    return ((long (*)(id, SEL))objc_msgSend)(fx, @selector(style));
}

// ZPGlassView（SJJ 的 SJJChatGlassView 同构）：setEffect: 旗标门控——
// 实例旗标 zpInstalling 为 NO 时，外部赋值一律吞掉并计数；为 YES 时
// 走 [super setEffect:] 放行。安装统一经 zpUpdateMaterial:（置旗→经
// 公开的 setEffect: 通道自装→清旗），与 DYKiller 的「吞噬 + 自有
// applyEffect: 绕行 super」是两条不同的安装路径，本轮换 SJJ 的。
// 另覆写 setBackgroundColor: 做 bg 写入方捕获（先记再放行，只记不钉）。
@interface ZPGlassView : UIVisualEffectView {
    BOOL _zpInstalling;
}
- (void)zpUpdateMaterial:(UIVisualEffect *)effect;
@end

@implementation ZPGlassView
- (void)setEffect:(UIVisualEffect *)effect {
    if (!_zpInstalling) {
        // 旗标关：外部调用——吞掉并计数，不调 super、不写任何状态。
        gSetEffectExtCount++;
        NSString *cls = effect ? NSStringFromClass(object_getClass(effect)) : @"nil";
        if (![cls isEqualToString:gSetEffectLastClass]) {
            [gSetEffectLastClass release];
            gSetEffectLastClass = [cls retain];
        }
        return;
    }
    // 旗标开：引擎自装（zpUpdateMaterial: 内），放行父类真装。
    [super setEffect:effect];
}
- (void)zpUpdateMaterial:(UIVisualEffect *)effect {
    // 变更门控（SJJ configureSlot 同款）：目标与现 effect 同为
    // UIGlassEffect 且 style 一致 → 不重装；两者皆 nil → 无事可做；
    // 现 effect 为 nil 而目标非 nil（或 style 真变）→ 真装并计数。
    UIVisualEffect *cur = self.effect;
    if (effect && cur) {
        long wantStyle = ZPEffectStyle(effect);
        long curStyle = ZPEffectStyle(cur);
        if (wantStyle >= 0 && wantStyle == curStyle) return;
    }
    if (!effect && !cur) return;
    _zpInstalling = YES;
    [self setEffect:effect];
    _zpInstalling = NO;
    gZPInstallCount++;
}
- (void)setBackgroundColor:(UIColor *)color {
    // 写入方捕获：先记（值 + 调用方返回地址），再放行写入本身
    // （只记不钉——不回写、不拦截，写入照常落到视图上）。
    ZPRecordBgWrite(color, __builtin_return_address(0));
    [super setBackgroundColor:color];
}
@end

// 玻璃视图工厂（导航玻璃面/透镜共用）：只负责「空身创建 + 一次性
// 塑形」，不入树、不装 effect（入树与后装在布局节按 SJJ 次序完
// 成）。空身：initWithFrame: 创建、出生无 effect。塑形仅此一次：
// 本体 capsule cornerConfiguration + contentView.layer
// masksToBounds + cornerRadius=高/2。无外壳、无 shadow、无任何装
// 饰层。UIGlassEffect 类取不到（<iOS 26）返回 nil，布局节据此静
// 默不建导航。
static ZPGlassView *ZHMakeNavGlassView(CGRect frame) {
    if (!NSClassFromString(@"UIGlassEffect")) return nil;
    ZPGlassView *v = [[ZPGlassView alloc] initWithFrame:frame];
    v.userInteractionEnabled = NO; // 玻璃层永不吃点击（点击归按钮）
    id cc = ZHCapsuleCornerConfiguration();
    if (cc && [v respondsToSelector:@selector(setCornerConfiguration:)])
        ((void (*)(id, SEL, id))objc_msgSend)(v, @selector(setCornerConfiguration:), cc);
    v.contentView.layer.masksToBounds = YES;
    v.contentView.layer.cornerRadius = frame.size.height / 2;
    return v; // +1，调用方转交 associated 持有后 release
}

// 点选弹跳门控（v3.1）：用户经自建按钮点选过至少一次才为 YES——
// 选中图标的 1.15 弹跳只跟用户点选驱动的切换，冷启首落位与程序
// 化切换保持安静。由 handler 的 zhPluginNavTapped: 在回链前置位。
static BOOL gNavUserTapped = NO;

#pragma mark - 自建导航按钮（数据从原栏 item 抄，几何自定）

// ZPNavButton：自建导航的单只按钮（UIControl）。内容只有图标在
// 上、标题在下，数据每轮维护时从原栏 item 视图同步（图标/头像
// 图、标题文、字体、色值——原栏选中/主题变化后图色随之变，两态
// 自动跟随）。点击经 handler 的 zhPluginNavTapped: 回原栏
// didClickTabBarItem:（原 item 的 itemControlClick 同一入口）。
@interface ZPNavButton : UIControl {
    UIImageView *_iconView;
    UILabel *_titleLabel;
    UIView *_bar;   // assign：原栏（按钮由 associated 挂在原栏上，生命周期从属原栏）
    id _model;      // RETAIN：原栏 item 的 model（点击回链用）
    BOOL _navSelected;
}
- (void)zpSetBar:(UIView *)bar model:(id)model;
- (UIView *)zpBar;
- (id)zpModel;
- (void)zpSyncIcon:(UIImage *)img avatar:(BOOL)avatar srcTint:(UIColor *)tint;
- (void)zpSyncTitle:(NSString *)title font:(UIFont *)font color:(UIColor *)color;
- (void)zpSetNavSelected:(BOOL)sel;
@end

@implementation ZPNavButton
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_titleLabel];
    }
    return self;
}
- (void)dealloc {
    [_iconView release];
    [_titleLabel release];
    [_model release];
    [super dealloc];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    _iconView.frame = CGRectMake((w - 24) / 2, 11, 24, 24);
    _titleLabel.frame = CGRectMake(0, 38, w, 13);
}
- (void)zpSetBar:(UIView *)bar model:(id)model {
    _bar = bar;
    if (_model != model) { [_model release]; _model = [model retain]; }
}
- (UIView *)zpBar { return _bar; }
- (id)zpModel { return _model; }
- (void)zpSyncIcon:(UIImage *)img avatar:(BOOL)avatar srcTint:(UIColor *)tint {
    if (_iconView.image != img) _iconView.image = img;
    if (tint && _iconView.tintColor != tint) _iconView.tintColor = tint;
    // 头像圆形、图标方形：只在形态变化时写 layer（幂等）
    CGFloat want = avatar ? 12 : 0;
    if (_iconView.layer.cornerRadius != want) {
        _iconView.layer.cornerRadius = want;
        _iconView.layer.masksToBounds = avatar;
    }
}
- (void)zpSyncTitle:(NSString *)title font:(UIFont *)font color:(UIColor *)color {
    if (title && ![title isEqualToString:_titleLabel.text]) _titleLabel.text = title;
    if (font && _titleLabel.font != font) _titleLabel.font = font;
    if (color && _titleLabel.textColor != color) _titleLabel.textColor = color;
}
- (void)zpSetNavSelected:(BOOL)sel {
    BOOL was = _navSelected;
    _navSelected = sel;
    // 选中弹跳（v3.1）：NO→YES 且由用户点选驱动（gNavUserTapped）
    // 时，图标先撑到 1.15 再以低阻尼弹簧回弹归位（过冲即弹跳感）；
    // 冷启首落位/程序化切换不弹。
    if (sel && !was && gNavUserTapped) {
        _iconView.transform = CGAffineTransformMakeScale(1.15, 1.15);
        [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.45
             initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{ _iconView.transform = CGAffineTransformIdentity; }
                         completion:nil];
    }
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    CGFloat a = highlighted ? 0.55 : 1.0;
    _iconView.alpha = a;
    _titleLabel.alpha = a;
    // 按压反馈（v3.1）：按下图标缩到 0.9（快、硬），松开弹簧回弹
    // （慢、软）；与选中弹跳共用 _iconView.transform，均以
    // BeginFromCurrentState 衔接，前后动画不打架。
    [UIView animateWithDuration:(highlighted ? 0.18 : 0.45) delay:0
         usingSpringWithDamping:(highlighted ? 0.85 : 0.5)
          initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
        _iconView.transform = highlighted ? CGAffineTransformMakeScale(0.9, 0.9)
                                          : CGAffineTransformIdentity;
    } completion:nil];
}
@end

#pragma mark - 原栏 item 数据读取（按钮数据来源）

// 原栏可见 item 视图列表：stackView 的 arrangedSubviews 中未隐藏
// 者（ZHGlassBar 时代定案口径：item = ZHTabBarItemNormalView，父
// 链 item → stackView → ZHTabBarNew）。
static NSArray *ZHVisibleItems(UIView *bar) {
    UIView *stack = ZHGetObj(bar, @"stackView");
    NSArray *arranged = ZHGetObj(stack, @"arrangedSubviews");
    if (![arranged isKindOfClass:[NSArray class]]) return nil;
    NSMutableArray *vis = [NSMutableArray array];
    for (id v in arranged) {
        if (![v isKindOfClass:[UIView class]]) continue;
        UIView *uv = (UIView *)v;
        if (uv.hidden || uv.alpha < 0.01) continue;
        [vis addObject:uv];
    }
    return vis;
}

// item 的 model 与 identifier（枚举：Feed=0、Video=2、
// Notifications=4、More=5、Creation=8——v1 静态定案；
// didClickTabBarItem: 内部以整数比较 identifier）
static id ZHItemModel(UIView *item) { return ZHGetObj(item, @"model"); }
static NSInteger ZHItemIdentifier(UIView *item) {
    id model = ZHItemModel(item);
    if (!model || ![model respondsToSelector:@selector(identifier)]) return -1;
    return ((NSInteger (*)(id, SEL))objc_msgSend)(model, @selector(identifier));
}

// item 的有效图标：我的（More）优先 avatarImageView 的头像图（有
// 图且未隐藏时），其余取 iconImageView 的当前图（选中/主题态由知
// 乎自己换图，维护每轮同步即跟随）。srcTint 带回 iconImageView 的
// tintColor（模板图标靠它上色，复制时一并带走）。
static UIImage *ZHItemIcon(UIView *item, BOOL *isAvatar, UIColor **srcTint) {
    *isAvatar = NO;
    if (srcTint) *srcTint = nil;
    UIView *av = ZHGetObj(item, @"avatarImageView");
    if ([av isKindOfClass:[UIImageView class]] && !av.hidden && ((UIImageView *)av).image) {
        *isAvatar = YES;
        return ((UIImageView *)av).image;
    }
    UIView *iv = ZHGetObj(item, @"iconImageView");
    if ([iv isKindOfClass:[UIImageView class]]) {
        if (srcTint) *srcTint = iv.tintColor;
        return ((UIImageView *)iv).image;
    }
    return nil;
}

// 风格钉住：overrideUserInterfaceStyle 钉知乎主题（ZPAppIsNight 口径——优先
// ZHThemeManage isNightMode，与发色点同源）。知乎主题与系统外观不一致时，
// 玻璃的明暗必须跟知乎走（SJJ configureSlot 样式先行同款动作）。
// ZHLayoutGlassNav 每轮都会调用，主题切换经既有 apply 路径自动同步；
// 先比对现值再写，保持幂等。
static void ZHGlassApplyTheme(UIView *v) {
    if (!v) return;
    UIUserInterfaceStyle want = ZPAppIsNight() ? UIUserInterfaceStyleDark : UIUserInterfaceStyleLight;
    if (v.overrideUserInterfaceStyle != want) v.overrideUserInterfaceStyle = want;
}

// bg 写入方捕获（本轮第二使命）：历代探针实证胶囊的 backgroundColor
// 被外部写入（首白末黑、共 2 次）而同窗材质胶囊 0 次，本插件源码无
// 任何对胶囊 bg 的赋值——写入方身份至今未定。本轮由 ZPGlassView 覆
// 写 setBackgroundColor: 在写入发生的当场捕获：值 + 调用方（返回地
// 址经 dladdr 解析为 <镜像名>+0x<镜像内偏移>；主程序即
// osee2unifiedRelease+0x…、系统库报库名）。至多留前 4 次详细记录
// （gBgRecords），总次数另计 gBgWriteTotal；首次/末次值保留
// gBgCapFirst/gBgCapLast 供诊断速览。只记不钉：覆写记录完即放行
// super，插件绝不回写胶囊 bg（两家样本对玻璃视图本体 bg 一指不碰
// 的纪律不变）。
static NSString *gBgCapFirst = nil, *gBgCapLast = nil; // 胶囊被写入值记录（RETAIN）
static NSUInteger gBgWriteTotal = 0;
static NSMutableArray *gBgRecords = nil; // 前 4 次详细记录（alloc/init 持有）
// 本镜像基址（dladdr 自身函数求得，捕获时用来跳过自家栈帧）
static void *ZPSelfImageBase(void) {
    static void *base = NULL;
    if (!base) {
        Dl_info info;
        if (dladdr((void *)ZPSelfImageBase, &info)) base = info.dli_fbase;
    }
    return base;
}
// 返回地址 → 「<镜像名>+0x<偏移>」；解析失败报「未知」
static NSString *ZPCallerDesc(void *ra) {
    if (!ra) return @"未知";
    Dl_info info;
    if (!dladdr(ra, &info) || !info.dli_fbase) return @"未知";
    const char *path = info.dli_fname ? info.dli_fname : "";
    const char *slash = strrchr(path, '/');
    const char *name = slash ? slash + 1 : path;
    return [NSString stringWithFormat:@"%s+0x%lx", name,
            (unsigned long)((uintptr_t)ra - (uintptr_t)info.dli_fbase)];
}
static void ZPRecordBgWrite(UIColor *color, void *retAddr) {
    // retAddr 是覆写方法的直接返回地址（objc_msgSend 尾调 IMP，指向发
    // 送方代码内紧挨着消息发送的下一条指令）；若它落在本镜像内（自家
    // 代码触发的写入），再用 backtrace 往外找第一帧非本镜像的地址作
    // 调用方，避免把自家帧误报成写入方。
    void *caller = retAddr;
    Dl_info probe;
    if (caller && dladdr(caller, &probe) && probe.dli_fbase == ZPSelfImageBase()) {
        void *frames[10];
        int n = backtrace(frames, 10);
        for (int i = 1; i < n; i++) {
            Dl_info fi;
            if (dladdr(frames[i], &fi) && fi.dli_fbase != ZPSelfImageBase()) {
                caller = frames[i];
                break;
            }
        }
    }
    NSString *d = ZPColorDesc(color);
    if (!gBgCapFirst) gBgCapFirst = [d retain];
    [gBgCapLast release];
    gBgCapLast = [d retain];
    gBgWriteTotal++;
    if (!gBgRecords) gBgRecords = [[NSMutableArray alloc] init];
    if (gBgRecords.count < 4)
        [gBgRecords addObject:[NSString stringWithFormat:@"%@ ← %@", d, ZPCallerDesc(caller)]];
}

#pragma mark - 开关回调（单例 handler，静态 RETAIN）

@interface ZHPluginHandler : NSObject
- (void)zhPluginGlassSwitchChanged:(id)sender;
- (void)zhPluginBlackSwitchChanged:(id)sender;
- (void)zhPluginLongPress:(UILongPressGestureRecognizer *)g;
- (void)zhPluginNavTapped:(id)sender;
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

// 自建导航按钮点击：回原栏真实点选链 [bar didClickTabBarItem:model]
// （与原 item 的 itemControlClick 同一入口——静态实证其链为
// [item.delegate didClickTabBarItem:item.model]、delegate 即原栏
// 本人；登录拦截、delegate tabBarNew:didSelect: 切换、model
// setSelected: 更新全在原链内，本插件不另造切换逻辑）。
- (void)zhPluginNavTapped:(id)sender {
    if (![sender isKindOfClass:[ZPNavButton class]]) return;
    ZPNavButton *btn = (ZPNavButton *)sender;
    UIView *bar = [btn zpBar];
    id model = [btn zpModel];
    if (!bar || !model) return;
    gNavUserTapped = YES; // 本次切换由用户点选驱动：选中图标可弹跳（v3.1）
    if ([bar respondsToSelector:@selector(didClickTabBarItem:)])
        ((void (*)(id, SEL, id))objc_msgSend)(bar, @selector(didClickTabBarItem:), model);
    ZHRequestApply(bar); // 点选后排一轮维护，透镜/选中态即时跟上
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

#pragma mark - 布局（正式版：apply 幂等：开 -> 自建导航落位+隐藏原栏；关 -> 还原原栏+移除自建栏）

// 导航几何（两槽定宽）：槽宽 86、栏高 62、两侧内边距 10 → 192×62；
// 底部居中，胶囊底边距屏幕底部 15pt（v3.6 定案：栏高 62 + 底边距 15）。
static const CGFloat kNavSlotW = 86, kNavBarH = 62, kNavPadX = 10;

// keyWindow 选取（与 ZPAppIsNight 同口径：windows 里找 isKeyWindow，回落第一只）
static UIWindow *ZPKeyWindow(void) {
    for (UIWindow *w in [UIApplication sharedApplication].windows)
        if (w.isKeyWindow) return w;
    return [UIApplication sharedApplication].windows.firstObject;
}

// 导航容器工厂：自建透明 UIView——bg 在创建时显式置 clearColor 且
// 此后永不写色（SJJ 宿主清场纪律的形式保留：本 host 无可清场，纪
// 律以「恒 clear」落地）。容器要吃点击（按钮在内），与探针版不同。
static UIView *ZHNavHostForBar(UIView *bar) {
    UIView *host = objc_getAssociatedObject(bar, &kNavHostKey);
    if (host) return host;
    host = [[UIView alloc] initWithFrame:CGRectZero];
    host.backgroundColor = [UIColor clearColor]; // 显式清场，此后永不写色
    objc_setAssociatedObject(bar, &kNavHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [host release];
    return host;
}

// 玻璃面（index 0 垫底）/ 透镜：取或建，塑形在工厂内一次完成；入
// 树与 effect 后装在 ZHLayoutGlassNav 按 SJJ 次序完成。玻璃面须在
// host.frame 定型后创建（塑形圆角按创建时高/2，host 尺寸恒定）。
static ZPGlassView *ZHNavGlassForBar(UIView *bar, UIView *host) {
    ZPGlassView *v = objc_getAssociatedObject(bar, &kNavGlassKey);
    if (v) return v;
    v = ZHMakeNavGlassView(host.bounds);
    if (!v) return nil;
    objc_setAssociatedObject(bar, &kNavGlassKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [v release];
    return v;
}
static ZPGlassView *ZHNavLensForBar(UIView *bar) {
    ZPGlassView *v = objc_getAssociatedObject(bar, &kNavLensKey);
    if (v) return v;
    v = ZHMakeNavGlassView(CGRectMake(0, 0, kNavSlotW - 12, kNavBarH - 12));
    if (!v) return nil;
    v.hidden = YES; // 首次落位前不显形，落位当轮直接置 frame 不滑动
    objc_setAssociatedObject(bar, &kNavLensKey, v, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [v release];
    return v;
}

// 按钮：取或建（建时挂 handler 点击回调），frame/数据在落位时同步。
static ZPNavButton *ZHNavButtonForBar(UIView *bar, const void *key) {
    ZPNavButton *b = objc_getAssociatedObject(bar, key);
    if (b) return b;
    b = [[ZPNavButton alloc] initWithFrame:CGRectZero];
    [b addTarget:ZPHandler() action:@selector(zhPluginNavTapped:)
        forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(bar, key, b, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [b release];
    return b;
}

// 把一只原栏 item 的数据同步进自建按钮（图标/头像、标题文/字体/
// 色、点击回链用的 bar+model）。
static void ZPSyncNavButton(ZPNavButton *btn, UIView *bar, UIView *item) {
    [btn zpSetBar:bar model:ZHItemModel(item)];
    BOOL avatar = NO; UIColor *tint = nil;
    UIImage *img = ZHItemIcon(item, &avatar, &tint);
    [btn zpSyncIcon:img avatar:avatar srcTint:tint];
    UILabel *lab = (UILabel *)ZHGetObj(item, @"titleLable");
    if ([lab isKindOfClass:[UILabel class]])
        [btn zpSyncTitle:lab.text font:lab.font color:lab.textColor];
}

// 玻璃容器工厂（v3.1）：UIVisualEffectView + UIGlassContainerEffect
// （spacing 2.0）——玻璃面与透镜同入其 contentView 聚合，透镜移动
// 时与底盘玻璃产生系统形变（系统 UITabBar 选中指示器的同款机制；
// spacing 2.0 与 SJJ 样本多元素组合的实测常量一致）。容器永不吃
// 点击。类取不到（<iOS 26）返回 nil，布局节回落玻璃面/透镜直挂
// host 的旧形态。
static UIVisualEffectView *ZHNavContainerForBar(UIView *bar, UIView *host) {
    UIVisualEffectView *cv = objc_getAssociatedObject(bar, &kNavContainerKey);
    if (cv) return cv;
    Class ccCls = NSClassFromString(@"UIGlassContainerEffect");
    if (!ccCls) return nil;
    id cfx = [[ccCls alloc] init];
    if (!cfx) return nil;
    if ([cfx respondsToSelector:@selector(setSpacing:)])
        ((void (*)(id, SEL, double))objc_msgSend)(cfx, @selector(setSpacing:), 2.0);
    cv = [[UIVisualEffectView alloc] initWithEffect:cfx];
    [cfx release];
    cv.userInteractionEnabled = NO;
    cv.frame = host.bounds;
    objc_setAssociatedObject(bar, &kNavContainerKey, cv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cv release];
    return cv;
}

// 原栏摘除与保留（v3.3 修 A，用户拍板方向修正：不藏、直接摘）：
// 玻璃开时，栏一入窗（出生钩在同一轮、首帧绘制前调用）或被
// apply/启动清扫首触时，直接 removeFromSuperview 摘出层级，并
// 由插件强引用保留（gDetachedBar）——它仍是图标/标题/头像的数
// 据源，每轮同步照旧从它身上读（item 视图不在层级内也持有数
// 据，控制器对栏对象的方法调用不因摘除而停）。摘除前把它的原
// 父视图与子视图位次记在它自己的 associated 上（父视图以
// RETAIN 存，根视图长命、无悬垂之虞），供玻璃关时原样放回。
// 知乎若重建出新的原栏实例（登录态变化等），出生钩对新实例同
// 口径摘除并换保留引用，旧的随之释放。不再有任何「未建成自动
// 把原栏放回来」的兜底：胶囊建不起来就留空槽胶囊在位（修 B），
// 原栏只在用户关玻璃开关时才放回。
static UIView *gDetachedBar = nil; // RETAIN：当前被摘除的原栏（数据源 + 放回用）
static void ZHNavDetachBar(UIView *bar) {
    if (!bar || !ZHGlassEnabled()) return;
    if (gDetachedBar == bar && !bar.superview) return; // 已摘除且就是保留的那只
    UIView *parent = bar.superview;
    if (parent) {
        objc_setAssociatedObject(bar, &kNavOrigParentKey, parent, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &kNavOrigIndexKey,
                                 @([parent.subviews indexOfObjectIdenticalTo:bar]),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (gDetachedBar != bar) { // 新实例换保留：旧的释放（其放回记录随之作废）
        [gDetachedBar release];
        gDetachedBar = [bar retain];
    }
    if (parent) [bar removeFromSuperview]; // 摘除会以 window=nil 再入出生钩，钩内守卫天然跳过
}
static BOOL ZHNavSlotsIdentified(UIView *bar) {
    return objc_getAssociatedObject(bar, &kNavIdentifiedKey) != nil;
}

// 冷启直达（v3.1 建链，v3.3 改判停）：建成判定 + 快重试链。胶囊
// 先到位（修 B）后「建成」来得很早，本链的实际职责是等槽位识别
// ——建成且已识别才停并清计数；每 0.1s 一拍重排 apply，计数上限
// 30（≈3s），到顶只是停链（空槽胶囊留在位、原栏不复活，v3.3 口
// 径），后续知乎事件（setItems/select/主题钩子）仍可把识别补完。
// 在途标记保证全程只有一条链（各处重复呼叫都被它合并）。
static BOOL ZHNavIsBuilt(UIView *bar) {
    UIView *host = objc_getAssociatedObject(bar, &kNavHostKey);
    return host && host.superview && objc_getAssociatedObject(bar, &kNavGlassKey) &&
           gDetachedBar == bar;
}
static void ZHNavKickRetry(UIView *bar) {
    if (!bar || !ZHGlassEnabled()) return;
    if (ZHNavIsBuilt(bar) && ZHNavSlotsIdentified(bar)) { // 建成且识别：清计数收工
        objc_setAssociatedObject(bar, &kNavRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (objc_getAssociatedObject(bar, &kNavRetryPendKey)) return; // 已有在途一拍
    NSInteger cnt = [objc_getAssociatedObject(bar, &kNavRetryKey) integerValue];
    if (cnt >= 30) return; // ≈3s 上限：停链，不复活原栏（v3.3）
    objc_setAssociatedObject(bar, &kNavRetryKey, @(cnt + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kNavRetryPendKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        objc_setAssociatedObject(bar, &kNavRetryPendKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!ZHGlassEnabled()) return;
        ZHRequestApply(bar); // 下一拍施工（识别与否由施工结果决定）
        ZHNavKickRetry(bar); // 未识别则续排下一拍（在途标记防叠链）
    });
}

// 跟随原栏显隐（v3.9）：知乎的显隐总漏斗是控制器
// -[ZHInitialTabBarController showTabBar:animated:] 内的
// [tabBar setHidden:!show]（静态实证见文件头 v3.9 段）。本插件
// 在 ZHTabBarNew 上加的 setHidden: 覆盖负责把每次信号记下来
// （值/来源/计数，供诊断判读），并同轮对齐自建 host；布局节
// 每轮再以原栏当前 hidden 实值对账（实值即知乎意图、为最终
// 准绳，钩子漏记也能自愈）。原栏被摘除不在层级内不影响这套
// 信号：控制器持有栏对象，setHidden: 是方法调用、照常到达。
static void ZHNavNoteFollow(UIView *bar, BOOL hidden, NSString *src) {
    NSNumber *old = objc_getAssociatedObject(bar, &kNavFollowKey);
    if (old && old.boolValue == hidden &&
        [objc_getAssociatedObject(bar, &kNavFollowSrcKey) isEqualToString:src])
        return; // 值与来源都没变：不重复计数（布局对账每轮都会走一遍）
    objc_setAssociatedObject(bar, &kNavFollowKey, @(hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(bar, &kNavFollowSrcKey, src, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSNumber *c = objc_getAssociatedObject(bar, &kNavFollowCntKey);
    objc_setAssociatedObject(bar, &kNavFollowCntKey,
                             @((c ? c.unsignedLongValue : 0) + 1),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 透镜单写者（v3.2 修 2）：全文件唯一写透镜几何（frame/transform）
// 的函数——首落位、槽位弹簧、空闲校正三条路径全经它，布局节只
// 做决策（落位/起弹簧/校正/在途跳过）。审计背景（详见
// PATCH_NOTES v3.2）：v3.1 的弹簧是一次性写入——槽位记忆在起弹
// 簧前先行提交，动画一旦没被呈现，后续维护轮次全因「槽位已达」
// 袖手、透镜再无补救；且透镜自 v3.1 起进了玻璃容器的
// contentView，容器按子视图 model 几何合成，只改 center 的
// presentation 层插值在合成结果里被压成瞬时落位（v3.0 透镜直挂
// host、同法写 frame 是可见滑动的）。本版弹簧改回写 frame（与
// v3.0 已验写形一致），并以在途标记 + completion 后补排核对保
// 证单写者纪律与自愈；槽位记忆只在本函数内提交。
static BOOL ZHNavRectNear(CGRect a, CGRect b, CGFloat tol) {
    return fabs(a.origin.x - b.origin.x) <= tol && fabs(a.origin.y - b.origin.y) <= tol &&
           fabs(a.size.width - b.size.width) <= tol && fabs(a.size.height - b.size.height) <= tol;
}
static void ZHNavDriveLens(UIView *bar, ZPGlassView *lens, CGRect target, NSInteger sel, BOOL animated) {
    objc_setAssociatedObject(bar, &kNavLensSlotKey, @(sel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!animated) { // 首落位/空闲校正：直接置位
        lens.frame = target;
        lens.transform = CGAffineTransformIdentity;
        return;
    }
    objc_setAssociatedObject(bar, &kNavLensAnimKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.75
         initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction
                     animations:^{ lens.frame = target; }
                     completion:^(BOOL finished) {
        (void)finished;
        objc_setAssociatedObject(bar, &kNavLensAnimKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ZHRequestApply(bar); // 补一轮核对：在途期间被跳过的槽位变化/落位偏差由此收口
    }];
}

// 玻璃开落位（每轮 apply 走一遍，全程幂等；次序照 SJJ：建槽入树
// → 钉风格 → 装 effect）：
//   胶囊先到位（v3.3 修 B）——host/玻璃面/透镜/按钮先按现行几何
//   建好并显示，不等 item 数据；槽位识别——可见 item 中
//   identifier 0 = 首页、5 = 我的双双命中才算识别，未识别先按
//   可见序尽力占位映射、按钮禁用（userInteractionEnabled=NO），
//   识别完成即启用，数据后续每轮同步补齐/纠正；未识别时另排冷
//   启快重试链（ZHNavKickRetry）等数据，不等下一轮事件。
//   host——不在当前 keyWindow 才重挂；frame 变更才写；hidden 同步。
//   玻璃面/透镜——同入玻璃容器（UIGlassContainerEffect，v3.1）的
//   contentView（玻璃面 index 0 垫底、透镜其上），容器不在 host
//   内才以 index 0 垫入；容器不可用时回落直挂 host。按钮随后入
//   host（叠在容器之上），已在位不重排。玻璃面 frame 与 host
//   bounds 不同才写（容器坐标与 host 坐标一致）。
//   风格——玻璃面与透镜每轮 ZHGlassApplyTheme 钉知乎主题（内含比
//   对、变更才写），排在装 effect 之前。
//   effect——为 nil 才建 fx 经 zpUpdateMaterial: 装入，已装永不重赋。
//   选中——识别后读两 item 的 themeSelected（都读不到回落上轮槽位）；
//   透镜目标 = 选中槽内缩（6,6,74,50）：几何只经单写者
//   ZHNavDriveLens（v3.2）——首次直接置位，后续槽位变化走弹簧
//   （0.5s/damping 0.75 写 frame，形变归容器 morph），在途期间
//   维护不碰、空闲时偏差 >0.5pt 直写校正。按钮选中态同步。
//   原栏——摘除/放回由出生钩与开关路径负责，布局节不碰。
static void ZHLayoutGlassNav(UIView *bar) {
    ZHRegisterBar(bar);
    UIWindow *win = ZPKeyWindow();
    if (!win || win.bounds.size.width < 100) { ZHNavKickRetry(bar); return; }

    UIView *host = ZHNavHostForBar(bar);
    if (host.superview != win) [win addSubview:host]; // 只挂一次、不重排
    CGFloat W = kNavSlotW * 2 + kNavPadX * 2;
    CGRect hf = CGRectMake((win.bounds.size.width - W) / 2,
                           win.bounds.size.height - 23 - kNavBarH,
                           W, kNavBarH);
    if (!CGRectEqualToRect(host.frame, hf)) host.frame = hf;
    // 跟随原栏显隐（v3.9）：原栏当前 hidden 实值即知乎的显隐意
    // 图（二级页经 showTabBar: 置 YES、一级页恢复 NO）——host
    // 与之对齐：隐藏时不显形也不吃触摸，不再压答案页自带底
    // 栏；与记录值不符时补记一次「layout对账」（钩子漏记的自
    // 愈路径，正常情况两者恒一致）。
    {
        BOOL followHidden = bar.hidden;
        NSNumber *rec = objc_getAssociatedObject(bar, &kNavFollowKey);
        if (!rec || rec.boolValue != followHidden)
            ZHNavNoteFollow(bar, followHidden, @"layout对账");
        if (host.hidden != followHidden) host.hidden = followHidden;
    }

    ZPGlassView *glass = ZHNavGlassForBar(bar, host);
    if (!glass) { // 玻璃类不可用：静默不建导航，空 host 摘掉免吃点击，原栏保持原样
        if (host.superview) [host removeFromSuperview];
        return;
    }
    ZPGlassView *lens = ZHNavLensForBar(bar);
    ZPNavButton *btnHome = ZHNavButtonForBar(bar, &kNavBtnHomeKey);
    ZPNavButton *btnMine = ZHNavButtonForBar(bar, &kNavBtnMineKey);
    // 玻璃容器（v3.1）：玻璃面+透镜同入容器 contentView 聚合（透镜
    // 移动时与底盘形变）；容器恒 host index 0、frame 同 host bounds。
    // 容器类取不到时回落旧形态：玻璃面/透镜直挂 host。
    UIVisualEffectView *container = ZHNavContainerForBar(bar, host);
    UIView *glassParent = host;
    if (container) {
        if (container.superview != host) [host insertSubview:container atIndex:0];
        if (!CGRectEqualToRect(container.frame, host.bounds)) container.frame = host.bounds;
        if (container.hidden) container.hidden = NO;
        glassParent = container.contentView;
    }
    if (glass.superview != glassParent) [glassParent insertSubview:glass atIndex:0]; // 玻璃面恒垫底
    if (!CGRectEqualToRect(glass.frame, host.bounds)) glass.frame = host.bounds;
    if (glass.hidden) glass.hidden = NO;
    if (lens && lens.superview != glassParent) [glassParent addSubview:lens];
    if (btnHome.superview != host) [host addSubview:btnHome];
    if (btnMine.superview != host) [host addSubview:btnMine];
    CGRect homeF = CGRectMake(kNavPadX, 0, kNavSlotW, kNavBarH);
    CGRect mineF = CGRectMake(kNavPadX + kNavSlotW, 0, kNavSlotW, kNavBarH);
    if (!CGRectEqualToRect(btnHome.frame, homeF)) btnHome.frame = homeF;
    if (!CGRectEqualToRect(btnMine.frame, mineF)) btnMine.frame = mineF;

    ZHGlassApplyTheme(glass);
    if (lens) ZHGlassApplyTheme(lens);
    if (container) ZHGlassApplyTheme(container);
    if (!glass.effect) {
        id fx = ZHMakeGlassEffect(YES);
        if (fx) [glass zpUpdateMaterial:fx];
    }
    if (lens && !lens.effect) {
        id fx = ZHMakeGlassEffect(YES);
        if (fx) [lens zpUpdateMaterial:fx];
    }

    // 槽位识别（v3.3 修 B）：identifier 0/5 双双命中才算识别；未
    // 识别时按可见序尽力占位映射（有几个排几个），按钮禁用，识别
    // 完成的那一轮起才启用按钮并走下面的选中/透镜逻辑。
    NSArray *vis = ZHVisibleItems(bar);
    UIView *homeItem = nil, *mineItem = nil;
    BOOL identified = NO;
    if (vis) {
        UIView *byIdHome = nil, *byIdMine = nil;
        for (UIView *it in vis) {
            NSInteger ident = ZHItemIdentifier(it);
            if (ident == 0 && !byIdHome) byIdHome = it;
            if (ident == 5 && !byIdMine) byIdMine = it;
        }
        if (byIdHome && byIdMine && byIdHome != byIdMine) {
            homeItem = byIdHome; mineItem = byIdMine; identified = YES;
        } else {
            if (vis.count >= 1) homeItem = vis.firstObject;
            if (vis.count >= 2) mineItem = vis.lastObject;
            if (homeItem == mineItem) mineItem = nil;
        }
    }
    if (homeItem) ZPSyncNavButton(btnHome, bar, homeItem);
    if (mineItem) ZPSyncNavButton(btnMine, bar, mineItem);
    if (btnHome.userInteractionEnabled != identified) btnHome.userInteractionEnabled = identified;
    if (btnMine.userInteractionEnabled != identified) btnMine.userInteractionEnabled = identified;
    if (identified && !ZHNavSlotsIdentified(bar))
        objc_setAssociatedObject(bar, &kNavIdentifiedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!identified) {
        // 占位态：透镜停在上轮槽位（无记录则首页槽）直接置位、不走
        // 弹簧；继续排快重试等识别，图标/标题每轮同步补齐。
        if (lens) {
            NSNumber *lastSelP = objc_getAssociatedObject(bar, &kNavSelKey);
            NSInteger parkSel = lastSelP ? lastSelP.integerValue : 0;
            CGRect pslot = (parkSel == 0) ? homeF : mineF;
            CGRect ptarget = CGRectInset(pslot, 6, 6);
            BOOL placedP = (objc_getAssociatedObject(bar, &kNavPlacedKey) != nil);
            BOOL inFlightP = (objc_getAssociatedObject(bar, &kNavLensAnimKey) != nil);
            if (!inFlightP && (!placedP || !ZHNavRectNear(lens.frame, ptarget, 0.5))) {
                ZHNavDriveLens(bar, lens, ptarget, parkSel, NO);
                objc_setAssociatedObject(bar, &kNavPlacedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (lens.hidden) lens.hidden = NO;
        }
        ZHNavKickRetry(bar);
        return;
    }

    NSInteger sel = -1;
    if (ZHGetBool(homeItem, @"themeSelected", NO)) sel = 0;
    else if (ZHGetBool(mineItem, @"themeSelected", NO)) sel = 1;
    NSNumber *lastSel = objc_getAssociatedObject(bar, &kNavSelKey);
    if (sel < 0) sel = lastSel ? lastSel.integerValue : 0;
    objc_setAssociatedObject(bar, &kNavSelKey, @(sel), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [btnHome zpSetNavSelected:(sel == 0)];
    [btnMine zpSetNavSelected:(sel == 1)];
    if (lens) {
        CGRect slot = (sel == 0) ? homeF : mineF;
        CGRect target = CGRectInset(slot, 6, 6);
        // 单写者纪律（v3.2）：在途标记置位期间一律不碰透镜几何
        // （弹簧由 ZHNavDriveLens 独占写入，其 completion 会补排
        // 一轮核对收口）；空闲时按「未落位 → 直写落位 / 槽位变
        // → 起弹簧 / 槽位同但 frame 与目标偏差 >0.5pt → 直写校
        // 正」决策，几何只经 ZHNavDriveLens 写。
        BOOL inFlight = (objc_getAssociatedObject(bar, &kNavLensAnimKey) != nil);
        if (!inFlight) {
            BOOL placed = (objc_getAssociatedObject(bar, &kNavPlacedKey) != nil);
            if (!placed) {
                ZHNavDriveLens(bar, lens, target, sel, NO); // 首次落位不动画（冷启直达口径）
                objc_setAssociatedObject(bar, &kNavPlacedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            } else {
                NSNumber *lensSlot = objc_getAssociatedObject(bar, &kNavLensSlotKey);
                if (!lensSlot || lensSlot.integerValue != sel)
                    ZHNavDriveLens(bar, lens, target, sel, YES);
                else if (!ZHNavRectNear(lens.frame, target, 0.5))
                    ZHNavDriveLens(bar, lens, target, sel, NO); // 空闲幂等核对：偏差超限直写校正（自愈）
            }
        }
        if (lens.hidden) lens.hidden = NO;
    }

    // 原栏的摘除/放回不在此处理（出生钩摘、关开关放回，v3.3）
}

// 玻璃关：把保留的原栏按摘除时记录的原父视图/位次放回并确保
// hidden=NO + 自建栏移出窗口（host 对象仍由 associated 持有，
// 下次开直接复用；透镜落位标记不清——重开时槽位未变不滑动、变
// 了走滑动，正是想要的）。只有当前保留的那只栏有东西可放（旧
// 实例在换保留时已释放，不在此列）。放回触发的 didMoveToWindow
// 时玻璃已关，出生钩不会再摘。
static void ZHRestoreOriginalBar(UIView *bar) {
    UIView *host = objc_getAssociatedObject(bar, &kNavHostKey);
    if (host && host.superview) [host removeFromSuperview];
    if (gDetachedBar == bar) {
        UIView *parent = objc_getAssociatedObject(bar, &kNavOrigParentKey);
        NSNumber *idx = objc_getAssociatedObject(bar, &kNavOrigIndexKey);
        if (parent) {
            NSUInteger at = idx ? idx.unsignedIntegerValue : parent.subviews.count;
            if (at > parent.subviews.count) at = parent.subviews.count;
            [parent insertSubview:bar atIndex:at];
        }
        if (bar.hidden) bar.hidden = NO;
        objc_setAssociatedObject(bar, &kNavOrigParentKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(bar, &kNavOrigIndexKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDetachedBar release];
        gDetachedBar = nil;
    }
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
    if (ZHGlassEnabled()) {
        ZHNavDetachBar(bar); // 出生即摘补漏（v3.3）：出生钩没赶上的栏，apply 首触先摘再建胶囊
        ZHLayoutGlassNav(bar);
        ZHNavKickRetry(bar); // 冷启直达（v3.1）：未建成则续排快重试，建成自动停
    }
    else ZHRestoreOriginalBar(bar);
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
// 施工；每轮 apply 按幂等清单维护导航（host/玻璃/透镜/按钮位置核
// 查、按钮数据同步、frame/风格变更才写、effect 为 nil 才装）——页
// 面切换/主题切换/选中变化都会带来新一轮维护。

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

// 玻璃导航的诊断块：自建栏 host 本值 frame + 窗口 frame 实测
// （convertRect:toView:nil）、superview 类名链、window 是否非空；
// 容器 effect 类名 + 玻璃面 frame（host 内坐标）+ 在其父视图中的
// 位次、effect 对象类名；透镜 frame/hidden/effect 类名；当前选中项（槽位序号 +
// 首页/我的）；两按钮 frame；effect 通道计数（setEffect: 外部调
// 用次数 + 最近传入类名 / zpUpdateMaterial: 安装次数）、bg 写入
// 记录（总次数 + 前 4 次详细：值 ← 调用方镜像+偏移，只记不
// 钉）、完整子树——从 host 起打印（玻璃面与透镜各自的背板
// _UIVisualEffectBackdropView 在不在一眼可见，见 ZPDiagWalk）。
static void ZPAppendNavDiag(NSMutableString *s, UIView *bar) {
    UIView *host = objc_getAssociatedObject(bar, &kNavHostKey);
    ZPGlassView *glass = objc_getAssociatedObject(bar, &kNavGlassKey);
    ZPGlassView *lens = objc_getAssociatedObject(bar, &kNavLensKey);
    ZPNavButton *btnHome = objc_getAssociatedObject(bar, &kNavBtnHomeKey);
    ZPNavButton *btnMine = objc_getAssociatedObject(bar, &kNavBtnMineKey);
    [s appendString:@"玻璃导航（自建栏·容器聚合玻璃面+透镜·两按钮）:\n"];
    if (!host || !glass) {
        [s appendString:@"  自建栏: 未创建（玻璃类不可用或窗口尚未就绪）\n"];
        return;
    }
    [s appendFormat:@"  自建栏 frame(本值)=%@ 窗口frame(实测)=%@ hidden=%d superview链=%@ window=%@\n",
         NSStringFromCGRect(host.frame),
         NSStringFromCGRect([host convertRect:host.bounds toView:nil]),
         (int)host.hidden, ZPSuperviewChain(host), host.window ? @"非空" : @"nil"];
    UIVisualEffectView *container = objc_getAssociatedObject(bar, &kNavContainerKey);
    [s appendFormat:@"  容器 effect类名=%@ host内子视图位=%ld\n",
         container ? ZPEffectClassName(container) : @"(无容器，回落直挂)",
         container ? (long)[host.subviews indexOfObjectIdenticalTo:container] : -1L];
    [s appendFormat:@"  玻璃面 frame(host内)=%@ hidden=%d 父视图内子视图位=%ld effect类名=%@\n",
         NSStringFromCGRect(glass.frame), (int)glass.hidden,
         (long)[glass.superview.subviews indexOfObjectIdenticalTo:glass],
         ZPEffectClassName(glass)];
    [s appendFormat:@"  透镜 frame(host内)=%@ hidden=%d effect类名=%@\n",
         lens ? NSStringFromCGRect(lens.frame) : @"-",
         lens ? (int)lens.hidden : -1,
         lens ? ZPEffectClassName(lens) : @"-"];
    NSNumber *sel = objc_getAssociatedObject(bar, &kNavSelKey);
    [s appendFormat:@"  当前选中项=%@ 槽位=%@\n",
         sel ? (sel.integerValue == 0 ? @"首页" : @"我的") : @"未知",
         sel ? [sel stringValue] : @"-"];
    [s appendFormat:@"  按钮 首页 frame=%@ 我的 frame=%@\n",
         btnHome ? NSStringFromCGRect(btnHome.frame) : @"-",
         btnMine ? NSStringFromCGRect(btnMine.frame) : @"-"];
    [s appendFormat:@"  槽位识别=%@ 按钮可点=%@ 原栏保留中=%@\n",
         ZHNavSlotsIdentified(bar) ? @"已识别" : @"未识别（占位）",
         (btnHome && btnHome.userInteractionEnabled) ? @"YES" : @"NO",
         (gDetachedBar == bar) ? @"YES" : @"NO"];
    // 跟随显隐（v3.9）：跟随状态以 host.hidden 为准（显示/随原栏
    // 隐藏），对照原栏 hidden 实值与最近信号来源/计数判读——二
    // 级页里应见「随原栏隐藏 + 原栏hidden=1 + 来源 setHidden:」。
    NSNumber *fcnt = objc_getAssociatedObject(bar, &kNavFollowCntKey);
    NSString *fsrc = objc_getAssociatedObject(bar, &kNavFollowSrcKey);
    [s appendFormat:@"  自建栏跟随 跟随状态=%@ 原栏hidden=%d host.hidden=%d 最近信号=%@ 信号计数=%lu\n",
         host.hidden ? @"随原栏隐藏" : @"显示",
         (int)bar.hidden, (int)host.hidden,
         fsrc ?: @"-", fcnt ? (unsigned long)fcnt.unsignedLongValue : 0UL];
    [s appendFormat:@"  effect通道计数 setEffect外部调用=%lu 最近传入=%@ zpUpdateMaterial安装=%lu\n",
         (unsigned long)gSetEffectExtCount, gSetEffectLastClass ?: @"-",
         (unsigned long)gZPInstallCount];
    [s appendFormat:@"  bg 写入记录 玻璃视图: 总次数=%lu 首次=%@ 末次=%@（只记不钉）\n",
         (unsigned long)gBgWriteTotal, gBgCapFirst ?: @"-", gBgCapLast ?: @"-"];
    for (NSString *rec in gBgRecords)
        [s appendFormat:@"    写入: %@\n", rec];
    [s appendString:@"  玻璃导航子树（host 起）:\n"];
    ZPDiagWalk(host, s, 1);
}

// 诊断文本（正式版）：知乎主题值 / 系统 trait / 颜色钩已装 / 纯黑命中集
// 解析数 / 原栏 hidden 状态（玻璃开时由本插件管理）/ 三玻璃类
// NSClassFromString 命中布尔 / UIAccessibility 三开关运行时实读 /
// 玻璃导航块（见 ZPAppendNavDiag，含自建栏 frame、当前选中项、
// effect 通道计数、bg 写入记录与 host 起完整子树）。
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
    if (!bar) { [s appendString:@"底栏: 尚无实例\n"]; ZPAppendBannerDiag(s); return s; }
    [s appendFormat:@"底栏 %@ bounds=%@ frame=%@ bg=%@\n",
         NSStringFromClass(object_getClass(bar)), NSStringFromCGRect(bar.bounds),
         NSStringFromCGRect(bar.frame), ZPColorDesc(bar.backgroundColor)];
    [s appendFormat:@"纯黑命中集: 已解析 %ld 个令牌（静态枚举全集 9）\n",
         (long)ZPCanvasResolvedCount()];
    [s appendFormat:@"原栏 在树=%@ hidden=%d（玻璃开时由本插件摘除并保留为数据源，关时按原父视图/位次放回）\n",
         bar.superview ? @"是" : @"否", (int)bar.hidden];
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
    ZPAppendNavDiag(s, bar);
    ZPAppendBannerDiag(s);

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

    id glassInfo = ZPMakeSwitchInfo(infoCls, @"玻璃底栏", @"开启后，使用液态玻璃底部导航（仅首页/我的）",
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
    if (self.window) {
        // 出生即摘（v3.3 修 A）：原实现跑完、入窗同一轮内同步摘除
        // 原栏并由插件保留（赶在首帧绘制前），它继续当数据源；玻
        // 璃关时由 ZHRestoreOriginalBar 按记录的原父视图/位次放回。
        // 摘除本身会以 window=nil 再入本钩子，上面的守卫天然跳过。
        ZHRegisterBar(self);
        if (ZHGlassEnabled()) {
            ZHNavDetachBar(self);
            ZHRequestApply(self);
            ZHNavKickRetry(self);
        }
    }
}

// setHidden:（v3.9，跟随原栏显隐）：知乎显隐的总漏斗是控制器
// -[ZHInitialTabBarController showTabBar:animated:] 内的
// [tabBar setHidden:!show]（反汇编实证见文件头 v3.9 段；约束切
// 换只管内容区，栏本体显隐就是这一个 flag）。原栏被摘除不在
// 层级内，控制器对它的这次方法调用照常到达。本覆盖只做三件
// 事：原样放行 super → 记跟随状态 → 玻璃开时同轮把自建 host
// 的 hidden 对齐并排一轮 apply 对账。host 隐藏后不显形也不吃
// 触摸，二级页不再与答案页自带底栏重叠；返回一级页知乎发
// setHidden:NO，host 同轮恢复。super 起点同 layoutSubviews
// 铁律：安装时解析父类链 IMP 直调（gSuperSetHidden），类自有
// 实现被 swizzle 时用原 IMP（gOrigSetHidden）——ZHTabBarNew 静
// 态无自有 setHidden:，预期走 class_addMethod + 父类链 IMP。
// 本插件自己对原栏的 hidden 写入只有 ZHRestoreOriginalBar 的
// hidden=NO（玻璃关路径调用，此时 ZHGlassEnabled() 已为 NO，
// 本钩子的对齐分支天然不触发，只留一条跟随记录，无副作用）。
static IMP gOrigSetHidden = NULL;
static IMP gSuperSetHidden = NULL;
static void ZH_Bar_setHidden(UIView *self, SEL _cmd, BOOL hidden) {
    if (gOrigSetHidden) {
        ((void (*)(id, SEL, BOOL))gOrigSetHidden)(self, _cmd, hidden);
    } else if (gSuperSetHidden) {
        ((void (*)(id, SEL, BOOL))gSuperSetHidden)(self, _cmd, hidden);
    } else {
        struct objc_super sup = { self, gBarClass ? class_getSuperclass(gBarClass)
                                                  : class_getSuperclass(object_getClass(self)) };
        ((void (*)(struct objc_super *, SEL, BOOL))objc_msgSendSuper)(&sup, _cmd, hidden);
    }
    ZHNavNoteFollow(self, hidden, @"setHidden:");
    if (ZHGlassEnabled()) {
        UIView *host = objc_getAssociatedObject(self, &kNavHostKey);
        if (host && host.hidden != hidden) host.hidden = hidden; // 同轮对齐，不等下一拍
        ZHRequestApply(self); // 补一轮维护对账（幂等）
    }
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
static BOOL gBirthHookInstalled = NO;
static BOOL gSettingsHookInstalled = NO;

#pragma mark - Hook（横幅拦截，v3.10 段4）

// 普查定案见文件头 v3.10 段：应用内推广通知（FloatNotice）一家的
// 请求漏斗 + 模块漏斗 + 展示漏斗。拦截计数（MRC：静态字典
// alloc/init 全程持有）：键 =「类 选择器」，值 = NSNumber 次数；
// 诊断尾部整表打印核对覆盖面。计数只在主线程的展示路径上写（知
// 乎的请求/展示都走主线程），不另加锁——与本文件既有计数风格一致。
static NSMutableDictionary *gBannerBlockCounts = nil;
static BOOL gBannerHookInstalled = NO;
static void ZPCountBannerBlock(id self, SEL _cmd) {
    if (!gBannerBlockCounts) gBannerBlockCounts = [[NSMutableDictionary alloc] init];
    NSString *key = [NSString stringWithFormat:@"%@ %@",
                     NSStringFromClass(object_getClass(self)), NSStringFromSelector(_cmd)];
    NSNumber *n = gBannerBlockCounts[key];
    gBannerBlockCounts[key] = @(n ? n.unsignedLongValue + 1 : 1);
}

// 请求/模块漏斗的空转实现：统一返回 0（真实方法均为请求式/void，
// 期望指针或布尔的调用方拿到 0 即「无通知」的正确语义）；绝不调
// 原实现、绝不触发完成回调——回调不来即无物可展示、无状态待清理。
static NSInteger ZP_Banner_req1(id self, SEL _cmd, id a1) {
    ZPCountBannerBlock(self, _cmd); return 0;
}
static NSInteger ZP_Banner_req4(id self, SEL _cmd, id a1, id a2, BOOL b, id a3) {
    ZPCountBannerBlock(self, _cmd); return 0;
}
static NSInteger ZP_Banner_req5(id self, SEL _cmd, id a1, id a2, BOOL b, id a3, id a4) {
    ZPCountBannerBlock(self, _cmd); return 0;
}
static NSInteger ZP_Banner_apiShow(id self, SEL _cmd, id a1, id a2, id a3, id a4, id a5, id a6, id a7) {
    ZPCountBannerBlock(self, _cmd); return 0;
}
// 展示漏斗的空转实现（三只通知窗口的 show/makeKeyAndVisible/
// makeVisible）：不调原实现，顺手把窗口 hidden 钉 YES——即便某条
// 未知路径已把它建成，show 被拦下时它也保持不可见、不吃触摸。
static void ZP_Banner_winShow(id self, SEL _cmd) {
    ZPCountBannerBlock(self, _cmd);
    ((void (*)(id, SEL, BOOL))objc_msgSend)(self, @selector(setHidden:), YES);
}

static void ZPAppendBannerDiag(NSMutableString *s) {
    [s appendFormat:@"横幅拦截（v3.10）: 已装=%@\n", gBannerHookInstalled ? @"YES" : @"NO"];
    if (!gBannerBlockCounts || gBannerBlockCounts.count == 0) {
        [s appendString:@"  本进程尚无拦截记录\n"];
        return;
    }
    NSUInteger total = 0;
    for (NSString *k in [[gBannerBlockCounts allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSNumber *num = gBannerBlockCounts[k];
        NSUInteger c = num ? num.unsignedLongValue : 0;
        total += c;
        [s appendFormat:@"  %@ = %lu\n", k, (unsigned long)c];
    }
    [s appendFormat:@"  合计 = %lu\n", (unsigned long)total];
}

// 段4：横幅拦截（FloatNotice 一家；与玻璃开关无关、常开）。
// 目标方法均已静态核实在各目标类自身方法表内（ZHSwap 改的是类
// 自有实现，不会污染父类）。逐类独立装：一类缺失/失败只跳过该类。
static void ZPInstallBannerHooks(void) {
    if (gBannerHookInstalled) return;
    int ok = 0, total = 0;
    Class mgCls = NSClassFromString(@"ZHFloatNoticeManager");
    if (mgCls) {
        total += 4;
        if (ZHSwap(mgCls, @selector(getFloatNoticeIfNeed:), (IMP)ZP_Banner_req1)) ok++;
        if (ZHSwap(mgCls, @selector(getFloatNoticeIfNeedSource:contentToken:needFringe:CallBack:), (IMP)ZP_Banner_req4)) ok++;
        if (ZHSwap(mgCls, @selector(getFloatNoticeIfNeedSource:contentToken:needFringe:CompletionView:CompletionWindow:), (IMP)ZP_Banner_req5)) ok++;
        if (ZHSwap(mgCls, @selector(getFloatNoticeSource:contentToken:needFringe:CompletionView:CompletionWindow:), (IMP)ZP_Banner_req5)) ok++;
    } else NSLog(@"[zhplugin] install segment banner: ZHFloatNoticeManager missing, skip");
    Class apiCls = NSClassFromString(@"ZHInAppNotificationModuleAPI");
    if (apiCls) {
        total += 4;
        if (ZHSwap(apiCls, @selector(getFloatNoticeViewWithCompletion:), (IMP)ZP_Banner_req1)) ok++;
        if (ZHSwap(apiCls, @selector(getFloatNoticeViewWithSource:contentToken:needFringe:Completion:), (IMP)ZP_Banner_req4)) ok++;
        if (ZHSwap(apiCls, @selector(getFloatNoticeViewWithSource:contentToken:needFringe:CompletionView:CompletionWindow:), (IMP)ZP_Banner_req5)) ok++;
        if (ZHSwap(apiCls, @selector(showFloatNoticeViewWithTitle:icon:nightIcon:content:buttonText:delegate:context:), (IMP)ZP_Banner_apiShow)) ok++;
    } else NSLog(@"[zhplugin] install segment banner: ZHInAppNotificationModuleAPI missing, skip");
    Class nvCls = NSClassFromString(@"ZHFloatNoticeView");
    if (nvCls) {
        total += 3;
        if (ZHSwap(nvCls, @selector(show), (IMP)ZP_Banner_winShow)) ok++;
        if (ZHSwap(nvCls, @selector(makeKeyAndVisible), (IMP)ZP_Banner_winShow)) ok++;
        if (ZHSwap(nvCls, @selector(makeVisible), (IMP)ZP_Banner_winShow)) ok++;
    } else NSLog(@"[zhplugin] install segment banner: ZHFloatNoticeView missing, skip");
    for (NSString *cn in @[@"FloatNoticeView", @"FloatNewNoticeView"]) {
        Class c = NSClassFromString(cn);
        if (!c) { NSLog(@"[zhplugin] install segment banner: %@ missing, skip", cn); continue; }
        total += 1;
        if (ZHSwap(c, @selector(show), (IMP)ZP_Banner_winShow)) ok++;
    }
    gBannerHookInstalled = (ok > 0);
    NSLog(@"[zhplugin] install segment banner: swapped %d/%d installed=%d", ok, total, gBannerHookInstalled);
}

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

// 段2a：出生钩提前装（v3.3 修 A）——只装 didMoveToWindow 这一只
// 钩子，由 +load 期随主题钩一起调用：原栏在启动早期就出生，等
// +1s 延迟段再装钩时它早已入窗、出生钩扑空，摘除只能靠清扫事
// 后补、中间露脸。本函数只做父类链 IMP 解析 + class_addMethod
// （类自有实现时退 swizzle）这类最小动作，与 +load 装主题钩同
// 级——不给知乎的类发消息、不触发其 +initialize 链（v7.2 式
// +load 闪退的动作不在此列）。其余底栏钩子仍在 ZPInstallBarHooks
// 延迟装。已装守卫：+load 与 ZPInstall 两处调用只生效一次。
static void ZPInstallBarBirthHook(void) {
    if (gBirthHookInstalled) return;
    Class cls = NSClassFromString(@"ZHTabBarNew");
    if (!cls) { NSLog(@"[zhplugin] install segment birth: ZHTabBarNew missing, skip"); return; }
    gBarClass = cls;
    // 先备好父类链 IMP（addMethod 成功时钩子靠它调 super），再挂钩
    Method superMove = class_getInstanceMethod(class_getSuperclass(cls), @selector(didMoveToWindow));
    gOrigDidMoveToWindow = superMove ? method_getImplementation(superMove) : NULL;
    BOOL addedMove = class_addMethod(cls, @selector(didMoveToWindow),
                                     (IMP)ZH_Bar_didMoveToWindow, "v16@0:8");
    if (!addedMove) // 类自有实现：swizzle，原 IMP 覆盖父类链 IMP（直调它即真 super 行为）
        gOrigDidMoveToWindow = ZHSwap(cls, @selector(didMoveToWindow), (IMP)ZH_Bar_didMoveToWindow);
    gBirthHookInstalled = YES;
    NSLog(@"[zhplugin] install segment birth: didMoveToWindow addMethod=%d orig=%p installed=1",
          addedMove, gOrigDidMoveToWindow);
}

// 段2：玻璃底栏 hook（ZHTabBarNew；出生钩已由段2a 提前装，此处只补装/无操作）
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
    // 跟随显隐（v3.9）：setHidden: 覆盖——先备父类链（UIView）的
    // setHidden: IMP 供钩子直调 super，再 class_addMethod；类自有
    // 实现时退 swizzle 存原 IMP（静态已核 ZHTabBarNew 无自有
    // setHidden:，预期走 addMethod 路）。
    Method superHidden = class_getInstanceMethod(class_getSuperclass(cls), @selector(setHidden:));
    gSuperSetHidden = superHidden ? method_getImplementation(superHidden) : NULL;
    BOOL addedHidden = class_addMethod(cls, @selector(setHidden:),
                                       (IMP)ZH_Bar_setHidden, "v20@0:8B16");
    if (!addedHidden)
        gOrigSetHidden = ZHSwap(cls, @selector(setHidden:), (IMP)ZH_Bar_setHidden);
    ZPInstallBarBirthHook(); // 出生钩：通常已在 +load 装好（守卫在内），此处为 +load 没装成时的补装
    gInstalled = (gOrigSetupUI != NULL && gOrigLayoutItems != NULL);
    NSLog(@"[zhplugin] install segment bar: setupUI=%p layoutItems=%p select=%p theme=%p addLayout=%d addTrait=%d addHidden=%d birth=%d installed=%d",
          gOrigSetupUI, gOrigLayoutItems, gOrigSelect, gOrigNotifyTheme, addedLayout, addedTrait, addedHidden, gBirthHookInstalled, gInstalled);
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

// 启动清扫（v3.1，冷启直达的另一半）：若底栏在钩子装好前就已建
// 成、此后再无事件（冷启静态栏），gLiveBars 可能为空、任何 apply
// 都不会被触发——本链在安装后以 0.1s 一拍（上限 30 拍 ≈ 3s）在当
// 前 keyWindow 的视图树里找 ZHTabBarNew 实例，找到即登记并排
// apply + 快重试；导航建成或拍数耗尽即停。玻璃关时整链不起。
static UIView *ZHFindBarInView(UIView *v) {
    if (!v) return nil;
    if (gBarClass && [v isKindOfClass:gBarClass]) return v;
    for (UIView *s in v.subviews) {
        UIView *hit = ZHFindBarInView(s);
        if (hit) return hit;
    }
    return nil;
}
static NSInteger gLaunchSweepLeft = 0;
static void ZHLaunchSweepTick(void) {
    if (gLaunchSweepLeft <= 0) return;
    gLaunchSweepLeft--;
    if (!ZHGlassEnabled()) { gLaunchSweepLeft = 0; return; }
    UIView *bar = [gLiveBars allObjects].firstObject;
    if (!bar) {
        bar = ZHFindBarInView(ZPKeyWindow());
        if (bar) ZHRegisterBar(bar);
    }
    if (bar) {
        if (ZHNavIsBuilt(bar)) { gLaunchSweepLeft = 0; return; }
        ZHNavDetachBar(bar); // 首触补摘（v3.3）：出生钩装好前出生的栏，清扫一找到先摘再建
        ZHRequestApply(bar);
        ZHNavKickRetry(bar);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ZHLaunchSweepTick(); });
}
static void ZHLaunchSweepStart(void) {
    if (!ZHGlassEnabled() || gLaunchSweepLeft > 0) return;
    gLaunchSweepLeft = 30;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ZHLaunchSweepTick(); });
}

// 四段独立安装：一段抛异常不许拖累其它段（WCBlack v4.7 教训）。
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
    @try {
        ZPInstallBannerHooks();
        NSLog(@"[zhplugin] install segment banner: OK");
    } @catch (NSException *e) {
        NSLog(@"[zhplugin] install segment banner: FAILED: %@", e);
    }
    ZHLaunchSweepStart(); // 冷启直达清扫（v3.1）：找栏 + 排 apply/重试，玻璃关时自跳过
}

@interface ZHPluginLoader : NSObject
@end
@implementation ZHPluginLoader
// +load 分工（本轮定案）：主题段在此即装，底栏/设置两段仍延迟到启动后 +1s；
// 例外（v3.3）：底栏段的 didMoveToWindow 出生钩单只提前到 +load 装（段2a），
// 否则赶不上原栏的首次入窗——它负责的只是摘除+保留，不施工。
// 为什么主题段必须提前：内容区画布色是页面在 viewDidLoad 建成时一次性取走的存量，
// 钩子若等 +1s 再装，首页早已建成、取色已过，事后通知/清扫都够不着（上一版实测
// 顶部黑了、feed 仍灰，清扫还误伤底栏附近容器）。赶在 +load 装好，任何页面建成
// 取色时都走钩子，源头即纯黑。
// 安全边界（与首版闪退教训的区分）：首版嫌疑动作是 +load 期「急切解析画布模型」
// （触发 ZHColorModel +initialize/单例构造）外加整段全量安装；本轮 +load 只做
// 一件最小动作——对 ZHThemeManage 的 +colorWithModel:ignoreNight: 做类方法
// swizzle，不碰 ZHColorModel、画布模型保持首次取色时 dispatch_once 懒解析，
// 底栏段的其余布局钩子（递归修复所在段）与设置段一律不动、维持 +1s 延迟；
// 出生钩的提前只做 IMP 解析 + addMethod，与主题钩同级最小动作（段2a）。
// 若 +load 期解析不到 ZHThemeManage（理论兜底），gThemeHookInstalled 保持 NO，
// +1s 的 ZPInstall 会再调一次 ZPInstallThemeHook 补装。
+ (void)load {
    @try {
        ZPInstallThemeHook();
        NSLog(@"[zhplugin] load: theme segment installed at +load (hook=%d)", gThemeHookInstalled);
    } @catch (NSException *e) {
        NSLog(@"[zhplugin] load: theme segment at +load FAILED (will retry at +1s): %@", e);
    }
    @try {
        // 出生钩（v3.3 修 A）：与主题段同级提前——原栏启动早期即出生，
        // 钩子必须赶在它第一次入窗前装好，才能在同一轮把它摘掉。
        // 只做 IMP 解析 + addMethod，不给知乎类发消息（见段2a 注释）。
        ZPInstallBarBirthHook();
        NSLog(@"[zhplugin] load: birth hook installed at +load (installed=%d)", gBirthHookInstalled);
    } @catch (NSException *e) {
        NSLog(@"[zhplugin] load: birth hook at +load FAILED (will retry at +1s): %@", e);
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
    // 启动已完成、宿主类与 UIApplication 均就绪，再延迟约 1 秒分四段独立安装。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ZPInstall(); });
}
@end
