# shellcheck shell=bash
# plateforme/k8s — outils/day0/commun.sh (F1-S07, CHG-3107)
# Fonctions communes des scripts d'orchestration de la reconstruction de k8s-par1 (outils/day0/NN-*.sh).
# Sourcé, jamais lancé seul. Chaque script de phase :
#   - s'arrête à la première erreur (set -euo pipefail) et peut être relancé : chaque étape vérifie
#     d'abord si elle est déjà faite ;
#   - horodate chaque étape dans le journal de la fenêtre (une ligne TSV : date ISO, phase, étape,
#     événement, durée en secondes), recopié ensuite dans docs/day0/chronologie.md ;
#   - demande une confirmation explicite avant toute action destructrice (OUI en majuscules).
# Rien de secret n'est écrit dans le journal.

set -euo pipefail

DAY0_JOURNAL="${DAY0_JOURNAL:-$HOME/day0/chronologie.tsv}"
DAY0_CONTEXTE="${DAY0_CONTEXTE:-k8s-par1}"
# kubeconfig utilisé pendant la reconstruction : admin.conf du NOUVEAU cluster tant que l'OIDC n'est
# pas revenu (S09), puis ton contexte personnel. Jamais l'ancien admin.conf.
DAY0_KUBECONFIG="${DAY0_KUBECONFIG:-$HOME/.kube/config}"
# shellcheck disable=SC2034  # lu par les scripts de phase
DAY0_SRC="${WB_SRC:-$HOME/src}"
mkdir -p "$(dirname "$DAY0_JOURNAL")"
chmod 700 "$(dirname "$DAY0_JOURNAL")"

export KUBECONFIG="$DAY0_KUBECONFIG"

# k ARGS… — kubectl avec le kubeconfig et le contexte de la reconstruction (jamais le contexte courant).
k() { kubectl --context "$DAY0_CONTEXTE" "$@"; }
# kcnpg SOUS-COMMANDE ARGS… — greffon CloudNativePG. Un greffon kubectl n'accepte AUCUNE option avant
# son nom (« flags cannot be placed before plugin name ») : le contexte vient après la sous-commande.
kcnpg() { kubectl cnpg "$1" --context "$DAY0_CONTEXTE" "${@:2}"; }

# jalon PHASE ÉTAPE ÉVÉNEMENT [DURÉE] — une ligne du journal de la fenêtre (et à l'écran).
jalon() {
  local l
  l="$(printf '%s\t%s\t%s\t%s\t%s' "$(date -Is)" "$1" "$2" "$3" "${4:-}")"
  printf '%s\n' "$l" >>"$DAY0_JOURNAL"
  printf '[%s] %s — %s : %s%s\n' "$(date +%H:%M:%S)" "$1" "$2" "$3" "${4:+ (${4} s)}"
}

# etape PHASE ÉTAPE COMMANDE… — lance la commande en horodatant début et fin ; en cas d'échec, note
# l'échec et s'arrête (la relance reprendra l'étape).
etape() {
  local phase="$1" nom="$2" debut rc=0
  shift 2
  debut=$SECONDS
  jalon "$phase" "$nom" "début"
  "$@" || rc=$?
  if ((rc != 0)); then
    jalon "$phase" "$nom" "ÉCHEC (code $rc)" "$((SECONDS - debut))"
    return "$rc"
  fi
  jalon "$phase" "$nom" "fin" "$((SECONDS - debut))"
}

# geste PHASE "description" — note un geste MANUEL (dette) dans le journal, avec sa raison.
geste() { jalon "$1" "GESTE MANUEL" "$2"; }

# confirmer "question" — demande « OUI » (majuscules) ; tout autre réponse arrête le script.
confirmer() {
  local r
  printf '⚠️  %s\nTape OUI pour continuer : ' "$1" >&2
  read -r r
  [[ "$r" == OUI ]] || { echo "Arrêt demandé." >&2; exit 1; }
}

# attendre SECONDES DESCRIPTION COMMANDE… — relance la commande toutes les 10 s jusqu'au succès.
attendre() {
  local delai="$1" quoi="$2" fin
  shift 2
  fin=$((SECONDS + delai))
  until "$@" >/dev/null 2>&1; do
    if ((SECONDS >= fin)); then
      echo "Délai dépassé ($delai s) : $quoi" >&2
      return 1
    fi
    sleep 10
  done
}

# outils_requis OUTIL… — vérifie la présence des outils sur adm01.
outils_requis() {
  local c manque=0
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; manque=1; }; done
  ((manque == 0))
}
