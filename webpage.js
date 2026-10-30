// webpage.js — 网页去广告脚本（自托管，多站点分区维护）
// 原作者：gh2yy
// 修改日期：2026-10-27
// 修改日志：
// - 2026-10-27 Muse：新建，多站点分区结构（顶部统一分发、每站一个独立处理函数）。已接入 91porny 与 hsex.men：剔除两站首页的热搜类模块，按标题锚点定位容器整段移除。

(function () {
  var body = $response.body;
  if (!body || typeof body !== "string") return $done({});
  var url = ($request && $request.url) || "";
  var out = body;

  // ================= 91porny.com =================
  if (/^https:\/\/91porny\.com\//.test(url)) out = site_91porny(out);

  // ================= hsex.men =================
  if (/^https:\/\/hsex\.men\//.test(url)) out = site_hsex(out);

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

  // ---------- hsex.men：剔除首页「热搜」模块 ----------
  // 结构 = <h2>热搜</h2> + <div class="row"><div class="hot_search">词条按钮×30</div></div>。
  // 以 div.hot_search 为锚（全页唯一），向前回溯到同模块的 h2 起点，向后按 div 配平找到 row 段结尾，整段切除。
  function site_hsex(html) {
    var hs = html.indexOf('<div class="hot_search">');
    if (hs < 0) return html;
    var row = html.lastIndexOf('<div class="row">', hs);
    if (row < 0) return html;
    var h2 = html.lastIndexOf('<h2>', row);
    if (h2 < 0) return html;
    if (html.slice(h2, row).indexOf('热搜') < 0) return html;
    var depth = 0, i = row, end = -1;
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
    var block = html.slice(h2, end);
    if (block.indexOf('hot_search') < 0 || block.indexOf('最热') >= 0) return html;
    return html.slice(0, h2) + html.slice(end);
  }
})();
