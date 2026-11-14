import SwiftUI
import Combine
import UserNotifications

// MARK: - Model

@MainActor
final class TimerModel: ObservableObject {
    @Published var duration = 25 * 60 { didSet { if !isRunning { remaining = duration } } }
    @Published var remaining = 25 * 60
    @Published var isRunning = false
    @Published var completedCycles = 0
    @Published var launchAtLogin: Bool { didSet { LoginItem.set(enabled: launchAtLogin) } }
    /// When time ran out and the alarm hasn't been acknowledged yet. nil = no alarm.
    @Published var alarmStartedAt: Date?
    @Published var secondsSinceAlarm = 0
    @Published var blink = false
    private var subscriptions = Set<AnyCancellable>()

    /// Repeat the sound every 15 s, for up to 2 min.
    static let soundInterval = 15, soundDuration = 120

    init() {
        let d = UserDefaults.standard
        launchAtLogin = (d.object(forKey: "launchAtLogin") ?? d.object(forKey: "abrirNoLogin")) as? Bool ?? true
        LoginItem.set(enabled: launchAtLogin)   // rewrite with the app's current path
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .acknowledgeAlarm)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.acknowledge() } }
            .store(in: &subscriptions)
        if CommandLine.arguments.contains("--test-alarm") { duration = 5; isRunning = true }
    }

    var isAlarming: Bool { alarmStartedAt != nil }

    private func tick() {
        if let start = alarmStartedAt {
            secondsSinceAlarm = Int(Date().timeIntervalSince(start))
            blink.toggle()
            if secondsSinceAlarm > 0, secondsSinceAlarm <= Self.soundDuration,
               secondsSinceAlarm % Self.soundInterval == 0 { playSound() }
        }
        guard isRunning else { return }
        if remaining > 0 { remaining -= 1 }
        if remaining == 0 { finish() }
    }

    private func finish() {
        isRunning = false; completedCycles += 1; remaining = duration
        alarmStartedAt = Date(); secondsSinceAlarm = 0; blink = true
        playSound()
        Alarm.notify(cycle: completedCycles)
        NotificationCenter.default.post(name: .alarmFired, object: nil)
    }

    private func playSound() {
        let sound = NSSound(named: "Glass")
        sound?.volume = 1
        sound?.play()
    }

    /// Stops every alert.
    func acknowledge() {
        guard isAlarming else { return }
        alarmStartedAt = nil; secondsSinceAlarm = 0; blink = false
        mainWindow()?.level = .normal
    }

    var progress: Double { isAlarming ? 1 : 1 - Double(remaining) / Double(duration) }
    var timeText: String { String(format: "%02d:%02d", remaining / 60, remaining % 60) }
    var overtimeText: String { String(format: "%02d:%02d", secondsSinceAlarm / 60, secondsSinceAlarm % 60) }
    func toggle() {
        acknowledge()
        if !isRunning { Alarm.requestPermission() }
        isRunning.toggle()
    }
    func reset() { acknowledge(); isRunning = false; remaining = duration }
}

/// macOS notification when time runs out.
enum Alarm {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func notify(cycle: Int) {
        let c = UNMutableNotificationContent()
        c.title = "🍅 Time's up!"
        c.body = "Cycle \(cycle) complete. Click to acknowledge."
        c.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: "foco-\(Date().timeIntervalSince1970)", content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// Launch at login via a LaunchAgent (with --login, so it starts in the menu bar only).
enum LoginItem {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.marcelo.foco.plist")
    static func set(enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        if enabled, let exe = Bundle.main.executablePath {
            let plist: [String: Any] = ["Label": "com.marcelo.foco", "ProgramArguments": [exe, "--login"],
                                        "RunAtLoad": true, "ProcessType": "Interactive"]
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                try? data.write(to: url)
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

extension Notification.Name {
    static let showWindow = Notification.Name("FocoShowWindow")
    static let alarmFired = Notification.Name("FocoAlarmFired")
    static let acknowledgeAlarm = Notification.Name("FocoAcknowledgeAlarm")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    // Show the notification even while the app is active
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    // Clicking the notification acknowledges the alarm
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .acknowledgeAlarm, object: nil) }
        completionHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !FocoApp.launchedAtLogin else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.activate(ignoringOtherApps: true)
            if let w = mainWindow() { bringToFront(w) }
        }
    }
    // Opening the app again (Finder/Spotlight) while it's running → show the window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .showWindow, object: nil)
        return false
    }
}

// MARK: - App

