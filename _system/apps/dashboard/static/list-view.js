// The shared list layer (FR-021, FR-022): sort by one or several columns, the
// metamodel's sort orders, an "agreed only" filter, and all of it in the address.
//
// Markup, declared in the templates:
//
//   <table data-list="<type>" data-sort-orders='[{"label", "keys"}]'>
//   <th data-sort="text|numeric">          the column sorts
//   <th data-key="priority">               its key in the address and in sort orders
//                                          (default: the header text, lower case)
//   <th data-sort-first="desc">            first click sorts descending (ratings,
//                                          counts, dates: the top is the interesting end)
//   <th aria-sort="ascending">             the order the server rendered
//   <td data-sort-value="…">               the sort key, else the cell's text
//   <tr data-status="accepted">            the row's status, for the status filter
//   <div data-list-controls="<type>">      the order picker (select[data-list-order])
//                                          and the status filter (button[data-list-status])
//
// Address: ?sort=<key>:<asc|desc>,<key>:<asc|desc> and ?status=accepted. Read on
// load, written with history.replaceState on every change. Unknown keys and values
// are ignored, so a bad address shows the server's list.
//
// A table with data-sort headers but no data-list sorts by header click alone and
// leaves the address alone. A header click fires `tablesort` on the table.
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

  function text(v) {
    return v === undefined || v === null ? "" : String(v).trim();
  }

  // rows: anything. spec: [{key, dir, numeric}]. valueOf(row, key) gives the sort
  // value, or undefined when the list has no such column (default: row[key]).
  // Keys no row knows are dropped. Ties keep the incoming order.
  function sortRows(rows, spec, valueOf) {
    valueOf = valueOf || function (row, key) { return row[key]; };
    var keys = (spec || []).filter(function (s) {
      return rows.some(function (r) { return valueOf(r, s.key) !== undefined; });
    });
    return rows
      .map(function (row, i) { return {row: row, i: i}; })
      .sort(function (a, b) {
        for (var k = 0; k < keys.length; k++) {
          var s = keys[k];
          var d = compare(text(valueOf(a.row, s.key)), text(valueOf(b.row, s.key)),
                          !!s.numeric, s.dir !== "desc");
          if (d) return d;
        }
        return a.i - b.i;
      })
      .map(function (e) { return e.row; });
  }

  // "priority:asc,release:desc" -> [{key, dir}]. A missing or unknown direction
  // is left out, so the column's own first direction applies.
  function parseSort(value) {
    var out = [];
    text(value).split(",").forEach(function (part) {
      var m = /^([A-Za-z0-9_-]+)(?::(asc|desc))?$/.exec(part.trim());
      if (m && !out.some(function (s) { return s.key === m[1]; })) {
        out.push(m[2] ? {key: m[1], dir: m[2]} : {key: m[1]});
      }
    });
    return out;
  }

  function formatSort(spec) {
    return spec.map(function (s) { return s.key + ":" + (s.dir === "desc" ? "desc" : "asc"); }).join(",");
  }

  function keepRow(status, filter) {
    return filter !== "accepted" || status === "accepted";
  }

  function clear(table) {
    table.querySelectorAll("th[aria-sort]").forEach(function (th) {
      th.removeAttribute("aria-sort");
    });
  }

  var api = {compare: compare, sortRows: sortRows, parseSort: parseSort,
             formatSort: formatSort, keepRow: keepRow, clear: clear};
  window.S42List = api;
  window.S42TableSort = api;                       // the former name, for older pages
  if (typeof document === "undefined") return;     // under node, for the tests

  function columns(table) {
    var cols = {};
    var row = table.tHead && table.tHead.rows[0];
    if (!row) return cols;
    Array.from(row.cells).forEach(function (th) {
      if (th.dataset.sort === undefined) return;
      var key = th.dataset.key || th.textContent.trim().toLowerCase().replace(/\s+/g, "-");
      cols[key] = {th: th, idx: th.cellIndex, numeric: th.dataset.sort === "numeric",
                   first: th.dataset.sortFirst === "desc" ? "desc" : "asc"};
    });
    return cols;
  }

  function cellKey(row, idx) {
    var td = row.cells[idx];
    if (!td) return "";
    return (td.dataset.sortValue !== undefined ? td.dataset.sortValue : td.textContent).trim();
  }

  function setup(table) {
    var tbody = table.tBodies[0];
    if (!tbody) return;
    var cols = columns(table);
    var isList = table.dataset.list !== undefined;
    var serverRows = Array.from(tbody.rows);
    var initialSort = table.querySelector("th[aria-sort]");
    var initialState = initialSort ? [initialSort, initialSort.getAttribute("aria-sort")] : null;
    var state = {spec: [], status: "all"};
    var controls = isList ? document.querySelector('[data-list-controls="' + table.dataset.list + '"]') : null;
    var picker = controls && controls.querySelector("select[data-list-order]");
    var statusButtons = controls ? Array.from(controls.querySelectorAll("button[data-list-status]")) : [];
    var orders = [];
    try { orders = JSON.parse(table.dataset.sortOrders || "[]"); } catch (e) { orders = []; }

    // only keys this table has, each with a direction
    function resolve(spec) {
      return spec.filter(function (s) { return cols[s.key]; }).map(function (s) {
        var c = cols[s.key];
        return {key: s.key, dir: s.dir || c.first, numeric: c.numeric};
      });
    }

    function orderSpec(keys) {
      return resolve(keys.map(function (k) { return {key: k}; }));
    }

    function render() {
      var rows = state.spec.length
        ? sortRows(serverRows, state.spec, function (row, key) {
            return cols[key] ? cellKey(row, cols[key].idx) : undefined;
          })
        : serverRows;
      rows.forEach(function (row) { tbody.appendChild(row); });
      clear(table);
      if (state.spec.length) {
        cols[state.spec[0].key].th.setAttribute("aria-sort",
          state.spec[0].dir === "desc" ? "descending" : "ascending");
      } else if (initialState) {
        initialState[0].setAttribute("aria-sort", initialState[1]);
      }
      if (!isList) return;
      if (statusButtons.length) {
        // a class, not `hidden`: a page's own filter (search, kind) owns
        // `hidden`, and a row shows only when both let it
        var shown = 0;
        serverRows.forEach(function (row) {
          var keep = keepRow(row.dataset.status, state.status);
          row.classList.toggle("list-out", !keep);
          if (keep && !row.hidden) shown++;
        });
        var hint = table.parentNode.querySelector(".list-empty");
        if (hint) hint.hidden = shown !== 0;
        table.dispatchEvent(new CustomEvent("listfilter"));
      }
      if (picker) {
        var current = formatSort(state.spec);
        picker.value = "";
        Array.from(picker.options).forEach(function (o) {
          if (o.value && formatSort(orderSpec(o.value.split(","))) === current) picker.value = o.value;
        });
      }
      statusButtons.forEach(function (b) {
        var on = b.dataset.listStatus === state.status;
        b.classList.toggle("active", on);
        b.setAttribute("aria-pressed", on ? "true" : "false");
      });
      writeAddress();
    }

    function writeAddress() {
      var params = new URLSearchParams(location.search);
      if (state.spec.length) params.set("sort", formatSort(state.spec));
      else params.delete("sort");
      if (statusButtons.length) {
        if (state.status === "accepted") params.set("status", "accepted");
        else params.delete("status");
      }
      var qs = params.toString().replace(/%3A/gi, ":").replace(/%2C/gi, ",");
      var url = location.pathname + (qs ? "?" + qs : "") + location.hash;
      if (url !== location.pathname + location.search + location.hash) {
        history.replaceState(history.state, "", url);
      }
    }

    function headerClick(key, extend) {
      var c = cols[key];
      var at = -1;
      state.spec.forEach(function (s, i) { if (s.key === key) at = i; });
      var flip = function (dir) { return dir === "desc" ? "asc" : "desc"; };
      if (extend && state.spec.length) {
        // shift-click: add the column as a further key, or flip it where it is
        if (at >= 0) state.spec[at].dir = flip(state.spec[at].dir);
        else state.spec.push({key: key, dir: c.first, numeric: c.numeric});
      } else {
        var dir = c.first;
        if (at === 0) dir = flip(state.spec[0].dir);
        else if (!state.spec.length && initialState && initialState[0] === c.th) {
          dir = initialState[1] === "descending" ? "asc" : "desc";
        }
        state.spec = [{key: key, dir: dir, numeric: c.numeric}];
      }
      render();
      table.dispatchEvent(new CustomEvent("tablesort"));
    }

    Object.keys(cols).forEach(function (key) {
      var th = cols[key].th;
      var button = document.createElement("button");
      button.type = "button";
      button.className = "th-sort";
      while (th.firstChild) button.appendChild(th.firstChild);
      th.appendChild(button);
      button.addEventListener("click", function (e) { headerClick(key, e.shiftKey); });
    });

    if (!isList) return;
    if (controls) controls.hidden = false;

    if (picker) {
      picker.addEventListener("change", function () {
        state.spec = picker.value ? orderSpec(picker.value.split(",")) : [];
        render();
        table.dispatchEvent(new CustomEvent("tablesort"));
      });
    }
    statusButtons.forEach(function (b) {
      b.addEventListener("click", function () {
        state.status = b.dataset.listStatus === "accepted" ? "accepted" : "all";
        render();
      });
    });

    var params = new URLSearchParams(location.search);
    state.spec = resolve(parseSort(params.get("sort")));
    if (statusButtons.length && params.get("status") === "accepted") state.status = "accepted";
    if (orders.length && !state.spec.length && picker) picker.value = "";
    render();
  }

  document.querySelectorAll("table").forEach(function (table) {
    if (table.querySelector("th[data-sort]")) setup(table);
  });
})();
