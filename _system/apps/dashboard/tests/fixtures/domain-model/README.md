# Order model fixture

Open this fixture to inspect the domain-term views. Its four pages are
illustrative test data.

From `_system/apps/dashboard/`, start with `uv` installed:

```sh
fixture_dir="$PWD/tests/fixtures/domain-model"
WIKI_DIR="$fixture_dir/wiki" \
WIKI_CONFIG="$fixture_dir/wiki.yaml" \
RAW_SOURCES_DIR="$fixture_dir/raw/sources" \
DOCS_DIR="$fixture_dir/docs" \
REPO_DIR="$fixture_dir" \
METAMODEL_DIR="$PWD/../../metamodel" \
uv run --with-requirements requirements.txt python app.py
```

The server listens on `http://localhost:8000`. Open a page within 90 seconds
to keep it running. Stop it with Ctrl+C. Settings go into a temporary file.

| Page | Expected result |
|---|---|
| `/domain-terms` | Four definitions, each linking to its own page. |
| `/graph/domain-terms` | Four terms, two structured relationships and one simple link. |
| `/graph/domain-terms?edges=related` | The link between Order and Review policy. |
| `/graph/domain-terms?edges=structured` | Customer places Order, and Order contains Order line. |
| `/entity-diagram` | Three entity classes with attribute names. Customer places `0..*` Orders. Order contains `1..*` Order lines, with a filled diamond at Order. |
| `/req42/models` | The same entity diagram within R4. |

The diagram currently displays multiplicity at the target end of each
relationship. Attribute multiplicities stay in the fixture frontmatter.
