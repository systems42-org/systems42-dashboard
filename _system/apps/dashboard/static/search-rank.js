// Shared search ranking for the /search page and the nav search popup, so both
// rank a query identically. Records have the shape of build_search_records()
// in app.py: {id, type, title, text} (text lower-cased; title and id are
// lower-cased here).
//
// Relevance as a 0–100 percentage, decided by *where* the query matched: the
// strongest tier wins, so a title hit can never be out-scored by a body hit
// and the number means the same thing for every query (not a per-query
// normalisation). Body-only matches scale with term frequency. Every query
// word must appear (AND). No lunr — weighted substring matching is plenty for
// a few hundred pages, keeps scores stable, and needs no German stemmer.
(function () {
  function countOcc(hay, needle) {
    var n = 0, i = 0;
    while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
    return n;
  }

  function tokenize(q) {
    return q.trim().toLowerCase().split(/\s+/).filter(Boolean);
  }

  function relevance(rec, tokens, q) {
    var title = rec.title.toLowerCase(), id = rec.id.toLowerCase();
    var type = rec.type.toLowerCase(), text = rec.text;
    if (!tokens.every(function (t) { return (text + " " + type).includes(t); })) return 0;
    if (title === q) return 100;                                            // exact title
    if (title.startsWith(q)) return 92;                                     // title prefix
    if (title.includes(q)) return 85;                                       // phrase in title
    if (tokens.every(function (t) { return title.includes(t); })) return 78; // all words in title
    if (tokens.some(function (t) { return title.includes(t); })) return 68;  // some word in title
    if (id.includes(q) || tokens.every(function (t) { return id.includes(t); })) return 62; // id match
    if (type.includes(q)) return 55;                                        // category match
    var freq = tokens.reduce(function (a, t) { return a + countOcc(text, t); }, 0);  // content only
    return 32 + Math.min(freq, 11) * 2;                                     // 34–54
  }

  function band(pct) { return pct >= 80 ? "high" : pct >= 55 ? "mid" : "low"; }

  // Rank `records` against query `q`; returns [{rec, score}] best first:
  // relevance, then body frequency, then title alphabetically.
  function rank(records, q) {
    q = q.trim().toLowerCase();
    var tokens = tokenize(q);
    if (!tokens.length) return [];
    var out = [];
    records.forEach(function (rec) {
      var score = relevance(rec, tokens, q);
      if (score > 0) {
        var freq = tokens.reduce(function (a, t) { return a + countOcc(rec.text, t); }, 0);
        out.push({rec: rec, score: score, freq: freq});
      }
    });
    out.sort(function (a, b) {
      return b.score - a.score || b.freq - a.freq
        || a.rec.title.localeCompare(b.rec.title, "en");
    });
    return out;
  }

  window.S42Search = {rank: rank, band: band};
})();
