# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-S03.sh — F1-S03 « Panne : les mains de quelqu'un sont passées par là »
#
# TROIS dérives à la fois, une par couche. La variante N (1 à 3) fixe la combinaison :
#   couche 1 (Proxmox, VM 1011 lb02, hors OpenTofu) — variante N :
#     1. démarrage automatique coupé (onboot 1 → 0) ;
#     2. étiquette Proxmox « essai-charge » ajoutée ;
#     3. drapeau de protection posé (protection: 1).
#   couche 2 (fichier modifié à la main sur une VM gérée par Ansible) — (N-1) % 2 + 1 :
#     1. lb02 : « timeout client » de /etc/haproxy/haproxy.cfg passé à 5s (configuration validée,
#        rechargement) ;
#     2. dns02 : source NTP publique ajoutée dans /etc/chrony/chrony.conf (chrony redémarré ;
#        la passerelle reste une source, rien ne se désynchronise).
#   couche 3 (objet du cluster géré par Helmfile, hors GitOps) — N % 2 + 1 :
#     1. cert-manager : limite mémoire du Deployment cert-manager changée (kubectl set resources) ;
#     2. external-dns : limite mémoire du Deployment external-dns changée.
#   Aucune de ces ressources n'est réconciliée par Argo CD (couche de base sous Helmfile, M20) :
#   rien ne corrige seul la dérive. Aucune interruption de service (lb02 est BACKUP, dns02 garde sa
#   source de temps, les Deployments font un déploiement progressif).
#
# Sauvegardes : pve01 et VMs → /var/lib/workbook/F1-S03.* ; objets Kubernetes →
# ~/.local/state/workbook/k8s/F1-S03/ ; état de la panne → ~/.local/state/workbook/F1-S03/ (adm01).
# Annulation : chaque élément n'est remis dans son état d'origine QUE s'il est encore exactement
# dans l'état injecté (une réparation de l'apprenant, par le code, n'est jamais défaite).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"

_S03_VMID="${WB_F1_LB02_VMID:-1011}"
_S03_LB01="${WB_F1_LB01:-lb01}"
_S03_LB02="${WB_F1_LB02:-lb02}"
_S03_DNS02="${WB_F1_DNS02:-dns02}"
_S03_VIP="${WB_F1_VIP_LB:-10.10.70.200}"

_s03_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F1-S03"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
_s03_poser() { printf '%s\n' "$2" >"$(_s03_etat)/$1"; }
_s03_lire() {
  local f
  f="$(_s03_etat)/$1"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
_s03_journal() { printf '%s [F1-S03 variante %s] %s\n' "$(date -Is)" "${WB_VAR:-?}" "$*" >>"$(_s03_etat)/journal"; }

# --- Contrôle préalable : le lab doit être sain --------------------------------------------------
_s03_sain() {
  local c
  for c in kubectl jq yq ssh; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  yq --version 2>/dev/null | grep -q mikefarah || { echo "yq de mikefarah (v4) attendu sur adm01" >&2; return 1; }
  remote "$WB_PVE_HOST" "qm status $_S03_VMID" </dev/null 2>/dev/null | grep -q 'status: running' ||
    { echo "La VM $_S03_VMID ($_S03_LB02) n'est pas démarrée : lab non conforme, rien n'est injecté." >&2; return 1; }
  remote "$_S03_LB01" "ip -4 -o addr show" </dev/null 2>/dev/null | grep -q " $_S03_VIP/" ||
    { echo "$_S03_LB01 ne porte pas la VIP $_S03_VIP : répartiteurs non conformes, rien n'est injecté." >&2; return 1; }
  remote "$_S03_LB02" "sudo -n haproxy -c -f /etc/haproxy/haproxy.cfg" </dev/null >/dev/null 2>&1 ||
    { echo "Configuration HAProxy de $_S03_LB02 invalide ou SSH impossible : rien n'est injecté." >&2; return 1; }
  remote "$_S03_DNS02" "chronyc -n tracking" </dev/null 2>/dev/null | grep -q 'Leap status *: Normal' ||
    { echo "chrony de $_S03_DNS02 n'est pas synchronisé : rien n'est injecté." >&2; return 1; }
  if ! wb_kubectl -n cert-manager get deployment cert-manager >/dev/null 2>&1 ||
    ! wb_kubectl -n external-dns get deployment external-dns >/dev/null 2>&1; then
    echo "Deployments cert-manager ou external-dns introuvables (kubeconfig d'administration ?)." >&2
    return 1
  fi
  if wb_marqueur_existe F1-S03; then
    echo "Une panne F1-S03 est déjà active." >&2
    return 1
  fi
}

# --- Couche 1 : Proxmox ---------------------------------------------------------------------------
_s03_couche1() {
  local n="$1"
  wb_exec "$WB_PVE_HOST" VMID="$_S03_VMID" N="$n" <<'EOF' || return 1
set -e
c="$(qm config "$VMID")"
orig_onboot="$(printf '%s\n' "$c" | sed -n 's/^onboot: //p')"
orig_tags="$(printf '%s\n' "$c" | sed -n 's/^tags: //p')"
orig_prot="$(printf '%s\n' "$c" | sed -n 's/^protection: //p')"
if [ ! -f "$WB_DIR/$WB_EX.vm-orig" ]; then
  printf 'onboot=%s\ntags=%s\nprotection=%s\n' "$orig_onboot" "$orig_tags" "$orig_prot" > "$WB_DIR/$WB_EX.vm-orig"
fi
case "$N" in
  1) [ "$orig_onboot" = 1 ] || exit 10
     qm set "$VMID" --onboot 0 >/dev/null
     echo "onboot=0" > "$WB_DIR/$WB_EX.vm-injecte" ;;
  2) case ";$orig_tags;" in *";essai-charge;"*) exit 10 ;; esac
     qm set "$VMID" --tags "${orig_tags:+$orig_tags;}essai-charge" >/dev/null
     echo "tags=essai-charge" > "$WB_DIR/$WB_EX.vm-injecte" ;;
  3) [ "${orig_prot:-0}" = 0 ] || exit 10
     qm set "$VMID" --protection 1 >/dev/null
     echo "protection=1" > "$WB_DIR/$WB_EX.vm-injecte" ;;
