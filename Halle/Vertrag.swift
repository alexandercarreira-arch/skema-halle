import Foundation

// Vertrag mit der Web-App (Bauzettel 50, § 2.7). Die einzige Quelle ist `packages/protocol/src/huelle.ts`
// im privaten Repo; ihr Build liegt als `huelle-vertrag.json` auf dem Worker (Namen, Faehigkeit je Weg,
// Felder mit Typen). Swift sendet und liest nur die Formen in dieser Datei. Sie braucht nur Foundation:
// `werkzeug/swift-vertrag.sh` uebersetzt sie im Pruef-Job fuer macOS und schreibt mit
// `werkzeug/swift-vertrag.swift` aus, was Swift tatsaechlich sendet und liest (`build/swift-vertrag.json`);
// `werkzeug/vertrag.sh` vergleicht das in beide Richtungen mit `huelle-vertrag.json`.

/// Die beiden Rollen der Web-App in der Huelle.
enum Rolle: String, CaseIterable {
    case regie
    case buehne

    var name: String { self == .regie ? "Regie" : "Bühne" }
    var pfad: String { self == .regie ? "/cockpit" : "/tv" }
}

enum Vertrag {
    static let nummer = 1

    /// Was die Huelle der Seite meldet. Beide Rollen melden `diagnose`: die Seite sendet `protokoll` nur mit
    /// dieser Faehigkeit, sonst kaeme das Log der Buehne nie ins native Protokoll. T2 (Stift.swift) ergaenzt
    /// die Regie um `stift.doppeltipp`, `stift.squeeze` und `haptik`.
    static func faehigkeiten(_ rolle: Rolle) -> [String] {
        switch rolle {
        case .regie: return ["wach", "buehne", "diagnose"]
        case .buehne: return ["wach", "buehne", "diagnose"]
        }
    }

    /// Ereignisse an diese Rolle; `Bruecke.sende` sendet keine anderen. `buehne` und `wach` an beide,
    /// `diagnose` nur an die Regie, als Antwort auf ihre Nachricht.
    static func ereignisse(_ rolle: Rolle) -> [Ereignis.Art] {
        switch rolle {
        case .regie: return [.buehne, .wach, .diagnose]
        case .buehne: return [.buehne, .wach]
        }
    }

    /// Nachrichten, die Swift von dieser Rolle annimmt: `diagnose` nur aus der Regie, `protokoll` aus beiden.
    static func nachrichten(_ rolle: Rolle) -> [Nachricht.Art] {
        switch rolle {
        case .regie: return [.diagnose, .protokoll]
        case .buehne: return [.protokoll]
        }
    }

    /// `window.__skemaHuelle` fuer eine Rolle.
    static func start(_ rolle: Rolle, bau: String, xcode: String, gebaut: String) -> Start {
        Start(vertrag: nummer, rolle: rolle.rawValue, bau: bau, xcode: xcode, gebaut: gebaut, faehigkeiten: faehigkeiten(rolle))
    }
}

/// `window.__skemaHuelle`, zu Dokumentbeginn gesetzt und eingefroren.
struct Start: Codable {
    let vertrag: Int
    let rolle: String
    let bau: String
    let xcode: String
    /// ISO 8601 in UTC auf die Sekunde (`gebaut.muster` im Vertrag), bauen.sh prueft es am Archiv
    let gebaut: String
    let faehigkeiten: [String]
}

/// Umschlag jedes Ereignisses (`detail` des CustomEvent) und jeder Nachricht (`postMessage`).
struct Umschlag<Daten: Codable>: Codable {
    let art: String
    let daten: Daten
}

/// Ereignis `buehne`: die TV-Szene, Werte roh aus UIKit (Diagnose.swift). Nie `null`.
struct BuehneDaten: Codable {
    let verbunden: Bool
    /// Bildschirm des TV in Punkten (`UIScreen.bounds`)
    let breite: Double
    let hoehe: Double
    /// `UIScreen.scale`
    let faktor: Double
    /// `UIScreen.currentMode` wie „3840x2160", leer ohne Modus
    let modus: String
    let modi: [String]
    /// `UIScreen.OverscanCompensation`: none, scale, insetBounds
    let overscan: String
    /// `UIScene.ActivationState`: unattached, foregroundActive, foregroundInactive, background
    let zustand: String

    /// Ohne TV, wie der Vertrag es verlangt: Zahlen 0, Texte leer, keine Szene.
    static let ohneTv = BuehneDaten(verbunden: false, breite: 0, hoehe: 0, faktor: 0, modus: "", modi: [], overscan: "", zustand: "unattached")
}

/// Ereignis `wach`: `isIdleTimerDisabled`, das Swift setzt, solange der TV steckt und die Regie vorn ist.
struct WachDaten: Codable {
    let aktiv: Bool
}

