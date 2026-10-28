#if !APP_STORE
// JavaScript runtime for Paperback 0.9 extensions, kept in code so no script file ships in the App Store build.
enum PaperbackShim {
    static let source = #"""
// Minimal Paperback 0.9 runtime for Folio Reader. Loaded before an extension bundle.
// The host provides __native.{request, sleep, getState, setState}; there is no DOM and no storage here.
(function (g) {
  var native = g.__native;
  var interceptors = {};
  var secure = {};

  var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  function b64decodeBytes(text) {
    text = String(text).replace(/[^A-Za-z0-9+\/]/g, "");
    var out = new Uint8Array(Math.floor(text.length * 3 / 4)), o = 0, bits = 0, acc = 0;
    for (var i = 0; i < text.length; i++) {
      acc = (acc << 6) | B64.indexOf(text.charAt(i)); bits += 6;
      if (bits >= 8) { bits -= 8; out[o++] = (acc >> bits) & 255; }
    }
    return out.subarray(0, o);
  }
  function b64encodeString(text) {
    var out = "", i = 0;
    while (i < text.length) {
      var a = text.charCodeAt(i++), b = text.charCodeAt(i++), c = text.charCodeAt(i++);
      out += B64.charAt(a >> 2) + B64.charAt(((a & 3) << 4) | (b >> 4));
      out += isNaN(b) ? "=" : B64.charAt(((b & 15) << 2) | (c >> 6));
      out += isNaN(c) ? "=" : B64.charAt(c & 63);
    }
    return out;
  }
  g.atob = g.atob || function (s) { var b = b64decodeBytes(s), r = ""; for (var i = 0; i < b.length; i++) r += String.fromCharCode(b[i]); return r; };
  g.btoa = g.btoa || b64encodeString;

  g.console = { log: function () {}, warn: function () {}, error: function () {}, info: function () {}, debug: function () {} };
  var timers = 0;
  g.setTimeout = function (fn, ms) { var id = ++timers; native.sleep(ms || 0, function () { if (timers >= 0) fn(); }); return id; };
  g.clearTimeout = function () {};
  g.crypto = g.crypto || { randomUUID: function () {
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
      var r = Math.random() * 16 | 0; return (c === "x" ? r : (r & 3 | 8)).toString(16);
    });
  } };

