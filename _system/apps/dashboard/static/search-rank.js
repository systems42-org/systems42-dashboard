// Shared search ranking for the /search page and the nav search popup, so both
// rank a query identically. Records have the shape of build_search_records()
// in app.py: {id, type, title, aliases, plain, fields, links, ...}.
//
// Relevance is a 0–100 percentage, decided by *where* and *how* each query
// word matched. Places, strongest first: id, title, type, body. Within a
// place an exact or prefix hit beats a word form, and a word form beats a
// typo (FR-002), so a typo never pushes a correct match down. The number means
// the same thing for every query (no per-query normalisation).
(function () {
  var WORD_RE = /\p{L}+-\d+|[\p{L}\p{N}]+/gu;
  var ID_RE = /^\p{L}+-\d+$/u;
  var SUFFIXES = ["ing", "ed", "es", "s"];

  // base score per place, and what each kind of match costs within a place
  var PLACE = {id: 90, title: 80, type: 50, body: 40};
  var COST = {exact: 0, prefix: 2, form: 4, typo: 8};

  function norm(s) { return String(s || "").normalize("NFC"); }
  function words(s) { return norm(s).match(WORD_RE) || []; }
  function len(w) { return Array.from(w).length; }

  // Common English endings count as the same word (FR-002).
  function stem(w) {
    for (var i = 0; i < SUFFIXES.length; i++) {
      var s = SUFFIXES[i];
      if (w.length > s.length && w.slice(-s.length) === s && len(w) - s.length >= 3) {
        return w.slice(0, -s.length);
      }
    }
    return w;
  }

  // Damerau-Levenshtein distance (optimal string alignment), or max + 1 once
  // it is clear the distance exceeds max.
  function distance(a, b, max) {
    a = Array.from(a); b = Array.from(b);
    if (Math.abs(a.length - b.length) > max) { return max + 1; }
    var prev2 = null, prev = [], i, j;
    for (j = 0; j <= b.length; j++) { prev.push(j); }
    for (i = 1; i <= a.length; i++) {
      var cur = [i], low = i;
      for (j = 1; j <= b.length; j++) {
        var c = a[i - 1] === b[j - 1] ? 0 : 1;
        var d = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + c);
        if (prev2 && i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
          d = Math.min(d, prev2[j - 2] + 1);
        }
        cur.push(d);
        if (d < low) { low = d; }
      }
      if (low > max) { return max + 1; }
      prev2 = prev; prev = cur;
    }
    return prev[b.length];
  }

  // How the query word `q` matches the text word `w` (both lower-case):
  // {kind: "exact"|"prefix"|"form"|"typo", from, to} or null. Words of 3
  // letters or fewer and IDs match only exactly or as a prefix. 4 to 7
  // letters allow one wrong, missing, extra or swapped letter, 8 or more two.
  function matchWord(q, w) {
    if (q === w) { return {kind: "exact", from: q, to: w}; }
    var n = len(q);
    var strict = n <= 3 || ID_RE.test(q);
    if (!strict && stem(q) === stem(w)) { return {kind: "form", from: q, to: w}; }
    if (w.lastIndexOf(q, 0) === 0) { return {kind: "prefix", from: q, to: w}; }
    if (strict || ID_RE.test(w)) { return null; }
    var max = n >= 8 ? 2 : 1;
    if (distance(q, w, max) <= max || distance(stem(q), stem(w), max) <= max) {
      return {kind: "typo", from: q, to: w};
    }
    return null;
  }

  // Per-record word lists, built once per record: lower-case word -> the
  // word as written, plus how often it occurs in the body.
  var prepared = typeof WeakMap === "function" ? new WeakMap() : null;

  function wordMap(s, counts) {
    var m = new Map();
    words(s).forEach(function (w) {
      var lc = w.toLowerCase();
      if (!m.has(lc)) { m.set(lc, w); }
      if (counts) { counts.set(lc, (counts.get(lc) || 0) + 1); }
    });
    return m;
  }

  function prep(rec) {
    var p = prepared && prepared.get(rec);
    if (p) { return p; }
    var freq = new Map();
    p = {
      id: wordMap(rec.id),
      title: wordMap(rec.title),
      titleLc: words(rec.title).join(" ").toLowerCase(),
      type: wordMap(rec.type),
      body: wordMap(rec.plain, freq),
      freq: freq,
    };
    if (prepared) { prepared.set(rec, p); }
    return p;
  }

  // Best match of query word `q` among the words of one place.
  function bestIn(map, q, memo) {
    var best = null;
    map.forEach(function (orig, lc) {
      var key = q + "\u0000" + lc;
      if (!memo.has(key)) { memo.set(key, matchWord(q, lc)); }
      var m = memo.get(key);
      if (m && (!best || COST[m.kind] < COST[best.kind])) {
        best = {kind: m.kind, from: q, to: orig, lc: lc};
      }
    });
    return best;
  }

  // Best place and match for one query word in one record.
  function matchUnit(p, q, memo) {
    var best = null;
    ["id", "title", "type", "body"].forEach(function (place) {
      var m = bestIn(p[place], q, memo);
      if (!m) { return; }
      var score = PLACE[place] - COST[m.kind];
      if (!best || score > best.score) { best = {place: place, score: score, match: m}; }
    });
    return best;
  }

  function relevance(p, qwords, matches) {
    var exactTitle = matches.every(function (m) {
      return m.place === "title" && (m.match.kind === "exact" || m.match.kind === "prefix");
    });
    var phrase = qwords.join(" ");
    if (exactTitle && p.titleLc === phrase) { return 100; }                  // exact title
    if (exactTitle && p.titleLc.lastIndexOf(phrase, 0) === 0) { return 92; } // title prefix
    if (exactTitle && p.titleLc.indexOf(phrase) !== -1) { return 85; }       // phrase in title
    var sum = matches.reduce(function (a, m) { return a + m.score; }, 0);
    return Math.round(sum / matches.length);
  }

  function band(pct) { return pct >= 80 ? "high" : pct >= 55 ? "mid" : "low"; }

  // Rank `records` against query `q`; returns [{rec, score}] best first:
  // relevance, then how often the words occur in the body, then title.
  function rank(records, q) {
    var qwords = words(q).map(function (w) { return w.toLowerCase(); });
    if (!qwords.length) { return []; }
    var memo = new Map();
    var out = [];
    records.forEach(function (rec) {
      var p = prep(rec);
      var matches = [];
      for (var i = 0; i < qwords.length; i++) {
        var m = matchUnit(p, qwords[i], memo);
        if (!m) { return; }                          // every word must match
        matches.push(m);
      }
      var freq = matches.reduce(function (a, m) {
        return a + (m.place === "body" ? p.freq.get(m.match.lc) || 0 : 0);
      }, 0);
      out.push({rec: rec, score: relevance(p, qwords, matches), freq: freq, matches: matches});
    });
    out.sort(function (a, b) {
      return b.score - a.score || b.freq - a.freq
        || a.rec.title.localeCompare(b.rec.title, "en");
    });
    return out;
  }

  window.S42Search = {rank: rank, band: band, matchWord: matchWord, stem: stem};
})();
