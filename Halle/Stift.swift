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
        Protokoll.shared.schreibe("Stift: an der Regie, Einstellung Doppeltipp \(einstellungText(UIPencilInteraction.preferredTapAction)), Squeeze \(einstellungText(UIPencilInteraction.preferredSqueezeAction))")
    }

    // MARK: UIPencilInteractionDelegate

    /// Doppeltipp: Einstellung zum Zeitpunkt des Tipps (der Nutzer kann sie jederzeit aendern), Punkt
    /// nur mit Pose.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        let roh = UIPencilInteraction.preferredTapAction
        let punkt = punktDerPose(tap.hoverPose)
        guard let einstellung = stiftEinstellung(roh) else {
            Protokoll.shared.schreibe("Stift: Doppeltipp mit Einstellung \(einstellungText(roh)), nicht im Vertrag, nicht gesendet")
            return
        }
        Protokoll.shared.schreibe("Stift: Doppeltipp \(einstellung.rawValue), Pose \(punkt == nil ? "nein" : "ja")")
        sende(.stiftDoppeltipp(StiftDoppeltippDaten(einstellung: einstellung, punkt: punkt)))
    }

    /// Squeeze: jede Phase geht an die Seite (die Tafel handelt bei `ended`); ins Protokoll `began`,
    /// `ended` und `cancelled`, die Meldungen `changed` dazwischen gezaehlt.
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        let roh = UIPencilInteraction.preferredSqueezeAction
        let punkt = punktDerPose(squeeze.hoverPose)
        guard let phase = squeezePhase(squeeze.phase) else {
            Protokoll.shared.schreibe("Stift: Squeeze mit Phase \(squeeze.phase.rawValue), nicht im Vertrag, nicht gesendet")
            return
        }
        guard let einstellung = stiftEinstellung(roh) else {
            Protokoll.shared.schreibe("Stift: Squeeze \(phase.rawValue) mit Einstellung \(einstellungText(roh)), nicht im Vertrag, nicht gesendet")
            return
        }
        let pose = "Pose \(punkt == nil ? "nein" : "ja")"
        switch phase {
        case .began:
            aenderungen = 0
            Protokoll.shared.schreibe("Stift: Squeeze began \(einstellung.rawValue), \(pose)")
        case .changed:
            aenderungen += 1
        case .ended, .cancelled:
            Protokoll.shared.schreibe("Stift: Squeeze \(phase.rawValue) \(einstellung.rawValue), \(pose), changed \(aenderungen)")
        }
        sende(.stiftSqueeze(StiftSqueezeDaten(phase: phase, einstellung: einstellung, punkt: punkt)))
    }

    // MARK: Haptik

    /// Nachricht `haptik` der Regie (Bruecke.empfange hat Rolle und Form geprueft): `form` an
    /// `pathCompleted(at:)`, `ausrichtung` an `alignmentOccurred(at:)`. Der Punkt kommt in CSS-px und geht
    /// in Punkten der Regie-WebView an UIKit, der Ansicht, an der der Generator haengt.
    func spiele(_ daten: HaptikDaten) {
        guard let web = ansicht?.webView else {
            return
        }
        let ort = CGPoint(x: CGFloat(daten.x) * web.pageZoom, y: CGFloat(daten.y) * web.pageZoom)
        switch daten.typ {
        case .form: haptik.pathCompleted(at: ort)
        case .ausrichtung: haptik.alignmentOccurred(at: ort)
        }
        Protokoll.shared.schreibe("Haptik \(daten.typ.rawValue)")
    }

    // MARK: Hilfen

    /// Punkt der Hover-Pose in CSS-px der Regie, oder `nil` ohne Pose (Stift nicht nah genug). Apple:
    /// `location` liegt im Koordinatenraum der Ansicht der Interaktion, hier der Regie-WebView; deren
    /// Inhalt beginnt an ihrer Kante (Scroll-Ansicht `.never`, kein Zoomen), ein CSS-px ist ein Punkt
    /// geteilt durch `pageZoom` (1, nie gesetzt).
    private func punktDerPose(_ pose: UIPencilHoverPose?) -> StiftPunkt? {
        guard let pose, let web = ansicht?.webView else {
            return nil
        }
        return StiftPunkt(x: Double(pose.location.x / web.pageZoom), y: Double(pose.location.y / web.pageZoom))
    }

    private func sende(_ ereignis: Ereignis) {
        guard let ansicht else {
            return
        }
        Bruecke.sende(ereignis, an: ansicht)
    }
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
