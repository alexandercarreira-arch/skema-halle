import UIKit
import WebKit

/// Stift und Haptik der Regie (Bauzettel 50, § 2.7, § 3.1 Doppeltipp, Squeeze, Haptik; Testbau T2). Haengt
/// nur an der Regie-WebView (WebAnsicht). Swift reicht Rohwerte weiter, in den Formen aus Vertrag.swift:
/// die Einstellung des Nutzers als Name des Falls von `UIPencilPreferredAction`, die Phase der Squeeze und
/// den Punkt der Hover-Pose in CSS-px der Regie. Was die Tafel daraus macht, entscheidet die Web-App.
/// Haptik kommt als Nachricht der Seite und geht an `UICanvasFeedbackGenerator`; fuehlbar ist sie nur mit
/// Apple Pencil Pro an einem passenden iPad. Mindest-iPadOS 26.0, daher ohne `@available` fuer 17.5.
@MainActor
final class Stift: NSObject, UIPencilInteractionDelegate {
    private weak var ansicht: WebAnsicht?
    private let haptik: UICanvasFeedbackGenerator
    /// Meldungen `changed` seit `began`: eine Protokollzeile je Squeeze statt einer je Meldung.
    private var aenderungen = 0

    init(_ ansicht: WebAnsicht) {
        self.ansicht = ansicht
        haptik = UICanvasFeedbackGenerator(view: ansicht.webView)
        super.init()
        ansicht.webView.addInteraction(UIPencilInteraction(delegate: self))
        // Apple (UIFeedbackGenerator.prepare()): vor dem Ereignis vorbereiten, das Feedback ausloest, damit
        // es mit wenig Verzug kommt; nach jedem Ausloesen wieder (spiele).
        haptik.prepare()
        Protokoll.shared.schreibe("Stift: an der Regie, Einstellung Doppeltipp \(einstellungText(UIPencilInteraction.preferredTapAction)), Squeeze \(einstellungText(UIPencilInteraction.preferredSqueezeAction))")
    }

    // MARK: UIPencilInteractionDelegate

