# Header and footer on every page

Written on 2026-11-11 from a conversation between Gernot Starke and Claude about the dashboard's page frame. The header and footer had grown item by item. The footer mixed content links, the state of the view and credits. "Agreed" lists what Gernot stated or accepted in that conversation. "Open" lists what Claude chose alone or what nobody settled. The code in `_system/apps/dashboard/` was changed the same day to match.

**Requirement.** Every page carries the same header and footer. The header leads to content. The footer holds formalities: the state of this view, the method behind the wiki and the technology of the dashboard.

**For.** Everyone who reads the dashboard, and workshop facilitators and participants who read it from a projected screen.

## Agreed

### Header

- The header links to Requirements, Architecture, Glossary, Decisions and Issues.
- The entry for the page the reader is on is marked.

### Footer

- The footer holds no link to wiki content. A link that the header has is not repeated.
- The footer shows when the data was last refreshed, as date and time without a time zone: "2026-11-11 10:02:08h".
- The footer shows how many clients are connected.
- The footer reads "Read-only dashboard for Systems42 LLM wiki". "LLM wiki" links to the help section that explains it.
- The footer links to the Metamodel page.
- The footer shows a two-colour Python logo with the word "Python" as the technology credit. It replaces the text "Python/Flask" and the flask glyph.
- The footer may hold further links that are not wiki content.

### Liveness

- A coloured dot in the footer shows that the page is connected to the dashboard server. The dot moves while the connection holds.
- When the connection is lost, the dot stops moving.

## Open

- Commons has no header entry. It is reachable from the home page only.

- On a lost connection the dot also turns grey and the client count gives way to the word "offline". Claude added both.