/// Ereignis `diagnose`: Antwort auf die Nachricht `diagnose` der Regie.
struct DiagnoseDaten: Codable {
    /// verbundene Regie-Szenen (1 erwartet)
    let regieSzenen: Int
    /// Speicher der App in MB (`phys_footprint`)
    let speicherMb: Double
    /// `ProcessInfo.ThermalState`: nominal, fair, serious, critical
    let waerme: String
    /// Akku in Prozent, -1 unbekannt
    let akku: Int
    /// `UIDevice.BatteryState`: unknown, unplugged, charging, full
    let laden: String
    /// die letzten Zeilen des nativen Protokolls, aelteste zuerst
    let protokoll: [String]
}

/// Nachricht `protokoll`: eine Zeile des Log-Rings der Seite.
struct ProtokollDaten: Codable {
    let stufe: String
    let text: String
}

/// Daten einer Nachricht ohne Felder (`diagnose`): ein leeres Objekt.
struct LeereDaten: Codable {}

/// Was Swift an die Seite sendet.
enum Ereignis {
    case buehne(BuehneDaten)
    case wach(WachDaten)
    case diagnose(DiagnoseDaten)

    enum Art: String, CaseIterable {
        case buehne
        case wach
        case diagnose
    }

    var art: Art {
        switch self {
        case .buehne: return .buehne
        case .wach: return .wach
        case .diagnose: return .diagnose
        }
    }

    /// Der Umschlag als JSON, so wie er an die Seite geht.
    func json() throws -> String {
        switch self {
        case .buehne(let daten): return try jsonText(Umschlag(art: art.rawValue, daten: daten))
        case .wach(let daten): return try jsonText(Umschlag(art: art.rawValue, daten: daten))
        case .diagnose(let daten): return try jsonText(Umschlag(art: art.rawValue, daten: daten))
        }
    }
}

/// Was Swift von der Seite liest.
enum Nachricht {
    case diagnose(LeereDaten)
    case protokoll(ProtokollDaten)

    enum Art: String, CaseIterable {
        case diagnose
        case protokoll
    }

    var art: Art {
        switch self {
        case .diagnose: return .diagnose
        case .protokoll: return .protokoll
        }
    }

    /// Der Umschlag als JSON, so wie die Seite ihn sendet (fuer werkzeug/swift-vertrag.swift).
    func json() throws -> String {
        switch self {
        case .diagnose(let daten): return try jsonText(Umschlag(art: art.rawValue, daten: daten))
        case .protokoll(let daten): return try jsonText(Umschlag(art: art.rawValue, daten: daten))
        }
    }

    /// Liest den Koerper von `postMessage`: `{ art, daten }` mit genau den Typen des Vertrags; sonst
    /// ein Fehler mit Grund (`lesefehlerText`).
    static func lies(_ koerper: Any) throws -> Nachricht {
        guard JSONSerialization.isValidJSONObject(koerper), koerper is [String: Any] else {
            throw Lesefehler.keinObjekt
        }
        let json = try JSONSerialization.data(withJSONObject: koerper)
        let leser = JSONDecoder()
        let kopf = try leser.decode(Kopf.self, from: json)
        guard let art = Art(rawValue: kopf.art) else {
            throw Lesefehler.unbekannt(kopf.art)
        }
        switch art {
        case .diagnose: return .diagnose(try leser.decode(Umschlag<LeereDaten>.self, from: json).daten)
        case .protokoll: return .protokoll(try leser.decode(Umschlag<ProtokollDaten>.self, from: json).daten)
        }
    }
}

/// Nur `art` des Umschlags, um die Daten mit dem passenden Typ zu lesen.
private struct Kopf: Decodable {
    let art: String
}

enum Lesefehler: Error, CustomStringConvertible {
    case keinObjekt
    case unbekannt(String)

    var description: String {
        switch self {
        case .keinObjekt: return "kein Objekt"
        case .unbekannt(let art): return "Nachricht \(art.prefix(40)) nicht im Vertrag"
        }
    }
}

/// Kurzer Grund, warum eine Nachricht nicht lesbar war, fuer das Protokoll.
func lesefehlerText(_ fehler: Error) -> String {
    guard let fehler = fehler as? DecodingError else {
        return "\(fehler)"
    }
    switch fehler {
    case .keyNotFound(let schluessel, let kontext):
        return "Feld \(pfadText(kontext.codingPath + [schluessel])) fehlt"
    case .typeMismatch(_, let kontext), .valueNotFound(_, let kontext):
        return "Feld \(pfadText(kontext.codingPath)) hat einen anderen Typ"
    case .dataCorrupted(let kontext):
        return "unlesbar: \(kontext.debugDescription)"
    @unknown default:
        return "\(fehler)"
    }
}

private func pfadText(_ schluessel: [CodingKey]) -> String {
    schluessel.map { $0.stringValue }.joined(separator: ".")
}

/// Wert als JSON-Text, der zugleich ein gueltiger JS-Ausdruck ist; Schluessel sortiert.
func jsonText<Wert: Encodable>(_ wert: Wert) throws -> String {
    let kodierer = JSONEncoder()
    kodierer.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try kodierer.encode(wert), as: UTF8.self)
}
