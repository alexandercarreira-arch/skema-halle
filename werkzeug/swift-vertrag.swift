import Foundation

// Formen der Bruecke, wie Swift sie tatsaechlich sendet und liest (Bauzettel 50, § 2.7), als JSON fuer
// werkzeug/vertrag.sh. werkzeug/swift-vertrag.sh uebersetzt diese Datei mit Halle/Vertrag.swift fuer
// macOS (kein Simulator) und schreibt die Ausgabe nach build/swift-vertrag.json.
//
// Nichts hier ist eine zweite Liste der Felder: je Weg kodiert die App-Logik (Ereignis.json,
// Nachricht.json) ein Beispiel, und die Felder mit Typen kommen vom Draht, also aus dem JSON, das die
// Seite bekommt. Kann-Felder (Optional) erkennt Mirror; die Beispiele setzen jedes Feld, sonst bricht
// das Werkzeug ab. Jede Nachricht liest Swift mit Nachricht.lies zurueck, so wie die Seite sie sendet.
// Ein neuer Fall in Ereignis.Art oder Nachricht.Art laesst sich ohne Beispiel nicht uebersetzen.
//
// Ausgabe: { vertrag, umschlag, start, rollen: { regie|buehne: { faehigkeiten, ereignisse, nachrichten } },
// ereignisse: { art: { feld: typ } }, nachrichten: { art: { feld: typ } } }; Typen wie in
// huelle-vertrag.json (bool, zahl, text, texte, objekt), ein ? am Ende des Feldnamens heisst Kann-Feld.

struct Abbruch: Error, CustomStringConvertible {
    let description: String
}

/// Beispiele je Ereignis; die Buehne einmal ohne TV (die Werte, die die App dann sendet) und einmal mit.
func beispiele(_ art: Ereignis.Art) -> [Ereignis] {
    switch art {
    case .buehne:
        return [
            .buehne(.ohneTv),
            .buehne(BuehneDaten(verbunden: true, breite: 3840, hoehe: 2160, faktor: 1, modus: "3840x2160", modi: ["3840x2160", "1920x1080"], overscan: "none", zustand: "foregroundActive")),
        ]
    case .wach:
        return [.wach(WachDaten(aktiv: true)), .wach(WachDaten(aktiv: false))]
    case .diagnose:
        return [.diagnose(DiagnoseDaten(regieSzenen: 1, speicherMb: 212, waerme: "nominal", akku: -1, laden: "unknown", protokoll: ["09:00:00.000 Start"]))]
    }
}

/// Beispiele je Nachricht, wie die Seite sie sendet.
func beispiele(_ art: Nachricht.Art) -> [Nachricht] {
    switch art {
    case .diagnose:
        return [.diagnose(LeereDaten())]
    case .protokoll:
        return [.protokoll(ProtokollDaten(stufe: "info", text: "Route geladen: cockpit"))]
    }
}

/// Typ eines Werts vom Draht (JSONSerialization), wie huelle-vertrag.json ihn nennt.
func drahtTyp(_ wert: Any) -> String {
    switch wert {
    case is NSNull:
        return "null"
    case let zahl as NSNumber:
        return CFGetTypeID(zahl as CFTypeRef) == CFBooleanGetTypeID() ? "bool" : "zahl"
    case is String:
        return "text"
    case let liste as [Any]:
        return liste.allSatisfy { $0 is String } ? "texte" : "liste"
    case is [String: Any]:
        return "objekt"
    default:
        return "unbekannt"
    }
}

func objekt(_ json: String, _ wo: String) throws -> [String: Any] {
    guard let wert = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
        throw Abbruch(description: "\(wo): kein JSON-Objekt: \(json)")
    }
    return wert
}

/// Felder eines Objekts vom Draht mit Typ; Kann-Felder aus den Eigenschaften des Swift-Werts (Mirror).
func felder(_ draht: [String: Any], _ wert: Any, _ wo: String) throws -> [String: String] {
    var eigenschaften: [String: Bool] = [:]
    for kind in Mirror(reflecting: wert).children {
        guard let name = kind.label else {
            throw Abbruch(description: "\(wo): Eigenschaft ohne Namen")
        }
        eigenschaften[name] = Mirror(reflecting: kind.value).displayStyle == .optional
    }
    guard Set(eigenschaften.keys) == Set(draht.keys) else {
        throw Abbruch(description: "\(wo): Eigenschaften \(eigenschaften.keys.sorted()), auf dem Draht \(draht.keys.sorted()); das Beispiel setzt jedes Feld, CodingKeys benennen nichts um")
    }
    var ergebnis: [String: String] = [:]
    for (name, inhalt) in draht {
        ergebnis[(eigenschaften[name] ?? false) ? name + "?" : name] = drahtTyp(inhalt)
    }
    return ergebnis
}

