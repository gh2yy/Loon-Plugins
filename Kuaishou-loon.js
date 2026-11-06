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
// 实测样本：position 16 条含 1 条瓜子二手车广告、scroll 12 条含 2 条
//（开心消消乐、途虎养车）、myfollow 7 条含 1 条。处理：凡顶层带
// 非空 feeds 数组的 feed 响应，整项丢弃 ad 不为 null 的条目，
// 其余条目与游标（pcursor 等）一律不动。
//
// 两个分支每次命中都 console.log（搜 KS-Pendant / KS-Feed），
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

    if (url.indexOf("/rest/n/feed/") !== -1) {
      if (!obj || !Array.isArray(obj.feeds)) return $done({});
      var before = obj.feeds.length;
      obj.feeds = obj.feeds.filter(function (f) {
        return !(f && typeof f === "object" && f.ad != null);
      });
      console.log("KS-Feed: feeds " + before + " -> " + obj.feeds.length);
      if (obj.feeds.length === before) return $done({});
      return $done({ body: JSON.stringify(obj) });
    }

    return $done({});
  } catch (e) {
    console.log("KS: error " + e);
    $done({});
  }
})();
