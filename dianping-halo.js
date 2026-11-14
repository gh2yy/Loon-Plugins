// 大众点评 - halo 配置改写（两项）
// ① 去「我的」页底部「我的收藏 / 最近浏览」整段：UserCenter 包源码定案，页面按 halo 键
//    my_favor_history 决定是否创建收藏/浏览模块（list + tabList）：==="s_a" 才显示，
//    其余值整段不创建。本脚本将其 "s_a" 精确替换为 "nothing"。
// ② 去搜索页键盘上方「AI 按住提问」悬浮按钮：其开关在同一份 halo 配置里，分两轮翻转——
//    第一轮 search_keyboard_voice_search 与 search_index_enable_ask_dianzai 由 "1" 改 "0"，
//    2026-11-15 用户实测按钮仍在，排除这两键。第二轮加翻 aiSearchFixedEntryV2（AI 搜索固定
//    入口）由 "true" 改 "false"：依据是搜索联想页 Picasso 包源码里该按钮模块
//    （VoiceInputEntranceModule）无条件创建、包内唯一相关键 search_new_voice_ui 只切换按钮
//    样式（pressToAsk/normal，两种样式都显示）不决定存废；而候选键中只有 aiSearchFixedEntryV2
//    出现在 App 主二进制的字符串表里，是原生侧的固定入口开关。
//    2026-11-14 ①已由用户实测确认去掉且未再现没网，halo 通道本身已验证可用。
// 均为带键名的精确字符串替换，模式不命中或任一步异常时原样放行，其余配置一律不碰。
(function main() {
  try {
    var body = $response.body;
    if (typeof body !== 'string' || body.indexOf('expParam') === -1) { $done({}); return; }
    var pairs = [
      ['my_favor_history\\":{\\"val\\":\\"s_a\\"}', 'my_favor_history\\":{\\"val\\":\\"nothing\\"}'],
      ['search_keyboard_voice_search\\":{\\"val\\":\\"1\\"}', 'search_keyboard_voice_search\\":{\\"val\\":\\"0\\"}'],
      ['search_index_enable_ask_dianzai\\":{\\"val\\":\\"1\\"}', 'search_index_enable_ask_dianzai\\":{\\"val\\":\\"0\\"}'],
      ['aiSearchFixedEntryV2\\":{\\"val\\":\\"true\\"}', 'aiSearchFixedEntryV2\\":{\\"val\\":\\"false\\"}']
    ];
    var out = body, hit = false;
    for (var i = 0; i < pairs.length; i++) {
      if (out.indexOf(pairs[i][0]) !== -1) { out = out.replace(pairs[i][0], pairs[i][1]); hit = true; }
    }
    if (hit) { $done({ body: out }); } else { $done({}); }
  } catch (e) { $done({}); }
})();
