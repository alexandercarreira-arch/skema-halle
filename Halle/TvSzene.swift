import UIKit

/// Delegate der TV-Szene, Rolle `windowExternalDisplayNonInteractive` (Bauzettel 50, § 3.1, § 4; Muster
/// Probe S1-H). Beim Verbinden Overscan `.none` vor dem Fenster, dann die Buehne randlos; jede Verbindung
/// ist eine neue Szene, die Buehnen-WebView bleibt und haengt am neuen Fenster.
@MainActor
final class TvSzene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else {
            Protokoll.shared.schreibe("TV: Szene ist keine UIWindowScene")
            return
        }
        let bildschirm = windowScene.screen
        let vorher = bildschirm.overscanCompensation
        // `.scale` schrumpft das ganze Bild fuer den TV, `.none` fuellt das Panel (S1H, Bau 15.1).
        if vorher != .none {
            bildschirm.overscanCompensation = .none
        }
        Protokoll.shared.schreibe("TV verbunden (\(session.configuration.name ?? "ohne Namen")), Overscan vorher \(overscanText(vorher)): \(bildschirmText(bildschirm))")
        let fenster = UIWindow(windowScene: windowScene)
        fenster.rootViewController = TvController(buehne: Zustand.shared.buehne())
        window = fenster
        fenster.makeKeyAndVisible()
        Zustand.shared.setzeTv(windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Zustand.shared.buehneWeb?.webView.removeFromSuperview()
        window?.isHidden = true
        window = nil
        Protokoll.shared.schreibe("TV getrennt")
        Zustand.shared.setzeTv(nil)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        melde("willEnterForeground", scene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        melde("didBecomeActive", scene)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        melde("willResignActive", scene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        melde("didEnterBackground", scene)
    }

    private func melde(_ ereignis: String, _ scene: UIScene) {
        Protokoll.shared.schreibe("TV: \(ereignis), Zustand \(zustandText(scene.activationState))")
        Zustand.shared.aktualisiere()
    }
}

/// Wurzel des TV-Fensters: schwarzer Grund, darauf randlos die Buehne. Die gespiegelte safeArea am
/// TV-Fenster gilt nicht (S1H: oben 32, unten 25), darum an den Kanten der Ansicht, nicht am safeArea.
@MainActor
final class TvController: UIViewController {
    private let buehne: WebAnsicht

    init(buehne: WebAnsicht) {
        self.buehne = buehne
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        let grund = UIView()
        grund.backgroundColor = .black
        let web = buehne.webView
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = false
        grund.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: grund.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: grund.trailingAnchor),
            web.topAnchor.constraint(equalTo: grund.topAnchor),
            web.bottomAnchor.constraint(equalTo: grund.bottomAnchor),
        ])
        view = grund
    }
}

/// Gemeinsamer Zustand von Regie und TV-Szene: TV-Szene, Wach, die zwei Web-Ansichten.
@MainActor
final class Zustand {
    static let shared = Zustand()

    weak var regieWeb: WebAnsicht?
    /// Lebt so lange wie die App: Kabel ab und an laedt die Buehne nicht neu (S1H P1 (b)).
    private(set) var buehneWeb: WebAnsicht?
    private(set) weak var tvSzene: UIWindowScene?
    private(set) var wach = false
    var regieSzenen = 0
    var neuladungen = 0

    private init() {}

    func buehne() -> WebAnsicht {
        if let vorhanden = buehneWeb {
            return vorhanden
        }
        let neu = WebAnsicht(rolle: .buehne)
        buehneWeb = neu
        return neu
    }

    /// TV verbunden oder getrennt: beide Seiten bekommen `buehne` und einmal `wach`, auch wenn sich Wach
    /// dabei nicht aendert. Laedt die Buehne beim Verbinden noch, bringt ihr `didFinish` beides nach.
    func setzeTv(_ szene: UIWindowScene?) {
        tvSzene = szene
        aktualisiere(wachMelden: true)
    }

    /// Wach: `isIdleTimerDisabled`, solange die TV-Szene verbunden und eine Regie vorn ist, sonst zurueck
    /// auf `false` (Apple: „reset it to false when the need no longer exists"). Danach das Ereignis
    /// `buehne` an beide Seiten und, wenn Wach sich aendert oder `wachMelden`, das Ereignis `wach`.
    func aktualisiere(wachMelden: Bool = false) {
        let regieVorn = UIApplication.shared.connectedScenes.contains { szene in
            szene.session.role == .windowApplication && (szene.activationState == .foregroundActive || szene.activationState == .foregroundInactive)
        }
        let soll = tvSzene != nil && regieVorn
        let geaendert = soll != wach
        if geaendert {
            wach = soll
            UIApplication.shared.isIdleTimerDisabled = soll
            Protokoll.shared.schreibe("Wach: \(soll ? "an" : "aus") (TV \(tvSzene != nil ? "verbunden" : "nicht verbunden"), Regie \(regieVorn ? "vorn" : "nicht vorn"))")
        }
        let tv = Diagnose.buehne()
        let wachStand = Diagnose.wach()
        for ansicht in [regieWeb, buehneWeb].compactMap({ $0 }) {
            Bruecke.sende(.buehne(tv), an: ansicht)
            if geaendert || wachMelden {
                Bruecke.sende(.wach(wachStand), an: ansicht)
            }
        }
    }

    /// Kurzer Stand fuer den Minutenbericht.
    var tvText: String {
        guard let szene = tvSzene else {
            return "nicht verbunden"
        }
        return "\(zustandText(szene.activationState)), \(bildschirmText(szene.screen))"
    }
}
