// 大众点评 - 搜索落地页空响应（替代 xingjiu 两条 reject 的优化）
// 背景：searchdirectsuggest.bin / hotsuggest.bin 原为 reject(404)，App 原生网络层对 404
// 会重试（2026-11-15 抓包实证：hotsuggest 首个 404 后约 1 秒重发），落地页要等失败
// 落定才渲染，本地的历史搜索被连带堵住数秒（用户录屏实证）。
// 改法：请求照常发出、走成功路径，本脚本把响应体整体换成「空数组」dpobject——与服务
// 器对 loadsplashconfig 的无数据应答同形（根空数组），经同一套 stored-gzip + AES 回送。
// 页面模型（搜索联想页包内 Bl.from）对缺失字段全部有默认值：hotRankList /
// suggestEntryList / directJumpConfig 均落为空，点评热点与推荐词条不显示；addToDirectMap
// 对无 url 的响应直接跳过。任一步异常时原样放行（退回服务器真实响应）。
// 证据链：2026-11-15 读 pexus-search-suggest 现行包源码 + capture9 重试时序；待用户真机实测。
var DP_KEY = [0x44,0x37,0x43,0x36,0x46,0x37,0x31,0x41,0x31,0x32,0x31,0x35,0x33,0x45,0x45,0x35];
var DP_IV  = [0x35,0x35,0x43,0x39,0x33,0x30,0x44,0x38,0x32,0x37,0x42,0x44,0x41,0x42,0x46,0x44];

function gfMul(a, b) { var p = 0; for (var i = 0; i < 8; i++) { if (b & 1) p ^= a; var hi = a & 0x80; a = (a << 1) & 0xff; if (hi) a ^= 0x1b; b >>= 1; } return p; }
var SBOX = [], INV_SBOX = [], MUL2 = [], MUL3 = [], MUL9 = [], MUL11 = [], MUL13 = [], MUL14 = [];
(function buildTables() {
  var inv = [0];
  for (var i = 1; i < 256; i++) { for (var j = 1; j < 256; j++) if (gfMul(i, j) === 1) { inv[i] = j; break; } }
  function affine(x) { return (x ^ ((x << 1) | (x >> 7)) ^ ((x << 2) | (x >> 6)) ^ ((x << 3) | (x >> 5)) ^ ((x << 4) | (x >> 4)) ^ 0x63) & 0xff; }
  for (var k = 0; k < 256; k++) {
    var s = affine(inv[k]); SBOX[k] = s; INV_SBOX[s] = k;
    MUL2[k] = gfMul(k, 2); MUL3[k] = gfMul(k, 3); MUL9[k] = gfMul(k, 9);
    MUL11[k] = gfMul(k, 11); MUL13[k] = gfMul(k, 13); MUL14[k] = gfMul(k, 14);
  }
})();
var RCON = [1, 2, 4, 8, 16, 32, 64, 128, 27, 54];
function aesExpandKey(key) {
  var w = key.slice(0, 16);
  for (var i = 4; i < 44; i++) {
    var t = [w[(i - 1) * 4], w[(i - 1) * 4 + 1], w[(i - 1) * 4 + 2], w[(i - 1) * 4 + 3]];
    if (i % 4 === 0) t = [SBOX[t[1]] ^ RCON[i / 4 - 1], SBOX[t[2]], SBOX[t[3]], SBOX[t[0]]];
    for (var j = 0; j < 4; j++) w.push(w[(i - 4) * 4 + j] ^ t[j]);
  }
  return w;
}
function aesBlock(block, w, decrypt) {
  var s = block.slice(0, 16), r, c;
  function addKey(round) { for (var i = 0; i < 16; i++) s[i] ^= w[round * 16 + i]; }
  function sub(inv) { for (var i = 0; i < 16; i++) s[i] = inv ? INV_SBOX[s[i]] : SBOX[s[i]]; }
  function shift(inv) {
    var o = s.slice(0, 16);
    for (var row = 0; row < 4; row++) for (var col = 0; col < 4; col++) {
      var src = inv ? (col - row + 4) % 4 : (col + row) % 4;
      s[col * 4 + row] = o[src * 4 + row];
    }
  }
  function mix() {
    for (c = 0; c < 4; c++) { var a0 = s[c*4], a1 = s[c*4+1], a2 = s[c*4+2], a3 = s[c*4+3];
      s[c*4]   = MUL2[a0] ^ MUL3[a1] ^ a2 ^ a3;
      s[c*4+1] = a0 ^ MUL2[a1] ^ MUL3[a2] ^ a3;
      s[c*4+2] = a0 ^ a1 ^ MUL2[a2] ^ MUL3[a3];
      s[c*4+3] = MUL3[a0] ^ a1 ^ a2 ^ MUL2[a3]; }
  }
  function invMix() {
    for (c = 0; c < 4; c++) { var a0 = s[c*4], a1 = s[c*4+1], a2 = s[c*4+2], a3 = s[c*4+3];
      s[c*4]   = MUL14[a0] ^ MUL11[a1] ^ MUL13[a2] ^ MUL9[a3];
      s[c*4+1] = MUL9[a0] ^ MUL14[a1] ^ MUL11[a2] ^ MUL13[a3];
      s[c*4+2] = MUL13[a0] ^ MUL9[a1] ^ MUL14[a2] ^ MUL11[a3];
      s[c*4+3] = MUL11[a0] ^ MUL13[a1] ^ MUL9[a2] ^ MUL14[a3]; }
  }
  if (!decrypt) {
    addKey(0);
    for (r = 1; r < 10; r++) { sub(false); shift(false); mix(); addKey(r); }
    sub(false); shift(false); addKey(10);
  } else {
    addKey(10);
    for (r = 9; r >= 1; r--) { sub(true); shift(true); addKey(r); invMix(); }
    sub(true); shift(true); addKey(0);
  }
  return s;
}
function aesCbc(data, key, iv, decrypt) {
  var w = aesExpandKey(key), out = [], prev = iv.slice(0, 16), i, j;
  for (i = 0; i < data.length; i += 16) {
    var blk = []; for (j = 0; j < 16; j++) blk[j] = data[i + j];
    if (!decrypt) { for (j = 0; j < 16; j++) blk[j] ^= prev[j]; var enc = aesBlock(blk, w, false); for (j = 0; j < 16; j++) out.push(enc[j]); prev = enc; }
    else { var dec = aesBlock(blk, w, true); for (j = 0; j < 16; j++) out.push(dec[j] ^ prev[j]); prev = blk; }
  }
  return out;
}

