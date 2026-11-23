# tailored fixture

A Systems42 derivative whose metamodel is tailored: section C6 is renamed to
"Open Points", and section A6 "Risks and Technical Debt" (type `risk`, folder
`wiki/risks/`) is added. Everything else is a copy of `basic`.

`sync-fixtures.sh` leaves this fixture alone, because refreshing its
`_system/` would undo the tailoring.
