#!/usr/bin/env bash
# Testet werkzeug/vertrag.sh ohne Worker (Bauzettel 50, § 2.5): bis 50a veroeffentlicht ist, laeuft im
# Pruef-Job nur der Zweig „Datei fehlt". Damit nicht erst der Upload-Job merkt, dass die Pruefung selbst
# falsch ist, prueft dieser Schritt alle Zweige mit Dateien, die aus dem Swift-Stand abgeleitet sind.
set -euo pipefail

T="build/vertrag-test"
mkdir -p "$T"
bash werkzeug/vertrag.sh --soll > "$T/passt.json"
echo "Swift meldet an: $(jq -c . "$T/passt.json")"
jq '.faehigkeiten += ["kuenftig"]' "$T/passt.json" > "$T/mehr.json"
jq '.faehigkeiten -= ["diagnose"]' "$T/passt.json" > "$T/fehlt.json"
jq '.vertrag += 1' "$T/passt.json" > "$T/nummer.json"
echo '<!doctype html><title>SLSHM</title>' > "$T/kein.json"

FEHLER=0
erwarte() { # Exit-Code, Angaben an vertrag.sh
  local soll="$1" ist
  shift
  set +e
  GITHUB_STEP_SUMMARY=/dev/null bash werkzeug/vertrag.sh "$@" > "$T/ausgabe.txt" 2>&1
  ist=$?
  set -e
  if [ "$ist" = "$soll" ]; then
    echo "ok: vertrag.sh $* -> $ist"
  else
    echo "::error::vertrag.sh $* ergab $ist, erwartet $soll"
    cat "$T/ausgabe.txt"
    FEHLER=1
  fi
}

erwarte 0 --streng --datei "$T/passt.json"
erwarte 0 --streng --datei "$T/mehr.json"
erwarte 1 --streng --datei "$T/fehlt.json"
erwarte 1 --streng --datei "$T/nummer.json"
erwarte 1 --streng --datei "$T/kein.json"
erwarte 0 --datei "$T/fehlt.json"
erwarte 0 --datei "$T/kein.json"
exit "$FEHLER"
