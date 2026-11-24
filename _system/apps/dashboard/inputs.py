"""Read text and YAML from files the dashboard does not write (issue #176).

Wiki pages, wiki.yaml and the metamodel are edited by hand and by agents.
Every request reads them, so an exception from one file is an error on every
route. The two readers here raise nothing but OSError, and they log what they
had to work around: the file and the problem, once per file until the problem
changes or goes away.

No Flask import here: metamodel.py uses this too.
"""
from __future__ import annotations

import logging
import threading
from pathlib import Path

import yaml

log = logging.getLogger("systems42.inputs")

# What PyYAML's constructors raise on a value that matches a type's pattern or
# tag but is not a value of that type: `2026-13-01`, `!!int abc`, `!!bool x`.
# RecursionError: nesting deeper than the interpreter's stack.
_CONSTRUCTOR_ERRORS = (ValueError, TypeError, KeyError, AttributeError,
                       OverflowError, RecursionError)

_LOCK = threading.Lock()
# path -> {aspect: the problem last logged for it}
_LOGGED: dict[Path, dict[str, str]] = {}


def _report(path: Path, aspect: str, problem: str | None) -> None:
    """Log `problem` for one aspect of `path` (its encoding, its YAML) unless
    it is the one logged last. None means that aspect is fine now."""
    with _LOCK:
        seen = _LOGGED.setdefault(path, {})
        if problem is None:
            seen.pop(aspect, None)
            if not seen:
                del _LOGGED[path]
            return
        if seen.get(aspect) == problem:
            return
        seen[aspect] = problem
    log.warning("%s: %s", path, problem)


def read_text(path: Path, *, replace: bool = False) -> str | None:
    """The file's text. Bytes that are not UTF-8 are logged. Then, with
    `replace`, they come back as U+FFFD, and without it the result is None:
    the caller treats the file as unreadable. OSError is the caller's."""
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as e:
        _report(path, "encoding", f"not valid UTF-8 at byte {e.start}, "
                + ("shown with replacement characters" if replace else "file ignored"))
        return path.read_text(encoding="utf-8", errors="replace") if replace else None
    _report(path, "encoding", None)
    return text


class _Loader(yaml.SafeLoader):
    """SafeLoader that keeps an impossible date as the text that was written,
    so one bad `created:` does not cost the page its other fields. The Go
    dashboard's YAML reader does the same."""

    def __init__(self, stream):
        super().__init__(stream)
        self.problems: list[str] = []

    def construct_yaml_timestamp(self, node):
        try:
            return super().construct_yaml_timestamp(node)
        except (ValueError, OverflowError) as e:   # month 13, day 30 of February, hour 25
            self.problems.append(f"{node.value!r} is not a valid date ({e}), kept as text")
            return self.construct_scalar(node)


_Loader.add_constructor("tag:yaml.org,2002:timestamp", _Loader.construct_yaml_timestamp)


def load_yaml(path: Path, text: str):
    """`text` (from `path`, named in the log) as YAML, or None when it cannot
    be read as YAML at all. An empty document is None as well."""
    loader = _Loader(text)
    try:
        data = loader.get_single_data()
    except yaml.YAMLError as e:
        _report(path, "yaml", "malformed YAML, fields ignored: " + " ".join(str(e).split()))
        return None
    except _CONSTRUCTOR_ERRORS as e:
        _report(path, "yaml", f"invalid YAML value, fields ignored: {type(e).__name__}: {e}")
        return None
    finally:
        loader.dispose()
    _report(path, "yaml", "; ".join(loader.problems) or None)
    return data
