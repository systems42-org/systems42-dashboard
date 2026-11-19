# Run a shared session in a workshop

Extracted on 2026-11-10 from the dashboard code (`_system/apps/dashboard/`) and the goals. "Today" describes what the code does. "Gaps" come from `raw/ingested/goals2.md` and were not rechecked. Nobody has agreed this requirement yet.

**Requirement.** A group opens the same dashboard on their own devices, and one person decides what the group sees.

**Serves.** GOAL-002 Show what Systems42 can do.

**For.** Workshop facilitators, workshop participants, the Keyholder, people presenting Systems42.

## Today

- The home page shows a QR code and its address. `/join` shows the code full size for projecting.
- The footer shows how many browser tabs are connected. `/who` lists them under generated nicknames, never real names.
- The first tab to connect is the Keyholder ("Yoda" in the code). If that tab closes, the role passes once to the tab with the next-earliest connection.
- Configure lets everyone see which areas and sections are shown. Only the Keyholder saves. Hidden sections leave the home page, the area pages and the top bar but stay reachable by address and search.
- Only the Keyholder sees "Disconnect all", which ends the session for everyone.
- "Reload" reads the wiki from disk again.
- The dashboard stops itself a few seconds after the last tab closes.

## Gaps

- Who holds the keys when several people work in parallel is open, see ISS-001.
- Whether workshops are a reason the dashboard exists is not decided. The vision has no sentence on them.