    /// Doppeltipp: Einstellung zum Zeitpunkt des Tipps (der Nutzer kann sie jederzeit aendern), Punkt
    /// nur mit Pose.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        let roh = UIPencilInteraction.preferredTapAction
        let pose = poseDerRegie(tap.hoverPose)
        guard let einstellung = stiftEinstellung(roh) else {
            Protokoll.shared.schreibe("Stift: Doppeltipp mit Einstellung \(einstellungText(roh)), nicht im Vertrag, nicht gesendet")
            return
        }
        Protokoll.shared.schreibe("Stift: Doppeltipp \(einstellung.rawValue), \(pose.text)")
        sende(.stiftDoppeltipp(StiftDoppeltippDaten(einstellung: einstellung, punkt: pose.punkt)))
    }

    /// Squeeze: jede Phase geht an die Seite (die Tafel handelt bei `ended`); ins Protokoll `began`,
    /// `ended` und `cancelled`, die Meldungen `changed` dazwischen gezaehlt.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        let roh = UIPencilInteraction.preferredSqueezeAction
        let pose = poseDerRegie(squeeze.hoverPose)
        guard let phase = squeezePhase(squeeze.phase) else {
            Protokoll.shared.schreibe("Stift: Squeeze mit Phase \(squeeze.phase.rawValue), nicht im Vertrag, nicht gesendet")
            return
        }
        guard let einstellung = stiftEinstellung(roh) else {
            Protokoll.shared.schreibe("Stift: Squeeze \(phase.rawValue) mit Einstellung \(einstellungText(roh)), nicht im Vertrag, nicht gesendet")
            return
        }
        switch phase {
        case .began:
            aenderungen = 0
            Protokoll.shared.schreibe("Stift: Squeeze began \(einstellung.rawValue), \(pose.text)")
        case .changed:
            aenderungen += 1
        case .ended, .cancelled:
            Protokoll.shared.schreibe("Stift: Squeeze \(phase.rawValue) \(einstellung.rawValue), \(pose.text), changed \(aenderungen)")
        }
        sende(.stiftSqueeze(StiftSqueezeDaten(phase: phase, einstellung: einstellung, punkt: pose.punkt)))
    }

    // MARK: Haptik

    /// Nachricht `haptik` der Regie (Bruecke.empfange hat Rolle und Form geprueft): `form` an
    /// `pathCompleted(at:)`, `ausrichtung` an `alignmentOccurred(at:)`. Der Punkt kommt in CSS-px der Regie
    /// und geht in Punkten der Regie-WebView an UIKit, der Ansicht, an der der Generator haengt
    /// (SeitenLage.punkt, die Umkehrung von SeitenLage.cssPx).
    func spiele(_ daten: HaptikDaten) {
        guard let web = ansicht?.webView else {
            return
        }
        let lage = SeitenLage(web)
        guard let ort = lage.punkt(daten.x, daten.y) else {
            Protokoll.shared.schreibe("Haptik \(daten.typ.rawValue) nicht umrechenbar (\(lage.text)), nicht gespielt")
            return
        }
        switch daten.typ {
        case .form: haptik.pathCompleted(at: ort)
        case .ausrichtung: haptik.alignmentOccurred(at: ort)
        }
        // Apple: nach dem Ausloesen kehrt die Taptic Engine in den Ruhezustand zurueck; kann in den
        // naechsten Sekunden weiteres Feedback folgen, sofort wieder vorbereiten.
        haptik.prepare()
        Protokoll.shared.schreibe("Haptik \(daten.typ.rawValue)")
    }

    // MARK: Hilfen

    /// Punkt der Hover-Pose in CSS-px der Regie (`nil` ohne Pose, Stift nicht nah genug) und der Text fuer
    /// das Protokoll: Pose in Punkten der WebView und in CSS-px, dazu zoomScale, contentOffset und pageZoom,
    /// damit G11 die Umrechnung (SeitenLage) am Geraet zeigt. Apple: `location` liegt im Koordinatenraum
    /// der Ansicht der Interaktion, hier der Regie-WebView.
    private func poseDerRegie(_ pose: UIPencilHoverPose?) -> (punkt: StiftPunkt?, text: String) {
        guard let web = ansicht?.webView else {
            return (nil, "ohne Regie-WebView")
        }
        let lage = SeitenLage(web)
        guard let pose else {
            return (nil, "Pose nein, \(lage.text)")
        }
        let ort = pose.location
        guard let punkt = lage.cssPx(ort) else {
            return (nil, "Pose \(zahl(ort.x)),\(zahl(ort.y)) pt nicht umrechenbar, \(lage.text)")
        }
        return (punkt, "Pose \(zahl(ort.x)),\(zahl(ort.y)) pt = \(zahl(punkt.x)),\(zahl(punkt.y)) css, \(lage.text)")
    }

    private func sende(_ ereignis: Ereignis) {
        guard let ansicht else {
            return
        }
        Bruecke.sende(ereignis, an: ansicht)
    }
}

/// Lage der Seite in der Regie-WebView und die Umrechnung zwischen Punkten der WebView (UIKit: Ort der
/// Hover-Pose, Ort der Haptik) und CSS-px der Regie, also `clientX`/`clientY` der Seite (so rechnet die
/// Tafel, auch fuer die Nachricht `haptik`); eine Stelle fuer beide Richtungen.
///
/// WebKit auf iOS (Quellen auf main, 23.10.2026): Client-Koordinaten beginnen an der linken oberen Ecke
/// des sichtbaren, nicht verdeckten Ausschnitts, nicht am Layout-Viewport. `LocalFrameView::
/// documentToClientOffset` nimmt `visibleContentRect()`, auf iOS `unobscuredContentRect` (den
/// Layout-Viewport nur als Quirk fuer discord.com, WebKit fd191036e4, Bug 306779), und teilt durch
/// `pageZoomFactor * frameScaleFactor`; `frameScaleFactor` ist 1, weil iOS das Skalieren an die
/// Scroll-Ansicht delegiert (`Frame::frameScaleFactor`), `pageZoom` wirkt wie CSS `zoom` auf die ganze
/// Seite (`WKWebView.pageZoom` setzt `pageZoomFactor`). Den Ausschnitt rechnet WKWebView aus ihren eigenen
/// Grenzen ohne die verdeckten Raender in Inhaltskoordinaten um (`_createVisibleContentRectUpdate`), die
/// Inhaltsansicht ist die Zoom-Ansicht der Scroll-Ansicht (Faktor `zoomScale`, Lage `contentOffset`).
/// `contentOffset` verschiebt Punkt und Ausschnitt gleich und faellt heraus:
///
///     css = (punkt - rand) / (zoomScale * pageZoom)        punkt = css * zoomScale * pageZoom + rand
///
/// `rand`: verdeckte Raender oben und links (`obscuredContentInsets`, in der Huelle nie gesetzt, also 0;
/// die Sicherheitsraender zaehlen nicht, weil die Scroll-Ansicht sie nicht anwendet, `.never`). Annahme
/// fuer G11: zoomScale 1 und pageZoom 1 (Viewport `width=device-width, initial-scale=1`, Zoomen aus),
/// dann ist css gleich punkt, bei jedem contentOffset; das Protokoll zeigt die drei Werte je Squeeze und
/// Doppeltipp.
@MainActor
struct SeitenLage {
    let zoomScale: CGFloat
    let contentOffset: CGPoint
    let pageZoom: CGFloat
    let rand: UIEdgeInsets

