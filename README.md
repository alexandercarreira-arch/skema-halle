# skema-halle

Native Hülle „SLSHM Coach“ der Hallen-App des SLSHM für das Hallen-iPad (iPad Air 11", iPadOS 26.5,
Apple Pencil Pro). Sie zeigt die Web-App am iPad als **Regie** (`/cockpit`) und über Apples Szene für
externe Displays von selbst randlos am TV als **Bühne** (`/tv`). Ausbau der Probe S1-H
(`alexandercarreira-arch/skema-buehnenprobe`), Bauzettel im privaten Repo: `docs/plan/50-bauzettel-huelle.md`.

## Was hier liegt und was nicht

- **Kein Web-Code.** Die Web-App liegt in einem privaten Repo. Bis die App fertig ist, lädt die Hülle sie
  vom Worker (`WKAppBoundDomains` in `Halle/Info.plist`, die einzige Stelle der Adresse); jede
  Veröffentlichung dort gilt beim nächsten Kaltstart.
- **Schlichtes UIKit in Swift**, ohne Capacitor. Das Xcode-Projekt erzeugt XcodeGen aus `project.yml` in
  jedem Lauf neu; es liegt nie im Repo.
- **Nur TestFlight intern** (`testFlightInternalTestingOnly`): nie extern, nie in den App Store. Jeder
  Testbau startet höchstens bis 90 Tage nach dem Upload.
- Keine Zertifikate, Profile oder Schlüssel im Repo. Signiert wird erst beim Export auf dem Runner.

| Pfad | Inhalt |
|---|---|
| `Halle/App.swift` | App-Delegate, Regie-Szene, Minutenbericht (Bildraten, Akku, Wärme, Speicher, Wach) |
| `Halle/TvSzene.swift` | TV-Szene: Overscan `.none`, Bühne randlos, Wach, gemeinsamer Zustand |
| `Halle/WebAnsicht.swift` | Die zwei WKWebViews: App-Bound Domains, Navigation nur auf der Worker-Domain |
| `Halle/Stift.swift` | T2: Doppeltipp und Squeeze des Apple Pencil an der Regie-WebView, Haptik über `UICanvasFeedbackGenerator` |
| `Halle/Vertrag.swift` | Vertrag mit der Web-App, nur Foundation: Fähigkeiten, Ereignisse und Nachrichten je Rolle, ihre Formen `{ art, daten }`, Lesen der Nachrichten |
| `Halle/Bruecke.swift` | Brücke in den WebViews: `window.__skemaHuelle`, Ereignisse senden, Nachrichten empfangen |
| `Halle/Netz.swift` | Nach einem Ladefehler neu laden: bei jeder Pfadmeldung „verbunden“ und wenn die Regie wieder vorn ist |
| `Halle/Diagnose.swift` | Werte der Ereignisse `buehne`, `wach`, `diagnose` (Bildschirm, Modi, Speicher, Wärme, Akku) |
| `Halle/Protokoll.swift` | Natives Protokoll mit Spiegel ins Systemlog |
| `werkzeug/erzeuge-icon.py` | Schreibt das App-Symbol aus dem Monogramm (PyMuPDF), RGB ohne Alphakanal; Quelle als Pfad außerhalb des Repos |
| `werkzeug/bauen.sh` | Bau ohne Signatur, Prüfung des Archivs, Formen der Brücke |
| `werkzeug/swift-vertrag.sh`, `.swift` | Übersetzt `Halle/Vertrag.swift` für macOS und schreibt, was Swift sendet und liest, nach `build/swift-vertrag.json` |
| `werkzeug/vertrag.sh`, `vertrag.jq` | Swift gegen `huelle-vertrag.json` vom Worker, in beide Richtungen, mit Feldern und Typen |
| `werkzeug/vertrag-test.sh` | Prüft Swift streng gegen echte `huelle-vertrag.json` (`werkzeug/testdaten/`: Web auf `main` und Web 50c) und `vertrag.sh` mit absichtlich falschen Dateien |
| `werkzeug/hochladen.sh` | Export, Prüfung des IPA, Upload nach App Store Connect |
| `.github/workflows/halle.yml` | Prüf-Job und Upload-Job |
| `.github/workflows/ablauf.yml` | Montags: Prüf-Job auf `main`, rot, wenn der letzte Upload älter als 70 Tage ist |

## Brücke (Vertrag 1)

- Swift an Seite beim Laden: `window.__skemaHuelle = { vertrag, rolle, bau, xcode, gebaut, faehigkeiten }`.
  `gebaut` ist der Zeitpunkt des Baus in UTC, ISO 8601 auf die Sekunde (`2026-10-23T09:00:00Z`), lesbar
  für `Date.parse`; `werkzeug/bauen.sh` prüft das am Archiv. Sonst verwirft die Web-App den Start.
- Fähigkeiten: Regie und Bühne melden `wach`, `buehne`, `diagnose`. Die Bühne braucht `diagnose`, damit
  die Seite ihr Log als `protokoll` schickt. Seit T2 meldet die Regie dazu `stift.doppeltipp`,
  `stift.squeeze`, `haptik` (unten).
