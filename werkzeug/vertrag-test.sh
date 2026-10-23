#!/usr/bin/env bash
# Testet werkzeug/vertrag.sh ohne Worker (Bauzettel 50, § 2.5, § 2.7) und prueft dabei die Swift-Seite:
# - werkzeug/testdaten/huelle-vertrag.json ist eine echte Datei aus dem Build der Web-App (npm run build
#   im privaten Repo, apps/web/dist; Stand im Feld web). Gegen sie muss Swift streng passen, also schon
#   im Pruef-Job, bevor der Worker sie ausliefert. Meldet Swift eine neue Faehigkeit (T2), kommt die Datei
#   neu aus dem Build des Web-Zweigs, der sie kennt; nie von Hand angepasst.
# - Absichtlich falsche Dateien (Vertrag) und falsche Formen von Swift muessen rot werden, mit dem Grund;
#   die Formen von Swift bilden die Funde F1 bis F6 der Gegenpruefung nach.
# Braucht build/swift-vertrag.json (bauen.sh); fehlt sie, erzeugt vertrag.sh sie.
# Kompatibel mit bash 3.2 (macOS).
set -euo pipefail

T="build/vertrag-test"
ECHT="werkzeug/testdaten/huelle-vertrag.json"
SWIFT="build/swift-vertrag.json"
mkdir -p "$T"
if [ ! -f "$SWIFT" ]; then
  bash werkzeug/swift-vertrag.sh
fi
echo "Vertrag der Web-App $(jq -r .web "$ECHT"), Swift-Formen aus $SWIFT"

# Vertrag: Web vor Swift (Stift und Haptik, die Swift noch nicht meldet), und falsch
jq '.faehigkeiten += ["stift.doppeltipp", "haptik"]
  | .ereignisse["stift.doppeltipp"] = { faehigkeit: "stift.doppeltipp", felder: { einstellung: "text", "x?": "zahl", "y?": "zahl" } }
  | .nachrichten.haptik = { faehigkeit: "haptik", felder: { typ: "text", x: "zahl", y: "zahl" } }' "$ECHT" > "$T/web-vor-swift.json"
jq '.faehigkeiten -= ["diagnose"] | del(.ereignisse.diagnose, .nachrichten.diagnose, .nachrichten.protokoll)' "$ECHT" > "$T/ohne-diagnose.json"
jq '.vertrag += 1' "$ECHT" > "$T/nummer.json"
jq '.ereignisse.diagnose.felder.akku = "text" | .ereignisse.buehne.felder.signal = "zahl"' "$ECHT" > "$T/felder.json"
jq '.ereignisse |= map_values(.felder | keys) | .nachrichten |= map_values(.felder | keys) | .start |= keys' "$ECHT" > "$T/alt.json"
echo '<!doctype html><title>SLSHM</title>' > "$T/kein.json"

# Swift: die Funde der Gegenpruefung
jq '.umschlag = { typ: "text", daten: "objekt" }' "$SWIFT" > "$T/f1-typ.json"
jq '.rollen[].ereignisse -= ["wach"] | del(.ereignisse.wach)' "$SWIFT" > "$T/f3-ohne-wach.json"
jq '.ereignisse.buehne.breite = "null" | .ereignisse.buehne.modus = "null"' "$SWIFT" > "$T/f4-null.json"
jq '.ereignisse.diagnose |= (del(.speicherMb, .laden) + { speicherFreiMB: "zahl", akku: "text" })' "$SWIFT" > "$T/f5-diagnose.json"
jq '.rollen.buehne.faehigkeiten = ["wach", "buehne"]' "$SWIFT" > "$T/f6-buehne.json"
jq '.ereignisse.wach = { "aktiv?": "bool" }' "$SWIFT" > "$T/kann.json"

FEHLER=0
erwarte() { # Exit-Code, Text in der Ausgabe (oder leer), Angaben an vertrag.sh
  local soll="$1" text="$2" ist
  shift 2
  set +e
  GITHUB_STEP_SUMMARY=/dev/null bash werkzeug/vertrag.sh "$@" > "$T/ausgabe.txt" 2>&1
  ist=$?
  set -e
  if [ "$ist" != "$soll" ]; then
    echo "::error::vertrag.sh $* ergab $ist, erwartet $soll"
    cat "$T/ausgabe.txt"
    FEHLER=1
  elif [ -n "$text" ] && ! grep -qF -- "$text" "$T/ausgabe.txt"; then
    echo "::error::vertrag.sh $* nennt nicht: $text"
    cat "$T/ausgabe.txt"
    FEHLER=1
  else
    echo "ok: vertrag.sh $* -> $ist${text:+ ($text)}"
  fi
}

# Die echte Datei: Swift passt streng
erwarte 0 "ok: Swift passt" --streng --datei "$ECHT"
erwarte 0 "ok: Swift passt" --streng --datei "$T/web-vor-swift.json"
# Vertrag falsch
erwarte 1 "Swift meldet Faehigkeit diagnose, die Web-App kennt sie nicht" --streng --datei "$T/ohne-diagnose.json"
erwarte 1 "Nummer: Swift 1" --streng --datei "$T/nummer.json"
erwarte 1 "Feld akku ist bei Swift zahl, im Vertrag text" --streng --datei "$T/felder.json"
erwarte 1 "Feld signal (zahl) fehlt bei Swift" --streng --datei "$T/felder.json"
erwarte 1 "nicht das Format mit Typen" --streng --datei "$T/alt.json"
erwarte 1 "kein JSON-Objekt" --streng --datei "$T/kein.json"
# Swift falsch (F1 bis F6)
erwarte 1 "Umschlag: Feld art (text) fehlt bei Swift" --streng --datei "$ECHT" --swift "$T/f1-typ.json"
erwarte 1 "Ereignis wach: gehoert zur Faehigkeit wach" --streng --datei "$ECHT" --swift "$T/f3-ohne-wach.json"
erwarte 1 "Feld breite ist bei Swift null" --streng --datei "$ECHT" --swift "$T/f4-null.json"
erwarte 1 "Feld speicherMb (zahl) fehlt bei Swift" --streng --datei "$ECHT" --swift "$T/f5-diagnose.json"
erwarte 1 "Feld akku ist bei Swift text" --streng --datei "$ECHT" --swift "$T/f5-diagnose.json"
erwarte 1 "Swift liest Nachricht protokoll ohne die Faehigkeit diagnose" --streng --datei "$ECHT" --swift "$T/f6-buehne.json"
erwarte 1 "Feld aktiv ist bei Swift Kann-Feld" --streng --datei "$ECHT" --swift "$T/kann.json"
# Ohne --streng nur Hinweis
erwarte 0 "Hinweis zum Vertrag" --datei "$T/ohne-diagnose.json"
erwarte 0 "Hinweis zum Vertrag" --datei "$T/kein.json"
exit "$FEHLER"
