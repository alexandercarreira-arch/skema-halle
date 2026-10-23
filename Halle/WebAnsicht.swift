import UIKit
import WebKit

/// Die einzige Adresse der Web-App: die erste Domain unter `WKAppBoundDomains` in der Info.plist
/// (eine Quelle fuer Swift, App-Bound Domains und `werkzeug/vertrag.sh`). In der TestFlight-Phase laedt
/// die Huelle die Web-App vom Worker (Bauzettel 50, § 2.2); `huelle.ts` nimmt keine feste Origin an.
enum Worker {
    static let host: String = (Bundle.main.object(forInfoDictionaryKey: "WKAppBoundDomains") as? [String])?.first ?? ""

    static func adresse(_ pfad: String) -> URL? {
        URL(string: "https://\(host)\(pfad)")
    }

    /// Grund, eine Navigation abzulehnen, oder `nil`. Regie: jeder Pfad der Worker-Domain ausser `/tv`
    /// und `/handy` (die App macht jeden Seitenwechsel als echte Navigation, `App.tsx`; ein Filter auf
    /// `/cockpit` sperrte die Startseite). Buehne: nur `/tv`. Andere Hosts und Schemata (`blob:`,
    /// `mailto:`, `data:`) nie; Unterrahmen nur `about:` oder die Worker-Domain.
    static func ablehnung(_ url: URL?, rolle: Rolle, hauptrahmen: Bool) -> String? {
        guard let url, let schema = url.scheme?.lowercased() else {
            return "ohne Adresse"
        }
        if !hauptrahmen, schema == "about" {
            return nil
        }
        guard schema == "https" else {
            return "Schema \(schema)"
        }
        guard url.host()?.lowercased() == host else {
            return "fremder Host"
        }
        guard hauptrahmen else {
            return nil
        }
        let pfad = url.path()
        let istTv = pfad == "/tv" || pfad.hasPrefix("/tv/")
        let istHandy = pfad == "/handy" || pfad.hasPrefix("/handy/")
        switch rolle {
        case .regie: return istTv || istHandy ? "Pfad \(pfad) gehört nicht in die Regie" : nil
        case .buehne: return istTv ? nil : "Pfad \(pfad) gehört nicht auf die Bühne"
        }
    }
}

/// Eine der beiden WKWebViews (Bauzettel 50, § 4). Einstellungen wie in der Probe gemessen
/// (Standard-Datenspeicher, Medien ohne Geste, Inline, Element-Vollbild, Scroll-Ansicht `.never`, kein
/// Federn, kein Zoomen), dazu `limitsNavigationsToAppBoundDomains` fuer den Dienst (§ 2.2).
@MainActor
final class WebAnsicht: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIScrollViewDelegate {
    let rolle: Rolle
    let webView: WKWebView
    /// Das letzte Laden scheiterte am Netz. Neu geladen wird bei jeder Pfadmeldung „verbunden"
    /// (Netz.swift) und wenn die Regie wieder nach vorn kommt (App.swift `sceneWillEnterForeground`).
    private var wartetAufNetz = false

