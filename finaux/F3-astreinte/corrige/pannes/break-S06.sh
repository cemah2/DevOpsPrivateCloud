# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants et filtres jq entre apostrophes
# break-S06.sh — F3-S06 « Mardi : un nœud tombe malade » (UN travailleur de k8s-par1)
#
# Choix du nœud : un travailleur (WB_K8S_WORKERS) qui ne porte ni le primaire de mediagenda-db de
# production, ni un pod Valkey de production (leur perte couperait la production au lieu de la dégrader).
# Contrôle préalable : lab sain, sauvegarde CNPG de prod « completed » (des réplicas peuvent être touchés).
# Jamais un nœud de contrôle, jamais etcd, jamais l'horloge (voir le corrigé : WireGuard de Cilium et
# cephx rendent une dérive d'horloge risquée à défaire).
#   1. Disque : fichier de « traces de débogage » (/var/log/medisphere/trace-debug-mediagenda.log,
#      fallocate) qui ne laisse que 4 % libres sur le système de fichiers de /var/lib/kubelet : pression
#      disque (DiskPressure), éviction de pods. Taille bornée à 40 Gio. Annulation : fichier supprimé.
#   2. kubelet : KUBELET_EXTRA_ARGS de /etc/default/kubelet reçoit « --max-pod=150 » (faute de frappe
#      de --max-pods), puis kubelet est redémarré : il refuse de démarrer, le nœud passe NotReady.
#   3. containerd : /etc/containerd/config.toml reçoit une table de miroir mal fermée, puis containerd est
#      redémarré : il refuse de démarrer (les conteneurs déjà lancés continuent, KillMode=process),
#      kubelet perd le runtime, le nœud passe NotReady.
# Fichiers sauvegardés sur le nœud (pannes-lib : sauver) ; annulation : fichier d'origine remis s'il porte
# encore la marque de la panne, service redémarré.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-commun.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-commun.sh"

read -r -a _S06_W <<<"${WB_F3_S06_NOEUDS:-${WB_K8S_WORKERS:-k8s-w01 k8s-w02 k8s-w03}}"
_S06_FICHIER=/var/log/medisphere/trace-debug-mediagenda.log

