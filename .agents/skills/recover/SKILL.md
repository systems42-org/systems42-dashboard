---
name: recover
description: >
  Recover the abstractions of existing code (alias: archeology, archaeology)
  into a report for Capture: top-down to a limited depth, every finding an
  abstraction with an evidence label, at least one check per constraint
  touched, cited requirement IDs resolved, and a closing round that asks one
  gap at a time, openly where only the human knows the answer, with the
  answers recorded in the report. Writes no wiki pages. Use when the user asks to
  recover, dig into or run archeology on existing code, to derive requirements
  or architecture from code, or to see what a codebase implies for the
  specification.
argument-hint: "<repository or path> [deeper: <feature or building block>]"
---

# Recover requirements and architecture from code

Run `_system/workflows/recover.md` in full for one scope.

1. Take the scope the human names: a repository, or a path in one. Note the
   one feature or building block they want one level deeper, if any. Ask for
   the scope only if they named none.
2. Read what the wiki already holds for the scope before reading the code.
3. Work top-down to the depth limit. Write abstractions, never copies of code
   or comments; code names appear only as evidence.
4. Write the report to the `raw/` inbox, then ask its gaps **one at a
   time**: open questions for intent, with links to existing pages that may apply and candidates only where they fit well; options only for choices. Record each
   answer in the report before asking the next gap.
5. Write no wiki pages. Hand the report to Capture when the human says so.
