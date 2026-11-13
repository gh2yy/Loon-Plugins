// 大众点评 - 去搜索页键盘上方「AI 按住提问」悬浮按钮（halo 配置改写）
// halo.newparam 的 expParam（转义 JSON 串）里三个 AI 搜索入口开关置关：
// - search_keyboard_voice_search：搜索键盘语音搜索（按钮正浮在键盘上方）
// - search_index_enable_ask_dianzai：搜索页「问点仔」提问入口（按钮文案即「按住提问」）
// - aiSearchFixedEntryV2：AI 搜索固定入口
// 只做带键名的精确字符串替换，模式不命中或任一步异常时原样放行。
// 验证：2026-11-13 以 11.75.2 真实抓包样本验证（替换后内外两层 JSON 均可解析、三开关值已翻转、其余不变）。
(function main() {
  try {
    var body = $response.body;
    if (typeof body !== 'string' || body.indexOf('expParam') === -1) { $done({}); return; }
    var pairs = [
      ['search_keyboard_voice_search\\":{\\"val\\":\\"1\\"}', 'search_keyboard_voice_search\\":{\\"val\\":\\"0\\"}'],
      ['search_index_enable_ask_dianzai\\":{\\"val\\":\\"1\\"}', 'search_index_enable_ask_dianzai\\":{\\"val\\":\\"0\\"}'],
      ['aiSearchFixedEntryV2\\":{\\"val\\":\\"true\\"}', 'aiSearchFixedEntryV2\\":{\\"val\\":\\"false\\"}']
    ];
    var changed = false;
    for (var i = 0; i < pairs.length; i++) {
      if (body.indexOf(pairs[i][0]) !== -1) { body = body.replace(pairs[i][0], pairs[i][1]); changed = true; }
    }
    if (changed) { $done({ body: body }); } else { $done({}); }
  } catch (e) { $done({}); }
})();
