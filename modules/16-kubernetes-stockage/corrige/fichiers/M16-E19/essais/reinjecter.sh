#!/usr/bin/env bash
# reinjecter.sh — recopie dans mediagenda-db les rendez-vous d'un praticien perdus après T,
# lus dans mediagenda-db-pitr (M16-E19, étape 8). Ne touche à rien d'autre : les lignes dont
# l'identifiant existe déjà dans mediagenda-db sont ignorées (ON CONFLICT DO NOTHING).
#   ./reinjecter.sh <PRATICIEN>
# Connexion locale (socket) en postgres dans les pods, par kubectl exec, comme le fait
# « kubectl cnpg psql » : aucun mot de passe ne circule. La colonne id est GENERATED ALWAYS :
# OVERRIDING SYSTEM VALUE conserve les identifiants d'origine.
set -euo pipefail
praticien="${1:?usage : $0 <PRATICIEN>}"
[[ "$praticien" =~ ^[a-z0-9-]+$ ]] || { echo "nom de praticien inattendu" >&2; exit 2; }
ns=mediagenda-recette

primaire() {
  kubectl -n "$ns" get pod -l "cnpg.io/cluster=$1,cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}'
}
source_pod="$(primaire mediagenda-db-pitr)"
cible_pod="$(primaire mediagenda-db)"
psql_dans() { local pod="$1"; shift; kubectl -n "$ns" exec -i "$pod" -c postgres -- psql -d mediagenda -v ON_ERROR_STOP=1 "$@"; }

echo "Dans mediagenda-db-pitr ($source_pod) : $(psql_dans "$source_pod" -Atc \
  "SELECT count(*) FROM rendez_vous WHERE praticien = '$praticien'") ligne(s) pour $praticien"

# Plusieurs -c s'exécutent dans la même session (psql >= 9.6) : la table temporaire survit
# d'une commande à l'autre ; COPY … FROM STDIN lit l'entrée standard de psql.
psql_dans "$source_pod" -Atc \
  "COPY (SELECT id, patient, praticien, debut, duree_minutes, motif, cree_le
         FROM rendez_vous WHERE praticien = '$praticien') TO STDOUT WITH (FORMAT csv)" \
| psql_dans "$cible_pod" \
    -c "CREATE TEMP TABLE a_reinjecter (LIKE rendez_vous)" \
    -c "COPY a_reinjecter (id, patient, praticien, debut, duree_minutes, motif, cree_le) FROM STDIN WITH (FORMAT csv)" \
    -c "INSERT INTO rendez_vous OVERRIDING SYSTEM VALUE SELECT * FROM a_reinjecter ON CONFLICT (id) DO NOTHING"

echo "Dans mediagenda-db ($cible_pod) : $(psql_dans "$cible_pod" -Atc \
  "SELECT count(*) FROM rendez_vous WHERE praticien = '$praticien'") ligne(s) pour $praticien"