# _s06_choisir — travailleur éligible, au hasard.
_s06_choisir() {
  local exclus n
  local -a ok=()
  exclus="$(wb_kubectl -n "$_F3P_PROD" get pods -o json 2>/dev/null | jq -r '.items[]
      | select((.metadata.labels["cnpg.io/instanceRole"] // .metadata.labels.role // "") == "primary"
               or (.metadata.name | test("^valkey")))
      | .spec.nodeName // empty' | sort -u)" || return 1
  for n in "${_S06_W[@]}"; do
    grep -qx "$n" <<<"$exclus" || ok+=("$n")
  done
  ((${#ok[@]} > 0)) || return 1
  printf '%s\n' "${ok[RANDOM % ${#ok[@]}]}"
}

_s06_noeud() { _f3p_lire S06 noeud; }

_s06_condition() {
  wb_kubectl get node "$(_s06_noeud)" -o json 2>/dev/null |
    jq -r --arg t "$1" '[.status.conditions[]? | select(.type == $t)][0].status // "Unknown"'
}

# --- Variante 1 : disque plein ---------------------------------------------------------------------------

_s06_v1_poser() {
  wb_exec "$(_s06_noeud)" FICHIER="$_S06_FICHIER" >/dev/null 2>&1 <<'EOF'
command -v fallocate >/dev/null || exit 10
set -- $(df -B1 --output=size,avail /var/lib/kubelet | tail -n 1)
taille="$1"; libre="$2"
garder=$((taille * 4 / 100))
remplir=$((libre - garder))
[ "$remplir" -gt 1073741824 ] || exit 10
[ "$remplir" -le 42949672960 ] || exit 10
# Fichier NEUF (aucune sauvegarde nécessaire : l'annulation le supprime) ; refus s'il existe déjà.
[ -e "$FICHIER" ] && exit 10
mkdir -p "$(dirname "$FICHIER")"
fallocate -l "$remplir" "$FICHIER" || { rm -f "$FICHIER"; exit 1; }
journal "fichier $FICHIER de $remplir octets (libre avant : $libre / $taille)"
EOF
}
_s06_v1_constat() {
  [[ "$(_s06_condition DiskPressure)" == True ]] ||
    wb_kubectl get pods -A --field-selector "spec.nodeName=$(_s06_noeud)" -o json 2>/dev/null |
    jq -e '[.items[] | select(.status.reason == "Evicted")] | length > 0' >/dev/null 2>&1
}
_s06_v1_defaire() {
  wb_exec "$(_s06_noeud)" FICHIER="$_S06_FICHIER" >/dev/null 2>&1 <<'EOF' || wb_avert "fichier $_S06_FICHIER à supprimer à la main sur $(_s06_noeud)"
if [ -f "$FICHIER" ]; then rm -f "$FICHIER" && journal "fichier $FICHIER supprimé"; fi
rmdir "$(dirname "$FICHIER")" 2>/dev/null || true
exit 0
EOF
}

# --- Variantes 2 et 3 : service qui ne redémarre plus ---------------------------------------------------

_s06_v2_poser() {
  wb_exec "$(_s06_noeud)" >/dev/null 2>&1 <<'EOF'
f=/etc/default/kubelet
systemctl is-active --quiet kubelet || exit 10
sauver "$f"
if [ -f "$f" ] && grep -q '^KUBELET_EXTRA_ARGS=' "$f"; then
  sed -i -E 's/^KUBELET_EXTRA_ARGS="?([^"]*)"?$/KUBELET_EXTRA_ARGS="\1 --max-pod=150"/' "$f"
else
  printf 'KUBELET_EXTRA_ARGS="--max-pod=150"\n' >> "$f"
fi
grep -q -- '--max-pod=150' "$f" || exit 1
cp "$f" "$WB_DIR/F3-S06.injecte-kubelet"
systemctl restart kubelet >/dev/null 2>&1 || true
journal "--max-pod=150 ajouté à $f, kubelet redémarré"
EOF
}
_s06_v3_poser() {
  wb_exec "$(_s06_noeud)" >/dev/null 2>&1 <<'EOF'
f=/etc/containerd/config.toml
[ -f "$f" ] || exit 10
systemctl is-active --quiet containerd || exit 10
systemctl show containerd -p KillMode | grep -q 'KillMode=process' || exit 10
sauver "$f"
printf '\n# Miroir interne pour les images de la plateforme (Lucas, PLAT-3306)\n[plugins."io.containerd.cri.v1.images".registry.mirrors."registry.par1.medisphere.internal"\n  endpoint = ["https://registry.par1.medisphere.internal"]\n' >> "$f"
cp "$f" "$WB_DIR/F3-S06.injecte-containerd"
systemctl restart containerd >/dev/null 2>&1 || true
journal "table de miroir mal fermée ajoutée à $f, containerd redémarré"
EOF
}
_s06_service_defaire() {
  wb_exec "$(_s06_noeud)" SERVICE="$1" FICHIER="$2" >/dev/null 2>&1 <<'EOF' || wb_avert "$2 et le service $1 à vérifier sur $(_s06_noeud)"
# Copie de l'état injecté propre à CE service : l'annulation de l'autre variante n'y touche pas.
inj="${WB_DIR:?}/F3-S06.injecte-${SERVICE:?}"
if [ -f "$inj" ]; then
  if cmp -s "$FICHIER" "$inj"; then
    restaurer_fichiers
    systemctl restart "$SERVICE" >/dev/null 2>&1 || true
    [ "$SERVICE" = containerd ] && systemctl restart kubelet >/dev/null 2>&1
    journal "$FICHIER rétabli, $SERVICE redémarré"
  else
    # Réparé autrement : on oublie la sauvegarde (une réparation n'est jamais défaite).
    rm -f "${WB_DIR:?}/${WB_EX:?}.manifeste"
    journal "annulation : $FICHIER modifié depuis la panne, laissé tel quel"
  fi
  rm -f "$inj"
fi
exit 0
EOF
}
_s06_notready() { [[ "$(_s06_condition Ready)" != True ]]; }

# --- Mécanique commune ------------------------------------------------------------------------------------

_f3p_S06_une() {
  case "$1" in
    1) _s06_v1_poser || return $?; _f3p_attendre 240 _s06_v1_constat || return 10 ;;
    2) _s06_v2_poser || return $?; _f3p_attendre 180 _s06_notready || return 10 ;;
    3) _s06_v3_poser || return $?; _f3p_attendre 180 _s06_notready || return 10 ;;
  esac
}
_f3p_S06_defaire() {
  [[ -n "$(_s06_noeud)" ]] || return 0
  case "$1" in
    1) _s06_v1_defaire ;;
    2) _s06_service_defaire kubelet /etc/default/kubelet ;;
    3) _s06_service_defaire containerd /etc/containerd/config.toml ;;
  esac
}

_s06_injecter() {
  local n
  _f3p_preparer S06 || return 1
  _f3p_cnpg_sain "$_F3P_PROD" || { echo "mediagenda-db (prod) n'est pas sain : $_F3P_REFUS" >&2; return 1; }
  n="$(_s06_choisir)" || { echo "Aucun travailleur éligible (primaire de prod ou Valkey de prod partout) : rien n'est cassé." >&2; return 1; }
  _f3p_sauvegarde_prod || return 1
  _f3p_ecrire S06 noeud "$n"
  _f3p_journal S06 "nœud choisi : $n"
  _f3p_essayer S06 3 "$1"
}

panne_S06_v1() { _s06_injecter 1; }
panne_S06_v2() { _s06_injecter 2; }
panne_S06_v3() { _s06_injecter 3; }

verifier_S06() {
  case "$(_f3p_lire S06 variante)" in
    1) _s06_v1_constat ;;
    2 | 3) _s06_notready ;;
    *) return 1 ;;
  esac
}

annuler_S06() {
  local v
  for v in 1 2 3; do _f3p_S06_defaire "$v" || true; done
  if [[ -n "$(_s06_noeud)" ]]; then
    wb_kubectl uncordon "$(_s06_noeud)" >/dev/null 2>&1 || true
  fi
  _f3p_oublier S06 variante
  _f3p_oublier S06 noeud
}

resume_S06() { echo "le travailleur $(_s06_noeud) est malade, des pods en sont chassés"; }

symptome_S06() {
  _f3p_symptome S06 INC-5906 "Ticket INC-5906 — De : Julien Petit — mardi 14 h 20" \
    "« Des pods de recette ont redémarré ailleurs d'un coup, et l'Alertmanager parle du nœud" \
    "$(_s06_noeud). Rien n'a été livré. La prod a l'air de tenir, mais elle tourne sur un nœud de moins :" \
    "si un deuxième tombe, on est mal. Tu peux regarder ? »" \
    "Contraintes : un seul nœud est touché ; ne redémarre pas la VM avant d'avoir compris (on veut la cause)." \
    "Temps cible : 1 h."
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S06 3 "$@"; }
fi
