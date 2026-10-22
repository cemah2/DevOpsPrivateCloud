# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants et expressions yq entre apostrophes
# break-E19.sh — M22-E19 « Panne : plus aucun journal d'un nœud »
#
# Variantes :
#   1. taint « medisphere.internal/maintenance=disque:NoSchedule » posée sur un travailleur (« Lucas
#      prépare le changement de disque ») puis pod alloy de ce nœud supprimé (« redémarré pour prendre la
#      nouvelle config ») : le DaemonSet ne le recrée pas (aucune tolérance). Sans effet si Alloy tolère
#      toutes les taints (operator: Exists sans clé) ;
#   2. commit de Lucas dans plateforme/observabilite (alloy/values.yaml) : tolérances des nœuds de
#      contrôle retirées de controller.tolerations « pour ne plus encombrer les nœuds de contrôle » :
#      plus aucun journal des trois nœuds de contrôle, ni du journal d'audit de l'API ;
#   3. drop-in journald « Storage=none » sur un travailleur (« économiser le disque, tout part dans
#      Loki ») : journald ne garde plus rien, Alloy ne lit plus rien de ce nœud (journaux système) ;
#   4. /var/log/journal renommé sur un travailleur (« archivage avant nettoyage ») puis journald
#      relancé : le journal devient volatil (/run/log/journal), qu'Alloy ne lit pas. Sans effet si
#      journald recrée /var/log/journal (Storage=persistent) ou si Alloy lit aussi /run/log/journal.
# Rien n'est supprimé : fichiers sauvegardés dans /var/lib/workbook/ du nœud, répertoire du journal
# renommé (jamais vidé), commit défait par un commit inverse.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m22-commun.sh
source "$WB_ROOT/modules/22-logs/corrige/pannes/_m22-commun.sh"

_E19_TAINT_CLE=medisphere.internal/maintenance
_E19_TAINT_VAL=disque

_e19_cible() { m22_lire E19 cible; }

# Alloy tolère-t-il toutes les taints (operator Exists sans clé) ?
_e19_tolere_tout() {
  wb_kubectl -n "$_M22_NS" get daemonset alloy -o json 2>/dev/null |
    jq -e '[.spec.template.spec.tolerations[]? | select(.operator == "Exists" and ((.key // "") == ""))] | length > 0' >/dev/null 2>&1
}

_e19_v1_effective() {
  local h
  h="$(_e19_cible)"
  [[ -n "$h" ]] && ! m22_alloy_sur "$h"
}

_e19_v2_effective() {
  # Le DaemonSet ne vise plus les nœuds de contrôle : aucun pod alloy sur aucun d'eux.
  local h
  for h in "${_M22_CP[@]}"; do
    m22_alloy_sur "$h" && return 1
  done
  return 0
}

# Variantes 3 et 4 : une ligne écrite dans journald du nœud n'arrive pas dans Loki en 2 min.
_e19_journald_coupe() {
  local h motif
  h="$(_e19_cible)"
  [[ -n "$h" ]] || return 1
  motif="$(m22_ligne_temoin "$h")" || return 1
  sleep 120
  ! m22_motif_present plateforme "$motif" 5m
}

_m22E19_une() {
  local n="$1" h rc=0
  case "$n" in
    1)
      _e19_tolere_tout && return 10
      h="$(m22_hasard "${_M22_W[@]}")"
      m22_alloy_sur "$h" || return 1
      m22_poser E19 cible "$h"
      wb_kubectl taint node "$h" "$_E19_TAINT_CLE=$_E19_TAINT_VAL:NoSchedule" --overwrite >/dev/null || return 1
      wb_kubectl annotate node "$h" medisphere.internal/maintenance-ticket="CHG-2319 changement du disque de données (Lucas)" --overwrite >/dev/null 2>&1 || true
      m22_journal E19 "taint $_E19_TAINT_CLE posée sur $h"
      wb_kubectl -n "$_M22_NS" delete pod -l app.kubernetes.io/name=alloy --field-selector "spec.nodeName=$h" --wait=false >/dev/null || return 1
      m22_attendre 90 _e19_v1_effective || return 10
      ;;
    2)
      _m22_transformer() {
        local f
        f="$(mktemp)"
        cat >"$f"
        # Il faut des tolérances visant les nœuds de contrôle (ou tout tolérer) pour que le retrait ait un effet.
        if ! yq -e '[.controller.tolerations[]? | select((.key // "") == "node-role.kubernetes.io/control-plane" or (.operator == "Exists" and (.key // "") == ""))] | length > 0' "$f" >/dev/null 2>&1; then
          rm -f "$f"
          return 10
        fi
        # Retire les tolérances des nœuds de contrôle et la tolérance « tout » ; garde (ou ajoute) celle
        # de la taint dedie=bdd de k8s-w03 pour que seuls les nœuds de contrôle soient touchés.
        yq -i '.controller.tolerations |= map(select((.key // "") != "node-role.kubernetes.io/control-plane" and ((.operator // "") != "Exists" or (.key // "") != "")))' "$f"
        if [[ "$(yq '[.controller.tolerations[] | select(.key == "dedie")] | length' "$f")" == 0 ]]; then
          yq -i '.controller.tolerations += [{"key": "dedie", "operator": "Equal", "value": "bdd", "effect": "NoSchedule"}]' "$f"
        fi
        cat "$f"
        rm -f "$f"
      }
      m22_git_modifier E19 "$_M22_F_ALLOY" "chore(alloy): ne plus planifier la collecte sur les nœuds de contrôle (M22-E19)

