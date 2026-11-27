// WCBlack.m — 微信深色模式纯黑背景 v8.33 (2026-11-27)：预览页底部操作
// 行已黑、已选缩略图条（MMAssetSelectedCollectionView）还亮着，一并置深。
// v8.32：v8.31 钩错预览
// 页（聊天相册点开的实际是 MMImagePreviewBrowserController），改钩其
// _blurView/_bottomBar。v8.31：发送图片预览页
// （MsgImgPickerPreviewViewController）底部面板发白——该页强制深色、
// 顶栏与照片区都正常，唯独底部 footerBkg 的毛玻璃层落到浅色外观
// （实测整块 #C6C6C6）。在该页 viewDidLayoutSubviews 后把 footerBkg
// 里的 UIVisualEffectView 强制换深色毛玻璃、contentView 盖 bg 模块色。
// v8.30：输入框四角描边
// 比直边粗——描边轮廓比色板大一圈，四角弧线错位露出。两张 field 色板
// （文字框 + 语音胶囊）各外扩 1pt、圆角同步加大，弧线移到描边之外吞掉。
// v8.29：语音模式「按住
// 说话」胶囊并入 field 模块——按钮 MMRecordButton 本体不涂色，灰是其底下
// 的背景图/图层渲染，在按钮内部标题之下放 field 色板盖住（范围按按钮
// 自己的 backgroundRectForBounds:），关模块时随 field 色板统一隐藏。
// v8.28：发现页横线真源头——
// 发现页 FindFriendEntryViewController 不用 WCTableViewManager，自己给每行
// MMTableViewCell 下发 setCustomSeparatorLineEdges:topInset:bottomInset:，
// 该方法由挂在 UITableViewCell 上的 FinderVideoCell 分类实现（宿主类与
// MMTableViewCell 父类是同一个 chained-fixup 绑定，逐字节核对一致），
// 实现按 edges 位往 cell 上加分隔线子视图。在 MMTableViewCell 上加覆盖，
// 「隐藏分割线」开时把 edges 清零再转发，线在源头不生成；朋友圈双闸豁免
// （WCInMomentsFeed + cell 内含 WCTimeLineCellView 的结构闸）。
// v8.27：朋友圈豁免——
// 全局藏线误伤朋友圈帖子间横线（闪一下消失），所有藏线收口点加
// WCInMomentsFeed 闸，朋友圈内一律保持原样。v8.26：按用户要求移除
// 全部诊断代码（计数/抓取/设置页诊断区），藏线逻辑与诊断版完全一致、
// 已由诊断实测确认生效。v8.25：诊断行点击复制全文到剪贴板。v8.24：诊断触发
// 页修正为发现页 FindFriendEntryViewController（v8.23 误认 MoreViewController
// =「我」页）。v8.23：设置页加
// 诊断区，记录钩子计数与发现页首行的视图/图层树。v8.22：drawSeparatorFor:
// 的参数是 cell 管理器不是 cell（v8.21 类型判断落空）；三路找真 cell +
// 钩 willDisplay 补网 + 扫表格本体装饰线。v8.21：交叉引用定案朋友圈
// 行的线是 WCTableViewManager drawSeparatorFor:AtIndexPath:mode: 在显示时
// 才加进 cell 的分隔视图，钩该方法藏线。v8.20：反汇编定案 drawCell:
// 的参数才是被描边的 cell（v8.19 读管理器 _cell 字段清了个空）；输入栏线
// 扩扫整栏子树与外层容器。v8.19：朋友圈行上下线定案
// 是 WCTableViewCellManager 在 drawCell: 里给 cell 图层设的边框，钩该方法清零；
// 输入栏线把指纹藏线扩成递归子树+图层子层。v8.18：补两处无
// ivar 的横线（用户 13:23 截图）：发现页朋友圈行上下两条（MMTable-
// ViewCell，WCTableView 框架按 section 上下线 inset 摆进 cell）、
// 聊天输入框上方一条（MMInputToolView 的 _toolView 顶边）。两处静态
// 查证均无 line ivar 可挂，按几何指纹（高 ≤1pt、宽 ≥85%、贴边）在
// 点名容器的 layout 里藏，受「隐藏分割线」开关管。聊天页切深浅一
// 线已由用户把 chatbar 设为原色自行解决（强涂与翻转天生冲突），
// v8.17 的 toColor 探针刷新与 layout 补扫保留、无害。
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
    dispatch_once(&once, ^{ l = os_log_create("com.nova.wcblack", "v8.33"); });
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
    // v8.18：纯黑走 Display P3 的 (0,0,0)。sRGB (0,0,0,1) 会被系统内化成
    // blackColor 单例，管线里多处拿「== blackColor / 值归零」当「没设值」
    // （本文件 WCModuleForColor 首句即是），全设纯黑时顶栏被当成没设颜色、
    // 回落原装浅色材质（用户实测：全 #000000 顶栏浅灰、全 #090909 正常）。
    // P3 黑渲染与采样都是真 0，但不是那个单例，哨兵不再误伤。
    if (rgb == 0) return [UIColor colorWithDisplayP3Red:0.0 green:0.0 blue:0.0 alpha:1.0];
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
static void WCRefreshDarkState(BOOL fresh);
static void WCScheduleDarkRefresh(void);

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
    // v8.30：色板外扩 1pt、圆角同步 +1——微信的描边画在比输入框大一圈的
    // 轮廓上：直边处与色板齐平、只露 1px（实测灰度 28）；四角两条弧线
    // 错位，露出的弧段显得更粗（语音模式角上实测达 44）。色板外扩后
    // 弧线移到描边之外，整圈吞掉。grow 不裁子视图（v5.3 话筒光晕能
    // 探出右界），外扩部分不会被裁掉。
    CGRect pf = CGRectInset(grow.bounds, -1, -1);
    if (!CGRectEqualToRect(plate.frame, pf)) plate.frame = pf;
    CGFloat pr = (grow.layer.cornerRadius > 0 ? grow.layer.cornerRadius : 8) + 1;
    if (plate.layer.cornerRadius != pr) plate.layer.cornerRadius = pr;
    plate.hidden = NO;
}
// v8.29：语音模式的「按住 说话」胶囊并入 field 模块（用户 19:39 点名）。
// 按钮本体是 MMRecordButton（MMTransparentButton→MMUIButton 系），全链
// 不涂背景色；那片 #2C2C2C 是它底下的背景图/图层渲染，WCFieldScan 只认
// backgroundColor、够不着——与文字模式 v5.2 同构。不抢它的渲染：在按钮
// 内部、标题标签正下方放一张 field 色板盖住，范围按按钮自己的
// backgroundRectForBounds:（胶囊有水平 outset），每拍重申位置；
// 登记进 WCFieldPlates，关模块/浅色时由 sweep 的还原分支统一隐藏。
static void WCEnsureRecordPlate(UIView *btn) {
    UIColor *cfg = WCConfigColor(@"field");
    if (!cfg) return;
    UIView *plate = objc_getAssociatedObject(btn, &kWCUnderlayKey);
    if (!plate) {
        plate = [[UIView alloc] initWithFrame:btn.bounds];
        plate.userInteractionEnabled = NO;
        plate.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        plate.clipsToBounds = YES;
        objc_setAssociatedObject(btn, &kWCUnderlayKey, plate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [WCFieldPlates() addObject:plate];
        [plate release];
    }
    CGRect br = [btn isKindOfClass:[UIButton class]] ? [(UIButton *)btn backgroundRectForBounds:btn.bounds] : btn.bounds;
    if (br.size.width <= 0 || br.size.height <= 0) br = btn.bounds;
    UIView *label = [btn isKindOfClass:[UIButton class]] ? [(UIButton *)btn titleLabel] : nil;
    NSInteger li = (label && label.superview == btn) ? (NSInteger)[btn.subviews indexOfObject:label] : -1;
    NSInteger want = (li >= 0) ? li - 1 : (NSInteger)btn.subviews.count - 1;
    NSInteger pi = (plate.superview == btn) ? (NSInteger)[btn.subviews indexOfObject:plate] : -1;
    if (plate.superview != btn || pi != want) {
        [plate removeFromSuperview];
        NSInteger at = (li >= 0) ? li : (NSInteger)btn.subviews.count;
        [btn insertSubview:plate atIndex:at];
    }
    // v8.30：同文字模式——色板外扩 1pt，弧线移到按钮描边之外吞掉四角。
    CGRect pf = CGRectInset(br, -1, -1);
    if (!CGRectEqualToRect(plate.frame, pf)) plate.frame = pf;
    CGFloat radius = pf.size.height / 2;
    if (plate.layer.cornerRadius != radius) plate.layer.cornerRadius = radius;
    if (plate.backgroundColor != cfg) plate.backgroundColor = cfg;
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
    else if ([NSStringFromClass([root class]) isEqualToString:@"MMRecordButton"]) { WCEnsureRecordPlate(root); }
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
    // 深浅认探针，不看栏 trait（v8.15）。此前用 bar.traitCollection 判：进聊天时
    // WCForceBar 是先 sweep 再钉 override，sweep 那一刻栏还是系统浅色 trait，
    // 直接走还原分支、输入框不上色；要等 5 秒家务 tick 再 sweep 时 trait 已
    // 被钉成深色才补上——用户实测：进聊天后输入框过了会才变成设置色 #0F0F0F。
    BOOL dark = gWCWeChatDark;
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

static IMP WCSwapOwn(Class cls, SEL sel, IMP newImp);
// v8.18：没有 ivar 的线（用户 13:23 两张截图）。发现页朋友圈行上下两条、
// 聊天输入框上方一条——静态查证：MMInputToolView 无任何 line ivar/方法；
// 发现页行是 MMTableViewCell（WCTableView 框架），线由框架按
// WCTableViewSectionManager 的上下线 inset 摆进 cell 层级、同样无 ivar。
// 这类线只能按几何指纹认：高 ≤1pt、宽 ≥85%、贴宿主上/下边。只在两个
// 点名容器上跑（MMTableViewCell 全家 + 输入栏 _toolView），受同一个
// 「隐藏分割线」开关管。
static BOOL WCIsHairlineFrame(CGRect f, CGFloat W) {
    return f.size.height > 0 && f.size.height <= 1.0 && f.size.width >= W * 0.85;
}
static void WCHideEdgeLines(UIView *host) {
    if (!host) return;
    CGFloat W = host.bounds.size.width, H = host.bounds.size.height;
    if (W < 50 || H < 8) return;
    for (UIView *v in host.subviews) {
        if (v.hidden) continue;
        if ([v isKindOfClass:[UILabel class]] || [v isKindOfClass:[UIControl class]]) continue;
        CGRect f = v.frame;
        if (!WCIsHairlineFrame(f, W)) continue;
        if (f.origin.y <= 1.0 || (f.origin.y + f.size.height) >= H - 1.0) v.hidden = YES;
    }
}
// v8.19：v8.18 实测零变化——反汇编 WCTableViewCellManager 的 drawCell:
// 定案：朋友圈行的上下线根本不是子视图，是框架在 drawCell: 里给 cell 的
// layer 设的 borderWidth+borderColor（配 mask+圆角画出整段卡片边框）。
// 藏视图永远够不着图层边框。改法：钩 drawCell: 本体（框架自己的上色点），
// orig 跑完立刻把边框宽清零；cell 的 layout 再兜一遍防重设。
// 输入栏那条同理扩围：线可能在 _toolView 子树深层或其图层子层上，
// 指纹藏线改为递归整棵子树 + 扫图层子层。
// v8.27：朋友圈豁免（用户 18:28 定界）。发现页行框线去掉，但朋友圈里面
// 的分隔要保持原样——v8.26 及之前被全局藏线误伤：WC_TV_layout 对每张表
// 都压 separatorStyle=None、WCApplySeparators 与普查钩子也不分页面，
// 朋友圈帖子间的横线被连带藏掉（滚动时先闪一下再消失）。判定：视图在
// WCTimeLineCellView 之内，或所属表格归 WCBaseTimelineViewController 管。
// 藏线的所有收口点都先过这道闸。
static BOOL WCInMomentsFeed(UIView *v) {
    static Class tlCellCls = Nil, tlVcCls = Nil;
    if (!tlCellCls) {
        tlCellCls = NSClassFromString(@"WCTimeLineCellView");
        tlVcCls = NSClassFromString(@"WCBaseTimelineViewController");
    }
    UIView *cur = v;
    UITableView *tv = nil;
    while (cur) {
        if (tlCellCls && [cur isKindOfClass:tlCellCls]) return YES;
        if (!tv && [cur isKindOfClass:[UITableView class]]) tv = (UITableView *)cur;
        cur = cur.superview;
    }
    if (tv && tlVcCls) {
        UIResponder *r = tv;
        while (r) {
            if ([r isKindOfClass:tlVcCls]) return YES;
            r = [r nextResponder];
        }
    }
    return NO;
}
static void WCHideEdgeLinesDeep(UIView *host, int depth) {
    if (!host || WCInMomentsFeed(host)) return;
    WCHideEdgeLines(host);
    CGFloat W = host.bounds.size.width, H = host.bounds.size.height;
    if (W >= 50 && H >= 8) {
        for (CALayer *l in host.layer.sublayers) {
            if (l.hidden) continue;
            CGRect f = l.frame;
            if (!WCIsHairlineFrame(f, W)) continue;
            if (f.origin.y <= 1.0 || (f.origin.y + f.size.height) >= H - 1.0) l.hidden = YES;
        }
    }
    if (depth <= 0) return;
    for (UIView *v in host.subviews) WCHideEdgeLinesDeep(v, depth - 1);
}
static void WCZeroBordersInCell(UITableViewCell *c) {
    if (!c || WCInMomentsFeed(c)) return;
    c.layer.borderWidth = 0;
    if (c.backgroundView) c.backgroundView.layer.borderWidth = 0;
    if (c.contentView) c.contentView.layer.borderWidth = 0;
    Ivar iv = class_getInstanceVariable([c class], "m_subContentView");
    if (iv) {
        const char *enc = ivar_getTypeEncoding(iv);
        if (enc && enc[0] == '@') {
            id sub = object_getIvar(c, iv);
            if ([sub isKindOfClass:[UIView class]]) ((UIView *)sub).layer.borderWidth = 0;
        }
    }
}
// 诊断结论（v8.23–v8.25 诊断版实测，v8.26 起移除诊断代码）：朋友圈行上下线
// 是 cell 本人最后两个子视图 + 本层两个子图层（高 0.3、全宽、贴上下边），
// 由 drawSeparatorFor: 在 willDisplay 时加进来，现行钩子链能把它们置隐藏。
// 早先诊断截图里 drawSep/cellLayout 计数为 0 是抓取时机太早，不是钩子没装。
static IMP gO_MMCellLayout;
static void WC_MMCell_layout(UITableViewCell *s, SEL c) {
    ((void (*)(id, SEL))gO_MMCellLayout)(s, c);
    if (!WCHideSep()) return;
    WCZeroBordersInCell(s);
    WCHideEdgeLinesDeep(s, 4);
}
static void WCInstallMMCellHook(void) {
    Class c = NSClassFromString(@"MMTableViewCell");
    if (c && !gO_MMCellLayout) gO_MMCellLayout = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_MMCell_layout);
}
// v8.28：发现页自定义分隔线的源头钩（定案见文件头）。方法签名按包内类型
// 编码 v88@0:8Q16{UIEdgeInsets}24{UIEdgeInsets}56 复原：
// -(void)setCustomSeparatorLineEdges:(NSUInteger)edges topInset:(UIEdgeInsets)top bottomInset:(UIEdgeInsets)bottom
// 发现页控制器已查实不直调 addCustomBottomSeparatorLineWithInset:，
// 线全走这一处下发，钩这一处即够。
static IMP gO_CustomSep;
static Class gWCTimeLineCellViewCls;
static BOOL WCViewTreeHasClass(UIView *v, Class cls, int depth) {
    if (!v || !cls) return NO;
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:cls]) return YES;
        if (depth > 0 && WCViewTreeHasClass(s, cls, depth - 1)) return YES;
    }
    return NO;
}
static void WC_Cell_setCustomSep(UITableViewCell *s, SEL c, NSUInteger edges, UIEdgeInsets top, UIEdgeInsets bottom) {
    if (WCHideSep() && !WCInMomentsFeed(s) && !WCViewTreeHasClass(s, gWCTimeLineCellViewCls, 4)) edges = 0;
    ((void (*)(id, SEL, NSUInteger, UIEdgeInsets, UIEdgeInsets))gO_CustomSep)(s, c, edges, top, bottom);
}
static void WCInstallCustomSepHook(void) {
    Class c = NSClassFromString(@"MMTableViewCell");
    if (!gWCTimeLineCellViewCls) gWCTimeLineCellViewCls = NSClassFromString(@"WCTimeLineCellView");
    if (c && !gO_CustomSep) gO_CustomSep = WCSwapOwn(c, @selector(setCustomSeparatorLineEdges:topInset:bottomInset:), (IMP)WC_Cell_setCustomSep);
}
static IMP gO_MgrDrawCell;
static void WC_Mgr_drawCell(id s, SEL c, id arg) {
    ((void (*)(id, SEL, id))gO_MgrDrawCell)(s, c, arg);
    if (!WCHideSep()) return;
    // v8.20：反汇编 drawCell: 定案——参数就是被上色的 cell 本人，边框设在
    // arg.contentView.layer（宽 1/屏幕缩放、色取管理器 borderColor）。
    // v8.19 读管理器的 _cell ivar，那个字段在 drawCell: 时不指向这只 cell，
    // 清了个空，所以实测零变化。改以参数为准，_cell 只作兜底。
    UITableViewCell *cell = nil;
    if ([arg isKindOfClass:[UITableViewCell class]]) cell = (UITableViewCell *)arg;
    if (!cell) {
        Ivar iv = class_getInstanceVariable([s class], "_cell");
        if (iv) {
            const char *enc = ivar_getTypeEncoding(iv);
            if (enc && enc[0] == '@') {
                id v = object_getIvar(s, iv);
                if ([v isKindOfClass:[UITableViewCell class]]) cell = (UITableViewCell *)v;
            }
        }
    }
    if (!cell) return;
    WCZeroBordersInCell(cell);
    WCHideEdgeLinesDeep(cell, 4);
}
static void WCInstallMgrHook(void) {
    Class c = NSClassFromString(@"WCTableViewCellManager");
    if (c && !gO_MgrDrawCell) gO_MgrDrawCell = WCSwapOwn(c, @selector(drawCell:), (IMP)WC_Mgr_drawCell);
}
// v8.21：交叉引用扫描定案——WCTableView 的分隔线根本不是 drawCell: 画的，
// 是表格管理器 WCTableViewManager 的 drawSeparatorFor:AtIndexPath:mode:
// 专门画的：它取一只分隔线视图（getSeparator）、按区段的上下线 inset 摆位、
// addSubview 进 cell。它在 willDisplay 时才调用，我之前的钩子（drawCell:/
// layout）全在它之前跑完，所以线每次都后脚出现、纹丝不动。钩它本人：
// orig 画完立刻在同一只 cell 上按指纹藏线，时机严丝合缝。
// v8.22：v8.21 又落空——drawSeparatorFor: 的第一个参数根本不是 cell，
// 是 cell 的管理器（它被发了 seperateLineMode，只可能是管理器），我的
// isKindOfClass:[UIView] 判断直接落空、什么都没干。这版三路找真 cell：
// 参数本身是视图就用它；否则读管理器的 _cell 字段；再否则用管理器的
// tableView 按 indexPath 现查。再加一道网：钩管理器自己的
// tableView:willDisplayCell:forRowAtIndexPath:（画线就是从这儿发起的，
// 参数里带真 cell），orig 回来后对真 cell 藏线，并扫一遍表格本体的
// 装饰线（线也可能被加在表格而不是 cell 上）。
static void WC_HideTableDecorations(UITableView *tv) {
    if (!tv || WCInMomentsFeed(tv)) return;
    CGFloat W = tv.bounds.size.width;
    if (W < 50) return;
    for (UIView *v in tv.subviews) {
        if (v.hidden) continue;
        if ([v isKindOfClass:[UITableViewCell class]]) continue;
        if ([v isKindOfClass:[UILabel class]] || [v isKindOfClass:[UIControl class]]) continue;
        if (WCIsHairlineFrame(v.frame, W)) v.hidden = YES;
    }
    for (CALayer *l in tv.layer.sublayers) {
        if (l.hidden) continue;
        if (WCIsHairlineFrame(l.frame, W)) l.hidden = YES;
    }
}
static IMP gO_MgrDrawSep;
static void WC_Mgr_drawSep(id s, SEL c, id info, id ip, NSInteger mode) {
    ((void (*)(id, SEL, id, id, NSInteger))gO_MgrDrawSep)(s, c, info, ip, mode);
    if (!WCHideSep()) return;
    UIView *host = nil;
    if ([info isKindOfClass:[UIView class]]) host = (UIView *)info;
    if (!host && info) {
        Ivar iv = class_getInstanceVariable([info class], "_cell");
        if (iv) {
            const char *enc = ivar_getTypeEncoding(iv);
            if (enc && enc[0] == '@') {
                id v = object_getIvar(info, iv);
                if ([v isKindOfClass:[UIView class]]) host = (UIView *)v;
            }
        }
    }
    if (host) WCHideEdgeLinesDeep(host, 4);
    if ([s respondsToSelector:@selector(tableView)]) {
        id tv = [s performSelector:@selector(tableView)];
        if ([tv isKindOfClass:[UITableView class]]) {
            if (!host && ip) {
                id cell = [(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip];
                if ([cell isKindOfClass:[UIView class]]) WCHideEdgeLinesDeep((UIView *)cell, 4);
            }
            WC_HideTableDecorations((UITableView *)tv);
        }
    }
}
static IMP gO_MgrWillDisplay;
static void WC_Mgr_willDisplay(id s, SEL c, UITableView *tv, UITableViewCell *cell, NSIndexPath *ip) {
    ((void (*)(id, SEL, id, id, id))gO_MgrWillDisplay)(s, c, tv, cell, ip);
    if (!WCHideSep()) return;
    if (cell) WCHideEdgeLinesDeep(cell, 4);
    WC_HideTableDecorations(tv);
}
static void WCInstallSepDrawHook(void) {
    Class c = NSClassFromString(@"WCTableViewManager");
    if (!c) return;
    if (!gO_MgrDrawSep) gO_MgrDrawSep = WCSwapOwn(c, @selector(drawSeparatorFor:AtIndexPath:mode:), (IMP)WC_Mgr_drawSep);
    if (!gO_MgrWillDisplay) gO_MgrWillDisplay = WCSwapOwn(c, @selector(tableView:willDisplayCell:forRowAtIndexPath:), (IMP)WC_Mgr_willDisplay);
}

static void WCSepTryMarkViaResponder(UITableView *tv);
static void WCApplySeparators(UITableView *tv) {
    WCSepTryMarkViaResponder(tv);
    BOOL hide = WCHideSep();
    if (hide && WCInMomentsFeed(tv)) hide = NO; // 朋友圈豁免：走恢复分支
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
    // v8.18：全局拦截，不再只限首页表
    if (style != UITableViewCellSeparatorStyleNone && WCHideSep()) {
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

// v8.18 全局分割线（用户要求：遍历微信所有分割线设计、去掉、不能有闪）：
// 静态普查完整二进制 46,673 个类，带 separator 视图 ivar 的类 255 个、301 条
// ivar（名单内嵌于下）。给这些类逐个钩 layoutSubviews（控制器类钩
// viewDidLayoutSubviews），原实现跑完就在同一次排版里按 ivar 把线藏掉——线
// 在摆出的同一帧被藏，冷启动也不闪。再加 UITableView 两道：setSeparatorStyle:
// 全局拦截（不再只限首页），layoutSubviews 开头把没走 setter 的默认样式表也
// 压成 None（原排版之前执行，线根本不会被摆出来）。
static NSMutableDictionary<NSString *, NSArray<NSString *> *> *gSepCensusIvars;
static NSMutableDictionary<NSString *, NSValue *> *gSepCensusOrigs;
static NSMutableSet<NSString *> *gSepCensusDone;
@interface WCSepPlan : NSObject
@property (nonatomic, assign) IMP orig;
@property (nonatomic, retain) NSArray<NSValue *> *ivars;
@property (nonatomic, assign) NSUInteger gen;
@end
@implementation WCSepPlan
@end
static NSMapTable *gSepPlans;
static NSUInteger gSepGen = 0;
static void WCSepHideIvars(id obj, Class regCls, NSArray<NSString *> *names);

static BOOL WCSepIvarIsViewLike(Ivar iv) {
    const char *te = ivar_getTypeEncoding(iv);
    if (!te || te[0] != '@' || te[1] != '"') return NO;
    const char *p = te + 2;
    const char *q = strchr(p, '"');
    if (!q || q == p) return NO;
    NSString *cn = [[NSString alloc] initWithBytes:p length:(NSUInteger)(q - p) encoding:NSUTF8StringEncoding];
    Class tc = cn ? NSClassFromString(cn) : Nil;
    [cn release];
    if (!tc) return NO;
    return [tc isSubclassOfClass:[UIView class]] || [tc isSubclassOfClass:[CALayer class]] || [tc isSubclassOfClass:[NSArray class]];
}
static WCSepPlan *WCBuildSepPlan(id s, SEL c) {
    WCSepPlan *plan = [[WCSepPlan alloc] init];
    plan.gen = gSepGen;
    NSMutableArray<NSValue *> *ivs = [NSMutableArray array];
    IMP origToCall = NULL;
    Class k = object_getClass(s);
    while (k) {
        NSString *kn = NSStringFromClass(k);
        NSArray<NSString *> *names = gSepCensusIvars[kn];
        if (names) {
            // 只认本类自己声明的 ivar、且类型编码验明是视图/层/数组才收：
            // v8.11 按名跨类取 ivar，同名类/同名异类 ivar 会取到 BOOL 槽，
            // object_getIvar 读出 0x1 再 isKindOfClass 直接崩（07:28 崩溃定案）。
            unsigned int ic = 0;
            Ivar *list = class_copyIvarList(k, &ic);
            for (unsigned int j = 0; j < ic; j++) {
                const char *inm = ivar_getName(list[j]);
                if (!inm) continue;
                if ([names containsObject:[NSString stringWithUTF8String:inm]] && WCSepIvarIsViewLike(list[j]))
                    [ivs addObject:[NSValue valueWithPointer:list[j]]];
            }
            if (list) free(list);
            if (!origToCall) {
                NSValue *v = gSepCensusOrigs[kn];
                if (v && v != (id)[NSNull null]) origToCall = [v pointerValue];
            }
        }
        k = class_getSuperclass(k);
    }
    if (!origToCall) origToCall = class_getMethodImplementation(object_getClass(s), c);
    plan.orig = origToCall;
    plan.ivars = ivs;
    if (!gSepPlans) gSepPlans = [[NSMapTable mapTableWithKeyOptions:(NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality) valueOptions:NSPointerFunctionsStrongMemory] retain];
    [gSepPlans setObject:plan forKey:object_getClass(s)];
    [plan release];
    return plan;
}
static void WC_Sep_layout(id s, SEL c) {
    WCSepPlan *plan = [gSepPlans objectForKey:object_getClass(s)];
    if (!plan || plan.gen != gSepGen) plan = WCBuildSepPlan(s, c);
    if (plan.orig) ((void (*)(id, SEL))plan.orig)(s, c);
    BOOL hide = WCHideSep();
    if (hide) { // 朋友圈豁免：相关类名一律不藏，实例在朋友圈内也不藏
        NSString *cn = NSStringFromClass([s class]);
        if ([cn hasPrefix:@"WCMoments"] || [cn hasPrefix:@"WCTimeLine"] || [cn hasPrefix:@"WCBaseTimeline"]) hide = NO;
        else if ([s isKindOfClass:[UIView class]] && WCInMomentsFeed((UIView *)s)) hide = NO;
    }
    for (NSValue *v in plan.ivars) {
        id val = object_getIvar(s, (Ivar)[v pointerValue]);
        if (!val || (uintptr_t)val < 0x10000 || ((uintptr_t)val & 0x7) != 0) continue;
        if ([val isKindOfClass:[UIView class]]) ((UIView *)val).hidden = hide;
        else if ([val isKindOfClass:[CALayer class]]) ((CALayer *)val).hidden = hide;
        else if ([val isKindOfClass:[NSArray class]])
            for (id el in (NSArray *)val) if ([el isKindOfClass:[UIView class]]) ((UIView *)el).hidden = hide;
    }
}
static IMP gOrigTVLayout;
static void WC_TV_layout(UITableView *s, SEL c) {
    if (WCHideSep() && !WCInMomentsFeed(s) && s.separatorStyle != UITableViewCellSeparatorStyleNone)
        s.separatorStyle = UITableViewCellSeparatorStyleNone;
    ((void (*)(id, SEL))gOrigTVLayout)(s, c);
}
static void WCInstallSepCensus(void) {
    if (!gSepCensusDone) {
        gSepCensusDone = [[NSMutableSet alloc] init];
        gSepCensusIvars = [[NSMutableDictionary alloc] init];
        gSepCensusOrigs = [[NSMutableDictionary alloc] init];
    }
    static const char *kSepCensus[] = {
	"BTRecoFlowCanvasCell|_bottomSeparatorView",
	"BTRecoFlowMsgCell|_bottomSeparatorView",
	"BTRecoFlowTopicMsgCell|_topSeparatorView,_bottomSeparatorView",
	"BizAppReaderMessageBigPicView|_separator",
	"BraceletRankInfoView|_separatorLine",
	"BraceletRankInfoViewV2|_separatorLine",
	"BraceletWorkoutCreateSheetView|_infoSeparator,_reminderTimeSeparator",
	"BrandCustomSharePanelSectionFooterView|_separator",
	"BrandMyTabEntranceCardView|_horizontalSeparator",
	"BrandMyTabEntranceCardNotify|_topSeparator",
	"BrandMyTabEntranceCardButtons|_verticalSeparator",
	"BrandProfileShopCardView|_recommendSeparator",
	"BrandProfileProductCardView|_recommendSeparator",
	"BrandProfileUrgePublishUserCell|_separatorView",
	"CBTAsstBoardSendConfirmCellView|_separatorLine",
	"CBTAsstBottomPanel|_topSeparatorLine,_attachmentSeparatorLine,_separatorLine,_bottomSeparatorLine",
	"CBTAsstMemoryActionDialogView|_horizontalSeparatorView,_verticalSeparatorView",
	"CBTAsstMemoryItemCell|_separatorView",
	"CBTAsstMemoryRecentCell|_separatorView",
	"CBTAsstMemoryTopicCell|_separatorView",
	"CBTAsstMemoryTopicViewController|_titleSeparatorView",
	"CBTAsstTalkingView|_navSeparatorView",
	"CBTAttachmentCodeBlockView|_topSeparator,_bottomSeparator",
	"CBTAttachmentMathBlockView|_topSeparatorLine,_bottomSeparatorLine",
	"CBTContactRowView|_separatorView",
	"CBTCoopV2CommNativeCellView|_separatorViews",
	"CBTCoopV2FinderCellView|_separator",
	"CBTGroupRowView|_separatorView",
	"CBTMomentContentTableViewCell|_likeListTopSeparator,_commentViewListTopSeparator",
	"CBTRefSourceCellContentView|_suppressSeparatorForLayout,_separatorLine",
	"CBTReferenceSourceSheet|_topSeparatorLine",
	"CameraQRCodeMyQRCodeModuleView|_addNewFriendSeparatorLine",
	"ChatBotHistoryEnterRoomCell|_separatorLine",
	"ChatBotVOIPMainView|_separatorLabel",
	"ChatBotVoIPAskAIAsstTalkingView|_separator",
	"ChatRoomInvitationMultiMenuTableViewCell|_separatorLineView",
	"ContactsImportTableViewCell|_separatorView",
	"EditImageMosaicToolAttrView|_separatorView",
	"EditImagePenToolAttrView|_needSeparator,_separator",
	"EditImageXiaoWeiEntryController|_toolBarSeparatorLine",
	"EmoticonLensMoreHeaderView|_topSeparator",
	"EmoticonLensMoreView|_navBarSeparator",
	"EmoticonStoreLensDesignerView|_separatorView",
	"EnterpriseSearchContactCell|_separatorBottomView",
	"FakeMainFrameCell|_separatorLine",
	"FavSelectedItemsSheetView|_navigationSeparator",
	"GameLifeNotifyInteractiveMsgCell|_separator",
	"KidsWatchInfoCellView|_separatorView",
	"MJComposingCreationCamPreviewController|_bottomLinkSeparatorView",
	"MJSegmentCellBorderView|_separatorLineLayer",
	"MJThumbnailTileLayer|_separatorLineBounds,_separatorLineLayer",
	"MJTimeCostReporterService|_keySeparator",
	"MJTimecodeView|_separatorLabel",
	"MMAlbumDropPickerCell|_separatorView",
	"MMBGMSelectedTabTableLyricCell|_separator",
	"MMBGMSelectedTabTableViewCell|_separatorLine",
	"MMBottomToolView|_separators,_separatorSize",
	"MMDatePickerHalfSheetView|_separatorLabel",
	"MMEasterEggNewYearActivityViewController|_separatorView",
	"MMFinderLiveAnchorGoodsCell|_actionButtonSeparatorLine",
	"MMFinderLiveAnchorRealNameLikeListTableViewCell|_separatorLine",
	"MMFinderLiveAnchorRealNameLikeListViewController|_recommendSeparator",
	"MMFinderLiveCastItemCell|_topSeparatorLine,_bottomSeparatorLine",
	"MMFinderLiveChooseModeView|_separatorLine",
	"MMFinderLiveCompleteViewReplaySettingsCheckboxCell|_separatorBar",
	"MMFinderLiveConcertTicketView|_separatorBarView",
	"MMFinderLiveConcertTicketViewController|_bottomButtonsSeparators",
	"MMFinderLiveConnectMicAudienceApplyPageSheet|_separatorBar",
	"MMFinderLiveConnectMicAudienceApplyPageSheetTableViewCell|_separatorBar",
	"MMFinderLiveConnectMicConditionCell|_separator",
	"MMFinderLiveConnectMicExtendedPkSelectAnchorParticipatingTableViewCell|_separatorBar",
	"MMFinderLiveConnectMicExtendedPkSelectDurationTableViewCell|_separatorBar",
	"MMFinderLiveConnectMicExtendedPkSelectTableViewCell|_separatorBar",
	"MMFinderLiveConnectMicModePageSheetNavigatingCell|_separatorBar",
	"MMFinderLiveConnectMicModePageSheetSecondaryHeaderTableViewCell|_separatorBar",
	"MMFinderLiveConnectMicModePageSheetSwitchCell|_separatorBar",
	"MMFinderLiveConnectMicModePageSheetUsersTableViewCell|_separatorBar",
	"MMFinderLiveConnectMicPkDesignatedGiftSelectionTableViewCell|_separatorBar",
	"MMFinderLiveConnectMicPkDurationSelectionPageSheet|_separatorBar",
	"MMFinderLiveConnectMicPkPanelTeamupNumberCell|_bottomSeparatorLine",
	"MMFinderLiveConnectMicSelectConnectModeCell|_separatorLine",
	"MMFinderLiveConnectedMicBaseCellHeaderView|_bottomSeparatorLine",
	"MMFinderLiveConnectedMicHintBaseViewCell|_separatorBar",
	"MMFinderLiveConnectedMicBaseUserCellView|_bottomSeparatorLine",
	"MMFinderLiveFansGroupMemberTableViewCell|_separatorLine",
	"MMFinderLiveFeedFriendsLikeListTableViewCell|_separatorLine",
	"MMFinderLiveGiftStarRankCell|_separator",
	"MMFinderLiveGiftStarGiftDetailPanel|_meBarSeparator",
	"MMFinderLiveGiftStarLightAllCell|_separator",
	"MMFinderLiveGoodsCell|_topSeparatorLine,_bottomSeparatorLine",
	"MMFinderLiveGoodsSelectionPanel|_topSeparatorLine",
	"MMFinderLiveMusicRelatedSettingTableFooterView|_separatorLeftMargin,_customSeparatorView",
	"MMFinderLiveNewMusicRequestedSongPanel|_headerSeparator",
	"MMFinderLiveNoticePromoteListTableViewCell|_horizontalSeparatorBar",
	"MMFinderLiveOnlineStateCollectionViewCell|_separatorLine",
	"MMFinderLivePaymentTrialModeCell|_separatorLine",
	"MMFinderLivePaymentTrialModeSettingView|_separatorLine",
	"MMFinderLiveRecentRewardCollectionCell|_needSeparatorLine,_separatorLine",
	"MMFinderLiveShopInfoEcShopTailView|_separator",
	"MMFinderLiveTestLiveInfoConfirmSheetRowView|_separatorView",
	"MMFinderLiveTopicEducationNotifyPlaceholderView|_footerSeparator",
	"MMFinderLiveInteractionWishProgressView|_rankSeparatorLine",
	"MMFinderLiveInteractionWishOperationView|_rankSeparatorLine",
	"MMLimitedModeBizCell|_separatorView",
	"MMLimitedModeIndependentVerifyViewController|m_separatorLine",
	"MMListCellConfig|_separatorConfig",
	"MMLiveBeautyFineTuningControlPanelGroupSeparator|_separatorView",
	"MMLiveCompleteStatisticsView|_horizontalSeparatorBar,_verticalSeparatorBar",
	"MMLiveGenerateReplaySettingSubSwitchCellView|_topSeparatorLine",
	"MMLiveMentionContactListTableViewCell|_separatorLine",
	"MMLiveRewardGiftCustomizationTipView|_separatorBar",
	"MMMLiveRewardQuotaSettingDetailCell|_separatorLine",
	"MMLiveRewardQuotaSettingSheetView|_topSeparatorLine,_footerSeparatorLine",
	"MMLiveStartLotteryNoticeOptionView|_separatorBar",
	"MMLiveSyndicateIntroductionPageSheet|_settlementSettingsTopSeparator,_settlementSettingsBottomSeparator",
	"MMLiveSyndicateManagementContactCell|_separator",
	"MMLiveSyndicateManagementPageSheet|_buttonsSeparator",
	"MMLiveSyndicateManagementQrCell|_separator",
	"MMLiveSyndicateParticipantManagementPageSheet|_buttonsSeparator",
	"MMMsgContentNavBar|_separatorView",
	"MMMsgTipsExpandMultiHeadCardView|_separatorLineView",
	"MMNewMsgContentNavBar|_separatorView",
	"MMOrderCenterOrderSearchHistoryTableViewClearCell|_separatorBarView",
	"MMOrderCenterOrderSearchHistoryTableViewItemCell|_separatorBarView",
	"MMOrderCenterTableViewCellFinderRefererView|_separatorBarView",
	"MMPickLocationContentView|_recentSentSeparatorLabel",
	"MainFrameSectionFoldView|_topSeparatorView,_bottomSeparatorView",
	"MassSendMessageCellView|m_separatorView",
	"CellSourceView|_separatorLineView",
	"MiniTaskCollectionScheduleCell|_separatorView",
	"MultiDeviceCardManageContentView|_headerSeparator,_footerSeparator",
	"MutiSessionCell|_bottomSeparatorView",
	"NewMainFrameCell|_separatorLine",
	"PendantPreviewSelectViewCell|_separatorView",
	"QMCPremadeRouteItemView|_separatorLine",
	"RoamPackageCreateDeviceCell|_uiSeparator",
	"SelectSubContactCell|_bottomSeparatorView",
	"SessionSelectSectionFoldView|_topSeparatorView,_bottomSeparatorView",
	"SettingChatLogCell|_bannerSeparatorView",
	"SolitaireInfoObj|_nsSeparator",
	"SolitaireItem|_nsSeparator",
	"SolitaireObj|_nsSeparator",
	"TextStateFriendSquareSectionFooterView|_separatorView",
	"TextStateFullScreenCardContentView|_iconSourceSeparator,_defaultHeadImageSourceSeparator",
	"TextStateProfileCardContentView|_topSeparator,_iconSourceSeparator",
	"TextStatePublishCustomIconView|_verticalSeparator",
	"TextStatePublishRecentUseIconItemView|_separatorView",
	"TextStateSquareButton|_separatorView",
	"TranslateFunctionButton|_separatorLine",
	"SelectLanguageButton|_separatorView",
	"VoiceReminderConfirmCellView|m_separatorView",
	"WAAgentInputNewPanel|_topSeparatorLine,_attachmentSeparatorLine",
	"WAPNAuthUnbindViewController|_topSeparator,_bottomSeparator",
	"WCAccountSignMethodSwitchViewController|_separatorTextLabel,_separatorLineView",
	"WCAdCountdownView|_timeSeparator1Label,_timeSeparator2Label",
	"WCAdDynamicFeedSeparatorView|_separatorLine",
	"WCAdDynamicFeedElementInfo|_separatorDirection",
	"WCBaseTimelineViewController|_holdSpeakSeparator",
	"WCC2CPlayerProgressBar|_separatorLine,_separatorLineForTracking",
	"WCCanvasComponentItem|_separatorInfo",
	"WCCommentDetailViewControllerFB|_holdSpeakSeparator,_topSeparatorLine",
	"WCCommentMultiImagesBrowseViewController|_holdSpeakSeparator",
	"WCDataItem|_isNewDataSeparator",
	"WCEcsShopCardViewBuildConfig|_secondLineSeparatorMargin,_shopBrand2ShopDescSeparatorLength",
	"WCEcsWindowCardViewBuildConfig|_secondLineSeparatorMargin,_shopBrand2ShopDescSeparatorLength",
	"WCFinderAdPromotionButton|_separatorLine",
	"WCFinderAggregatedMentionCell|_separatorLine",
	"WCFinderCollectionFeedItemContentView|_separatorView",
	"WCFinderCommentDetailViewController|_commentAttachmentSeparatorView",
	"WCFinderContactListCell|_separator",
	"WCFinderFansListViewCell|_separator",
	"WCFinderFeedContentVM|_hideSeparatorLine",
	"WCFinderFeedDetailSectionFooterView|_separatorView",
	"WCFinderFeedFavListCollectionViewCell|_separatorLine",
	"WCFinderFeedFavListGuideView|_separatorLine",
	"WCFinderFeedFriendsLikeListTableViewCell|_separatorLine",
	"WCFinderFeedHighlightsPanel|_separatorLine",
	"WCFinderFeedInputView|_commentAttachmentSeparatorView",
	"WCFinderFeedLikeListCollectionViewCell|_separatorLine",
	"WCFinderStreamFeedLikeGuideView|_separatorLine",
	"WCFinderFeedSubtitleSettingTableViewCell|_separatorLine",
	"WCFinderFullInteractivePanelView|_pagLinkTimeSeparator",
	"WCFinderGameLiveListCell|_separator",
	"WCFinderGameLiveListContentView|_separator",
	"WCFinderGameLiveTabPageHeaderView|_separatorLine",
	"WCFinderHalfProfileInteractionInfoView|_separator",
	"WCFinderHelpPromotionUserCell|_separatorLine",
	"WCFinderHighEntropyFeedCell|_separatorView",
	"WCFinderHighEntropyPlaceholderCell|_bottomSeparator",
	"WCFinderInteractionCommentRecordContentView|_separator",
	"WCFinderItemCollectionCellView|_separator",
	"WCFinderLandScapeVideoView|_topSeparator",
	"WCFinderLiveCompleteLiveContentView|_livePreviewBottomSeparator",
	"WCFinderLiveRosterSelectCell|_separator",
	"WCFinderLiveStartLiveSectionCell|_postSeparatorLine,_bottomSeparatorLine",
	"WCFinderLocationLbsTableViewCell|_separatorLine",
	"WCFinderMSActivityLikeListCell|_bottomSeparatorLine",
	"WCFinderMSActivityTopBlankCell|_separatorLine",
	"WCFinderMemberShipCollectionTableViewCell|_topSeparatorLine,_bottomSeparatorLine",
	"WCFinderMemberShipSearchResultCell|_separatorView",
	"WCFinderMemberShipZoneIntroduceHeader|_topSeparatorLine,_bottomSeparatorLine",
	"WCFinderMentionSearchContactTableViewCell|_separatorLine",
	"WCFinderMentionUserContactTableViewCell|_separatorLine",
	"WCFinderMyTabFinderCardView|_postSeparatorLine",
	"WCFinderPersonalCenterPostActionView|_postSeparatorLine",
	"WCFinderPersoncalCenterContactBlockCollectionViewCell|_separator",
	"WCFinderPhotoFeedHeaderView|_separatorView",
	"WCFinderProfileOverviewCollectionCell|_separatorLine",
	"WCFinderRefuseLikeListTableViewCell|_separatorAlignAvatarLeft,_separator",
	"WCFinderRefuseListTableViewCell|_separator",
	"WCFinderSearchContactCellContentView|_separatorLine",
	"WCFinderSearchSecurityTipsCell|_separatorLine",
	"WCFinderShareFeedCellView|_separator",
	"WCFinderShareTopicCellView|_separator",
	"WCFinderTLFriendLikeFeedFoldTableViewCell|_sectionSeparator,_lineSeparator",
	"WCMicroMerchantAdProductCardView|_tailSeparator",
	"WCMomentsFinderRecommendationButton|_separatorLine",
	"WCMomentsFinderRecommendationInfo|_customizedSeparatorTips",
	"WCMomentsFinderRecommendationManager|_configurations_customizedSeparatorTips",
	"WCMomentsFinderRecommendationViewModel|_customizedSeparatorTipsText",
	"WCMomentsUserTableViewCell|_separatorLine",
	"WCMomentsVisibilityTabBar|_separatorLine",
	"WCPayCountryCodeAndPhoneNumberItem|_separator",
	"WCPayF2FTransferFavorItemView|_separator",
	"WCPayInputMoneyView|_separator",
	"WCPayLQTKeyboardToolView|_separators",
	"WCPayRealNameTipsViewController|_separatorLine",
	"WCPayUploadIDCardTipsViewController|_separatorLine",
	"WCPlayerConfigFullScreenProgressBarWithMultiSpeed|_separatorLine",
	"WCPlayerConfigFullScreenProgressBarWithShrink|_separatorLine",
	"WCRedesignBaseItemView|_separators,_topSeparator,_bottomSeparator",
	"WCRedesignBaseItem|_separators",
	"WCStoryTimelineEntranceTableViewCell|_separatorLine",
	"WCTableViewSectionManager|_bDrawNoSeparator,_bDrawSeparatorBetweenCells",
	"WeDropPermissionCell|_separatorLineTop,_separatorLineBottom",
	"WebSearchTagView|_descSeparator",
	"ilinkMultiSelectContactsViewController|_headerViewSeparatorView",
	"_TtC6WeChat40FinderBulletBlackWordInputViewController|inputSeparator",
	"_TtC6WeChatP33_D950BC01DA6365B954DE32A434FFB25E25FinderBulletBlackWordCell|separatorView",
	"_TtC6WeChat25LedgerDailyCellRecordView|topSeparator,separator,bottomseparator",
	"_TtC6WeChat20LedgerDetailItemCell|topSeparator,bottomseparator",
	"_TtC6WeChat33LedgerUserTransactionsFiltertCell|separator",
	"_TtC6WeChatP33_BA7D4393BD0E8BF147478A024CD0CA1214RangeIndicator|topSeparator,bottomSeparator",
	"_TtC6WeChat25WCPayLedgerViewController|$__lazy_storage_$_separator",
	"_TtC6WeChat36WSNativeHotListHotSearchItemBaseView|$__lazy_storage_$_todayTopSeparatorView",
	"KSCrashReportFilterConcatenate|_separatorFmt",
	"WAMiniToolMenuListItemView|_separatorLine",
	"WAMediaCastingRoutePickerTableViewCell|_separatorLineView",
	"DotLoadingView|_separatorDistance",
	"_TtC9WeAppCore24WANavigateMapAppItemView|$__lazy_storage_$_separatorView",
	"WCTabBarView|_separatorView",
	"WCSplitViewController|_separatorLine",
	"MMMenuContentView|_separatorViews",
	"WCCustomNavigationBar|_rendererSeparatorHidden",
	"WCCustomNavigationBarContentView|_separatorView",
        NULL
    };
    for (int i = 0; kSepCensus[i]; i++) {
        NSString *entry = [NSString stringWithUTF8String:kSepCensus[i]];
        NSRange bar = [entry rangeOfString:@"|"];
        if (bar.location == NSNotFound) continue;
        NSString *clsName = [entry substringToIndex:bar.location];
        if ([gSepCensusDone containsObject:clsName]) continue;
        Class cls = NSClassFromString(clsName);
        if (!cls) continue;
        [gSepCensusDone addObject:clsName];
        NSArray<NSString *> *ivars = [[entry substringFromIndex:bar.location + 1] componentsSeparatedByString:@","];
        SEL sel = NULL;
        if ([cls isSubclassOfClass:[UIView class]]) sel = @selector(layoutSubviews);
        else if ([cls isSubclassOfClass:[UIViewController class]]) sel = @selector(viewDidLayoutSubviews);
        if (!sel) continue;
        // 若本类的该方法已是我的钩子（继承自先装的普查祖先类），不再重复装，
        // 只登记 ivars，钩子解析时会沿继承链一并处理（orig 取祖先的真实现）。
        Method m = class_getInstanceMethod(cls, sel);
        if (m && method_getImplementation(m) == (IMP)WC_Sep_layout) {
            gSepCensusIvars[clsName] = ivars;
            gSepCensusOrigs[clsName] = (id)[NSNull null];
            gSepGen++;
            continue;
        }
        IMP orig = WCSwapOwn(cls, sel, (IMP)WC_Sep_layout);
        if (orig) {
            gSepCensusIvars[clsName] = ivars;
            gSepCensusOrigs[clsName] = [NSValue valueWithPointer:orig];
            gSepGen++;
        }
    }
}

static void WCInstallSepGate(void) {
    WCInstallSepCensus();
    if (!gOrigTVLayout) gOrigTVLayout = WCSwapOwn([UITableView class], @selector(layoutSubviews), (IMP)WC_TV_layout);
    if (gOrigSetSepStyle) return;
    gOrigSetSepStyle = WCSwapOwn([UITableView class], @selector(setSeparatorStyle:), (IMP)WC_TV_setSepStyle);
    gOrigSetDelegate = WCSwapOwn([UITableView class], @selector(setDelegate:), (IMP)WC_TV_setDelegate);
    gOrigSetDataSource = WCSwapOwn([UITableView class], @selector(setDataSource:), (IMP)WC_TV_setDataSource);
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

static IMP gO_InT, gO_InW, gO_ContT, gO_ContW, gO_InLayout, gO_ContLayout;
static void WC_In_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_InT)(s, c, p); if (s.window) WCForceBar(s, @"chatbar", 4); WCScheduleDarkRefresh(); }
static void WC_In_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_InW)(s, c); if (!gBarsInput) gBarsInput = [[NSHashTable weakObjectsHashTable] retain]; if (s.window) { WCRegisterBar(gBarsInput, s); WCForceBar(s, @"chatbar", 4); } }
static void WC_Cont_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_ContT)(s, c, p); if (s.window) WCForceBar(s, @"chatbar", 4); WCScheduleDarkRefresh(); }
static void WC_Cont_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_ContW)(s, c); if (!gBarsInput) gBarsInput = [[NSHashTable weakObjectsHashTable] retain]; if (s.window) { WCRegisterBar(gBarsInput, s); WCForceBar(s, @"chatbar", 4); } }
// v8.18：输入框上色的源头时机。进聊天时 didMoveToWindow 触发 WCForceBar
// 的那一刻，输入栏的子视图（文本框等）还没建好，sweep 扫了个空；此前
// 只能等 5 秒家务 tick 补扫——用户实测进聊天后约 5 秒输入框才变成设置
// 色（12:59 录屏逐帧量到 7.1s 处色值才跳）。layoutSubviews 是栏内容
// 建好后的第一次排版、就在进场动画里，挂它补扫，进场即上色。
static void WC_In_layout(UIView *s, SEL c) {
    ((void (*)(id, SEL))gO_InLayout)(s, c);
    if (gWCWeChatDark && WCConfigColor(@"field")) WCFieldSweep(s);
    if (WCHideSep()) {
        // 输入框上方那条长线：_toolView 自身上下边 + 栏根层与 strip 顶边对齐处
        Ivar iv = class_getInstanceVariable([s class], "_toolView");
        UIView *tool = nil;
        if (iv) { id v = object_getIvar(s, iv); if ([v isKindOfClass:[UIView class]]) tool = v; }
        if (tool) {
            WCHideEdgeLinesDeep(tool, 6);
            CGFloat ty = tool.frame.origin.y, W = s.bounds.size.width;
            for (UIView *v in s.subviews) {
                if (v.hidden || v == tool) continue;
                if ([v isKindOfClass:[UILabel class]] || [v isKindOfClass:[UIControl class]]) continue;
                if (WCIsHairlineFrame(v.frame, W) && fabs(v.frame.origin.y - ty) <= 1.5) v.hidden = YES;
            }
        }
        // v8.20：整栏子树也扫一遍——输入条若是 _toolView 的兄弟子树，
        // v8.19 只扫 _toolView 内部就够不着它顶边那条线。
        WCHideEdgeLinesDeep(s, 5);
    }
}
static void WC_Cont_layout(UIView *s, SEL c) { ((void (*)(id, SEL))gO_ContLayout)(s, c); if (gWCWeChatDark && WCConfigColor(@"field")) WCFieldSweep(s); if (WCHideSep()) WCHideEdgeLinesDeep(s, 3); }

