import UIKit
import os

/// Einstieg der Huelle „SLSHM Coach" (Bauzettel 50, § 4). Gibt je Rolle die Konfiguration aus dem
/// Szenen-Manifest zurueck („Regie", „TV") und schreibt einmal je Minute Bildraten, Akku, Waerme,
/// Speicher und Wach ins Protokoll (§ 1: kein Dauertest, ein Abbruch im Training ist nachlesbar).
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private var minutenTakt: Takt?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Protokoll.shared.schreibe("Start: SLSHM Coach \(Bau.text), \(Bau.xcode), gebaut \(Bau.gebaut), gilt bis \(Bau.giltBis ?? "? (gebaut ist kein ISO 8601, die Seite verwirft den Start)"), iPadOS \(UIDevice.current.systemVersion), Worker \(Worker.host)")
        UIDevice.current.isBatteryMonitoringEnabled = true
        let zentrale = NotificationCenter.default
        zentrale.addObserver(self, selector: #selector(akkuGeaendert), name: UIDevice.batteryStateDidChangeNotification, object: nil)
        zentrale.addObserver(self, selector: #selector(waermeGeaendert), name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        Netz.shared.starte()
        minutenTakt = Takt(intervall: 60) { [weak self] in
            self?.minutenbericht()
        }
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let rolle = connectingSceneSession.role
        let name = rolle == .windowExternalDisplayNonInteractive ? "TV" : "Regie"
        Protokoll.shared.schreibe("Szene angefragt: Rolle \(rolle.rawValue), Konfiguration \(name)")
        return UISceneConfiguration(name: name, sessionRole: rolle)
    }

    @objc private func akkuGeaendert() {
        Protokoll.shared.schreibe("Akku: \(akkuText())")
    }

    /// Die Meldung kann auf einem beliebigen Thread kommen; hier wird nur gelesen und protokolliert.
    @objc nonisolated private func waermeGeaendert() {
        Protokoll.shared.schreibe("Wärme: \(waermeText(ProcessInfo.processInfo.thermalState))")
    }

    private func minutenbericht() {
        let zustand = Zustand.shared
        let freiMB = os_proc_available_memory() / 1_048_576
        Protokoll.shared.schreibe("Minute: Akku \(akkuText()); Wärme \(waermeText(ProcessInfo.processInfo.thermalState)); App \(Int(speicherDerAppMb())) MB, frei \(freiMB) MB; Wach \(zustand.wach ? "an" : "aus"); Netz \(Netz.shared.text); Regie-Szenen \(zustand.regieSzenen); Neuladungen \(zustand.neuladungen); TV \(zustand.tvText)")
        zustand.regieWeb?.meldeBildrate()
        zustand.buehneWeb?.meldeBildrate()
    }
}

/// Delegate der Hauptszene (Regie): ein Fenster, darin die Regie-WebView ueber die ganze Flaeche.
@MainActor
final class RegieSzene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            Protokoll.shared.schreibe("Regie: Szene ist keine UIWindowScene")
            return
        }
        let fenster = UIWindow(windowScene: windowScene)
        fenster.rootViewController = RegieController()
        window = fenster
        fenster.makeKeyAndVisible()
        Zustand.shared.regieSzenen += 1
        Protokoll.shared.schreibe("Regie verbunden (Regie-Szenen \(Zustand.shared.regieSzenen))")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Zustand.shared.regieSzenen -= 1
        Protokoll.shared.schreibe("Regie getrennt (Regie-Szenen \(Zustand.shared.regieSzenen))")
        Zustand.shared.aktualisiere()
    }

    /// Die Regie kommt wieder nach vorn: Wartet eine Ansicht nach einem Ladefehler, laedt sie neu. Das
    /// deckt den Ladefehler bei verbundenem Pfad, nach dem `NWPathMonitor` nichts mehr meldet (Netz.swift).
    func sceneWillEnterForeground(_ scene: UIScene) {
        melde("willEnterForeground")
        let regie = (window?.rootViewController as? RegieController)?.web
        for ansicht in [regie, Zustand.shared.buehneWeb].compactMap({ $0 }) {
            ansicht.ladeNeuWennWartet("Regie wieder vorn")
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        melde("didBecomeActive")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        melde("willResignActive")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        melde("didEnterBackground")
    }

    private func melde(_ ereignis: String) {
        Protokoll.shared.schreibe("Regie: \(ereignis)")
        Zustand.shared.aktualisiere()
    }
}

/// Wurzel der Regie: die Regie-WebView ist die Ansicht selbst. Keine nativen Knoepfe (`46` Entscheid 3).
@MainActor
final class RegieController: UIViewController {
    private(set) var web: WebAnsicht?
    /// Nur mit Xcode 27 im Bau (`45` E6): die `UISceneAccessoryRegistration`. Als `AnyObject` gehalten,
    /// weil eine gespeicherte Eigenschaft nicht hinter `#available` stehen kann.
    private var tvRegistrierung: AnyObject?

    override func loadView() {
        let web = WebAnsicht(rolle: .regie)
        self.web = web
        Zustand.shared.regieWeb = web
        view = web.webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        registriereTvFuerIPadOS27()
    }

    /// Ab iOS 27 kommt die TV-Szene erst nach Registrierung eines Szenen-Zubehoers (Release Note 177015874,
    /// nur fuer Bauten mit SDK 27). Nur mit Xcode 27 (Swift 6.4) im Bau, greift nur unter iPadOS 27; am
    /// Hallen-iPad mit 26.5 laeuft er nie. Uebernommen aus der Probe, vor G27 einmal mit `xcode: 27` gebaut.
    private func registriereTvFuerIPadOS27() {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let konfiguration = UISceneConfiguration(name: "TV", sessionRole: .windowExternalDisplayNonInteractive)
            konfiguration.delegateClass = TvSzene.self
            let zubehoer = UISceneAccessory.externalNonInteractive(sceneConfiguration: konfiguration)
            tvRegistrierung = registerSceneAccessory(zubehoer)
            Protokoll.shared.schreibe("iPadOS 27: Szenen-Zubehör für den TV registriert")
        } else {
            Protokoll.shared.schreibe("iPadOS 27: Weg im Bau, unter dieser Fassung nicht genutzt")
        }
        #else
        Protokoll.shared.schreibe("iPadOS 27: Weg nicht im Bau (Compiler vor Swift 6.4)")
        #endif
    }
}

/// Wiederkehrender Takt auf dem Haupt-Thread, ueber Ziel und Selektor statt Block (Muster Probe).
@MainActor
final class Takt: NSObject {
    private var timer: Timer?
    private let aktion: () -> Void

    init(intervall: TimeInterval, aktion: @escaping () -> Void) {
        self.aktion = aktion
        super.init()
        let neu = Timer(timeInterval: intervall, target: self, selector: #selector(feuer), userInfo: nil, repeats: true)
        RunLoop.main.add(neu, forMode: .common)
        timer = neu
    }

    @objc private func feuer() {
        aktion()
    }
}
