// 虎扑 - 去底部发布与评分 tab（getBottomNav 清单改写）
// 原作者：gh2yy
// 修改日期：2026-10-30
// 修改日志：
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
      return it && it.code !== 'post' && it.code !== 'score';
    });
    if (normals.navItems.length === before) { $done({}); return; }
    normals.type = normals.navItems.length - 1;
    if (obj.result.navVersion) obj.result.navVersion = String(obj.result.navVersion).replace(/\d+$/, function (n) { return String(parseInt(n, 10) + 1); });
    $done({ body: JSON.stringify(obj) });
  } catch (e) {
    $done({});
  }
})();
