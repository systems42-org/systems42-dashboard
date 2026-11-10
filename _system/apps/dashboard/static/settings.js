// Configure dialog: the hide list behind _system/dashboard.yaml (DR-033).
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

  function clientId() {
    try { return sessionStorage.getItem("etsu-client-id") || ""; } catch (e) { return ""; }
  }
  function facilitator() { return document.documentElement.dataset.facilitator === "1"; }

  function render(data) {
    var hidden = {};
    data.hidden.forEach(function (k) { hidden[k] = true; });
    groups.innerHTML = "";
    data.areas.forEach(function (a) {
      var fs = document.createElement("fieldset");
      fs.className = "settings-group settings-group-" + (a.key === "commons" ? "commons" : a.colors[0]);
      var lg = document.createElement("label");
      lg.className = "settings-area settings-area-" + (a.key === "commons" ? "commons" : a.colors[0]);
      lg.innerHTML = '<input type="checkbox" name="area" value="' + a.key + '"' + (hidden[a.key] ? "" : " checked") + "> <strong>" + a.label + "</strong>";
      fs.appendChild(lg);
      a.sections.forEach(function (s) {
        var l = document.createElement("label");
        l.className = "settings-section settings-section-" + s.colors[0] + (s.scope === "in" ? "" : " is-out");
        var chip = s.colors.map(function (c) { return "settings-id-" + c; }).join(" ");
        l.innerHTML = '<input type="checkbox" name="section" value="' + s.id + '"' + (hidden[s.id] ? "" : " checked") + '> <code class="settings-id ' + chip + '">' + s.id + "</code> <span>" + s.title + "</span>";
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
    }).catch(function () { window.alert("Could not load the settings."); });
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
        window.alert(String(err.message) === "403" ? "Only the facilitator can save." : "Could not save the settings.");
      });
  });
})();
