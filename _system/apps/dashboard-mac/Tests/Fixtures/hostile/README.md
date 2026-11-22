# hostile fixture

A Systems42 derivative with broken pages, for `HostileVaultTests`. `_system/`
is a copy of `basic`, so the metamodel and anchors resolve. `sync-fixtures.sh`
refreshes only that copy and leaves `wiki/` alone.

`wiki/domain-terms/` holds unclosed, broken and list-shaped frontmatter, wrong
field types, no frontmatter, an empty file, an alias bomb, duplicate ids,
a page without id and status, and a markup title. `wiki/issues/` holds one
open and one resolved issue.

Git cannot hold these portably, so the tests create them in a temp copy:

- symlinks that point outside the wiki, loop, break or stay inside it
- a file with invalid UTF-8
- a file over 5 MB
- a folder named like a page (`x.md`)
- deeply nested frontmatter
