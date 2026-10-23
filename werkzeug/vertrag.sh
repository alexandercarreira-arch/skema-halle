#!/usr/bin/env bash
# Huelle: Vertrag der Bruecke gegen die veroeffentlichte Web-App (Bauzettel 50, § 2.5, § 2.7).
# Vergleicht huelle-vertrag.json vom Worker (Build von packages/protocol/src/huelle.ts, die einzige
# Quelle) mit den Formen, die Swift tatsaechlich sendet und liest (build/swift-vertrag.json, erzeugt von
# werkzeug/swift-vertrag.sh), in beide Richtungen (werkzeug/vertrag.jq): Nummer, Umschlag { art, daten },
# Start, Faehigkeiten je Rolle, Ereignisse und Nachrichten mit Faehigkeit, Felder mit Typen.
# Format der Datei: { vertrag, rollen, faehigkeiten, typen, umschlag: { feld: typ }, start: { feld: typ },
#   ereignisse: { art: { faehigkeit, felder: { feld: typ } } }, nachrichten: { ebenso }, ... }
# Ohne --streng (Pruef-Job) ist jede Abweichung nur ein Hinweis, damit „Swift vor Web" beim Bauen geht;
# mit --streng (Upload-Job) ist sie rot: kein Testbau geht hoch, den die veroeffentlichte Web-App nicht kennt.
# --datei PFAD prueft eine Datei statt der vom Worker, --swift PFAD andere Formen von Swift
# (beides fuer werkzeug/vertrag-test.sh). Fehlen die Formen von Swift oder sind sie kaputt, ist das immer rot.
# Kompatibel mit bash 3.2 (macOS).
set -euo pipefail

STRENG=0
VORGABE=""
SWIFT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --streng) STRENG=1 ;;
    --datei) VORGABE="$2"; shift ;;
    --swift) SWIFT="$2"; shift ;;
    *) echo "::error::vertrag.sh: unbekannte Angabe $1"; exit 2 ;;
  esac
  shift
done
if ! command -v jq > /dev/null; then
  echo "::error::jq fehlt auf diesem Runner"
  exit 1
fi
ZUSAMMENFASSUNG="${GITHUB_STEP_SUMMARY:-/dev/null}"
ABWEICHUNG=0
mkdir -p build/logs

if [ -z "$SWIFT" ]; then
  SWIFT="build/swift-vertrag.json"
  if [ ! -f "$SWIFT" ]; then
    bash werkzeug/swift-vertrag.sh
  fi
fi
if ! jq -e '(.rollen | type) == "object" and (.ereignisse | type) == "object" and (.nachrichten | type) == "object"' "$SWIFT" > /dev/null 2>&1; then
  echo "::error::Vertrag: $SWIFT ist keine Form von Swift (werkzeug/swift-vertrag.sh)"
  exit 1
fi

abweichung() {
  ABWEICHUNG=1
  if [ "$STRENG" = 1 ]; then
    echo "::error::Vertrag: $1"
    echo "- rot: Vertrag: $1" >> "$ZUSAMMENFASSUNG"
  else
    echo "::warning::Hinweis zum Vertrag (rot erst im Upload-Job): $1"
    echo "- Hinweis: Vertrag: $1" >> "$ZUSAMMENFASSUNG"
  fi
}

ende() {
  if [ "$ABWEICHUNG" = 0 ]; then
    echo "ok: Swift passt zu $ADRESSE"
    echo "- Vertrag $(jq -r .vertrag "$SWIFT"): Swift passt zur Web-App ($ADRESSE)" >> "$ZUSAMMENFASSUNG"
  fi
  if [ "$STRENG" = 1 ] && [ "$ABWEICHUNG" = 1 ]; then exit 1; fi
  exit 0
}

echo "Swift: Vertrag $(jq -r .vertrag "$SWIFT")"
jq -r '.rollen | to_entries[] | "Swift \(.key): Faehigkeiten \(.value.faehigkeiten | join(", ")); sendet \(.value.ereignisse | join(", ")); liest \(.value.nachrichten | join(", "))"' "$SWIFT"

if [ -n "$VORGABE" ]; then
  ADRESSE="$VORGABE"
  DATEI="$VORGABE"
else
  HOST="$(/usr/libexec/PlistBuddy -c 'Print :WKAppBoundDomains:0' Halle/Info.plist)"
  ADRESSE="https://$HOST/huelle-vertrag.json"
  DATEI="build/huelle-vertrag.json"
  if ! curl -fsS --retry 3 --max-time 30 -o "$DATEI" "$ADRESSE"; then
    abweichung "$ADRESSE fehlt (50a noch nicht auf dem Worker veroeffentlicht?)"
    ende
  fi
fi
# Ohne Datei liefert der Worker wahrscheinlich die index.html der App (SPA-Rueckfall), also kein JSON.
if ! jq -e 'type == "object"' "$DATEI" > /dev/null 2>&1; then
  abweichung "$ADRESSE ist kein JSON-Objekt (50a noch nicht auf dem Worker veroeffentlicht?)"
  ende
fi
if [ -z "$VORGABE" ]; then
  cp "$DATEI" build/logs/huelle-vertrag.json
fi
FORMAT='(.vertrag | type) == "number"
  and (.rollen | type) == "array" and (.faehigkeiten | type) == "array" and (.typen | type) == "array"
  and ([.umschlag, .start] | all(type == "object" and all(.[]; type == "string")))
  and ([.ereignisse, .nachrichten] | all(type == "object"
    and all(.[]; type == "object" and (.faehigkeit | type) == "string" and (.felder | type) == "object")))'
if ! jq -e "$FORMAT" "$DATEI" > /dev/null 2>&1; then
  abweichung "$ADRESSE hat nicht das Format mit Typen (Wege mit faehigkeit und felder; Web-App vor d225fdc?)"
  ende
fi

LISTE="$(jq -n -r --slurpfile w "$DATEI" --slurpfile s "$SWIFT" -f werkzeug/vertrag.jq)"
while IFS= read -r zeile; do
  if [ -n "$zeile" ]; then
    abweichung "$zeile"
  fi
done <<< "$LISTE"
ende
