// Sortable table headers, declared in the templates:
//
//   <th data-sort="text|numeric">          the column sorts
//   <th data-sort-first="desc">            first click sorts descending (ratings,
//                                          counts, dates: the top is the interesting end)
//   <th aria-sort="ascending">             the order the server rendered
//   <td data-sort-value="…">               the sort key, else the cell's text
//
// The label moves into a <button>, so a header works from the keyboard and a page
// without this script still shows plain, correct headers. Sorting moves rows
// within the tbody: row listeners, filters and hidden rows stay as they are.
// A header click fires `tablesort` on the table for pages with other sort controls.
(function () {
  // numeric: STK-2 before STK-10. sensitivity "base": Ärztin next to Arzt, and
  // case does not split the list.
  var collator = new Intl.Collator(undefined, {numeric: true, sensitivity: "base"});

  function compare(a, b, numeric, asc) {
    // an empty cell is missing data, not a small value: last in either direction
    if (a === "" || b === "") return a === b ? 0 : (a === "" ? 1 : -1);
    var d = numeric ? Number(a) - Number(b) : collator.compare(a, b);
    return asc ? d : -d;
  }

  function clear(table) {
    table.querySelectorAll("th[aria-sort]").forEach(function (th) {
      th.removeAttribute("aria-sort");
    });
  }

  window.S42TableSort = {compare: compare, clear: clear};
  if (typeof document === "undefined") return;   // under node, for the comparator test

  function cellKey(row, idx) {
    var td = row.cells[idx];
    if (!td) return "";
    return (td.dataset.sortValue !== undefined ? td.dataset.sortValue : td.textContent).trim();
  }

  function sortBy(th) {
    var table = th.closest("table");
    var tbody = table.tBodies[0];
    var state = th.getAttribute("aria-sort");
    var asc = state === "ascending" ? false
      : state === "descending" ? true
      : th.dataset.sortFirst !== "desc";
    var idx = th.cellIndex;
    var numeric = th.dataset.sort === "numeric";
    Array.from(tbody.rows)
      .map(function (row) { return {row: row, key: cellKey(row, idx)}; })
      .sort(function (a, b) { return compare(a.key, b.key, numeric, asc); })
      .forEach(function (entry) { tbody.appendChild(entry.row); });
    clear(table);
    th.setAttribute("aria-sort", asc ? "ascending" : "descending");
    table.dispatchEvent(new CustomEvent("tablesort"));
  }

  document.querySelectorAll("th[data-sort]").forEach(function (th) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "th-sort";
    while (th.firstChild) button.appendChild(th.firstChild);
    th.appendChild(button);
    button.addEventListener("click", function () { sortBy(th); });
  });
})();
