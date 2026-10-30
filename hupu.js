// 虎扑 - 去底部发布与评分 tab、去首页热榜频道
// 原作者：gh2yy
// 修改日期：2026-10-30
// 修改日志：
// - 2026-10-30 v10 Muse：新增去首页热榜。顶栏频道（热榜/推荐/赛事）由 bplapi/device/v1/init 响应里的 result.clientLevelOneNavV2 清单下发，脚本按 en=hotRank 删去热榜一项（clientLevelOneNav 一并同规则过滤，现清单无此项）；删后默认落到第一项推荐。底部 tab 逻辑不变。已用用户抓包原响应本地验证：V2 清单 3 项变 2 项、其余字段不动，底部清单回归验证仍为 5 删 2。待用户冷启动实测。
// - 2026-10-30 v9 Muse：改包配套版。逆向定案第 3 位动作键逻辑在 App 代码内（HPContainerTabBarViewController 的 hp_tabbar:shouleSelectedAt: 写死 index != 2，will 处理写死 index==2 走发布、index==4 走「我的」），已在改包中修掉，插件数据层实验证明走不通的部分不再试。本版恢复删 post 与 score 两项（三项：首页/专区/我的），type 与 order 不再改动，只做删项与 navVersion 标记（原值+30 拼条目数，如 D1273）。使用时须配合改包版虎扑，否则第 3 位的「我的」仍会弹出打开。
// - 2026-10-30 v8（实验）Muse：用户选择试 type=0。四项版（只删 post）基础上仅改 normals.type 为 0（原值 4，此前试过改为条目数-1 无效），验证 type 是否为布局枚举、0 能否关掉第 3 位动作键逻辑；若评分恢复正常切换，再将 type=0 套到三项版收尾。版本号标记同步改为原值+20 拼条目数（D1174），与 v7 内容区分防同版跳过。
// - 2026-10-30 v7 Muse：用户选择恢复评分试试。本版只删 post（发帖），清单为 首页/专区/评分/我的 四项；按第 3 位动作键模型，评分将落在动作位（预计弹出打开）、「我的」回到第 4 位应恢复正常切换。另 navVersion 改为原值+10 再拼条目数（如 D1074），避免与此前三项版同为 D98 时被 App 按版本相同跳过。
// - 2026-10-30 v6 Muse：v5 实测清单顺序不影响排位（App 按 code 固定次序）；恢复自然次序，配合重装后首启验证缓存因素。
// - 2026-10-30 v5（诊断）Muse：v4 无效；本版重排为 首页/我的/专区，验证第 3 个位置是否被 App 写死拦截。
// - 2026-10-30 v4 Muse：v3 改 type 无效；本版将删后条目的 order 重排为连续 1..3，疑为 order 与槽位不对应所致。
// - 2026-10-30 v3 Muse：tab 已确认去掉，撤下诊断通知；针对点「我的」变弹出式打开且无底部栏，将清单 type 同步改为条目数减一。
// - 2026-10-30 Muse：首版。抓包定案底部栏由 games.mobileapi.hupu.com 的 bplapi/device/v1/nav/getBottomNav 明文 JSON 下发（result.normals.navItems 共 5 项：home/bbs/post/score/more）；脚本删 code 为 post（发帖，即中间红色+按钮）与 score（评分）的两项，只留首页/专区/我的，并把 navVersion 由 D97 顺延为 D98，防止 App 按版本号相同跳过应用新清单。解析异常或结构不符时原样放行；青少年模式 teens 清单不动。
(function () {
  try {
    var body = $response.body;
    if (!body) { $done({}); return; }
    var url = ($request && $request.url) || '';
    var obj = JSON.parse(body);

    // 首页顶栏频道：init 响应的 clientLevelOneNavV2 / clientLevelOneNav，删热榜
    if (url.indexOf('/bplapi/device/v1/init') !== -1) {
      var res = obj && obj.result;
      if (!res) { $done({}); return; }
      var changed = false;
      ['clientLevelOneNavV2', 'clientLevelOneNav'].forEach(function (key) {
        var list = res[key];
        if (Array.isArray(list)) {
          var filtered = list.filter(function (it) {
            return !(it && (it.en === 'hotRank' ||
              (typeof it.schema === 'string' && it.schema.indexOf('hotRank') !== -1)));
          });
          if (filtered.length !== list.length) { res[key] = filtered; changed = true; }
        }
      });
      if (!changed) { $done({}); return; }
      $done({ body: JSON.stringify(obj) });
      return;
    }

    // 底部栏：getBottomNav 清单删 post 与 score
    var normals = obj && obj.result && obj.result.normals;
    if (!normals || !Array.isArray(normals.navItems)) { $done({}); return; }
    var before = normals.navItems.length;
    normals.navItems = normals.navItems.filter(function (it) {
      return it && it.code !== 'post' && it.code !== 'score';
    });
    if (normals.navItems.length === before) { $done({}); return; }
    if (obj.result.navVersion) obj.result.navVersion = String(obj.result.navVersion).replace(/\d+$/, function (n) { return String(parseInt(n, 10) + 30); }) + String(normals.navItems.length);
    $done({ body: JSON.stringify(obj) });
  } catch (e) {
    $done({});
  }
})();
