# Abweichungen zwischen dem Vertrag der Web-App ($w: huelle-vertrag.json, Build von
# packages/protocol/src/huelle.ts) und den Formen, die Swift sendet und liest ($s: build/swift-vertrag.json
# aus werkzeug/swift-vertrag.sh), je eine Zeile, in beide Richtungen. Aufruf aus werkzeug/vertrag.sh:
#   jq -n -r --slurpfile w VERTRAG --slurpfile s SWIFT -f werkzeug/vertrag.jq
# Felder sind Name auf Typ; ein ? am Ende des Namens heisst Kann-Feld.

def form:
  to_entries
  | map({ key: (.key | rtrimstr("?")), value: { typ: .value, kann: (.key | endswith("?")) } })
  | from_entries;

def schnitt($a; $b): $a - ($a - $b);

def pflicht($kann): if $kann then "Kann-Feld" else "Pflichtfeld" end;

# Felder in beide Richtungen: fehlt bei Swift, nur bei Swift, anderer Typ, Kann oder Pflicht
def felder($wo; $soll; $ist):
  ($soll | form) as $a
  | ($ist | form) as $b
  | ( ($a | keys) - ($b | keys) | .[] | "\($wo): Feld \(.) (\($a[.].typ)) fehlt bei Swift" ),
    ( ($b | keys) - ($a | keys) | .[] | "\($wo): Feld \(.) (\($b[.].typ)) gibt es nur bei Swift, der Vertrag kennt es nicht" ),
    ( schnitt($a | keys; $b | keys)[] as $f
      | ( select($a[$f].typ != $b[$f].typ)
          | "\($wo): Feld \($f) ist bei Swift \($b[$f].typ), im Vertrag \($a[$f].typ)" ),
        ( select($a[$f].kann != $b[$f].kann)
          | "\($wo): Feld \($f) ist bei Swift \(pflicht($b[$f].kann)), im Vertrag \(pflicht($a[$f].kann))" ) );

$w[0] as $w
| $s[0] as $s
| ([$s.rollen[].faehigkeiten[]] | unique) as $sf
| ([$s.rollen[].ereignisse[]] | unique) as $se
| ([$s.rollen[].nachrichten[]] | unique) as $sn
| ( select($w.vertrag != $s.vertrag) | "Nummer: Swift \($s.vertrag), Web \($w.vertrag)" ),
  felder("Umschlag"; $w.umschlag; $s.umschlag),
  felder("Start"; $w.start; $s.start),
  ( ($s.rollen | keys) - $w.rollen | .[] | "Rolle \(.): nur Swift kennt sie" ),
  ( $w.rollen - ($s.rollen | keys) | .[] | "Rolle \(.): Swift meldet fuer sie nichts" ),
  # Swift an Web: was Swift einer Rolle meldet, sendet oder von ihr liest, kennt der Vertrag, und die
  # Rolle hat die Faehigkeit dazu (ohne sie verwirft die Seite das Ereignis und sendet die Nachricht nie)
  ( $s.rollen | to_entries[] | .key as $r | .value as $v
    | ( $v.faehigkeiten - $w.faehigkeiten | .[]
        | "\($r): Swift meldet Faehigkeit \(.), die Web-App kennt sie nicht" ),
      ( $v.ereignisse[] as $e
        | if ($w.ereignisse | has($e) | not) then
            "\($r): Swift sendet Ereignis \($e), die Web-App kennt es nicht"
          elif ($w.ereignisse[$e].faehigkeit | IN($v.faehigkeiten[]) | not) then
            "\($r): Swift sendet Ereignis \($e) ohne die Faehigkeit \($w.ereignisse[$e].faehigkeit); die Seite verwirft es"
          else empty end ),
      ( $v.nachrichten[] as $n
        | if ($w.nachrichten | has($n) | not) then
            "\($r): Swift liest Nachricht \($n), die Web-App kennt sie nicht"
          elif ($w.nachrichten[$n].faehigkeit | IN($v.faehigkeiten[]) | not) then
            "\($r): Swift liest Nachricht \($n) ohne die Faehigkeit \($w.nachrichten[$n].faehigkeit); die Seite sendet sie nie"
          else empty end ) ),
  # Web an Swift: zu jeder Faehigkeit, die Swift meldet, sendet Swift die Ereignisse des Vertrags und
  # liest seine Nachrichten (Web vor Swift: Wege zu Faehigkeiten, die Swift nicht meldet, zaehlen nicht)
  ( $w.ereignisse | to_entries[]
    | select(.value.faehigkeit | IN($sf[])) | select(.key | IN($se[]) | not)
    | "Ereignis \(.key): gehoert zur Faehigkeit \(.value.faehigkeit), die Swift meldet; Swift sendet es nie" ),
  ( $w.nachrichten | to_entries[]
    | select(.value.faehigkeit | IN($sf[])) | select(.key | IN($sn[]) | not)
    | "Nachricht \(.key): gehoert zur Faehigkeit \(.value.faehigkeit), die Swift meldet; Swift liest sie nie" ),
  # Swift selbst: was es sendet oder liest, hat eine Form, und jede Form gehoert zu einer Rolle
  ( $se - ($s.ereignisse | keys) | .[] | "Ereignis \(.): Swift sendet es ohne Form" ),
  ( ($s.ereignisse | keys) - $se | .[] | "Ereignis \(.): Swift hat eine Form, sendet es aber keiner Rolle" ),
  ( $sn - ($s.nachrichten | keys) | .[] | "Nachricht \(.): Swift liest sie ohne Form" ),
  ( ($s.nachrichten | keys) - $sn | .[] | "Nachricht \(.): Swift hat eine Form, liest sie aber von keiner Rolle" ),
  # Felder mit Typen, in beide Richtungen
  ( schnitt($w.ereignisse | keys; $s.ereignisse | keys)[] as $e
    | felder("Ereignis \($e)"; $w.ereignisse[$e].felder; $s.ereignisse[$e]) ),
  ( schnitt($w.nachrichten | keys; $s.nachrichten | keys)[] as $n
    | felder("Nachricht \($n)"; $w.nachrichten[$n].felder; $s.nachrichten[$n]) ),
  # Typen, die der Vertrag nicht kennt (etwa null), auch auf Wegen ohne Gegenstueck im Vertrag
  ( [ $s.umschlag[], $s.start[], ($s.ereignisse[] | .[]), ($s.nachrichten[] | .[]) ] | unique - $w.typen | .[]
    | "Typ \(.): Swift sendet oder liest ihn, der Vertrag kennt ihn nicht" )
