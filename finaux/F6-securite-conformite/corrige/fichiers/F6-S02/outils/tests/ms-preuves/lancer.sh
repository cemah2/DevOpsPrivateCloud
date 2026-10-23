#!/usr/bin/env bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# tests/ms-preuves/lancer.sh — tests de ms-preuves sans aucun service réel (F6-S02, PLAT-3602).
# Faux yq, cosign et aws (dossier faux/) ; collecteurs de test (dossier collecteurs/) ; compartiment
# simulé dans un dossier temporaire. On vérifie la logique (statuts, garde-fous, manifeste, signature,
# dépôt, vérification, codes retour), pas RGW ni OpenBao.
# Lancé par la CI de plateforme/outils (job test:ms-preuves) et à la main : tests/ms-preuves/lancer.sh
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTIL="$ICI/../../bin/ms-preuves"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/s3/preuves-conformite" "$T/lots"
printf 'fausse clé publique\n' >"$T/cle.pub"
export PATH="$ICI/faux:$PATH" FAUX_S3="$T/s3" FAUX_CATALOGUE_JSON="$ICI/catalogue-test.json"
export MS_PREUVES_CATALOGUE="$ICI/catalogue-test.yaml" MS_PREUVES_COLLECTEURS="$ICI/collecteurs"
export MS_PREUVES_SORTIE="$T/lots" MS_PREUVES_CLE_PUBLIQUE="$T/cle.pub" MS_PREUVES_DELAI=10
echecs=0

attendu() { # attendu "description" CODE_ATTENDU commande…
  local d="$1" c="$2" r=0
  shift 2
  "$@" >/dev/null 2>&1 || r=$?
  if [[ "$r" == "$c" ]]; then echo "ok    $d"; else echo "ÉCHEC $d (code $r, attendu $c)"; echecs=$((echecs + 1)); fi
}
vrai() { # vrai "description" commande… (code 0 attendu, sortie ignorée)
  local d="$1"
  shift
  if "$@" >/dev/null 2>&1; then echo "ok    $d"; else echo "ÉCHEC $d"; echecs=$((echecs + 1)); fi
}

attendu "usage : sans argument → 2" 2 "$OUTIL"
attendu "usage : sous-commande inconnue → 2" 2 "$OUTIL" effacer
attendu "fréquence invalide → 2" 2 "$OUTIL" collecter --frequence annuelle

# 1. Collecte quotidienne : deux preuves valides, lot complet.
L1="$("$OUTIL" collecter --frequence quotidienne 2>/dev/null | tail -n 1)"
vrai "collecte quotidienne : lot créé" test -f "$L1/lot.json"
vrai "collecte quotidienne : lot complet, 2 preuves" jq -e '.resultat == "complet" and .compte.ok == 2' "$L1/lot.json"
vrai "empreinte de chaque preuve dans lot.json" \
  jq -e --arg h "$(sha256sum "$L1/preuves/P-TST-01.json" | cut -d' ' -f1)" '.preuves[] | select(.id == "P-TST-01") | .sha256 == $h' "$L1/lot.json"

# 2. Collecte hebdomadaire : un échec et une fuite de secret → lot partiel, secret jamais conservé.
L2="$("$OUTIL" collecter --frequence hebdomadaire 2>/dev/null | tail -n 1)"
vrai "collecteur en échec → statut echec, lot partiel" \
  jq -e '.resultat == "partiel" and (.preuves[] | select(.id == "P-TST-03") | .statut == "echec")' "$L2/lot.json"
vrai "secret détecté → preuve refusée" jq -e '.preuves[] | select(.id == "P-TST-04") | .statut == "refusee"' "$L2/lot.json"
if grep -rq 'tres-secret' "$L2"; then echo "ÉCHEC le secret est resté dans le lot"; echecs=$((echecs + 1)); else echo "ok    le secret n'est écrit nulle part dans le lot"; fi
L3="$("$OUTIL" collecter --frequence mensuelle 2>/dev/null | tail -n 1)"
vrai "collecteur absent → code 127, lot partiel" jq -e '.preuves[0].code == 127 and .resultat == "partiel"' "$L3/lot.json"

