# Workflow: Clarify

Resolve an open Issue with the human and update the affected requirements.

1. Read the Issue and every linked page, then summarize the unresolved choice
   and its consequences.
2. Ask the human for the decision. Do not choose a side or edit pages before
   the human answers.
3. Identify which requirement pages the answer changes. Before changing any FR
   with `delivery: implemented` or `partial`, warn that the implementation
   claim will be checked for drift and may become `outdated`.
4. Update the affected page(s), set `updated:` to today and link the decision
   rationale where appropriate. Do not automatically restore a prior delivery
   value after a typo or editorial correction. The human must review the diff
   and explicitly confirm that the meaning did not change.
5. Resolve the Issue (`resolved` or `wontfix`) only when the answer is applied.
   If the decision changes functional-requirement content, Inspect's
   `delivery.py` check marks any checked implementation `outdated`.
6. Append `## [YYYY-MM-DD] clarify | <issue title>` to `_system/log.md` and
   report the changed pages and remaining open questions.