- Swift an Seite: `CustomEvent("skema-huelle", { detail: { art, daten } })` am `window`. `buehne` und `wach`
  an beide nach jedem Laden und bei jeder Änderung (`wach` auch einmal beim Verbinden des TV),
  `diagnose` als Antwort an die Regie, `stift.doppeltipp` und `stift.squeeze` nur an die Regie. Ohne TV
  meldet `buehne` Zahlen 0, leere Texte, `zustand` `unattached`, nie `null`.
- Seite an Swift: `window.webkit.messageHandlers.huelle.postMessage({ art, daten })`, `art` ist
  `protokoll` (beide), `diagnose` oder `haptik` (nur Regie).
- Die Quelle des Vertrags ist `packages/protocol/src/huelle.ts` im privaten Repo; ihr Build liegt als
  `huelle-vertrag.json` auf dem Worker (Namen, Fähigkeit je Weg, Felder mit Typen). `werkzeug/vertrag.sh`
  vergleicht sie mit `build/swift-vertrag.json`, das `bauen.sh` aus `Halle/Vertrag.swift` erzeugt: Namen,
  Umschlag, Start, Fähigkeiten je Rolle, Felder mit Typen, Werte (Einstellung, Phase, Art der Haptik), in
  beide Richtungen. Beim Push nur Hinweis, im Upload-Job rot; gegen die Testdatei von Web 50c in
  `werkzeug/testdaten/` ist es schon im Prüf-Job rot.

## T2: Stift und Haptik

- `Halle/Stift.swift` hängt `UIPencilInteraction` nur an die Regie-WebView. Doppeltipp
  (`pencilInteraction(_:didReceiveTap:)`) sendet `stift.doppeltipp { einstellung, x?, y? }`, jede Phase der
  Squeeze (`pencilInteraction(_:didReceiveSqueeze:)`) `stift.squeeze { phase, einstellung, x?, y? }`.
- `einstellung` ist der Name des Falls von `UIPencilInteraction.preferredTapAction` bzw.
  `preferredSqueezeAction` (`ignore`, `switchEraser`, `switchPrevious`, `showColorPalette`,
  `showInkAttributes`, `showContextualPalette`, `runSystemShortcut`), `phase` einer von `began`, `changed`,
  `ended`, `cancelled`. Ein Fall außerhalb des Vertrags geht nicht an die Seite, nur ins Protokoll.
- `x`, `y`: `hoverPose.location` in CSS-px der Regie (Punkte der WebView geteilt durch `pageZoom`, 1).
  Ohne Pose fehlen beide, nie `null`.
- `haptik { typ, x, y }` nimmt Swift nur aus der Regie an: `form` an `pathCompleted(at:)`, `ausrichtung` an
  `alignmentOccurred(at:)` eines `UICanvasFeedbackGenerator` an der Regie-WebView. Ein anderer `typ` wird
  verworfen und protokolliert. Fühlbar nur mit Apple Pencil Pro.
- Protokoll: `Stift: Doppeltipp switchEraser, Pose ja`, `Stift: Squeeze ended …, Pose nein, changed 3`,
  `Haptik form`.
- Upload erst, wenn Web 50c (die Tafel nutzt Stift und Haptik) auf dem Worker ist: Gegen die Web-App auf
  `main` meldet T2 drei Fähigkeiten, die sie nicht nutzt, `vertrag.sh --streng` ist dann rot.

## App-Symbol

`Halle/Assets.xcassets/AppIcon.appiconset/icon-1024.png` ist eingecheckt; der Bau braucht nur das PNG.
Die Quelle, das SLSHM-Monogramm (Eigentum des Vereins) als Illustrator-Datei, liegt nicht im Repo
(`.gitignore`: `symbol/`, `*.ai`). Neu erzeugt wird das PNG am PC mit der Quelle aus einem lokalen Pfad
außerhalb des Repos (braucht `pip install pymupdf`):

```
python werkzeug/erzeuge-icon.py PFAD/ZUR/QUELLE.ai
```

Ein Pfad im Repo wird abgelehnt.

## Bau und Upload

Gebaut wird auf `macos-26` mit Xcode 26.6. Der Name `halle.yml` bleibt fest, weil die Baunummer aus
`run_number.run_attempt` entsteht.

- **Prüf-Job:** bei jedem Push. Projekt erzeugen, Archiv ohne Signatur, Info.plist, App-Symbol und Inhalt
  prüfen, Vertrag als Hinweis. Braucht keine Secrets. Das App-Symbol liegt als Artefakt `app-symbol-…` bei.
- **Upload-Job:** startet nur Alex, nie während eines Trainings: Actions → Halle → Run workflow → `main`,
  `hochladen` an. Wie der Prüf-Job, Vertrag streng, dann Ad-hoc-Signatur, Export, Prüfung der
  Entitlements, Upload mit `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.
- Mit `xcode: 27` (ohne Upload) wird einmal der Weg für iPadOS 27 übersetzt, vor dem Gerätetest G27.

Logs und Artefakte sind öffentlich; sie enthalten nur geschwärzte Auszüge, nie den Schlüssel, das IPA
oder `DistributionSummary.plist`.
