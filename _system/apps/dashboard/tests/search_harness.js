// Runs static/search-rank.js under node for the Python search tests.
//
//   node tests/search_harness.js "<query>" < index.json
//
// stdin holds the search index: the {records, synonyms} object /search.json
// serves, or a bare list of records. Prints the ranked hits as JSON:
// [{id, score, note}], best first.
var fs = require("fs");
var path = require("path");

var window = {};
var src = fs.readFileSync(path.join(__dirname, "..", "static", "search-rank.js"), "utf8");
new Function("window", src)(window);

var data = JSON.parse(fs.readFileSync(0, "utf8"));
var records = Array.isArray(data) ? data : data.records;
var synonyms = Array.isArray(data) ? [] : (data.synonyms || []);
var q = process.argv[2] || "";

var hits = window.S42Search.rank(records, q, synonyms);
console.log(JSON.stringify(hits.map(function (h) {
  return {id: h.rec.id, score: h.score, note: h.note === undefined ? null : h.note};
})));
