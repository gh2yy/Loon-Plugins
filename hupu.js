// 虎扑 - 去底部发布与评分 tab、去首页热榜频道、详情页离线包换黑包
// 原作者：gh2yy
// 修改日期：2026-10-30
// 修改日志：
// - 2026-10-30 Muse：脚本按 URL 分发处理三个接口，前两项经实测生效。getBottomNav：底部清单 5 项删 post 与 score，navVersion 顺延标记防按版本跳过；第 3 位动作键逻辑写死在 App 代码内，插件层试过 type/order/顺序均无效，已由改包修复，须配合改包版使用。init：clientLevelOneNavV2 删 en 为 hotRank 的热榜项。帖子详情页是随包下发的离线 H5（frontendofflinepkg 的 bbs-detailapp-opg 包），脚本改写该接口的升级清单，把详情包的下载地址与 md5 换成本仓库的改色包（深色变量改 OLED 黑），待实测；另有一段 bbs-m-web 主题 CSS 改写，作用于 m.hupu.com 网页版（详情页不走它）。
(function () {
  try {
    var body = $response.body;
    if (!body) { $done({}); return; }
    var url = ($request && $request.url) || '';

    // 帖子详情页 H5（bbs-m-web）主题 CSS：深色变量改 OLED 黑（与 App 内颜色令牌同名同值，独立一份）
    if (url.indexOf('/bbs-m-web/') !== -1 && url.indexOf('.css') !== -1) {
      var pairs = [
        ['--bg:#24262b', '--bg:#000000'],
        ['--bg2:#111217', '--bg2:#000000'],
        ['--bg_card:#2c2f37', '--bg_card:#121214'],
        ['--bg_data:#2c2f37', '--bg_data:#0b0b0d'],
        ['--bg_click:#3a3f49', '--bg_click:#232328'],
        ['--line:#303440', '--line:#1e1e21'],
        ['--separator:#111217', '--separator:#161618'],
        ['--label_bg1:#2a3e45', '--label_bg1:#141f24'],
        ['--label_bg2:#3e2c32', '--label_bg2:#2c1d21'],
        ['--label_bg3:#343f50', '--label_bg3:#1d2735'],
        ['--label_bg4:#474134', '--label_bg4:#2a251c'],
        ['--disable_text:#3a3f49', '--disable_text:#2e2e33'],
        ['--toast:#242f37cc', '--toast:#1c1c20cc']
      ];
      var out = body, hit = false;
      pairs.forEach(function (p) {
        if (out.indexOf(p[0]) !== -1) { out = out.split(p[0]).join(p[1]); hit = true; }
      });
      if (!hit) { $done({}); return; }
      $done({ body: out });
      return;
    }

    var obj = JSON.parse(body);

    // 帖子详情离线包：改写升级清单，把官方详情包换成本仓库的改色包（深色变量已改 OLED 黑）
    if (url.indexOf('frontendofflinepkg/upgradeListByCodes') !== -1) {
      var ZIP_URL = 'https://raw.githubusercontent.com/gh2yy/Loon-Plugins/main/bbs-detailapp-black.zip';
      var ZIP_MD5 = '30e7382a9ee1f211f4439e96b4479c1e';
      var ZIP_VER = 12461;
      if (!Array.isArray(obj.result)) obj.result = [];
      var found = false;
      obj.result.forEach(function (entry) {
        if (entry && entry.package && entry.package.appId === 'bbs-detailapp-opg') {
          entry.package.url = ZIP_URL;
          entry.package.md5 = ZIP_MD5;
          entry.package.version = ZIP_VER;
          found = true;
        }
      });
      if (!found) {
        obj.result.push({ code: 1, package: { type: 'zip', version: ZIP_VER, url: ZIP_URL, md5: ZIP_MD5, appId: 'bbs-detailapp-opg', appCode: 310001 } });
      }
      $done({ body: JSON.stringify(obj) });
      return;
    }

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
