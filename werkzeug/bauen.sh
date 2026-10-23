#!/usr/bin/env bash
# Huelle „SLSHM Coach": Bau ohne Signatur und Pruefung des Archivs (Bauzettel 50, § 4; Muster Probe S1-H,
# Bauzettel 45 § 5.3 Schritte 1 bis 5). Laeuft im Pruef-Job und im Upload-Job, braucht keine Secrets.
# Kompatibel mit bash 3.2 (macOS).
set -euo pipefail

BUNDLE_ID="io.github.alexandercarreira-arch.skema-halle"
VERSION="0.1"
ANZEIGENAME="SLSHM Coach"
XCODEGEN_URL="https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip"
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"
ICON="Halle/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
# Die Worker-Domain steht nur in der Info.plist (WKAppBoundDomains); Swift und vertrag.sh lesen sie dort.
WORKER_HOST="$(/usr/libexec/PlistBuddy -c 'Print :WKAppBoundDomains:0' Halle/Info.plist)"

LOGS="build/logs"
ZUSAMMENFASSUNG="${GITHUB_STEP_SUMMARY:-/dev/null}"
FEHLER=0
mkdir -p "$LOGS" build/werkzeug

rot() {
  echo "::error::$1"
  echo "- rot: $1" >> "$ZUSAMMENFASSUNG"
  FEHLER=1
}

gleich() { # Name, Ist, Soll
  if [ "$2" = "$3" ]; then
    echo "ok: $1 = $2"
  else
    rot "$1 ist '$2', erwartet '$3'"
  fi
}

halt_bei_rot() {
  if [ "$FEHLER" != 0 ]; then
    echo "::error::$1"
    exit 1
  fi
}

# 1. Xcode und die Schluessel der Export-Optionen
echo "::group::1 Xcode"
if [ -n "${DEVELOPER_DIR:-}" ] && [ ! -d "$DEVELOPER_DIR" ]; then
  ls -d /Applications/Xcode* || true
  rot "DEVELOPER_DIR fehlt auf diesem Runner: $DEVELOPER_DIR"
  halt_bei_rot "Xcode-Fassung nicht gefunden"
fi
xcodebuild -version > "$LOGS/xcode-version.txt"
cat "$LOGS/xcode-version.txt"
xcodebuild -help > "$LOGS/xcodebuild-help.txt" 2>&1 || true
for schluessel in app-store-connect testFlightInternalTestingOnly manageAppVersionAndBuildNumber destination; do
  if grep -q -- "$schluessel" "$LOGS/xcodebuild-help.txt"; then
    echo "ok: xcodebuild -help nennt $schluessel"
  else
    rot "xcodebuild -help nennt $schluessel nicht"
  fi
done
halt_bei_rot "Export-Optionen passen nicht zu dieser Xcode-Fassung"
echo "::endgroup::"

# 2. App-Symbol: 1024 x 1024 ohne Alphakanal (ITMS-90717), erzeugt von werkzeug/erzeuge-icon.py
echo "::group::2 App-Symbol"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$ICON" > "$LOGS/app-symbol.txt"
cat "$LOGS/app-symbol.txt"
symbol() { awk -v k="$1" '$1 == k ":" { print $2 }' "$LOGS/app-symbol.txt"; }
gleich "App-Symbol Breite" "$(symbol pixelWidth)" 1024
gleich "App-Symbol Hoehe" "$(symbol pixelHeight)" 1024
gleich "App-Symbol Alphakanal" "$(symbol hasAlpha)" no
halt_bei_rot "App-Symbol falsch"
echo "::endgroup::"

# 3. XcodeGen 2.46.0 mit Pruefsumme, Projekt erzeugen, Build-Einstellungen pruefen
echo "::group::3 XcodeGen"
curl -fsSL --retry 3 -o build/werkzeug/xcodegen.zip "$XCODEGEN_URL"
echo "$XCODEGEN_SHA256  build/werkzeug/xcodegen.zip" | shasum -a 256 -c -
rm -rf build/werkzeug/xcodegen
unzip -q build/werkzeug/xcodegen.zip -d build/werkzeug
build/werkzeug/xcodegen/bin/xcodegen generate --spec project.yml
xcodebuild -project Halle.xcodeproj -scheme Halle -configuration Release \
  -destination 'generic/platform=iOS' -showBuildSettings > "$LOGS/build-settings.txt"
