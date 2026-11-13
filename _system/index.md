# Index

Content catalog, one line per page, grouped by type. The agent updates this on
every capture (`_system/workflows/capture.md`, step 7).

## Glossary

## Goals

- [[GOAL-001-trusted-answers]] Trusted answers about requirements and architecture (vision, accepted)
- [[GOAL-002-show-what-systems42-can-do]] Show what Systems42 can do (objective, accepted)
- [[GOAL-003-answers-without-asking-a-colleague]] Answers without asking a colleague (objective, accepted)
- [[GOAL-004-requirements-with-reasons-and-checks]] Requirements with their reasons and their checks (objective, draft)
- [[GOAL-005-architecture-traced-to-requirements]] Architecture and decisions traced to requirements (objective, draft)
- [[GOAL-006-source-and-status-on-every-statement]] Source and status on every statement (objective, draft)
- [[GOAL-007-readers-who-come-back]] Readers who come back (objective, draft)
- [[GOAL-008-one-way-into-every-systems42-wiki]] One way into every Systems42 wiki (objective, draft)

## Stakeholders

- [[STK-001-product-owners]] Product owners (draft)
- [[STK-002-business-analysts]] Business analysts (draft)
- [[STK-003-requirements-engineers]] Requirements engineers (draft)
- [[STK-004-development-teams]] Development teams (draft)
- [[STK-005-testers]] Testers (draft)
- [[STK-006-ai-agents]] AI agents, hidden from the context diagram (draft)
- [[STK-007-workshop-facilitators]] Workshop facilitators (draft)
- [[STK-008-workshop-participants]] Workshop participants (draft)
- [[STK-009-software-architects]] Software architects (draft)
- [[STK-010-people-who-run-the-dashboard]] People who run the dashboard (draft)
- [[STK-011-people-who-set-up-a-project-wiki]] People who set up a new project wiki (draft)
- [[STK-012-maintainers]] Maintainers of the dashboard and the Systems42 method (draft)
- [[STK-013-people-learning-or-presenting-systems42]] People learning or presenting Systems42 (draft)
- [[STK-014-domain-experts]] Domain experts (draft)
- [[STK-015-newcomers]] Newcomers to a project (draft)
- [[STK-016-ux-designers]] UX designers, an assumption (draft)
- [[STK-017-operations-staff]] Operations and infrastructure staff, an assumption (draft)
- [[STK-018-owners-of-neighbouring-systems]] Owners of neighbouring systems, an assumption (draft)
- [[STK-019-auditors-and-quality-assurance]] Auditors and quality assurance (draft)
- [[STK-020-data-protection-and-security-officers]] Data protection and security officers (draft)
- [[STK-021-builders-of-project-specific-dashboards]] Builders of project-specific dashboards, an assumption (draft)
- [[STK-022-prospective-adopters]] Prospective adopters of Systems42, an assumption (draft)
- [[STK-023-keyholder]] Keyholder, the person who started the dashboard app (draft)

## Context

## External interfaces

## Data models

## Activity models

## Use cases

## Functional requirements

- [[FR-001-search-the-wiki]] Search the wiki (epic, Must, draft)
- [[FR-002-typos-and-word-forms]] Typos and word forms (feature, Must, draft)
- [[FR-003-related-words-from-aliases-and-glossary]] Related words from aliases and the glossary (feature, Must, draft)
- [[FR-004-question-style-queries]] Question-style queries (feature, Must, draft)
- [[FR-005-reason-for-every-non-exact-hit]] Reason for every non-exact hit (feature, Must, draft)
- [[FR-006-tags-and-fields-are-searched]] Tags and fields are searched (feature, Should, draft)
- [[FR-007-highlighted-passage-on-the-results-page]] Highlighted passage on the results page (feature, Should, draft)
- [[FR-008-related-pages-group]] Related pages group (feature, Should, draft)
- [[FR-009-more-filters-on-the-full-results-page]] More filters on the full results page (feature, Could, draft)
- [[FR-010-show-the-method]] Show the method (epic, Should, draft)
- [[FR-011-explain-the-three-loops]] Explain the three loops (feature, Should, draft)
- [[FR-012-guided-path-through-the-wiki]] Guided path through the wiki (feature, Should, draft)
- [[FR-013-header-and-footer-on-every-page]] Header and footer on every page (feature, Must, draft)
- [[FR-014-reach-the-main-content-from-the-header]] Reach the main content from the header (story, Must, draft)
- [[FR-015-read-the-formalities-in-the-footer]] Read the formalities in the footer (story, Should, draft)
- [[FR-016-see-whether-the-page-is-still-connected]] See whether the page is still connected (story, Should, draft)
- [[FR-017-browse-by-area-and-section]] Browse by area and section (epic, Must, draft)
- [[FR-018-orientation-on-the-first-page]] Orientation on the first page (feature, Must, draft)
- [[FR-019-section-at-a-glance]] Section at a glance (feature, Must, draft)
- [[FR-020-know-where-you-are]] Know where you are (feature, Must, draft)
- [[FR-021-sort-lists]] Sort lists (feature, Must, draft)
- [[FR-022-lists-keep-sort-and-filter-in-their-address]] Lists keep sort and filter in their address (feature, Should, draft)
- [[FR-023-areas-and-sections-follow-the-tailoring]] Areas and sections follow the tailoring (feature, Should, draft)
- [[FR-024-see-what-is-still-open]] See what is still open (epic, Must, draft)
- [[FR-025-issue-list-with-filters]] Issue list with filters (feature, Must, draft)
- [[FR-026-issues-carry-a-category]] Issues carry a category (feature, Should, draft)
- [[FR-027-issues-on-the-page-they-affect]] Issues on the page they affect (feature, Must, draft)
- [[FR-028-who-answers-an-issue]] Who answers an issue (feature, Should, draft)
- [[FR-029-the-dashboard-as-a-product]] The dashboard as a product (epic, Should, draft)
- [[FR-030-numbered-releases]] Numbered releases (feature, Should, draft)
- [[FR-031-branding-is-configuration]] Branding is configuration (feature, Must, draft)
- [[FR-032-example-brands-to-try]] Example brands to try (feature, Should, draft)
- [[FR-033-runnable-dashboard-in-the-starter-kit]] Runnable dashboard in the starter kit (feature, Should, draft)

