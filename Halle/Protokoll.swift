import Foundation
import os

/// Natives Protokoll der Huelle (Bauzettel 50, § 4): Ring mit Uhrzeit, gespiegelt nach `os.Logger`,
/// damit `pymobiledevice3 syslog live` mitlesen kann. Jeder eingesetzte Text steht mit
/// `privacy: .public`, sonst schwaerzt das System ihn als `<private>`. Die Diagnose der Web-App zeigt
/// die letzten 200 Zeilen (Ereignis `diagnose`, Diagnose.swift). Keine Inhalte der Tafel, keine Eingaben.
final class Protokoll: @unchecked Sendable {
    static let shared = Protokoll()

    private let grenze = 1_000
    private let sperre = NSLock()
    private var zeilen: [String] = []
    private let uhr: DateFormatter
    private let logger = Logger(subsystem: "io.github.alexandercarreira-arch.skema-halle", category: "halle")

    private init() {
        uhr = DateFormatter()
        uhr.locale = Locale(identifier: "en_US_POSIX")
        uhr.dateFormat = "HH:mm:ss.SSS"
    }

    /// Darf von jedem Thread kommen.
    func schreibe(_ text: String) {
        sperre.lock()
        let zeile = "\(uhr.string(from: Date())) \(text)"
        zeilen.append(zeile)
        if zeilen.count > grenze {
            zeilen.removeFirst(zeilen.count - grenze)
        }
        sperre.unlock()
        logger.log("\(zeile, privacy: .public)")
    }

    /// Die letzten Zeilen, die neueste zuletzt.
    func letzte(_ anzahl: Int) -> [String] {
        sperre.lock()
        defer { sperre.unlock() }
        return Array(zeilen.suffix(anzahl))
    }
}

/// Kuerzt lange Texte (Adressen, Meldungen der Seite) fuer das Protokoll.
func kurz(_ text: String, _ grenze: Int = 200) -> String {
    text.count > grenze ? String(text.prefix(grenze)) + "…" : text
}

func fehlerText(_ fehler: Error) -> String {
    let ns = fehler as NSError
    return "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
}
