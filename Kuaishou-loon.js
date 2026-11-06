// Kuaishou-loon.js — 快手去红包挂件脚本（Loon）
// 定位（快手 14.9.10.10022，Loon 抓包 354，2026-11-06）：
// 视频页左侧的红包挂件（看视频挂件 / pendant）由冷启动接口
// POST az*-api.ksapisrv.com/rest/n/encourage/unionTask/startup
// 的响应 data.widgetInfo.widgetList 唯一一条 WATCH_PHOTO 挂件下发：
// common.metadata.currentWidgetStyle = "RP"（红包样式），
// mainArea 跳转 https://encourage.kuaishou.com/kwai/task?...&source=pendant
//（即视频里点开的任务中心），初始位置 side=0（左侧）、y=133，
// 与录屏中红包的位置、点开页面完全一致。抓包全量核查无第二处下发。
// 本脚本只把 widgetList 清空，其余字段（legalArea / sideBar /
// extConfig / tkBundleInfo 等）一律原样保留；解析失败或结构不符时
// 原样放行，绝不改坏响应。插件内另有一条 jq 改写做同一件事，
// 两条机制任一生效即可；每次命中都会 console.log 到 Loon 日志
//（搜 KS-Pendant），用于确认脚本到底有没有运行。
(function () {
  try {
    var body = $response.body;
    console.log("KS-Pendant: hit, bodyType=" + typeof body + ", len=" + (body ? body.length : 0));
    if (!body || typeof body !== "string") return $done({});
    var obj = JSON.parse(body);
    var wi = obj && obj.data && obj.data.widgetInfo;
    if (!wi || !Array.isArray(wi.widgetList)) {
      console.log("KS-Pendant: no widgetInfo/widgetList, passthrough");
      return $done({});
    }
    console.log("KS-Pendant: widgetList " + wi.widgetList.length + " -> 0");
    if (wi.widgetList.length === 0) return $done({});
    wi.widgetList = [];
    $done({ body: JSON.stringify(obj) });
  } catch (e) {
    console.log("KS-Pendant: error " + e);
    $done({});
  }
})();
