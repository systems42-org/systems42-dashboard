# Install the app with Homebrew

Raised by Gernot Starke on 2026-11-22. Not yet captured into `wiki/`.

**Requirement.** A macOS user installs, updates and removes the dashboard app with Homebrew.

**For.** People who run the dashboard app on macOS.

## Needed

- `brew install --cask systems42-org/tap/systems42-dashboard` installs the newest release of the app.
- `brew upgrade` brings the app to the newest release. `brew uninstall --cask systems42-dashboard` removes it.
- Homebrew checks the download against the checksum of the release.
- Every release updates the cask without a manual step.
- The install guide names the Homebrew commands.

## State on 2026-11-22

The repository holds a cask file (`_system/apps/dashboard/macos/Casks/systems42-dashboard.rb`), but no tap exists, so nobody can install with Homebrew. The cask skips the checksum (`sha256 :no_check`) and still names release 0.13.0.

## Open

- The app is ad-hoc signed and not notarised with Apple. After a Homebrew install macOS may still refuse to open it.
- Where the tap lives: a new repository `systems42-org/homebrew-tap` is the usual form.