Les nœuds de contrôle sont déjà chargés, Alloy n'a rien à y faire ; tolérances explicites plutôt
que « tout tolérer ». -- Lucas" || return $?
      m22_attendre 420 _e19_v2_effective || return 1
      ;;
    3)
      h="$(m22_hasard "${_M22_W[@]}")"
      m22_poser E19 cible "$h"
      m22_journald_collecte "$h" 120 || { echo "La collecte journald de $h ne fonctionne pas avant la panne (lab/bin/check 22 03)." >&2; return 1; }
      m22_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
d=/etc/systemd/journald.conf.d
f="$d/60-economie-disque.conf"
[ -e "$f" ] && exit 10
sauver "$f"
mkdir -p "$d"
cat > "$f" <<'CONF'
# Lucas — CHG-2319 : économiser le disque des travailleurs, les journaux partent dans Loki de toute façon
[Journal]
Storage=none
CONF
systemctl restart systemd-journald
journal "drop-in journald $f (Storage=none), journald relancé"
EOF
      ((rc == 0)) || return "$rc"
      ;;
    4)
      h="$(m22_hasard "${_M22_W[@]}")"
      m22_poser E19 cible "$h"
      m22_journald_collecte "$h" 120 || { echo "La collecte journald de $h ne fonctionne pas avant la panne (lab/bin/check 22 03)." >&2; return 1; }
      m22_wb_exec "$h" >/dev/null <<'EOF' || rc=$?
[ -d /var/log/journal ] || exit 10
# Storage=persistent recréerait le répertoire : variante sans effet
systemd-analyze cat-config systemd/journald.conf 2>/dev/null | grep -Eq '^[[:space:]]*Storage=persistent' && exit 10
cible="/var/log/journal.archive-$(date +%Y%m%d)"
[ -e "$cible" ] && exit 10
mv /var/log/journal "$cible"
echo "$cible" > "$WB_DIR/$WB_EX.journal-renomme"
systemctl restart systemd-journald
sleep 2
if [ -d /var/log/journal ]; then
  # journald l'a recréé : on remet tout comme avant
  rmdir /var/log/journal 2>/dev/null || true
  [ -d /var/log/journal ] || mv "$cible" /var/log/journal
  rm -f "$WB_DIR/$WB_EX.journal-renomme"
  systemctl restart systemd-journald
  exit 10
fi
journal "/var/log/journal renommé en $cible, journald relancé (journal volatil)"
EOF
      ((rc == 0)) || return "$rc"
      ;;
  esac
  m22_journal E19 "variante $n posée"
}

_e19_defaire() {
  local n="$1" h
  h="$(_e19_cible)"
  case "$n" in
    1)
      [[ -n "$h" ]] || return 0
      if wb_kubectl get node "$h" -o json 2>/dev/null | jq -e --arg k "$_E19_TAINT_CLE" --arg v "$_E19_TAINT_VAL" \
        '[.spec.taints[]? | select(.key == $k and .value == $v)] | length > 0' >/dev/null 2>&1; then
        wb_kubectl taint node "$h" "$_E19_TAINT_CLE=$_E19_TAINT_VAL:NoSchedule-" >/dev/null 2>&1 || wb_avert "taint non retirée sur $h"
        wb_kubectl annotate node "$h" medisphere.internal/maintenance-ticket- >/dev/null 2>&1 || true
        m22_journal E19 "annulation : taint retirée de $h"
      fi
      ;;
    2)
      m22_git_annuler E19 || true
      ;;
    3)
      [[ -n "$h" ]] || return 0
      m22_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (journald)"
