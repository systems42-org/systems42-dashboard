// View dialog: the hide list of this session (FR-046). It lives in the
// running dashboard only.
// Everyone can look; only the facilitator (the tab base.html's ping marked
// data-facilitator="1") can save. Posts the same client_id the heartbeat uses.
(function () {
  var dlg = document.getElementById("settings-dialog");
  var openBtn = document.getElementById("open-settings");
  if (!dlg || !openBtn || typeof dlg.showModal !== "function") { return; }
  var groups = document.getElementById("settings-groups");
  var form = document.getElementById("settings-form");
  var save = document.getElementById("settings-save");
  var note = document.getElementById("settings-note");
  var cancel = document.getElementById("settings-cancel");

  // the id base.html's heartbeat uses, which is in memory only when storage
  // is blocked
  function clientId() {
    if (window.etsuClientId) { return window.etsuClientId; }
    try { return sessionStorage.getItem("etsu-client-id") || ""; } catch (e) { return ""; }
  }
  function facilitator() { return document.documentElement.dataset.facilitator === "1"; }

  // Section ids and titles come from the repository's metamodel, so every
  // value goes in as text, never as markup.
  function el(tag, className, text) {
    var n = document.createElement(tag);
    if (className) { n.className = className; }
    if (text !== undefined) { n.textContent = text; }
    return n;
  }
  function checkbox(name, value, checked) {
    var i = el("input");
    i.type = "checkbox";
    i.name = name;
    i.value = value;
    i.checked = checked;
    return i;
  }

  function render(data) {
    var hidden = {};
    data.hidden.forEach(function (k) { hidden[k] = true; });
    groups.textContent = "";
    data.areas.forEach(function (a) {
      var tone = a.key === "commons" ? "commons" : a.colors[0];
      var fs = el("fieldset", "settings-group settings-group-" + tone);
      var lg = el("label", "settings-area settings-area-" + tone);
      lg.append(checkbox("area", a.key, !hidden[a.key]), " ", el("strong", "", a.label));
      fs.appendChild(lg);
      a.sections.forEach(function (s) {
        var l = el("label", "settings-section settings-section-" + s.colors[0] + (s.scope === "in" ? "" : " is-out"));
        var chip = s.colors.map(function (c) { return "settings-id-" + c; }).join(" ");
        l.append(checkbox("section", s.id, !hidden[s.id]), " ",
                 el("code", "settings-id " + chip, s.id), " ", el("span", "", s.title));
        fs.appendChild(l);
      });
      groups.appendChild(fs);
    });
    var can = facilitator();
    save.disabled = !can;
    note.hidden = can;
    groups.querySelectorAll("input").forEach(function (i) { i.disabled = !can; });
  }

  openBtn.addEventListener("click", function () {
    document.getElementById("menu").removeAttribute("open");
    fetch("/settings").then(function (r) { return r.json(); }).then(function (data) {
      render(data);
      dlg.showModal();
    }).catch(function () { window.alert("Could not load the view."); });
  });
  cancel.addEventListener("click", function () { dlg.close(); });

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    var hidden = [];
    groups.querySelectorAll("input").forEach(function (i) { if (!i.checked) { hidden.push(i.value); } });
    save.disabled = true;
    save.textContent = "Saving…";
    fetch("/settings", { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ client_id: clientId(), hidden: hidden }) })
      .then(function (r) { if (!r.ok) { throw new Error(r.status); } window.location.reload(); })
      .catch(function (err) {
        save.disabled = false; save.textContent = "Save";
        window.alert(String(err.message) === "403" ? "Only the facilitator can save." : "Could not save the view.");
      });
  });
})();
