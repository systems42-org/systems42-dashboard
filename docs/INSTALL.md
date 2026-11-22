# Install, start and update the dashboard

The Systems42 dashboard shows a Systems42 wiki in the browser, read-only. It comes in three forms. Pick one, they all show the same pages.

| Form | You need | Runs on | Take it when |
|------|----------|---------|--------------|
| **Docker** | Docker | Linux, macOS | you have Docker anyway |
| **uv** | [uv](https://docs.astral.sh/uv/) | Linux, macOS | Docker cannot run, for example in a virtual machine |
| **App** | nothing | macOS 14 or later, Linux, Windows | you want no terminal, no Docker and no Python |

The app is supported on macOS. The programs for Linux and Windows come without support.

Docker and uv start through the launcher script `dashboard.sh` and run exactly the release your wiki names. The app is installed once per machine and opens every wiki.

The uv form and the app exist from release 0.13.0 on. All downloads are on <https://dashboard.systems42.org/downloads/>.

## Before you start

The dashboard opens a Systems42 wiki only. That is a folder with `wiki/`, `raw/`, `_system/wiki.yaml`, `_system/metamodel/` and `_system/anchors/`. It refuses any other folder and names what is missing.

The dashboard never changes your wiki. After the first start it needs no network.

## Docker

### Install

1. Install [Docker](https://docs.docker.com/get-docker/) and start it.
2. In a terminal, go to the folder of your wiki.
3. Get the launcher, unless your wiki already has a `dashboard.sh`.
4. Name the newest release in your wiki.

Steps 3 and 4 as commands:

```sh
curl -fsSLO https://dashboard.systems42.org/downloads/dashboard.sh
chmod +x dashboard.sh
./dashboard.sh update
```

The last command writes one line to `_system/wiki.yaml`, for example `dashboard_version: "0.13.0"`. Commit that file, so that everybody on the team runs the same release.

### Start and stop

```sh
./dashboard.sh         # start, the browser opens at http://localhost:8080
./dashboard.sh down    # stop
```

The first start fetches the release, which takes a minute. Later starts take seconds.

### Update

```sh
./dashboard.sh update  # name the newest release in _system/wiki.yaml
./dashboard.sh         # start it
```

Commit `_system/wiki.yaml` again. To go back to an older release, set `dashboard_version:` to its number by hand and start again.

### Remove

`./dashboard.sh down` stops and removes the container. The fetched release stays on the machine for other wikis. Remove it with `docker rmi ghcr.io/systems42-org/dashboard:<release>`.

## uv

### Install

1. Install uv, see <https://docs.astral.sh/uv/getting-started/installation/>. You do not need to install Python: uv fetches it.
2. Get the launcher and name a release, as in steps 2 to 4 for Docker. The release must be 0.13.0 or newer.

### Start and stop

```sh
./dashboard.sh uv      # start, the browser opens at http://localhost:8080
```

The dashboard runs in this terminal. Stop it with Ctrl+C. It also stops by itself when you close its last browser tab.

The first start of a release needs network, because uv fetches Python 3.12, the dashboard and its libraries. Later starts work offline.

### Update

```sh
./dashboard.sh update  # name the newest release in _system/wiki.yaml
./dashboard.sh uv      # start it, the first time with network
```

### Remove

Nothing is installed in your wiki. uv keeps what it fetched in its cache. `uv cache clean` empties it.

## App

### Install on macOS

1. Download `Systems42-Dashboard-<release>-universal.dmg` from the downloads page. It runs on Apple Silicon and Intel, macOS 14 or later.
2. Open the file and drag **Systems42 Dashboard** to **Applications**.
3. Open the app. macOS may refuse the first time, because the app is ad-hoc signed and not notarised with Apple. In that case open **System Settings → Privacy & Security**, scroll to the message about Systems42 Dashboard and choose **Open Anyway**. From a terminal you can clear the browser quarantine flag directly instead, or download with `curl` (which does not set it):

```sh
# Clear the quarantine flag once after dragging to Applications
xattr -dr com.apple.quarantine "/Applications/Systems42 Dashboard.app"

# Or download without a browser quarantine flag
curl -fsSLO https://github.com/systems42-org/systems42-dashboard/releases/download/v<release>/Systems42-Dashboard-<release>-universal.dmg
```

### Start and stop on macOS

1. Open **Systems42 Dashboard**. Its icon appears in the menu bar.
2. Choose your wiki folder from the menu, or drag the folder onto the app. The wiki opens in your browser.
3. The app remembers the wikis you opened. Each open wiki gets its own address.
4. A wiki's dashboard stops when you close its last browser tab. Quit the app from its menu.

### Install and start on Linux and Windows

1. Download the file for your system from the downloads page: `systems42-dashboard-<release>-linux-amd64.tar.gz`, `…-linux-arm64.tar.gz` or `…-windows-amd64.zip`.
2. Unpack it. It holds one program, `systems42-dashboard` (`systems42-dashboard.exe` on Windows).
3. Start it with the folder of your wiki, as shown below.

```sh
./systems42-dashboard --open /path/to/your-wiki
```

The browser opens at `http://localhost:8080`. Stop with Ctrl+C, or close the last browser tab.

### Update

Download the newest file and replace the old one. On macOS, drag the new app to **Applications** and confirm that it replaces the old one.

The app does not follow `dashboard_version:` in your wiki. When a wiki names another release than the app, the app shows the wiki anyway and says so in the footer of every page.

### Remove

On macOS, move the app to the Trash. Its list of recent wikis is in `~/Library/Application Support/Systems42 Dashboard/`. On Linux and Windows, delete the program.

## Check the release you run

The footer of every dashboard page shows the release. From a terminal:

```sh
grep dashboard_version _system/wiki.yaml   # the release your wiki names
./systems42-dashboard --version            # the release of the app
```

## When something does not work

| What you see | What to do |
|--------------|------------|
| "This is not a Systems42 wiki" | Start the launcher in the folder that holds `_system/wiki.yaml`. |
| "names no dashboard release" | Run `./dashboard.sh update`. |
| "Docker is not installed or not on PATH" | Start Docker, or use uv or the app. |
| "Port 8080 is already in use" | Another dashboard is running. Stop it, or choose a port: `DASH_PORT=8081 ./dashboard.sh`, or `--port 8081` for the app. |
| "uv could not fetch dashboard" | The first start of a release needs network. Releases before 0.13.0 have no uv form: run `./dashboard.sh update`. |
| A phone in the room cannot open the QR code's address | Phone and computer must be in the same network. Set the address yourself: `DASH_PUBLIC_URL=http://<your-address>:8080 ./dashboard.sh`. |
