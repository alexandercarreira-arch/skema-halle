import Darwin
import Foundation
import UIKit
import os

/// Was der Testbau ueber sich weiss, aus der Info.plist (bauen.sh setzt HuelleGebaut und HuelleXcode).
enum Bau {
    static let version = Bau.info("CFBundleShortVersionString")
    static let nummer = Bau.info("CFBundleVersion")
    static let xcode = Bau.info("HuelleXcode")
    /// Zeitpunkt des Baus in UTC, ISO 8601 auf die Sekunde (z. B. `2026-10-23T09:00:00Z`); bauen.sh setzt
    /// und prueft ihn am Archiv. Vertrag der Bruecke: die Web-App liest ihn mit `Date.parse` und verwirft
    /// sonst den ganzen Start (`leseHuelleStart`), die Seite liefe wie im Browser. `lokal` steht hier nur
    /// ohne bauen.sh. Der Upload-Job laedt im selben Lauf hoch.
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

/// Inhalt der Ereignisse `buehne`, `wach` und `diagnose` an die Seite (Bauzettel 50, § 2.7, § 3.1
/// Diagnose), in den Formen aus Vertrag.swift. Nur Rohwerte; Darstellung und Bewertung liegen in der
/// Web-App (Abschnitt „Hülle"). Was der Vertrag nicht nennt (Netz, Neuladungen, Brücke in der Seite),
/// steht im nativen Protokoll, das `diagnose` mitbringt.
@MainActor
enum Diagnose {
    /// Antwort auf die Nachricht `diagnose` der Regie.
    static func daten() -> DiagnoseDaten {
        let geraet = UIDevice.current
        return DiagnoseDaten(
            regieSzenen: Zustand.shared.regieSzenen,
            speicherMb: speicherDerAppMb(),
            waerme: waermeText(ProcessInfo.processInfo.thermalState),
            akku: akkuProzent(geraet.batteryLevel),
            laden: ladenText(geraet.batteryState),
            protokoll: Protokoll.shared.letzte(200)
        )
    }

    /// Stand der TV-Szene; ohne TV `BuehneDaten.ohneTv`, ohne Modus ein leerer Text, nie `null`.
    static func buehne() -> BuehneDaten {
        guard let szene = Zustand.shared.tvSzene else {
            return .ohneTv
        }
        let bildschirm = szene.screen
        return BuehneDaten(
            verbunden: true,
            breite: Double(bildschirm.bounds.width),
            hoehe: Double(bildschirm.bounds.height),
            faktor: Double(bildschirm.scale),
            modus: bildschirm.currentMode.map { modusText($0) } ?? "",
            modi: bildschirm.availableModes.map { modusText($0) },
            overscan: overscanText(bildschirm.overscanCompensation),
            zustand: zustandText(szene.activationState)
        )
    }

    /// Ob Swift den Bildschirm wach haelt.
    static func wach() -> WachDaten {
        WachDaten(aktiv: Zustand.shared.wach)
    }
}

/// Speicher der App in MB (`phys_footprint`, so zaehlt auch das System); -1, wenn der Kern ihn nicht nennt.
func speicherDerAppMb() -> Double {
    var info = task_vm_info_data_t()
    var anzahl = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let ergebnis = withUnsafeMutablePointer(to: &info) { zeiger in
        zeiger.withMemoryRebound(to: integer_t.self, capacity: Int(anzahl)) { roh in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), roh, &anzahl)
        }
    }
    guard ergebnis == KERN_SUCCESS else {
        return -1
    }
    return (Double(info.phys_footprint) / 1_048_576).rounded()
}

/// `UIDevice.batteryLevel` (0 bis 1, -1 unbekannt) in Prozent, -1 unbekannt.
func akkuProzent(_ stand: Float) -> Int {
    stand < 0 ? -1 : Int((stand * 100).rounded())
}

func ladenText(_ zustand: UIDevice.BatteryState) -> String {
    switch zustand {
    case .unknown: return "unknown"
    case .unplugged: return "unplugged"
    case .charging: return "charging"
    case .full: return "full"
    @unknown default: return "unknown"
    }
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

/// Akku fuer das Protokoll, mit den Werten der Diagnose.
@MainActor
func akkuText() -> String {
    let geraet = UIDevice.current
    let prozent = akkuProzent(geraet.batteryLevel)
    return "\(prozent < 0 ? "unbekannt" : "\(prozent) %"), \(ladenText(geraet.batteryState))"
}

/// Bildschirm der TV-Szene fuer das Protokoll.
@MainActor
func bildschirmText(_ bildschirm: UIScreen) -> String {
    let modi = bildschirm.availableModes.map { modusText($0) }.joined(separator: ", ")
    return "bounds \(Int(bildschirm.bounds.width))x\(Int(bildschirm.bounds.height)) scale \(bildschirm.scale), Modus \(bildschirm.currentMode.map { modusText($0) } ?? "keiner"), Modi [\(modi)], Overscan \(overscanText(bildschirm.overscanCompensation))"
}
