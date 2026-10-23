# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # scripts distants entre apostrophes
# break-E22.sh — M29-E22 « Panne : les tests d'infrastructure sont rouges »
#
# Dérive RÉELLE posée à la main sur une VM non critique du socle (WB_M29_E22_HOTES, défaut
# « nbx01 mon01 ») ; la suite Testinfra de l'apprenant (WB_M29_TESTINFRA_CMD) doit être verte sur
# l'hôte avant, et rouge après : sinon la variante est « sans effet » et on essaie la suivante.
#   1. chrony : /etc/chrony/chrony.conf retouché à la main, source remplacée par 10.10.20.254 (« nouveau
#      serveur de temps » qui n'existe pas), chrony redémarré : plus synchronisé. Le template du rôle
#      base le voit (--check) ;
#   2. sshd : fichier /etc/ssh/sshd_config.d/00-debogage.conf (X11Forwarding, AllowTcpForwarding,
#      MaxAuthTries 10), lu AVANT les fichiers des rôles : configuration effective changée. Le rôle ne
#      gère pas les fichiers qui ne sont pas à lui : --check ne voit rien ;
#   3. node_exporter : service arrêté et désactivé. Le rôle node_exporter le voit (--check).
# Fichiers sauvegardés dans /var/lib/workbook/ de la VM ; l'annulation remet l'état d'origine si le
# fichier est encore exactement dans l'état injecté (empreinte sha256), sinon elle respecte la réparation.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m29-commun.sh
source "$WB_ROOT/modules/29-tests-resilience/corrige/pannes/_m29-commun.sh"

read -r -a _E22_HOTES <<<"${WB_M29_E22_HOTES:-nbx01 mon01}"
# {hote} est remplacé par le nom de la VM. Lancé depuis adm01, dans un sous-shell.
_E22_CMD="${WB_M29_TESTINFRA_CMD:-cd ~/src/ansible && uv run pytest tests/infra -q -p no:cacheprovider --hosts=ansible://{hote}}"

_e22_hote() { m29_lire E22 hote; }

# _e22_suite HÔTE — code de retour de la suite Testinfra sur l'hôte (0 vert, 1 rouge, autre : erreur).
_e22_suite() {
  local cmd="${_E22_CMD//\{hote\}/$1}"
  (bash -c "$cmd") >"$(m29_etat E22)/suite.log" 2>&1
}

_e22_sain() {
  local h rc=0
  m29_outils ssh || return 1
  h="$(m29_hasard "${_E22_HOTES[@]}")"
  remote "$h" true </dev/null >/dev/null 2>&1 || { echo "SSH vers $h impossible depuis adm01." >&2; return 1; }
  _e22_suite "$h" || rc=$?
  case "$rc" in
    0) ;;
    1) echo "La suite Testinfra est DÉJÀ rouge sur $h (journal : $(m29_etat E22)/suite.log) : répare d'abord." >&2; return 1 ;;
    *) echo "La suite Testinfra ne s'exécute pas sur $h (code $rc, journal : $(m29_etat E22)/suite.log)." >&2
       echo "Vérifie M29-E04 ou règle WB_M29_TESTINFRA_CMD dans lab/lab.env." >&2; return 1 ;;
  esac
  m29_poser E22 hote "$h"
}

_m29E22_une() {
  local n="$1" h rc=0
  h="$(_e22_hote)"
  case "$n" in
    1) wb_exec "$h" <<'EOF' || return $?
f=/etc/chrony/chrony.conf
[ -f "$f" ] && grep -qE '^(server|pool) ' "$f" || exit 10
sauver "$f"
sed -i -E 's/^(server|pool) .*/server 10.10.20.254 iburst/' "$f"
# commentaire laissé par « Lucas » : la trace existe
sed -i '1i # Nouveau serveur de temps du site (test, Lucas)' "$f"
touch -d '-9 hours' "$f"
sha256sum "$f" > "$WB_DIR/$WB_EX.injecte"
systemctl restart chrony
journal "chrony : source remplacée par 10.10.20.254"
EOF
       ;;
    2) wb_exec "$h" <<'EOF' || return $?
