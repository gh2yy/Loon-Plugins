// Kuaishou-loon.js — 快手净化脚本（Loon）：去红包挂件 + 去信息流广告
//
// 一、红包挂件（定位：快手 14.9.10.10022，抓包 354，2026-11-06）
// 视频页左侧红包挂件由冷启动接口 POST */rest/n/encourage/unionTask/startup
// 的 data.widgetInfo.widgetList 唯一一条 WATCH_PHOTO 挂件下发（样式 RP、
// 左侧 y=133、跳转任务中心 source=pendant）。处理：widgetList 清空，
// 其余字段原样保留。插件内另有一条 jq 改写做同一件事，双保险。
//
// 二、信息流广告（定位：抓包 355，2026-11-06）
// 精选/关注等 feed 接口（/rest/n/feed/selection/profile/position、
// .../scroll、selectionFast、myfollow、profile2 等）的响应均为明文
// JSON，顶层 feeds 数组逐条下发；广告条目带顶层 ad 对象（creativeId、
// adType、appName、tracks 等完整广告载荷），正常视频条目没有 ad 字段。
// 处理：凡顶层带非空 feeds 数组的 feed 响应，整项丢弃 ad 不为 null
// 的条目，其余条目与游标（pcursor 等）一律不动。
//
// 三、2026-11-18 v4 增补（用户报信息流偶尔仍刷到广告，静态复查）
// 1) 沉浸式滑动 feed /rest/app/customer/video/c/slide/feeds、.../refresh
//    不在 /rest/n/feed/ 前缀内，v3 未覆盖，本版并入同一过滤；结构不符
//    时原样放行，不误伤。
// 2) KS-Feed 日志带接口路径，事后在 Loon 日志里可按时间对位是哪条
//    feed 在下发、滤了几条，无需抓包。
// 3) 可疑条目侦测（只记日志、不删）：未被 ad 规则命中的条目若带
//    adInfo/adData/adExt/commercialInfo/advertisement/adPhoto 等
//    广告味字段，打 KS-Suspect 日志（路径+序号+字段名）。若日后仍
//    刷到广告，凭日志即可定案是不是无 ad 字段的变体条目。
// 另：diverse/ad 独立广告下发通道（客户端本地插入 feed，feed 过滤
// 够不着）由插件 [Rewrite] 直接 REJECT，不在本脚本内。
//
// 各分支每次命中都 console.log（搜 KS-Pendant / KS-Feed / KS-Suspect），
// 用于确认脚本是否运行；解析失败或结构不符一律原样放行。
(function () {
  try {
    var url = ($request && $request.url) || "";
    var body = $response.body;
    if (!body || typeof body !== "string") return $done({});
    var obj = JSON.parse(body);

    if (url.indexOf("/encourage/unionTask/startup") !== -1) {
      var wi = obj && obj.data && obj.data.widgetInfo;
      if (!wi || !Array.isArray(wi.widgetList)) return $done({});
      console.log("KS-Pendant: widgetList " + wi.widgetList.length + " -> 0");
      if (wi.widgetList.length === 0) return $done({});
      wi.widgetList = [];
      return $done({ body: JSON.stringify(obj) });
    }

    var isFeed =
      url.indexOf("/rest/n/feed/") !== -1 ||
      url.indexOf("/customer/video/c/slide/") !== -1;
    if (isFeed) {
      if (!obj || !Array.isArray(obj.feeds)) return $done({});
      var path = url.split("?")[0].replace(/^https?:\/\/[^/]+/, "");
      var before = obj.feeds.length;
      var suspects = [];
      var SUSPECT_KEYS = [
        "adInfo",
        "adData",
        "adExt",
        "commercialInfo",
        "advertisement",
        "adPhoto"
      ];
      obj.feeds = obj.feeds.filter(function (f, idx) {
        if (f && typeof f === "object") {
          if (f.ad != null) return false;
          for (var k = 0; k < SUSPECT_KEYS.length; k++) {
            if (f[SUSPECT_KEYS[k]] != null) {
              suspects.push(idx + ":" + SUSPECT_KEYS[k]);
              break;
            }
          }
        }
        return true;
      });
      console.log(
        "KS-Feed " + path + ": feeds " + before + " -> " + obj.feeds.length
      );
      if (suspects.length) {
        console.log("KS-Suspect " + path + ": " + suspects.join(","));
      }
      if (obj.feeds.length === before) return $done({});
      return $done({ body: JSON.stringify(obj) });
    }

    return $done({});
  } catch (e) {
    console.log("KS: error " + e);
    $done({});
  }
})();
