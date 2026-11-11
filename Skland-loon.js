/*
 * 森空岛自动签到 for Loon（明日方舟，可选终末地）
 *
 * 逻辑移植自现行维护中的开源实现（skland-kit / 青龙森空岛脚本，2026 年仍在更新的同一套接口）：
 *   鹰角通行证 token -> grant code -> cred -> HMAC-SHA256+MD5 签名请求 -> 绑定角色 -> 签到
 * 数美设备 ID（dId）在脚本内用纯 JS 现场生成（DES / AES / RSA / gzip 均为内置实现，无外部依赖），
 * 生成后存 $persistentStore 复用，与网页版客户端行为一致。
 *
 * 参数（插件 [Argument] 传入，也兼容手动以 argument="Token=xxx&Endfield=false" 形式调试）：
 *   Token    鹰角通行证 token（登录 skland.com 后打开 web-api.skland.com/account/info/hg 取 data.content；
 *            整段 JSON 粘进来也能识别；多账号用英文分号 ; 分隔）
 *   Endfield 是否同时签到终末地（默认关）
 *   Notify   是否发通知（默认开）
 *
 * 日志搜 Skland。token 等同登录凭证，只填在自己手机的插件参数里，切勿外泄。
 */

"use strict";

/* ================= 基础字节工具 ================= */

function utf8Encode(str) {
  var out = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c < 0x80) {
      out.push(c);
    } else if (c < 0x800) {
      out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < str.length && str.charCodeAt(i + 1) >= 0xdc00 && str.charCodeAt(i + 1) <= 0xdfff) {
      var cp = 0x10000 + ((c - 0xd800) << 10) + (str.charCodeAt(i + 1) - 0xdc00);
      out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3f), 0x80 | ((cp >> 6) & 0x3f), 0x80 | (cp & 0x3f));
      i++;
    } else {
      out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(out);
}

function utf8Decode(bytes) {
  var s = "", i = 0, cp, b;
  while (i < bytes.length) {
    b = bytes[i];
    if (b < 0x80) { cp = b; i += 1; }
    else if ((b & 0xe0) === 0xc0) { cp = ((b & 0x1f) << 6) | (bytes[i + 1] & 0x3f); i += 2; }
    else if ((b & 0xf0) === 0xe0) { cp = ((b & 0x0f) << 12) | ((bytes[i + 1] & 0x3f) << 6) | (bytes[i + 2] & 0x3f); i += 3; }
    else { cp = ((b & 0x07) << 18) | ((bytes[i + 1] & 0x3f) << 12) | ((bytes[i + 2] & 0x3f) << 6) | (bytes[i + 3] & 0x3f); i += 4; }
    if (cp < 0x10000) s += String.fromCharCode(cp);
    else { cp -= 0x10000; s += String.fromCharCode(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff)); }
  }
  return s;
}

function bytesToHex(bytes) {
  var s = "";
  for (var i = 0; i < bytes.length; i++) s += ("0" + bytes[i].toString(16)).slice(-2);
  return s;
}

