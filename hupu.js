// 虎扑 - 去底部发布与评分 tab（getBottomNav 清单改写）
// 原作者：gh2yy
// 修改日期：2026-10-30
// 修改日志：
// - 2026-10-30 v8（实验）Muse：用户选择试 type=0。四项版（只删 post）基础上仅改 normals.type 为 0（原值 4，此前试过改为条目数-1 无效），验证 type 是否为布局枚举、0 能否关掉第 3 位动作键逻辑；若评分恢复正常切换，再将 type=0 套到三项版收尾。版本号标记同步改为原值+20 拼条目数（D1174），与 v7 内容区分防同版跳过。
// - 2026-10-30 v7 Muse：用户选择恢复评分试试。本版只删 post（发帖），清单为 首页/专区/评分/我的 四项；按第 3 位动作键模型，评分将落在动作位（预计弹出打开）、「我的」回到第 4 位应恢复正常切换。另 navVersion 改为原值+10 再拼条目数（如 D1074），避免与此前三项版同为 D98 时被 App 按版本相同跳过。
// - 2026-10-30 v6 Muse：v5 实测条目顺序纹丝不动 ⇒ App 按 code 的固定原生次序排位，清单顺序与 order 字段都不决定位置（v4/v5 的改法对它无效）。本版恢复自然次序（首页/专区/我的），配合用户重装 App 后首启即喂 3 项清单，排除旧五槽结构缓存的干扰。
// - 2026-10-30 v5（诊断）Muse：条目重排为 首页/我的/专区 做位置诊断；实测未挪位，见 v6 说明。
// - 2026-10-30 v4 Muse：v3 的 type 同步无效（用户实测现象不变，type 定位说排除）。清单里每项还带 order 字段（原 1..5），删后「我的」仍是 order=5，疑为 App 按 order 把条目放进固定槽位、槽位对不上导致按外链弹出；本版删后将 order 重排为连续的 1..3，type 同步保留 v3 的改法。
// - 2026-10-30 v3 Muse：用户实测 tab 已去掉（诊断通知确认送达），按要求撤下全部通知。另修「我的」页异常：删后点「我的」变成弹出式打开且无底部栏，疑为 normals.type 仍为 4（与原 5 项对应）而清单只剩 3 项，App 按 type 定位「我的」失败后按普通链接打开；本版将 type 同步改为条目数减一（3 项时为 2）。
// - 2026-10-30 Muse：首版。抓包定案底部栏由 games.mobileapi.hupu.com 的 bplapi/device/v1/nav/getBottomNav 明文 JSON 下发（result.normals.navItems 共 5 项：home/bbs/post/score/more）；脚本删 code 为 post（发帖，即中间红色+按钮）与 score（评分）的两项，只留首页/专区/我的，并把 navVersion 由 D97 顺延为 D98，防止 App 按版本号相同跳过应用新清单。解析异常或结构不符时原样放行；青少年模式 teens 清单不动。
(function () {
  try {
    var body = $response.body;
    if (!body) { $done({}); return; }
    var obj = JSON.parse(body);
    var normals = obj && obj.result && obj.result.normals;
    if (!normals || !Array.isArray(normals.navItems)) { $done({}); return; }
    var before = normals.navItems.length;
    normals.navItems = normals.navItems.filter(function (it) {
      return it && it.code !== 'post';
    });
    if (normals.navItems.length === before) { $done({}); return; }
    normals.type = 0;
    normals.navItems.forEach(function (it, idx) { it.order = idx + 1; });
    if (obj.result.navVersion) obj.result.navVersion = String(obj.result.navVersion).replace(/\d+$/, function (n) { return String(parseInt(n, 10) + 20); }) + String(normals.navItems.length);
    $done({ body: JSON.stringify(obj) });
  } catch (e) {
    $done({});
  }
})();
