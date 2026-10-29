// 虎扑 - 去底部发布与评分 tab（getBottomNav 清单改写）
// 原作者：gh2yy
// 修改日期：2026-10-30
// 修改日志：
// - 2026-10-30 诊断版 Muse：用户实测未生效且抓包记录为改写前字节、无法判定送达。三个出口（改写/放行/异常）各加系统通知（独立 try 包裹），标题带“诊断”字样；确诊后移除。
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
    try { $notification.post('虎扑插件·诊断', normals.navItems.length === before ? '脚本已触发：清单无可删项' : '脚本已触发：已删 post/score', ''); } catch (e2) {}
    if (normals.navItems.length === before) { $done({}); return; }
    if (obj.result.navVersion) obj.result.navVersion = String(obj.result.navVersion).replace(/\d+$/, function (n) { return String(parseInt(n, 10) + 1); });
    $done({ body: JSON.stringify(obj) });
  } catch (e) {
    try { $notification.post('虎扑插件·诊断', '脚本已触发：异常放行', String(e && e.message || e)); } catch (e3) {}
    $done({});
  }
})();
