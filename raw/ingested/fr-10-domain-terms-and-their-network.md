# Domain terms and their two views

Extracted on 2026-11-10 from the dashboard code and the goals. Rewritten by Claude on 2026-11-14 from a future perspective, after Gernot Starke asked to reflect the planned merge of glossary terms and data models (systems42-org/meta#36) in the dashboard. Nobody has agreed this requirement yet.

**Requirement.** A reader who meets a domain term finds its one meaning, what kind of term it is, and how it relates to other terms. The dashboard shows all domain terms in one section with two views of the same set: the terminology network and the entity diagram.

**Serves.** GOAL-003 Answers without asking a colleague.

**For.** Newcomers, domain experts, development teams, business analysts.

**Background.** Systems42 plans one type, Domain Term, for what are now glossary terms and data-model entities (meta#36). A term without a stereotype is a defined business concept, such as "review" in iSAQB atrium. Optional stereotypes such as `entity` or `value-object` mark terms that are modelled structurally, with optional attributes and typed relationships with multiplicities. Any terms may link to each other. Systems42 defines the type, the dashboard shows it (CON-004).

## Needs

1. **One list.** The section Domain Terms (C5) lists every domain term with name, definition, kind (none, entity, value object, …), status and number of links. It sorts and filters like every list, and also filters by kind.
2. **A term page.** Shows the definition, the kind and the aliases. A structured term also shows its attributes and its typed relationships with multiplicities. Its neighbours are one click away.
3. **Terminology network.** All terms of every kind and the links between them.
4. **Entity diagram.** Only the structured terms, with their attributes and typed relationships.
5. **Both views lead to the term.** Every node opens its term page, and every node is also reachable as a text link on the same page (QR-001).
6. **Definition in place.** On any page, hovering or focusing a link to a term shows its definition.
7. **Found by search.** Search finds a term by its name and its aliases (FR-003).

## Questions for you

1. Answered: GOAL-003.
2. Answered: one epic "Domain terms", Must, with four features: the term list (Must), the term page (Must), two views of the same terms (Should), definition in place (Should). Search needs no new page (FR-003).
3. Answered: yes, a bridge now. Glossary terms and data-model entities show as one set of domain terms before Systems42 has the new type: a glossary term counts as a term without kind, a data-model entity as `entity`. Once Systems42 has the type, the dashboard reads it directly and the bridge goes.
4. Answered: no move. The data model (the entity diagram over the structured terms) stays in Supporting Models (R4). Domain Terms (C5) holds the list, the term pages and the terminology network. The two views link to each other. Where a view sits is Systems42's framework, so this also goes to meta#36.
