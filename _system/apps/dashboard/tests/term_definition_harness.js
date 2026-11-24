// Runs static/term-definition.js under node against a stand-in for one page,
// for tests/test_term_definitions.py.
//
//   node tests/term_definition_harness.js < spec.json
//
// stdin: {viewport: {w, h},                          the window, in CSS pixels
//         box: {w, h},                               the size the box lays out at
//         links: [{title, href, rect: {left, top, right, bottom}}],
//         actions: [{hover: 0} | {leave: 0, to: "box"} | {leaveBox: true} | {focus: 0} | {blur: 0}
//                   | {tap: 0} | {tapElsewhere: true} | {click: 0} | {key: "Escape"} | {wait: 200}]}
// A link without a title stands for a link the script must leave alone.
// Prints one state per action: {shown, text, left, top, open, openHref, role,
// prevented, titles: [title of each link], described: [aria-describedby of each link]}.
var fs = require("fs");
var path = require("path");

var spec = JSON.parse(fs.readFileSync(0, "utf8"));
var now = 1000000, timers = [];

function listeners(target) {
  var map = {};
  target.addEventListener = function (type, fn) { (map[type] = map[type] || []).push(fn); };
  target.fire = function (type, event) { (map[type] || []).forEach(function (fn) { fn(event); }); };
  return target;
}

function element(extra) {
  var el = listeners({});
  var attrs = {};
  el.children = [];
  el.hidden = false;
  el.style = {};
  el.appendChild = function (child) { el.children.push(child); child.parent = el; return child; };
  el.contains = function (node) {
    for (var n = node; n; n = n.parent) { if (n === el) { return true; } }
    return false;
  };
  el.setAttribute = function (name, value) { attrs[name] = String(value); };
  el.getAttribute = function (name) { return name in attrs ? attrs[name] : null; };
  el.removeAttribute = function (name) { delete attrs[name]; };
  Object.keys(extra || {}).forEach(function (k) { el[k] = extra[k]; });
  return el;
}

var created = [];
var document = listeners({
  body: element(),
  documentElement: {clientWidth: spec.viewport.w, clientHeight: spec.viewport.h},
  createElement: function (tag) {
    var el = element({tagName: tag, offsetWidth: spec.box.w, offsetHeight: spec.box.h});
    created.push(el);
    return el;
  }
});
var window = listeners({});

var links = spec.links.map(function (l) {
  var a = element({href: l.href});
  if (l.title) { a.setAttribute("title", l.title); }
  // the selector asks for a title: a link whose title the script took is still its link
  a.closest = function () { return a.getAttribute("title") ? a : null; };
  a.getClientRects = function () { return [l.rect]; };
  a.getBoundingClientRect = function () { return l.rect; };
  document.body.appendChild(a);
  return a;
});
var elsewhere = element({closest: function () { return null; }});

var source = fs.readFileSync(path.join(__dirname, "..", "static", "term-definition.js"), "utf8");
new Function("document", "window", "setTimeout", "clearTimeout", "Date", source)(
  document, window,
  function (fn, ms) { var t = {fn: fn, at: now + ms}; timers.push(t); return t; },
  function (t) { timers = timers.filter(function (x) { return x !== t; }); },
  {now: function () { return now; }});

function wait(ms) {
  now += ms;
  timers.filter(function (t) { return t.at <= now; }).forEach(function (t) {
    timers = timers.filter(function (x) { return x !== t; });
    t.fn();
  });
}

function event(target, extra) {
  var e = {target: target, defaultPrevented: false, relatedTarget: null,
           preventDefault: function () { e.defaultPrevented = true; }};
  Object.keys(extra || {}).forEach(function (k) { e[k] = extra[k]; });
  return e;
}

function box() { return created.filter(function (el) { return el.className === "term-def"; })[0] || null; }
function part(name) { return created.filter(function (el) { return el.className === name; })[0] || null; }

function tap(target) {
  document.fire("pointerdown", event(target, {pointerType: "touch"}));
  document.fire("focusin", event(target));
  document.fire("mouseover", event(target));
  var click = event(target);
  document.fire("click", click);
  return click.defaultPrevented;
}

var states = spec.actions.map(function (a) {
  var prevented = false;
  if ("hover" in a) {
    document.fire("mouseover", event(links[a.hover]));
  } else if ("leave" in a) {
    document.fire("mouseout", event(links[a.leave], {relatedTarget: a.to === "box" ? box() : elsewhere}));
    if (a.to === "box") { box().fire("mouseenter", event(box())); }
  } else if ("leaveBox" in a) {
    box().fire("mouseleave", event(box()));
  } else if ("focus" in a) {
    document.fire("focusin", event(links[a.focus]));
  } else if ("blur" in a) {
    document.fire("focusout", event(links[a.blur], {relatedTarget: elsewhere}));
  } else if ("tap" in a) {
    prevented = tap(links[a.tap]);
  } else if ("tapElsewhere" in a) {
    prevented = tap(elsewhere);
  } else if ("click" in a) {
    document.fire("pointerdown", event(links[a.click], {pointerType: "mouse"}));
    var click = event(links[a.click]);
    document.fire("click", click);
    prevented = click.defaultPrevented;
  } else if ("key" in a) {
    document.fire("keydown", event(elsewhere, {key: a.key}));
  } else if ("wait" in a) {
    wait(a.wait);
  }
  var b = box(), open = part("term-def-open"), text = part("term-def-text");
  return {
    shown: !!b && !b.hidden,
    text: text ? text.textContent : "",
    left: b ? parseFloat(b.style.left) : null,
    top: b ? parseFloat(b.style.top) : null,
    open: !!open && !open.hidden,
    openHref: open ? open.href || "" : "",
    role: b ? b.getAttribute("role") : null,
    inBody: !!b && document.body.contains(b),
    prevented: prevented,
    titles: links.map(function (l) { return l.getAttribute("title"); }),
    described: links.map(function (l) { return l.getAttribute("aria-describedby"); })
  };
});
console.log(JSON.stringify(states));
