#!/usr/bin/env bash
# Huelle „SLSHM Coach": Export, Pruefung des IPA und Upload nach TestFlight intern (Bauzettel 50, § 2.4,
# § 4; Muster ist das Upload-Skript der Bühnenprobe, Bauzettel 45 § 5.3 Schritte 6 bis 9). Laeuft nur im
# Upload-Job nach werkzeug/bauen.sh und werkzeug/vertrag.sh --streng. Erwartet ASC_KEY_ID, ASC_ISSUER_ID
# und ASC_KEY_P8 (Inhalt der .p8 als PEM-Text) sowie BUILD, HUELLE_XCODE und HUELLE_GEBAUT aus bauen.sh.
#
# Das Repo ist oeffentlich, seine Logs und Artefakte auch (Bauzettel 45 § 5.1, § 5.6). Darum:
# - kein Schritt gibt den Schluessel aus, er liegt nur in $RUNNER_TEMP/asc und wird im Workflow geloescht;
# - die Ausgaben von xcodebuild gehen zuerst in Dateien unter $RUNNER_TEMP und erscheinen im Log und im
#   Artefakt nur als Auszug (Fehler, Warnungen, Ergebnis) und geschwaerzt (Namen, Mail, Team);
# - DistributionSummary.plist, die rohen Verteilungs-Logs und das IPA gehen nie ins Artefakt (B2).
set -euo pipefail

TEAM_ID="FTZZJQT9QX"
BUNDLE_ID="io.github.alexandercarreira-arch.skema-halle"
LOGS="build/logs"
ROH="${RUNNER_TEMP:?}/halle-roh"
SCHLUESSEL="${RUNNER_TEMP:?}/asc/AuthKey.p8"
APP="build/Halle.xcarchive/Products/Applications/Halle.app"
ZUSAMMENFASSUNG="${GITHUB_STEP_SUMMARY:-/dev/null}"
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_P8:?}" "${BUILD:?}" "${HUELLE_XCODE:?}" "${HUELLE_GEBAUT:?}"
mkdir -p "$LOGS" "$ROH"

# Schwaerzt Zertifikatsnamen („Apple Distribution: Vorname Name (TEAMID)"), Mail-Adressen, Teamnamen
# und jeden Wert eines Schluessels, der auf „name" endet (teamName, displayName, firstName, ...).
schwaerze() {
  sed -E \
    -e 's/((Apple|iPhone|iOS) (Distribution|Development|Developer)|Developer ID Application): [^()"]*\(/\1: <Name> (/g' \
    -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<Mail>/g' \
    -e 's/([A-Za-z]*[Nn]ame"?[[:space:]]*[:=][[:space:]]*)"[^"]*"/\1"<Name>"/g' \
    -e 's/([A-Za-z]*[Nn]ame"?[[:space:]]*=[[:space:]]*)[^";,}]+/\1<Name>/g' \
    -e 's/([Tt]eam:? *)"[^"]*"/\1"<Team>"/g' \
    -e "s/([Tt]eam:? *)'[^']*'/\\1'<Team>'/g"
}

# Nur Zeilen mit Fehlern, Warnungen und Ergebnis, geschwaerzt, ohne Doppelte, hoechstens 150.
auszug() {
  grep -a -i -E 'error|warn|fail|ITMS-|succeeded|exported|upload|denied|unauthori|forbidden|not found|no (account|signing|profile|certificate)|\*\*' "$1" \
    | schwaerze | awk '!gesehen[$0]++' | head -n 150 || true
}

# Auszuege aus den Verteilungs-Logs, die seit der Marke entstanden sind. Nie DistributionSummary.plist.
verteilungslogs() { # Name, Marke
  local ziel="$LOGS/verteilung-$1-auszug.txt"
  : > "$ziel"
  local ordner datei
  for ordner in $(find "${TMPDIR:-/tmp}" "$ROH" -maxdepth 2 -name '*.xcdistributionlogs' -newer "$2" 2>/dev/null); do
    for datei in "$ordner"/IDEDistribution.critical.log "$ordner"/IDEDistribution.standard.log "$ordner"/Packaging.log; do
      if [ -f "$datei" ]; then
        echo "== $(basename "$datei")" >> "$ziel"
        auszug "$datei" >> "$ziel"
      fi
    done
  done
  if [ -s "$ziel" ]; then
    cat "$ziel"
  else
    echo "keine Verteilungs-Logs gefunden"
  fi
}

export_lauf() { # Name, Optionen, Ziel
  local marke="$ROH/marke-$1"
  touch "$marke"
  set +e
  xcodebuild -exportArchive -archivePath build/Halle.xcarchive -exportPath "$3" \
    -exportOptionsPlist "$2" -allowProvisioningUpdates \
    -authenticationKeyPath "$SCHLUESSEL" -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID" > "$ROH/$1.log" 2>&1
  local status=$?
  set -e
  auszug "$ROH/$1.log" | tee "$LOGS/$1-auszug.txt"
  echo "-- Verteilungs-Logs ($1)"
  verteilungslogs "$1" "$marke"
  return "$status"
}

optionen() { # Datei, destination
  rm -f "$1"
  /usr/libexec/PlistBuddy \
    -c "Add :method string app-store-connect" \
    -c "Add :destination string $2" \
    -c "Add :signingStyle string automatic" \
    -c "Add :teamID string $TEAM_ID" \
    -c "Add :manageAppVersionAndBuildNumber bool false" \
    -c "Add :testFlightInternalTestingOnly bool true" \
    -c "Add :uploadSymbols bool true" \
    "$1" > /dev/null
  cp "$1" "$LOGS/"
}

