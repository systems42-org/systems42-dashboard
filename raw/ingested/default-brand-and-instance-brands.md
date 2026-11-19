# Default brand and instance brands

Draft note, 2026-11-19. Written by Claude at Gernot Starke's request, for him to check before capture.

## What Gernot Starke said (chat, 2026-11-19)

- Every wiki can have its own animation, logo and brand.
- The dashboard ships a default.
- Any specific Systems42 instance, like atrium or meta, may replace the default with its own.
- Atrium and meta have their own logos and animations already, and these are kept.

## What the wiki already says

- FR-031: `brand:` names the shipped brand or a folder in the wiki's repository. Without it, the dashboard shows its default brand.
- FR-032: the dashboard ships one brand, the Peaks mark and its intro. The atrium brand lives in isaqb-atrium.

So the rule itself is covered.

## What the wiki does not say yet

1. The look of one instance never changes the shipped default. Release 0.11.3 broke this: meta's intro (the systems42 logo and a fly-in wordmark) replaced the default intro, and this repository lost its Peaks intro. Proposed as one more line in FR-032.
2. Meta is the second instance with its own brand, beside atrium. Its brand folder is meta pull request #46. FR-032 names only atrium.
3. FR-031 still says "Brand files are trusted content" and "reviewed like code". Since release 0.11.1 an intro runs in a sandboxed frame without the dashboard's rights (issue #34). The line is out of date.

## Open question

- Projects created from meta get no brand folder, so they show the default (Peaks). Is that wanted, or should a new project start with meta's brand?
