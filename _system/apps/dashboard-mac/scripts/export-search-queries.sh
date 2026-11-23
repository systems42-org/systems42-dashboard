#!/usr/bin/env bash
# Writes Tests/Golden/<fixture>/queries.json: what static/search-rank.js (the
# ranker of the Go and Python dashboards) answers for a list of queries on the
# search.json of each fixture. The Swift ranker must give the same hits, scores,
# notes, passages and related pages. Needs Node. Tests never start it.
#
# Usage: export-search-queries.sh [golden-folder]. The folder holds one folder per
# fixture with its search.json, and gets the queries.json next to it. It defaults
# to Tests/Golden. export-golden.sh runs this on its temp folder before it
# replaces Tests/Golden, so one move replaces everything or nothing.
# Two runs give the same bytes: the queries are fixed or derived from the
# fixture's own titles, ids and aliases, and the output is written in one order.
#
# The Swift ranker looks at the first 200 characters of a query and its first 16
# words. The JavaScript has no such limit, so a query is first cut the same way,
# and queries.json holds the JavaScript's answer for the cut query.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(git -C "$here" rev-parse --show-toplevel)"
golden="${1:-$here/Tests/Golden}"
command -v node >/dev/null || { echo "export-search-queries.sh needs Node" >&2; exit 1; }

node - "$repo/_system/apps/dashboard/static/search-rank.js" "$golden" <<'JS'
const fs = require("fs");
const path = require("path");
const [rankerPath, goldenDir] = process.argv.slice(2);

// Load the ranker the way tests/search_harness.js does.
const window = {};
new Function("window", fs.readFileSync(rankerPath, "utf8"))(window);
const S = window.S42Search;

// Queries of the Python tests and more: typos, word forms, filler words, IDs, aliases, glossary
// terms, non-ASCII, one letter, only punctuation, only filler words.
const fixed = [
  "keyholder", "keyholdr", "keyhodler", "keyholderr", "keyholders", "stakholdrs", "requirement engineer",
  "requirement engineers", "STK-02", "stk-023", "STK-024", "023", "02", "test", "tset", "tst", "seach", "searches",
  "ärztn", "ärztin", "aerztin", "Jedi Master", "jedi", "master", "moderator", "facilitator", "facilitators",
  "definition of done", "definition done", "dod", "DoD", "who starts the app", "what is the keyholder",
  "what does the keyholder do", "search the wiki", "wiki search", "search wiki tips", "keyholder workshop",
  "workshop keyholder", "workshops started", "the a", "the", "a", "of", "in the", "Must", "should could", "navigation",
  "tags navigation", "accepted", "draft", "open", "status draft", "status:draft", "tag:navigation", "every",
  "person", "start", "session", "ask", "SRC-006", "export board", "run checks", "main menu", "bread crumbs",
  "reach", "text tools", "!!!", "---", "a-1", "x y z", "keyholder keyholder", "decision", "stakeholder",
  "building block", "quality", "goal", "vision", "Stakeholder", "domain term",
  "😀 workshop", "keyholder 😀", "cafe\u0301", "caf\u00e9", "straße", "strasse", "ß", "STRASSE", "İstanbul", "ΟΔΟΣ",
  "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen keyholder workshop",
  "keyholder keyholder keyholder keyholder keyholder keyholder keyholder keyholder keyholder keyholder keyholder " +
    "keyholder keyholder keyholder keyholder keyholder workshop test",
];

// The Swift ranker's limits: 200 characters, 16 words.
function cut(q) {
  const words = Array.from(q).slice(0, 200).join("").normalize("NFC").match(/\p{L}+-\d+|[\p{L}\p{N}]+/gu) || [];
  return words.length > 16 ? words.slice(0, 16).join(" ") : Array.from(q).slice(0, 200).join("");
}

function derived(records) {
  const out = [];
  records.forEach(function (r) {
    out.push(r.title, r.id, r.id.replace(/^[^-]*-/, ""));
    const first = (r.title.match(/[\p{L}\p{N}]+/u) || [""])[0];
    out.push(first);
    if (first.length >= 5) { out.push(first.slice(0, 2) + first.slice(3)); }   // one letter missing
    if (first.length >= 6) { out.push(first.slice(0, 1) + first.slice(2, 3) + first.slice(1, 2) + first.slice(3)); }   // two swapped
    (r.aliases || []).forEach(function (a) { out.push(a); });
  });
  return out;
}

function unescapeHtml(s) {
  return s.replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&amp;/g, "&");
}

// The passage as text and the UTF-16 ranges to mark, the form the Swift port returns.
function plainPassage(html) {
  const m = /^<p class="hit-passage">([\s\S]*)<\/p>$/.exec(html);
  if (!m || m[1] === "") { return null; }
  const re = /<mark>([\s\S]*?)<\/mark>/g;
  let text = "", last = 0, found;
  const marks = [];
  while ((found = re.exec(m[1])) !== null) {
    text += unescapeHtml(m[1].slice(last, found.index));
    const from = text.length;
    text += unescapeHtml(found[1]);
    marks.push([from, text.length]);
    last = re.lastIndex;
  }
  text += unescapeHtml(m[1].slice(last));
  return {text: text, marks: marks};
}

const filters = [
  ["the", {status: "accepted"}], ["the", {priority: "must"}], ["every", {tag: "navigation"}],
  ["every", {tag: "navigation", status: "accepted"}], ["keyholder", {status: "accepted"}], ["test", {priority: "should"}],
  ["facilitator", {status: "draft"}], ["the", {}],
];

fs.readdirSync(goldenDir).sort().forEach(function (fixture) {
  const file = path.join(goldenDir, fixture, "search.json");
  if (!fs.existsSync(file)) { return; }
  const index = JSON.parse(fs.readFileSync(file, "utf8"));
  const withPassages = fixture === "search" || fixture === "basic";
  const withFilters = fixture === "search";
  const seen = new Set();
  const queries = fixed.concat(derived(index.records)).filter(function (q) {
    if (seen.has(q)) { return false; }
    seen.add(q);
    return true;
  });
  const lines = queries.map(function (q) {
    const hits = S.rank(index.records, cut(q), index.synonyms);
    const entry = {
      q: q,
      hits: hits.map(function (h) {
        const row = {id: h.rec.id, score: h.score, note: h.note === undefined ? null : h.note};
        if (withPassages) { row.passage = plainPassage(S.passage(h)); }
        return row;
      }),
      related: S.related(hits, index.records).map(function (r) { return {id: r.rec.id, note: r.note}; }),
    };
    return " " + JSON.stringify(entry);
  });
  const filtered = withFilters ? filters.map(function (pair) {
    const hits = S.filter(S.rank(index.records, pair[0], index.synonyms), pair[1]);
    return " " + JSON.stringify({q: pair[0], filter: pair[1],
      hits: hits.map(function (h) { return {id: h.rec.id, note: h.note === undefined ? null : h.note}; }),
      related: S.filter(S.related(hits, index.records), pair[1]).map(function (r) { return {id: r.rec.id, note: r.note}; })});
  }) : [];
  const body = '{"queries": [\n' + lines.join(",\n") + "\n]" +
    (withFilters ? ',\n"filtered": [\n' + filtered.join(",\n") + "\n]" : "") + "}\n";
  fs.writeFileSync(path.join(goldenDir, fixture, "queries.json"), body);
});
JS
echo "Search queries written to $golden"
