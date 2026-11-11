import Cocoa
import UserNotifications

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

// Same steps as the notification thresholds: <50 green, 50-80 yellow, 80-90 orange, >=90 red.
func color(_ p: Double) -> NSColor { p >= 90 ? .systemRed : p >= 80 ? .systemOrange : p >= 50 ? .systemYellow : NSColor(srgbRed: 0.10, green: 0.47, blue: 0.25, alpha: 1) }
func titleColor(_ p: Double) -> NSColor { p >= 80 ? color(p) : .labelColor }

class BarView: NSView {
    let title: String, pct: Double, sub: String
    init(title: String, pct: Double, sub: String) {
        self.title = title; self.pct = pct; self.sub = sub
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 52))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ r: NSRect) {
        let pad: CGFloat = 14
        NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]).draw(at: NSPoint(x: pad, y: 33))
        let v = NSAttributedString(string: "\(Int(pct.rounded())) %", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold), .foregroundColor: pct >= 90 ? color(pct) : NSColor.labelColor])
        v.draw(at: NSPoint(x: bounds.width - pad - v.size().width, y: 33))
        let track = NSRect(x: pad, y: 22, width: bounds.width - 2 * pad, height: 6)
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        if pct > 0 {
            var f = track; f.size.width = max(6, track.width * CGFloat(min(pct, 100)) / 100)
            color(pct).setFill()
            NSBezierPath(roundedRect: f, xRadius: 3, yRadius: 3).fill()
        }
        NSAttributedString(string: sub, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8)]).draw(at: NSPoint(x: pad, y: 5))
    }
}

let thresholds: [Double] = [50, 80, 90, 95]

class App: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var usage: Usage?; var error: String?; var updated: Date?

    func applicationDidFinishLaunching(_ n: Notification) {
        let nc = UNUserNotificationCenter.current()
        nc.delegate = self
        nc.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        render(); refresh()
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in self.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in self.refresh() }
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }

    // One alert per threshold per reset period; if several are crossed at once, only the highest fires.
    func checkAlerts(_ u: Usage) {
        for (name, label, b) in [("week", "hebdomadaire", u.week), ("session", "de la session 5 h", u.session)] {
            guard let b = b, let t = thresholds.last(where: { b.pct >= $0 }) else { continue }
            let period = b.reset.map { String(Int(($0.timeIntervalSince1970 / 60).rounded())) } ?? "none"
            let key = "alert.\(name).\(period)"
            if Double(UserDefaults.standard.integer(forKey: key)) >= t { continue }
            UserDefaults.standard.set(Int(t), forKey: key)
            let c = UNMutableNotificationContent()
            c.title = "Claude — limite \(label) à \(Int(t)) %"
            c.body = "Usage actuel : \(Int(b.pct.rounded())) %, \(fmtReset(b.reset))"
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key + ".\(Int(t))", content: c, trigger: nil))
        }
    }

    @objc func noop() {}

    @objc func refresh() {
        fetch { u, e in DispatchQueue.main.async {
            if let u = u { self.usage = u; self.error = nil; self.updated = Date(); self.checkAlerts(u) } else { self.error = e }
            self.render()
        } }
    }

    func render() {
        let b = item.button!
        if let w = usage?.week {
            let t = NSMutableAttributedString(string: "7j ", attributes: [.font: NSFont.menuBarFont(ofSize: 0)])
            t.append(NSAttributedString(string: "\(Int(w.pct.rounded()))%", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium), .foregroundColor: titleColor(w.pct)]))
            b.attributedTitle = t
        } else { b.title = error == nil ? "7j …" : "7j ⚠︎" }

        b.toolTip = "Usage Claude (limite hebdomadaire)"
        let m = NSMenu()
        func add(_ s: String, bold: Bool = false) {
            let i = NSMenuItem(title: s, action: #selector(noop), keyEquivalent: ""); i.target = self
            if bold { i.attributedTitle = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]) }
            m.addItem(i)
        }
        add("Claude — Usage"); m.addItem(.separator())
        func bar(_ t: String, _ b: Bucket) {
            let i = NSMenuItem(); i.view = BarView(title: t, pct: b.pct, sub: fmtReset(b.reset)); m.addItem(i)
        }
        if let w = usage?.week { bar("Semaine", w) }
        if let s = usage?.session { m.addItem(.separator()); bar("Session 5 h", s) }
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
