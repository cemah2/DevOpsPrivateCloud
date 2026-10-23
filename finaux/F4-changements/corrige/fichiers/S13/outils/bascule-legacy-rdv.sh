#!/usr/bin/env bash
# bascule-legacy-rdv.sh — bascule de Legacy-RDV de legacy-rdv01 vers legacy-rdv-prod (F4-S13, CHG-3413).
# Solution de référence ; RB-346 en décrit chaque étape. Depuis adm01, avec ton identité (kubectl, SSH).
#
#   bascule-legacy-rdv.sh --pre-copie        (J-1) copie initiale des pièces jointes, horodatée
#   bascule-legacy-rdv.sh --repetition       répétition chronométrée vers legacy-rdv-recette (sans gel,
#                                            sans toucher aux répartiteurs ni à la VM)
#   bascule-legacy-rdv.sh                    VRAIE bascule (fenêtre) : gel, synchronisation, contrôles,
#                                            bascule ; s'arrête et demande confirmation aux étapes humaines
#
# État (horodatages, référence, plus grand identifiant au gel) : ~/.local/state/f4-bascule/ (700).
# Le retour arrière s'appuie sur cet état : retour-arriere-legacy-rdv.sh.
# ⚠️ La vraie bascule écrit dans legacy-rdv-prod (table rendez_vous REMPLACÉE) et retire les droits
# d'écriture de l'application sur la VM. Elle refuse de démarrer si la sonde, la base cible ou la
# sauvegarde de la VM ne sont pas prêtes.
# shellcheck disable=SC2016,SC2029  # $MARIADB_ROOT_PASSWORD s'étend DANS le pod ; noms de fichiers étendus côté adm01 (voulu)
set -euo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COPIER="${COPIER:-$ICI/../../S12/outils/copier-donnees-legacy.sh}"
VM=admin@legacy-rdv01.par1.medisphere.internal
ETAT="${XDG_STATE_HOME:-$HOME/.local/state}/f4-bascule"
URL_RDV="https://rdv.par1.medisphere.internal"
mkdir -p "$ETAT" && chmod 700 "$ETAT"

mode=bascule
case "${1:-}" in
  --pre-copie) mode=pre-copie ;;
  --repetition) mode=repetition ;;
  "") ;;
  *) echo "usage : $0 [--pre-copie|--repetition]" >&2; exit 2 ;;
esac
cible=legacy-rdv-prod
[[ "$mode" == repetition ]] && cible=legacy-rdv-recette

t0=$(date +%s)
horloge() { printf '[%s +%ss] %s\n' "$(date +%T)" "$(($(date +%s) - t0))" "$*"; }
humain() {   # humain "consigne" — étape faite par une personne (MR, annonce) : on attend sa confirmation
  printf '\n==> ÉTAPE HUMAINE : %s\n    Entrée quand c'"'"'est fait (Ctrl+C pour arrêter, puis RB-346 « retour arrière »)… ' "$*"
  read -r _
}
sql_vm() { ssh "$VM" "sudo mariadb -N -B legacy_rdv" <<<"$1"; }
pod_db() { kubectl -n "$cible" get pods -l app.kubernetes.io/instance=legacy-rdv-db -o name | grep -v metrics | head -n 1; }
sql_cible() {
  kubectl -n "$cible" exec -i "$(pod_db)" -c mariadb -- \
    sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot -N -B legacy_rdv' <<<"$1"
}
temoins() { echo "SELECT id, DATE_FORMAT(date_rdv, '%Y-%m-%d %H:%i:%s'), IFNULL(piece_jointe, '-') FROM rendez_vous WHERE praticien = 'dr-temoin' ORDER BY id;"; }
somme_vm() { ssh "$VM" "sudo sha256sum /var/www/legacy-rdv/uploads/$1" | awk '{print $1}'; }
somme_cible() { kubectl -n "$cible" exec deploy/legacy-rdv -c web -- sha256sum "/var/www/legacy-rdv/uploads/$1" | awk '{print $1}'; }

if [[ "$mode" == pre-copie ]]; then
  date '+%F %T' > "$ETAT/pre-copie"
  horloge "copie initiale des pièces jointes vers legacy-rdv-prod (horodatage : $(cat "$ETAT/pre-copie"))"
  "$COPIER" --espace legacy-rdv-prod --pieces
  exit 0
fi

# --- 0. Go / no-go -----------------------------------------------------------------------------------
horloge "contrôles préalables ($mode vers $cible)"
kubectl -n "$cible" get mariadb legacy-rdv-db -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' | grep -qx True \
  || { echo "NO-GO : la MariaDB de $cible n'est pas prête" >&2; exit 1; }
kubectl -n "$cible" rollout status deploy/legacy-rdv --timeout=60s >/dev/null \
  || { echo "NO-GO : Legacy-RDV n'est pas déployé et prêt dans $cible" >&2; exit 1; }
