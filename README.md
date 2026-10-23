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
| `Halle/Bruecke.swift` | Vertrag mit der Web-App: `window.__skemaHuelle`, Ereignisse, Nachrichten |
| `Halle/Netz.swift` | Nach einem Ladefehler neu laden: bei jeder Pfadmeldung „verbunden“ und wenn die Regie wieder vorn ist |
| `Halle/Diagnose.swift` | Bau, „gilt bis“, Bildschirm, Modi, Wach, Speicher für den Abschnitt „Hülle“ |
| `Halle/Protokoll.swift` | Natives Protokoll mit Spiegel ins Systemlog |
| `werkzeug/erzeuge-icon.py` | Schreibt das App-Symbol aus dem Monogramm (PyMuPDF), RGB ohne Alphakanal; Quelle als Pfad außerhalb des Repos |
| `werkzeug/bauen.sh` | Bau ohne Signatur und Prüfung des Archivs |
| `werkzeug/vertrag.sh` | Brücke gegen `huelle-vertrag.json` vom Worker |
| `werkzeug/vertrag-test.sh` | Prüft `vertrag.sh` ohne Worker mit Dateien aus dem Swift-Stand |
| `werkzeug/hochladen.sh` | Export, Prüfung des IPA, Upload nach App Store Connect |
| `.github/workflows/halle.yml` | Prüf-Job und Upload-Job |
| `.github/workflows/ablauf.yml` | Montags: Prüf-Job auf `main`, rot, wenn der letzte Upload älter als 70 Tage ist |

## Brücke (Vertrag 1)

- Swift an Seite beim Laden: `window.__skemaHuelle = { vertrag, rolle, bau, xcode, gebaut, faehigkeiten }`.
- Swift an Seite: `CustomEvent("skema-huelle", { detail: { typ, daten } })` am `window`, `typ` ist
  `buehne` oder `diagnose`.
- Seite an Swift: `window.webkit.messageHandlers.huelle.postMessage({ typ, daten })`, `typ` ist
  `protokoll` (beide) oder `diagnose` (nur Regie).
- Die Namen stehen in `Halle/Bruecke.swift` in den Zeilen mit `// vertrag:`; `werkzeug/vertrag.sh` prüft sie
  gegen die veröffentlichte Web-App. Beim Push nur Hinweis, im Upload-Job rot. `bash werkzeug/vertrag.sh --soll`
  gibt aus, was Swift anmeldet, im Format von `huelle-vertrag.json`.

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