static void WCInstallChatbarHooks(void) {
    Class c;
    c = NSClassFromString(@"MMInputToolView");
    if (c && !gO_InT) { gO_InT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_In_trait); gO_InW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_In_window); gO_InLayout = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_In_layout); }
    c = NSClassFromString(@"InputToolContainerView");
    if (c && !gO_ContT) { gO_ContT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_Cont_trait); gO_ContW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_Cont_window); gO_ContLayout = WCSwapOwn(c, @selector(layoutSubviews), (IMP)WC_Cont_layout); }
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
static void WC_Tab_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_TabT)(s, c, p); if (s.window) WCForceBar(s, @"tab", 4); WCScheduleDarkRefresh(); }
static void WC_Tab_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_TabW)(s, c); if (s.window) { WC_Tab_reg(s); WCForceBar(s, @"tab", 4); } }
static void WC_TabView_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_TabViewT)(s, c, p); if (s.window) WCForceBar(s, @"tab", 4); WCScheduleDarkRefresh(); }
static void WC_TabView_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_TabViewW)(s, c); if (s.window) { WC_Tab_reg(s); WCForceBar(s, @"tab", 4); } }
static void WC_MMTab_trait(UIView *s, SEL c, UITraitCollection *p) { ((void (*)(id, SEL, id))gO_MMTabT)(s, c, p); if (s.window) WCForceBar(s, @"tab", 4); WCScheduleDarkRefresh(); }
static void WC_MMTab_window(UIView *s, SEL c) { ((void (*)(id, SEL))gO_MMTabW)(s, c); if (s.window) { WC_Tab_reg(s); WCForceBar(s, @"tab", 4); } }