@main
struct FocoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = TimerModel()
    static let launchedAtLogin = CommandLine.arguments.contains("--login")

    var body: some Scene {
        Window("Foco", id: "main") {
            TomatoWindow().environmentObject(model)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultLaunchBehavior(Self.launchedAtLogin ? .suppressed : .presented)

        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            MenuBarLabel().environmentObject(model)
        }
    }
}

// MARK: - Menu bar

/// Menu bar icon. `progress` nil = solid tomato (idle);
/// with a value = tomato outline that fills from the bottom up.
/// `colored` = red tomato with green leaves (used to blink during the alarm).
func menuBarIcon(progress: Double? = nil, colored: Bool = false) -> NSImage {
    if colored {
        return NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            let r = CGRect(x: 1, y: 0.5, width: 16, height: 17)
            ctx.addPath(Tomato.body(in: r)); ctx.setFillColor(CGColor(red: 0.90, green: 0.22, blue: 0.18, alpha: 1)); ctx.fillPath()
            ctx.addPath(Tomato.stem(in: r)); ctx.setFillColor(CGColor(red: 0.18, green: 0.52, blue: 0.24, alpha: 1)); ctx.fillPath()
            ctx.addPath(Tomato.leaves(in: r)); ctx.setFillColor(CGColor(red: 0.25, green: 0.69, blue: 0.31, alpha: 1)); ctx.fillPath()
            return true
        }
    }
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        let r = CGRect(x: 1, y: 0.5, width: 16, height: 17)
        let body = Tomato.body(in: r)
        ctx.setFillColor(.black); ctx.setStrokeColor(.black)
        if let p = progress {
            ctx.addPath(body.copy(strokingWithWidth: 1.4, lineCap: .round, lineJoin: .round, miterLimit: 1))
            ctx.fillPath()
            // fill level: from the bottom of the tomato (y = maxY) up to the top of the body
            let top = r.minY + 0.10 * r.height
            let level = r.maxY - CGFloat(min(max(p, 0), 1)) * (r.maxY - top)
            ctx.saveGState()
            ctx.addPath(body); ctx.clip()
            ctx.fill(CGRect(x: r.minX, y: level, width: r.width, height: r.maxY - level))
            ctx.restoreGState()
        } else {
            ctx.addPath(body); ctx.fillPath()
        }
        ctx.setBlendMode(.clear)                       // cut out an outline around the leaves
        ctx.addPath(Tomato.leaves(in: r)); ctx.setLineWidth(1.8); ctx.strokePath()
        ctx.setBlendMode(.normal)
        ctx.addPath(Tomato.leaves(in: r)); ctx.fillPath()
        ctx.addPath(Tomato.stem(in: r)); ctx.fillPath()
        return true
    }
    img.isTemplate = true
    return img
}

