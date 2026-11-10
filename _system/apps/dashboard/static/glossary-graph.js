/* Shared glossary term-network rendering (DR-023).
 *
 * Single source of the cytoscape style, the layout-engine registration and the
 * layout options, used by BOTH the full view (`/graph/glossary`, graph.html) and
 * the per-term ego snippet on a glossary detail page (mountEgo, detail.html).
 * Keeping styling/layout here means a colour or layout tweak lands in one place.
 *
 * Readability amendment (2026-10-12): nodes are card-coloured boxes with a thick
 * frame in the TYPE colour; fill and ink come from the page's theme tokens, so the
 * graph reads the same in the light and the dark theme and re-styles itself when
 * the theme toggles. No per-type shapes (a diamond cannot hold a wrapped title),
 * no text halo (labels sit inside opaque boxes). Neighbour nodes show their ID and
 * a clipped title; the full title appears in a tooltip on hover.
 */
window.AQ_GLOSSARY_GRAPH = (function () {
  var TITLE_CLIP = 48;     // characters of a neighbour title shown inside the node
  var WRAP = 160;          // px, label wrap width

  // --- theme tokens -----------------------------------------------------------
  // Read once per style build from the CSS custom properties, so the graph follows
  // :root / :root[data-theme="light"] without a second colour table in JS.
  function token(name, fallback) {
    var v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return v || fallback;
  }
  function tokens() {
    return {
      card: token('--card', '#16223d'), ink: token('--ink', '#e8eef9'),
      dim: token('--ink-dim', '#6f81a3'),
      accent: token('--accent', '#3ea6ff'), font: token('--font-text', 'sans-serif'),
      GLO: token('--layer-glo-ink', '#5fa3e8'), DM: token('--layer-dm-ink', '#8fd8c4'),
      STK: token('--layer-stk-ink', '#e6b667'), EIF: token('--layer-eif-ink', '#b39ad6'),
      GOAL: token('--layer-goal-ink', '#e0c068'), BB: token('--layer-bb-ink', '#7fb8ff'),
      REST: token('--layer-rest-ink', '#aab4c9')
    };
  }

  // --- labels ---------------------------------------------------------------------
  function clip(s, n) {
    s = String(s || '');
    return s.length > n ? s.slice(0, n - 1).replace(/\s+\S*$/, '') + '…' : s;
  }
  // GLO: the term itself. Neighbours: ID on the first line, clipped title below.
  function label(ele) {
    var d = ele.data();
    if (d.type === 'GLO') return d.label || d.id;
    var id = String(d.id).split('-').slice(0, 2).join('-');
    return id + '\n' + clip(d.label, TITLE_CLIP);
  }
  // Tooltip text: the full title (and a term's aliases) whenever the node clips it.
  function tipText(ele) {
    var d = ele.data(), parts = [];
    if (d.type === 'GLO') { if (d.aliases) parts.push('also: ' + d.aliases); }
    else if ((d.label || '').length > TITLE_CLIP) parts.push(d.label);
    return parts.join('\n');
  }

  // --- style ------------------------------------------------------------------------
  function frame(colour, width) {
    return { 'border-color': colour, 'border-width': width };
  }
  function style() {
    var t = tokens();
    return [
      { selector: 'node', style: {
          'label': label, 'font-family': t.font, 'font-size': 12, 'font-weight': 500,
          'text-valign': 'center', 'text-halign': 'center',
          'text-wrap': 'wrap', 'text-max-width': WRAP, 'line-height': 1.25,
          // `width: label` sizes the box a few px under the label's own bounding
          // box, and the frame is drawn centred on the edge: pad generously so
          // no glyph touches the frame.
          'width': 'label', 'height': 'label', 'padding': '14px',
          'shape': 'round-rectangle', 'background-color': t.card, 'background-opacity': 1,
          'color': t.ink, 'text-outline-width': 0, 'border-style': 'solid'
      }},
      { selector: 'node[type="GLO"]', style: Object.assign({
          'padding': 'mapData(degree, 0, 8, 14, 28)', 'font-weight': 600
      }, frame(t.GLO, 3.5)) },
      // state on a term = frame STYLE (the frame colour is taken by the type)
      { selector: 'node[type="GLO"][state="draft"]', style: { 'border-style': 'dashed' }},
      { selector: 'node[type="GLO"][state="deprecated"]', style: {
          'border-style': 'dotted', 'color': t.dim, 'opacity': 0.6 }},
      { selector: 'node[type="GLO"][?assumption]', style: { 'font-style': 'italic' }},
      { selector: 'node[type="DM"]',   style: frame(t.DM, 3) },
      { selector: 'node[type="STK"]',  style: frame(t.STK, 3) },
      { selector: 'node[type="EIF"]',  style: frame(t.EIF, 3) },
      { selector: 'node[type="GOAL"]', style: frame(t.GOAL, 3) },
      { selector: 'node[type="BB"]',   style: frame(t.BB, 3) },
      { selector: 'node[rest]',        style: frame(t.REST, 3) },
      { selector: 'edge', style: { 'width': 1.8, 'line-color': t.dim, 'curve-style': 'bezier', 'opacity': 0.9 }},
      { selector: 'edge[?cross]', style: { 'line-style': 'dashed', 'line-dash-pattern': [6, 4] }},
      { selector: '.hidden', style: { 'display': 'none' }},
      { selector: '.faded', style: { 'opacity': 0.15, 'text-opacity': 0.15 }},
      { selector: 'edge.high', style: { 'line-color': t.accent, 'width': 2.8, 'opacity': 1 }},
      // ego snippet: ring the focal term so it reads as the centre of its network
      { selector: 'node[?focus]', style: { 'border-color': t.accent, 'border-width': 5 }}
    ];
  }

  // Run `fn` once the page's web fonts are in: cytoscape measures label boxes with
  // whatever font is current, and a box measured in the fallback font is too small
  // for Bricolage Grotesque — text overruns the frame and cola packs nodes too close.
  function ready(fn) {
    if (!document.fonts || !document.fonts.load) { fn(); return; }
    // fonts.ready alone resolves before a face that nothing has used yet is even
    // requested; ask for the faces the labels use, then wait for them.
    var fam = tokens().font.split(',')[0].trim();
    Promise.all(['500 12px ' + fam, '600 12px ' + fam, 'italic 600 12px ' + fam]
      .map(function (f) { return document.fonts.load(f); }))
      .then(function () { return document.fonts.ready; })
      .then(fn, fn);
  }

  // Call `fn` once a node that was just un-hidden really is visible and measured.
  // removeClass('hidden') takes effect on the next frame; a layout started before
  // that frame runs on the old visible set and leaves the new nodes where they were
  // seeded. After the frame, touching each bounding box computes the label boxes
  // the layout will read.
  function measured(cy, fn) {
    requestAnimationFrame(function () {
      cy.nodes(':visible').forEach(function (n) { n.boundingBox({ includeLabels: true }); });
      fn();
    });
  }

  // Pairs of visible nodes whose label boxes intersect — what a cola pass must
  // leave at zero. A pass that ends early (its time budget, not convergence) can
  // leave some; the caller then runs one more incremental pass.
  function overlapping(cy) {
    var ns = cy.nodes(':visible'), bbs = ns.map(function (n) { return n.boundingBox({ includeLabels: true }); }), k = 0;
    for (var i = 0; i < bbs.length; i++) for (var j = i + 1; j < bbs.length; j++) {
      var a = bbs[i], b = bbs[j];
      if (!(a.x2 < b.x1 || a.x1 > b.x2 || a.y2 < b.y1 || a.y1 > b.y2)) k++;
    }
    return k;
  }

  // Re-style when the theme toggles (base.html flips data-theme on <html>) and
  // show the tooltip with the full title next to a hovered node.
  function attach(cy, container) {
    var mo = new MutationObserver(function () { cy.style(style()); });
    mo.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });

    var tip = document.createElement('div');
    tip.className = 'graph-tip'; tip.hidden = true;
    container.parentNode.insertBefore(tip, container.nextSibling);
    function hide() { tip.hidden = true; }
    cy.on('mouseover', 'node', function (e) {
      var text = tipText(e.target);
      if (!text) return hide();
      var bb = e.target.renderedBoundingBox(), host = container.getBoundingClientRect();
      tip.textContent = text;
      tip.style.left = Math.round(host.left + window.scrollX + bb.x1) + 'px';
      tip.style.top = Math.round(host.top + window.scrollY + bb.y2 + 6) + 'px';
      tip.hidden = false;
    });
    cy.on('mouseout grab pan zoom', hide);
    cy.on('mouseout', 'node', hide);
    return { tip: tip, observer: mo };
  }

  // Register fcose (needs cytoscape.use) and detect cola (auto-registers on load).
  // Returns the available engines and the default (cola → fcose → builtin cose).
  function register(cytoscape) {
    var avail = { cose: true, fcose: false, cola: false };
    try { if (window.cytoscapeFcose) { cytoscape.use(window.cytoscapeFcose); avail.fcose = true; } } catch (e) {}
    if (window.cytoscapeCola && window.cola) { avail.cola = true; }
    return { avail: avail, layout: avail.cola ? 'cola' : (avail.fcose ? 'fcose' : 'cose') };
  }

  // Layout options for the chosen engine. `compact:true` tightens spacing for the
  // small ego snippet; the full view passes no extra and gets the original params.
  function layoutOpts(name, randomize, extra) {
    extra = extra || {};
    var c = !!extra.compact;
    var base = { name: name, animate: true, animationDuration: 450, fit: !c,
                 padding: c ? 24 : 45, nodeDimensionsIncludeLabels: true };
    if (name === 'cola') {
      // Finite + avoidOverlap (label-sized boxes): settles and STOPS, so afterwards a
      // drag moves only the grabbed node; fit:false → caller frames once on layoutstop.
      return Object.assign(base, {
        randomize: !!randomize, fit: false,
        avoidOverlap: true, handleDisconnected: true,
        nodeSpacing: function () { return c ? 14 : 20; },
        edgeLength: c ? 120 : 140, maxSimulationTime: c ? 2500 : 4000,
        convergenceThreshold: 0.005, unconstrIter: 15, userConstIter: 20, allConstIter: 40
      });
    }
    if (name === 'fcose') {
      return Object.assign(base, {
        quality: 'proof', randomize: !!randomize, nodeSeparation: c ? 90 : 150,
        idealEdgeLength: c ? 95 : 130, nodeRepulsion: c ? 8000 : 12000,
        gravity: 0.15, gravityRange: 3.8, packComponents: true
      });
    }
    return Object.assign(base, {   // built-in cose fallback
      randomize: !!randomize, nodeOverlap: 30, componentSpacing: c ? 90 : 140,
      idealEdgeLength: c ? 95 : 130, gravity: 0.2
    });
  }

  // Compact, mostly-read-only ego snippet for a glossary detail page. Shows the focal
  // term + its direct GLO neighbours by default; the DM/STK/GOAL buttons reveal the
  // term's neighbours of that type (1-hop). A node tap opens that page.
  function mountEgo(opts) {
    var cytoscape = window.cytoscape;
    if (!cytoscape || !opts || !opts.container) return null;
    var reg = register(cytoscape);
    var LAYOUT = reg.layout;
    var data = opts.data;
    var layersEl = opts.layersSelector ? document.querySelector(opts.layersSelector) : null;

    // created only once the label font is in (see ready): measured boxes are cached
    ready(function () {
    var cy = cytoscape({
      container: opts.container,
      elements: { nodes: data.nodes, edges: data.edges },
      wheelSensitivity: 0.2,
      style: style(),
      layout: { name: 'preset' }
    });
    attach(cy, opts.container);

    function relayout(randomize, retry) {
      cy.nodes().off('grab free position lock unlock');
      var l = cy.elements(':visible').layout(layoutOpts(LAYOUT, randomize, { compact: true }));
      if (LAYOUT === 'cola') {
        l.one('layoutstop', function () {
          cy.nodes().off('grab free position lock unlock');
          if (!retry && overlapping(cy)) { relayout(false, true); return; }   // one more pass settles it
          cy.animate({ fit: { eles: cy.elements(':visible'), padding: 24 } }, { duration: 300 });
        });
      }
      l.run();
    }

    // default: focal term + direct GLO neighbours; cross-type neighbours hidden
    cy.batch(function () {
      cy.nodes().filter(function (n) { return n.data('type') !== 'GLO'; }).addClass('hidden');
      cy.edges().filter(function (e) { return !!e.data('cross'); }).addClass('hidden');
    });

    if (layersEl) {
      layersEl.querySelectorAll('.layer-btn[data-layer]').forEach(function (btn) {
        btn.addEventListener('click', function () {
          var on = btn.getAttribute('aria-pressed') !== 'true';
          btn.setAttribute('aria-pressed', on ? 'true' : 'false');
          btn.classList.toggle('on', on);
          var t = btn.dataset.layer;
          cy.batch(function () {
            var act = on ? 'removeClass' : 'addClass';
            cy.nodes('[type="' + t + '"]')[act]('hidden');
            cy.edges('[ntype="' + t + '"]')[act]('hidden');
          });
          measured(cy, function () { relayout(false); });
        });
      });
    }

    // the snippet doubles as navigation: tap a node → open its page
    cy.on('tap', 'node', function (e) { var u = e.target.data('url'); if (u) window.location = u; });

    relayout(true);
    });
    return null;
  }

  return { style: style, attach: attach, ready: ready, measured: measured, overlapping: overlapping,
           label: label, clip: clip,
           register: register, layoutOpts: layoutOpts, mountEgo: mountEgo };
})();
