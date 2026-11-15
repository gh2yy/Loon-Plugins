// 大众点评 - halo 配置改写
// 去「我的」页底部「我的收藏 / 最近浏览」整段：UserCenter 包源码定案，页面按 halo 键
// my_favor_history 决定是否创建收藏/浏览模块（list + tabList）：==="s_a" 才显示，
// 其余值整段不创建。本脚本只将其 "s_a" 精确替换为 "nothing"，其余配置一律不碰；
// 模式不命中或任一步异常时原样放行。2026-11-14 用户实测确认去掉、未再现没网，定版。
//
// 附记（已关闭，勿再试）：搜索页「AI 按住提问」悬浮按钮经两轮实测无 halo 存废开关——
// search_keyboard_voice_search、search_index_enable_ask_dianzai（第一轮）与
// aiSearchFixedEntryV2（第二轮）均已翻转验证无效；搜索联想页包源码里该按钮模块
// VoiceInputEntranceModule 无条件创建，包内键 search_new_voice_ui 只切换按钮样式。
// 三键已全部回退，不再保留无效改动。
(function main() {
  try {
    var body = $response.body;
    if (typeof body !== 'string' || body.indexOf('expParam') === -1) { $done({}); return; }
    var from = 'my_favor_history\\":{\\"val\\":\\"s_a\\"}';
    var to = 'my_favor_history\\":{\\"val\\":\\"nothing\\"}';
    if (body.indexOf(from) !== -1) { $done({ body: body.replace(from, to) }); } else { $done({}); }
  } catch (e) { $done({}); }
})();
