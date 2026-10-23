"""Schreibt das App-Symbol der Huelle aus dem SLSHM-Monogramm (Bauzettel 50, § 2.8 und § 12 Nr. 2).

Quelle: die Illustrator-Datei des Monogramms („SLSHM MONOGRAM NEW.ai", PDF-kompatibel) oder ein PDF
daraus. Sie liegt nicht im Repo (das Repo ist oeffentlich, die Datei traegt Illustrator-Metadaten) und
wird als Pfad ausserhalb des Repos uebergeben:

    python werkzeug/erzeuge-icon.py PFAD/ZUR/QUELLE.ai

Das Monogramm sind fuenf gefuellte Vektorpfade: der Rahmen in Dunkelgruen (#013516), das S in Gruen
(#005B27) und der Stern in Gold (#EFB600). Die Geometrie wird unveraendert uebernommen.

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

import argparse
import pathlib

import fitz  # PyMuPDF

WURZEL = pathlib.Path(__file__).resolve().parent.parent
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


def quelle_lesen():
    """Pfad der Quelle aus dem Argument; sie muss ausserhalb des Repos liegen."""
    leser = argparse.ArgumentParser(description="Schreibt das App-Symbol aus dem SLSHM-Monogramm.")
    leser.add_argument("quelle", type=pathlib.Path, help="Illustrator-Datei (.ai) oder PDF ausserhalb des Repos")
    quelle = leser.parse_args().quelle.resolve()
    if not quelle.is_file():
        raise SystemExit(f"Quelle {quelle} nicht gefunden")
    if quelle.is_relative_to(WURZEL):
        raise SystemExit(f"Quelle {quelle} liegt im Repo; sie gehoert nicht ins oeffentliche Repo")
    return quelle


def main():
    quelle = quelle_lesen()
    # Illustrator speichert PDF-kompatibel; mit filetype oeffnet PyMuPDF auch die Endung .ai.
    pfade = fitz.open(quelle, filetype="pdf")[0].get_drawings()
    umriss = pfade[0]["rect"]
    gruppen = {}  # Zielfarbe zu Liste von Linienzuegen, in der Reihenfolge des ersten Auftretens
    for pfad in pfade:
        umriss |= pfad["rect"]
        original = rgb255(pfad["fill"])
        if original not in UMFAERBUNG:
            raise SystemExit(f"unbekannte Farbe {original} in {quelle.name}")
        for teil in pfad["items"]:
            if teil[0] != "l":
                raise SystemExit(f"unerwartetes Pfadstueck {teil[0]} in {quelle.name}")
        gruppen.setdefault(UMFAERBUNG[original], []).append([teil[1:] for teil in pfad["items"]])

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
