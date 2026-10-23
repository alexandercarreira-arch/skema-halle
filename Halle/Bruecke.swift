import Foundation
import WebKit

/// Vertrag mit der Web-App (Bauzettel 50, § 2.7). Die Quelle der Namen ist
/// `packages/protocol/src/huelle.ts` im privaten Repo; der Build legt sie als `huelle-vertrag.json` auf
/// den Worker. `werkzeug/vertrag.sh` liest die Zeilen mit `// vertrag:` und prueft sie dagegen.
/// Die Fähigkeiten gelten je Rolle: die Bühne fragt keine Diagnose an (nur die Regie hat das Tafelmenü).
/// T2 (Stift.swift) ergänzt `stift.doppeltipp`, `stift.squeeze`, `haptik`.
enum Vertrag {
    static let nummer = 1 // vertrag:nummer
    static let faehigkeitenRegie = ["wach", "buehne", "diagnose"] // vertrag:faehigkeiten
    static let faehigkeitenBuehne = ["wach", "buehne"] // vertrag:faehigkeiten
    /// Swift an Seite: `CustomEvent("skema-huelle", { detail: { typ, daten } })` am `window`.
    static let ereignisse = ["buehne", "diagnose"] // vertrag:ereignisse
    /// Seite an Swift: `window.webkit.messageHandlers.huelle.postMessage({ typ, daten })`.
    static let nachrichtenRegie = ["diagnose", "protokoll"] // vertrag:nachrichten
    static let nachrichtenBuehne = ["protokoll"] // vertrag:nachrichten

    static func faehigkeiten(_ rolle: Rolle) -> [String] {
        rolle == .regie ? faehigkeitenRegie : faehigkeitenBuehne
    }

    static func nachrichten(_ rolle: Rolle) -> [String] {
        rolle == .regie ? nachrichtenRegie : nachrichtenBuehne
    }
}

/// Die Bruecke selbst: das Skript `window.__skemaHuelle`, Ereignisse an die Seite und der Empfang der
/// Nachrichten. Nie ueber die Bruecke: Inhalte der Tafel, Eingaben, Dateien (Regel 5, § 2.7).
@MainActor
enum Bruecke {
    static let handler = "huelle"
    static let ereignis = "skema-huelle"

    /// Laeuft zu Dokumentbeginn im Hauptrahmen vor jedem Modul der Seite; mit App-Bound Domains nur auf
    /// der Worker-Domain. Eingefroren, die Seite kann es nicht ueberschreiben.
    static func skript(_ rolle: Rolle) -> WKUserScript {
        let werte: [String: Any] = [
            "vertrag": Vertrag.nummer,
            "rolle": rolle.rawValue,
            "bau": Bau.text,
            "xcode": Bau.xcode,
            "gebaut": Bau.gebaut,
            "faehigkeiten": Vertrag.faehigkeiten(rolle),
        ]
        let quelle = """
            (function () {
              if (window.__skemaHuelle) { return; }
              var huelle = \(json(werte));
              Object.freeze(huelle.faehigkeiten);
              Object.defineProperty(window, "__skemaHuelle", { value: Object.freeze(huelle), writable: false, configurable: false, enumerable: false });
            })();
            """
        return WKUserScript(source: quelle, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Prueft nach dem Laden, ob das Skript angekommen ist (RH50-2: App-Bound Domains falsch eingerichtet).
    static let pruefSkript = "(window.__skemaHuelle && window.__skemaHuelle.vertrag) || 0"

    /// Ereignis an eine Seite. Laedt die Seite gerade, geht es verloren; nach dem Laden schickt
    /// WebAnsicht den Stand von selbst.
    static func sende(_ typ: String, _ daten: [String: Any], an ansicht: WebAnsicht) {
        let detail = json(["typ": typ, "daten": daten])
        let name = ansicht.rolle.name
        ansicht.webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent(\"\(ereignis)\", { detail: \(detail) })); true") { _, fehler in
            if let fehler {
                Protokoll.shared.schreibe("\(name): Ereignis \(typ) nicht zugestellt: \(fehlerText(fehler))")
            }
        }
    }

    static func empfange(_ nachricht: WKScriptMessage, von ansicht: WebAnsicht) {
        let name = ansicht.rolle.name
        let rahmen = nachricht.frameInfo
        guard rahmen.isMainFrame, rahmen.securityOrigin.`protocol` == "https", rahmen.securityOrigin.host == Worker.host else {
            Protokoll.shared.schreibe("\(name): Nachricht von fremdem Rahmen verworfen (\(rahmen.securityOrigin.`protocol`)://\(rahmen.securityOrigin.host))")
            return
        }
        guard let roh = nachricht.body as? [String: Any], let typ = roh["typ"] as? String else {
            Protokoll.shared.schreibe("\(name): Nachricht ohne typ verworfen")
            return
        }
        guard Vertrag.nachrichten(ansicht.rolle).contains(typ) else {
            Protokoll.shared.schreibe("\(name): Nachricht \(kurz(typ, 40)) nicht im Vertrag, verworfen")
            return
        }
        let daten = roh["daten"] as? [String: Any] ?? [:]
        switch typ {
        case "protokoll":
            let stufe = daten["stufe"] as? String ?? "?"
            let text = daten["text"] as? String ?? ""
            Protokoll.shared.schreibe("\(name) [\(kurz(stufe, 12))] \(kurz(text, 500))")
        case "diagnose":
            sende("diagnose", Diagnose.daten(fuer: ansicht.rolle), an: ansicht)
        default:
            break
        }
    }
}

/// Wert als JSON-Text, der zugleich ein gueltiger JS-Ausdruck ist.
func json(_ wert: Any) -> String {
    guard JSONSerialization.isValidJSONObject(wert),
          let daten = try? JSONSerialization.data(withJSONObject: wert, options: [.sortedKeys]),
          let text = String(data: daten, encoding: .utf8)
    else {
        Protokoll.shared.schreibe("JSON nicht möglich, sende null")
        return "null"
    }
    return text
}
