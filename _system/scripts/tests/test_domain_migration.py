"""Migration regressions exercised against a project with a GLO/DM pair."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import yaml


SCRIPTS = Path(__file__).resolve().parents[1]
SCRIPT = SCRIPTS / "migrate-domain-terms.py"
spec = importlib.util.spec_from_file_location("domain_migration", SCRIPT)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class DomainMigration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.term = self.write("wiki/glossary/GLO-001-money.md",
                               "---\nid: GLO-001\ntype: glossary-term\ntitle: Money\n"
                               "aliases: ['Currency, local']\n---\nDefinition.\n")
        self.model = self.write("wiki/data-models/DM-004-money.md",
                                "---\nid: DM-004\ntype: data-model\ntitle: Money\n"
                                "stereotype: value-object\n---\nModel prose.\n")
        self.index = self.write("_system/index.md",
                                "# Index\n\n## Data models\n\n- [[DM-004-money|Model]]\n\n"
                                "## Glossary\n\n- [[GLO-001-money|Money]] — Definition.\n")
        self.folder = self.root / "wiki/domain-terms"

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def command(self, *args):
        return subprocess.run([sys.executable, str(SCRIPT), *args, str(self.root)],
                              capture_output=True, text=True)

    def test_retry_keeps_allocated_id_and_protects_intervening_edits(self):
        replace = migration.replace_file

        def fail_at_index(path, data, mode):
            if path == self.index:
                raise PermissionError("index is read-only")
            replace(path, data, mode)

        with patch.object(migration, "replace_file", fail_at_index):
            with self.assertRaises(PermissionError):
                migration.migrate(self.root, [self.term, self.model], False, yaml)
        self.assertTrue(self.term.exists() and self.model.exists())
        self.assertEqual(self.command("--check").returncode, 1)
        original = self.index.read_bytes()
        self.index.write_text("edited during recovery", encoding="utf-8")
        self.assertIn("changed since migration", self.command().stderr)
        self.assertEqual(self.index.read_text(), "edited during recovery")
        self.index.write_bytes(original)
        self.assertEqual(self.command("--dry-run").returncode, 0)
        self.assertEqual(self.index.read_bytes(), original)
        self.assertEqual(self.command().returncode, 0)
        self.assertEqual(self.command("--check").returncode, 0)
        self.assertEqual([p.name for p in self.folder.glob("*.md")], ["DT-001-money.md"])
        self.assertIn("Model prose.", (self.folder / "DT-001-money.md").read_text())
        self.assertFalse(self.term.exists() or self.model.exists())

    def test_provenance_catalog_and_audit_after_merge(self):
        fields = [
            'ingested-pages: [\n  "[[GLO-001-money]]",\n  "[[DM-004-money]]"\n]',
            'ingested-pages:\n- "[[GLO-001-money]]"\n# keep this comment\n- "[[DM-004-money]]"',
        ]
        records = []
        for i, field in enumerate(fields):
            record = '---\n' + field + '\nrelated: ["[[DM-004-money]]"]\n---\nHistory: [[DM-004-money]]\n'
            path = self.write(f"raw/sources/SRC-00{i}.md", record)
            records.append((path, record.replace(field, field.replace("GLO-001-money", "DT-001-money")
                                                             .replace("DM-004-money", "DT-001-money"))))
        self.write("wiki/building-blocks/BB-001-currency.md",
                   "---\nid: BB-001\ntitle: 'Currency, local'\ntype: building-block\n---\n")
        result = self.command()
        self.assertEqual(result.returncode, 0, result.stderr)
        for path, expected in records:
            self.assertEqual(path.read_text(), expected)
        self.assertEqual(self.index.read_text().count("DT-001-money"), 1)
        self.assertIn("[[DT-001-money|Money]] — Definition.", self.index.read_text())
        audit = subprocess.run([sys.executable, str(SCRIPTS / "concept-cluster-audit.py")],
                               cwd=self.root, capture_output=True, text=True, check=True)
        self.assertIn("1 MULTI-LENS CONCEPTS", audit.stdout)

    def test_conflicting_source_of_truth_stops_before_writes(self):
        self.model.write_text(self.model.read_text().replace("stereotype: value-object",
                              "stereotype: value-object\nsource-of-truth: Accounting"))
        for paired in (True, False):
            if not paired:
                self.term.unlink()
            for args in (("--dry-run",), ()):
                result = self.command(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("DM-004-money.md", result.stderr)
                self.assertIn("Accounting", result.stderr)
                self.assertTrue(self.model.exists())
                self.assertFalse(self.folder.exists())


if __name__ == "__main__":
    unittest.main()
