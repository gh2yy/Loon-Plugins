// 虎扑 - 去开屏与信息流广告、去首页热榜频道、详情页离线包换黑包、去首页游戏推广卡（底部栏不动：位置写死的发布键，插件层无解）
// 原作者：gh2yy
// 修改日期：2026-11-27
// 修改日志：
// - 2026-10-30 Muse：脚本按 URL 分发处理各接口。getBottomNav：底部清单 5 项删 post 与 score，navVersion 顺延标记防按版本跳过；第 3 位动作键逻辑写死在 App 代码内，插件层试过 type/order/顺序均无效，已由改包修复，须配合改包版使用。init：clientLevelOneNavV2 删 en 为 hotRank 的热榜项。帖子详情页是随包下发的离线 H5（frontendofflinepkg 的 bbs-detailapp-opg 包），脚本改写该接口的升级清单，把详情包的下载地址与 md5 换成本仓库的改色包（深色变量改 OLED 黑）；另有一段 bbs-m-web 主题 CSS 改写，作用于 m.hupu.com 网页版（详情页不走它）。basketballapi/news/v3/tab（tagCode=nba）：入口清单删「战术百科」与「2K手游」，保留赛程、数据、主队。
// - 2026-11-21 Muse：新增 getRecommendList 游戏推广卡过滤（服务器文案特征法，原独立插件 hupu-gamecard 合并进来，命中弹通知报标题）。
// - 2026-11-25 Muse：v1 真机漏检（鬼杀队卡再现、无通知）。二进制 Swift 元数据定案游戏卡模型 HCHomeRecommendGameItemModel 独有键 actionButtonTitle/actionButtonScheme/actionLabelName，v2 改以结构键为主判据（命中任一即删）、文案组为备判据。
// - 2026-11-27 Muse：适配商店最新版 8.2.70（用户抓包定案）：广告全走 goblin interfaceAd/getOther（开屏 pid=999、信息流、评论、资讯、专区），脚本在请求阶段直接本地回无填充（ad_code=-41、ads=[]，与真实空响应同构），不走网络、开屏无广告可播直接进首页；插件另 reject 穿山甲 get_ads 砍掉开屏竞价瀑布的等待。底部栏试删 post+deeptalk 的三项版，真机实测与 8.1.9 同样错位（第 3 位按位置写死为发布键、「我的」顶上误弹发布），用户拍板恢复五项、底部栏不再动，getBottomNav 处理已撤除。同日用户因商店版热启动白屏难解回旧改包版，应其要求恢复 getBottomNav 删 post+score（脚本 ?v=9）。同日加去「问深聊」：帖子详情 threads/refactor 响应的 data.deepTalk 一并驱动顶栏问AI按钮、帖下问深聊卡与评论区 @深聊 引导，脚本把 needShow/replyAiShow 关掉并清空文案。插件文件另融合树先生（ishowshu）的重写规则一组（我的页游戏栏目/VIP推广、横幅、榜单等，详见插件修改日志）。
// - 2026-11-27 Muse：v3.1 诊断信息同步写 console.log 进脚本日志页（通知正文在 Loon 里点开为空、不可靠）；已过滤通知正文为空时改填条目键名。
// - 2026-11-27 Muse：v2 真机再漏检（《凡人问道》卡，三组文案齐全仍漏、无通知）。静态核对：接口路径与二进制一致（bbsallapi/recommend/v2/getRecommendList），疑点收窄到送达（首页容器发请求的域名未必是 bbs 域名）或条目结构再变。v3 双管：插件规则加 games 域名一条、路径前缀放宽；脚本加疑似诊断——条目带 action* 键或只命中 1 组文案时不删但弹通知报该条目的键名清单，拿真实特征定案。
(function () {
  try {
    var url = ($request && $request.url) || '';

    // 请求阶段（无 $response）：广告接口不发网络请求，直接本地回无填充，省掉开屏等待
    if (typeof $response === 'undefined') {
      if (url.indexOf('interfaceAd/getOther') !== -1) {
        $done({ response: { status: 200, headers: { 'Content-Type': 'application/json' }, body: '{"ad_code":-41,"show_type":0,"ads":[]}' } });
      } else {
        $done({});
      }
      return;
    }

    var body = $response.body;
    if (!body) { $done({}); return; }

    // 帖子详情页 H5（bbs-m-web）主题 CSS：深色变量改 OLED 黑（与 App 内颜色令牌同名同值，独立一份）
    if (url.indexOf('/bbs-m-web/') !== -1 && url.indexOf('.css') !== -1) {
      var pairs = [
        ['--bg:#24262b', '--bg:#000000'],
        ['--bg2:#111217', '--bg2:#000000'],
        ['--bg_card:#2c2f37', '--bg_card:#121214'],
        ['--bg_data:#2c2f37', '--bg_data:#0b0b0d'],
        ['--bg_click:#3a3f49', '--bg_click:#232328'],
        ['--line:#303440', '--line:#1e1e21'],
        ['--separator:#111217', '--separator:#2e2e33'],
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

    // 广告系统：interfaceAd/getOther（v3 与 batch）——开屏（pid=999）、首页推荐信息流、评论、资讯等
    // 全部广告位都走这个接口下发。统一改成服务端的无填充形态（ad_code=-41、ads=[]，与真实空响应同构），
    // 开屏拿不到广告即直接进首页，其余广告位同样不再出广告。保留 request_id 等其余字段原样。
    if (url.indexOf('interfaceAd/getOther') !== -1) {
      if (obj && Array.isArray(obj.ads)) {
        obj.ads = [];
        obj.ad_code = -41;
        if ('interval' in obj) obj.interval = 0;
        if (!('show_type' in obj)) obj.show_type = 0;
        $done({ body: JSON.stringify(obj) });
      } else {
        $done({});
      }
      return;
    }

    // 首页推荐流：getRecommendList 里伪装成帖子的 shaper AI 小游戏推广卡
    // v2 主判据（结构字段）：游戏卡模型 HCHomeRecommendGameItemModel 的独有键 actionButtonTitle / actionButtonScheme / actionLabelName
    // （二进制 Swift 字段元数据定案、全 App 仅此模型有这组键；v1 只认展示文案值，服务端若下发代码值就会漏）
    // 备判据（v1 文案组）：读取进度 / JRs 玩过 / 你玩过的 / drj_aigame·shaper 链接，命中 >=2 组
    if (url.indexOf('bbsallapi/recommend/v2/getRecommendList') !== -1) {
      var STRUCT_KEYS = ['"actionButtonTitle"', '"actionButtonScheme"', '"actionLabelName"'];
      var MARKER_GROUPS = [['读取进度'], ['JRs 玩过', 'JRs玩过'], ['你玩过的'], ['drj_aigame', 'shaper/published', '/shaper/']];
      var markerScore = function (item) {
        var s = JSON.stringify(item), score = 0;
        if (STRUCT_KEYS.some(function (k) { return s.indexOf(k) !== -1; })) return 99;
        MARKER_GROUPS.forEach(function (g) {
          if (g.some(function (m) { return s.indexOf(m) !== -1; })) score++;
        });
        return score;
      };
      var dropped = [];
      var suspects = [];
      var cleanse = function (node) {
        if (Array.isArray(node)) {
          for (var i = node.length - 1; i >= 0; i--) {
            var el = node[i];
            // 条目是 {schema_url, data:{...}} 的薄包装（仅 2 键），不能按键数设门槛；判据只看内容特征
            if (el && typeof el === 'object' && !Array.isArray(el)) {
              var sc = markerScore(el);
              if (sc >= 2) { dropped.push(el); node.splice(i, 1); continue; }
              // v3 疑似诊断：带 action* 键或只命中 1 组文案的条目先不删，收集其键名供定案
              var es = JSON.stringify(el);
              if (sc === 1 || es.indexOf('"action') !== -1) suspects.push(el);
            }
            cleanse(el);
          }
        } else if (node && typeof node === 'object') {
          Object.keys(node).forEach(function (k) { cleanse(node[k]); });
        }
      };
      cleanse(obj);
      if (dropped.length) {
        var firstTitle = '';
        var tm = JSON.stringify(dropped[dropped.length - 1]).match(/"(?:title|content|name|desc)":"([^"]{1,50})"/);
        if (tm) firstTitle = tm[1];
        console.log('[游戏卡] 已过滤 ' + dropped.length + ' 条，标题：' + firstTitle);
        console.log('[游戏卡] 被删条目：' + JSON.stringify(dropped[dropped.length - 1]).slice(0, 1200));
        $notification.post('虎扑游戏推广卡已过滤', '删掉 ' + dropped.length + ' 条', firstTitle || JSON.stringify(dropped[dropped.length - 1]).slice(0, 200));
        $done({ body: JSON.stringify(obj) });
        return;
      }
      if (suspects.length) {
        // 把疑似条目（含其 data 子对象）的键名摊开报出来，拿真实结构定特征
        var keySet = {};
        var collectKeys = function (o, depth) {
          if (!o || typeof o !== 'object' || depth > 2) return;
          Object.keys(o).forEach(function (k) { keySet[k] = 1; collectKeys(o[k], depth + 1); });
        };
        collectKeys(suspects[suspects.length - 1], 0);
        console.log('[游戏卡] 疑似漏检 ' + suspects.length + ' 条，键名：' + Object.keys(keySet).join(','));
        console.log('[游戏卡] 疑似条目：' + JSON.stringify(suspects[suspects.length - 1]).slice(0, 2000));
        $notification.post('虎扑游戏卡疑似漏检', '疑似 ' + suspects.length + ' 条，键名如下', Object.keys(keySet).slice(0, 40).join(','));
      }
      $done({});
      return;
    }

    // 帖子详情离线包：改写升级清单，把官方详情包换成本仓库的改色包（深色变量已改 OLED 黑）
    if (url.indexOf('frontendofflinepkg/upgradeListByCodes') !== -1) {
      var ZIP_URL = 'https://raw.githubusercontent.com/gh2yy/Loon-Plugins/main/bbs-detailapp-black.zip';
      var ZIP_MD5 = '547b1880de162e5af8cb8d6b14e5d6f1';
      var ZIP_VER = 12564;
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

    // 帖子详情页「问深聊」：data.deepTalk 同时驱动顶栏问AI按钮、帖下问深聊卡、评论区 @深聊 引导
    // 用服务端自己的开关关掉（needShow/replyAiShow=false），文案一并清空兜底
    if (url.indexOf('/threads/refactor/') !== -1) {
      var dt = obj && obj.data && obj.data.deepTalk;
      if (dt && typeof dt === 'object') {
        dt.needShow = false;
        dt.replyAiShow = false;
        dt.guideName = '';
        dt.guideNameSubtitle = '';
        dt.replyGuideName = '';
        dt.iconName = '';
        $done({ body: JSON.stringify(obj) });
      } else {
        $done({});
      }
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

    // NBA 页快捷入口：news/v3/tab 清单（tagCode=nba）删战术百科与 2K 手游
    if (url.indexOf('basketballapi/news/v3/tab') !== -1 && url.indexOf('tagCode=nba') !== -1) {
      if (!Array.isArray(obj.result)) { $done({}); return; }
      var kept = obj.result.filter(function (it) {
        return it && it.name !== '战术百科' && it.name !== '2K手游';
      });
      if (kept.length === obj.result.length) { $done({}); return; }
      obj.result = kept;
      $done({ body: JSON.stringify(obj) });
      return;
    }

    // 底部栏：getBottomNav 清单删 post 与 score（用户已回旧改包版，改包内有第 3 位修正；商店版删项会错位、勿用）
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