if [[ "$mode" == bascule ]]; then
  [[ -s "$ETAT/pre-copie" ]] || { echo "NO-GO : pas de pré-copie des pièces jointes (--pre-copie la veille)" >&2; exit 1; }
  humain "go/no-go de CHG-3413 décidé et noté dans la fiche (sonde verte, sauvegarde PBS de 3401 du matin vérifiée, astreinte prête)"

  # --- 1. Gel ------------------------------------------------------------------------------------------
  humain "fusionner la MR « legacy_rdv_cible: maintenance » et jouer les répartiteurs (lb02 puis lb01) ; la page de maintenance s'affiche sur $URL_RDV"
  horloge "gel : droits d'écriture de l'application retirés sur legacy-rdv01"
  sql_vm "REVOKE INSERT, UPDATE, DELETE ON legacy_rdv.* FROM 'legacy_rdv'@'localhost';"
  if sql_vm "SHOW GRANTS FOR 'legacy_rdv'@'localhost';" | grep -Eq 'INSERT|UPDATE|DELETE'; then
    echo "le compte applicatif a encore des droits d'écriture : arrêt" >&2; exit 1
  fi
  date '+%F %T' > "$ETAT/gel"
fi

# --- 2. Référence --------------------------------------------------------------------------------------
reference="$(sql_vm 'SELECT COUNT(*) FROM rendez_vous;')"
max_id="$(sql_vm 'SELECT IFNULL(MAX(id), 0) FROM rendez_vous;')"
printf '%s\n' "$reference" > "$ETAT/reference-$mode"
printf '%s\n' "$max_id" > "$ETAT/max-id-$mode"
horloge "Référence rendez-vous : $reference (identifiant max. $max_id) — à recopier dans CHG-3413"

# --- 3. Base -------------------------------------------------------------------------------------------
horloge "base : vidage logique legacy-rdv01 -> $cible"
FORCER_PROD=oui "$COPIER" --espace "$cible" --base

# --- 4. Pièces jointes -----------------------------------------------------------------------------------
if [[ "$mode" == bascule ]]; then
  horloge "pièces jointes : rattrapage depuis $(cat "$ETAT/pre-copie")"
  "$COPIER" --espace "$cible" --pieces --depuis "$(cat "$ETAT/pre-copie")"
else
  "$COPIER" --espace "$cible" --pieces
fi

# --- 5. Contrôles ---------------------------------------------------------------------------------------
horloge "contrôles"
n_cible="$(sql_cible 'SELECT COUNT(*) FROM rendez_vous;')"
[[ "$n_cible" == "$reference" ]] || { echo "ÉCART : $reference rendez-vous à la source, $n_cible dans $cible" >&2; exit 1; }
diff <(sql_vm "$(temoins)") <(sql_cible "$(temoins)") \
  || { echo "ÉCART sur les rendez-vous témoins (date, heure ou pièce)" >&2; exit 1; }
diff <(sql_vm "SELECT DATE_FORMAT(date_rdv, '%Y-%m-%d %H:%i:%s'), praticien FROM rendez_vous ORDER BY id;" | sha256sum) \
     <(sql_cible "SELECT DATE_FORMAT(date_rdv, '%Y-%m-%d %H:%i:%s'), praticien FROM rendez_vous ORDER BY id;" | sha256sum) \
  || { echo "ÉCART : au moins une date de rendez-vous diffère entre la source et $cible" >&2; exit 1; }
echo "   rendez-vous : $reference des deux côtés ; témoins et empreinte des dates identiques"
mapfile -t echantillon < <(ssh "$VM" "sudo find /var/www/legacy-rdv/uploads -type f -name '*.pdf' -printf '%f\n' | shuf -n 10"; \
  ssh "$VM" "sudo find /var/www/legacy-rdv/uploads -type f -name '*temoin*' -printf '%f\n'")
for f in "${echantillon[@]}"; do
  [[ "$(somme_vm "$f")" == "$(somme_cible "$f")" ]] || { echo "ÉCART : pièce $f différente ou absente" >&2; exit 1; }
done
echo "   pièces jointes : ${#echantillon[@]} fichiers identiques (échantillon + témoin)"

if [[ "$mode" == repetition ]]; then
  horloge "répétition terminée : durée totale $(($(date +%s) - t0)) s (à reporter dans CHG-3413)"
  exit 0
fi

# --- 6. Bascule du nom publié --------------------------------------------------------------------------
humain "fusionner la MR « legacy_rdv_cible: k8s » et jouer les répartiteurs (lb02, contrôle, lb01)"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$URL_RDV/")"
[[ "$code" == 200 ]] || { echo "ATTENTION : $URL_RDV répond $code : retour arrière (RB-346) si non résolu dans la fenêtre" >&2; exit 1; }
date '+%F %T' > "$ETAT/bascule"
horloge "Legacy-RDV servi par Kubernetes sur $URL_RDV"

# --- 7. Après --------------------------------------------------------------------------------------------
horloge "stats01 : tâche nocturne désactivée (décision CHG-3413 : aucun lecteur depuis 2020)"
ssh admin@stats01.par1.medisphere.internal "sudo test -f /etc/cron.d/stats-rdv && sudo mv /etc/cron.d/stats-rdv /root/stats-rdv.cron.desactive || true"
humain "contrôles fonctionnels par l'URL des cabinets (consultation, prise de RDV de test puis annulation, pièce jointe), annonce de fin par Nadia"
horloge "bascule terminée en $(($(date +%s) - t0)) s ; gel à $(cat "$ETAT/gel"), bascule à $(cat "$ETAT/bascule")"
