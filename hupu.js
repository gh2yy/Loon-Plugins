// 虎扑 - 去底部发布与评分 tab、去首页热榜频道
// 原作者：gh2yy
// 修改日期：2026-10-30
// 修改日志：
// - 2026-10-30 Muse：脚本按 URL 分发处理两个接口，均经实测生效。getBottomNav：底部清单 5 项删 post 与 score，navVersion 顺延标记防按版本跳过；第 3 位动作键逻辑写死在 App 代码内，插件层试过 type/order/顺序均无效，已由改包修复，须配合改包版使用。init：clientLevelOneNavV2 删 en 为 hotRank 的热榜项。
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
