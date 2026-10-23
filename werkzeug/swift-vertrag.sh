#!/usr/bin/env bash
# Formen der Bruecke, wie Swift sie tatsaechlich sendet und liest (Bauzettel 50, § 2.7): uebersetzt
# Halle/Vertrag.swift (nur Foundation) mit werkzeug/swift-vertrag.swift fuer macOS, ohne Simulator, und
# schreibt build/swift-vertrag.json fuer werkzeug/vertrag.sh. Laeuft in bauen.sh; nie von Hand pflegen.
# Kompatibel mit bash 3.2 (macOS).
set -euo pipefail

mkdir -p build/werkzeug build/logs
xcrun --sdk macosx swiftc -swift-version 5 -parse-as-library \
  -o build/werkzeug/swift-vertrag Halle/Vertrag.swift werkzeug/swift-vertrag.swift
build/werkzeug/swift-vertrag > build/swift-vertrag.json
jq -e 'type == "object"' build/swift-vertrag.json > /dev/null
cp build/swift-vertrag.json build/logs/swift-vertrag.json
echo "Formen von Swift in build/swift-vertrag.json:"
jq -r '"rollen: \(.rollen | tojson)", (.ereignisse | to_entries[] | "Ereignis \(.key): \(.value | tojson)"),
  (.nachrichten | to_entries[] | "Nachricht \(.key): \(.value | tojson)"), "werte: \(.werte | tojson)"' build/swift-vertrag.json
