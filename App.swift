import SwiftUI
import Combine
import UserNotifications

// MARK: - Modelo

@MainActor
final class FocoModel: ObservableObject {
    @Published var total = 25 * 60 { didSet { if !rodando { restante = total } } }
    @Published var restante = 25 * 60
    @Published var rodando = false
    @Published var ciclos = 0
    @Published var abrirNoLogin: Bool { didSet { LoginItem.definir(abrirNoLogin) } }
    /// Tempo esgotado e ainda não confirmado (OK). nil = sem alarme.
    @Published var esgotadoDesde: Date?
    @Published var segundosEsgotado = 0
    @Published var piscar = false
    private var cancelaveis = Set<AnyCancellable>()

    /// Repete o som a cada 15 s, por até 2 min.
    static let intervaloSom = 15, duracaoSom = 120

    init() {
        let d = UserDefaults.standard
        if d.object(forKey: "abrirNoLogin") == nil { d.set(true, forKey: "abrirNoLogin") }
        abrirNoLogin = d.bool(forKey: "abrirNoLogin")
        LoginItem.definir(abrirNoLogin)   // regrava com o caminho atual do app
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
            .store(in: &cancelaveis)
        NotificationCenter.default.publisher(for: .confirmarAlarme)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.confirmar() } }
            .store(in: &cancelaveis)
        if CommandLine.arguments.contains("--teste-alarme") { total = 5; rodando = true }
    }

    var esgotado: Bool { esgotadoDesde != nil }

    private func tick() {
        if let desde = esgotadoDesde {
            segundosEsgotado = Int(Date().timeIntervalSince(desde))
            piscar.toggle()
            if segundosEsgotado > 0, segundosEsgotado <= Self.duracaoSom,
               segundosEsgotado % Self.intervaloSom == 0 { tocar() }
        }
        guard rodando else { return }
        if restante > 0 { restante -= 1 }
        if restante == 0 { terminar() }
    }

    private func terminar() {
        rodando = false; ciclos += 1; restante = total
        esgotadoDesde = Date(); segundosEsgotado = 0; piscar = true
        tocar()
        Alarme.notificar(ciclos: ciclos)
        NotificationCenter.default.post(name: .alarmeDisparou, object: nil)
    }

    private func tocar() {
        let som = NSSound(named: "Glass")
        som?.volume = 1
        som?.play()
    }

    /// Para todos os avisos.
    func confirmar() {
        guard esgotado else { return }
        esgotadoDesde = nil; segundosEsgotado = 0; piscar = false
        janelaPrincipal()?.level = .normal
    }

    var progresso: Double { esgotado ? 1 : 1 - Double(restante) / Double(total) }
    var tempo: String { String(format: "%02d:%02d", restante / 60, restante % 60) }
    var tempoEsgotado: String { String(format: "+%02d:%02d", segundosEsgotado / 60, segundosEsgotado % 60) }
    func alternar() {
        confirmar()
        if !rodando { Alarme.pedirPermissao() }
        rodando.toggle()
    }
    func zerar() { confirmar(); rodando = false; restante = total }
}


/// Notificação do macOS quando o tempo acaba.
enum Alarme {
    static func pedirPermissao() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    static func notificar(ciclos: Int) {
        let c = UNMutableNotificationContent()
        c.title = "🍅 Tempo esgotado!"
        c.body = "Ciclo \(ciclos) concluído. Clique para confirmar."
        c.interruptionLevel = .timeSensitive
        let req = UNNotificationRequest(identifier: "foco-\(Date().timeIntervalSince1970)", content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// Abre no login via LaunchAgent (com --login, para iniciar só na barra de menus).
enum LoginItem {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.marcelo.foco.plist")
    static func definir(_ ligado: Bool) {
        UserDefaults.standard.set(ligado, forKey: "abrirNoLogin")
        if ligado, let exe = Bundle.main.executablePath {
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
    static let abrirJanela = Notification.Name("FocoAbrirJanela")
    static let alarmeDisparou = Notification.Name("FocoAlarmeDisparou")
    static let confirmarAlarme = Notification.Name("FocoConfirmarAlarme")
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    // Mostra a notificação mesmo com o app ativo
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    // Clicou na notificação → confirma o alarme
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .confirmarAlarme, object: nil) }
        completionHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !FocoApp.noLogin else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.activate(ignoringOtherApps: true)
            if let w = janelaPrincipal() { trazer(w) }
        }
    }
    // Abrir o app de novo (Finder/Spotlight) enquanto ele já roda → mostra a janela
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .abrirJanela, object: nil)
        return false
    }
}

// MARK: - App

@main
struct FocoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = FocoModel()
    static let noLogin = CommandLine.arguments.contains("--login")

    var body: some Scene {
        Window("Foco", id: "principal") {
            JanelaTomate().environmentObject(model)
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultLaunchBehavior(Self.noLogin ? .suppressed : .presented)

        MenuBarExtra {
            MenuConteudo().environmentObject(model)
        } label: {
            RotuloBarra().environmentObject(model)
        }
    }
}

