#!/usr/bin/env bash
# Testet werkzeug/vertrag.sh ohne Worker (Bauzettel 50, § 2.5, § 2.7) und prueft dabei die Swift-Seite.
# Zwei echte Dateien in werkzeug/testdaten, beide nie von Hand angepasst:
# - huelle-vertrag.json: der Build der Web-App auf main (f38df7b), Byte fuer Byte wie auf dem Worker.
#   Ihre Web-App nutzt Stift und Haptik noch nicht (HUELLE_GENUTZT in apps/web/src/plattform/
#   huelleVertrag.ts). Swift T2 meldet sie, also ist das streng rot: kein Upload von T2, bevor Web 50c
#   auf dem Worker ist (§ 6: Web zuerst veroeffentlicht).
# - huelle-vertrag-50c.json: dieselbe Funktion huelleVertragDatei aus packages/protocol/src/huelle.ts
#   (f38df7b, eingefroren) mit allen Faehigkeiten als genutzt, so wie Web 50c sie veroeffentlicht:
#     node --experimental-strip-types erzeuge.mts (huelleVertragDatei(HUELLE_FAEHIGKEITEN, 'f38df7b+50c'),
#     JSON mit zwei Leerzeichen und Zeilenende wie apps/web/bau/huelleVertrag.ts)
#   Gegen sie muss Swift streng passen, schon im Pruef-Job. Ist Web 50c gebaut, kommt sie aus dessen Build.
# Absichtlich falsche Dateien (Vertrag) und falsche Formen von Swift muessen rot werden, mit dem Grund;
# die Formen von Swift bilden die Funde F1 bis F6 der Gegenpruefung nach, dazu Stift und Haptik.
# Braucht build/swift-vertrag.json (bauen.sh); fehlt sie, erzeugt vertrag.sh sie.
# Kompatibel mit bash 3.2 (macOS).
set -euo pipefail

T="build/vertrag-test"
ECHT="werkzeug/testdaten/huelle-vertrag.json"
T2="werkzeug/testdaten/huelle-vertrag-50c.json"
SWIFT="build/swift-vertrag.json"
mkdir -p "$T"
if [ ! -f "$SWIFT" ]; then
  bash werkzeug/swift-vertrag.sh
fi
echo "Vertrag der Web-App $(jq -r .web "$ECHT") und $(jq -r .web "$T2"), Swift-Formen aus $SWIFT"

# Vertrag falsch (auf Grundlage von Web 50c, damit nur der gewollte Fehler auftaucht)
jq '.faehigkeiten -= ["diagnose"] | del(.ereignisse.diagnose, .nachrichten.diagnose, .nachrichten.protokoll)' "$T2" > "$T/ohne-diagnose.json"
jq '.vertrag += 1' "$T2" > "$T/nummer.json"
jq '.ereignisse.diagnose.felder.akku = "text" | .ereignisse.buehne.felder.signal = "zahl"' "$T2" > "$T/felder.json"
jq '.ereignisse |= map_values(.felder | keys) | .nachrichten |= map_values(.felder | keys) | .start |= keys' "$T2" > "$T/alt.json"
jq '.werte.haptikTyp += ["ring"]' "$T2" > "$T/haptik-ring.json"
jq 'del(.werte.haptikTyp)' "$T2" > "$T/ohne-haptik-typ.json"
echo '<!doctype html><title>SLSHM</title>' > "$T/kein.json"

# Swift: die Funde der Gegenpruefung
jq '.umschlag = { typ: "text", daten: "objekt" }' "$SWIFT" > "$T/f1-typ.json"
jq '.rollen[].ereignisse -= ["wach"] | del(.ereignisse.wach)' "$SWIFT" > "$T/f3-ohne-wach.json"
jq '.ereignisse.buehne.breite = "null" | .ereignisse.buehne.modus = "null"' "$SWIFT" > "$T/f4-null.json"
jq '.ereignisse.diagnose |= (del(.speicherMb, .laden) + { speicherFreiMB: "zahl", akku: "text" })' "$SWIFT" > "$T/f5-diagnose.json"
jq '.rollen.buehne.faehigkeiten = ["wach", "buehne"]' "$SWIFT" > "$T/f6-buehne.json"
jq '.ereignisse.wach = { "aktiv?": "bool" }' "$SWIFT" > "$T/kann.json"
# Swift: Stift und Haptik
jq '.ereignisse["stift.squeeze"]["x?"] = "null"' "$SWIFT" > "$T/squeeze-null.json"
jq '.ereignisse["stift.doppeltipp"] |= (del(.["x?"], .["y?"]) + { x: "zahl", y: "zahl" })' "$SWIFT" > "$T/doppeltipp-pflicht.json"
jq '.rollen.regie.faehigkeiten -= ["haptik"]' "$SWIFT" > "$T/ohne-haptik.json"
jq '.rollen.regie.nachrichten -= ["haptik"] | del(.nachrichten.haptik)' "$SWIFT" > "$T/haptik-nie.json"
jq '.nachrichten.haptik.typ = "zahl"' "$SWIFT" > "$T/haptik-zahl.json"
jq '.rollen.regie.ereignisse -= ["stift.squeeze"] | del(.ereignisse["stift.squeeze"])' "$SWIFT" > "$T/squeeze-nie.json"
jq '.rollen.buehne.ereignisse += ["stift.doppeltipp"]' "$SWIFT" > "$T/buehne-stift.json"
jq '.werte.stiftEinstellung += ["switchEarser"]' "$SWIFT" > "$T/einstellung-falsch.json"
# Web vor Swift: ein Testbau ohne Squeeze (G11 nein, § 3.1) gegen Web 50c
jq '.rollen.regie.faehigkeiten -= ["stift.squeeze"] | .rollen.regie.ereignisse -= ["stift.squeeze"] | del(.ereignisse["stift.squeeze"])' "$SWIFT" > "$T/ohne-squeeze.json"

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