esac
journal "VM $VMID : $(cat "$WB_DIR/$WB_EX.vm-injecte") (hors OpenTofu)"
EOF
  _s03_poser couche1 "$n"
}

_s03_couche1_verifier() {
  local c
  c="$(remote "$WB_PVE_HOST" "qm config $_S03_VMID" </dev/null 2>/dev/null)" || return 1
  case "$(_s03_lire couche1)" in
    1) grep -q '^onboot: 0$' <<<"$c" ;;
    2) grep -Eq '^tags: (.*;)?essai-charge(;|$)' <<<"$c" ;;
    3) grep -q '^protection: 1$' <<<"$c" ;;
    *) return 1 ;;
  esac
}

_s03_couche1_annuler() {
  [[ -n "$(_s03_lire couche1)" ]] || return 0
  wb_exec "$WB_PVE_HOST" VMID="$_S03_VMID" <<'EOF' || wb_avert "couche 1 : annulation incomplète sur pve01"
o="$WB_DIR/$WB_EX.vm-orig"; i="$WB_DIR/$WB_EX.vm-injecte"
[ -f "$o" ] || exit 0
orig_onboot="$(sed -n 's/^onboot=//p' "$o")"
orig_tags="$(sed -n 's/^tags=//p' "$o")"
orig_prot="$(sed -n 's/^protection=//p' "$o")"
c="$(qm config "$VMID" 2>/dev/null)" || { rm -f "$o" "$i"; exit 0; }
case "$(cat "$i" 2>/dev/null)" in
  onboot=0)
    if printf '%s\n' "$c" | grep -q '^onboot: 0$'; then
      if [ -n "$orig_onboot" ]; then qm set "$VMID" --onboot "$orig_onboot" >/dev/null; else qm set "$VMID" --delete onboot >/dev/null; fi
      journal "annulation : onboot remis à « ${orig_onboot:-défaut} »"
    fi ;;
  tags=essai-charge)
    if printf '%s\n' "$c" | grep -Eq '^tags: (.*;)?essai-charge(;|$)'; then
      if [ -n "$orig_tags" ]; then qm set "$VMID" --tags "$orig_tags" >/dev/null; else qm set "$VMID" --delete tags >/dev/null; fi
      journal "annulation : étiquettes remises à « $orig_tags »"
    fi ;;
  protection=1)
    if printf '%s\n' "$c" | grep -q '^protection: 1$'; then
      if [ -n "$orig_prot" ]; then qm set "$VMID" --protection "$orig_prot" >/dev/null; else qm set "$VMID" --delete protection >/dev/null; fi
      journal "annulation : protection remise à « ${orig_prot:-défaut} »"
    fi ;;
