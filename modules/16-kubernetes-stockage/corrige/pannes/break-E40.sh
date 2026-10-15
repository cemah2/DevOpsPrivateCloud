# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M16-E40 « Panne : la base PostgreSQL ne bascule plus »
#
# Contexte du ticket : maintenance du travailleur X qui porte le primaire de mediagenda-db
# (mediagenda-recette) ; il faut basculer le primaire et drainer X. Variantes :
#   1. PDB supplémentaire « mediagenda-db-maintenance » (minAvailable 3) qui couvre tous les pods
#      du cluster, en plus des deux PDB de CloudNativePG → chaque éviction est refusée (« more than
#      one PodDisruptionBudget ») : le drain ne passe pas ;
#   2. une réplique est clôturée (annotation cnpg.io/fencedInstances, « diagnostic disque » de
#      Lucas oublié) → il ne reste qu'une réplique saine : la promotion vers la réplique clôturée est
#      refusée, et après la bascule et le drain (l'instance évincée de X reste Pending : anti-affinité
#      requise), plus aucune réplique synchrone : avec dataDurability: required, les écritures attendent ;
#   3. réplication synchrone mal réglée : .spec.postgresql.synchronous.number passe de 1 à 2 → tant que
#      les trois instances tournent, tout va bien ; dès que le drain retire une instance, les
#      validations attendent une seconde réplique synchrone qui n'existe plus : écritures bloquées.
# Rien n'est supprimé ; les valeurs d'origine (annotation, nombre de répliques synchrones) sont gardées
# localement ; l'annulation ne défait que ce qui porte encore la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m16-commun.sh
source "$WB_ROOT/modules/16-kubernetes-stockage/corrige/pannes/_m16-commun.sh"

_E40_PDB=mediagenda-db-maintenance

# _e40_instances — lignes « pod nœud rôle » des instances de mediagenda-db.
_e40_instances() {
  m16_k get pods -n "$_M16_NS_DB" -l "cnpg.io/cluster=$_M16_CLUSTER" -o json \
    | jq -r '.items[] | select(.metadata.deletionTimestamp == null)
             | "\(.metadata.name) \(.spec.nodeName) \(.metadata.labels["cnpg.io/instanceRole"] // .metadata.labels.role // "?")"'
}

# _e40_une_de_moins — une instance de moins que prévu est prête (la réplique clôturée).
_e40_une_de_moins() {
  m16_cnpg | jq -e '(.status.readyInstances // 0) == (.spec.instances - 1)' >/dev/null 2>&1
}

# _e40_sync_deux — PostgreSQL attend deux répliques synchrones.
_e40_sync_deux() { m16_psql "show synchronous_standby_names" | grep -Eq '^(ANY|FIRST) 2 '; }

_m16E40_une() {
  local n="$1" p x rep nb
  p="$(m16_lire E40 primaire)"
  x="$(m16_lire E40 noeud)"
  case "$n" in
    1)
      m16_existe pdb "$_E40_PDB" "$_M16_NS_DB" && return 10
      m16_sauver pdb "$_E40_PDB" "$_M16_NS_DB"
      wb_kubectl apply -f - >/dev/null 2>&1 <<EOF || return 1
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: $_E40_PDB
  namespace: $_M16_NS_DB
  annotations: {medisphere.fr/ticket: "CHG-1738 protection de la base pendant la migration"}
spec:
  minAvailable: 3
  selector:
    matchLabels: {cnpg.io/cluster: $_M16_CLUSTER}
EOF
      ;;
    2)
      [[ -z "$(m16_cnpg | jq -r '.metadata.annotations["cnpg.io/fencedInstances"] // empty')" ]] || return 10
      # Une réplique au hasard (pas le primaire).
      rep="$(_e40_instances | awk -v p="$p" '$1 != p { print $1 }' | shuf -n 1)"
      [[ -n "$rep" ]] || return 10
      rep="$(jq -cn --arg r "$rep" '[$r]')"
      wb_kubectl annotate cluster.postgresql.cnpg.io "$_M16_CLUSTER" -n "$_M16_NS_DB" --overwrite \
        "cnpg.io/fencedInstances=$rep" >/dev/null 2>&1 || return 1
      m16_ecrire E40 cloture "$rep"
      m16_attendre 180 _e40_une_de_moins || { _e40_defaire 2; return 1; }
      ;;
    3)
      nb="$(m16_cnpg | jq -r '.spec.postgresql.synchronous.number // empty')"
      [[ "$nb" == 1 ]] || return 10
      [[ "$(m16_cnpg | jq -r '.spec.postgresql.synchronous.dataDurability // "required"')" == required ]] || return 10
      m16_ecrire E40 sync_nombre "$nb"
      wb_kubectl patch cluster.postgresql.cnpg.io "$_M16_CLUSTER" -n "$_M16_NS_DB" --type merge \
        -p '{"spec":{"postgresql":{"synchronous":{"number":2}}}}' >/dev/null 2>&1 || return 10
      m16_ecrire E40 sync_pose oui
      m16_attendre 120 _e40_sync_deux || { _e40_defaire 3; return 1; }
      ;;
  esac
  m16_journal E40 "variante $n posée (primaire $p sur $x)"
}