struct MenuBarLabel: View {
    @EnvironmentObject var model: TimerModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        HStack(spacing: 4) {
            if model.isAlarming {
                // blink: red tomato ↔ outline
                Image(nsImage: model.blink ? menuBarIcon(colored: true) : menuBarIcon(progress: 0))
                Text("+" + model.overtimeText).monospacedDigit()
            } else {
                let active = model.isRunning || model.remaining != model.duration
                Image(nsImage: menuBarIcon(progress: active ? model.progress : nil))
                if active {
                    Text((model.isRunning ? "" : "⏸ ") + model.timeText).monospacedDigit()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWindow)) { _ in
            showWindow(openWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .alarmFired)) { _ in
            // the tomato jumps in front of everything until OK
            showWindow(openWindow)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { mainWindow()?.level = .floating }
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: TimerModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        if model.isAlarming {
            Text("🍅 Time's up — \(model.overtimeText) ago")
            Button("OK, got it!") { model.acknowledge() }
        } else {
            Text("\(model.timeText) • \(model.completedCycles) cycle(s)")
        }
        Divider()
        Button(model.isRunning ? "Pause" : "Start") { model.toggle() }
        Button("Reset") { model.reset() }
        Menu("Duration") {
            ForEach(durations, id: \.self) { s in
                Button("\(label(for: s))\(model.duration == s ? " ✓" : "")") { model.duration = s }
            }
        }.disabled(model.isRunning)
        Divider()
        Button("Show Window") { showWindow(openWindow) }
        Toggle("Launch at Login", isOn: $model.launchAtLogin)
        Divider()
        Button("Quit Foco") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

// MARK: - Tomato-shaped window

/// Durations in seconds (5 s is for testing the alarm).
let durations = [5, 5 * 60, 15 * 60, 25 * 60, 50 * 60]
func label(for s: Int) -> String { s < 60 ? "\(s) s" : "\(s / 60) min" }

struct BodyShape: Shape { func path(in r: CGRect) -> Path { Path(Tomato.body(in: r)) } }
struct LeavesShape: Shape { func path(in r: CGRect) -> Path { Path(Tomato.leaves(in: r)) } }
struct StemShape: Shape { func path(in r: CGRect) -> Path { Path(Tomato.stem(in: r)) } }

struct TomatoWindow: View {
    @EnvironmentObject var model: TimerModel
    @Environment(\.dismissWindow) var dismissWindow
    let red = Color(red: 0.90, green: 0.22, blue: 0.18)
    let green = Color(red: 0.25, green: 0.69, blue: 0.31)
    let darkGreen = Color(red: 0.18, green: 0.52, blue: 0.24)
    let W: CGFloat = 400, H: CGFloat = 390

    var body: some View {
        ZStack {
            BodyShape().fill(red).gesture(WindowDragGesture())
            StemShape().fill(darkGreen).gesture(WindowDragGesture())
            LeavesShape().fill(green).gesture(WindowDragGesture())
            content.padding(.top, 95)
            Button { dismissWindow(id: "main") } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.22)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("Close (stays in the menu bar)")
            .position(x: W * 0.80, y: H * 0.22)
        }
        .frame(width: W, height: H)
        .background(TransparentWindow())
    }

    var content: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 10)
                Circle().trim(from: 0, to: model.progress)
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: model.progress)
                VStack(spacing: 2) {
                    if model.isAlarming {
                        Text("Time's up!").font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("\(model.overtimeText) ago").font(.caption.weight(.semibold))
                            .monospacedDigit().opacity(0.85)
                    } else {
                        Text(model.timeText).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("\(model.completedCycles) cycle\(model.completedCycles == 1 ? "" : "s")")
                            .font(.caption.weight(.semibold)).opacity(0.8)
                    }
                }.foregroundStyle(.white)
            }
            .frame(width: 140, height: 140)
            .scaleEffect(model.isAlarming && model.blink ? 1.06 : 1)   // pulses during the alarm
            .animation(.easeInOut(duration: 0.5), value: model.blink)

            HStack(spacing: 6) {
                ForEach(durations, id: \.self) { s in
                    let selected = model.duration == s
                    Button { model.duration = s } label: {
                        Text(label(for: s)).font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? red : .white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(selected ? 1 : 0.2)))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .disabled(model.isRunning).opacity(model.isRunning ? 0.5 : 1)

            if model.isAlarming {
                Button { model.acknowledge() } label: {
                    Text("OK").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(red)
                        .frame(width: 120, height: 52).background(Capsule().fill(.white)).contentShape(Capsule())
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            } else {
                HStack(spacing: 16) {
                    Button { model.toggle() } label: {
                        Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold)).foregroundStyle(red)
                            .frame(width: 52, height: 52).background(Circle().fill(.white)).contentShape(Circle())
                    }
                    .buttonStyle(.plain).keyboardShortcut(.space, modifiers: [])
                    Button { model.reset() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.2))).contentShape(Circle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// Removes the window background so only the tomato shows.
struct TransparentWindow: NSViewRepresentable {
    final class V: NSView {
        override func viewDidMoveToWindow() {
            guard let w = window else { return }
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.isMovableByWindowBackground = true
        }
    }
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Brings the tomato window to the front, on the screen where the mouse is.
/// Reuses the existing window (even if closed); only creates a new one if it doesn't exist.
@MainActor func showWindow(_ openWindow: OpenWindowAction) {
    NSApp.activate(ignoringOtherApps: true)
    if let w = mainWindow() {
        bringToFront(w)
    } else {
        openWindow(id: "main")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { if let w = mainWindow() { bringToFront(w) } }
    }
}

@MainActor func mainWindow() -> NSWindow? {
    NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
}

@MainActor func bringToFront(_ w: NSWindow) {
    let mouse = NSEvent.mouseLocation
    if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
       !screen.visibleFrame.intersects(w.frame) || !w.isVisible {
        let v = screen.visibleFrame
        w.setFrameOrigin(NSPoint(x: v.midX - w.frame.width / 2, y: v.midY - w.frame.height / 2))
    }
    w.makeKeyAndOrderFront(nil)
    w.orderFrontRegardless()
}