esac
rm -f "$o" "$i"
EOF
}

# --- Couche 2 : fichier modifié à la main ---------------------------------------------------------
_s03_couche2() {
  local n="$1" h
  case "$n" in
    1)
      h="$_S03_LB02"
      wb_exec "$h" <<'EOF' || return $?
f=/etc/haproxy/haproxy.cfg
grep -Eq '^[[:space:]]*timeout[[:space:]]+client[[:space:]]+' "$f" || exit 10
grep -Eq '^[[:space:]]*timeout[[:space:]]+client[[:space:]]+5s[[:space:]]*$' "$f" && exit 10
sauver "$f"
sed -i -E '0,/^([[:space:]]*)timeout[[:space:]]+client[[:space:]]+.*/s//\1timeout client 5s/' "$f"
if ! haproxy -c -f "$f" >/dev/null 2>&1; then restaurer_fichiers; exit 1; fi
touch -d '-2 days' "$f"
sha256sum "$f" > "$WB_DIR/$WB_EX.injecte"
systemctl reload haproxy
journal "haproxy.cfg : timeout client passé à 5s à la main"
EOF
      ;;
    2)
      h="$_S03_DNS02"
      wb_exec "$h" <<'EOF' || return $?
f=/etc/chrony/chrony.conf
[ -f "$f" ] || exit 10
grep -q 'pool.ntp.org' "$f" && exit 10
sauver "$f"
printf '\n# Source de secours (test, Lucas)\npool 2.debian.pool.ntp.org iburst maxsources 2\n' >> "$f"
touch -d '-2 days' "$f"
sha256sum "$f" > "$WB_DIR/$WB_EX.injecte"
systemctl restart chrony
journal "chrony.conf : source publique ajoutée à la main"
EOF
      ;;
  esac
  _s03_poser couche2 "$n"
  _s03_poser couche2-hote "$h"
}

_s03_couche2_verifier() {
  local h
  h="$(_s03_lire couche2-hote)"
  case "$(_s03_lire couche2)" in
    # haproxy.cfg est en 0640 root:haproxy (rôle haproxy, M07) : lecture par sudo, comme les checks.
    1) remote "$h" "sudo -n grep -Eq '^[[:space:]]*timeout[[:space:]]+client[[:space:]]+5s' /etc/haproxy/haproxy.cfg" </dev/null ;;
    2) remote "$h" "sudo -n grep -q '^pool 2.debian.pool.ntp.org' /etc/chrony/chrony.conf" </dev/null ;;
    *) return 1 ;;
  esac
}

_s03_couche2_annuler() {
  local h
  h="$(_s03_lire couche2-hote)"
  [[ -n "$h" ]] || return 0
  wb_exec "$h" <<'EOF' || wb_avert "couche 2 : annulation incomplète sur $h"
m="$WB_DIR/$WB_EX.manifeste"
if [ -f "$WB_DIR/$WB_EX.injecte" ] && ! sha256sum -c --status "$WB_DIR/$WB_EX.injecte" 2>/dev/null; then
  journal "annulation : fichier modifié depuis la panne (réparation), laissé tel quel"
  if [ -f "$m" ]; then
    while IFS="$(printf '\t')" read -r src dst; do
      if [ "$dst" != ABSENT ]; then rm -f "$dst"; fi
    done < "$m"
    rm -f "$m"
  fi
else
  restaurer_fichiers
  journal "annulation : fichier d'origine remis"
fi
rm -f "$WB_DIR/$WB_EX.injecte"
if [ -f /etc/haproxy/haproxy.cfg ] && haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
  systemctl reload haproxy >/dev/null 2>&1 || true
fi
if [ -f /etc/chrony/chrony.conf ]; then systemctl restart chrony >/dev/null 2>&1 || true; fi
EOF
}

# --- Couche 3 : objet du cluster hors GitOps ------------------------------------------------------
_s03_c3_cible() {
  case "$1" in
    1) echo "cert-manager cert-manager" ;;
    2) echo "external-dns external-dns" ;;
  esac
}

_s03_c3_limite() {
  wb_kubectl -n "$1" get deployment "$2" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null
}

