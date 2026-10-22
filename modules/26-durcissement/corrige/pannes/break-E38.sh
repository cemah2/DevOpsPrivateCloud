# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M26-E38 « Panne : sudo cassé après le durcissement »
#
# Sur UNE VM non critique (jamais adm01, gw01/gw02, pbs01) : le durcissement a cassé « sudo -n » du
# compte d'automatisation « admin » (celui d'Ansible et des checks). Variantes :
#   1. « Defaults requiretty » posé dans un drop-in : sudo refuse de tourner sans terminal (Ansible en
#      pipelining, nos checks en SSH non interactif) ;
#   2. le drop-in NOPASSWD d'admin rendu inscriptible par tous (0666) : sudo l'IGNORE (il exige un
#      fichier non inscriptible par le groupe/les autres), admin doit saisir un mot de passe ;
#   3. NOPASSWD retiré d'admin et « Defaults timestamp_timeout=0 » : admin doit s'authentifier à chaque
#      appel, donc « sudo -n » échoue.
#
# ⚠️ L'injection écrit par SSH+sudo (sudo marche encore). L'ANNULATION passe par l'agent QEMU (qm guest
# exec, root dans l'invité, sans sudo) : c'est le filet de sécurité quand sudo est cassé. break refuse
# d'injecter si l'agent QEMU ne répond pas.
#
# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m26-commun.sh
source "$WB_ROOT/modules/26-durcissement/corrige/pannes/_m26-commun.sh"

_e38_cible() {
  local c
  c="$(m26_lire E38 cible)"
  if [[ -z "$c" ]]; then c="$(m26_hasard "${_M26_VMS_SUDO[@]}")"; m26_ecrire E38 cible "$c"; fi
  printf '%s\n' "$c"
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }

_e38_injecter() {
  local n="$1" cible
  cible="$(_e38_cible)"
  m26_hote_sain "$cible" || { m26_oublier E38 cible; return 1; }
  m26_ecrire E38 variante "$n"
  case "$n" in
    1)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || return 1
d=/etc/sudoers.d/90-durcissement-requiretty
sauver "$d"
printf 'Defaults requiretty\n' > "$d"
chmod 0440 "$d"
journal "Defaults requiretty posé dans $d (sudo refuse sans tty)"
EOF
      ;;
    2)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || return 1
# Drop-in qui donne NOPASSWD à admin (déposé par cloud-init ou le rôle).
f="$(grep -Els '^admin[[:space:]].*NOPASSWD' /etc/sudoers.d/* 2>/dev/null | head -n1)"
[ -n "$f" ] || f=/etc/sudoers.d/90-cloud-init-users
[ -e "$f" ] || { echo "aucun drop-in NOPASSWD pour admin" >&2; exit 1; }
sauver "$f"
chmod 0666 "$f"
journal "drop-in $f rendu inscriptible par tous (0666) : ignoré par sudo"
EOF
      ;;
    3)
      m26_wb_exec "$cible" >/dev/null <<'EOF' || return 1
f="$(grep -Els '^admin[[:space:]].*NOPASSWD' /etc/sudoers.d/* 2>/dev/null | head -n1)"
[ -n "$f" ] || { echo "aucun drop-in NOPASSWD pour admin" >&2; exit 1; }
sauver "$f"
# Retire NOPASSWD et pose timestamp_timeout=0 (réauthentification à chaque appel).
sed -i 's/NOPASSWD:[[:space:]]*//' "$f"
d=/etc/sudoers.d/10-durcissement-timeout
sauver "$d"
printf 'Defaults timestamp_timeout=0\n' > "$d"
chmod 0440 "$d"
journal "NOPASSWD retiré d'admin dans $f ; timestamp_timeout=0 dans $d"
EOF
      ;;
  esac
  m26_journal E38 "variante $n posée sur $cible"
}

# La panne est effective si « sudo -n » du compte admin ne fonctionne plus (via SSH, comme Ansible).
verifier_E38() {
  local cible
  cible="$(_e38_cible)"
  ! m26_ssh "$cible" 'true' >/dev/null 2>&1
}

annuler_E38() {
  local cible
  cible="$(m26_lire E38 cible)"
  if [[ -n "$cible" ]]; then
    # Par l'agent QEMU : root dans l'invité, ne dépend pas de sudo (qui peut être cassé).
    WB_EX=M26-E38 m26_wb_exec_invite "$cible" >/dev/null <<'EOF' || wb_avert "annulation par l'agent QEMU incomplète sur $cible"
restaurer_fichiers
faillock --user admin --reset 2>/dev/null || true
journal "annulation : fichiers sudoers rétablis (agent QEMU)"
EOF
  fi
  m26_oublier E38 variante
  m26_oublier E38 cible
  m26_journal E38 "annulation"
}

resume_E38() { echo "Sur une VM du socle, « sudo » du compte d'automatisation admin ne fonctionne plus (Ansible et checks en échec)."; }

symptome_E38() {
  local cible
  cible="$(_e38_cible)"
  wb_symptome "Ticket INC-5338 — De : Nadia Roussel" \
    "Le playbook de nuit a échoué sur $cible : « sudo: a password is required » ou « sudo: a terminal" \
    "is required ». Le compte admin ne peut plus rien faire en sudo non interactif. C'est arrivé après" \
    "la vague de durcissement. Garde un accès de secours : la console Proxmox et l'agent QEMU répondent" \
    "encore (l'annulation du workbook passe par là si tu te bloques)." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 26 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 26 E38 3 "$@"; }
fi
