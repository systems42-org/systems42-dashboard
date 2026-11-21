import Cocoa
import Foundation

// MARK: - Models

struct CheckReply: Decodable {
    let ok: Bool
    let repo_dir: String?
    let system_name: String?
    let dashboard_version: String?
    let own_version: String?
    let missing: [String]?
    let message: String?
}

struct ReadyReply: Decodable {
    let url: String
    let public_url: String
    let port: Int
    let repo_dir: String
    let system_name: String
    let dashboard_version: String
    let own_version: String
}

struct RecentEntry: Codable, Equatable {
    let path: String
    let name: String
    let lastOpened: Date
}

struct RecentFile: Codable {
    var recent: [RecentEntry]
}

final class RunningWiki {
    let canonicalPath: String
    let systemName: String
    let localURL: URL
    let publicURL: String
    let port: Int
    let process: Process

    init(canonicalPath: String, systemName: String, localURL: URL, publicURL: String, port: Int, process: Process) {
        self.canonicalPath = canonicalPath
        self.systemName = systemName
        self.localURL = localURL
        self.publicURL = publicURL
        self.port = port
        self.process = process
    }
}

// MARK: - Recent Wikis Store (~/Library/Application Support/Systems42 Dashboard/recent.json)

final class RecentStore {
    private let maxEntries = 10
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Systems42 Dashboard", isDirectory: true)
        self.fileURL = dir.appendingPathComponent("recent.json")
    }

    func load() -> [RecentEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let parsed = try? decoder.decode(RecentFile.self, from: data) {
            return parsed.recent
        }
        return []
    }

    func record(path: String, name: String) {
        var list = load().filter { $0.path != path }
        list.insert(RecentEntry(path: path, name: name, lastOpened: Date()), at: 0)
        if list.count > maxEntries {
            list = Array(list.prefix(maxEntries))
        }
        save(list)
    }

    func clear() {
        save([])
    }

    private func save(_ entries: [RecentEntry]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(RecentFile(recent: entries)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recentStore = RecentStore()
    private var running: [String: RunningWiki] = [:]
    private var launchedWithFiles = false
    private var initialPromptDone = false

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    private var helperURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/systems42-dashboard")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        rebuildMenu()

        // Allow Finder/open -a URLs delivered right after launch to run first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self, !self.initialPromptDone else { return }
            self.initialPromptDone = true
            if !self.launchedWithFiles && self.running.isEmpty {
                self.chooseWikiFolder()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        launchedWithFiles = true
        initialPromptDone = true
        for url in urls {
            if url.isFileURL {
                openWiki(at: url.path)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if running.isEmpty {
            chooseWikiFolder()
        } else {
            statusItem.button?.performClick(nil)
        }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopAllServers()
    }

    // MARK: - Menu Bar UI

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let iconURL = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
               let img = NSImage(contentsOf: iconURL) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                button.image = img
                button.imagePosition = .imageOnly
            } else {
                button.title = "S42"
            }
            button.toolTip = "Systems42 Dashboard"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let active = running.values.sorted { $0.systemName.localizedCaseInsensitiveCompare($1.systemName) == .orderedAscending }
        if active.isEmpty {
            let emptyItem = NSMenuItem(title: "No wikis running", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            let header = NSMenuItem(title: "Running Wikis", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for item in active {
                let row = NSMenuItem(title: "\(item.systemName)  (:\(item.port))", action: nil, keyEquivalent: "")
                let sub = NSMenu()

                let openBrowser = NSMenuItem(title: "Open in Browser", action: #selector(menuOpenRunning(_:)), keyEquivalent: "")
                openBrowser.target = self
                openBrowser.representedObject = item.canonicalPath
                sub.addItem(openBrowser)

                let copyLocal = NSMenuItem(title: "Copy URL (\(item.localURL.absoluteString))", action: #selector(menuCopyText(_:)), keyEquivalent: "")
                copyLocal.target = self
                copyLocal.representedObject = item.localURL.absoluteString
                sub.addItem(copyLocal)

                if item.publicURL != item.localURL.absoluteString {
                    let copyWorkshop = NSMenuItem(title: "Copy Workshop URL (\(item.publicURL))", action: #selector(menuCopyText(_:)), keyEquivalent: "")
                    copyWorkshop.target = self
                    copyWorkshop.representedObject = item.publicURL
                    sub.addItem(copyWorkshop)
                }

                sub.addItem(NSMenuItem.separator())

                let stopItem = NSMenuItem(title: "Stop", action: #selector(menuStopRunning(_:)), keyEquivalent: "")
                stopItem.target = self
                stopItem.representedObject = item.canonicalPath
                sub.addItem(stopItem)

                row.submenu = sub
                menu.addItem(row)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let openItem = NSMenuItem(title: "Open Wiki Folder…", action: #selector(menuChooseWiki(_:)), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)

        let recentItem = NSMenuItem(title: "Recent Wikis", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        let entries = recentStore.load()
        if entries.isEmpty {
            let none = NSMenuItem(title: "No recent wikis", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentMenu.addItem(none)
        } else {
            for entry in entries {
                let title = "\(entry.name) — \(abbreviatePath(entry.path))"
                let mi = NSMenuItem(title: title, action: #selector(menuOpenRecent(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = entry.path
                mi.isEnabled = FileManager.default.fileExists(atPath: entry.path)
                recentMenu.addItem(mi)
            }
            recentMenu.addItem(NSMenuItem.separator())
            let clearItem = NSMenuItem(title: "Clear Recent", action: #selector(menuClearRecent(_:)), keyEquivalent: "")
            clearItem.target = self
            recentMenu.addItem(clearItem)
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        menu.addItem(NSMenuItem.separator())

        let versionItem = NSMenuItem(title: "Systems42 Dashboard \(appVersion)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(title: "Quit Systems42 Dashboard", action: #selector(menuQuit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        if let button = statusItem.button {
            button.toolTip = active.isEmpty
                ? "Systems42 Dashboard"
                : "Systems42 Dashboard — \(active.count) running"
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Actions

    @objc private func menuChooseWiki(_ sender: Any?) {
        chooseWikiFolder()
    }

    @objc private func menuOpenRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        openWiki(at: path)
    }

    @objc private func menuClearRecent(_ sender: Any?) {
        recentStore.clear()
        rebuildMenu()
    }

    @objc private func menuOpenRunning(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let wiki = running[key] else { return }
        NSWorkspace.shared.open(wiki.localURL)
    }

    @objc private func menuCopyText(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func menuStopRunning(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
              let wiki = running[key] else { return }
        if wiki.process.isRunning {
            wiki.process.terminate()
        }
    }

    @objc private func menuQuit(_ sender: Any?) {
        stopAllServers()
        NSApplication.shared.terminate(nil)
    }

    private func chooseWikiFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Open a Systems42 Wiki"
        panel.message = "Choose a Systems42 repository folder (holding wiki/, raw/, _system/wiki.yaml)."
        panel.prompt = "Open Wiki"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            openWiki(at: url.path)
        }
    }

    // MARK: - Launching & Lifecycle

    private func openWiki(at rawPath: String) {
        let canonical = URL(fileURLWithPath: rawPath).standardizedFileURL.resolvingSymlinksInPath().path

        if let existing = running[canonical] {
            NSWorkspace.shared.open(existing.localURL)
            return
        }

        let helper = helperURL
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            showAlert(
                title: "Dashboard binary missing",
                body: "Expected bundled server at:\n\(helper.path)"
            )
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // 1. Validate Systems42 layout via CON-005 preflight (`--check`).
            let checkProc = Process()
            checkProc.executableURL = helper
            checkProc.arguments = ["--check", canonical]
            let checkOut = Pipe()
            let checkErr = Pipe()
            checkProc.standardOutput = checkOut
            checkProc.standardError = checkErr
            do {
                try checkProc.run()
                checkProc.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: "Could not start preflight", body: error.localizedDescription)
                }
                return
            }

            let outData = checkOut.fileHandleForReading.readDataToEndOfFile()
            if checkProc.terminationStatus != 0 {
                let msg: String
                if let reply = try? JSONDecoder().decode(CheckReply.self, from: outData),
                   let m = reply.message, !m.isEmpty {
                    msg = m
                } else {
                    let errData = checkErr.fileHandleForReading.readDataToEndOfFile()
                    msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                        ?? "This folder is not a Systems42 wiki."
                }
                DispatchQueue.main.async {
                    self.showAlert(title: "Not a Systems42 wiki", body: msg)
                }
                return
            }

            // 2. Spawn server on a free port (`--port 0 --ready-json`).
            let proc = Process()
            proc.executableURL = helper
            proc.arguments = ["--port", "0", "--ready-json", canonical]
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            proc.standardOutput = stdoutPipe
            proc.standardError = stderrPipe

            do {
                try proc.run()
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: "Could not start dashboard", body: error.localizedDescription)
                }
                return
            }

            // Read stdout until the READY JSON line arrives.
            let handle = stdoutPipe.fileHandleForReading
            var buffer = Data()
            var ready: ReadyReply?
            while ready == nil {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    break
                }
                buffer.append(chunk)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.prefix(upTo: nl)
                    buffer.removeSubrange(...nl)
                    if let line = String(data: lineData, encoding: .utf8),
                       line.hasPrefix("READY ") {
                        let jsonStr = String(line.dropFirst("READY ".count))
                        if let jsonData = jsonStr.data(using: .utf8),
                           let parsed = try? JSONDecoder().decode(ReadyReply.self, from: jsonData) {
                            ready = parsed
                            break
                        }
                    }
                }
            }

            guard let info = ready, let url = URL(string: info.url) else {
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? "The dashboard exited before becoming ready."
                if proc.isRunning { proc.terminate() }
                DispatchQueue.main.async {
                    self.showAlert(title: "Could not start dashboard", body: errMsg)
                }
                return
            }

            // Keep draining stderr/stdout so pipes never fill and stall the child.
            stdoutPipe.fileHandleForReading.readabilityHandler = { fh in
                let data = fh.availableData
                if data.isEmpty { fh.readabilityHandler = nil }
            }
            stderrPipe.fileHandleForReading.readabilityHandler = { fh in
                let data = fh.availableData
                if data.isEmpty { fh.readabilityHandler = nil }
            }

            let displayName = info.system_name.isEmpty
                ? URL(fileURLWithPath: canonical).lastPathComponent
                : info.system_name

            let instance = RunningWiki(
                canonicalPath: canonical,
                systemName: displayName,
                localURL: url,
                publicURL: info.public_url,
                port: info.port,
                process: proc
            )

            proc.terminationHandler = { [weak self] _ in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if self.running[canonical]?.process === proc {
                        self.running.removeValue(forKey: canonical)
                        self.rebuildMenu()
                    }
                }
            }

            DispatchQueue.main.async {
                self.running[canonical] = instance
                self.recentStore.record(path: canonical, name: displayName)
                self.rebuildMenu()
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func stopAllServers() {
        let procs = running.values.map(\.process)
        running.removeAll()
        for proc in procs where proc.isRunning {
            proc.terminate()
        }
        let deadline = Date().addingTimeInterval(2.0)
        for proc in procs {
            while proc.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    private func showAlert(title: String, body: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
