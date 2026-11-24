"""Import direction of the dashboard's modules (issue #185). No pytest.

`app.py` holds the Flask app and the routes. Every module below it is usable
without a web request, so it imports neither Flask nor `app`, and only the
sibling modules the table names. The projections are the package `project/`,
one row per module in it (`project.context`). The check reads the sources with
`ast` and imports nothing.

Run from the dashboard dir:
    .venv/bin/python tests/test_module_imports.py
"""
import ast
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent

# module below app.py -> what it may import besides the standard library.
# A new module gets a row here, in the Dockerfile and in pyproject.toml.
ALLOWED = {
    "inputs": {"yaml"},
    "metamodel": {"inputs", "yaml"},
    "catalog": {"metamodel"},
    "wiki": {"inputs", "metamodel", "catalog", "yaml"},
    "links": {"wiki"},
    "render": {"wiki", "links", "metamodel", "markdown", "nh3", "markupsafe"},
    "search": {"wiki", "links", "render", "catalog", "project.terms"},
    "project.architecture": {"wiki", "links", "render", "catalog", "project.common"},
    "project.common": {"wiki", "links", "metamodel"},
    "project.context": {"wiki", "links", "project.common"},
    "project.goals": {"wiki", "links", "render", "project.requirements"},
    "project.requirements": {"wiki", "links", "render", "project.common"},
    "project.terms": {"wiki", "links", "render", "catalog", "project.common"},
    "preflight": set(),
}
# These sit above the modules: the app itself and what starts it.
ABOVE = {"app", "cli", "gunicorn.conf"}
NEVER = {"flask", "app"}
# Package folders. A module in one is named with its package: `project.context`.
PACKAGES = {"project"}


def _source(module: str) -> Path:
    return HERE / (module.replace(".", "/") + ".py")


def _name(dotted: str) -> str:
    """`urllib.parse` is `urllib`, `project.context` stays `project.context`."""
    parts = dotted.split(".")
    return ".".join(parts[:2]) if parts[0] in PACKAGES else parts[0]


def _imports(module: str) -> set[str]:
    """The names a module imports, anywhere in its source: the top-level name,
    and for a module of a package the package and the module."""
    tree = ast.parse(_source(module).read_text(encoding="utf-8"))
    names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names |= {_name(a.name) for a in node.names}
        elif isinstance(node, ast.ImportFrom):
            assert node.level == 0, f"{module}.py: relative import"
            if node.module in PACKAGES:        # from project import context
                names |= {f"{node.module}.{a.name}" for a in node.names}
            else:
                names.add(_name(node.module))
    return names


def test_every_module_has_a_row():
    found = {p.name[:-len(".py")] for p in HERE.glob("*.py")}
    for package in PACKAGES:
        found |= {f"{package}.{p.name[:-len('.py')]}" for p in (HERE / package).glob("*.py")
                  if p.name != "__init__.py"}
    assert found == set(ALLOWED) | ABOVE, sorted(found ^ (set(ALLOWED) | ABOVE))


def test_a_package_itself_holds_no_code():
    """`project/__init__.py` is a docstring. Code there would run on the import
    of any of its modules, outside the table."""
    for package in PACKAGES:
        body = ast.parse((HERE / package / "__init__.py").read_text(encoding="utf-8")).body
        assert all(isinstance(st, ast.Expr) and isinstance(st.value, ast.Constant) for st in body), package


def test_no_module_below_app_imports_flask_or_app():
    for module in ALLOWED:
        hit = _imports(module) & NEVER
        assert not hit, f"{module}.py imports {sorted(hit)}"


def test_modules_import_only_what_the_table_allows():
    for module, allowed in ALLOWED.items():
        extra = _imports(module) - set(sys.stdlib_module_names) - {"__future__"} - allowed
        assert not extra, f"{module}.py imports {sorted(extra)}, allowed: {sorted(allowed)}"


def test_the_table_names_no_cycle():
    """A module may import only modules whose own rows do not lead back to it."""
    def reach(module: str, seen: tuple = ()) -> None:
        assert module not in seen, " -> ".join((*seen, module))
        for dep in ALLOWED.get(module, ()):
            reach(dep, (*seen, module))
    for module in ALLOWED:
        reach(module)


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
    print("ok")
