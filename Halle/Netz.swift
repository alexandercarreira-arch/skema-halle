import Foundation
import Network

/// Rueckfall ohne Netz und ohne Dienst (Bauzettel 50, § 2.2): Scheitert das Laden einer Web-Ansicht am
/// Netz, bleibt sie auf dem leeren Startbild und laedt neu, sobald `NWPathMonitor` wieder Netz meldet.
/// Kein Timer, kein Knopf, keine eigene Fehlerseite (Regel 2, Regel 7, `46` Entscheid 3).
@MainActor
final class Netz {
    static let shared = Netz()
    /// Gepostet, wenn das Netz nach einer Luecke wieder da ist.
    static let zurueck = Notification.Name("HalleNetzZurueck")

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
            Task { @MainActor in
                Netz.shared.melde(jetzt)
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.github.alexandercarreira-arch.skema-halle.netz"))
    }

    private func melde(_ jetzt: Bool) {
        let vorher = da
        guard jetzt != vorher else {
            return
        }
        da = jetzt
        Protokoll.shared.schreibe("Netz: \(jetzt ? "da" : "weg")")
        if jetzt, vorher == false {
            NotificationCenter.default.post(name: Netz.zurueck, object: nil)
        }
    }

    /// Fehler, nach denen ein Neuladen bei wiederkehrendem Netz hilft.
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
