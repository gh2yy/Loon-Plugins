// 大众点评 - 去「我的」页底部「我的收藏 / 最近浏览」整段（halo 配置改写）
// UserCenter 包源码定案：页面按 halo 键 my_favor_history 决定是否创建收藏/浏览模块
// （list + tabList 两个模块）：该键 === "s_a" 才显示，其余值整段不创建（App 自带降级路径同理）。
// 本脚本只把 my_favor_history 的 "s_a" 精确替换为 "nothing"，其余配置一律不碰；
// 模式不命中或任一步异常时原样放行。
// 验证：2026-11-14 以 11.75.2 真实抓包样本验证（替换后内外两层 JSON 均可解析、仅此一值变化）。
// 注：2026-11-13 曾在此通道改三个 AI 搜索开关，同期用户遇 App 没网（归因未隔离：脚本或服务端风控），
// 经用户要求回退；本次应用户新需求只动这一个键，若再现没网，禁用插件即恢复。
(function main() {
  try {
    var body = $response.body;
    if (typeof body !== 'string' || body.indexOf('expParam') === -1) { $done({}); return; }
    var from = 'my_favor_history\\":{\\"val\\":\\"s_a\\"}';
    var to = 'my_favor_history\\":{\\"val\\":\\"nothing\\"}';
    if (body.indexOf(from) !== -1) { $done({ body: body.replace(from, to) }); } else { $done({}); }
  } catch (e) { $done({}); }
})();
