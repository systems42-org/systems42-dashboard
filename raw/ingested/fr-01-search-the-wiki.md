# Search the wiki

Extracted on 2026-11-10 from the dashboard code (`_system/apps/dashboard/`) and the goals. "Today" describes what the code does. "Gaps" come from `raw/ingested/goals2.md` and were not rechecked. Nobody has agreed this requirement yet.

**Requirement.** A reader finds a page by its ID, its title or any word in its text, from every page of the dashboard.

**Serves.** GOAL-003 Answers without asking a colleague.

**For.** Development teams, newcomers, workshop participants, domain experts.

## Today

- Every page has a search box in the top bar. Cmd K (Ctrl K elsewhere) puts the cursor in it.
- While the reader types, a popup lists the best hits (`static/search-popup.js`, `/search.json`). Submitting opens `/search` with all hits.
- The index holds ID, title, aliases and body text of every wiki page (`build_search_records()` in `app.py`).
- A page is a hit only if it contains every word of the query.
- Hits are ranked by where the query matched: title first, then ID, then page type, then body text (`static/search-rank.js`).
- Pages of sections hidden in Configure stay in the search results.

## Gaps

- No tolerance for typing errors or word forms.
- Tags and frontmatter fields are not searched.