    init(_ web: WKWebView) {
        zoomScale = web.scrollView.zoomScale
        contentOffset = web.scrollView.contentOffset
        pageZoom = web.pageZoom
        rand = web.obscuredContentInsets
    }

    /// Punkte der WebView je CSS-px; `nil`, wenn das Produkt nicht endlich und positiv ist.
    private var skala: CGFloat? {
        let faktor = zoomScale * pageZoom
        return faktor.isFinite && faktor > 0 ? faktor : nil
    }

    /// Punkt der WebView in CSS-px der Regie.
    func cssPx(_ punkt: CGPoint) -> StiftPunkt? {
        guard let faktor = skala else {
            return nil
        }
        return StiftPunkt(x: Double((punkt.x - rand.left) / faktor), y: Double((punkt.y - rand.top) / faktor))
    }

    /// CSS-px der Regie als Punkt der WebView.
    func punkt(_ x: Double, _ y: Double) -> CGPoint? {
        guard let faktor = skala else {
            return nil
        }
        return CGPoint(x: CGFloat(x) * faktor + rand.left, y: CGFloat(y) * faktor + rand.top)
    }

    var text: String {
        "zoomScale \(zahl(zoomScale)), contentOffset \(zahl(contentOffset.x)),\(zahl(contentOffset.y)), pageZoom \(zahl(pageZoom))"
    }
}

/// Zahl fuer das Protokoll, so kurz wie noetig (1, 412.5, -24).
func zahl(_ wert: Double) -> String {
    String(format: "%g", wert)
}

/// `UIPencilPreferredAction` als Name des Falls (Vertrag `werte.stiftEinstellung`); `nil` fuer einen Fall,
/// den der Vertrag nicht kennt.
func stiftEinstellung(_ aktion: UIPencilPreferredAction) -> StiftEinstellung? {
    switch aktion {
    case .ignore: return .ignore
    case .switchEraser: return .switchEraser
    case .switchPrevious: return .switchPrevious
    case .showColorPalette: return .showColorPalette
    case .showInkAttributes: return .showInkAttributes
    case .showContextualPalette: return .showContextualPalette
    case .runSystemShortcut: return .runSystemShortcut
    @unknown default: return nil
    }
}

/// `UIPencilInteraction.Phase` als Name des Falls (Vertrag `werte.squeezePhase`); `nil` fuer einen Fall,
/// den der Vertrag nicht kennt.
func squeezePhase(_ phase: UIPencilInteraction.Phase) -> SqueezePhase? {
    switch phase {
    case .began: return .began
    case .changed: return .changed
    case .ended: return .ended
    case .cancelled: return .cancelled
    @unknown default: return nil
    }
}

/// Einstellung fuer das Protokoll, auch fuer einen Fall ausserhalb des Vertrags (dann mit Rohwert).
func einstellungText(_ aktion: UIPencilPreferredAction) -> String {
    stiftEinstellung(aktion)?.rawValue ?? "unbekannt (\(aktion.rawValue))"
}
