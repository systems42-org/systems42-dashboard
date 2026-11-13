// The goal coverage matrix on /goals follows the page's "Agreed only" filter
// (FR-036, FR-022). The filter lives in static/list-view.js and in ?status=.
// With it on, only accepted goals (rows) and accepted epics and use cases
// (columns) show, and a goal whose marks are all hidden becomes a gap.
//
// Markup (templates/goals.html): <section class="goal-matrix">, rows
// <tr data-goal data-status data-gap-note data-gap-note-accepted>, header and body cells <th|td data-status>, a mark
// is <span class="gm-dot">.
(function () {
  function keep(status, filter) {
    return filter !== "accepted" || status === "accepted";
  }

  // rows: [{status, marks: [bool per column], note, noteAccepted}], cols: [{status}].
  // Returns which rows and columns show, which shown rows are gaps and the
  // note each gap gets, which shown columns are the last three (their
  // tooltips open to the left), and whether no row shows at all.
  function view(rows, cols, filter) {
    var shownCols = cols.map(function (c) { return keep(c.status, filter); });
    var shownRows = rows.map(function (r) { return keep(r.status, filter); });
    var gaps = rows.map(function (r, i) {
      return shownRows[i] && !r.marks.some(function (m, j) { return m && shownCols[j]; });
    });
    var notes = rows.map(function (r) { return filter === "accepted" ? r.noteAccepted : r.note; });
    var left = 3;
    var edges = shownCols.slice().reverse().map(function (on) {
      return on && left-- > 0;
    }).reverse();
    return {rows: shownRows, cols: shownCols, gaps: gaps, notes: notes, edges: edges,
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
    return {status: tr.dataset.status, note: tr.dataset.gapNote,
            noteAccepted: tr.dataset.gapNoteAccepted,
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
      var note = tr.cells[0].querySelector(".gm-gap-note");
      if (v.gaps[i] && !note) {
        note = document.createElement("span");
        note.className = "gm-gap-note";
        tr.cells[0].appendChild(note);
      }
      if (note) {
        note.hidden = !v.gaps[i];
        if (v.notes[i]) note.textContent = v.notes[i];
      }
    });
  }

  var list = document.querySelector('table[data-list="goal"]');
  if (list) list.addEventListener("listfilter", function (e) {
    apply(e.detail && e.detail.status);
  });
  // list-view.js ran first and already applied the address: catch up with it
  apply(new URLSearchParams(location.search).get("status") === "accepted" ? "accepted" : "all");
})();