  function utf8(buffer) {
    var bytes = new Uint8Array(buffer), out = "", i = 0;
    while (i < bytes.length) {
      var c = bytes[i++];
      if (c < 128) out += String.fromCharCode(c);
      else if (c < 224) out += String.fromCharCode(((c & 31) << 6) | (bytes[i++] & 63));
      else if (c < 240) out += String.fromCharCode(((c & 15) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63));
      else {
        var cp = ((c & 7) << 18) | ((bytes[i++] & 63) << 12) | ((bytes[i++] & 63) << 6) | (bytes[i++] & 63);
        cp -= 0x10000; out += String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 1023));
      }
    }
    return out;
  }

  var entities = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
  function decodeEntities(text) {
    return String(text).replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, function (m, e) {
      if (e.charAt(0) === "#") {
        var n = e.charAt(1).toLowerCase() === "x" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10);
        return isNaN(n) ? m : String.fromCodePoint(n);
      }
      return entities[e] !== undefined ? entities[e] : m;
    });
  }

  function toHeaders(object) {
    var out = {};
    Object.keys(object || {}).forEach(function (k) { if (object[k] !== undefined && object[k] !== null) out[k] = String(object[k]); });
    return out;
  }

  async function intercept(request) {
    var ids = Object.keys(interceptors);
    for (var i = 0; i < ids.length; i++) request = await interceptors[ids[i]].request(request);
    return request;
  }

  var Application = {
    isResourceLimited: false,
    Selector: function (object, name) {
      var fn = function () { return object[name].apply(object, arguments); };
      fn.__selector = name; return fn;
    },
    SelectorRegistry: { selector: function (fn) { return fn; } },
    registerInterceptor: function (id, request, response) { interceptors[id] = { request: request, response: response }; },
    unregisterInterceptor: function (id) { delete interceptors[id]; },
    getState: function (key) { var v = native.getState(String(key)); return v == null ? undefined : JSON.parse(v); },
    setState: function (value, key) { native.setState(String(key), value === undefined ? null : JSON.stringify(value)); },
    getSecureState: function (key) { return secure[key]; },
    setSecureState: function (value, key) { secure[key] = value; }, // memory only, not persisted
    sleep: function (ms) { return new Promise(function (ok) { native.sleep(ms, ok); }); },
    decodeHTMLEntities: decodeEntities,
    arrayBufferToUTF8String: utf8,
    base64Decode: function (s) { return g.atob(s); },
    base64Encode: function (s) { return g.btoa(s); },
    getDefaultUserAgent: async function () {
      return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1";
    },
    formDidChange: function () {},
    invalidateDiscoverSections: function () {},
    scheduleRequest: async function (request) {
      var req = await intercept(Object.assign({ method: "GET", headers: {} }, request));
      var headers = toHeaders(req.headers);
      if (req.cookies && Object.keys(req.cookies).length) {
        headers.Cookie = Object.keys(req.cookies).map(function (k) { return k + "=" + req.cookies[k]; }).join("; ");
      }
      var body = req.body;
      if (body !== undefined && body !== null && typeof body !== "string") body = JSON.stringify(body);
      var raw = await new Promise(function (ok, fail) {
        native.request(JSON.stringify({ url: String(req.url), method: String(req.method || "GET"), headers: headers, body: body }), ok, fail);
      });
      var parsed = JSON.parse(raw);
      var bytes = b64decodeBytes(parsed.body);
      var data = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      var response = { url: parsed.url, status: parsed.status, headers: parsed.headers, mimeType: parsed.headers["Content-Type"] || parsed.headers["content-type"], cookies: [] };
      var ids = Object.keys(interceptors);
      for (var i = 0; i < ids.length; i++) data = await interceptors[ids[i]].response(req, response, data);
      return [response, data];
    }
  };
  g.Application = Application;

  var initialised = false;
  // method: search | details | chapters | pages. Returns a JSON string.
  g.__run = async function (id, method, args) {
    var instance = g.source && g.source[id];
    if (!instance) throw new Error("Extension " + id + " not found.");
    if (!initialised) { initialised = true; if (instance.initialise) await instance.initialise(); }
    var result;
    if (method === "discover") {
      if (!instance.getDiscoverSections || !instance.getDiscoverSectionItems) return JSON.stringify([]);
      var sections = await instance.getDiscoverSections();
      var groups = [];
      for (var section of (sections || []).slice(0, 12)) {
        try {
          var page = await instance.getDiscoverSectionItems(section, undefined);
          var items = (page && page.items || []).filter(function (item) {
            return item && item.mangaId && item.title;
          }).slice(0, 30).map(function (item) {
            return { mangaId: item.mangaId, title: item.title, imageUrl: item.imageUrl, subtitle: item.subtitle };
          });
          if (items.length) groups.push({ id: String(section.id), title: String(section.title || ""), items: items });
        } catch (error) { /* Other sections remain available. */ }
      }
      result = groups;
    } else if (method === "search") {
      result = await instance.getSearchResults({ title: args.query, filters: [] }, args.metadata || undefined);
    } else if (method === "details") {
      result = await instance.getMangaDetails(args.mangaId);
    } else if (method === "chapters") {
      var chapters = await instance.getChapters({ mangaId: args.mangaId, mangaInfo: { primaryTitle: args.title || "", secondaryTitles: [] } }, undefined);
      // Extensions attach the whole series to every chapter; drop it so long series stay small.
      result = chapters.map(function (c) { return { chapterId: c.chapterId, title: c.title, chapNum: c.chapNum }; });
    } else if (method === "pages") {
      var details = await instance.getChapterDetails({ chapterId: args.chapterId, sourceManga: { mangaId: args.mangaId, mangaInfo: { primaryTitle: "", secondaryTitles: [] } }, langCode: "en", chapNum: 0, volume: 0 });
      var pages = [];
      for (var i = 0; i < details.pages.length; i++) {
        var url = details.pages[i];
        var request = await intercept({ url: url, method: "GET", headers: {} });
        pages.push({ url: request.url, headers: toHeaders(request.headers) });
      }
      result = pages;
    } else throw new Error("Unknown method " + method);
    return JSON.stringify(result === undefined ? null : result);
  };
})(this);
"""#
}
#endif
