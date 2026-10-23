import Foundation

// Formen der Bruecke, wie Swift sie tatsaechlich sendet und liest (Bauzettel 50, § 2.7), als JSON fuer
// werkzeug/vertrag.sh. werkzeug/swift-vertrag.sh uebersetzt diese Datei mit Halle/Vertrag.swift fuer
// macOS (kein Simulator) und schreibt die Ausgabe nach build/swift-vertrag.json.
//
// Nichts hier ist eine zweite Liste der Felder: je Weg kodiert die App-Logik (Ereignis.json,
// Nachricht.json) Beispiele, und die Felder mit Typen kommen vom Draht, also aus dem JSON, das die
// Seite bekommt. Kann-Felder (Optional) erkennt Mirror. Ein Kann-Feld ohne Wert muss auf dem Draht
// fehlen (nie null), jedes andere Feld dort stehen; jedes Kann-Feld zeigen die Beispiele einmal mit und
// einmal ohne Wert (Stift mit und ohne Hover-Pose), sonst bricht das Werkzeug ab. Jede Nachricht liest
// Swift mit Nachricht.lies zurueck, so wie die Seite sie sendet. Ein neuer Fall in Ereignis.Art oder
// Nachricht.Art laesst sich ohne Beispiel nicht uebersetzen. Die Texte mit fester Liste (werte im
// Vertrag) kommen aus den Faellen der Swift-Typen StiftEinstellung, SqueezePhase und HaptikTyp.
//
// Ausgabe: { vertrag, umschlag, start, rollen: { regie|buehne: { faehigkeiten, ereignisse, nachrichten } },
// ereignisse: { art: { feld: typ } }, nachrichten: { art: { feld: typ } }, werte: { liste: [text] } };
// Typen wie in huelle-vertrag.json (bool, zahl, text, texte, objekt), ein ? am Ende des Feldnamens heisst
// Kann-Feld.

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
    case .stiftDoppeltipp:
        return [
            .stiftDoppeltipp(StiftDoppeltippDaten(einstellung: .switchEraser, punkt: StiftPunkt(x: 412.5, y: 300))),
            .stiftDoppeltipp(StiftDoppeltippDaten(einstellung: .ignore, punkt: nil)),
        ]
    case .stiftSqueeze:
        return [
            .stiftSqueeze(StiftSqueezeDaten(phase: .ended, einstellung: .showContextualPalette, punkt: StiftPunkt(x: 412.5, y: 300))),
            .stiftSqueeze(StiftSqueezeDaten(phase: .began, einstellung: .switchPrevious, punkt: nil)),
        ]
    }
}

/// Beispiele je Nachricht, wie die Seite sie sendet.
func beispiele(_ art: Nachricht.Art) -> [Nachricht] {
    switch art {
    case .diagnose:
        return [.diagnose(LeereDaten())]
    case .protokoll:
        return [.protokoll(ProtokollDaten(stufe: "info", text: "Route geladen: cockpit"))]
    case .haptik:
        return [.haptik(HaptikDaten(typ: .form, x: 412.5, y: 300)), .haptik(HaptikDaten(typ: .ausrichtung, x: 0, y: 0))]
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
/// Auf dem Draht stehen genau die Eigenschaften mit Wert: ein Kann-Feld ohne Wert fehlt dort (nie null).
func felder(_ draht: [String: Any], _ wert: Any, _ wo: String) throws -> [String: String] {
    var kann: [String: Bool] = [:]
    var mitWert: Set<String> = []
    for kind in Mirror(reflecting: wert).children {
        guard let name = kind.label else {
            throw Abbruch(description: "\(wo): Eigenschaft ohne Namen")
        }
        let inhalt = Mirror(reflecting: kind.value)
        let optional = inhalt.displayStyle == .optional
        kann[name] = optional
        if !optional || !inhalt.children.isEmpty {
            mitWert.insert(name)
        }
    }
    guard mitWert == Set(draht.keys) else {
        throw Abbruch(description: "\(wo): Eigenschaften mit Wert \(mitWert.sorted()), auf dem Draht \(draht.keys.sorted()); ein Kann-Feld ohne Wert fehlt dort (nie null), CodingKeys benennen nichts um")
    }
    var ergebnis: [String: String] = [:]
    for (name, inhalt) in draht {
        ergebnis[(kann[name] ?? false) ? name + "?" : name] = drahtTyp(inhalt)
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

/// Form eines Wegs aus allen Beispielen (die Buehne ohne TV wie mit, der Stift mit und ohne Pose): jedes
/// Feld hat in jedem Beispiel denselben Typ, ein Pflichtfeld steht in jedem, ein Kann-Feld in einem mit
/// und in einem ohne Wert.
func vereinige(_ formen: [[String: String]], _ wo: String) throws -> [String: String] {
    guard !formen.isEmpty else {
        throw Abbruch(description: "\(wo): kein Beispiel")
    }
    var ergebnis: [String: String] = [:]
    for form in formen {
        for (feld, typ) in form {
            if let bisher = ergebnis[feld], bisher != typ {
                throw Abbruch(description: "\(wo): Feld \(feld) ist in einem Beispiel \(bisher), in einem anderen \(typ)")
            }
            ergebnis[feld] = typ
        }
    }
    for feld in ergebnis.keys.sorted() {
        let fehlt = formen.contains { $0[feld] == nil }
        if feld.hasSuffix("?") && !fehlt {
            throw Abbruch(description: "\(wo): Kann-Feld \(feld) hat kein Beispiel ohne Wert; keins zeigt, dass es dann fehlt (nie null)")
        }
        if !feld.hasSuffix("?") && fehlt {
            throw Abbruch(description: "\(wo): Pflichtfeld \(feld) fehlt in einem Beispiel")
        }
    }
    return ergebnis
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
        ereignisse[art.rawValue] = try vereinige(felderJe, "Ereignis \(art.rawValue)")
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
        nachrichten[art.rawValue] = try vereinige(felderJe, "Nachricht \(art.rawValue)")
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
        "umschlag": try vereinige(umschlaege, "Umschlag"),
        "start": startFelder,
        "rollen": rollen,
        "ereignisse": ereignisse,
        "nachrichten": nachrichten,
        "werte": [
            "stiftEinstellung": StiftEinstellung.allCases.map { $0.rawValue },
            "squeezePhase": SqueezePhase.allCases.map { $0.rawValue },
            "haptikTyp": HaptikTyp.allCases.map { $0.rawValue },
        ],
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
