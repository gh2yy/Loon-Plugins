// 虎扑 - 去底部发布与评分 tab（getBottomNav 清单改写）
// 原作者：gh2yy
// 修改日期：2026-10-30
// 修改日志：
// - 2026-10-30 v5（诊断）Muse：v4 的 order 重排亦无效。改做位置诊断：条目重排为 首页/我的/专区（「我的」移到第 2 位、「专区」占第 3 位），验证 App 是否写死拦截第 3 个位置（原发帖键位置）。若「我的」恢复正常而「专区」变弹出，则位置拦截坐实；若「我的」仍弹出，则问题与位置无关。
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
      return it && it.code !== 'post' && it.code !== 'score';
    });
    if (normals.navItems.length === before) { $done({}); return; }
    normals.type = normals.navItems.length - 1;
    var prio = { home: 0, more: 1, bbs: 2 };
    normals.navItems.sort(function (a, b) { return (prio[a.code] != null ? prio[a.code] : 9) - (prio[b.code] != null ? prio[b.code] : 9); });
    normals.navItems.forEach(function (it, idx) { it.order = idx + 1; });
    if (obj.result.navVersion) obj.result.navVersion = String(obj.result.navVersion).replace(/\d+$/, function (n) { return String(parseInt(n, 10) + 1); });
    $done({ body: JSON.stringify(obj) });
  } catch (e) {
    $done({});
  }
})();
