// Incremental search in the topbar: typing into #nav-search shows the best
// matches in a popup, ranked by static/search-rank.js (the same ranking as the
// /search page). The index (/search.json) is fetched once, on first focus.
//
// Keys: ↓/↑ move through the results, Enter opens the highlighted result,
// Enter with nothing highlighted — or Cmd/Ctrl-Enter at any time — opens the
// full /search results page. Esc closes the popup, a second Esc leaves the box.
(function () {
  var box = document.getElementById("nav-search");
  if (!box || !window.S42Search) { return; }
  var form = box.form;
  var MAX = 8;
  var records = null, loading = null;
  var hits = [], active = -1, total = 0;

  var pop = document.createElement("div");
  pop.className = "search-pop";
  pop.id = "nav-search-pop";
  pop.hidden = true;
  form.appendChild(pop);
  box.setAttribute("role", "combobox");
  box.setAttribute("aria-autocomplete", "list");
  box.setAttribute("aria-controls", pop.id);
  box.setAttribute("aria-expanded", "false");

  function load() {
    if (!loading) {
      loading = fetch("/search.json").then(function (r) { return r.json(); })
        .then(function (data) { records = data; render(); })
        .catch(function () { loading = null; });
    }
    return loading;
  }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) {
      return {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c];
    });
  }

  function close() {
    pop.hidden = true;
    active = -1;
    box.setAttribute("aria-expanded", "false");
    box.removeAttribute("aria-activedescendant");
  }

  function setActive(i) {
    active = i;
    Array.prototype.forEach.call(pop.querySelectorAll(".sp-item"), function (el, j) {
      el.classList.toggle("is-active", j === i);
      el.setAttribute("aria-selected", j === i ? "true" : "false");
    });
    if (i >= 0) {
      box.setAttribute("aria-activedescendant", "sp-opt-" + i);
      var el = document.getElementById("sp-opt-" + i);
      if (el) { el.scrollIntoView({block: "nearest"}); }
    } else {
      box.removeAttribute("aria-activedescendant");
    }
  }

  function render() {
    var q = box.value.trim();
    if (!q || !records) { close(); return; }
    var ranked = window.S42Search.rank(records, q);
    total = ranked.length;
    hits = ranked.slice(0, MAX);
    var html = '<ul class="sp-list" role="listbox" aria-label="Search results">';
    hits.forEach(function (h, i) {
      var r = h.rec;
      html += '<li role="option" aria-selected="false" id="sp-opt-' + i + '">' +
        '<a class="sp-item" href="' + esc(r.url) + '" tabindex="-1">' +
        '<span class="badge kind-badge">' + esc(r.type) + '</span>' +
        '<code class="sresult-id">' + esc(r.id) + '</code>' +
        '<span class="sp-title">' + esc(r.title) + '</span>' +
        '<span class="sresult-score" data-band="' + window.S42Search.band(h.score) + '" title="Relevance">' +
        '<span class="score-track"><span class="score-fill" style="width:' + h.score + '%"></span></span>' +
        '<span class="score-pct">' + h.score + '%</span></span></a></li>';
    });
    html += "</ul>";
    if (!hits.length) { html = '<p class="sp-empty">No matches.</p>'; }
    var mac = /Mac|iPhone|iPad/.test(navigator.platform || "");
    html += '<a class="sp-all" href="/search?q=' + encodeURIComponent(q) + '" tabindex="-1">' +
      (total > hits.length ? "All " + total + " results" : "Open the search page") +
      ' <kbd>' + (mac ? "⌘" : "Ctrl") + "↵</kbd></a>";
    pop.innerHTML = html;
    pop.hidden = false;
    box.setAttribute("aria-expanded", "true");
    setActive(-1);
  }

  function fullSearch() {
    window.location.href = "/search?q=" + encodeURIComponent(box.value.trim());
  }

  box.addEventListener("focus", function () { load(); render(); });
  box.addEventListener("input", function () { load(); render(); });
  box.addEventListener("keydown", function (e) {
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      if (pop.hidden) { render(); }
      if (!hits.length) { return; }
      e.preventDefault();
      var n = hits.length;
      setActive(e.key === "ArrowDown" ? (active + 1) % n : (active <= 0 ? n - 1 : active - 1));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (!box.value.trim()) { return; }
      if (e.metaKey || e.ctrlKey || active < 0 || pop.hidden) { fullSearch(); }
      else { window.location.href = hits[active].rec.url; }
    } else if (e.key === "Escape") {
      if (!pop.hidden) { e.preventDefault(); close(); } else { box.blur(); }
    } else if (e.key === "Tab") {
      close();
    }
  });
  // keep focus in the box while clicking a result, so the blur below never
  // closes the popup out from under the click
  pop.addEventListener("mousedown", function (e) { e.preventDefault(); });
  pop.addEventListener("mousemove", function (e) {
    var li = e.target.closest("li[role=option]");
    if (li) {
      var i = parseInt(li.id.replace("sp-opt-", ""), 10);
      if (i !== active) { setActive(i); }
    }
  });
  box.addEventListener("blur", close);
  form.addEventListener("submit", function (e) { e.preventDefault(); fullSearch(); });
})();
