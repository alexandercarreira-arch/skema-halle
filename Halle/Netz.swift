import Foundation
import Network

/// Rueckfall ohne Netz und ohne Dienst (Bauzettel 50, § 2.2): Scheitert das Laden einer Web-Ansicht am
/// Netz, bleibt sie auf dem leeren Startbild und wartet. Neu geladen wird bei jeder Pfadmeldung
/// „verbunden" von `NWPathMonitor`, nicht nur beim Wechsel von „weg" auf „da": Das Laden scheitert auch
/// bei verbundenem Pfad (Hotspot ohne Internet, Namensaufloesung, Zeitueberschreitung im Hallen-WLAN),
/// dann kommt nie ein Wechsel. Dazu laedt die Regie-Szene neu, wenn sie wieder nach vorn kommt (App.swift).
/// Kein Timer, kein Knopf, keine eigene Fehlerseite (Regel 2, Regel 7, `46` Entscheid 3).
@MainActor
final class Netz {
    static let shared = Netz()
    /// Gepostet bei jeder Pfadmeldung „verbunden", auch ohne Wechsel.
    static let verbunden = Notification.Name("HalleNetzVerbunden")

    private let monitor = NWPathMonitor()
    private(set) var da: Bool?

    private init() {}

    func starte() {
        Netz.beobachte(monitor)
    }

    /// Ausserhalb des Haupt-Akteurs, damit der Rueckruf auf der Warteschlange des Monitors nicht als
    /// Haupt-Akteur gilt; er reicht nur den Befund an den Haupt-Akteur weiter.
    nonisolated private static func beobachte(_ monitor: NWPathMonitor) {
        monitor.pathUpdateHandler = { pfad in
            let jetzt = pfad.status == .satisfied
            let wege = pfad.availableInterfaces.map { "\($0.type)" }
            Task { @MainActor in
                Netz.shared.melde(jetzt, wege)
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.github.alexandercarreira-arch.skema-halle.netz"))
    }

    private func melde(_ jetzt: Bool, _ wege: [String]) {
        let wechsel = jetzt != da
        da = jetzt
        let art = wege.isEmpty ? "ohne Schnittstelle" : wege.joined(separator: ", ")
        Protokoll.shared.schreibe("Netz: \(wechsel ? "" : "weiter ")\(jetzt ? "da" : "weg") (\(art))")
        if jetzt {
            NotificationCenter.default.post(name: Netz.verbunden, object: nil)
        }
    }

    /// Fehler, nach denen ein Neuladen bei verbundenem Netz hilft.
    nonisolated static func istNetzFehler(_ fehler: Error) -> Bool {
        let ns = fehler as NSError
        guard ns.domain == NSURLErrorDomain else {
            return false
        }
        let netz: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed]
        return netz.contains(URLError.Code(rawValue: ns.code))
    }

    var text: String {
        switch da {
        case .some(true): return "da"
        case .some(false): return "weg"
        case .none: return "unbekannt"
        }
    }
}
