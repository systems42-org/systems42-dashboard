// The goal coverage matrix on /goals follows the page's "Agreed only" filter
// (FR-036, FR-022). The filter lives in static/list-view.js and in ?status=.
// With it on, only accepted goals (rows) and accepted epics and use cases
// (columns) show. The server works out each row for both views: whether it is
// a gap (no requirement at all serves the goal) and its row-head notes, one
// <span data-view="all|accepted"> each. The script shows the view's notes.
//
// Markup (templates/goals.html): <section class="goal-matrix">, rows
// <tr data-goal data-status data-gap data-gap-accepted>, header and body cells <th|td data-status>, a mark
// is <span class="gm-dot">.
(function () {
  function keep(status, filter) {
    return filter !== "accepted" || status === "accepted";
  }

  // rows: [{status, marks: [bool per column], gap, gapAccepted}], cols: [{status}].
  // Returns which rows and columns show, which shown rows are gaps, which
  // shown columns are the last three (their tooltips open to the left), and
  // whether no row shows at all.
  function view(rows, cols, filter) {
    var shownCols = cols.map(function (c) { return keep(c.status, filter); });
    var shownRows = rows.map(function (r) { return keep(r.status, filter); });
    var gaps = rows.map(function (r, i) {
      return shownRows[i] && !!(filter === "accepted" ? r.gapAccepted : r.gap);
    });
    var left = 3;
    var edges = shownCols.slice().reverse().map(function (on) {
      return on && left-- > 0;
    }).reverse();
    return {rows: shownRows, cols: shownCols, gaps: gaps, edges: edges,
            none: !shownRows.some(Boolean)};
  }

  window.S42GoalMatrix = {view: view};
  if (typeof document === "undefined") return;     // under node, for the tests

  var section = document.querySelector(".goal-matrix");
  var table = section && section.querySelector("table");
  if (!table || !table.tHead) return;
  var heads = Array.from(table.tHead.rows[0].cells).slice(1);
  var trs = Array.from(table.tBodies[0].rows);
  var cols = heads.map(function (th) { return {status: th.dataset.status}; });
  var rows = trs.map(function (tr) {
    return {status: tr.dataset.status, gap: tr.dataset.gap !== undefined,
            gapAccepted: tr.dataset.gapAccepted !== undefined,
            marks: Array.from(tr.cells).slice(1).map(function (td) { return !!td.querySelector(".gm-dot"); })};
  });

  function apply(filter) {
    var v = view(rows, cols, filter);
    heads.forEach(function (th, j) {
      th.classList.toggle("list-out", !v.cols[j]);
      th.classList.toggle("gm-edge", v.edges[j]);
    });
    var none = section.querySelector("[data-gm-none]");
    if (none) none.hidden = !v.none;
    trs.forEach(function (tr, i) {
      tr.classList.toggle("list-out", !v.rows[i]);
      Array.from(tr.cells).slice(1).forEach(function (td, j) { td.classList.toggle("list-out", !v.cols[j]); });
      tr.classList.toggle("gm-gap", v.gaps[i]);
      var view = filter === "accepted" ? "accepted" : "all";
      tr.cells[0].querySelectorAll("[data-view]").forEach(function (note) {
        note.hidden = note.dataset.view !== view;
      });
    });
  }

  var list = document.querySelector('table[data-list="goal"]');
  if (list) list.addEventListener("listfilter", function (e) {
    apply(e.detail && e.detail.status);
  });
  // list-view.js ran first and already applied the address: catch up with it
  apply(new URLSearchParams(location.search).get("status") === "accepted" ? "accepted" : "all");
})();
