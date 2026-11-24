// Runs static/list-view.js under node against a stand-in for one list page,
// for the Python list tests.
//
//   node tests/list_harness.js < spec.json
//
// stdin: {search: "?kind=entity",                    the address the page opens with
//         columns: [{key, numeric}],                 the sortable columns, in order
//         rows: [{status, kind, cells: [text]}],     one text per column
//         kinds: ["", "entity", "none"],             the values of the kind picker, [] = no picker
//         actions: [{kind: "none"} | {status: "accepted"} | {sort: "title"}]}
// An action picks a kind, clicks a status button or clicks a column header.
// Prints {shown: [first cell of each visible row, in order], search, kind, emptyHint, events}.
var fs = require("fs");
var path = require("path");

var spec = JSON.parse(fs.readFileSync(0, "utf8"));

function listeners() {
  var map = {};
  return {
    addEventListener: function (type, fn) { (map[type] = map[type] || []).push(fn); },
    fire: function (type, event) { (map[type] || []).forEach(function (fn) { fn(event || {}); }); }
  };
}

function classList() {
  var set = {};
  return {
    toggle: function (name, on) { if (on) set[name] = true; else delete set[name]; },
    contains: function (name) { return !!set[name]; }
  };
}

function element(extra) {
  var el = listeners();
  var attrs = {};
  el.dataset = {};
  el.classList = classList();
  el.children = [];
  el.firstChild = null;
  el.hidden = false;
  el.appendChild = function (child) { el.children.push(child); return child; };
  el.setAttribute = function (name, value) { attrs[name] = String(value); };
  el.getAttribute = function (name) { return name in attrs ? attrs[name] : null; };
  el.removeAttribute = function (name) { delete attrs[name]; };
  el.hasAttribute = function (name) { return name in attrs; };
  Object.keys(extra || {}).forEach(function (k) { el[k] = extra[k]; });
  return el;
}

var headers = spec.columns.map(function (c, i) {
  var th = element({cellIndex: i, textContent: c.key});
  th.dataset.sort = c.numeric ? "numeric" : "text";
  th.dataset.key = c.key;
  return th;
});
var rows = spec.rows.map(function (r) {
  var tr = element({cells: r.cells.map(function (t) { return {dataset: {}, textContent: t}; })});
  tr.dataset.status = r.status;
  tr.dataset.kind = r.kind;
  return tr;
});
var tbody = {
  rows: rows.slice(),
  appendChild: function (row) {
    tbody.rows.splice(tbody.rows.indexOf(row), 1);
    tbody.rows.push(row);
  }
};
var hint = {hidden: true};
var events = [];
var table = element({
  tHead: {rows: [{cells: headers}]},
  tBodies: [tbody],
  parentNode: {querySelector: function () { return hint; }},
  querySelector: function (sel) {
    if (sel === "th[data-sort]") return headers[0] || null;
    if (sel === "th[aria-sort]") return headers.filter(function (th) { return th.hasAttribute("aria-sort"); })[0] || null;
    throw new Error("table.querySelector: " + sel);
  },
  querySelectorAll: function (sel) {
    if (sel === "th[aria-sort]") return headers.filter(function (th) { return th.hasAttribute("aria-sort"); });
    throw new Error("table.querySelectorAll: " + sel);
  },
  dispatchEvent: function (e) { if (e.type === "listfilter") events.push(e.detail); }
});
table.dataset.list = "domain-term";
table.dataset.sortOrders = "[]";

var kindPicker = spec.kinds.length
  ? element({value: "", options: spec.kinds.map(function (v) { return {value: v}; })})
  : null;
var statusButtons = ["all", "accepted"].map(function (v) {
  var b = element();
  b.dataset.listStatus = v;
  return b;
});
var controls = element({
  querySelector: function (sel) {
    if (sel === "select[data-list-order]") return null;
    if (sel === "select[data-list-kind]") return kindPicker;
    throw new Error("controls.querySelector: " + sel);
  },
  querySelectorAll: function (sel) {
    if (sel === "button[data-list-status]") return statusButtons;
    throw new Error("controls.querySelectorAll: " + sel);
  }
});

var document = {
  querySelectorAll: function (sel) {
    if (sel === "table") return [table];
    if (sel === '[data-list-controls="domain-term"]') return [controls];
    throw new Error("document.querySelectorAll: " + sel);
  },
  createElement: function () { return element(); }
};
var location = {pathname: "/domain-terms", search: spec.search || "", hash: ""};
var history = {
  state: null,
  replaceState: function (state, title, url) {
    var q = url.indexOf("?");
    location.search = q < 0 ? "" : url.slice(q);
  }
};
function CustomEvent(type, init) { this.type = type; this.detail = init && init.detail; }

var src = fs.readFileSync(path.join(__dirname, "..", "static", "list-view.js"), "utf8");
new Function("window", "document", "location", "history", "CustomEvent", src)({}, document, location, history, CustomEvent);

(spec.actions || []).forEach(function (a) {
  if (a.kind !== undefined) {
    kindPicker.value = a.kind;
    kindPicker.fire("change");
  } else if (a.status !== undefined) {
    statusButtons.filter(function (b) { return b.dataset.listStatus === a.status; })[0].fire("click");
  } else if (a.sort !== undefined) {
    // the script wraps each header's content in a button
    headers.filter(function (th) { return th.dataset.key === a.sort; })[0].children[0].fire("click", {shiftKey: false});
  }
});

console.log(JSON.stringify({
  shown: tbody.rows.filter(function (r) { return !r.classList.contains("list-out"); })
    .map(function (r) { return r.cells[0].textContent; }),
  search: location.search,
  kind: kindPicker ? kindPicker.value : null,
  emptyHint: !hint.hidden,
  events: events
}));
