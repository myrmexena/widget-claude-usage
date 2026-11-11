import Cocoa

struct Bucket { let pct: Double; let reset: Date? }
struct Usage { let week: Bucket?; let session: Bucket? }

func readToken() -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let o = j["claudeAiOauth"] as? [String: Any] else { return nil }
    return o["accessToken"] as? String
}

let iso: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
}()

func bucket(_ d: Any?) -> Bucket? {
    guard let d = d as? [String: Any], let u = d["utilization"] as? Double else { return nil }
    return Bucket(pct: u, reset: (d["resets_at"] as? String).flatMap { iso.date(from: $0) })
}

func fetch(_ done: @escaping (Usage?, String?) -> Void) {
    guard let tok = readToken() else { done(nil, "Token introuvable (lance `claude` pour te connecter)"); return }
    var r = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
    r.timeoutInterval = 15
    r.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
    r.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    r.setValue("claude-code/2.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: r) { data, resp, err in
        if let err = err { done(nil, err.localizedDescription); return }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let data = data,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            done(nil, code == 401 ? "Token expiré (relance `claude`)" : "HTTP \(code)"); return
        }
        done(Usage(week: bucket(j["seven_day"]), session: bucket(j["five_hour"])), nil)
    }.resume()
}

func fmtReset(_ d: Date?) -> String {
    guard let d = d else { return "" }
    let s = Int(d.timeIntervalSinceNow)
    if s <= 0 { return "reset imminent" }
    let (days, h, m) = (s / 86400, s % 86400 / 3600, s % 3600 / 60)
    let rel = days > 0 ? "\(days)j \(h)h" : (h > 0 ? "\(h)h \(m)min" : "\(m)min")
    let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE HH:mm"
    return "reset dans \(rel) (\(f.string(from: d)))"
}

func color(_ p: Double) -> NSColor { p >= 90 ? .systemRed : p >= 70 ? .systemOrange : .labelColor }

class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var usage: Usage?; var error: String?; var updated: Date?

    func applicationDidFinishLaunching(_ n: Notification) {
        render(); refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in self.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in self.refresh() }
    }

    @objc func noop() {}

    @objc func refresh() {
        fetch { u, e in DispatchQueue.main.async {
            if let u = u { self.usage = u; self.error = nil; self.updated = Date() } else { self.error = e }
            self.render()
        } }
    }

    func render() {
        let b = item.button!
        if let w = usage?.week {
            let t = NSMutableAttributedString(string: "7j ", attributes: [.font: NSFont.menuBarFont(ofSize: 0)])
            t.append(NSAttributedString(string: "\(Int(w.pct.rounded()))%", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium), .foregroundColor: color(w.pct)]))
            b.attributedTitle = t
        } else { b.title = error == nil ? "7j …" : "7j ⚠︎" }

        let m = NSMenu()
        func add(_ s: String, bold: Bool = false) {
            let i = NSMenuItem(title: s, action: #selector(noop), keyEquivalent: ""); i.target = self
            if bold { i.attributedTitle = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]) }
            m.addItem(i)
        }
        if let w = usage?.week { add("Semaine : \(Int(w.pct.rounded()))%", bold: true); add(fmtReset(w.reset)) }
        if let s = usage?.session { m.addItem(.separator()); add("Session 5 h : \(Int(s.pct.rounded()))%"); add(fmtReset(s.reset)) }
        if let e = error { m.addItem(.separator()); add("⚠︎ \(e)") }
        if let u = updated { let f = DateFormatter(); f.timeStyle = .short; m.addItem(.separator()); add("Mis à jour à \(f.string(from: u))") }
        m.addItem(.separator())
        let r = NSMenuItem(title: "Actualiser", action: #selector(refresh), keyEquivalent: "r"); r.target = self; m.addItem(r)
        m.addItem(NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = m
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
