// 虎扑首页推荐流去游戏推广卡 v1 (2026-11-21)
// 特征（服务器下发的展示文案，App 包内不存在这些字符串）：
// 「读取进度」按钮、底部「xx万+JRs 玩过」、右上「你玩过的」标签、shaper 小游戏链接。
// 单条命中 >=2 组特征才删，防误伤正常帖；命中时弹通知报标题，可核对。
const MARKER_GROUPS = [
  ['读取进度'],
  ['JRs 玩过', 'JRs玩过'],
  ['你玩过的'],
  ['drj_aigame', 'shaper/published', '/shaper/']
];

function markerScore(item) {
  const s = JSON.stringify(item);
  let score = 0;
  for (const group of MARKER_GROUPS) {
    if (group.some(m => s.includes(m))) score++;
  }
  return score;
}

function isCardLike(v) {
  return v && typeof v === 'object' && !Array.isArray(v) && Object.keys(v).length >= 4;
}

function cleanse(node, dropped) {
  if (Array.isArray(node)) {
    for (let i = node.length - 1; i >= 0; i--) {
      const el = node[i];
      if (isCardLike(el) && markerScore(el) >= 2) {
        dropped.push(el);
        node.splice(i, 1);
      } else {
        cleanse(el, dropped);
      }
    }
  } else if (node && typeof node === 'object') {
    for (const k of Object.keys(node)) cleanse(node[k], dropped);
  }
}

function pickTitle(item) {
  const s = JSON.stringify(item);
  const m = s.match(/"(?:title|content|name|desc)":"([^"]{1,50})"/);
  return m ? m[1] : '';
}

try {
  const obj = JSON.parse($response.body);
  const dropped = [];
  cleanse(obj, dropped);
  if (dropped.length) {
    $notification.post('虎扑游戏推广卡已过滤', '删掉 ' + dropped.length + ' 条', pickTitle(dropped[0]));
    $done({ body: JSON.stringify(obj) });
  } else {
    $done({});
  }
} catch (e) {
  $done({});
}
