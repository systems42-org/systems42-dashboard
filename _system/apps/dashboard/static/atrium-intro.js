// atrium logo intro: the lockup's twelve pieces (templates/_atrium_lockup.html)
// spiral in from the edges of their frame and settle into the finished logo
// in about a second. Two uses:
//   - the home-page splash (#atrium-splash), once per browser tab;
//   - /about, where it replaces the static lockup image of the brand guide.
// Loaded without `defer` right after the splash markup, so the splash is up
// before the home page paints — no flash of the page underneath.
// prefers-reduced-motion: no splash, and /about shows the still logo.
(function () {
  "use strict";
  var CENTRE = { x: 117, y: 79.7 };   // middle of the finished lockup, in group coordinates
  var reduce = !!(window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches);

  function easeOut(t) { return 1 - Math.pow(1 - t, 3); }
  function lerp(a, b, t) { return a + (b - a) * t; }

  function settle(svg, pieces) {
    pieces.forEach(function (g) { g.removeAttribute("transform"); g.style.opacity = ""; });
    svg.classList.remove("is-armed");
  }

  // Fly the pieces of `svg` together; resolves once the logo stands.
  // `frame` is the element whose edges the pieces start just outside of.
  function play(svg, frame, duration) {
    var dur = duration || 1000;
    var pieces = [].slice.call(svg.querySelectorAll(".intro-piece"));
    cancelAnimationFrame(svg._introRaf);
    if (reduce) { settle(svg, pieces); return Promise.resolve(); }
    var box = (frame || svg).getBoundingClientRect();
    var scale = svg.getScreenCTM().a || 1;               // px per SVG unit
    var r0 = Math.hypot(box.width, box.height) / 2 / scale + 30;
    var n = pieces.length;
    var meta = pieces.map(function (g, i) {
      var b = g.getBBox();
      var c = { x: b.x + b.width / 2, y: b.y + b.height / 2 };
      var entry = (i / n) * 2 * Math.PI + 0.4;             // every edge gets a piece
      var final = Math.atan2(c.y - CENTRE.y, c.x - CENTRE.x);
      while (final < entry) { final += 2 * Math.PI; }
      return {
        g: g, c: c, entry: entry, final: final,
        rf: Math.hypot(c.x - CENTRE.x, c.y - CENTRE.y),
        spin: (i % 2 ? 1 : -1) * (120 + 60 * (i % 3)),     // degrees, unwinding to 0
        delay: ((i * 37) % 160) / 1000,                    // share of the duration
      };
    });
    svg.classList.add("is-armed");
    return new Promise(function (resolve) {
      var t0 = null;
      function step(now) {
        if (t0 === null) { t0 = now; }
        var done = true;
        meta.forEach(function (m) {
          var p = Math.min(1, Math.max(0, ((now - t0) / dur - m.delay) / 0.84));
          if (p < 1) { done = false; }
          var e = easeOut(p);
          // angle and radius shrink together around the logo's centre: a spiral
          var a = lerp(m.entry + 2.2 * Math.PI, m.final, e);
          var r = lerp(r0, m.rf, e);
          var x = CENTRE.x + r * Math.cos(a), y = CENTRE.y + r * Math.sin(a);
          m.g.setAttribute("transform", "translate(" + x + " " + y + ") rotate(" + (1 - e) * m.spin +
            ") scale(" + lerp(0.4, 1, e) + ") translate(" + -m.c.x + " " + -m.c.y + ")");
          m.g.style.opacity = Math.min(1, p * 4);
        });
        if (done) { settle(svg, pieces); resolve(); }
        else { svg._introRaf = requestAnimationFrame(step); }
      }
      svg._introRaf = requestAnimationFrame(step);
    });
  }

  // Home splash: full-window cover, logo flies together, holds, fades.
  // A click or any key skips it.
  function splash() {
    var el = document.getElementById("atrium-splash");
    if (!el) { return; }
    var seen = "1";
    try {
      seen = sessionStorage.getItem("atrium-splash-seen");
      sessionStorage.setItem("atrium-splash-seen", "1");
    } catch (e) {}   // blocked storage: show it, every visit is a first one
    if (seen || reduce) { el.remove(); return; }
    el.hidden = false;
    var closed = false;
    function close() {
      if (closed) { return; }
      closed = true;
      document.removeEventListener("keydown", close);
      el.classList.add("is-leaving");
      setTimeout(function () { el.remove(); }, 400);
    }
    el.addEventListener("click", close);
    document.addEventListener("keydown", close);
    play(el.querySelector("svg"), el).then(function () { setTimeout(close, 700); });
  }

  // /about: swap the brand guide's first lockup image (outside the tables)
  // for the animated logo; play when it scrolls into view, replay on click.
  function about() {
    var tpl = document.getElementById("atrium-lockup-tpl");
    var prose = document.querySelector(".about-prose");
    if (!tpl || !prose) { return; }
    var img = [].slice.call(prose.querySelectorAll('img[src*="atrium-lockup"]'))
      .filter(function (i) { return !i.closest("table"); })[0];
    if (!img) { return; }
    var fig = document.createElement("figure");
    fig.className = "atrium-intro-frame";
    fig.title = "Click to replay";
    fig.appendChild(tpl.content.cloneNode(true));
    var svg = fig.querySelector("svg");
    if (img.alt) { svg.setAttribute("aria-label", img.alt); }
    (img.closest("p") && img.closest("p").children.length === 1 ? img.closest("p") : img).replaceWith(fig);
    fig.addEventListener("click", function () { play(svg, fig); });
    if (!("IntersectionObserver" in window)) { play(svg, fig); return; }
    svg.classList.add("is-armed");   // hidden until it first plays
    var io = new IntersectionObserver(function (entries) {
      if (entries[0].isIntersecting) { io.disconnect(); play(svg, fig); }
    }, { threshold: 0.5 });
    io.observe(fig);
  }

  window.atriumIntro = { play: play };
  if (document.getElementById("atrium-splash")) { splash(); }
  if (document.readyState === "loading") { document.addEventListener("DOMContentLoaded", about); }
  else { about(); }
})();
