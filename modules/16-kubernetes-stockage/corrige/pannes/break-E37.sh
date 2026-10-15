# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E37.sh — M16-E37 « Panne : le volume est déjà attaché ailleurs »
#
# Le travailleur X qui porte le témoin temoin-rbd (wb-essais, PVC RWO sur ceph-rbd) « tombe », puis
# le pod du témoin est supprimé (comme le ferait l'éviction après 5 min, en plus rapide) : son
# remplaçant, placé sur un autre nœud, reste en ContainerCreating sur « Multi-Attach error ».
# Variantes :
#   1. nœud à moitié mort : le conteneur du témoin est arrêté (crictl stop), puis kubelet arrêté ;
#      la VM répond encore au ping et en SSH, le nœud passe NotReady ;
#   2. nœud éteint brutalement : « qm stop » de la VM du travailleur depuis pve01 (coupure de
#      courant simulée ; aucune donnée détruite, la VM redémarre normalement).
# Effet de bord voulu et annoncé : les autres pods du nœud (dont, peut-être, une instance de
# mediagenda-db) vivent eux aussi la perte du nœud.
# L'annulation relance kubelet (v1) ou la VM (v2), attend le retour du nœud et retire une teinte
# node.kubernetes.io/out-of-service restée posée sur un nœud redevenu Ready.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m16-commun.sh
source "$WB_ROOT/modules/16-kubernetes-stockage/corrige/pannes/_m16-commun.sh"

_e37_noeud() { m16_lire E37 noeud; }

_e37_nonpret() { ! m16_noeud_pret "$1"; }

_m16E37_une() {
  local n="$1" x vmid p rc=0
  x="$(_e37_noeud)"
  vmid="${_M16_VMID[$x]:-}"
  case "$n" in
    1)
      wb_exec "$x" >/dev/null 2>&1 <<'EOF' || rc=$?
systemctl is-active --quiet kubelet || exit 10
for c in $(crictl ps -q --name '^temoin$' --label io.kubernetes.pod.namespace=wb-essais 2>/dev/null); do
  crictl stop "$c" >/dev/null 2>&1 || true
done
systemctl stop kubelet
journal "conteneur du témoin arrêté, kubelet arrêté (nœud NotReady)"
EOF
      ((rc == 0)) || return "$rc"
      m16_ecrire E37 kubelet_arrete oui
      ;;
    2)
      [[ -n "$vmid" ]] || return 10
      # Garde-fou : la VM visée est bien ce travailleur, dans le pool lab.
      remote "$WB_PVE_HOST" "qm config $vmid" 2>/dev/null | grep -Eq "^name: $x\$" || return 10
      remote "$WB_PVE_HOST" "qm status $vmid" 2>/dev/null | grep -q 'status: running' || return 10
      m16_ecrire E37 vm_arretee "$vmid"
      remote "$WB_PVE_HOST" "qm stop $vmid" >/dev/null 2>&1 || return 1
      ;;
  esac
  # Le nœud doit être constaté NotReady (délai de grâce du contrôleur de nœuds : ~40-50 s).
  m16_attendre 150 _e37_nonpret "$x" || { _e37_defaire "$n"; return 1; }
  p="$(m16_premier_pod "$_M16_NS_T" app.kubernetes.io/name=temoin-rbd)"
  [[ -n "$p" ]] && wb_kubectl delete pod "$p" -n "$_M16_NS_T" --wait=false >/dev/null 2>&1
  m16_journal E37 "variante $n posée (nœud $x)"
}

_e37_attendre_pret() { m16_attendre "$2" m16_noeud_pret "$1"; }

_e37_defaire() {
  local x vmid
  x="$(_e37_noeud)"
  [[ -n "$x" ]] || return 0
  case "$1" in
    1)
      [[ "$(m16_lire E37 kubelet_arrete)" == oui ]] || return 0
      wb_exec "$x" >/dev/null 2>&1 <<'EOF' || wb_avert "annulation : kubelet de $x non relancé"
systemctl is-active --quiet kubelet && exit 0
systemctl start kubelet
journal "kubelet relancé"
EOF
      _e37_attendre_pret "$x" 120 || wb_avert "annulation : $x n'est pas revenu Ready"
      ;;
    2)
      vmid="$(m16_lire E37 vm_arretee)"
      [[ -n "$vmid" ]] || return 0
      if ! remote "$WB_PVE_HOST" "qm status $vmid" 2>/dev/null | grep -q 'status: running'; then
        remote "$WB_PVE_HOST" "qm start $vmid" >/dev/null 2>&1 || wb_avert "annulation : VM $vmid non redémarrée"
      fi
      _e37_attendre_pret "$x" 300 || wb_avert "annulation : $x n'est pas revenu Ready"
      ;;
  esac
  # Teinte de mise hors service laissée sur un nœud revenu : on la retire (le nœud est sain).
  if m16_noeud_pret "$x"; then
    wb_kubectl taint node "$x" node.kubernetes.io/out-of-service- >/dev/null 2>&1 || true
  fi
}

_e37_injecter() {
  local x
  m16_preparer || return 1
  x="$(m16_noeud_du_pod "$_M16_NS_T" app.kubernetes.io/name=temoin-rbd)"
  [[ -n "$x" ]] || { wb_avert "témoin temoin-rbd sans pod Running"; return 1; }
  m16_ecrire E37 noeud "$x"
  m16_horodater E37
  m16_essayer E37 2 "$1"
}

panne_E37_v1() { _e37_injecter 1; }
panne_E37_v2() { _e37_injecter 2; }

# Constatée si le remplaçant du témoin, sur un autre nœud, signale l'attachement multiple.
_e37_multi() {
  local p
  p="$(m16_premier_pod "$_M16_NS_T" app.kubernetes.io/name=temoin-rbd)"
  [[ -n "$p" ]] && m16_evenement "$_M16_NS_T" "$p" 'Multi-Attach'
}
verifier_E37() { m16_attendre 120 _e37_multi; }

annuler_E37() {
  case "${WB_VAR:-}" in
    1 | 2) _e37_defaire "$WB_VAR" ;;
    *) _e37_defaire 2; _e37_defaire 1 ;;
  esac
  m16_journal E37 "annulation"
  m16_effacer_etat E37
}

resume_E37() {
  echo "Le témoin temoin-rbd (wb-essais) ne redémarre pas depuis que $(_e37_noeud) est tombé : son nouveau pod reste en ContainerCreating."
}

symptome_E37() {
  local detail="La VM répond encore au ping, mais Kubernetes la voit NotReady."
  [[ "$WB_VAR" == 2 ]] && detail="La VM est arrêtée (InfoGér diagnostique le matériel : ne la redémarre pas avant leur feu vert)."
  wb_symptome "Ticket INC-4343 — De : Nadia Roussel" \
    "Alerte de 3 h 12 : le travailleur $(_e37_noeud) est tombé. $detail" \
    "Kubernetes a bien relancé ailleurs le pod du témoin temoin-rbd (wb-essais), mais ce pod reste en" \
    "ContainerCreating : son volume « serait déjà attaché ». Mêmes symptômes à craindre pour tout pod" \
    "avec un volume RWO qui tournait sur ce nœud. Fais repartir le témoin au plus vite, sans risquer" \
    "ses données, et écris ce qu'on fera la prochaine fois qu'un nœud tombera vraiment." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 16 37"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 16 E37 2 "$@"; }
fi