# Web 50c: Swift passt streng; Web vor Swift (ohne Squeeze) auch
erwarte 0 "ok: Swift passt" --streng --datei "$T2"
erwarte 0 "ok: Swift passt" --streng --datei "$T2" --swift "$T/ohne-squeeze.json"
# Web auf main (f38df7b): Swift vor Web, streng rot, ohne --streng nur Hinweis
erwarte 1 "regie: Swift meldet Faehigkeit stift.doppeltipp, die Web-App kennt sie nicht" --streng --datei "$ECHT"
erwarte 1 "regie: Swift sendet Ereignis stift.squeeze, die Web-App kennt es nicht" --streng --datei "$ECHT"
erwarte 1 "regie: Swift liest Nachricht haptik, die Web-App kennt sie nicht" --streng --datei "$ECHT"
erwarte 0 "Hinweis zum Vertrag" --datei "$ECHT"
# Vertrag falsch
erwarte 1 "Swift meldet Faehigkeit diagnose, die Web-App kennt sie nicht" --streng --datei "$T/ohne-diagnose.json"
erwarte 1 "Nummer: Swift 1" --streng --datei "$T/nummer.json"
erwarte 1 "Feld akku ist bei Swift zahl, im Vertrag text" --streng --datei "$T/felder.json"
erwarte 1 "Feld signal (zahl) fehlt bei Swift" --streng --datei "$T/felder.json"
erwarte 1 "Werte haptikTyp: ring fehlt bei Swift" --streng --datei "$T/haptik-ring.json"
erwarte 1 "Werte haptikTyp: Swift nutzt sie, der Vertrag nennt sie nicht" --streng --datei "$T/ohne-haptik-typ.json"
erwarte 1 "nicht das Format mit Typen" --streng --datei "$T/alt.json"
erwarte 1 "kein JSON-Objekt" --streng --datei "$T/kein.json"
# Swift falsch (F1 bis F6)
erwarte 1 "Umschlag: Feld art (text) fehlt bei Swift" --streng --datei "$T2" --swift "$T/f1-typ.json"
erwarte 1 "Ereignis wach: gehoert zur Faehigkeit wach" --streng --datei "$T2" --swift "$T/f3-ohne-wach.json"
erwarte 1 "Feld breite ist bei Swift null" --streng --datei "$T2" --swift "$T/f4-null.json"
erwarte 1 "Feld speicherMb (zahl) fehlt bei Swift" --streng --datei "$T2" --swift "$T/f5-diagnose.json"
erwarte 1 "Feld akku ist bei Swift text" --streng --datei "$T2" --swift "$T/f5-diagnose.json"
erwarte 1 "Swift liest Nachricht protokoll ohne die Faehigkeit diagnose" --streng --datei "$T2" --swift "$T/f6-buehne.json"
erwarte 1 "Feld aktiv ist bei Swift Kann-Feld" --streng --datei "$T2" --swift "$T/kann.json"
# Swift falsch: Stift und Haptik
erwarte 1 "Ereignis stift.squeeze: Feld x ist bei Swift null, im Vertrag zahl" --streng --datei "$T2" --swift "$T/squeeze-null.json"
erwarte 1 "Typ null: Swift sendet oder liest ihn" --streng --datei "$T2" --swift "$T/squeeze-null.json"
erwarte 1 "Ereignis stift.doppeltipp: Feld x ist bei Swift Pflichtfeld, im Vertrag Kann-Feld" --streng --datei "$T2" --swift "$T/doppeltipp-pflicht.json"
erwarte 1 "regie: Swift liest Nachricht haptik ohne die Faehigkeit haptik; die Seite sendet sie nie" --streng --datei "$T2" --swift "$T/ohne-haptik.json"
erwarte 1 "Nachricht haptik: Feld typ ist bei Swift zahl, im Vertrag text" --streng --datei "$T2" --swift "$T/haptik-zahl.json"
erwarte 1 "Ereignis stift.squeeze: gehoert zur Faehigkeit stift.squeeze, die Swift meldet; Swift sendet es nie" --streng --datei "$T2" --swift "$T/squeeze-nie.json"
erwarte 1 "Nachricht haptik: gehoert zur Faehigkeit haptik, die Swift meldet; Swift liest sie nie" --streng --datei "$T2" --swift "$T/haptik-nie.json"
erwarte 1 "buehne: Swift sendet Ereignis stift.doppeltipp ohne die Faehigkeit stift.doppeltipp" --streng --datei "$T2" --swift "$T/buehne-stift.json"
erwarte 1 "Werte stiftEinstellung: switchEarser gibt es nur bei Swift" --streng --datei "$T2" --swift "$T/einstellung-falsch.json"
# Ohne --streng nur Hinweis
erwarte 0 "Hinweis zum Vertrag" --datei "$T/ohne-diagnose.json"
erwarte 0 "Hinweis zum Vertrag" --datei "$T/kein.json"
exit "$FEHLER"