## Quality requirements

- [[QR-001-usable-on-phone-and-tablet]] Usable on phone and tablet (usable, flexible, should, draft)
- [[QR-002-runs-alike-on-linux-and-macos]] Runs alike on Linux and macOS (flexible, operable, should, draft)

## Constraints

- [[CON-001-proof-of-concept-not-production-ready]] The dashboard is a proof of concept, not production-ready for every environment (draft)
- [[CON-002-dashboard-never-writes-to-the-wiki]] The dashboard never writes to the wiki (draft)
- [[CON-003-docker-is-the-supported-way-to-run-it]] Docker is the supported way to run the dashboard (draft)

## Decisions

- [[DR-001-english-brief-plain-writing]] Write all documentation in brief, plain English (accepted)
- [[DR-002-tailoring-belongs-to-systems42-the-view-to-the-dashboard]] Tailoring belongs to Systems42, the view belongs to the dashboard (accepted)
- [[DR-003-quality-requirements-are-classified-by-q42-dimensions]] Quality requirements are classified by Q42 dimensions (accepted)

## Issues

- [[ISS-001-who-holds-the-keys-in-parallel-work]] Who holds the keys when two people work in parallel (open)
- [[ISS-002-define-the-clarify-loop]] Define the clarify loop (open)

## Sources

- [[SRC-001-stakeholders-of-the-systems42-dashboard]] Stakeholders of the Systems42 dashboard (document)
- [[SRC-002-grilling-session-on-stakeholders]] Grilling session on stakeholders (interview)
- [[SRC-003-vision-of-the-systems42-dashboard]] Vision of the Systems42 dashboard (interview)
- [[SRC-004-goals-of-the-systems42-dashboard]] Goals of the Systems42 dashboard (document)
- [[SRC-005-search-the-wiki]] Search the wiki (document)
- [[SRC-006-grilling-session-on-search]] Grilling session on search (interview)
- [[SRC-007-show-the-method]] Show the method (document)
- [[SRC-008-grilling-session-on-showing-the-method]] Grilling session on showing the method (interview)
- [[SRC-009-guided-path-through-the-wiki]] Guided path through the wiki (document)
- [[SRC-010-header-and-footer-on-every-page]] Header and footer on every page (document)
- [[SRC-011-grilling-session-on-header-and-footer]] Grilling session on header and footer (interview)
- [[SRC-012-conversation-on-tailoring-and-the-view]] Conversation on tailoring and the view (interview)
- [[SRC-013-browse-by-area-and-section]] Browse by area and section (document)
- [[SRC-014-grilling-session-on-browsing]] Grilling session on browsing (interview)
- [[SRC-015-see-what-is-still-open]] See what is still open (document)
- [[SRC-016-grilling-session-on-open-issues]] Grilling session on open issues (interview)
- [[SRC-017-usable-on-phone-and-tablet]] Usable on phone and tablet (document)
- [[SRC-018-grilling-session-on-phone-and-tablet]] Grilling session on phone and tablet (interview)
- [[SRC-019-the-dashboard-as-a-product]] The dashboard as a product (document)
- [[SRC-020-grilling-session-on-the-dashboard-as-a-product]] Grilling session on the dashboard as a product (interview)