function inflate(data) {
  var pos = 0, bitbuf = 0, bitcnt = 0, out = [];
  function bits(n) { while (bitcnt < n) { bitbuf |= data[pos++] << bitcnt; bitcnt += 8; } var v = bitbuf & ((1 << n) - 1); bitbuf >>= n; bitcnt -= n; return v; }
  function huff(lengths) {
    var max = 0, i; for (i = 0; i < lengths.length; i++) if (lengths[i] > max) max = lengths[i];
    var bl = new Array(max + 1).fill(0); for (i = 0; i < lengths.length; i++) if (lengths[i]) bl[lengths[i]]++;
    var code = 0, next = new Array(max + 1).fill(0);
    for (i = 1; i <= max; i++) { code = (code + bl[i - 1]) << 1; next[i] = code; }
    var map = {};
    for (i = 0; i < lengths.length; i++) if (lengths[i]) { var c = next[lengths[i]]++; map[lengths[i] + ':' + c] = i; }
    return { map: map, max: max };
  }
  function decode(h) {
    var code = 0;
    for (var len = 1; len <= h.max; len++) { code = (code << 1) | bits(1); var k = len + ':' + code; if (k in h.map) return h.map[k]; }
    throw new Error('inflate: bad code');
  }
  var LB = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
  var LE = [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
  var DB = [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
  var DE = [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];
  var last = 0;
  while (!last) {
    last = bits(1); var type = bits(2);
    if (type === 0) {
      bitbuf = 0; bitcnt = 0;
      var len = data[pos] | (data[pos + 1] << 8); pos += 4;
      for (var i = 0; i < len; i++) out.push(data[pos++]);
    } else {
      var lh, dh;
      if (type === 2) {
        var hlit = bits(5) + 257, hdist = bits(5) + 1, hclen = bits(4) + 4;
        var order = [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
        var cl = new Array(19).fill(0);
        for (var j = 0; j < hclen; j++) cl[order[j]] = bits(3);
        var ch = huff(cl), lens = [];
        while (lens.length < hlit + hdist) {
          var sym = decode(ch);
          if (sym < 16) lens.push(sym);
          else if (sym === 16) { var rep = 3 + bits(2), pv = lens[lens.length - 1]; while (rep--) lens.push(pv); }
          else if (sym === 17) { var r2 = 3 + bits(3); while (r2--) lens.push(0); }
          else { var r3 = 11 + bits(7); while (r3--) lens.push(0); }
        }
        lh = huff(lens.slice(0, hlit)); dh = huff(lens.slice(hlit));
      } else {
        var fl = [], fd = [], q;
        for (q = 0; q < 288; q++) fl.push(q < 144 ? 8 : q < 256 ? 9 : q < 280 ? 7 : 8);
        for (q = 0; q < 32; q++) fd.push(5);
        lh = huff(fl); dh = huff(fd);
      }
      while (true) {
        var s2 = decode(lh);
        if (s2 === 256) break;
        if (s2 < 256) out.push(s2);
        else {
          var li = s2 - 257, length = LB[li] + bits(LE[li]);
          var ds = decode(dh), dist = DB[ds] + bits(DE[ds]);
          for (var m = 0; m < length; m++) out.push(out[out.length - dist]);
        }
      }
    }
  }
  return out;
}
function gunzip(data) {
  if (data[0] !== 0x1f || data[1] !== 0x8b || data[2] !== 8) throw new Error('not gzip');
  var flg = data[3], pos = 10;
  if (flg & 4) { var xlen = data[pos] | (data[pos + 1] << 8); pos += 2 + xlen; }
  if (flg & 8) { while (data[pos++]) {} }
  if (flg & 16) { while (data[pos++]) {} }
  if (flg & 2) pos += 2;
  return inflate(data.slice(pos));
}
var CRC_TABLE = (function () { var t = []; for (var n = 0; n < 256; n++) { var c = n; for (var k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1); t[n] = c >>> 0; } return t; })();
function crc32(data) { var c = 0xffffffff; for (var i = 0; i < data.length; i++) c = CRC_TABLE[(c ^ data[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }
function gzipStored(data) {
  var out = [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3], pos = 0;
  if (data.length === 0) out.push(1, 0, 0, 0xff, 0xff);
  while (pos < data.length) {
    var chunk = Math.min(65535, data.length - pos);
    out.push(pos + chunk >= data.length ? 1 : 0, chunk & 0xff, (chunk >> 8) & 0xff, (~chunk) & 0xff, ((~chunk) >> 8) & 0xff);
    for (var i = 0; i < chunk; i++) out.push(data[pos + i]);
    pos += chunk;
  }
  var crc = crc32(data), sz = data.length >>> 0;
  out.push(crc & 0xff, (crc >>> 8) & 0xff, (crc >>> 16) & 0xff, (crc >>> 24) & 0xff, sz & 0xff, (sz >>> 8) & 0xff, (sz >>> 16) & 0xff, (sz >>> 24) & 0xff);
  return out;
}

function serialize(node) {
  if (node.type === 0x42 && node.repl) {
    var d = node.repl;
    return [0x42, (d.length >>> 24) & 0xff, (d.length >>> 16) & 0xff, (d.length >>> 8) & 0xff, d.length & 0xff].concat(d);
  }
  if (node.type === 0x41) {
    var out = [0x41, (node.children.length >> 8) & 0xff, node.children.length & 0xff];
    node.children.forEach(function (ch) { out = out.concat(serialize(ch)); });
    return out;
  }
  if (node.type === 0x4f || node.type === 0x51) {
    var o = [node.type];
    if (node.type === 0x4f) o.push((node.schema >> 8) & 0xff, node.schema & 0xff);
    else o.push((node.schema >>> 24) & 0xff, (node.schema >>> 16) & 0xff, (node.schema >>> 8) & 0xff, node.schema & 0xff);
    node.fields.forEach(function (f) { o.push(0x4d, (f.hash >> 8) & 0xff, f.hash & 0xff); o = o.concat(serialize(f.value)); });
    o.push(0x5a);
    return o;
  }
  return node.raw;
}

(function main() {
  try {
    var empty = serialize({ type: 0x41, children: [] });
    var gz = gzipStored(empty);
    while (gz.length % 16 !== 0) gz.push(0);
    var enc = aesCbc(gz, DP_KEY, DP_IV, false);
    $done({ body: new Uint8Array(enc) });
  } catch (e) {
    $done({});
  }
})();