    init(rolle: Rolle) {
        self.rolle = rolle
        let inhalt = WKUserContentController()
        inhalt.addUserScript(Bruecke.skript(rolle))
        let konfiguration = WKWebViewConfiguration()
        konfiguration.websiteDataStore = WKWebsiteDataStore.default()
        konfiguration.userContentController = inhalt
        konfiguration.limitsNavigationsToAppBoundDomains = true
        konfiguration.mediaTypesRequiringUserActionForPlayback = []
        konfiguration.allowsInlineMediaPlayback = true
        konfiguration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: konfiguration)
        super.init()
        inhalt.add(SchwacherBote(self), name: Bruecke.handler)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = true
        // Kein Vorschau-Menue auf Links: es boete „In Safari öffnen" an (Huelle ohne Links nach Safari).
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.scrollView.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(netzVerbunden), name: Netz.verbunden, object: nil)
        lade()
    }

    func lade() {
        guard let url = Worker.adresse(rolle.pfad) else {
            Protokoll.shared.schreibe("\(rolle.name): keine Adresse (WKAppBoundDomains leer?)")
            return
        }
        Protokoll.shared.schreibe("\(rolle.name) lädt \(url.absoluteString)")
        wartetAufNetz = false
        webView.load(URLRequest(url: url))
    }

    @objc private func netzVerbunden() {
        ladeNeuWennWartet("Netz verbunden")
    }

    /// Laedt neu, wenn das letzte Laden am Netz scheiterte; sonst nichts. Anlaesse: jede Pfadmeldung
    /// „verbunden" und die Regie wieder vorn. Scheitert das Laden erneut, wartet die Ansicht auf den
    /// naechsten Anlass; kein Timer (Regel 2).
    func ladeNeuWennWartet(_ anlass: String) {
        guard wartetAufNetz else {
            return
        }
        Protokoll.shared.schreibe("\(rolle.name): \(anlass), lade nach Ladefehler neu")
        lade()
    }

    /// Bildrate der Seite fuer den Minutenbericht: zaehlt eine Sekunde lang `requestAnimationFrame` in
    /// einer eigenen Skript-Welt (die Seite sieht davon nichts). Ohne Fenster (TV ab) bleibt sie bei 0.
    func meldeBildrate() {
        let name = rolle.name
        webView.callAsyncJavaScript(WebAnsicht.bildrateSkript, arguments: [:], in: nil, in: .defaultClient) { ergebnis in
            switch ergebnis {
            case .success(let wert):
                let werte = wert as? [String: Any] ?? [:]
                let raf = werte["raf"] as? Int ?? -1
                let sichtbar = werte["sichtbar"] as? String ?? "?"
                Protokoll.shared.schreibe("Minute \(name): rAF \(raf)/s, \(sichtbar)")
            case .failure(let fehler):
                Protokoll.shared.schreibe("Minute \(name): Bildrate nicht messbar: \(fehlerText(fehler))")
            }
        }
    }

    private static let bildrateSkript = """
        return await new Promise(function (fertig) {
          var bilder = 0;
          var aus = false;
          function zaehle() { if (aus) { return; } bilder += 1; window.requestAnimationFrame(zaehle); }
          window.requestAnimationFrame(zaehle);
          window.setTimeout(function () { aus = true; fertig({ raf: bilder, sichtbar: document.visibilityState }); }, 1000);
        });
        """

    // MARK: UIScrollViewDelegate

    /// Zoomen aus wie in der Probe: die erste Pinch-Geste schaltet die Erkennung ab.
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        scrollView.pinchGestureRecognizer?.isEnabled = false
    }

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Bruecke.empfange(message, von: self)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let adresse = kurz(url?.absoluteString ?? "?")
        if navigationAction.shouldPerformDownload {
            Protokoll.shared.schreibe("\(rolle.name): Herunterladen abgelehnt: \(adresse)")
            decisionHandler(.cancel)
            return
        }
        let hauptrahmen = navigationAction.targetFrame?.isMainFrame ?? true
        if let grund = Worker.ablehnung(url, rolle: rolle, hauptrahmen: hauptrahmen) {
            Protokoll.shared.schreibe("\(rolle.name): Navigation abgelehnt (\(grund)): \(adresse)")
            decisionHandler(.cancel)
            return
        }
        if hauptrahmen {
            Protokoll.shared.schreibe("\(rolle.name): Navigation \(adresse)")
        }
        decisionHandler(.allow)
    }

    /// Was die WebView nicht anzeigen kann, wuerde ein Herunterladen; die Huelle laedt nichts herunter.
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            Protokoll.shared.schreibe("\(rolle.name): Antwort ohne Anzeige abgelehnt (\(navigationResponse.response.mimeType ?? "?")): \(kurz(navigationResponse.response.url?.absoluteString ?? "?"))")
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Protokoll.shared.schreibe("\(rolle.name) geladen: \(kurz(webView.url?.absoluteString ?? "?"))")
        wartetAufNetz = false
        // Nach jedem Laden den Stand, auf den die Seite wartet (Vertrag: buehne und wach nach didFinish)
        Bruecke.sende(.buehne(Diagnose.buehne()), an: self)
        Bruecke.sende(.wach(Diagnose.wach()), an: self)
        let name = rolle.name
        webView.evaluateJavaScript(Bruecke.pruefSkript) { wert, _ in
            let vertrag = wert as? Int ?? 0
            Protokoll.shared.schreibe("\(name): Brücke in der Seite \(vertrag > 0 ? "ja, Vertrag \(vertrag)" : "nein")")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        scheitere("Fehler beim Laden", error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        scheitere("Fehler beim Start der Navigation", error)
    }

    private func scheitere(_ was: String, _ fehler: Error) {
        let netz = Netz.istNetzFehler(fehler)
        if netz {
            wartetAufNetz = true
        }
        Protokoll.shared.schreibe("\(rolle.name) \(was): \(fehlerText(fehler))\(netz ? ", warte auf Netzmeldung oder Regie vorn" : "")")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Zustand.shared.neuladungen += 1
        Protokoll.shared.schreibe("\(rolle.name): Web-Inhalt beendet, lade neu (Neuladungen gesamt \(Zustand.shared.neuladungen))")
        if webView.url == nil {
            lade()
        } else {
            webView.reload()
        }
    }

    // MARK: WKUIDelegate

    /// `target=_blank` und `window.open` oeffnen nichts.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        Protokoll.shared.schreibe("\(rolle.name): neues Fenster verlangt, nicht geöffnet: \(kurz(navigationAction.request.url?.absoluteString ?? "?"))")
        return nil
    }
}

/// Haelt den Empfaenger der Nachrichten schwach; `WKUserContentController` haelt seine Boten stark.
@MainActor
private final class SchwacherBote: NSObject, WKScriptMessageHandler {
    weak var ziel: WKScriptMessageHandler?

    init(_ ziel: WKScriptMessageHandler) {
        self.ziel = ziel
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        ziel?.userContentController(userContentController, didReceive: message)
    }
}
