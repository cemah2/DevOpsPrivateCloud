# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E21.sh — M11-E21 « Panne : l'installation reste bloquée »
#
# Variantes (fichiers servis par pxe01, sous la racine nginx) :
#   1. preseed de bm01 (preseed/bm01.cfg, à défaut le premier preseed) : la ligne
#      « d-i partman/confirm boolean true » est commentée → d-i (priority=critical) pose la
#      question « Écrire les modifications sur les disques ? » et attend ;
#   2. kickstart de bm03 (kickstart/bm03.ks, à défaut le premier) : la source « url --url=… » pointe
#      vers …/BaseOs/… (casse) → Anaconda : erreur de configuration de la source d'installation ;
#      si le kickstart n'a pas de « url », c'est inst.repo du script iPXE de la machine qui est touché ;
#   3. kickstart de bm03 : « ignoredisk --only-use=sda » devient « …=sdb » (disque absent) →
#      Anaconda s'arrête sur une erreur de stockage.
# Seuls les fichiers servis sont touchés (pas les gabarits du dépôt) : la comparaison avec le rendu du
# code est le bon réflexe de diagnostic. Sauvegardes : /var/lib/workbook/M11-E21.* sur pxe01.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m11-commun.sh
source "$WB_ROOT/modules/11-bare-metal/corrige/pannes/_m11-commun.sh"

# _e21_servi CHEMIN — contenu servi par pxe01 en HTTPS (depuis pxe01 lui-même : les fichiers de
# réponse sont réservés au VLAN 60 et à adm01 ; adm01 passe aussi).
_e21_servi() {
  curl -sS --fail --max-time 10 --resolve "$_M11_PXE_FQDN:443:$_M11_PXE_IP" \
    "https://$_M11_PXE_FQDN$1" 2>/dev/null
}

# _e21_fichier TYPE NOM — chemin relatif (preseed/bm01.cfg…) du fichier visé, ou le premier du type.
_e21_fichier() {
  m11_wb_exec pxe01 D="$1" N="$2" 2>/dev/null <<'EOF'
r="$(nginx_racine)"
[ -n "$r" ] || exit 1
if [ -f "$r/$D/$N" ]; then f="$r/$D/$N"; else f="$(ls "$r/$D"/* 2>/dev/null | head -n 1)"; fi
[ -n "$f" ] && printf '%s\n' "${f#"$r"}"
EOF
}

_e21_precondition() {
  local p k
  p="$(_e21_fichier preseed bm01.cfg)"
  k="$(_e21_fichier kickstart bm03.ks)"
  if [[ -z "$p" && -z "$k" ]]; then
    wb_avert "pxe01 ne sert ni preseed ni kickstart sous sa racine : lab/bin/check 11 21"
    return 1
  fi
  m11_ecrire E21 preseed "$p"
  m11_ecrire E21 kickstart "$k"
}

_mE21_une() {
  local n="$1" rc=0 cible
  case "$n" in
    1)
      cible="$(m11_lire E21 preseed)"
      [[ -n "$cible" ]] || return 10
      m11_wb_exec pxe01 F="$cible" >/dev/null <<'EOF' || rc=$?
f="$(nginx_racine)$F"
subst "$f" '^d-i[ \t]+partman/confirm[ \t]+boolean[ \t]+true[ \t]*$' '#d-i partman/confirm boolean true' || exit $?
journal "$f : partman/confirm commenté"
EOF
      ;;
    2)
      cible="$(m11_lire E21 kickstart)"
      [[ -n "$cible" ]] || return 10
      m11_wb_exec pxe01 F="$cible" >/dev/null <<'EOF' || rc=$?
r="$(nginx_racine)"
f="$r$F"
if subst "$f" '^(url[ \t].*--url=?[ \t]*\S*?)/BaseOS/' '\1/BaseOs/'; then
  journal "$f : url du kickstart faussée (BaseOs)"
  exit 0