einstellung() {
  awk -v k="$1" '{ sub(/^[ \t]+/, "") } index($0, k " = ") == 1 { print substr($0, length(k) + 4); exit }' \
    "$LOGS/build-settings.txt"
}
gleich PLATFORM_NAME "$(einstellung PLATFORM_NAME)" iphoneos
case "$(einstellung SDKROOT)" in
  *iPhoneOS*.sdk) echo "ok: SDKROOT $(einstellung SDKROOT)" ;;
  *) rot "SDKROOT ist '$(einstellung SDKROOT)', erwartet das iPhoneOS-SDK" ;;
esac
gleich TARGETED_DEVICE_FAMILY "$(einstellung TARGETED_DEVICE_FAMILY)" 2
gleich PRODUCT_BUNDLE_IDENTIFIER "$(einstellung PRODUCT_BUNDLE_IDENTIFIER)" "$BUNDLE_ID"
gleich PRODUCT_MODULE_NAME "$(einstellung PRODUCT_MODULE_NAME)" Halle
gleich IPHONEOS_DEPLOYMENT_TARGET "$(einstellung IPHONEOS_DEPLOYMENT_TARGET)" 26.0
gleich SWIFT_VERSION "$(einstellung SWIFT_VERSION)" 5.0
halt_bei_rot "Build-Einstellungen falsch (hat XcodeGen seine Vorgaben gefunden?)"
echo "::endgroup::"

# 4. Baunummer, Xcode-Fassung, Zeitpunkt des Baus
BUILD="${GITHUB_RUN_NUMBER:-0}.${GITHUB_RUN_ATTEMPT:-1}"
HUELLE_XCODE="$(sed -n 1p "$LOGS/xcode-version.txt")"
HUELLE_GEBAUT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Baunummer $BUILD, $HUELLE_XCODE, gebaut $HUELLE_GEBAUT"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "BUILD=$BUILD" >> "$GITHUB_ENV"
  echo "HUELLE_XCODE=$HUELLE_XCODE" >> "$GITHUB_ENV"
  echo "HUELLE_GEBAUT=$HUELLE_GEBAUT" >> "$GITHUB_ENV"
fi

# 5. Archiv ohne Signatur
echo "::group::5 Archiv"
set +e
xcodebuild -project Halle.xcodeproj -scheme Halle -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Halle.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  CURRENT_PROJECT_VERSION="$BUILD" HUELLE_XCODE="$HUELLE_XCODE" HUELLE_GEBAUT="$HUELLE_GEBAUT" \
  archive > "$LOGS/archive.log" 2>&1
STATUS=$?
set -e
grep -E "(error|warning): " "$LOGS/archive.log" | awk '!gesehen[$0]++' | head -n 200 || true
tail -n 5 "$LOGS/archive.log"
echo "::endgroup::"
if [ "$STATUS" != 0 ]; then
  grep -E "error: " "$LOGS/archive.log" | awk '!gesehen[$0]++' | head -n 40 | while IFS= read -r zeile; do
    echo "::error::$zeile"
  done || true
  echo "- rot: Archiv (xcodebuild Status $STATUS), Fehler im Artefakt archive.log" >> "$ZUSAMMENFASSUNG"
  exit 1
fi

# 6. Pruefung des Archivs, bevor Apple etwas sieht
echo "::group::6 Pruefung des Archivs"
APP="build/Halle.xcarchive/Products/Applications/Halle.app"
INFO="$APP/Info.plist"
if [ ! -f "$INFO" ]; then
  rot "kein $INFO im Archiv"
  halt_bei_rot "Archiv ohne Programm"
fi
plutil -p "$INFO" > "$LOGS/archiv-info.txt"
ls -la "$APP" > "$LOGS/archiv-inhalt.txt"
wert() {
  local aus
  if aus="$(/usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null)"; then
    echo "$aus"
  else
    echo "<fehlt>"
  fi
}
anzahl() {
  local aus
  if aus="$(/usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null)"; then
    echo "$aus" | grep -c "UIInterfaceOrientation" || true
  else
    echo 0
  fi
}
MANIFEST="UIApplicationSceneManifest:UISceneConfigurations"
gleich CFBundleIdentifier "$(wert CFBundleIdentifier)" "$BUNDLE_ID"
gleich CFBundleShortVersionString "$(wert CFBundleShortVersionString)" "$VERSION"
gleich CFBundleVersion "$(wert CFBundleVersion)" "$BUILD"
gleich CFBundleDisplayName "$(wert CFBundleDisplayName)" "$ANZEIGENAME"
gleich HuelleXcode "$(wert HuelleXcode)" "$HUELLE_XCODE"
gleich HuelleGebaut "$(wert HuelleGebaut)" "$HUELLE_GEBAUT"
gleich ITSAppUsesNonExemptEncryption "$(wert ITSAppUsesNonExemptEncryption)" false
gleich "UIDeviceFamily:0" "$(wert UIDeviceFamily:0)" 2
gleich "UIDeviceFamily:1" "$(wert UIDeviceFamily:1)" "<fehlt>"
# App-Bound Domains (Bauzettel 50, § 2.2): genau die Worker-Domain, sonst kein Skript und kein Dienst (RH50-2).
case "$WORKER_HOST" in
  *.workers.dev) echo "ok: Worker-Domain $WORKER_HOST" ;;
  *) rot "WKAppBoundDomains:0 in Halle/Info.plist ist '$WORKER_HOST', erwartet eine Domain unter workers.dev" ;;