// v8.10：侧滑切应用时底栏露浅灰（用户录屏逐帧定案：内容全程深色、只有底栏在
// 过渡画面里翻浅，玻璃关掉也犯）。既有强涂挂在 trait/入窗/5 秒家务上，过渡
// 路径里栏的背景被重建/被快照时全绕开了。改在赋值与快照点拦：背景视图一被
// 换上、半透明一被重设、快照一生成、控制器一准备转场，就在同一调用栈里涂黑。
static void WCApplyBarsState(void);
static IMP gO_TabBgView, gO_TabTranslucent, gO_TabSnapshot, gO_CtlPrepare;
static void WC_Tab_setBgView(UIView *s, SEL c, UIView *v) {
    ((void (*)(id, SEL, id))gO_TabBgView)(s, c, v);
    WCForceBar(s, @"tab", 4);
}
static void WC_Tab_setTranslucent(UIView *s, SEL c, BOOL t) {
    ((void (*)(id, SEL, BOOL))gO_TabTranslucent)(s, c, t);
    WCForceBar(s, @"tab", 4);
}
static UIView *WC_Tab_snapshot(UIView *s, SEL c, BOOL afterUpdates) {
    UIView *snap = ((UIView *(*)(id, SEL, BOOL))gO_TabSnapshot)(s, c, afterUpdates);
    if (snap) WCForceBar(snap, @"tab", 4);
    return snap;
}
static void WC_Ctl_prepare(id s, SEL c, id arg) {
    ((void (*)(id, SEL, id))gO_CtlPrepare)(s, c, arg);
    WCApplyBarsState();
}