fi
# Pas de « url » dans le kickstart : la source vient d'inst.repo, dans le script iPXE de la machine.
h="$(basename "$f" .ks)"
s="$(grep -l "kickstart/$h\.ks" "$r"/ipxe/mac-*.ipxe 2>/dev/null | head -n 1)"
[ -n "$s" ] || exit 10
subst "$s" '(inst\.repo=\S*?)/BaseOS/' '\1/BaseOs/' || exit $?
printf '%s\n' "${s#"$r"}" >"$WB_DIR/M11-E21.cible"
journal "$s : inst.repo faussé (BaseOs)"
EOF
      ;;
    3)
      cible="$(m11_lire E21 kickstart)"
      [[ -n "$cible" ]] || return 10
      m11_wb_exec pxe01 F="$cible" >/dev/null <<'EOF' || rc=$?
f="$(nginx_racine)$F"
d="$(sed -nE 's/^ignoredisk[ \t]+--only-use=([a-z0-9]+).*/\1/p' "$f" | head -n 1)"
[ -n "$d" ] || exit 10
case "$d" in sdb) nv=sdc ;; vdb) nv=vdc ;; *) nv=sdb ;; esac
subst "$f" "^(ignoredisk[ \\t]+--only-use=)$d\\b" "\\g<1>$nv" || exit $?
journal "$f : ignoredisk $d → $nv"
EOF
      ;;
  esac
  ((rc == 0)) || return "$rc"
  verifier_E21_n "$n" || { _e21_defaire; return 10; }
}

verifier_E21_n() {
  local c
  case "$1" in
    1) ! _e21_servi "$(m11_lire E21 preseed)" | grep -Eq '^d-i[[:space:]]+partman/confirm[[:space:]]+boolean[[:space:]]+true' ;;
    2)
      c="$(m11_wb_exec pxe01 2>/dev/null <<'EOF'
cat "$WB_DIR/M11-E21.cible" 2>/dev/null || true
EOF
)"
      _e21_servi "${c:-$(m11_lire E21 kickstart)}" | grep -q '/BaseOs/' ;;
    3) _e21_servi "$(m11_lire E21 kickstart)" | grep -Eq '^ignoredisk[[:space:]]+--only-use=(sdb|sdc|vdc)' ;;
    *) return 1 ;;
  esac
}

_e21_defaire() {
  m11_wb_exec pxe01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pxe01 (fichiers de réponse)"
defaire_subst >/dev/null
rm -f "$WB_DIR/M11-E21.cible"
EOF
}

_e21_injecter() {
  _e21_precondition || return 1
  m11_essayer E21 3 "$1"
}

panne_E21_v1() { _e21_injecter 1; }
panne_E21_v2() { _e21_injecter 2; }
panne_E21_v3() { _e21_injecter 3; }

verifier_E21() { verifier_E21_n "${WB_VAR:-0}"; }

annuler_E21() {
  _e21_defaire
  m11_effacer E21 preseed
  m11_effacer E21 kickstart
}

resume_E21() {
  case "${WB_VAR:-0}" in
    1) echo "L'installation Debian de bm01 s'arrête en cours de route et attend." ;;
    *) echo "L'installation Rocky de bm03 s'arrête en cours de route et attend." ;;
  esac
}

symptome_E21() {
  local -a l
  case "${WB_VAR:-0}" in
    1) l=("L'installation de bm01 (Debian 13) ne se termine plus. Le démarrage réseau se passe"
      "bien, l'installateur démarre, configure le réseau, puis reste sur un écran bleu au milieu"
      "de l'installation. Ça fait une heure, et rien ne bouge.") ;;
    *) l=("L'installation de bm03 (Rocky 10) ne se termine plus. Le démarrage réseau se passe"
      "bien, Anaconda démarre en mode texte, puis plus rien ne bouge : l'écran affiche un"
      "résumé de l'installation et semble attendre. Ça fait une heure.") ;;
  esac
  wb_symptome "Ticket INC-3843 — De : Julien Petit" "${l[@]}" "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 11 21"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 11 E21 3 "$@"; }
fi
