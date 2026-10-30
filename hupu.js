// 虎扑 - 去底部发布与评分 tab（getBottomNav 清单改写）；去首页右上角活动入口（活动导航数据拦截）
// 原作者：gh2yy
// 修改日期：2026-10-30
// 修改日志：
// - 2026-10-30 v11 Muse：v10 实测无效且诊断通知未出现，判断请求侧改版本号使请求体 MD5 签名失效、服务器未下发数据块。本版撤掉请求侧改动，改两条腿：① init 接口（bplapi/device/v1/init）的响应里 result 本就映射到含 activityNav 字段的初始化模型，注入 activityNav 为空数组，覆盖本地缓存的活动导航数据；② update 接口响应侧保留清空逻辑，并放宽诊断：只要 result.data 非空就一次性通知首个数据块的字段名，便于确认数据块是否流动及其结构。init 处理也发一次性通知（注明字段原本是否存在）。
// - 2026-10-30 v10 Muse：新增去首页右上角活动入口（精灵球图标，点开为「今天玩什么」游戏聚合页），免改包、纯插件实现。该入口数据由 bplapi/device/v1/update 增量通道的 activityNav 模块下发并缓存在本地，版本未变时服务器不下发内容（抓包响应 data 为空），故两段处理：请求侧把上报的 activityNav 版本号改报为 0，促使服务器回传当前数据块；响应侧在 result.data 中定位 activityNav 数据块，保留其标量字段（版本号等），把数组清空、对象置空、长字符串清空，使 App 以空数据更新本地缓存、入口不再显示。首次实际拦到数据块时发一次性通知列出字段名，便于核对拦截是否命中。原 getBottomNav 逻辑不变，按请求 URL 分发。
// - 2026-10-30 v9 Muse：改包配套版。逆向定案第 3 位动作键逻辑在 App 代码内（HPContainerTabBarViewController 的 hp_tabbar:shouleSelectedAt: 写死 index != 2，will 处理写死 index==2 走发布、index==4 走「我的」），已在改包中修掉，插件数据层实验证明走不通的部分不再试。本版恢复删 post 与 score 两项（三项：首页/专区/我的），type 与 order 不再改动，只做删项与 navVersion 标记（原值+30 拼条目数，如 D1273）。使用时须配合改包版虎扑，否则第 3 位的「我的」仍会弹出打开。
// - 2026-10-30 v8（实验）Muse：用户选择试 type=0。四项版（只删 post）基础上仅改 normals.type 为 0（原值 4，此前试过改为条目数-1 无效），验证 type 是否为布局枚举、0 能否关掉第 3 位动作键逻辑；若评分恢复正常切换，再将 type=0 套到三项版收尾。版本号标记同步改为原值+20 拼条目数（D1174），与 v7 内容区分防同版跳过。
// - 2026-10-30 v7 Muse：用户选择恢复评分试试。本版只删 post（发帖），清单为 首页/专区/评分/我的 四项；按第 3 位动作键模型，评分将落在动作位（预计弹出打开）、「我的」回到第 4 位应恢复正常切换。另 navVersion 改为原值+10 再拼条目数（如 D1074），避免与此前三项版同为 D98 时被 App 按版本相同跳过。
// - 2026-10-30 v6 Muse：v5 实测条目顺序纹丝不动 ⇒ App 按 code 的固定原生次序排位，清单顺序与 order 字段都不决定位置（v4/v5 的改法对它无效）。本版恢复自然次序（首页/专区/我的），配合用户重装 App 后首启即喂 3 项清单，排除旧五槽结构缓存的干扰。
// - 2026-10-30 v5（诊断）Muse：条目重排为 首页/我的/专区 做位置诊断；实测未挪位，见 v6 说明。
// - 2026-10-30 v4 Muse：v3 的 type 同步无效（用户实测现象不变，type 定位说排除）。清单里每项还带 order 字段（原 1..5），删后「我的」仍是 order=5，疑为 App 按 order 把条目放进固定槽位、槽位对不上导致按外链弹出；本版删后将 order 重排为连续的 1..3，type 同步保留 v3 的改法。
// - 2026-10-30 v3 Muse：用户实测 tab 已去掉（诊断通知确认送达），按要求撤下全部通知。另修「我的」页异常：删后点「我的」变成弹出式打开且无底部栏，疑为 normals.type 仍为 4（与原 5 项对应）而清单只剩 3 项，App 按 type 定位「我的」失败后按普通链接打开；本版将 type 同步改为条目数减一（3 项时为 2）。
// - 2026-10-30 Muse：首版。抓包定案底部栏由 games.mobileapi.hupu.com 的 bplapi/device/v1/nav/getBottomNav 明文 JSON 下发（result.normals.navItems 共 5 项：home/bbs/post/score/more）；脚本删 code 为 post（发帖，即中间红色+按钮）与 score（评分）的两项，只留首页/专区/我的，并把 navVersion 由 D97 顺延为 D98，防止 App 按版本号相同跳过应用新清单。解析异常或结构不符时原样放行；青少年模式 teens 清单不动。
(function () {
  var url = (typeof $request !== 'undefined' && $request && $request.url) || '';
  if (url.indexOf('/bplapi/device/v1/update') !== -1) {
    handleDeviceUpdate();
  } else if (url.indexOf('/bplapi/device/v1/init') !== -1) {
    handleDeviceInit();
  } else {
    handleBottomNav();
  }

  function handleBottomNav() {
    try {
      var body = $response.body;
      if (!body) { $done({}); return; }
      var obj = JSON.parse(body);
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
  }

  function handleDeviceInit() {
    // init 响应 result 映射到含 activityNav 的初始化模型：把该字段置为空数组，覆盖缓存的活动导航
    try {
      var body = $response.body;
      if (!body) { $done({}); return; }
      var obj = JSON.parse(body);
      var result = obj && obj.result;
      if (!result || typeof result !== 'object') { $done({}); return; }
      var had = Object.prototype.hasOwnProperty.call(result, 'activityNav');
      var prevDesc = '无此字段';
      if (had) {
        var prev = result.activityNav;
        if (Array.isArray(prev)) prevDesc = '数组(' + prev.length + ' 项)';
        else if (prev && typeof prev === 'object') prevDesc = '对象，字段：' + Object.keys(prev).join(', ');
        else prevDesc = String(typeof prev);
      }
      result.activityNav = [];
      notifyOnce('hupu_init_diag', '虎扑插件', '已处理 init 的 activityNav 字段', '原本：' + prevDesc);
      $done({ body: JSON.stringify(obj) });
    } catch (e) {
      $done({});
    }
  }

  function handleDeviceUpdate() {
    // 响应侧：定位 activityNav 数据块并清空其内容（标量字段保留）；data 非空时一次性诊断通知
    try {
      var body = $response.body;
      if (!body) { $done({}); return; }
      var obj = JSON.parse(body);
      var result = obj && obj.result;
      if (!result) { $done({}); return; }
      var changed = false;
      if (Object.prototype.hasOwnProperty.call(result, 'activityNav')) {
        result.activityNav = null;
        changed = true;
      }
      var data = result.data;
      if (Array.isArray(data) && data.length) {
        var first = data[0];
        var firstDesc = typeof first === 'string' ? '字符串：' + first.slice(0, 120) : '字段：' + Object.keys(first || {}).join(', ');
        notifyOnce('hupu_update_diag', '虎扑插件', 'update 接口有数据块下发', firstDesc);
        for (var i = 0; i < data.length; i++) {
          var el = data[i];
          if (typeof el === 'string' && el.indexOf('activityNav') !== -1) {
            try {
              var parsed = JSON.parse(el);
              emptyPayload(parsed);
              data[i] = JSON.stringify(parsed);
              changed = true;
              notifyOnce('hupu_activitynav_diag', '虎扑插件', '已拦截活动导航数据块', '字段：' + Object.keys(parsed).join(', '));
            } catch (e2) { /* 非 JSON 字符串则不动 */ }
          } else if (el && typeof el === 'object' && JSON.stringify(el).indexOf('activityNav') !== -1) {
            emptyPayload(el);
            changed = true;
            notifyOnce('hupu_activitynav_diag', '虎扑插件', '已拦截活动导航数据块', '字段：' + Object.keys(el).join(', '));
          }
        }
      }
      if (changed) $done({ body: JSON.stringify(obj) });
      else $done({});
    } catch (e) {
      $done({});
    }
  }

  function emptyPayload(block) {
    Object.keys(block).forEach(function (k) {
      var v = block[k];
      if (Array.isArray(v)) block[k] = [];
      else if (v && typeof v === 'object') block[k] = {};
      else if (typeof v === 'string' && v.length > 40) block[k] = '';
    });
  }

  function notifyOnce(flag, title, subtitle, bodyText) {
    try {
      if (!$persistentStore.read(flag)) {
        $persistentStore.write('1', flag);
        $notification.post(title, subtitle, bodyText);
      }
    } catch (e) { /* 通知失败不影响改写 */ }
  }
})();