static void WCInstallTabHooks(void) {
    Class c;
    c = NSClassFromString(@"WCGNativeTabBar");
    if (c && !gO_TabT) { gO_TabT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_Tab_trait); gO_TabW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_Tab_window); }
    c = NSClassFromString(@"WCTabBarView");
    if (c && !gO_TabViewT) { gO_TabViewT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_TabView_trait); gO_TabViewW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_TabView_window); }
    c = NSClassFromString(@"MMTabBar");
    if (c && !gO_MMTabT) { gO_MMTabT = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_MMTab_trait); gO_MMTabW = WCSwapOwn(c, @selector(didMoveToWindow), (IMP)WC_MMTab_window); }
    // v8.10 赋值/快照点拦截
    c = NSClassFromString(@"WCTabBarView");
    if (c && !gO_TabBgView) {
        gO_TabBgView = WCSwapOwn(c, @selector(setBackgroundContentView:), (IMP)WC_Tab_setBgView);
        gO_TabTranslucent = WCSwapOwn(c, @selector(setTranslucent:), (IMP)WC_Tab_setTranslucent);
        gO_TabSnapshot = WCSwapOwn(c, @selector(snapshotViewAfterScreenUpdates:), (IMP)WC_Tab_snapshot);
    }
    Class ctlCls = NSClassFromString(@"WCTabBarController");
    if (ctlCls && !gO_CtlPrepare) gO_CtlPrepare = WCSwapOwn(ctlCls, @selector(prepareTabBarForTransition:), (IMP)WC_Ctl_prepare);
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
    // v8.18：色板字符串的消费者（顶栏那条路）把 000000 当未设值，写 010101
    // 让它认得下这口黑（肉眼与 0 无区别）；对象路径已由 P3 黑保持真 0。
    if ([hex isEqualToString:@"000000"]) hex = @"010101";
    NSString *newDark = [@"#" stringByAppendingString:(dark.length > 7 ? [hex stringByAppendingString:[dark substringFromIndex:7]] : hex)];
    gWCValueStrHits++;
    return [NSString stringWithFormat:@"%@,%@", parts[0], newDark];
}

