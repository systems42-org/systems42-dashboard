/* Draws one diagram from data. The app calls S42Diagram.render(payload) with a JSON object and
   gets the outcome back as a string. Text from the wiki reaches the page only as data: Mermaid
   gets it through textContent, cytoscape through its element data. Nothing is concatenated into HTML.

   payload: { kind: "mermaid" | "graph", theme: "light" | "dark",
              text: String                      (mermaid; click lines are already removed),
              graph: { nodes, edges }, preset: "term-network" | "metamodel"   (graph),
              links: [node id]                  (the nodes a click is reported for) }
   A click posts the node id, a string, to the "select" handler. The app checks it again. */
window.S42Diagram = (function () {
  "use strict";
  var host = document.getElementById("diagram");
  var cy = null;
  var themeObserver = null;

  var CLUSTER = {
    light: { clusterBkg: "#eaf1fa", clusterBorder: "#d2ddec", titleColor: "#4c5c7a" },
    dark: { clusterBkg: "#14203a", clusterBorder: "#25345a", titleColor: "#9fb0cc" }
  };

  function post(id) {
    var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.select;
    if (handler) { handler.postMessage(String(id)); }
  }

  function reset() {
    if (cy) { cy.destroy(); cy = null; }
    host.className = "";
    host.replaceChildren();
  }

  function message(text) {
    reset();
    var p = document.createElement("p");
    p.className = "s42-message";
    p.textContent = text;
    host.appendChild(p);
  }

  // Mermaid names a flowchart node element "mermaid-<n>-flowchart-<id>-<k>".
  function mermaidNodeID(el) {
    var id = el.getAttribute("id") || "";
    var marker = "flowchart-";
    var at = id.indexOf(marker);
    if (at < 0 || (at > 0 && id.charAt(at - 1) !== "-")) { return null; }
    var from = at + marker.length;
    var cut = id.lastIndexOf("-");
    return cut > from ? id.slice(from, cut) : null;
  }

  function bindMermaidClicks(root, links) {
    var wanted = new Set(links);
    root.querySelectorAll("g.node").forEach(function (el) {
      var id = mermaidNodeID(el);
      if (id === null || !wanted.has(id)) { return; }
      el.classList.add("s42-link");
      el.setAttribute("role", "link");
      el.setAttribute("tabindex", "0");
      el.setAttribute("aria-label", (el.textContent || "").trim());
      el.addEventListener("click", function () { post(id); });
      el.addEventListener("keydown", function (e) { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); post(id); } });
    });
  }

  // Keys a %%{init}%% directive in the text may not change, besides Mermaid's own list.
  var SECURE = ["secure", "securityLevel", "startOnLoad", "maxTextSize", "suppressErrorRendering", "maxEdges",
                "htmlLabels", "flowchart", "theme", "themeVariables"];

  function mermaidConfig(payload) {
    var light = payload.theme === "light";
    return {
      startOnLoad: false, securityLevel: "strict", htmlLabels: false, suppressErrorRendering: true,
      maxTextSize: payload.maxText, secure: SECURE,
      theme: light ? "default" : "dark", themeVariables: light ? CLUSTER.light : CLUSTER.dark,
      flowchart: { useMaxWidth: true, curve: "basis", htmlLabels: false },
      sequence: { useMaxWidth: true }, er: { useMaxWidth: true }, class: { useMaxWidth: true }
    };
  }

  function isErrorDrawing(svg) {
    return svg.getAttribute("aria-roledescription") === "error" || svg.querySelector(".error-icon, .error-text") !== null;
  }

  function drawMermaid(payload) {
    if (!window.mermaid) { message("The diagram library did not load."); return Promise.resolve("error: mermaid missing"); }
    reset();
    var pre = document.createElement("pre");
    pre.className = "mermaid";
    pre.textContent = payload.text;
    host.appendChild(pre);
    // Start from the defaults every time, so nothing a diagram text changed stays for the next one.
    if (mermaid.mermaidAPI && mermaid.mermaidAPI.reset) { mermaid.mermaidAPI.reset(); }
    mermaid.initialize(mermaidConfig(payload));
    return Promise.resolve(mermaid.run({ nodes: [pre] })).then(function () {
      var svg = pre.querySelector("svg");
      if (!svg || isErrorDrawing(svg)) { message("This diagram could not be drawn."); return "error: no svg"; }
      bindMermaidClicks(pre, payload.links || []);
      return "ok";
    }, function () {
      message("This diagram could not be drawn.");
      return "error: mermaid";
    });
  }

  function styleFor(preset) {
    var module = preset === "metamodel" ? window.AQ_METAMODEL_GRAPH : window.AQ_GLOSSARY_GRAPH;
    return module && module.style ? module.style : null;
  }

  function drawGraph(payload) {
    var G = window.AQ_GLOSSARY_GRAPH;
    var style = styleFor(payload.preset);
    if (!window.cytoscape || !G || !style) { message("The diagram library did not load."); return Promise.resolve("error: cytoscape missing"); }
    reset();
    host.className = "graph";
    var reg = G.register(window.cytoscape);
    var engine = reg.avail.fcose ? "fcose" : "cose";
    var links = new Set(payload.links || []);
    var frames = payload.frameColours || {};
    // The frame colour of a node type, from the app. Only plain prefixes and colours make a selector.
    var ALNUM = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    function plain(text, extra) {
      return typeof text === "string" && text.length > 0 && text.length < 20 &&
        Array.prototype.every.call(text, function (c) { return ALNUM.indexOf(c) >= 0 || extra.indexOf(c) >= 0; });
    }
    function styled() {
      var rules = style();
      Object.keys(frames).forEach(function (prefix) {
        if (plain(prefix, "_-") && plain(frames[prefix], "#")) {
          rules.push({ selector: 'node[type="' + prefix + '"]', style: { "border-color": frames[prefix] } });
        }
      });
      return rules;
    }
    cy = window.cytoscape({
      container: host, elements: { nodes: payload.graph.nodes, edges: payload.graph.edges },
      wheelSensitivity: 0.2, style: styled(), layout: { name: "preset" }
    });
    cy.on("tap", "node", function (e) { var id = e.target.id(); if (links.has(id)) { post(id); } });
    if (themeObserver) { themeObserver.disconnect(); }
    var current = cy;
    themeObserver = new MutationObserver(function () { current.style(styled()); });
    themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] });
    var options = G.layoutOpts(engine, true, { compact: payload.preset !== "metamodel" && payload.graph.nodes.length < 12 });
    options.animate = false;
    if (payload.preset === "metamodel" && engine === "fcose") {   // groups and long edge labels need room
      options.nodeSeparation = 110; options.idealEdgeLength = 150; options.nestingFactor = 0.1;
    }
    var layout = cy.layout(options);
    if (payload.graph.nodes.length === 0) { return Promise.resolve("ok"); }
    return new Promise(function (resolve) {
      layout.one("layoutstop", function () { current.fit(current.elements(), 30); resolve("ok"); });
      layout.run();
    });
  }

  function render(payload) {
    document.documentElement.setAttribute("data-theme", payload.theme === "dark" ? "dark" : "light");
    if (payload.kind === "mermaid") { return drawMermaid(payload); }
    if (payload.kind === "graph") { return drawGraph(payload); }
    message("This diagram could not be drawn.");
    return Promise.resolve("error: unknown kind");
  }

  // For the tests of the app: the node count of the graph on show, and a tap as the page would see it.
  function tap(id) {
    if (!cy) { return false; }
    var node = cy.getElementById(String(id));
    if (node.empty()) { return false; }
    node.emit("tap");
    return true;
  }

  // For the tests of the app: the settings Mermaid draws with now.
  function config() {
    var c = window.mermaid && mermaid.mermaidAPI ? mermaid.mermaidAPI.getConfig() : {};
    return { htmlLabels: c.htmlLabels === true, flowchartHtmlLabels: !!(c.flowchart && c.flowchart.htmlLabels), securityLevel: c.securityLevel };
  }

  return { config: config, render: render, count: function () { return cy ? cy.nodes().length : -1; }, tap: tap };
})();
