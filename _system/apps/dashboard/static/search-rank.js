// Shared search ranking for the /search page and the nav search popup, so both
// rank a query identically. Records have the shape of build_search_records()
// in app.py: {id, type, title, aliases, plain, fields, links, ...}.
//
// Relevance is a 0–100 percentage, decided by *where* and *how* each query
// word matched. Places, strongest first: id, title, alias, field (tags,
// priority, status and the like, FR-006), type, body.
// Within a place an exact or prefix hit beats a word form, a word form beats
// a typo (FR-002), and a typo beats a glossary synonym (FR-003), so a weaker
// match never pushes a correct one down. The number means
// the same thing for every query (no per-query normalisation).
//
// Pages that contain every query word come first. Pages that contain only
// some follow, ranked by how many, with a note such as "matches 1 of 2 words"
// and a score of at most 20 (FR-004).
(function () {
  var WORD_RE = /\p{L}+-\d+|[\p{L}\p{N}]+/gu;
  var ID_RE = /^\p{L}+-\d+$/u;
  var SUFFIXES = ["ing", "ed", "es", "s"];
  // Filler words of a question don't count, unless the query has nothing else (FR-004).
  var STOP_WORDS = new Set(("who what when where why how the a an is are does do of to in on " +
    "for and or with").split(" "));

  // base score per place, and what each kind of match costs within a place
  var PLACE = {id: 90, title: 80, alias: 70, field: 60, type: 50, body: 40};
  var PLACES = ["id", "title", "alias", "field", "type", "body"];
  var COST = {exact: 0, prefix: 2, form: 4, typo: 8, synonym: 12};

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
      alias: wordMap((rec.aliases || []).join(" ")),
      aliasLc: (rec.aliases || []).map(function (a) { return words(a).join(" ").toLowerCase(); }),
      field: wordMap(Object.keys(rec.fields || {}).map(function (k) {
        return [].concat(rec.fields[k]).join(" ");
      }).join(" ")),
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

  // The query as units: a single word, or a glossary term's name or alias
  // that the query contains. A unit carries its alternatives: the words as
  // typed first, then the other names of the same term (FR-003).
  function units(qwords, synonyms, titles) {
    var groups = (synonyms || []).map(function (g) {
      return g.map(function (s) { return words(s).map(function (w) { return w.toLowerCase(); }); })
        .filter(function (ws) { return ws.length; });
    });
    var out = [], i = 0;
    while (i < qwords.length) {
      var found = null;
      groups.forEach(function (g) {
        g.forEach(function (ws) {
          if ((!found || ws.length > found.words.length) && ws.every(function (w, k) {
            var q = qwords[i + k];
            return q !== undefined && (q === w || stem(q) === stem(w));
          })) { found = {words: ws, group: g}; }
        });
      });
      if (found) {
        var typed = qwords.slice(i, i + found.words.length);
        var name = found.group[0].join(" ");
        out.push({words: typed, via: titles.get(name) || name,
                  alts: [typed].concat(found.group.filter(function (ws) { return ws !== found.words; }))});
        i += found.words.length;
      } else {
        out.push({words: [qwords[i]], alts: [[qwords[i]]], via: null});
        i += 1;
      }
    }
    return out;
  }

  // Best place and match for one query unit in one record. Every word of an
  // alternative must match within the same place.
  function matchUnit(p, unit, memo) {
    var best = null;
    PLACES.forEach(function (place) {
      unit.alts.forEach(function (alt, ai) {
        var worst = null, lcs = [];
        for (var k = 0; k < alt.length; k++) {
          var m = bestIn(p[place], alt[k], memo);
          if (!m) { return; }
          lcs.push(m.lc);
          if (!worst || COST[m.kind] > COST[worst.kind]) { worst = m; }
        }
        var cost = COST[worst.kind] + (ai > 0 ? COST.synonym : 0);
        var score = PLACE[place] - cost;
        if (!best || score > best.score) {
          best = {place: place, score: score, match: worst, lcs: lcs,
                  via: ai > 0 ? unit.via : null};
        }
      });
    });
    return best;
  }

  function relevance(p, phrase, matches) {
    function all(place) {
      return matches.every(function (m) {
        return m.place === place && !m.via && (m.match.kind === "exact" || m.match.kind === "prefix");
      });
    }
    if (all("title")) {
      if (p.titleLc === phrase) { return 100; }                      // exact title
      if (p.titleLc.lastIndexOf(phrase, 0) === 0) { return 92; }     // title prefix
      if (p.titleLc.indexOf(phrase) !== -1) { return 85; }           // phrase in title
    }
    if (all("alias") && p.aliasLc.indexOf(phrase) !== -1) { return 88; }  // an alias, exactly
    var sum = matches.reduce(function (a, m) { return a + m.score; }, 0);
    return Math.round(sum / matches.length);
  }

  // Why a page with every query word is a hit, when it doesn't contain the
  // words as typed: the first non-exact word decides (FR-005). An exact or
  // prefix hit has no note.
  function reason(rec, matches) {
    for (var i = 0; i < matches.length; i++) {
      var m = matches[i];
      if (m.via) { return "via alias of " + m.via; }
      if (m.place === "alias") { return "via alias of " + rec.title; }
      if (m.match.kind === "typo") { return "typo: " + m.match.from + " → " + m.match.to; }
      if (m.match.kind === "form") { return "word form: " + m.match.from + " → " + m.match.to; }
    }
    return null;
  }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c];
    });
  }

  function sentences(plain) {
    return norm(plain).split("\n").reduce(function (acc, line) {
      return acc.concat(line.split(/(?<=[.!?])\s+/));
    }, []).filter(function (x) { return x.trim(); });
  }

  // The sentence where the query matched, with the matching words in <mark>,
  // for /search (FR-007). A hit with no match in the body shows the page's
  // first sentence. Empty when the page has no text. Escaped before marking.
  var PASSAGE_MAX = 240;
  function passage(hit) {
    var marks = new Set();
    hit.matches.forEach(function (m) {
      if (m.place === "body") { m.lcs.forEach(function (w) { marks.add(w); }); }
    });
    var all = sentences(hit.rec.plain);
    var s = all[0];
    if (marks.size) {
      s = all.filter(function (x) {
        return words(x).some(function (w) { return marks.has(w.toLowerCase()); });
      })[0] || s;
    }
    if (!s) { return ""; }
    var html = "", last = 0, first = -1, m;
    var re = new RegExp(WORD_RE.source, "gu");
    while ((m = re.exec(s)) !== null) {
      if (!marks.has(m[0].toLowerCase())) { continue; }
      if (first < 0) { first = m.index; }
      html += esc(s.slice(last, m.index)) + "<mark>" + esc(m[0]) + "</mark>";
      last = m.index + m[0].length;
    }
    html += esc(s.slice(last));
    if (s.length > PASSAGE_MAX && first > PASSAGE_MAX / 2) {
      // keep the first mark in view: cut the start at a word gap before it
      var cut = s.lastIndexOf(" ", first - 40);
      html = "…" + html.slice(esc(s.slice(0, cut + 1)).length);
    }
    return '<p class="hit-passage">' + html + "</p>";
  }

  // Pages one link step away from the strong hits, for the "Related pages"
  // group on /search (FR-008). Strong means every query word matched in the
  // title or an alias. At most `max` (5), never a page that is a hit already,
  // each with its reason.
  function related(hits, records, max) {
    max = max || 5;
    var byId = new Map(), seen = new Set(), out = [];
    records.forEach(function (r) { byId.set(r.id, r); });
    hits.forEach(function (h) { seen.add(h.rec.id); });
    hits.forEach(function (h) {
      var strong = h.full && h.matches.every(function (m) {
        return m.place === "title" || m.place === "alias";
      });
      if (!strong) { return; }
      (h.rec.links || []).forEach(function (id) {
        var r = byId.get(id);
        if (!r || seen.has(id) || out.length >= max) { return; }
        seen.add(id);
        out.push({rec: r, note: "linked from " + h.rec.id});
      });
    });
    return out;
  }

  function band(pct) { return pct >= 80 ? "high" : pct >= 55 ? "mid" : "low"; }

  // Rank `records` against query `q`, with the glossary's synonym groups;
  // returns [{rec, score, note}] best first: pages with every word, then
  // relevance, then the number of matched words, then how often the words
  // occur in the body, then title.
  function rank(records, q, synonyms) {
    var qwords = words(q).map(function (w) { return w.toLowerCase(); });
    var content = qwords.filter(function (w) { return !STOP_WORDS.has(w); });
    if (content.length) { qwords = content; }
    if (!qwords.length) { return []; }
    var titles = new Map();
    records.forEach(function (r) { titles.set(words(r.title).join(" ").toLowerCase(), r.title); });
    var qunits = units(qwords, synonyms, titles);
    var phrase = qwords.join(" ");
    var memo = new Map();
    var out = [];
    records.forEach(function (rec) {
      var p = prep(rec);
      var matches = [];
      qunits.forEach(function (u) {
        var m = matchUnit(p, u, memo);
        if (m) { matches.push(m); }
      });
      if (!matches.length) { return; }
      var n = qunits.length, full = matches.length === n;
      var freq = matches.reduce(function (a, m) {
        return a + (m.place === "body" ? p.freq.get(m.match.lc) || 0 : 0);
      }, 0);
      var sum = matches.reduce(function (a, m) { return a + m.score; }, 0);
      out.push({
        rec: rec, matches: matches, freq: freq, full: full,
        score: full ? relevance(p, phrase, matches) : Math.min(20, Math.round(sum / n / 4)),
        note: full ? reason(rec, matches) : "matches " + matches.length + " of " + n + " words",
      });
    });
    out.sort(function (a, b) {
      return (b.full - a.full) || b.score - a.score || b.matches.length - a.matches.length
        || b.freq - a.freq || a.rec.title.localeCompare(b.rec.title, "en");
    });
    return out;
  }

  window.S42Search = {rank: rank, band: band, matchWord: matchWord, stem: stem, passage: passage,
                      related: related, esc: esc};
})();
