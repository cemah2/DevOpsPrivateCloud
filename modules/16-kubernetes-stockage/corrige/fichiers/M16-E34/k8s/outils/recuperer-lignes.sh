#!/usr/bin/env bash
# plateforme/k8s — outils/recuperer-lignes.sh (M16-E34, modèle pour RB-162)
# Récupération SÉLECTIVE : copie des lignes de rendez_vous d'un cluster d'enquête vers la base de
# production, sans rien écraser.
#   1. extrait du cluster d'enquête les lignes du praticien (COPY … TO STDOUT, format binaire de COPY
#      non : CSV, pour pouvoir le relire) dans un fichier 600 de adm01 ;
#   2. les charge dans une table de travail de la production (transaction unique) ;
#   3. insère avec OVERRIDING SYSTEM VALUE (mêmes identifiants) celles qui n'existent plus et dont le
#      créneau (praticien, début) est libre ; liste les conflits (identifiants seulement) ;
#   4. efface le fichier (shred).
# Usage : recuperer-lignes.sh --praticien ID [--enquete mediagenda-db-enquete] [--appliquer]
#         Sans --appliquer : simulation (même transaction, terminée par ROLLBACK).
set -euo pipefail

ns=mediagenda-recette
prod=mediagenda-db
enquete=mediagenda-db-enquete
praticien=""
fin=ROLLBACK
while (($#)); do
  case "$1" in
    --praticien) praticien="$2"; shift 2 ;;
    --enquete) enquete="$2"; shift 2 ;;
    --appliquer) fin=COMMIT; shift ;;
    *) echo "option inconnue : $1" >&2; exit 2 ;;
  esac
done
[[ "$praticien" =~ ^[a-z0-9-]+$ ]] || { echo "--praticien attend un identifiant (ex. dr-garnier)" >&2; exit 2; }

base="$(kubectl get cluster "$prod" -n "$ns" -o jsonpath='{.spec.bootstrap.initdb.database}')"
base="${base:-app}"
p_prod="$(kubectl get cluster "$prod" -n "$ns" -o jsonpath='{.status.currentPrimary}')"
p_enq="$(kubectl get cluster "$enquete" -n "$ns" -o jsonpath='{.status.currentPrimary}')"
[[ -n "$p_prod" && -n "$p_enq" ]] || { echo "primaire introuvable" >&2; exit 1; }

umask 077
f="$(mktemp "$HOME/m16/e34/extraction.XXXXXX.csv")"
trap 'shred -u "$f" 2>/dev/null || rm -f "$f"' EXIT

# 1. Extraction (le cluster d'enquête est en lecture/écriture après la récupération : on ne lit que).
kubectl exec -n "$ns" "$p_enq" -c postgres -- psql -X -q -v ON_ERROR_STOP=1 -d "$base" -c \
  "COPY (SELECT id, patient, praticien, debut, duree_minutes, motif, cree_le FROM rendez_vous
         WHERE praticien = '$praticien' ORDER BY id) TO STDOUT WITH (FORMAT csv)" >"$f"
echo "$(wc -l <"$f") ligne(s) de $praticien dans le cluster d'enquête."

# 2-3. Chargement et réinsertion dans UNE transaction (simulation par défaut).
{
  echo "BEGIN;"
  echo "CREATE TEMP TABLE recup (LIKE rendez_vous INCLUDING DEFAULTS) ON COMMIT DROP;"
  echo "ALTER TABLE recup ALTER COLUMN id DROP IDENTITY IF EXISTS;"
  echo "COPY recup (id, patient, praticien, debut, duree_minutes, motif, cree_le) FROM STDIN WITH (FORMAT csv);"
  cat "$f"
  echo '\.'
  cat <<'SQL'
-- Conflits : créneau repris depuis l'erreur (même praticien, même début, autre identifiant).
SELECT 'CONFLIT ' || r.id || ' (créneau repris par ' || p.id || ')'
  FROM recup r JOIN rendez_vous p ON p.praticien = r.praticien AND p.debut = r.debut AND p.id <> r.id;
-- Réinsertion : lignes absentes de la production, créneau libre, mêmes identifiants.
WITH ins AS (
  INSERT INTO rendez_vous (id, patient, praticien, debut, duree_minutes, motif, cree_le)
  OVERRIDING SYSTEM VALUE
  SELECT r.id, r.patient, r.praticien, r.debut, r.duree_minutes, r.motif, r.cree_le
    FROM recup r
   WHERE NOT EXISTS (SELECT 1 FROM rendez_vous p WHERE p.id = r.id)
     AND NOT EXISTS (SELECT 1 FROM rendez_vous p WHERE p.praticien = r.praticien AND p.debut = r.debut)
  RETURNING id)
SELECT 'REINSERE ' || count(*) || ' : ' || coalesce(string_agg(id::text, ' ' ORDER BY id), '') FROM ins;
SQL
  echo "$fin;"
} | kubectl exec -i -n "$ns" "$p_prod" -c postgres -- psql -X -q -At -v ON_ERROR_STOP=1 -d "$base"

[[ "$fin" == COMMIT ]] && echo "Appliqué." || echo "Simulation : rien n'a été écrit (relance avec --appliquer)."