f=/etc/systemd/journald.conf.d/60-economie-disque.conf
if grep -qs '^Storage=none' "$f"; then
  restaurer_fichiers
  systemctl restart systemd-journald
  journal "annulation : drop-in journald retiré, journald relancé"
else
  rm -f "$WB_DIR/$WB_EX.manifeste"
fi
EOF
      ;;
    4)
      [[ -n "$h" ]] || return 0
      m22_wb_exec "$h" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (répertoire du journal)"
m="$WB_DIR/$WB_EX.journal-renomme"
[ -f "$m" ] || exit 0
cible="$(cat "$m")"
if [ ! -e /var/log/journal ] && [ -d "$cible" ]; then
  mv "$cible" /var/log/journal
  systemctl restart systemd-journald
  journalctl --flush >/dev/null 2>&1 || true
  journal "annulation : $cible remis en /var/log/journal, journal volatil vidé vers le disque"
elif [ -d "$cible" ]; then
  journal "annulation : /var/log/journal recréé par l'apprenant ; anciens journaux laissés dans $cible (journalctl -D $cible)"
  echo "avertissement : anciens journaux de ce nœud conservés dans $cible (lisibles par journalctl -D)" >&2
fi
rm -f "$m"
EOF
      ;;
  esac
}

panne_E19_v1() { m22_preparer && m22_essayer E19 4 1; }
panne_E19_v2() { m22_preparer && m22_essayer E19 4 2; }
panne_E19_v3() { m22_preparer && m22_essayer E19 4 3; }
panne_E19_v4() { m22_preparer && m22_essayer E19 4 4; }

verifier_E19() {
  case "$WB_VAR" in
    1) _e19_v1_effective ;;
    2) _e19_v2_effective ;;
    3 | 4) _e19_journald_coupe ;;
    *) return 1 ;;
  esac
}

annuler_E19() {
  case "${WB_VAR:-}" in
    [1-4]) _e19_defaire "$WB_VAR" ;;
    *) local v; for v in 1 2 3 4; do _e19_defaire "$v"; done ;;
  esac
  m22_oublier E19 cible
  m22_journal E19 "annulation"
}

resume_E19() {
  case "${WB_VAR:-}" in
    2) echo "Plus aucun journal des nœuds de contrôle dans Loki, et le journal d'audit de l'API s'est arrêté." ;;
    3 | 4) echo "Plus aucun journal système (kubelet, containerd) du nœud $(_e19_cible) dans Loki ; ses pods journalisent toujours." ;;
    *) echo "Plus aucun journal du nœud $(_e19_cible) dans Loki, ni de ses pods ni de son système." ;;
  esac
}

symptome_E19() {
  case "${WB_VAR:-}" in
    2)
      wb_symptome "Ticket INC-4919 — De : Sophie Laurent" \
        "Le tableau « Audit de l'API » est vide depuis ce matin, et Nadia ne trouve plus aucun" \
        "journal des nœuds de contrôle (k8s-cp01 à 03) dans Loki. Les autres nœuds vont bien." \
        "Sans journal d'audit, nous ne sommes plus conformes. Rétablis la collecte, et dis-moi" \
        "ce qui manque et pourquoi." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 22 19"
      ;;
    3 | 4)
      wb_symptome "Ticket INC-4919 — De : Nadia Roussel" \
        "Je cherchais pourquoi le kubelet de $(_e19_cible) a redémarré cette nuit : dans Loki, plus" \
        "aucun journal système de ce nœud depuis quelques minutes (kubelet, containerd, rien)." \
        "Les journaux de ses pods, eux, arrivent. Lucas a « fait un peu de ménage » sur les nœuds" \
        "hier. Rétablis la collecte sans perdre ce qu'il reste du journal." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 22 19"
      ;;
    *)
      wb_symptome "Ticket INC-4919 — De : Nadia Roussel" \
        "Plus aucun journal du nœud $(_e19_cible) dans Loki : ni ses pods, ni son système, depuis" \
        "quelques minutes. Les autres nœuds vont bien, les pods de ce nœud tournent normalement." \
        "Rétablis la collecte sans redémarrer le nœud." \
        "" \
        "Temps cible : 20 min. Contrôle : lab/bin/check 22 19"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 22 E19 4 "$@"; }
fi