# 7. Ad-hoc-Signatur ohne Entitlements (45 E10) und Schluessel ablegen
echo "::group::7 Ad-hoc-Signatur und Schluessel"
codesign --force --sign - "$APP"
mkdir -p "$(dirname "$SCHLUESSEL")"
(
  umask 077
  printf '%s\n' "$ASC_KEY_P8" | tr -d '\r' > "$SCHLUESSEL"
)
unset ASC_KEY_P8
if [ "$(sed -n 1p "$SCHLUESSEL")" = "-----BEGIN PRIVATE KEY-----" ] && grep -qx -- '-----END PRIVATE KEY-----' "$SCHLUESSEL"; then
  echo "ok: Schluessel mit PEM-Rahmen"
else
  echo "::error::ASC_KEY_P8 ist kein PEM-Text mit BEGIN/END PRIVATE KEY (Inhalt wird nicht gezeigt)"
  exit 1
fi
if openssl pkey -in "$SCHLUESSEL" -noout > /dev/null 2>&1; then
  echo "ok: Schluessel lesbar"
else
  echo "::error::ASC_KEY_P8 laesst sich nicht als privater Schluessel lesen (Inhalt wird nicht gezeigt)"
  exit 1
fi
optionen build/ExportOptions-export.plist export
optionen build/ExportOptions-upload.plist upload
echo "::endgroup::"

# 8. Export als IPA und Pruefung, bevor etwas zu Apple geht
echo "::group::8 Export als IPA"
if ! export_lauf export build/ExportOptions-export.plist build/export; then
  echo "::endgroup::"
  echo "::error::Export fehlgeschlagen, Auszug oben und im Artefakt (export-auszug.txt, verteilung-export-auszug.txt)"
  echo "- rot: Export (Signierung oder Profil), siehe export-auszug.txt" >> "$ZUSAMMENFASSUNG"
  exit 1
fi
echo "::endgroup::"

echo "::group::8 Pruefung des IPA"
IPA=""
for datei in build/export/*.ipa; do
  IPA="$datei"
  break
done
if [ ! -f "$IPA" ]; then
  echo "::error::kein IPA in build/export"
  exit 1
fi
unzip -l "$IPA" > "$LOGS/ipa-inhalt.txt"
rm -rf "$ROH/ipa"
mkdir -p "$ROH/ipa"
unzip -q "$IPA" -d "$ROH/ipa"
IPA_APP="$ROH/ipa/Payload/Halle.app"
plutil -p "$IPA_APP/Info.plist" > "$LOGS/ipa-info.txt"
if ! codesign -d --entitlements - --xml "$IPA_APP" > "$ROH/entitlements.plist"; then
  echo "::error::codesign liest die Entitlements des IPA nicht"
  exit 1
fi
plutil -p "$ROH/entitlements.plist" > "$LOGS/ipa-entitlements.txt"
cat "$LOGS/ipa-entitlements.txt"
FEHLER=0
APP_ID="$(/usr/libexec/PlistBuddy -c 'Print :application-identifier' "$ROH/entitlements.plist" 2> /dev/null || echo '<fehlt>')"
if [ "$APP_ID" = "$TEAM_ID.$BUNDLE_ID" ]; then
  echo "ok: application-identifier $APP_ID"
else
  echo "::error::application-identifier ist '$APP_ID', erwartet '$TEAM_ID.$BUNDLE_ID' (45 E10, Rueckfall Archiv wie Xcode Cloud)"
  FEHLER=1
fi
BETA="$(/usr/libexec/PlistBuddy -c 'Print :beta-reports-active' "$ROH/entitlements.plist" 2> /dev/null || echo '<fehlt>')"
echo "beta-reports-active: $BETA"
for datei in PrivacyInfo.xcprivacy Assets.car embedded.mobileprovision; do
  if [ -f "$IPA_APP/$datei" ]; then echo "ok: $datei im IPA"; else echo "::error::$datei fehlt im IPA"; FEHLER=1; fi
done
IPA_BAU="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$IPA_APP/Info.plist" 2> /dev/null || echo '<fehlt>')"
if [ "$IPA_BAU" = "$BUILD" ]; then echo "ok: CFBundleVersion $IPA_BAU"; else echo "::error::CFBundleVersion im IPA ist '$IPA_BAU', erwartet '$BUILD'"; FEHLER=1; fi
echo "::endgroup::"
if [ "$FEHLER" != 0 ]; then
  echo "- rot: Pruefung des IPA" >> "$ZUSAMMENFASSUNG"
  exit 1
fi

# 9. Upload nach App Store Connect (45 E11); testFlightInternalTestingOnly: nie extern, nie in den Store
echo "::group::9 Upload"
if ! export_lauf upload build/ExportOptions-upload.plist build/upload; then
  echo "::endgroup::"
  echo "::error::Upload fehlgeschlagen, Auszug oben und im Artefakt (upload-auszug.txt, verteilung-upload-auszug.txt)"
  echo "- rot: Upload, siehe upload-auszug.txt" >> "$ZUSAMMENFASSUNG"
  exit 1
fi
echo "::endgroup::"

{
  echo "### Hochgeladen"
  echo ""
  echo "- Baunummer: \`$BUILD\` (Version 0.1), gebaut \`$HUELLE_GEBAUT\`"
  echo "- Xcode: \`$HUELLE_XCODE\`"
  echo "- TestFlight: nur intern (\`testFlightInternalTestingOnly\`), 90 Tage ab dem Upload lauffaehig"
  echo "- Kalender: Eintrag in 80 Tagen, Testbau erneuern (Bauzettel 50, § 7 Nr. 9)"
} >> "$ZUSAMMENFASSUNG"
echo "Hochgeladen: Bau $BUILD, $HUELLE_XCODE"
