// The definition of a term, shown where the reader meets the term (FR-041).
//
// A link to a domain term (a.wl-term) or to a method term (a.wl-anchor, the
// "Format:" label of a page head) carries its definition in `title`. This
// script shows that text in one box next to the link:
//
//   pointer   on hover. The box stays while the pointer is on the link or on
//             the box, so its text can be selected.
//   keyboard  on focus. Focus stays on the link, Enter opens the page.
//   touch     the first tap shows the box with an "Open the page" link, a
//             second tap on the term opens the page as well.
//   Esc, or a tap or click elsewhere, closes the box.
//
// While the box shows, the link's `title` moves to `aria-describedby`, so a
// screen reader reads the definition once and the browser's own tooltip does
// not cover the box. Without script the `title` stays and the browser shows it.
(function () {
  var SELECTOR = "a.wl-term[title], a.wl-anchor[title], a.format-label[title]";
  var GAP = 6, EDGE = 8, LEAVE_MS = 150, TOUCH_MS = 1000;
  var pop = null, text = null, open = null;
  var current = null, title = "", armed = null, timer = null, lastTouch = 0;

  function build() {
    pop = document.createElement("div");
    pop.className = "term-def";
    pop.setAttribute("role", "tooltip");
    pop.hidden = true;
    text = document.createElement("span");
    text.className = "term-def-text";
    text.id = "term-def-text";
    open = document.createElement("a");
    open.className = "term-def-open";
    open.textContent = "Open the page";
    pop.appendChild(text);
    pop.appendChild(open);
    document.body.appendChild(pop);
    pop.addEventListener("mouseenter", stay);
    pop.addEventListener("mouseleave", leave);
  }

  function linkOf(node) {
    return node && node.closest ? node.closest(SELECTOR) : null;
  }

  function byTouch() {
    return Date.now() - lastTouch < TOUCH_MS;
  }

  // Below the link's first line, or above it when there is no room below.
  // Always inside the viewport, also on a narrow phone.
  function place() {
    if (!current) { return; }
    var r = current.getClientRects()[0] || current.getBoundingClientRect();
    var vw = document.documentElement.clientWidth, vh = document.documentElement.clientHeight;
    var w = pop.offsetWidth, h = pop.offsetHeight;
    var left = Math.max(EDGE, Math.min(r.left, vw - w - EDGE));
    var top = r.bottom + GAP;
    if (top + h > vh - EDGE && r.top - GAP - h >= EDGE) { top = r.top - GAP - h; }
    pop.style.left = left + "px";
    pop.style.top = top + "px";
  }

  function show(link, touch) {
    stay();
    if (current !== link) {
      hide();
      var t = link.getAttribute("title");
      if (!t) { return; }
      if (!pop) { build(); }
      current = link;
      title = t;
      link.removeAttribute("title");
      link.setAttribute("aria-describedby", text.id);
      text.textContent = t;
    }
    open.hidden = !touch;
    open.href = link.href;
    pop.hidden = false;
    place();
  }

  function hide() {
    stay();
    if (!current) { return; }
    current.setAttribute("title", title);
    current.removeAttribute("aria-describedby");
    pop.hidden = true;
    current = null;
    armed = null;
  }

  function stay() {
    if (timer) { clearTimeout(timer); timer = null; }
  }

  function leave() {
    stay();
    timer = setTimeout(hide, LEAVE_MS);
  }

  document.addEventListener("pointerdown", function (e) {
    if (e.pointerType === "touch" || e.pointerType === "pen") { lastTouch = Date.now(); }
    if (current && !current.contains(e.target) && !pop.contains(e.target)) { hide(); }
  }, true);

  document.addEventListener("mouseover", function (e) {
    var link = linkOf(e.target);
    if (link && !byTouch()) { show(link, false); }
  });

  document.addEventListener("mouseout", function (e) {
    if (!current || byTouch() || !current.contains(e.target)) { return; }
    var to = e.relatedTarget;
    if (to && (current.contains(to) || pop.contains(to))) { return; }
    leave();
  });

  document.addEventListener("focusin", function (e) {
    var link = linkOf(e.target);
    // a tap focuses the link too: the click below shows the box then
    if (link && !byTouch()) { show(link, false); }
  });

  document.addEventListener("focusout", function (e) {
    if (!current || byTouch()) { return; }
    var to = e.relatedTarget;
    if (to && (current.contains(to) || pop.contains(to))) { return; }
    hide();
  });

  // The first tap on a term shows its definition instead of leaving the page.
  document.addEventListener("click", function (e) {
    var link = linkOf(e.target) || (current && current.contains(e.target) ? current : null);
    if (!link || !byTouch() || e.defaultPrevented) { return; }
    if (armed === link && current === link) { return; }
    e.preventDefault();
    show(link, true);
    armed = link;
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { hide(); }
  });

  window.addEventListener("scroll", place, { passive: true, capture: true });
  window.addEventListener("resize", place);
})();