static UIColor *WC_MMDynamicColor_toColor(id self, SEL _cmd) {
    UIColor *orig = ((UIColor *(*)(id, SEL))gOrigToColor)(self, _cmd);
    if (!orig || !WCEnabled()) return orig;
    // v8.18：翻转的源头信号。微信内部深浅类型一变，全 App 的动态色都会
    // 重新走一遍 toColor——这就是翻转本身。在这里顺手刷新探针（探针自带
    // 0.5 秒缓存、热路径只是一次时间比较），探针一翻立刻重涂/还原全栏，
    // 不再依赖栏/页面 trait 钩子的触发时机（v8.18 实测：聊天页切深浅时
    // 梯队档位与微信内部类型更新错开，底板滞留到录屏结束都没跟上）。
    if ([NSThread isMainThread]) WCRefreshDarkState(NO);
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
    // v8.9：v8.7 的 0.15s 延迟在录屏里量出约 0.2s 的可见灰闪。改成立即刷：
    // 即将回前台（willEnterForeground）先刷一次赶在第一帧前，激活瞬间再刷
    // 一次，0.3s 后留一次兜底。
    WCGlassResumeRefresh();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCGlassResumeRefresh(); });
}

// v8.18：系统外观翻转时微信内部类型更新时机不固定，setCurrentType: 不一定
// 被调，探针没人刷新——栏的 trait 钩子拿着旧的 gWCWeChatDark 重涂，底栏能
// 黑着卡到下一个 5 秒家务 tick（用户 11:07 录屏：内容已变浅、底栏黑约 4 秒）。
// 修法：栏 trait 一翻就排一小梯队探针刷新（事件驱动、无常驻轮询），微信
// 类型一变，WCRefreshDarkState 的变化检测立即重涂全栏。
static void WCScheduleDarkRefresh(void) {
    static const double delays[5] = {0.1, 0.35, 0.8, 1.6, 2.8};
    for (int i = 0; i < 5; i++)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ WCRefreshDarkState(YES); });
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
    if (s == 2) return @"去掉微信各页面的分割线（会话列表、通讯录、设置等），冷启动也不闪。关掉开关即恢复。";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"c"];
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.textLabel.font = [UIFont systemFontOfSize:17];
    cell.textLabel.numberOfLines = 1;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    if (ip.section == 0) {
        cell.textLabel.text = @"启用 WCBlack";
        cell.detailTextLabel.text = WCEnabled() ? @"开" : @"关";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.accessoryView = nil;
    } else if (ip.section == 2) {
        cell.textLabel.text = @"隐藏分割线";
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
            os_log(WCLog(), "[WCBlack] v8.33 registered in plugin list");
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
// 页面级外观翻转信号（v8.16 引入，梯队保留作兜底）。栏被钉了 overrideUserInterfaceStyle=Dark，
// 系统翻转时栏自己的 trait 不变、它的 traitCollectionDidChange 不触发；
// 聊天页里切深浅时，聊天底板（底栏同理）只能等探针被别的路径刷新才跟，
// 实测黑底板在浅色页上滞留约半秒到数秒（用户 12:47 录屏）。微信所有页面
// 控制器的基类 MMUIViewController 不钉 override，它的 trait 翻转就是
// 页面翻转的同一时刻——挂它，翻转一到就排探针刷新梯队。
static IMP gO_VC_trait;
static void WC_VC_trait(UIViewController *s, SEL c, UITraitCollection *p) {
    ((void (*)(id, SEL, id))gO_VC_trait)(s, c, p);
    WCScheduleDarkRefresh();
}
static void WCInstallVCTraitHook(void) {
    Class c = NSClassFromString(@"MMUIViewController");
    if (c && !gO_VC_trait) gO_VC_trait = WCSwapOwn(c, @selector(traitCollectionDidChange:), (IMP)WC_VC_trait);
}

// v8.31：发送图片预览页底部面板发白。该页控制器写死深色外观
// (overrideUserInterfaceStyle 返回 2)，顶栏 #212121、照片区纯黑都正常，
// 只有底部毛玻璃层（addBlurEffectWithColor: 建的 UIVisualEffectView）
// 落到浅色，整块渲染成 #C6C6C6。插件的色板引擎够不着这层（它不从
// WCColorMgr 取色），故在该页布局后定点处理：把毛玻璃换成深色
// 效果、contentView 盖 bg 模块色。用关联对象记住自己装的 effect
// 实例，微信若换回则下次布局再装。
// v8.32：v8.31 钩错了页面——聊天里从相册格子点开的预览实际是
// MMImagePreviewBrowserController（initSelectCheckButton 顶右勾选圈、
// onOriginImageCheck 原图、OnSend 发送、_blurView/_bottomBar），
// MsgImgPickerPreviewViewController 是另一入口的旧预览页。改钩前者
// 的 _blurView（getter）与 _bottomBar（KVC 兜底），旧钩保留无害。
static char kWCForcedEffectKey;
static IMP gO_PreviewLayout = NULL;
static IMP gO_BrowserLayout = NULL;
static void WCDeepDarkenEffectViews(UIView *v, UIColor *cover, int depth) {
    if (!v || depth > 6) return;
    if ([v isKindOfClass:[UIVisualEffectView class]]) {
        UIVisualEffectView *ev = (UIVisualEffectView *)v;
        UIBlurEffect *mine = objc_getAssociatedObject(ev, &kWCForcedEffectKey);
        if (ev.effect != mine) {
            UIBlurEffect *dark = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
            ev.effect = dark;
            objc_setAssociatedObject(ev, &kWCForcedEffectKey, dark, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (ev.contentView.backgroundColor != cover) ev.contentView.backgroundColor = cover;
    }
    for (UIView *sub in v.subviews) WCDeepDarkenEffectViews(sub, cover, depth + 1);
}
static void WCFixPreviewBottom(UIViewController *s) {
    if (!gWCWeChatDark) return;
    UIColor *bg = WCConfigColor(@"bg");
    if (!bg) return;
    if ([s respondsToSelector:@selector(footerBkg)]) {
        UIView *footer = [s performSelector:@selector(footerBkg)];
        if (footer) WCDeepDarkenEffectViews(footer, bg, 0);
    }
    if ([s respondsToSelector:@selector(blurView)]) {
        UIView *blur = [s performSelector:@selector(blurView)];
        if (blur) {
            if (blur.backgroundColor != bg) blur.backgroundColor = bg;
            WCDeepDarkenEffectViews(blur, bg, 0);
        }
        @try {
            UIView *bar = [s valueForKey:@"bottomBar"];
            if (bar && bar != blur) WCDeepDarkenEffectViews(bar, bg, 0);
        } @catch (id e) {}
        // v8.33：已选缩略图条是独立的 MMAssetSelectedCollectionView
        // （ivar m_selectedCollectionView，无 getter，KVC 直取 ivar），
        // 不在 _blurView/_bottomBar 里，v8.32 只压黑了操作行、它还亮着
        // （实测操作行 (9,9,9)、缩略图条 (197,197,197)）。
        @try {
            UIView *strip = [s valueForKey:@"m_selectedCollectionView"];
            if (strip) {
                if (strip.backgroundColor != bg) strip.backgroundColor = bg;
                WCDeepDarkenEffectViews(strip, bg, 0);
                for (UIView *sub in strip.subviews)
                    if ([sub isKindOfClass:[UICollectionView class]] && sub.backgroundColor != bg)
                        sub.backgroundColor = bg;
            }
        } @catch (id e) {}
    }
}
static void WC_Preview_layout(UIViewController *s, SEL c) {
    ((void (*)(id, SEL))gO_PreviewLayout)(s, c);
    WCFixPreviewBottom(s);
}
static void WC_Browser_layout(UIViewController *s, SEL c) {
    ((void (*)(id, SEL))gO_BrowserLayout)(s, c);
    WCFixPreviewBottom(s);
}
static void WCInstallPreviewHook(void) {
    Class c = NSClassFromString(@"MsgImgPickerPreviewViewController");
    if (c && !gO_PreviewLayout) gO_PreviewLayout = WCSwapOwn(c, @selector(viewDidLayoutSubviews), (IMP)WC_Preview_layout);
    Class b = NSClassFromString(@"MMImagePreviewBrowserController");
    if (b && !gO_BrowserLayout) gO_BrowserLayout = WCSwapOwn(b, @selector(viewDidLayoutSubviews), (IMP)WC_Browser_layout);
}

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
                os_log(WCLog(), "[WCBlack] v8.18 source hooks in");
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
    WCInstallTabHooks();
    WCInstallVCTraitHook();
    WCInstallMMCellHook();
    WCInstallCustomSepHook();
    WCInstallMgrHook();
    WCInstallSepDrawHook();
    WCInstallPreviewHook();
    static id wcActiveToken = nil;
    if (!wcActiveToken) {
        wcActiveToken = [[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { WCOnDidBecomeActive(); }] retain];
        static id wcForegroundToken = nil;
        wcForegroundToken = [[[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) { WCGlassResumeRefresh(); }] retain];
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
