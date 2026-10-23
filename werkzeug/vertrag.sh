#!/usr/bin/env bash
# Huelle: Vertrag der Bruecke gegen die veroeffentlichte Web-App (Bauzettel 50, § 2.5, § 2.7).
# Liest Nummer, Faehigkeiten, Ereignisse und Nachrichten aus Halle/Bruecke.swift (Zeilen mit
# „// vertrag:") und vergleicht sie mit huelle-vertrag.json vom Worker (Build von packages/protocol):
#   { "vertrag": 1, "faehigkeiten": [...], "ereignisse": [...], "nachrichten": [...] }
# Ohne --streng (Pruef-Job) ist jede Abweichung nur ein Hinweis, damit „Swift vor Web" beim Bauen geht;
# mit --streng (Upload-Job) ist sie rot: kein Testbau geht hoch, den die veroeffentlichte Web-App nicht kennt.
# --datei PFAD prueft eine Datei statt der vom Worker (werkzeug/vertrag-test.sh); --soll gibt aus, was
# Swift anmeldet, im Format der Datei.
set -euo pipefail

STRENG=0
VORGABE=""
SOLL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --streng) STRENG=1 ;;
    --datei) VORGABE="$2"; shift ;;
    --soll) SOLL=1 ;;
    *) echo "::error::vertrag.sh: unbekannte Angabe $1"; exit 2 ;;
  esac
  shift
done
if ! command -v jq > /dev/null; then
  echo "::error::jq fehlt auf diesem Runner"
  exit 1
fi
QUELLE="Halle/Bruecke.swift"
HOST="$(/usr/libexec/PlistBuddy -c 'Print :WKAppBoundDomains:0' Halle/Info.plist)"
ADRESSE="${VORGABE:-https://$HOST/huelle-vertrag.json}"
DATEI="build/huelle-vertrag.json"
ZUSAMMENFASSUNG="${GITHUB_STEP_SUMMARY:-/dev/null}"
ABWEICHUNG=0
mkdir -p build/logs

swift_namen() { # Feld: alle Namen aus den Zeilen „// vertrag:Feld", ohne Doppelte
  grep -E "// vertrag:$1\$" "$QUELLE" | grep -oE '"[^"]+"' | tr -d '"' | sort -u
}
SWIFT_NUMMER="$(grep -E '// vertrag:nummer$' "$QUELLE" | grep -oE '[0-9]+' | head -n 1)"

if [ "$SOLL" = 1 ]; then
  liste() { swift_namen "$1" | jq -R . | jq -s -c .; }
  jq -n --argjson v "$SWIFT_NUMMER" --argjson f "$(liste faehigkeiten)" --argjson e "$(liste ereignisse)" \
    --argjson n "$(liste nachrichten)" '{vertrag: $v, faehigkeiten: $f, ereignisse: $e, nachrichten: $n}'
  exit 0
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
    echo "ok: Vertrag $SWIFT_NUMMER passt zu $ADRESSE"
    echo "- Vertrag $SWIFT_NUMMER passt zur Web-App ($ADRESSE)" >> "$ZUSAMMENFASSUNG"
  fi
  if [ "$STRENG" = 1 ] && [ "$ABWEICHUNG" = 1 ]; then exit 1; fi
  exit 0
}

echo "Swift: Vertrag $SWIFT_NUMMER"
for feld in faehigkeiten ereignisse nachrichten; do
  echo "Swift $feld: $(swift_namen "$feld" | tr '\n' ' ')"
done

if [ -n "$VORGABE" ]; then
  cp "$VORGABE" "$DATEI"
elif ! curl -fsS --retry 3 --max-time 30 -o "$DATEI" "$ADRESSE"; then
  abweichung "$ADRESSE fehlt (50a noch nicht auf dem Worker veroeffentlicht?)"
  ende
fi
# Ohne Datei liefert der Worker wahrscheinlich die index.html der App (SPA-Rueckfall), also kein JSON.
if ! jq -e 'type == "object"' "$DATEI" > /dev/null 2>&1; then
  abweichung "$ADRESSE ist kein JSON-Objekt (50a noch nicht auf dem Worker veroeffentlicht?)"
  ende
fi
cp "$DATEI" build/logs/huelle-vertrag.json
WEB_NUMMER="$(jq -r '.vertrag // "keine"' "$DATEI")"
if [ "$WEB_NUMMER" != "$SWIFT_NUMMER" ]; then
  abweichung "Nummer: Swift $SWIFT_NUMMER, Web $WEB_NUMMER"
fi
for feld in faehigkeiten ereignisse nachrichten; do
  WEB="$(jq -r --arg f "$feld" '.[$f] | if type == "array" then .[] | strings else empty end' "$DATEI")"
  for name in $(swift_namen "$feld"); do
    if ! printf '%s\n' "$WEB" | grep -qxF -- "$name"; then
      abweichung "$feld: Swift meldet '$name' an, die Web-App auf dem Worker kennt es nicht"
    fi
  done
done
ende