// MARK: - Barra de menus

/// Ícone da barra. `progresso` nil = tomate sólido (parado);
/// com valor = contorno do tomate que vai enchendo de baixo para cima.
/// `colorido` = tomate vermelho com folhas verdes (usado para piscar no alarme).
func iconeBarra(progresso: Double? = nil, colorido: Bool = false) -> NSImage {
    if colorido {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let ctx = NSGraphicsContext.current!.cgContext
            let r = CGRect(x: 1, y: 0.5, width: 16, height: 17)
            ctx.addPath(Tomate.corpo(in: r)); ctx.setFillColor(CGColor(red: 0.90, green: 0.22, blue: 0.18, alpha: 1)); ctx.fillPath()
            ctx.addPath(Tomate.cabo(in: r)); ctx.setFillColor(CGColor(red: 0.18, green: 0.52, blue: 0.24, alpha: 1)); ctx.fillPath()
            ctx.addPath(Tomate.folhas(in: r)); ctx.setFillColor(CGColor(red: 0.25, green: 0.69, blue: 0.31, alpha: 1)); ctx.fillPath()
            return true
        }
        return img
    }
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        let ctx = NSGraphicsContext.current!.cgContext
        let r = CGRect(x: 1, y: 0.5, width: 16, height: 17)
        let corpo = Tomate.corpo(in: r)
        ctx.setFillColor(.black); ctx.setStrokeColor(.black)
        if let p = progresso {
            ctx.addPath(corpo.copy(strokingWithWidth: 1.4, lineCap: .round, lineJoin: .round, miterLimit: 1))
            ctx.fillPath()
            // nível do "suco": do fundo do tomate (y = maxY) até o topo do corpo
            let topo = r.minY + 0.10 * r.height
            let nivel = r.maxY - CGFloat(min(max(p, 0), 1)) * (r.maxY - topo)
            ctx.saveGState()
            ctx.addPath(corpo); ctx.clip()
            ctx.fill(CGRect(x: r.minX, y: nivel, width: r.width, height: r.maxY - nivel))
            ctx.restoreGState()
        } else {
            ctx.addPath(corpo); ctx.fillPath()
        }
        ctx.setBlendMode(.clear)                       // recorta o contorno das folhas
        ctx.addPath(Tomate.folhas(in: r)); ctx.setLineWidth(1.8); ctx.strokePath()
        ctx.setBlendMode(.normal)
        ctx.addPath(Tomate.folhas(in: r)); ctx.fillPath()
        ctx.addPath(Tomate.cabo(in: r)); ctx.fillPath()
        return true
    }
    img.isTemplate = true
    return img
}

struct RotuloBarra: View {
    @EnvironmentObject var model: FocoModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        HStack(spacing: 4) {
            if model.esgotado {
                // pisca: tomate vermelho ↔ contorno
                Image(nsImage: model.piscar ? iconeBarra(colorido: true) : iconeBarra(progresso: 0))
                Text(model.tempoEsgotado).monospacedDigit()
            } else {
                let ativo = model.rodando || model.restante != model.total
                Image(nsImage: iconeBarra(progresso: ativo ? model.progresso : nil))
                if ativo {
                    Text((model.rodando ? "" : "⏸ ") + model.tempo).monospacedDigit()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .abrirJanela)) { _ in
            mostrarJanela(openWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: .alarmeDisparou)) { _ in
            // tomate pula na frente de tudo até o OK
            mostrarJanela(openWindow)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { janelaPrincipal()?.level = .floating }
        }
    }
}

