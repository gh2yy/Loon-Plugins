// 虎扑 - 去广告（interfaceAd/getOther 接口回空广告）
// 原作者：热心群友
// 修改日期：2026-10-30
// 修改日志：
// - 2026-10-30 Muse：按群友投稿的 mock 逻辑转 Loon 脚本。命中 goblin.hupu.com 的 interfaceAd/getOther 时，直接回固定空广告 JSON {"ad_code":-41,"show_type":0,"ads":[]}（投稿原逻辑），不等待不白屏；其余响应不经过本脚本。
(function () {
  $done({ body: JSON.stringify({ ad_code: -41, show_type: 0, ads: [] }) });
})();
