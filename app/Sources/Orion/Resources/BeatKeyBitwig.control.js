// Beat Key controller script for Bitwig Studio.
// Installed by Beat Key as ~/Documents/Bitwig Studio/Controller Scripts/Beat Key/BeatKey.control.js
// and added in Bitwig: Settings > Controllers > Add Controller > Four Letter Records > Beat Key.
//
// OSC over UDP: listens on 127.0.0.1:11043, answers on 127.0.0.1:11044 (the datagram observer
// does not tell who sent a packet).
//   /beatkey/ping        -> /beatkey/pong ,s version
//   /beatkey/set ,f bpm  -> /beatkey/ok   ,f tempo (read back on the next observer update)
// Bitwig has no project key: tempo only (Transport.tempo().value().setRaw(bpm)).

if (typeof loadAPI === "function") {   // inside Bitwig (tests load this file in node)
   loadAPI(17);
   host.defineController("Four Letter Records", "Beat Key", "1.0", "6f1b6a52-3c55-4d0e-9a3b-6c1f0e1b7a41", "Beat Key");
   host.defineMidiPorts(0, 0);
}

var BEATKEY_VERSION = "1";
var LISTEN_PORT = 11043;
var REPLY_PORT = 11044;
var transport = null;

function u8(b) { return b & 0xff; }

function oscString(bytes, i) {
   var s = "";
   while (i < bytes.length && u8(bytes[i]) !== 0) { s += String.fromCharCode(u8(bytes[i])); i++; }
   return { value: s, next: (i + 4) & ~3 };
}

function oscDecode(bytes) {
   var a = oscString(bytes, 0);
   if (a.value.charAt(0) !== "/") return null;
   var msg = { address: a.value, args: [] };
   if (a.next >= bytes.length) return msg;
   var t = oscString(bytes, a.next), i = t.next;
   for (var k = 1; k < t.value.length; k++) {
      var c = t.value.charAt(k);
      if (c === "i" || c === "f") {
         var w = ((u8(bytes[i]) << 24) | (u8(bytes[i + 1]) << 16) | (u8(bytes[i + 2]) << 8) | u8(bytes[i + 3])) | 0;
         i += 4;
         if (c === "i") msg.args.push(w);
         else msg.args.push(floatFromBits(w));
      } else if (c === "s") {
         var s = oscString(bytes, i); msg.args.push(s.value); i = s.next;
      } else return null;
   }
   return msg;
}

function floatFromBits(w) {
   var sign = (w >>> 31) ? -1 : 1, exp = (w >>> 23) & 0xff, frac = w & 0x7fffff;
   if (exp === 0) return sign * frac * Math.pow(2, -149);
   if (exp === 255) return frac ? NaN : sign * Infinity;
   return sign * (1 + frac / 8388608) * Math.pow(2, exp - 127);
}

function bitsFromFloat(f) {
   if (f === 0) return 0;
   var sign = f < 0 ? 1 : 0; f = Math.abs(f);
   var exp = Math.floor(Math.log(f) / Math.LN2);
   if (Math.pow(2, exp) > f) exp--;
   if (Math.pow(2, exp + 1) <= f) exp++;
   var frac = Math.round((f / Math.pow(2, exp) - 1) * 8388608);
   if (frac === 8388608) { frac = 0; exp++; }
   return ((sign << 31) | ((exp + 127) << 23) | frac) | 0;
}

function pad(out) { out.push(0); while (out.length % 4) out.push(0); }

function oscEncode(address, args) {
   var out = [], tags = ",", body = [], k, j;
   for (j = 0; j < address.length; j++) out.push(address.charCodeAt(j) & 0x7f);
   pad(out);
   for (k = 0; k < args.length; k++) {
      var a = args[k];
      if (typeof a === "number") {
         tags += "f";
         var w = bitsFromFloat(a);
         body.push((w >>> 24) & 0xff, (w >>> 16) & 0xff, (w >>> 8) & 0xff, w & 0xff);
      } else {
         tags += "s";
         var s = String(a);
         for (j = 0; j < s.length; j++) body.push(s.charCodeAt(j) & 0x7f);
         pad(body);
      }
   }
   for (j = 0; j < tags.length; j++) out.push(tags.charCodeAt(j));
   pad(out);
   out = out.concat(body);
   // Java bytes are signed
   for (j = 0; j < out.length; j++) if (out[j] > 127) out[j] -= 256;
   return out;
}

// One request -> the reply bytes. setTempo/getTempo are injected so this runs outside Bitwig.
function beatKeyHandle(bytes, setTempo, getTempo) {
   var m = oscDecode(bytes);
   if (!m) return null;
   if (m.address === "/beatkey/ping") return oscEncode("/beatkey/pong", [BEATKEY_VERSION]);
   if (m.address === "/beatkey/set") {
      var bpm = m.args.length ? m.args[0] : 0;
      if (bpm > 0) setTempo(Math.max(20, Math.min(666, bpm)));
      return oscEncode("/beatkey/ok", [bpm > 0 ? bpm : getTempo()]);
   }
   return oscEncode("/beatkey/error", ["unknown request " + m.address]);
}

function init() {
   transport = host.createTransport();
   transport.tempo().value().markInterested();
   var bound = host.addDatagramPacketObserver("Beat Key", LISTEN_PORT, function (data) {
      var reply = beatKeyHandle(data,
         function (bpm) { transport.tempo().value().setRaw(bpm); },
         function () { return transport.tempo().value().getRaw(); });
      if (reply) host.sendDatagramPacket("127.0.0.1", REPLY_PORT, reply);
   });
   if (!bound) host.errorln("Beat Key could not open UDP port " + LISTEN_PORT);
   else host.println("Beat Key listening on 127.0.0.1:" + LISTEN_PORT);
}

function exit() {}

if (typeof module !== "undefined") module.exports = { oscEncode: oscEncode, oscDecode: oscDecode, beatKeyHandle: beatKeyHandle, bitsFromFloat: bitsFromFloat, floatFromBits: floatFromBits };
