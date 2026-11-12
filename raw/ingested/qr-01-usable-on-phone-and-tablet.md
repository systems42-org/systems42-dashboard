# Usable on phone and tablet

Raised by Gernot Starke on 2026-11-12. Drafted by Claude. Nobody has agreed this requirement yet.

**Requirement.** Every page of the dashboard is easy to read and use on a phone or a tablet, not only on a laptop. The layout adapts to the screen (responsive design).

**Kind.** Quality requirement. ISO 25010: flexibility (adaptability) and interaction capability (operability).

**Serves.** GOAL-003 Answers without asking a colleague, GOAL-007 Readers who come back.

**For.** Workshop participants who open a shared link on their phone, product owners and developers who look something up away from their desk, presenters who show the dashboard on a tablet.

## Quality scenario

- **Source.** A workshop participant.
- **Stimulus.** Opens a link to a dashboard page on a phone.
- **Environment.** Phone in portrait, 360 CSS pixels wide, normal workshop use.
- **Response.** The page fits the screen. Search, menu, lists, filters and links all work by touch.
- **Measure.**
  - No page scrolls sideways at 360 pixels width. Wide tables and diagrams may scroll inside their own box.
  - Text is readable without zooming.
  - Every link and button is at least 24 × 24 CSS pixels (WCAG 2.2, 2.5.8).
  - Nothing a laptop reader can do is missing on the phone.

## Open points

- Which narrowest width counts: 360 pixels, or smaller?
- Must large diagrams (context, glossary network, building blocks) work on a phone, or is "readable on a tablet" enough for them?
- Priority: Must or Should?
