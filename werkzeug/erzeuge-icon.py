"""Schreibt das App-Symbol der Huelle aus dem SLSHM-Monogramm (Bauzettel 50, § 2.8 und § 12 Nr. 2).

Quelle: symbol/slshm-monogramm.pdf, Alex' Datei „SLSHM MONOGRAM NEW.ai" (Adobe Illustrator,
PDF-kompatibel). Das Monogramm sind fuenf gefuellte Vektorpfade: der Rahmen in Dunkelgruen (#013516),
das S in Gruen (#005B27) und der Stern in Gold (#EFB600). Die Geometrie wird unveraendert uebernommen.

Grund ist Dunkelgruen #003223 aus der CI. Darauf waeren die beiden Gruen des Originals kaum zu sehen,
darum wird das Monogramm hell gesetzt und behaelt die Rangfolge des Originals (Rahmen zurueck, S vorn):
- Rahmen: Licht #EEF1EE zu 55 % ueber dem Grund (ergibt #839B93),
- S: Weiss #FFFFFF,
- Stern: Originalfarbe.
Pfade gleicher Farbe werden als ein Pfad gefuellt, sonst zeigt die Kantenglaettung eine Naht, wo sie
aneinanderstossen.

Ziel: Halle/Assets.xcassets/AppIcon.appiconset/icon-1024.png, 1024 x 1024 Pixel, PNG in RGB ohne
Alphakanal (Farbtyp 2), weil der Upload ein grosses Symbol mit Alphakanal ablehnt (ITMS-90717,
Bauzettel 45 § 4). Braucht PyMuPDF (`pip install pymupdf`). Einmal am PC ausgefuehrt, das PNG ist
eingecheckt; der Pruef-Job prueft Groesse und Alphakanal und legt es als Artefakt ab.
"""

import pathlib

import fitz  # PyMuPDF

WURZEL = pathlib.Path(__file__).resolve().parent.parent
QUELLE = WURZEL / "symbol" / "slshm-monogramm.pdf"
ZIEL = WURZEL / "Halle" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png"

GROESSE = 1024
# Hoehe des Monogramms samt Stern als Anteil der Kante; der Rest ist Rand fuer die Maske des Systems.
HOEHE = 0.74

GRUND = (0x00, 0x32, 0x23)  # CI Dunkelgruen
LICHT = (0xEE, 0xF1, 0xEE)  # CI Licht
WEISS = (0xFF, 0xFF, 0xFF)  # CI Weiss


def mische(vorn, hinten, anteil):
    return tuple(round(v * anteil + h * (1 - anteil)) for v, h in zip(vorn, hinten))


# Originalfarbe (gerundet auf 0..255) zu Farbe im Symbol; der Stern bleibt.
UMFAERBUNG = {
    (1, 53, 22): mische(LICHT, GRUND, 0.55),  # Rahmen
    (0, 91, 39): WEISS,  # S
    (239, 182, 0): (239, 182, 0),  # Stern
}


def rgb255(farbe):
    return tuple(round(k * 255) for k in farbe)


def anteile(rgb):
    return tuple(k / 255 for k in rgb)


def main():
    pfade = fitz.open(QUELLE)[0].get_drawings()
    umriss = pfade[0]["rect"]
    gruppen = {}  # Zielfarbe zu Liste von Linienzuegen, in der Reihenfolge des ersten Auftretens
    for pfad in pfade:
        umriss |= pfad["rect"]
        quelle = rgb255(pfad["fill"])
        if quelle not in UMFAERBUNG:
            raise SystemExit(f"unbekannte Farbe {quelle} in {QUELLE.name}")
        for teil in pfad["items"]:
            if teil[0] != "l":
                raise SystemExit(f"unerwartetes Pfadstueck {teil[0]} in {QUELLE.name}")
        gruppen.setdefault(UMFAERBUNG[quelle], []).append([teil[1:] for teil in pfad["items"]])

    massstab = HOEHE * GROESSE / umriss.height
    verschub = fitz.Point(
        GROESSE / 2 - (umriss.x0 + umriss.width / 2) * massstab,
        GROESSE / 2 - (umriss.y0 + umriss.height / 2) * massstab,
    )

    seite = fitz.open().new_page(width=GROESSE, height=GROESSE)
    seite.draw_rect(seite.rect, color=None, fill=anteile(GRUND))
    for farbe, zuege in gruppen.items():
        form = seite.new_shape()
        for zug in zuege:
            for von, bis in zug:
                form.draw_line(von * massstab + verschub, bis * massstab + verschub)
        form.finish(color=None, fill=anteile(farbe), closePath=True)
        form.commit()

    bild = seite.get_pixmap(dpi=72, alpha=False)
    bild.save(ZIEL)
    daten = ZIEL.read_bytes()
    breite = int.from_bytes(daten[16:20], "big")
    hoehe = int.from_bytes(daten[20:24], "big")
    # Kontrolle: Groesse und Farbtyp 2 (RGB ohne Alpha) im IHDR.
    assert (breite, hoehe, daten[25]) == (GROESSE, GROESSE, 2), (breite, hoehe, daten[25])
    print(f"{ZIEL} ({len(daten)} Bytes, {breite} x {hoehe}, RGB ohne Alpha)")


if __name__ == "__main__":
    main()
