// Runs the static demo's issue filter (site/demo/issue-filters.js) under node
// for tests/test_demo_issue_filters.py.
//
//   node tests/demo_issue_filters_harness.js < input.json
//
// stdin: {rows, options, queries}. rows are the issue rows of the exported
// page, options the values its filters offer, queries the query strings to
// try. Prints [{chosen, filtered, ids}], one entry per query.
var fs = require("fs");
var path = require("path");

var window = {};
var src = fs.readFileSync(path.join(__dirname, "..", "..", "..", "..", "site", "demo", "issue-filters.js"), "utf8");
new Function("window", src)(window);

var input = JSON.parse(fs.readFileSync(0, "utf8"));
console.log(JSON.stringify(input.queries.map(function (q) {
  var chosen = window.S42DemoIssues.choose(new URLSearchParams(q), input.options);
  return {
    chosen: chosen,
    filtered: window.S42DemoIssues.isFiltered(chosen),
    ids: input.rows.filter(function (r) { return window.S42DemoIssues.keep(r, chosen); })
      .map(function (r) { return r.id; }),
  };
})));
