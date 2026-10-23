# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et scripts distants entre apostrophes
# _f3-fin-pannes.sh — fonctions partagées par les incidents de jeudi et vendredi du final F3
# (break-S10.sh à break-S13.sh). Préfixe f3fp_.
#
# Sourcé APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_kubectl, wb_k8s_sauver, wb_avert, WB_EX, WB_VAR…) ;
# lab/bin/break a déjà chargé lab/lib/check-lib.sh (remote, prom_requete…).
# Rappel : lab/bin/break tourne sous « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande n'y échoue sans « || true ».
#
# Règles (CONVENTIONS §8, PLAN §4.14 « Pannes des finaux », règles des blocs C à G) :
#   - contrôle préalable : le lab doit être SAIN (contrôle commun de _f3-commun.sh, puis contrôles
#     propres à l'incident) ; sinon rien n'est injecté ;
#   - sauvegarde avant toute modification (objets Kubernetes par wb_k8s_sauver, fichiers d'un hôte par
#     sauver(), configuration d'OpenBao ou de RabbitMQ en JSON dans l'état local) ;
#   - kms01 jamais touché ; au plus un nœud de la grappe OpenBao arrêté ; aucune perte de message ;
#     aucun PVC, aucune sauvegarde, aucune archive de WAL touchés ; aucune action qui détruise une
#     preuve de sécurité ;
#   - état local de chaque incident : ~/.local/state/workbook/F3-SXX/ (700) sur adm01. Les checks de
#     F3 peuvent le LIRE (nom du pod visé en S12, par exemple), jamais le modifier.

# Fonctions communes du final (état local, contrôle préalable, symptôme, GitLab…) : _f3-commun.sh
# (préfixe _f3p_), qui charge aussi le contrôle de santé de S01 (checks/_f3-sante.sh, préfixe _f3s_).
# shellcheck source=_f3-commun.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-commun.sh"

# ---------------------------------------------------------------------------
# État local (adm01) : même dossier que _f3p_etat (~/.local/state/workbook/F3-SXX/)
# ---------------------------------------------------------------------------

f3fp_etat() { _f3p_etat "$@"; }
f3fp_ecrire() { _f3p_ecrire "$@"; }
f3fp_lire() { _f3p_lire "$@"; }
f3fp_oublier() { _f3p_oublier "$@"; }
f3fp_journal() { _f3p_journal "$@"; }
# f3fp_ecrire_si_absent SXX FICHIER VALEUR — une seule sauvegarde par incident : on ne capture jamais
#   un état déjà cassé (relance après une injection interrompue).
f3fp_ecrire_si_absent() { local d; d="$(f3fp_etat "$1")"; [[ -e "$d/$2" ]] || (umask 077 && printf '%s\n' "$3" >"$d/$2"); }
f3fp_existe() { [[ -e "$(f3fp_etat "$1")/$2" ]]; }

# f3fp_attendre SECONDES COMMANDE… — réessaie toutes les 5 s jusqu'au succès ou au délai (sorties tues).
f3fp_attendre() {
  local delai="$1" fin
  shift
  fin=$((SECONDS + delai))
  while ((SECONDS < fin)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 5
  done
  "$@" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Contrôle préalable
# ---------------------------------------------------------------------------

# f3fp_preparer SXX [outils…] — contrôle commun du final (outils, aucune autre panne active, santé de
#   S01 : _f3p_preparer) ; les contrôles propres à l'incident sont faits ensuite par chaque script.
f3fp_preparer() { _f3p_preparer "$@"; }

# f3fp_refus "raison" — refus d'une injection pour un contrôle propre à l'incident.
f3fp_refus() {
  echo "Injection refusée : $_F3P_REFUS ($*)." >&2
  return 1
}

# ---------------------------------------------------------------------------
# Kubernetes
# ---------------------------------------------------------------------------

# f3fp_condition JSON TYPE [STATUT=True] — l'objet JSON a la condition TYPE au statut donné.
f3fp_condition() {
  jq -e --arg t "$2" --arg s "${3:-True}" '[.status.conditions[]? | select(.type == $t and .status == $s)] | length > 0' \
    >/dev/null 2>&1 <<<"$1"
}

# f3fp_es_rafraichir ESPACE NOM — rafraîchissement immédiat d'un ExternalSecret (annotation force-sync).
f3fp_es_rafraichir() {
  wb_kubectl -n "$1" annotate externalsecrets.external-secrets.io "$2" "force-sync=$(date +%s)" --overwrite >/dev/null 2>&1
}
f3fp_es_pret() {
  f3fp_condition "$(wb_kubectl -n "$1" get externalsecrets.external-secrets.io "$2" -o json 2>/dev/null || true)" Ready
}
f3fp_es_en_erreur() {
  f3fp_condition "$(wb_kubectl -n "$1" get externalsecrets.external-secrets.io "$2" -o json 2>/dev/null || true)" Ready False
}

# f3fp_pod ESPACE SÉLECTEUR — un pod Running et prêt correspondant au sélecteur (vide sinon).
f3fp_pod() {
  wb_kubectl -n "$1" get pods -l "$2" -o json 2>/dev/null |
    jq -r '[.items[] | select(.status.phase == "Running" and .metadata.deletionTimestamp == null
            and all(.status.containerStatuses[]?; .ready))] | .[0].metadata.name // empty' 2>/dev/null || true
}
