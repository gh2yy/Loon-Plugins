// webpage.js — 网页去广告脚本（自托管，多站点分区维护）
// 原作者：gh2yy
// 修改日期：2026-10-27
// 修改日志：
// - 2026-10-27 Muse：新建。91porny 首页：剔除顶部「九色热搜」模块（服务端直出 HTML，按标题锚点定位容器 div 后整段移除）。
// - 2026-10-27 Muse：改为多站点分区结构——顶部统一分发，每个网站一个独立处理函数（以域名命名、横幅注释隔开），新增网站只加一段，互不影响。

(function () {
  var body = $response.body;
  if (!body || typeof body !== "string") return $done({});
  var url = ($request && $request.url) || "";
  var out = body;

  // ================= 91porny.com =================
  if (/^https:\/\/91porny\.com\//.test(url)) out = site_91porny(out);

  // ================= 下一个网站从这里往下加 =================

  if (out === body) return $done({});
  return $done({ body: out });

  // ---------- 91porny.com：剔除首页顶部「九色热搜」模块 ----------
  // 以 title="大家正在搜" 为锚（全页唯一），回溯到其容器
  // <div class="container-fluid px-0 d-md-block"> 起点，再按 div 嵌套配平找到整段结尾后切除。
  // 锚点或结构对不上时原样返回，绝不误删其他内容。
  function site_91porny(html) {
    var anchor = html.indexOf('title="大家正在搜"');
    if (anchor < 0) return html;
    var openTag = '<div class="container-fluid px-0 d-md-block">';
    var start = html.lastIndexOf(openTag, anchor);
    if (start < 0) return html;
    var depth = 0, i = start, end = -1;
    while (i < html.length) {
      var nextOpen = html.indexOf('<div', i);
      var nextClose = html.indexOf('</div>', i);
      if (nextClose < 0) return html;
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth++; i = nextOpen + 4;
      } else {
        depth--; i = nextClose + 6;
        if (depth === 0) { end = i; break; }
      }
    }
    if (end < 0) return html;
    var block = html.slice(start, end);
    if (block.indexOf('九色热搜') < 0 || block.indexOf('video-elem') >= 0) return html;
    return html.slice(0, start) + html.slice(end);
  }
})();