struct MenuConteudo: View {
    @EnvironmentObject var model: FocoModel
    @Environment(\.openWindow) var openWindow
    var body: some View {
        if model.esgotado {
            Text("🍅 Tempo esgotado há \(String(model.tempoEsgotado.dropFirst()))")
            Button("OK, vi!") { model.confirmar() }
        } else {
            Text("\(model.tempo) • \(model.ciclos) ciclo(s)")
        }
        Divider()
        Button(model.rodando ? "Pausar" : "Iniciar") { model.alternar() }
        Button("Zerar") { model.zerar() }
        Menu("Duração") {
            ForEach(duracoes, id: \.self) { s in
                Button("\(rotulo(s))\(model.total == s ? " ✓" : "")") { model.total = s }
            }
        }.disabled(model.rodando)
        Divider()
        Button("Abrir janela") { mostrarJanela(openWindow) }
        Toggle("Abrir ao iniciar o Mac", isOn: $model.abrirNoLogin)
        Divider()
        Button("Sair do Foco") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

// MARK: - Janela em forma de tomate

/// Durações em segundos (5 s é para testar o alarme).
let duracoes = [5, 5 * 60, 15 * 60, 25 * 60, 50 * 60]
func rotulo(_ s: Int) -> String { s < 60 ? "\(s) s" : "\(s / 60) min" }

struct CorpoShape: Shape { func path(in r: CGRect) -> Path { Path(Tomate.corpo(in: r)) } }
struct FolhasShape: Shape { func path(in r: CGRect) -> Path { Path(Tomate.folhas(in: r)) } }
struct CaboShape: Shape { func path(in r: CGRect) -> Path { Path(Tomate.cabo(in: r)) } }

struct JanelaTomate: View {
    @EnvironmentObject var model: FocoModel
    @Environment(\.dismissWindow) var dismissWindow
    let vermelho = Color(red: 0.90, green: 0.22, blue: 0.18)
    let verde = Color(red: 0.25, green: 0.69, blue: 0.31)
    let verdeEscuro = Color(red: 0.18, green: 0.52, blue: 0.24)
    let W: CGFloat = 400, H: CGFloat = 390

    var body: some View {
        ZStack {
            CorpoShape().fill(vermelho).gesture(WindowDragGesture())
            CaboShape().fill(verdeEscuro).gesture(WindowDragGesture())
            FolhasShape().fill(verde).gesture(WindowDragGesture())
            conteudo.padding(.top, 95)
            Button { dismissWindow(id: "principal") } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26).background(Circle().fill(.white.opacity(0.22)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction).help("Fechar (fica na barra de menus)")
            .position(x: W * 0.80, y: H * 0.22)
        }
        .frame(width: W, height: H)
        .background(JanelaTransparente())
    }

    var conteudo: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 10)
                Circle().trim(from: 0, to: model.progresso)
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: model.progresso)
                VStack(spacing: 2) {
                    if model.esgotado {
                        Text("Acabou!").font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("há \(String(model.tempoEsgotado.dropFirst()))").font(.caption.weight(.semibold))
                            .monospacedDigit().opacity(0.85)
                    } else {
                        Text(model.tempo).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                        Text("\(model.ciclos) ciclo\(model.ciclos == 1 ? "" : "s")").font(.caption.weight(.semibold)).opacity(0.8)
                    }
                }.foregroundStyle(.white)
            }
            .frame(width: 140, height: 140)
            .scaleEffect(model.esgotado && model.piscar ? 1.06 : 1)   // pulsa durante o alarme
            .animation(.easeInOut(duration: 0.5), value: model.piscar)

            HStack(spacing: 6) {
                ForEach(duracoes, id: \.self) { s in
                    let sel = model.total == s
                    Button { model.total = s } label: {
                        Text(rotulo(s)).font(.caption.weight(.semibold))
                            .foregroundStyle(sel ? vermelho : .white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(sel ? 1 : 0.2)))
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .disabled(model.rodando).opacity(model.rodando ? 0.5 : 1)

            if model.esgotado {
                Button { model.confirmar() } label: {
                    Text("OK").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(vermelho)
                        .frame(width: 120, height: 52).background(Capsule().fill(.white)).contentShape(Capsule())
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
            } else {
            HStack(spacing: 16) {
                Button { model.alternar() } label: {
                    Image(systemName: model.rodando ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(vermelho)
                        .frame(width: 52, height: 52).background(Circle().fill(.white)).contentShape(Circle())
                }
                .buttonStyle(.plain).keyboardShortcut(.space, modifiers: [])
                Button { model.zerar() } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(.white.opacity(0.2))).contentShape(Circle())
                }.buttonStyle(.plain)
            }
            }
        }
    }
}

/// Deixa a janela sem fundo, para só o tomate aparecer.
struct JanelaTransparente: NSViewRepresentable {
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

/// Traz a janela do tomate para a frente, na tela onde está o mouse.
/// Reaproveita a janela existente (mesmo fechada); só cria uma nova se ela não existir.
@MainActor func mostrarJanela(_ openWindow: OpenWindowAction) {
    NSApp.activate(ignoringOtherApps: true)
    if let w = janelaPrincipal() {
        trazer(w)
    } else {
        openWindow(id: "principal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { if let w = janelaPrincipal() { trazer(w) } }
    }
}

@MainActor func janelaPrincipal() -> NSWindow? {
    NSApp.windows.first { $0.identifier?.rawValue.contains("principal") == true }
}

@MainActor func trazer(_ w: NSWindow) {
    let mouse = NSEvent.mouseLocation
    if let tela = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
       !tela.visibleFrame.intersects(w.frame) || !w.isVisible {
        let v = tela.visibleFrame
        w.setFrameOrigin(NSPoint(x: v.midX - w.frame.width / 2, y: v.midY - w.frame.height / 2))
    }
    w.makeKeyAndOrderFront(nil)
    w.orderFrontRegardless()
}
