// 大众点评 - halo 配置改写（两项）
// ① 去「我的」页底部「我的收藏 / 最近浏览」整段：UserCenter 包源码定案，页面按 halo 键
//    my_favor_history 决定是否创建收藏/浏览模块（list + tabList）：==="s_a" 才显示，
//    其余值整段不创建。本脚本将其 "s_a" 精确替换为 "nothing"。
// ② 去搜索页键盘上方「AI 按住提问」悬浮按钮：其开关在同一份 halo 配置里，本次先翻转两个
//    直指该按钮的键——search_keyboard_voice_search（搜索键盘语音搜索）与
//    search_index_enable_ask_dianzai（搜索页问点仔）由 "1" 改 "0"；aiSearchFixedEntryV2
//    本轮不动，若按钮还在下一轮再翻（2026-11-13 三键版与当晚没网同期、归因未隔离，故分步）。
//    2026-11-14 ①已由用户实测确认去掉且未再现没网，halo 通道本身已验证可用。
// 均为带键名的精确字符串替换，模式不命中或任一步异常时原样放行，其余配置一律不碰。
(function main() {
  try {
    var body = $response.body;
    if (typeof body !== 'string' || body.indexOf('expParam') === -1) { $done({}); return; }
    var pairs = [
      ['my_favor_history\\":{\\"val\\":\\"s_a\\"}', 'my_favor_history\\":{\\"val\\":\\"nothing\\"}'],
      ['search_keyboard_voice_search\\":{\\"val\\":\\"1\\"}', 'search_keyboard_voice_search\\":{\\"val\\":\\"0\\"}'],
      ['search_index_enable_ask_dianzai\\":{\\"val\\":\\"1\\"}', 'search_index_enable_ask_dianzai\\":{\\"val\\":\\"0\\"}']
    ];
    var out = body, hit = false;
    for (var i = 0; i < pairs.length; i++) {
      if (out.indexOf(pairs[i][0]) !== -1) { out = out.replace(pairs[i][0], pairs[i][1]); hit = true; }
    }
    if (hit) { $done({ body: out }); } else { $done({}); }
  } catch (e) { $done({}); }
})();
