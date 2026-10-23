import Foundation
import WebKit

/// Die Bruecke zur Web-App (Bauzettel 50, § 2.7): das Skript `window.__skemaHuelle`, Ereignisse an die
/// Seite und der Empfang der Nachrichten, in den Formen aus Vertrag.swift. Nie ueber die Bruecke: Inhalte
/// der Tafel, Eingaben, Dateien (Regel 5).
@MainActor
enum Bruecke {
    /// `window.webkit.messageHandlers.huelle`
    static let handler = "huelle"
    /// Typ des CustomEvent am `window`
    static let ereignisTyp = "skema-huelle"

    /// Laeuft zu Dokumentbeginn im Hauptrahmen vor jedem Modul der Seite; mit App-Bound Domains nur auf
    /// der Worker-Domain. Eingefroren, die Seite kann es nicht ueberschreiben.
    static func skript(_ rolle: Rolle) -> WKUserScript {
        let start = Vertrag.start(rolle, bau: Bau.text, xcode: Bau.xcode, gebaut: Bau.gebaut)
        let wert: String
        do {
            wert = try jsonText(start)
        } catch {
            Protokoll.shared.schreibe("\(rolle.name): Start nicht als JSON (\(error)), die Seite läuft wie im Browser")
            wert = "null"
        }
        let quelle = """
            (function () {
              var huelle = \(wert);
              if (window.__skemaHuelle || !huelle) { return; }
              Object.freeze(huelle.faehigkeiten);
              Object.defineProperty(window, "__skemaHuelle", { value: Object.freeze(huelle), writable: false, configurable: false, enumerable: false });
            })();
            """
        return WKUserScript(source: quelle, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    /// Prueft nach dem Laden, ob das Skript angekommen ist (RH50-2: App-Bound Domains falsch eingerichtet).
    static let pruefSkript = "(window.__skemaHuelle && window.__skemaHuelle.vertrag) || 0"

    /// Ereignis an eine Seite, nur wenn es zu ihrer Rolle gehoert (`Vertrag.ereignisse`; `stift.*` nur an die
    /// Regie, aus Stift.swift). Laedt die Seite gerade, geht es verloren; nach dem Laden schickt WebAnsicht
    /// `buehne` und `wach` von selbst.
    static func sende(_ ereignis: Ereignis, an ansicht: WebAnsicht) {
        let name = ansicht.rolle.name
        let art = ereignis.art.rawValue
        guard Vertrag.ereignisse(ansicht.rolle).contains(ereignis.art) else {
            Protokoll.shared.schreibe("\(name): Ereignis \(art) gehört nicht zu dieser Rolle, nicht gesendet")
            return
        }
        let detail: String
        do {
            detail = try ereignis.json()
        } catch {
            Protokoll.shared.schreibe("\(name): Ereignis \(art) nicht als JSON: \(error)")
            return
        }
        ansicht.webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent(\"\(ereignisTyp)\", { detail: \(detail) })); true") { _, fehler in
            if let fehler {
                Protokoll.shared.schreibe("\(name): Ereignis \(art) nicht zugestellt: \(fehlerText(fehler))")
            }
        }
    }

    /// Nachricht der Seite: nur aus dem Hauptrahmen der Worker-Domain, nur `{ art, daten }` mit den Typen
    /// des Vertrags, nur was diese Rolle senden darf (`Vertrag.nachrichten`; `haptik` nur aus der Regie,
    /// dort spielt sie Stift.swift).
    static func empfange(_ nachricht: WKScriptMessage, von ansicht: WebAnsicht) {
        let name = ansicht.rolle.name
        let rahmen = nachricht.frameInfo
        guard rahmen.isMainFrame, rahmen.securityOrigin.`protocol` == "https", rahmen.securityOrigin.host == Worker.host else {
            Protokoll.shared.schreibe("\(name): Nachricht von fremdem Rahmen verworfen (\(rahmen.securityOrigin.`protocol`)://\(rahmen.securityOrigin.host))")
            return
        }
        let gelesen: Nachricht
        do {
            gelesen = try Nachricht.lies(nachricht.body)
        } catch {
            // auch eine haptik mit anderem typ als form oder ausrichtung (Vertrag werte.haptikTyp)
            Protokoll.shared.schreibe("\(name): Nachricht verworfen, \(kurz(lesefehlerText(error)))")
            return
        }
        guard Vertrag.nachrichten(ansicht.rolle).contains(gelesen.art) else {
            Protokoll.shared.schreibe("\(name): Nachricht \(gelesen.art.rawValue) kommt nicht aus dieser Rolle, verworfen")
            return
        }
        switch gelesen {
        case .protokoll(let daten):
            Protokoll.shared.schreibe("\(name) [\(kurz(daten.stufe, 12))] \(kurz(daten.text, 500))")
        case .diagnose:
            sende(.diagnose(Diagnose.daten()), an: ansicht)
        case .haptik(let daten):
            guard let stift = ansicht.stift else {
                Protokoll.shared.schreibe("\(name): Haptik ohne Stift an dieser Ansicht, verworfen")
                return
            }
            stift.spiele(daten)
        }
    }
}