_s03_couche3() {
  local n="$1" ns dep actuelle neuve
  read -r ns dep <<<"$(_s03_c3_cible "$n")"
  actuelle="$(_s03_c3_limite "$ns" "$dep")"
  case "$actuelle" in
    320Mi) neuve=384Mi ;;
    *) neuve=320Mi ;;
  esac
  wb_k8s_sauver deployment "$dep" "$ns"
  wb_kubectl -n "$ns" set resources "deployment/$dep" --limits="memory=$neuve" >/dev/null || return 1
  _s03_poser couche3 "$n"
  _s03_poser couche3-valeur "$neuve"
  _s03_journal "couche 3 : $ns/$dep limite mémoire $actuelle → $neuve (kubectl set resources)"
}

_s03_couche3_verifier() {
  local ns dep
  read -r ns dep <<<"$(_s03_c3_cible "$(_s03_lire couche3)")"
  [[ -n "$ns" && "$(_s03_c3_limite "$ns" "$dep")" == "$(_s03_lire couche3-valeur)" ]]
}

_s03_couche3_annuler() {
  local n ns dep d
  n="$(_s03_lire couche3)"
  d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/k8s/F1-S03"
  if [[ -n "$n" ]]; then
    read -r ns dep <<<"$(_s03_c3_cible "$n")"
    if [[ "$(_s03_c3_limite "$ns" "$dep")" == "$(_s03_lire couche3-valeur)" ]]; then
      wb_k8s_restaurer || wb_avert "couche 3 : restauration de $ns/$dep incomplète (sauvegarde conservée dans $d)"
      _s03_journal "annulation : $ns/$dep remis"
      return 0
    fi
    _s03_journal "annulation : $ns/$dep modifié depuis la panne (réparation), laissé tel quel"
  fi
  rm -rf -- "$d"
}

# --- Points d'entrée -----------------------------------------------------------------------------
_s03_injecter() {
  local n="$1" n2 n3 i essai
  _s03_sain || return 1
  # Couche 1 : la variante demandée, sinon la suivante qui a un effet sur ce lab (code 10).
  for ((i = 0; i < 3; i++)); do
    essai=$(((n - 1 + i) % 3 + 1))
    if _s03_couche1 "$essai"; then break; fi
    wb_exec "$WB_PVE_HOST" <<'EOF' >/dev/null 2>&1 || true
rm -f "$WB_DIR/$WB_EX.vm-injecte"
EOF
    ((i == 2)) && { wb_avert "couche 1 : aucune variante applicable à la VM $_S03_VMID"; return 1; }
  done
  n2=$(((n - 1) % 2 + 1))
  if ! _s03_couche2 "$n2"; then
    n2=$((3 - n2))
    _s03_couche2 "$n2" || { wb_avert "couche 2 : aucune variante applicable"; return 1; }
  fi
  n3=$((n % 2 + 1))
  _s03_couche3 "$n3" || return 1
  _s03_journal "injectée : couche 1 v$(_s03_lire couche1), couche 2 v$n2 ($(_s03_lire couche2-hote)), couche 3 v$n3"
}

panne_S03_v1() { _s03_injecter 1; }
panne_S03_v2() { _s03_injecter 2; }
panne_S03_v3() { _s03_injecter 3; }

verifier_S03() {
  _s03_couche1_verifier && _s03_couche2_verifier && _s03_couche3_verifier
}

annuler_S03() {
  _s03_couche1_annuler
  _s03_couche2_annuler
  _s03_couche3_annuler
  _s03_journal "annulation terminée"
  rm -f -- "$(_s03_etat)/couche1" "$(_s03_etat)/couche2" "$(_s03_etat)/couche2-hote" \
    "$(_s03_etat)/couche3" "$(_s03_etat)/couche3-valeur"
}

resume_S03() {
  echo "Le diff n'est pas vide quelque part sur le socle ou le cluster, et Karim a un doute sur lb02."
}

symptome_S03() {
  wb_symptome "Ticket INC-5703 — De : Karim Benali" \
    "Je relisais le plan de la reconstruction et j'ai relancé les contrôles de dérive par acquit" \
    "de conscience : le diff n'est pas vide quelque part. Je n'ai pas eu le temps de creuser." \
    "J'ai un doute sur lb02, quelqu'un y a travaillé pendant l'astreinte du week-end dernier," \
    "mais je ne suis sûr de rien et ce n'est peut-être pas le seul endroit." \
    "On ne détruit rien tant que le code et la réalité ne disent pas la même chose." \
    "Trouve tout, décide pour chaque écart (retour au code ou code qui adopte la réalité), et trace-le." \
    "" \
    "Temps cible : 1 h 30. Contrôle : lab/bin/check F1 3"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F1 S03 3 "$@"; }
fi