esac
gleich "WKAppBoundDomains:0" "$(wert WKAppBoundDomains:0)" "$WORKER_HOST"
gleich "WKAppBoundDomains:1" "$(wert WKAppBoundDomains:1)" "<fehlt>"
if /usr/libexec/PlistBuddy -c "Print :UILaunchScreen" "$INFO" > /dev/null 2>&1; then
  echo "ok: UILaunchScreen vorhanden"
else
  rot "UILaunchScreen fehlt"
fi
gleich UIApplicationSupportsMultipleScenes "$(wert UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes)" true
gleich "Regie: Name" "$(wert "$MANIFEST:UIWindowSceneSessionRoleApplication:0:UISceneConfigurationName")" Regie
gleich "Regie: Klasse" "$(wert "$MANIFEST:UIWindowSceneSessionRoleApplication:0:UISceneDelegateClassName")" Halle.RegieSzene
gleich "TV: Name" "$(wert "$MANIFEST:UIWindowSceneSessionRoleExternalDisplayNonInteractive:0:UISceneConfigurationName")" TV
gleich "TV: Klasse" "$(wert "$MANIFEST:UIWindowSceneSessionRoleExternalDisplayNonInteractive:0:UISceneDelegateClassName")" Halle.TvSzene
gleich "Ausrichtungen" "$(anzahl UISupportedInterfaceOrientations)" 4
gleich "Ausrichtungen~ipad" "$(anzahl 'UISupportedInterfaceOrientations~ipad')" 4
gleich "CFBundleIcons~ipad: CFBundleIconName" "$(wert 'CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconName')" AppIcon
if grep -q '\$(' "$LOGS/archiv-info.txt"; then
  rot "nicht eingesetzte Build-Einstellung in der Info.plist: $(grep '\$(' "$LOGS/archiv-info.txt" | head -n 3 | tr '\n' ' ')"
else
  echo "ok: keine Reste von \$( in der Info.plist"
fi
for datei in PrivacyInfo.xcprivacy Assets.car Halle; do
  if [ -f "$APP/$datei" ]; then echo "ok: $datei im Programm"; else rot "$datei fehlt im Programm"; fi
done
plutil -lint "$APP/PrivacyInfo.xcprivacy" || rot "PrivacyInfo.xcprivacy ist kein gueltiges Plist"
if ls build/Halle.xcarchive/dSYMs/*.dSYM > /dev/null 2>&1; then echo "ok: dSYM im Archiv"; else rot "kein dSYM im Archiv"; fi
# Welcher Zweig aus RegieController.registriereTvFuerIPadOS27 im Programm steckt: der Text der
# Registrierung nur mit Swift 6.4 (Xcode 27), sonst der Hinweis „Compiler vor Swift 6.4".
if grep -a -q "TV registriert" "$APP/Halle"; then
  WEG27="im Bau (Swift 6.4 oder neuer)"
elif grep -a -q "Compiler vor Swift 6.4" "$APP/Halle"; then
  WEG27="nicht im Bau (Compiler vor Swift 6.4)"
else
  WEG27="unbekannt"
  rot "Weg fuer iPadOS 27: keiner der beiden Texte im Programm"
fi
echo "Weg fuer iPadOS 27: $WEG27"
echo "::endgroup::"
halt_bei_rot "Pruefung des Archivs rot"

{
  echo "### Archiv geprueft"
  echo ""
  echo "- Baunummer: \`$BUILD\`, gebaut \`$HUELLE_GEBAUT\`"
  echo "- Xcode: \`$HUELLE_XCODE\`"
  echo "- Bundle-ID: \`$BUNDLE_ID\`, Name am iPad: $ANZEIGENAME"
  echo "- App-Bound Domain: \`$WORKER_HOST\`"
  echo "- Weg fuer iPadOS 27: $WEG27"
} >> "$ZUSAMMENFASSUNG"
echo "Archiv geprueft: Bau $BUILD, $HUELLE_XCODE"
