# Dashboard requirements that still lived in meta

2026-11-19 — what `systems42-org/meta` still held about the dashboard, and what of it this wiki lacked. Drafted by Claude from [meta issue #49](https://github.com/systems42-org/meta/issues/49) (sub-issue of meta #38) and the meta pages named below; read and decided by Peter Gerstbach. The pages stay in meta until this capture has landed here, then meta removes them.

## Rule

The dashboard's requirements live here (DR-005). Where both wikis cover a topic, this wiki's finer structure wins. What exists only in meta is captured here.

## Covered here already, nothing to capture

- meta FR-010 "Requirements dashboard": stays in meta as the product-level feature; here the dashboard is the whole wiki.
- meta DR-025 provenance chips: FR-034 shows the sources in the page head.
- meta DR-032 five nav entries: FR-014 fixes a different five, with reasons. This wiki wins.
- meta DR-033 three areas, two levels, hide list: FR-017, FR-023, FR-044 and FR-046 (the View, written to no file).
- meta DR-022 presence, Keyholder, Disconnect all, QR join: FR-046. "Yoda" stays as the name of the first Keyholder.
- meta DR-025 QR join: FR-046.
- meta DR-024 brand requirements stays in meta (a method decision).

## To capture

1. **meta FR-012 "Visualise the requirements hierarchy".** As a business analyst I want to see the requirements hierarchy as a diagram, and a detail diagram for an element I select, so that I grasp the structure at a glance instead of reading lists. Criteria: the hierarchy is drawn as a diagram with the project's level names; selecting an element shows its children and its linked building blocks; a changed page changes the diagram without manual redrawing. The dashboard shows today a goals diagram and epic cards with a breakdown page, but no detail diagram. Building blocks exist in the wikis the dashboard shows, so the requirement holds.
2. **meta FR-013 "Hide cross-references and metadata".** As a subject matter expert I want to hide cross-references and metadata in requirement text, so that the requirement reads cleanly. Criteria: with the filter on, the text shows plain wording without square brackets or IDs; the setting is kept in the browser; another viewer's view does not change. Source: the team meeting of 2026-10-12 (meta `raw/ingested/entscheidungen-meeting-12-10-2026.md`, line 55: "Filterfunktionen ... Hoch"), an explicit wish of Peter Hruschka. Scope: the text of a page only.
3. **meta FR-034 "Show delivery status on the dashboard".** A badge per requirement and a filter by delivery status. The method behind it is meta FR-031, which the Implement loop of meta is still building; the dashboard does not read delivery fields yet.
4. **meta QR-004 "Current browser support".** The latest two stable major versions of Firefox, Chrome, Edge and Safari (macOS), Safari (iOS) and Chrome (Android). Every page renders and is usable, on a phone without horizontal scrolling; the dashboard keeps running while a page is open, including Back/Forward, reload and five minutes in the background; after the last page closes it stops within 30 s. Checked by hand before each release, on a real iPhone and Android phone. Origin: in Firefox the dashboard stopped itself while a page was open.
5. **meta DR-022 self-shutdown.** Becomes a requirement, not a decision record: the dashboard stops itself when nobody is watching. Heartbeat of every open page (about 20 s), a short grace after a page announces it is leaving (about 5 s), a longer grace otherwise (90 s, longer than the browser's throttling of background tabs, about 60 s), and a grace at start-up if no page ever connects. Closing the tab is the stop gesture; there is no stop button, because a page cannot close its own tab. It can be switched off when the dashboard starts.
6. **meta DR-023 term network.** The requirements in it: the network first shows only the terms; further page types are shown layer by layer, and their buttons are the legend; edges are undirected, merged, and taken only from `related:`, never from wikilinks in the text; the type is told by the frame colour and the state (agreed, draft, deprecated, assumption) by the frame style; the size follows the number of links; labels are always visible; hovering highlights the neighbours; both themes read the same. Every term page shows its own one-hop network with the same layer buttons and a link to the whole network. The decision in it, a server projection of data with the layout in the browser, while Mermaid stays for static diagrams, becomes a small decision record here.
7. **meta DR-032 ⌘K.** ⌘K (Ctrl K elsewhere) focuses the search box; the placeholder names the key. It is built.
8. **meta DR-033 menu.** One menu holds the View, the theme, who is here, reload and Disconnect all. FR-013 here leaves the menu out of scope; the theme switch is nowhere.
