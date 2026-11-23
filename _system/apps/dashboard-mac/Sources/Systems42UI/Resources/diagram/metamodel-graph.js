/* The metamodel as a network (DR-035), for /metamodel.
 *
 * Same visual language as the glossary term network (glossary-graph.js): nodes
 * are card-coloured boxes with a thick frame in the type's colour, taken from
 * the page's theme tokens, so the graph follows the light/dark switch. On top
 * of that: compound parents for the req42 blocks a type lives in, directed
 * edges with an arrow at the target and the field name as label, dashed edges
 * for hierarchies (`parent`), loops for a relation inside one type.
 *
 * Reuses the shared module for engine registration, the font-ready guard and
 * the layout options; the style is its own, because the shared one knows only
 * the term network's node types and its theme observer would re-apply it.
 */
window.AQ_METAMODEL_GRAPH = (function () {
  var G = window.AQ_GLOSSARY_GRAPH;

  function token(name, fallback) {
    var v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return v || fallback;
  }
  // one frame colour per type: --layer-<prefix>-ink, REST when a type has none
  function frameColour(prefix) {
    var rest = token('--layer-rest-ink', '#aab4c9');
    return prefix ? token('--layer-' + String(prefix).toLowerCase() + '-ink', rest) : rest;
  }
  function tokens() {
    return {
      card: token('--card', '#16223d'), card2: token('--card-2', '#1b294a'),
      soft: token('--bg-soft', '#14203a'), line: token('--line', '#25345a'),
      ink: token('--ink', '#e8eef9'), dim: token('--ink-dim', '#6f81a3'),
      softInk: token('--ink-soft', '#9fb0cc'), accent: token('--accent', '#3ea6ff'),
      bg: token('--graph-bg', '#0c1424'), font: token('--font-text', 'sans-serif'),
      mono: token('--font-mono', 'monospace')
    };
  }

  function style() {
    var t = tokens();
    return [
      { selector: 'node', style: {
          'label': function (ele) { var d = ele.data(); return d.prefix ? d.prefix + '\n' + d.label : d.label; },
          'font-family': t.font, 'font-size': 12, 'font-weight': 500,
          'text-valign': 'center', 'text-halign': 'center',
          'text-wrap': 'wrap', 'text-max-width': 150, 'line-height': 1.25,
          'width': 'label', 'height': 'label', 'padding': '14px',
          'shape': 'round-rectangle', 'background-color': t.card, 'background-opacity': 1,
          'color': t.ink, 'text-outline-width': 0, 'border-style': 'solid', 'border-width': 3.5,
          'border-color': function (ele) { return frameColour(ele.data('prefix')); }
      }},
      { selector: 'node[prefix="SRC"]', style: { 'border-style': 'dashed' }},
      // a section: a soft, dashed group frame with its title along the top
      { selector: 'node[?is_block]', style: {
          'shape': 'round-rectangle', 'background-color': t.soft, 'background-opacity': .55,
          'border-width': 1, 'border-style': 'dashed', 'border-color': t.dim,
          'label': 'data(label)', 'font-size': 11, 'font-weight': 600, 'color': t.softInk,
          'text-valign': 'top', 'text-halign': 'center', 'text-margin-y': -6,
          'padding': '24px', 'text-wrap': 'none'
      }},
      { selector: 'edge', style: {
          'width': 1.8, 'line-color': t.dim, 'curve-style': 'bezier', 'opacity': .9,
          'target-arrow-shape': 'triangle', 'target-arrow-color': t.dim, 'arrow-scale': 1.1,
          'label': 'data(label)', 'font-family': t.mono, 'font-size': 9.5, 'color': t.softInk,
          'text-rotation': 'autorotate', 'text-margin-y': -7,
          'text-background-color': t.bg, 'text-background-opacity': 1, 'text-background-padding': '2px',
          'text-background-shape': 'round-rectangle'
      }},
      { selector: 'edge[?symmetric]', style: { 'target-arrow-shape': 'none' }},
      { selector: 'edge[semantics="hierarchy"]', style: { 'line-style': 'dashed', 'line-dash-pattern': [6, 4] }},
      { selector: 'edge[loop_dir]', style: { 'loop-direction': 'data(loop_dir)', 'loop-sweep': '50deg', 'text-rotation': 'none', 'text-margin-y': -4 }},
      { selector: 'edge.nolabels', style: { 'text-opacity': 0, 'text-background-opacity': 0 }},
      { selector: '.faded', style: { 'opacity': 0.15, 'text-opacity': 0.15, 'text-background-opacity': 0.15 }},
      { selector: 'node[?is_block].faded', style: { 'opacity': 0.5 }},
      { selector: 'edge.high', style: { 'line-color': t.accent, 'target-arrow-color': t.accent, 'width': 2.8, 'opacity': 1, 'color': t.ink }}
    ];
  }

  function mount(opts) {
    var cytoscape = window.cytoscape;
    if (!cytoscape || !G || !opts || !opts.container) return null;
    var reg = G.register(cytoscape);
    var LAYOUT = reg.avail.fcose ? 'fcose' : reg.layout;   // fcose packs compound groups best
    var container = opts.container, data = opts.data;

    G.ready(function () {
      var cy = cytoscape({
        container: container,
        elements: { nodes: data.nodes, edges: data.edges },
        wheelSensitivity: 0.2,
        style: style(),
        layout: { name: 'preset' }
      });

      // follow the theme switch (base.html flips data-theme on <html>)
      new MutationObserver(function () { cy.style(style()); })
        .observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });

      // tooltip: German label, stereotypes, or the edge's cardinality and note
      var tip = document.createElement('div');
      tip.className = 'graph-tip'; tip.hidden = true;
      container.parentNode.insertBefore(tip, container.nextSibling);
      function hide() { tip.hidden = true; }
      function showTip(ele, text) {
        if (!text) return hide();
        var bb = ele.renderedBoundingBox(), host = container.getBoundingClientRect();
        tip.textContent = text;
        tip.style.left = Math.round(host.left + window.scrollX + bb.x1) + 'px';
        tip.style.top = Math.round(host.top + window.scrollY + bb.y2 + 6) + 'px';
        tip.hidden = false;
      }
      cy.on('mouseover', 'node', function (e) {
        var d = e.target.data(), parts = [];
        if (d.is_block) return hide();
        if (d.label_de) parts.push(d.label_de);
        if (d.stereotypes) parts.push('stereotypes: ' + d.stereotypes);
        parts.push('tap twice to open the row');
        showTip(e.target, parts.join('\n'));
      });
      cy.on('mouseover', 'edge', function (e) {
        var d = e.target.data(), parts = [d.label + (d.cardinality ? '  ' + d.cardinality : '')];
        if (d.note) parts.push(d.note);
        showTip(e.target, parts.join('\n'));
      });
      cy.on('mouseout grab pan zoom', hide);

      // hover or tap highlights the neighbourhood; a second tap on the focused
      // node scrolls to its row in the type table
      var focusedId = null;
      function highlight(node) {
        cy.elements().addClass('faded');
        var nb = node.closedNeighborhood();
        nb.removeClass('faded'); nb.edges().addClass('high');
        node.parent().removeClass('faded');
      }
      function clearHighlight() { cy.elements().removeClass('faded'); cy.edges().removeClass('high'); }
      cy.on('mouseover', 'node[!is_block]', function (e) { if (!focusedId) highlight(e.target); });
      cy.on('mouseout', 'node', function () { if (!focusedId) clearHighlight(); });
      cy.on('tap', 'node[!is_block]', function (e) {
        var n = e.target;
        if (focusedId === n.id()) { var u = n.data('url'); if (u) window.location.hash = u; return; }
        focusedId = n.id(); highlight(n);
      });
      cy.on('tap', function (e) { if (e.target === cy) { focusedId = null; clearHighlight(); } });

      var running = null;
      function runLayout(randomize) {
        if (running) { try { running.stop(); } catch (err) {} }
        var o = G.layoutOpts(LAYOUT, randomize);
        if (LAYOUT === 'fcose') { o.nodeSeparation = 110; o.idealEdgeLength = 150; o.nestingFactor = 0.1; }
        running = cy.layout(o);
        running.one('layoutstop', function () {
          cy.animate({ fit: { eles: cy.elements(), padding: 30 } }, { duration: 300 });
        });
        running.run();
      }

      // layout buttons: switch → fresh layout; re-click → tidy from current positions
      var layoutBtns = opts.layoutSelector ? document.querySelectorAll(opts.layoutSelector + ' .lay-btn') : [];
      function paintBtns() {
        layoutBtns.forEach(function (b) {
          var on = b.dataset.lay === LAYOUT;
          b.setAttribute('aria-pressed', on ? 'true' : 'false'); b.classList.toggle('on', on);
        });
      }
      layoutBtns.forEach(function (b) {
        if (!reg.avail[b.dataset.lay]) { b.disabled = true; b.title = b.dataset.lay + ' not loaded'; return; }
        b.addEventListener('click', function () {
          var same = LAYOUT === b.dataset.lay;
          LAYOUT = b.dataset.lay; paintBtns(); runLayout(!same);
        });
      });
      paintBtns();
      var fit = opts.fitButton ? document.querySelector(opts.fitButton) : null;
      if (fit) fit.addEventListener('click', function () { cy.animate({ fit: { eles: cy.elements(), padding: 30 } }, { duration: 300 }); });
      var toggle = opts.edgeLabelToggle ? document.querySelector(opts.edgeLabelToggle) : null;
      if (toggle) toggle.addEventListener('change', function () { cy.edges().toggleClass('nolabels', !toggle.checked); });

      runLayout(true);
    });
    return null;
  }

  return { style: style, mount: mount };
})();