function hexToBytes(hex) {
  var out = new Uint8Array(hex.length / 2);
  for (var i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}

var B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
function bytesToB64(bytes) {
  var s = "", i;
  for (i = 0; i + 3 <= bytes.length; i += 3) {
    var n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    s += B64_ALPHABET[(n >> 18) & 63] + B64_ALPHABET[(n >> 12) & 63] + B64_ALPHABET[(n >> 6) & 63] + B64_ALPHABET[n & 63];
  }
  var rem = bytes.length - i;
  if (rem === 1) {
    var n1 = bytes[i] << 16;
    s += B64_ALPHABET[(n1 >> 18) & 63] + B64_ALPHABET[(n1 >> 12) & 63] + "==";
  } else if (rem === 2) {
    var n2 = (bytes[i] << 16) | (bytes[i + 1] << 8);
    s += B64_ALPHABET[(n2 >> 18) & 63] + B64_ALPHABET[(n2 >> 12) & 63] + B64_ALPHABET[(n2 >> 6) & 63] + "=";
  }
  return s;
}

function randomUuid() {
  var b = new Uint8Array(16), i;
  for (i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  var h = bytesToHex(b);
  return h.substr(0, 8) + "-" + h.substr(8, 4) + "-" + h.substr(12, 4) + "-" + h.substr(16, 4) + "-" + h.substr(20, 12);
}

/* ================= MD5 ================= */

function md5hex(input) {
  var K = [], i;
  for (i = 0; i < 64; i++) K[i] = Math.floor(Math.abs(Math.sin(i + 1)) * 4294967296) >>> 0;
  var S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
           5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
           4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
           6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
  function rl(v, b) { return ((v << b) | (v >>> (32 - b))) >>> 0; }
  var origLen = input.length;
  var paddedLen = (((origLen + 8) >>> 6) + 1) << 6;
  var buf = new Uint8Array(paddedLen);
  buf.set(input);
  buf[origLen] = 0x80;
  var dv = new DataView(buf.buffer);
  dv.setUint32(paddedLen - 8, (origLen << 3) >>> 0, true);
  dv.setUint32(paddedLen - 4, Math.floor(origLen / 536870912) >>> 0, true);
  var a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  var M = new Uint32Array(16);
  for (var off = 0; off < paddedLen; off += 64) {
    for (i = 0; i < 16; i++) M[i] = dv.getUint32(off + i * 4, true);
    var A = a0, B = b0, C = c0, D = d0;
    for (i = 0; i < 64; i++) {
      var F, g;
      if (i < 16) { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
      else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      var tmp = D;
      D = C; C = B;
      B = (B + rl((A + F + K[i] + M[g]) >>> 0, S[i])) >>> 0;
      A = tmp;
    }
    a0 = (a0 + A) >>> 0; b0 = (b0 + B) >>> 0; c0 = (c0 + C) >>> 0; d0 = (d0 + D) >>> 0;
  }
  var out = new Uint8Array(16), odv = new DataView(out.buffer);
  odv.setUint32(0, a0, true); odv.setUint32(4, b0, true); odv.setUint32(8, c0, true); odv.setUint32(12, d0, true);
  return bytesToHex(out);
}

/* ================= SHA-256 / HMAC-SHA256 ================= */

var SHA256_K = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];

function sha256bytes(input) {
  function rr(v, b) { return ((v >>> b) | (v << (32 - b))) >>> 0; }
  var H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  var origLen = input.length;
  var paddedLen = (((origLen + 8) >>> 6) + 1) << 6;
  var buf = new Uint8Array(paddedLen);
  buf.set(input);
  buf[origLen] = 0x80;
  var dv = new DataView(buf.buffer);
  dv.setUint32(paddedLen - 4, (origLen << 3) >>> 0, false);
  dv.setUint32(paddedLen - 8, Math.floor(origLen / 536870912) >>> 0, false);
  var w = new Uint32Array(64);
  for (var off = 0; off < paddedLen; off += 64) {
    var t, i;
    for (t = 0; t < 16; t++) w[t] = dv.getUint32(off + t * 4, false);
    for (t = 16; t < 64; t++) {
      var s0 = (rr(w[t - 15], 7) ^ rr(w[t - 15], 18) ^ (w[t - 15] >>> 3)) >>> 0;
      var s1 = (rr(w[t - 2], 17) ^ rr(w[t - 2], 19) ^ (w[t - 2] >>> 10)) >>> 0;
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) >>> 0;
    }
    var a = H[0], b = H[1], c = H[2], d = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
    for (t = 0; t < 64; t++) {
      var S1 = (rr(e, 6) ^ rr(e, 11) ^ rr(e, 25)) >>> 0;
      var ch = ((e & f) ^ (~e & g)) >>> 0;
      var t1 = (h + S1 + ch + SHA256_K[t] + w[t]) >>> 0;
      var S0 = (rr(a, 2) ^ rr(a, 13) ^ rr(a, 22)) >>> 0;
      var maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      var t2 = (S0 + maj) >>> 0;
      h = g; g = f; f = e; e = (d + t1) >>> 0;
      d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
  }
  var out = new Uint8Array(32), odv = new DataView(out.buffer);
  for (var i = 0; i < 8; i++) odv.setUint32(i * 4, H[i], false);
  return out;
}

function hmacSha256hex(keyBytes, dataBytes) {
  var key = keyBytes;
  if (key.length > 64) key = sha256bytes(key);
  var k = new Uint8Array(64);
  k.set(key);
  var ipad = new Uint8Array(64 + dataBytes.length);
  var opad = new Uint8Array(64 + 32);
  var i;
  for (i = 0; i < 64; i++) { ipad[i] = k[i] ^ 0x36; opad[i] = k[i] ^ 0x5c; }
  ipad.set(dataBytes, 64);
  var inner = sha256bytes(ipad);
  opad.set(inner, 64);
  return bytesToHex(sha256bytes(opad));
}

/* ================= DES（单 DES，ECB，零填充） ================= */
/* 数美指纹里标注的 3DES 在密钥三段相同时与单 DES 等价，现行 Python 实现亦用单 DES。 */

var DES_IP = [58, 50, 42, 34, 26, 18, 10, 2, 60, 52, 44, 36, 28, 20, 12, 4, 62, 54, 46, 38, 30, 22, 14, 6, 64, 56, 48, 40, 32, 24, 16, 8, 57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3, 61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7];
var DES_FP = [40, 8, 48, 16, 56, 24, 64, 32, 39, 7, 47, 15, 55, 23, 63, 31, 38, 6, 46, 14, 54, 22, 62, 30, 37, 5, 45, 13, 53, 21, 61, 29, 36, 4, 44, 12, 52, 20, 60, 28, 35, 3, 43, 11, 51, 19, 59, 27, 34, 2, 42, 10, 50, 18, 58, 26, 33, 1, 41, 9, 49, 17, 57, 25];
var DES_E = [32, 1, 2, 3, 4, 5, 4, 5, 6, 7, 8, 9, 8, 9, 10, 11, 12, 13, 12, 13, 14, 15, 16, 17, 16, 17, 18, 19, 20, 21, 20, 21, 22, 23, 24, 25, 24, 25, 26, 27, 28, 29, 28, 29, 30, 31, 32, 1];
var DES_P = [16, 7, 20, 21, 29, 12, 28, 17, 1, 15, 23, 26, 5, 18, 31, 10, 2, 8, 24, 14, 32, 27, 3, 9, 19, 13, 30, 6, 22, 11, 4, 25];
var DES_PC1 = [57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18, 10, 2, 59, 51, 43, 35, 27, 19, 11, 3, 60, 52, 44, 36, 63, 55, 47, 39, 31, 23, 15, 7, 62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 28, 20, 12, 4];
var DES_PC2 = [14, 17, 11, 24, 1, 5, 3, 28, 15, 6, 21, 10, 23, 19, 12, 4, 26, 8, 16, 7, 27, 20, 13, 2, 41, 52, 31, 37, 47, 55, 30, 40, 51, 45, 33, 48, 44, 49, 39, 56, 34, 53, 46, 42, 50, 36, 29, 32];
var DES_ROT = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];
var DES_SBOX = [
  [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, 0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8, 4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, 15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
  [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, 3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5, 0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, 13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
  [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, 13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1, 13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, 1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
  [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, 13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9, 10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, 3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
  [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, 14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6, 4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, 11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
  [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, 10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8, 9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, 4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
  [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, 13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6, 1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, 6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
  [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, 1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2, 7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, 2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11]
];

function bytesToBits(bytes) {
  var bits = [];
  for (var i = 0; i < bytes.length; i++) for (var j = 7; j >= 0; j--) bits.push((bytes[i] >> j) & 1);
  return bits;
}
function bitsToBytes(bits) {
  var out = new Uint8Array(bits.length / 8);
  for (var i = 0; i < out.length; i++) {
    var v = 0;
    for (var j = 0; j < 8; j++) v = (v << 1) | bits[i * 8 + j];
    out[i] = v;
  }
  return out;
}
function permuteBits(bits, table) {
  var out = new Array(table.length);
  for (var i = 0; i < table.length; i++) out[i] = bits[table[i] - 1];
  return out;
}

function desEncryptBlock(keyBytes, blockBytes) {
  var keyBits = permuteBits(bytesToBits(keyBytes), DES_PC1);
  var C = keyBits.slice(0, 28), D = keyBits.slice(28, 56);
  var subkeys = [], r, i;
  for (r = 0; r < 16; r++) {
    for (i = 0; i < DES_ROT[r]; i++) { C.push(C.shift()); D.push(D.shift()); }
    subkeys.push(permuteBits(C.concat(D), DES_PC2));
  }
  var bits = permuteBits(bytesToBits(blockBytes), DES_IP);
  var L = bits.slice(0, 32), R = bits.slice(32, 64);
  for (r = 0; r < 16; r++) {
    var expanded = permuteBits(R, DES_E);
    for (i = 0; i < 48; i++) expanded[i] ^= subkeys[r][i];
    var sOut = [];
    for (i = 0; i < 8; i++) {
      var six = expanded.slice(i * 6, i * 6 + 6);
      var row = (six[0] << 1) | six[5];
      var col = (six[1] << 3) | (six[2] << 2) | (six[3] << 1) | six[4];
      var v = DES_SBOX[i][row * 16 + col];
      sOut.push((v >> 3) & 1, (v >> 2) & 1, (v >> 1) & 1, v & 1);
    }
    var pOut = permuteBits(sOut, DES_P);
    var newR = new Array(32);
    for (i = 0; i < 32; i++) newR[i] = L[i] ^ pOut[i];
    L = R; R = newR;
  }
  return bitsToBytes(permuteBits(R.concat(L), DES_FP));
}

function desEcbEncryptB64(keyStr, plainStr) {
  var key = utf8Encode(keyStr).slice(0, 8);
  var data = utf8Encode(String(plainStr));
  var padLen = 8 - (data.length % 8);
  var padded = new Uint8Array(data.length + padLen);
  padded.set(data);
  var out = new Uint8Array(padded.length);
  for (var off = 0; off < padded.length; off += 8) {
    out.set(desEncryptBlock(key, padded.slice(off, off + 8)), off);
  }
  return bytesToB64(out);
}

/* ================= AES-128（CBC，PKCS7） ================= */
/* S 盒按 GF(2^8) 求逆 + 仿射变换运行时生成，避免抄表出错（harness 与标准向量对拍）。 */

var AES_SBOX = (function () {
  var exp = new Uint8Array(512), log = new Uint8Array(256);
  var x = 1, i;
  for (i = 0; i < 255; i++) {
    exp[i] = x; log[x] = i;
    var xt = ((x << 1) & 0xff) ^ ((x & 0x80) ? 0x1b : 0);
    x = xt ^ x;
  }
  for (i = 255; i < 512; i++) exp[i] = exp[i - 255];
  function rotl(v, b) { return ((v << b) | (v >> (8 - b))) & 0xff; }
  var box = new Uint8Array(256);
  for (i = 0; i < 256; i++) {
    var inv = i === 0 ? 0 : exp[255 - log[i]];
    box[i] = (inv ^ rotl(inv, 1) ^ rotl(inv, 2) ^ rotl(inv, 3) ^ rotl(inv, 4) ^ 0x63) & 0xff;
  }
  return box;
})();

function aesXtime(v) { return ((v << 1) & 0xff) ^ ((v & 0x80) ? 0x1b : 0); }

function aes128ExpandKey(keyBytes) {
  var w = new Uint8Array(176);
  w.set(keyBytes);
  var rcon = 1;
  for (var i = 16; i < 176; i += 4) {
    var t = [w[i - 4], w[i - 3], w[i - 2], w[i - 1]];
    if (i % 16 === 0) {
      t = [AES_SBOX[t[1]] ^ rcon, AES_SBOX[t[2]], AES_SBOX[t[3]], AES_SBOX[t[0]]];
      rcon = aesXtime(rcon);
    }
    for (var j = 0; j < 4; j++) w[i + j] = w[i - 16 + j] ^ t[j];
  }
  return w;
}

function aesEncryptBlock(expandedKey, round, block) {
  var s = new Uint8Array(16), i, r, c;
  for (i = 0; i < 16; i++) s[i] = block[i] ^ expandedKey[round * 16 + i];
  function subBytes() { for (var k = 0; k < 16; k++) s[k] = AES_SBOX[s[k]]; }
  function shiftRows() {
    var t = new Uint8Array(16);
    for (var r2 = 0; r2 < 4; r2++) for (var c2 = 0; c2 < 4; c2++) t[c2 * 4 + r2] = s[((c2 + r2) % 4) * 4 + r2];
    s.set(t);
  }
  function mixColumns() {
    for (var c3 = 0; c3 < 4; c3++) {
      var a0 = s[c3 * 4], a1 = s[c3 * 4 + 1], a2 = s[c3 * 4 + 2], a3 = s[c3 * 4 + 3];
      s[c3 * 4] = aesXtime(a0) ^ (aesXtime(a1) ^ a1) ^ a2 ^ a3;
      s[c3 * 4 + 1] = a0 ^ aesXtime(a1) ^ (aesXtime(a2) ^ a2) ^ a3;
      s[c3 * 4 + 2] = a0 ^ a1 ^ aesXtime(a2) ^ (aesXtime(a3) ^ a3);
      s[c3 * 4 + 3] = (aesXtime(a0) ^ a0) ^ a1 ^ a2 ^ aesXtime(a3);
    }
  }
  function addRoundKey(rd) { for (var k = 0; k < 16; k++) s[k] ^= expandedKey[rd * 16 + k]; }
  for (r = 1; r <= 9; r++) { subBytes(); shiftRows(); mixColumns(); addRoundKey(r); }
  subBytes(); shiftRows(); addRoundKey(10);
  return s;
}

function aes128CbcEncryptHex(keyStr, ivStr, plainBytes) {
  var key = utf8Encode(keyStr);
  var iv = utf8Encode(ivStr);
  var expanded = aes128ExpandKey(key);
  var padLen = 16 - (plainBytes.length % 16);
  var padded = new Uint8Array(plainBytes.length + padLen);
  padded.set(plainBytes);
  for (var i = plainBytes.length; i < padded.length; i++) padded[i] = padLen;
  var out = new Uint8Array(padded.length);
  var prev = iv;
  for (var off = 0; off < padded.length; off += 16) {
    var block = new Uint8Array(16);
    for (var j = 0; j < 16; j++) block[j] = padded[off + j] ^ prev[j];
    var enc = aesEncryptBlock(expanded, 0, block);
    out.set(enc, off);
    prev = enc;
  }
  return bytesToHex(out);
}

/* ================= RSA PKCS#1 v1.5（公钥加密，BigInt） ================= */
/* 数美公钥（skland-kit / 青龙脚本同源常量），n 由 DER 公钥解析得到，e = 65537。 */

var RSA_N = BigInt("0xa6c4c36bee7f19793d2d13547d8ff98f8b1a229cf91e33e938546227fecd24ecde6b2407e767478c111f9087016fb21ce8d0b36679492947cb88954fc6115afc98ddbcb0a9b0776829ca0aa3d1e3e7066396e2fd195706d260afa2ce4855164d95fdda0ba0c6d6cba6fe52703c9a48ef8348985910727d1b0ada0765ee596a0b");
var RSA_E = 65537n;

function bigIntModPow(base, exp, mod) {
  var result = 1n;
  base = base % mod;
  while (exp > 0n) {
    if (exp & 1n) result = (result * base) % mod;
    exp >>= 1n;
    base = (base * base) % mod;
  }
  return result;
}

function rsaEncryptB64(msgBytes, n, e) {
  var k = 128;
  var psLen = k - msgBytes.length - 3;
  if (psLen < 8) throw new Error("RSA 消息过长");
  var em = new Uint8Array(k);
  em[0] = 0; em[1] = 2;
  for (var i = 0; i < psLen; i++) em[2 + i] = 1 + Math.floor(Math.random() * 255);
  em[2 + psLen] = 0;
  em.set(msgBytes, 3 + psLen);
  var m = 0n;
  for (var j = 0; j < k; j++) m = (m << 8n) | BigInt(em[j]);
  var c = bigIntModPow(m, e, n);
  var out = new Uint8Array(k);
  for (var p = k - 1; p >= 0; p--) { out[p] = Number(c & 0xffn); c >>= 8n; }
  return bytesToB64(out);
}

/* ================= CRC32 / gzip（stored 块） ================= */

var CRC32_TABLE = (function () {
  var table = new Uint32Array(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  var crc = 0xffffffff;
  for (var i = 0; i < bytes.length; i++) crc = CRC32_TABLE[(crc ^ bytes[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function gzipStore(bytes) {
  var out = [];
  var header = [0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 19];
  var i;
  for (i = 0; i < header.length; i++) out.push(header[i]);
  var pos = 0;
  do {
    var chunkLen = Math.min(65535, bytes.length - pos);
    var isFinal = (pos + chunkLen >= bytes.length) ? 1 : 0;
    out.push(isFinal);
    out.push(chunkLen & 0xff, (chunkLen >> 8) & 0xff);
    var nlen = (~chunkLen) & 0xffff;
    out.push(nlen & 0xff, (nlen >> 8) & 0xff);
    for (i = 0; i < chunkLen; i++) out.push(bytes[pos + i]);
    pos += chunkLen;
  } while (pos < bytes.length);
  var crc = crc32(bytes);
  out.push(crc & 0xff, (crc >> 8) & 0xff, (crc >> 16) & 0xff, (crc >> 24) & 0xff);
  var isize = bytes.length >>> 0;
  out.push(isize & 0xff, (isize >> 8) & 0xff, (isize >> 16) & 0xff, (isize >> 24) & 0xff);
  return new Uint8Array(out);
}

/* ================= 数美 dId 生成 ================= */

var SM_ORGANIZATION = "UWXspnCCJN4sfYlNfqps";
var DES_RULE = {
appId: ["uy7mzc4h", "xx", 1], box: [null, "jf", 0], canvas: ["snrn887t", "yk", 1],
clientSize: ["cpmjjgsu", "zx", 1], organization: ["78moqjfc", "dp", 1], os: ["je6vk6t4", "pj", 1],
platform: ["pakxhcd2", "gm", 1], plugins: ["v51m3pzl", "kq", 1], pmf: ["2mdeslu3", "vw", 1],
protocol: [null, "protocol", 0], referer: ["y7bmrjlc", "ab", 1], res: ["whxqm2a7", "hf", 1],
rtype: ["x8o2h2bl", "lo", 1], sdkver: ["9q3dcxp2", "sc", 1], status: ["2jbrxxw4", "an", 1],
subVersion: ["eo3i2puh", "ns", 1], svm: ["fzj3kaeh", "qr", 1], time: ["q2t3odsk", "nb", 1],
timezone: ["1uv05lj5", "as", 1], tn: ["x9nzj1bp", "py", 1], trees: ["acfs0xo4", "pi", 1],
ua: ["k92crp1t", "bj", 1], url: ["y95hjkoo", "cf", 1], version: [null, "version", 0],
vpw: ["r9924ab5", "ca", 1]
};

function getSmId() {
var d = new Date();
function p2(v) { return ("0" + v).slice(-2);}
var timeStr = "" + d.getFullYear() + p2(d.getMonth() + 1) + p2(d.getDate()) + p2(d.getHours()) + p2(d.getMinutes()) + p2(d.getSeconds());
var v = timeStr + md5hex(utf8Encode(randomUuid())) + "00";
return v + md5hex(utf8Encode("smsk_web_" + v)).substring(0, 14) + "0";
}

function getTn(o) {
var keys = Object.keys(o).sort();
var parts = [];
for (var i = 0; i < keys.length; i++) {
var v = o[keys[i]];
if (typeof v === "number") parts.push(String(v * 10000));
else if (typeof v === "object" && v!== null) parts.push(getTn(v));
else parts.push(v? String(v): "");
}
return parts.join("");
}

/* 与 skland-kit gzipObject 一致：JSON 用 ", " / ": " 分隔后再 gzip */
function spacedStringify(obj) {
var parts = [];
var keys = Object.keys(obj);
for (var i = 0; i < keys.length; i++) {
var v = obj[keys[i]];
var vs = (typeof v === "string")? JSON.stringify(v): String(v);
parts.push(JSON.stringify(keys[i]) + ": " + vs);
}
return "{" + parts.join(", ") + "}";
}

function httpRequest(options, attempt) {
attempt = attempt || 0;
var stage = options.stage || options.url;
return new Promise(function (resolve, reject) {
var done = function (err, resp, data) {
if (err) { reject(new Error("网络请求失败（" + stage + "，第 " + (attempt + 1) + " 次）: " + err)); return;}
resolve({ status: resp? (resp.status || resp.statusCode || 0): 0, body: data || ""});
};
var req = { url: options.url, headers: options.headers || {}, timeout: 60};
if (typeof options.body === "string") req.body = options.body;
console.log("[Skland] 请求 " + stage + "（第 " + (attempt + 1) + " 次）");
if (options.method === "POST") $httpClient.post(req, done);
else $httpClient.get(req, done);
}).catch(function (e) {
/* 网络层失败（超时/断连）自动重试，最多共 3 次；业务错误不在这里重试 */
if (attempt >= 2) throw e;
console.log("[Skland] " + e.message + "，2 秒后重试");
return new Promise(function (r) { setTimeout(r, 2000);}).then(function () { return httpRequest(options, attempt + 1);});
});
}

function parseJson(text) {
try { return JSON.parse(text);} catch (e) { return null;}
}

var DID_STORE_KEY = "skland.did";
var UA_APP = "Mozilla/5.0 (Linux; Android 12; SM-A5560 Build/V417IR; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/101.0.4951.61 Safari/537.36; SKLand/1.52.1";
var UA_WEB = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36";

function getDid(forceRefresh) {
if (!forceRefresh) {
var cached = null;
try { cached = $persistentStore.read(DID_STORE_KEY);} catch (e) {}
if (cached) return Promise.resolve(cached);
}
var uid = randomUuid();
var priId = md5hex(utf8Encode(uid)).substring(0, 16);
var ep = rsaEncryptB64(utf8Encode(uid), RSA_N, RSA_E);
var nowMs = Date.now();
var target = {
plugins: "MicrosoftEdgePDFPluginPortableDocumentFormatinternal-pdf-viewer1,MicrosoftEdgePDFViewermhjfbmdgcfjbbpaeojofohoefgiehjai1",
ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36 Edg/129.0.0.0",
canvas: "259ffe69",
timezone: -480,
platform: "Win32",
url: "https://www.skland.com/",
referer: "",
res: "1920_1080_24_1.25",
clientSize: "0_0_1080_1920_1920_1080_1920_1080",
status: "0011",
vpw: randomUuid(),
svm: nowMs,
trees: randomUuid(),
pmf: nowMs,
protocol: 102,
organization: SM_ORGANIZATION,
appId: "default",
os: "web",
version: "3.0.0",
sdkver: "3.0.0",
box: "",
rtype: "all",
smid: getSmId(),
subVersion: "1.0.0",
time: 0
};
target.tn = md5hex(utf8Encode(getTn(target)));
var desResult = {};
var keys = Object.keys(target);
for (var i = 0; i < keys.length; i++) {
var key = keys[i];
var rule = DES_RULE[key];
if (rule) {
if (rule[2] === 1) desResult[rule[1]] = desEcbEncryptB64(rule[0], String(target[key]));
else desResult[rule[1]] = target[key];
} else {
desResult[key] = target[key];
}
}
var gzB64 = bytesToB64(gzipStore(utf8Encode(spacedStringify(desResult))));
var dataHex = aes128CbcEncryptHex(priId, "0102030405060708", utf8Encode(gzB64));
var body = JSON.stringify({
appId: "default", compress: 2, data: dataHex, encode: 5,
ep: ep, organization: SM_ORGANIZATION, os: "web"
});
return httpRequest({
stage: "dId生成/portal101",
method: "POST",
url: "https://fp-it.portal101.cn/deviceprofile/v4",
headers: { "Content-Type": "application/json"},
body: body
}).then(function (res) {
var json = parseJson(res.body);
if (!json || json.code!== 1100 ||!json.detail ||!json.detail.deviceId) {
throw new Error("dId 生成失败: " + res.body.substring(0, 120));
}
var did = "B" + json.detail.deviceId;
try { $persistentStore.write(did, DID_STORE_KEY);} catch (e) {}
return did;
});
}

/* ================= 森空岛接口 ================= */

var SKLAND_APP_CODE = "4ca99fa6b56cc2ba";

function signHeaders(signToken, path, bodyOrQuery, did) {
var ts = String(Math.floor(Date.now() / 1000) - 2);
var headerCa = { platform: "3", timestamp: ts, dId: did, vName: "1.0.0"};
var s = path + bodyOrQuery + ts + JSON.stringify(headerCa);
var sign = md5hex(utf8Encode(hmacSha256hex(utf8Encode(signToken), utf8Encode(s))));
return {
"User-Agent": UA_APP,
"Accept-Encoding": "gzip",
"Connection": "close",
"X-Requested-With": "com.hypergryph.skland",
"dId": did,
"platform": "3",
"timestamp": ts,
"vName": "1.0.0",
"sign": sign
};
}

function grantCode(hgToken, did) {
return httpRequest({
stage: "grant/鹰角授权",
method: "POST",
url: "https://as.hypergryph.com/user/oauth2/v2/grant",
headers: { "User-Agent": UA_APP, "dId": did, "X-Requested-With": "com.hypergryph.skland", "Content-Type": "application/json"},
body: JSON.stringify({ appCode: SKLAND_APP_CODE, token: hgToken, type: 0})
}).then(function (res) {
var json = parseJson(res.body);
if (!json || json.status!== 0 ||!json.data ||!json.data.code) {
throw new Error("grant 失败（token 可能已失效）: " + res.body.substring(0, 120));
}
return json.data.code;
});
}

function generateCred(code, did) {
return httpRequest({
stage: "cred/生成凭证",
method: "POST",
url: "https://zonai.skland.com/web/v1/user/auth/generate_cred_by_code",
headers: {
"Content-Type": "application/json", "User-Agent": UA_WEB,
"referer": "https://www.skland.com/", "origin": "https://www.skland.com",
"dId": did, "platform": "3", "timestamp": String(Math.floor(Date.now() / 1000)), "vName": "1.0.0"
},
body: JSON.stringify({ code: code, kind: 1})
}).then(function (res) {
var json = parseJson(res.body);
if (!json || json.code!== 0 ||!json.data ||!json.data.cred) {
throw new Error("cred 获取失败: " + res.body.substring(0, 120));
}
return { cred: json.data.cred, token: json.data.token};
});
}

function signedRequest(cred, did, method, url, path, bodyOrQuery, bodyStr, extraHeaders) {
var headers = signHeaders(cred.token, path, bodyOrQuery, did);
headers["cred"] = cred.cred;
if (extraHeaders) for (var k in extraHeaders) headers[k] = extraHeaders[k];
if (method === "POST") headers["Content-Type"] = "application/json";
var opt = { stage: "签名接口 " + path, method: method, url: url, headers: headers};
if (typeof bodyStr === "string" && bodyStr.length > 0) opt.body = bodyStr;
return httpRequest(opt).then(function (res) {
var json = parseJson(res.body);
if (!json) throw new Error("接口返回非 JSON（HTTP " + res.status + "）: " + res.body.substring(0, 120));
return json;
});
}

function getBinding(cred, did) {
var url = "https://zonai.skland.com/api/v1/game/player/binding";
return signedRequest(cred, did, "GET", url, "/api/v1/game/player/binding", "").then(function (json) {
if (json.code!== 0) throw new Error("绑定列表获取失败: " + (json.message || JSON.stringify(json).substring(0, 120)));
return (json.data && json.data.list) || [];
});
}

function shanghaiDateStr(date) {
var d = new Date(date.getTime() + 8 * 3600 * 1000);
function p2(v) { return ("0" + v).slice(-2);}
return d.getUTCFullYear() + "-" + p2(d.getUTCMonth() + 1) + "-" + p2(d.getUTCDate());
}

function signArknights(cred, did, binding) {
var uid = binding.uid, gameId = binding.gameId || 1;
var query = "uid=" + encodeURIComponent(uid) + "&gameId=" + gameId;
var statusUrl = "https://zonai.skland.com/api/v1/game/attendance?" + query;
return signedRequest(cred, did, "GET", statusUrl, "/api/v1/game/attendance", query).then(function (st) {
var today = shanghaiDateStr(new Date());
var records = (st.data && st.data.records) || [];
for (var i = 0; i < records.length; i++) {
if (shanghaiDateStr(new Date(Number(records[i].ts) * 1000)) === today) {
return { name: binding.nickName || "博士", result: "今日已签到"};
}
}
var bodyStr = JSON.stringify({ gameId: gameId, uid: uid});
return signedRequest(cred, did, "POST", "https://zonai.skland.com/api/v1/game/attendance", "/api/v1/game/attendance", bodyStr, bodyStr).then(function (json) {
if (json.code!== 0) {
var msg = json.message || "未知错误";
if (msg.indexOf("已签到") >= 0 || msg.indexOf("重复") >= 0) return { name: binding.nickName || "博士", result: "今日已签到"};
throw new Error("明日方舟签到失败: " + msg);
}
var awards = [];
var list = (json.data && json.data.awards) || [];
for (var i = 0; i < list.length; i++) {
var rname = (list[i].resource && list[i].resource.name) || "奖励";
awards.push(rname + "×" + (list[i].count || 1));
}
return { name: binding.nickName || "博士", result: "签到成功" + (awards.length? "：" + awards.join("、"): "")};
});
});
}

function signEndfieldRole(cred, did, binding, role) {
var url = "https://zonai.skland.com/web/v1/game/endfield/attendance";
var path = "/web/v1/game/endfield/attendance";
var extra = {
"sk-game-role": "3_" + role.roleId + "_" + role.serverId,
"referer": "https://game.skland.com/",
"origin": "https://game.skland.com/"
};
return signedRequest(cred, did, "GET", url, path, "", null, extra).then(function (st) {
if (st.data && st.data.hasToday) {
return { name: role.nickname || binding.nickName || "管理员", result: "今日已签到"};
}
return signedRequest(cred, did, "POST", url, path, "", null, extra).then(function (json) {
if (json.code!== 0) {
var msg = json.message || "未知错误";
if (msg.indexOf("已签到") >= 0 || msg.indexOf("重复") >= 0) return { name: role.nickname || binding.nickName || "管理员", result: "今日已签到"};
throw new Error("终末地签到失败: " + msg);
}
var awards = [];
var ids = (json.data && json.data.awardIds) || [];
var map = (json.data && json.data.resourceInfoMap) || {};
for (var i = 0; i < ids.length; i++) {
var info = map[ids[i].id];
if (info) awards.push(info.name + "×" + (info.count || 1));
}
return { name: role.nickname || binding.nickName || "管理员", result: "签到成功" + (awards.length? "：" + awards.join("、"): "")};
});
});
}

function runAccount(hgToken, includeEndfield, forceFreshDid) {
return getDid(forceFreshDid).then(function (did) {
return grantCode(hgToken, did).then(function (code) {
return generateCred(code, did);
}).then(function (cred) {
return getBinding(cred, did).then(function (list) {
var jobs = [];
for (var i = 0; i < list.length; i++) {
var item = list[i];
var bindings = item.bindingList || [];
for (var j = 0; j < bindings.length; j++) {
(function (appCode, b) {
if (appCode === "arknights") {
jobs.push(signArknights(cred, did, b).then(function (r) {
return "" + r.name + " " + r.result;
}));
} else if (appCode === "endfield" && includeEndfield) {
var roles = b.roles || [];
for (var k = 0; k < roles.length; k++) {
(function (role) {
jobs.push(signEndfieldRole(cred, did, b, role).then(function (r) {
return "" + r.name + " " + r.result;
}));
})(roles[k]);
}
}
})(item.appCode, bindings[j]);
}
}
if (!jobs.length) return ["未找到可签到的绑定角色（终末地默认关闭，可在插件参数里打开）"];
return Promise.all(jobs);
});
});
});
}

/* ================= 入口 ================= */

function parseHgToken(raw) {
var t = String(raw || "").trim();
if (!t) return "";
try {
var j = JSON.parse(t);
if (j && j.data && typeof j.data.content === "string") return j.data.content;
} catch (e) {}
return t;
}

function argBool(v, dft) {
if (typeof v === "boolean") return v;
if (typeof v === "string") return v === "true" || v === "1";
if (typeof v === "number") return v!== 0;
return dft;
}

function main() {
var args = (typeof $argument!== "undefined" && $argument)? $argument: {};
if (typeof args === "string") {
var parsed = {};
args.split("&").forEach(function (pair) {
var idx = pair.indexOf("=");
if (idx > 0) parsed[decodeURIComponent(pair.substring(0, idx))] = decodeURIComponent(pair.substring(idx + 1));
});
args = parsed;
}
var notify = argBool(args.Notify, true);
var includeEndfield = argBool(args.Endfield, false);
var rawToken = args.Token || "";
var tokens = String(rawToken).split(/[;,\n]/).map(parseHgToken).filter(function (t) { return!!t;});

function finish(title, body) {
console.log("[Skland] " + title + (body? "\n" + body: ""));
if (notify) $notification.post(title, "", body || "");
}

if (!tokens.length) {
finish("森空岛签到未配置", "插件参数 Token 为空。登录 skland.com 后打开 web-api.skland.com/account/info/hg，把 data.content 粘到插件的 Token 参数里。");
$done();
return;
}

var all = tokens.map(function (t, idx) {
return runAccount(t, includeEndfield, false).catch(function (err) {
/* 失败且用的是缓存 dId 时，换新 dId 重试一次（dId 被服务端淘汰的兜底） */
var hadCachedDid = false;
try { hadCachedDid =!!$persistentStore.read(DID_STORE_KEY);} catch (e) {}
if (!hadCachedDid) throw err;
console.log("[Skland] 账号 " + (idx + 1) + " 首次失败（" + err.message + "），刷新 dId 重试");
return runAccount(t, includeEndfield, true);
}).then(function (lines) {
return lines.map(function (l) { return (tokens.length > 1? "账号" + (idx + 1) + " ": "") + l;});
}).catch(function (err) {
return ["账号" + (idx + 1) + " 签到失败：" + err.message];
});
});

Promise.all(all).then(function (grouped) {
var lines = [];
grouped.forEach(function (g) { lines = lines.concat(g);});
var failed = lines.some(function (l) { return l.indexOf("失败") >= 0;});
finish(failed? "森空岛签到（部分失败）": "森空岛签到完成", lines.join("\n"));
$done();
}).catch(function (err) {
finish("森空岛签到失败", String(err && err.message || err));
$done();
});
}

main();
