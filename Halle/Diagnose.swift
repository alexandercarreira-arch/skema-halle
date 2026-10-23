import Foundation
import UIKit
import os

/// Was der Testbau ueber sich weiss, aus der Info.plist (bauen.sh setzt HuelleGebaut und HuelleXcode).
enum Bau {
    static let version = Bau.info("CFBundleShortVersionString")
    static let nummer = Bau.info("CFBundleVersion")
    static let xcode = Bau.info("HuelleXcode")
    /// Zeitpunkt des Baus in UTC, ISO 8601. Der Upload-Job laedt im selben Lauf hoch.
    static let gebaut = Bau.info("HuelleGebaut")
    /// „0.1 (17.1)"
    static let text = "\(version) (\(nummer))"

    /// TestFlight: „Each build is available to test for up to 90 days, starting from the day the developer
    /// uploads their build" (Bauzettel 50, § 2.3). Gerechnet ab dem Bau, der im selben Lauf hochgeht.
    static var giltBis: String? {
        let format = ISO8601DateFormatter()
        guard let datum = format.date(from: gebaut) else {
            return nil
        }
        return format.string(from: datum.addingTimeInterval(90 * 24 * 60 * 60))
    }

    private static func info(_ schluessel: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: schluessel) as? String ?? "?"
    }
}

/// Inhalt der Ereignisse `diagnose` und `buehne` an die Seite (Bauzettel 50, § 2.7, § 3.1 Diagnose).
/// Nur Rohwerte; Darstellung und Bewertung liegen in der Web-App (Abschnitt „Hülle").
@MainActor
enum Diagnose {
    /// Antwort auf die Nachricht `diagnose` der Regie.
    static func daten(fuer rolle: Rolle) -> [String: Any] {
        let zustand = Zustand.shared
        return [
            "bau": Bau.text,
            "xcode": Bau.xcode,
            "gebaut": Bau.gebaut,
            "giltBis": oderNull(Bau.giltBis),
            "vertrag": Vertrag.nummer,
            "faehigkeiten": Vertrag.faehigkeiten(rolle),
            "ipados": UIDevice.current.systemVersion,
            "regieSzenen": zustand.regieSzenen,
            "buehne": buehne(),
            "wach": zustand.wach,
            "speicherFreiMB": Int(os_proc_available_memory() / 1_048_576),
            "waerme": waermeText(ProcessInfo.processInfo.thermalState),
            "akku": akkuText(),
            "netz": Netz.shared.text,
            "neuladungen": zustand.neuladungen,
            "brueckeInSeite": [
                "regie": oderNull(zustand.regieWeb?.brueckeInSeite),
                "buehne": oderNull(zustand.buehneWeb?.brueckeInSeite),
            ],
            "protokoll": Protokoll.shared.letzte(200),
        ]
    }

    /// Stand der TV-Szene; ohne TV sind die Werte des Bildschirms `null`.
    static func buehne() -> [String: Any] {
        let zustand = Zustand.shared
        guard let szene = zustand.tvSzene else {
            return [
                "verbunden": false, "breite": NSNull(), "hoehe": NSNull(), "faktor": NSNull(), "modus": NSNull(),
                "modi": [String](), "overscan": NSNull(), "zustand": "nicht verbunden", "wach": zustand.wach,
            ]
        }
        let bildschirm = szene.screen
        return [
            "verbunden": true,
            "breite": Int(bildschirm.bounds.width),
            "hoehe": Int(bildschirm.bounds.height),
            "faktor": Double(bildschirm.scale),
            "modus": oderNull(bildschirm.currentMode.map { modusText($0) }),
            "modi": bildschirm.availableModes.map { modusText($0) },
            "overscan": overscanText(bildschirm.overscanCompensation),
            "zustand": zustandText(szene.activationState),
            "wach": zustand.wach,
        ]
    }
}

/// JSON kennt kein `nil`: fehlende Werte gehen als `null` an die Seite.
func oderNull(_ wert: Any?) -> Any {
    wert ?? NSNull()
}

@MainActor
func modusText(_ modus: UIScreenMode) -> String {
    "\(Int(modus.size.width))x\(Int(modus.size.height))"
}

func zustandText(_ zustand: UIScene.ActivationState) -> String {
    switch zustand {
    case .unattached: return "unattached"
    case .foregroundActive: return "foregroundActive"
    case .foregroundInactive: return "foregroundInactive"
    case .background: return "background"
    @unknown default: return "unbekannt"
    }
}

func overscanText(_ art: UIScreen.OverscanCompensation) -> String {
    switch art {
    case .scale: return "scale"
    case .insetBounds: return "insetBounds"
    case .none: return "none"
    @unknown default: return "unbekannt"
    }
}

func waermeText(_ zustand: ProcessInfo.ThermalState) -> String {
    switch zustand {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unbekannt"
    }
}

@MainActor
func akkuText() -> String {
    let geraet = UIDevice.current
    let stand = geraet.batteryLevel < 0 ? "unbekannt" : "\(Int((geraet.batteryLevel * 100).rounded())) %"
    let laden: String
    switch geraet.batteryState {
    case .charging: laden = "lädt"
    case .full: laden = "voll"
    case .unplugged: laden = "nicht angeschlossen"
    case .unknown: laden = "unbekannt"
    @unknown default: laden = "unbekannt"
    }
    return "\(stand), \(laden)"
}

/// Bildschirm der TV-Szene fuer das Protokoll.
@MainActor
func bildschirmText(_ bildschirm: UIScreen) -> String {
    let modi = bildschirm.availableModes.map { modusText($0) }.joined(separator: ", ")
    return "bounds \(Int(bildschirm.bounds.width))x\(Int(bildschirm.bounds.height)) scale \(bildschirm.scale), Modus \(bildschirm.currentMode.map { modusText($0) } ?? "keiner"), Modi [\(modi)], Overscan \(overscanText(bildschirm.overscanCompensation))"
}
