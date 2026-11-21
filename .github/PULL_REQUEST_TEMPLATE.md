## Summary

- What changed and why:

## Parity checklist (Python and Go)

- [ ] Both implementations updated (`_system/apps/dashboard/app.py` and `_system/apps/dashboard/internal/`), or change is intentionally specific to one runtime (explain above).
- [ ] `./dashboard.sh test` passes.
- [ ] `go test -race ./...` passes in `_system/apps/dashboard/`.
- [ ] `tests/test_parity.py` passes with 0 parity failures.
- [ ] `CHANGELOG.md` updated for user-visible changes.
