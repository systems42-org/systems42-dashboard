// The issue filters of the static demo (FR-058).
//
// The dashboard filters issues on the server (app.py, issues_view). The demo
// has no server: its one issue page lists every issue, and this script shows
// the ones the address asks for. site/build.py adds it to the exported page.
//
// It reads ?status= (or the former ?filter=), ?category=, ?severity=,
// ?section= and ?owner= as the server does: a value the page's filters do not
// offer is ignored, and a section without a status shows its open issues. Each
// row carries its values as data attributes (templates/issues.html). The
// page's own script reloads the page with the new address when a filter
// changes, and static/list-view.js sorts from ?sort=.
(function () {
  var NAMES = ["status", "category", "severity", "section", "owner"];

  function text(v) {
    return v === undefined || v === null ? "" : String(v).trim();
  }

  // params: URLSearchParams. options: {name: [value]}, what each filter offers.
  function choose(params, options) {
    function known(name, value) {
      return (options[name] || []).indexOf(value) >= 0 ? value : "";
    }
    var section = known("section", text(params.get("section")).toUpperCase());
    var status = known("status", text(params.get("status")) || text(params.get("filter")));
    return {
      status: status || (section ? "open" : "all"),
      category: known("category", text(params.get("category"))),
      severity: known("severity", text(params.get("severity"))),
      section: section,
      owner: known("owner", text(params.get("owner"))),
    };
  }

  // row: {status, open: "yes" | "no", category, severity, sections: [id], owner}
  function keep(row, chosen) {
    var st = chosen.status;
    var open = row.open === "yes";
    if (st === "open" && !open || st === "closed" && open) return false;
    if (st !== "all" && st !== "open" && st !== "closed" && row.status !== st) return false;
    if (chosen.category && row.category !== chosen.category) return false;
    if (chosen.severity && row.severity !== chosen.severity) return false;
    if (chosen.section && row.sections.indexOf(chosen.section) < 0) return false;
    if (chosen.owner && row.owner !== (chosen.owner === "none" ? "" : chosen.owner)) return false;
    return true;
  }

  function isFiltered(chosen) {
    return chosen.status !== "all" || !!(chosen.category || chosen.severity || chosen.section || chosen.owner);
  }

  window.S42DemoIssues = {choose: choose, keep: keep, isFiltered: isFiltered};
  if (typeof document === "undefined") return;     // under node, for the tests

  var form = document.querySelector(".issue-filters");
  var table = document.getElementById("issues-table");
  if (!form || !table) return;

  var options = {};
  NAMES.forEach(function (name) {
    options[name] = Array.from(form.elements[name].options).map(function (o) { return o.value; });
  });
  var chosen = choose(new URLSearchParams(location.search), options);
  NAMES.forEach(function (name) { form.elements[name].value = chosen[name]; });

  var shown = 0;
  table.querySelectorAll("tr.issue-row").forEach(function (tr) {
    var d = tr.dataset;
    var on = keep({status: d.status, open: d.open, category: d.category, severity: d.severity,
                   sections: text(d.sections).split(/\s+/), owner: d.owner}, chosen);
    tr.hidden = !on;
    if (on) shown++;
  });
  if (!isFiltered(chosen)) return;

  // the lines the server writes for a filtered list
  var counts = document.querySelector(".issue-counts");
  if (counts) {
    counts.lastChild.textContent = counts.lastChild.textContent.replace(/\.\s*$/, "")
      + ". These filters show " + shown + ".";
    var note = document.createElement("p");
    note.className = "filter-note";
    if (chosen.section) {
      var title = document.createElement("strong");
      title.textContent = form.elements.section.selectedOptions[0].textContent;
      note.append("Showing the issues that point at pages of ", title, ". ");
    }
    var all = document.createElement("a");
    all.href = location.pathname;
    all.textContent = "Show all issues →";
    note.append(all);
    counts.after(note);
  }
  if (!shown) {
    var hint = document.createElement("p");
    hint.className = "empty-hint";
    hint.textContent = "No issues match these filters.";
    table.after(hint);
  }
})();