_e40_defaire() {
  local cur
  case "$1" in
    1) m16_restaurer pdb "$_E40_PDB" "$_M16_NS_DB" ;;
    2)
      cur="$(m16_cnpg | jq -c '.metadata.annotations["cnpg.io/fencedInstances"] // empty | fromjson? // empty')"
      if [[ -n "$cur" && -n "$(m16_lire E40 cloture)" && "$cur" == "$(jq -c . <<<"$(m16_lire E40 cloture)")" ]]; then
        wb_kubectl annotate cluster.postgresql.cnpg.io "$_M16_CLUSTER" -n "$_M16_NS_DB" \
          cnpg.io/fencedInstances- >/dev/null 2>&1 || wb_avert "annulation : clôture des répliques non levée"
      fi ;;
    3)
      [[ "$(m16_lire E40 sync_pose)" == oui ]] || return 0
      if [[ "$(m16_cnpg | jq -r '.spec.postgresql.synchronous.number // empty')" == 2 ]]; then
        wb_kubectl patch cluster.postgresql.cnpg.io "$_M16_CLUSTER" -n "$_M16_NS_DB" --type merge \
          -p "{\"spec\":{\"postgresql\":{\"synchronous\":{\"number\":$(m16_lire E40 sync_nombre)}}}}" >/dev/null 2>&1 \
          || wb_avert "annulation : nombre de répliques synchrones non rétabli"
      fi ;;
  esac
}

_e40_injecter() {
  local p x
  if [[ -z "${_M16_ASTREINTE:-}" ]]; then
    m16_sain_csi || return 1
  fi
  m16_cnpg_sain || { wb_avert "$_M16_CLUSTER n'est pas sain (3 instances prêtes attendues) : lab/bin/check 16 18"; return 1; }
  p="$(m16_primaire)"
  x="$(m16_k get pod "$p" -n "$_M16_NS_DB" -o jsonpath='{.spec.nodeName}')"
  [[ -n "$p" && -n "$x" ]] || return 1
  m16_ecrire E40 primaire "$p"
  m16_ecrire E40 noeud "$x"
  m16_horodater E40
  m16_essayer E40 3 "$1"
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }

verifier_E40() {
  case "$WB_VAR" in
    1) m16_existe pdb "$_E40_PDB" "$_M16_NS_DB" ;;
    2) _e40_une_de_moins ;;
    3) _e40_sync_deux ;;
  esac
}

annuler_E40() {
  case "${WB_VAR:-}" in
    1 | 2 | 3) _e40_defaire "$WB_VAR" ;;
    *) _e40_defaire 3; _e40_defaire 2; _e40_defaire 1 ;;
  esac
  m16_journal E40 "annulation"
  m16_effacer_etat E40
}

resume_E40() {
  echo "La maintenance de $(m16_lire E40 noeud) n'est pas sûre : la répétition de la bascule de mediagenda-db ($(m16_lire E40 primaire)) a échoué ou bloqué les écritures."
}

symptome_E40() {
  local x p
  x="$(m16_lire E40 noeud)"; p="$(m16_lire E40 primaire)"
  wb_symptome "Ticket INC-4346 — De : Nadia Roussel" \
    "Ce soir, maintenance noyau du travailleur $x, qui porte le primaire de mediagenda-db ($p," \
    "espace mediagenda-recette). Procédure prévue : basculer le primaire sur une réplique, drainer" \
    "$x, (maintenance simulée), remettre $x en service. Lucas a fait une répétition cet après-midi :" \
    "« ça ne bascule pas, ou ça bascule mal ». Fais la maintenance complète ce soir, sans perte de" \
    "données et avec la coupure d'écriture la plus courte possible, puis dis-moi ce qui bloquait." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 16 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 16 E40 3 "$@"; }
fi