f=/etc/ssh/sshd_config.d/00-debogage.conf
[ -d /etc/ssh/sshd_config.d ] || exit 10
sauver "$f"
printf '# Débogage du transfert de port pour la supervision (Lucas)\nX11Forwarding yes\nAllowTcpForwarding yes\nMaxAuthTries 10\n' > "$f"
chmod 600 "$f"
touch -d '-9 hours' "$f"
if ! sshd -t; then rm -f "$f"; exit 1; fi
sha256sum "$f" > "$WB_DIR/$WB_EX.injecte"
systemctl reload ssh
journal "sshd : $f ajouté"
EOF
       ;;
    3) wb_exec "$h" <<'EOF' || return $?
systemctl is-active --quiet node_exporter || exit 10
printf '%s\n' "$(systemctl is-enabled node_exporter 2>/dev/null)" > "$WB_DIR/$WB_EX.node_exporter-enabled"
systemctl disable --now node_exporter >/dev/null 2>&1
journal "node_exporter arrêté et désactivé"
EOF
       ;;
  esac
  m29_poser E22 variante "$n"
  sleep 5
  # La dérive doit être vue par la suite de l'apprenant.
  _e22_suite "$h" || rc=$?
  ((rc == 1)) || return 10
  m29_journal E22 "variante $n posée sur $h (suite Testinfra rouge)"
}

_m29E22_defaire() {
  local h
  h="$(_e22_hote)"
  [[ -n "$h" ]] || return 0
  # Un fichier n'est remis que s'il est encore EXACTEMENT dans l'état injecté (empreinte notée à
  # l'injection) : une réparation de l'apprenant (rôle Ansible rejoué, fichier retiré) n'est jamais défaite.
  wb_exec "$h" <<'EOF' || true
m="$WB_DIR/$WB_EX.manifeste"
if [ -f "$WB_DIR/$WB_EX.injecte" ] && ! sha256sum -c --status "$WB_DIR/$WB_EX.injecte" 2>/dev/null; then
  journal "annulation : fichier modifié ou retiré depuis la panne (réparation), laissé tel quel"
  if [ -f "$m" ]; then
    while IFS="$(printf '\t')" read -r src dst; do
      if [ "$dst" != ABSENT ]; then rm -f "$dst"; fi
    done < "$m"
    rm -f "$m"
  fi
else
  restaurer_fichiers
fi
rm -f "$WB_DIR/$WB_EX.injecte"
if [ -f "$WB_DIR/$WB_EX.node_exporter-enabled" ]; then
  systemctl enable --now node_exporter >/dev/null 2>&1 || true
  rm -f "$WB_DIR/$WB_EX.node_exporter-enabled"
fi
systemctl restart chrony >/dev/null 2>&1 || true
if sshd -t 2>/dev/null; then systemctl reload ssh >/dev/null 2>&1 || true; fi
journal "annulation : état d'origine remis"
EOF
}

panne_E22_v1() { _e22_sain && m29_essayer E22 3 1; }
panne_E22_v2() { _e22_sain && m29_essayer E22 3 2; }
panne_E22_v3() { _e22_sain && m29_essayer E22 3 3; }

verifier_E22() {
  local h
  h="$(_e22_hote)"
  case "$(m29_lire E22 variante)" in
    1) remote "$h" "grep -q '^server 10.10.20.254 ' /etc/chrony/chrony.conf" </dev/null ;;
    2) remote "$h" "sudo -n sshd -T 2>/dev/null | grep -qx 'x11forwarding yes'" </dev/null ;;
    3) ! remote "$h" "systemctl is-active --quiet node_exporter" </dev/null ;;
    *) return 1 ;;
  esac
}

annuler_E22() {
  _m29E22_defaire
  m29_oublier E22 variante
  m29_journal E22 "annulation"
  m29_oublier E22 hote
}

resume_E22() {
  echo "La suite Testinfra est rouge sur $(_e22_hote) depuis cette nuit."
}

symptome_E22() {
  wb_symptome "Ticket PLAT-3022 — De : Nadia Roussel" \
    "Les tests d'infrastructure sont rouges sur $(_e22_hote) depuis cette nuit, et seulement là." \
    "Lucas dit que « c'est encore un test flou, il suffit de relancer ». Il a relancé trois fois." \
    "Je ne veux pas qu'on s'habitue à ignorer ce job. Dis-moi qui a raison, le test ou la VM," \
    "et répare ce qu'il faut réparer, comme il faut." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 29 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 29 E22 3 "$@"; }
fi