# 3. Signature : manifeste complet, pas de double signature.
vrai "signer : manifeste et bundle écrits" "$OUTIL" signer "$L1"
vrai "manifeste : preuves, journaux et lot.json" bash -c "grep -q 'preuves/P-TST-01.json' '$L1/MANIFESTE.sha256' && grep -q 'lot.json' '$L1/MANIFESTE.sha256' && grep -q 'journal/' '$L1/MANIFESTE.sha256'"
attendu "re-signer un lot → refus (3)" 3 "$OUTIL" signer "$L1"
attendu "signature refusée par le coffre → 1" 1 env FAUX_COSIGN_REFUS=1 "$OUTIL" signer "$L3"

# 4. Dépôt : garde-fous du compartiment, rétention vérifiée, pas d'écrasement.
attendu "déposer un lot non signé → refus (3)" 3 "$OUTIL" deposer "$L2"
attendu "compartiment sans verrouillage → refus (3)" 3 env FAUX_VERROU=aucun "$OUTIL" deposer "$L1"
attendu "verrouillage sans rétention par défaut → refus (3)" 3 env FAUX_VERROU=sans-regle "$OUTIL" deposer "$L1"
attendu "objets déposés sans rétention → refus (3)" 3 env FAUX_S3_SANS_RETENTION=1 "$OUTIL" deposer "$L1"
rm -rf "${T:?}/s3/preuves-conformite/lots"
vrai "déposer : succès" "$OUTIL" deposer "$L1"
LOT="$(jq -r .lot "$L1/lot.json")"
P="lots/${LOT:0:4}/${LOT:4:2}/${LOT:6:2}/$LOT"
vrai "objets dans le compartiment, bundle compris" test -f "$T/s3/preuves-conformite/$P/MANIFESTE.sha256.sigstore.json"
vrai "DEPOT.json : modes et échéances relevés" jq -e '(.objets | length) >= 5 and all(.objets[]; .mode == "GOVERNANCE")' "$L1/DEPOT.json"
attendu "déposer deux fois → refus (3)" 3 "$OUTIL" deposer "$L1"

# 5. Vérification : intacte, puis altérée.
vrai "vérifier le lot local : OK" "$OUTIL" verifier "$L1"
vrai "vérifier le lot du compartiment : OK" "$OUTIL" verifier "s3://preuves-conformite/$P/"
vrai "lister : le lot apparaît" bash -c "'$OUTIL' lister 2>/dev/null | grep -q '$LOT'"
cp "$T/s3/preuves-conformite/$P/preuves/P-TST-01.json" "$T/orig.json"
printf '{"preuve":"P-TST-01","valeur":43}\n' >"$T/s3/preuves-conformite/$P/preuves/P-TST-01.json"
attendu "preuve modifiée dans le compartiment → 1" 1 "$OUTIL" verifier "s3://preuves-conformite/$P/"
cp "$T/orig.json" "$T/s3/preuves-conformite/$P/preuves/P-TST-01.json"
printf 'ajout\n' >"$T/s3/preuves-conformite/$P/preuves/P-TST-99.txt"
attendu "fichier ajouté hors manifeste → 1" 1 "$OUTIL" verifier "s3://preuves-conformite/$P/"
rm -f "$T/s3/preuves-conformite/$P/preuves/P-TST-99.txt"
printf '%s\n' "$(sed 's/P-TST-02/P-TST-0X/' "$L1/MANIFESTE.sha256")" >"$L1/MANIFESTE.sha256"
attendu "manifeste réécrit après signature → 1" 1 "$OUTIL" verifier "$L1"

((echecs == 0)) || { echo "$echecs test(s) en échec"; exit 1; }
echo "tous les tests passent"