/// Umschlag und Felder eines Wegs; `fall` ist der Wert von Ereignis oder Nachricht.
func form(_ json: String, _ fall: Any, _ art: String, _ wo: String) throws -> (umschlag: [String: String], felder: [String: String]) {
    let draht = try objekt(json, wo)
    guard draht["art"] as? String == art else {
        throw Abbruch(description: "\(wo): art auf dem Draht ist \(String(describing: draht["art"])), erwartet \(art)")
    }
    guard let daten = draht["daten"] as? [String: Any], let nutzlast = Mirror(reflecting: fall).children.first?.value else {
        throw Abbruch(description: "\(wo): keine daten auf dem Draht: \(json)")
    }
    let felderDaten = try felder(daten, nutzlast, "\(wo).daten")
    return (draht.mapValues(drahtTyp), felderDaten)
}

/// Alle Beispiele eines Wegs muessen dieselbe Form haben (die Buehne ohne TV wie mit).
func einig(_ formen: [[String: String]], _ wo: String) throws -> [String: String] {
    guard let erste = formen.first else {
        throw Abbruch(description: "\(wo): kein Beispiel")
    }
    for andere in formen where andere != erste {
        throw Abbruch(description: "\(wo): Beispiele mit verschiedenen Formen: \(erste.sorted { $0.key < $1.key }) und \(andere.sorted { $0.key < $1.key })")
    }
    return erste
}

func formen() throws -> [String: Any] {
    var umschlaege: [[String: String]] = []
    var ereignisse: [String: Any] = [:]
    for art in Ereignis.Art.allCases {
        var felderJe: [[String: String]] = []
        for ereignis in beispiele(art) {
            guard ereignis.art == art else {
                throw Abbruch(description: "Beispiel fuer Ereignis \(art.rawValue) ist \(ereignis.art.rawValue)")
            }
            let teil = try form(try ereignis.json(), ereignis, art.rawValue, "Ereignis \(art.rawValue)")
            umschlaege.append(teil.umschlag)
            felderJe.append(teil.felder)
        }
        ereignisse[art.rawValue] = try einig(felderJe, "Ereignis \(art.rawValue)")
    }
    var nachrichten: [String: Any] = [:]
    for art in Nachricht.Art.allCases {
        var felderJe: [[String: String]] = []
        for nachricht in beispiele(art) {
            guard nachricht.art == art else {
                throw Abbruch(description: "Beispiel fuer Nachricht \(art.rawValue) ist \(nachricht.art.rawValue)")
            }
            let json = try nachricht.json()
            // Swift liest, was die Seite in dieser Form sendet
            let gelesen: Nachricht
            do {
                gelesen = try Nachricht.lies(try JSONSerialization.jsonObject(with: Data(json.utf8)))
            } catch {
                throw Abbruch(description: "Nachricht \(art.rawValue): Swift liest \(json) nicht: \(lesefehlerText(error))")
            }
            guard gelesen.art == art else {
                throw Abbruch(description: "Nachricht \(art.rawValue): gelesen als \(gelesen.art.rawValue)")
            }
            let teil = try form(json, nachricht, art.rawValue, "Nachricht \(art.rawValue)")
            umschlaege.append(teil.umschlag)
            felderJe.append(teil.felder)
        }
        nachrichten[art.rawValue] = try einig(felderJe, "Nachricht \(art.rawValue)")
    }
    let start = Vertrag.start(.regie, bau: "0.1 (1.1)", xcode: "Xcode 26.6", gebaut: "2026-10-23T09:00:00Z")
    let startFelder = try felder(try objekt(try jsonText(start), "Start"), start, "Start")
    var rollen: [String: Any] = [:]
    for rolle in Rolle.allCases {
        rollen[rolle.rawValue] = [
            "faehigkeiten": Vertrag.faehigkeiten(rolle),
            "ereignisse": Vertrag.ereignisse(rolle).map { $0.rawValue },
            "nachrichten": Vertrag.nachrichten(rolle).map { $0.rawValue },
        ]
    }
    return [
        "vertrag": Vertrag.nummer,
        "umschlag": try einig(umschlaege, "Umschlag"),
        "start": startFelder,
        "rollen": rollen,
        "ereignisse": ereignisse,
        "nachrichten": nachrichten,
    ]
}

@main
enum SwiftVertrag {
    static func main() {
        do {
            let json = try JSONSerialization.data(withJSONObject: try formen(), options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("swift-vertrag: \(error)\n".utf8))
            exit(1)
        }
    }
}
