# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M01-E40 « Panne : clone et push en SSH impossibles »
#
# Variantes :
#   1. compte système « git » de git01 expiré (chage -E) : sshd refuse toute connexion git@ — git01 ;
#   2. clé d'hôte de git01.par1.medisphere.internal remplacée par une autre dans
#      ~/.ssh/known_hosts de l'apprenant (alerte « REMOTE HOST IDENTIFICATION HAS CHANGED ») — adm01 ;
#   3. gitlab_url de /var/opt/gitlab/gitlab-shell/config.yml (fichier GÉNÉRÉ) modifié : gitlab-shell
#      ne joint plus l'API interne — git01 ;
#   4. bloc « Host *.par1.medisphere.internal » avec un ProxyJump vers un ancien bastion du
#      prestataire inséré avant les autres blocs de ~/.ssh/config — adm01.
# Sauvegardes : /var/lib/workbook/M01-E40.* sur git01 (v1 : date d'expiration d'origine ; v3 :
#   config.yml) ; ~/.local/state/workbook/M01-E40/ sur adm01 (v2 : entrées known_hosts d'origine
#   et clé factice ; v4 : présence d'origine de ~/.ssh/config).
# Les connexions maîtresses SSH (ControlMaster, M00-E15) vers la forge sont fermées après
# injection, sinon la panne resterait masquée jusqu'à 5 minutes.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m01-commun.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m01-commun.sh"

_E40_KH="$HOME/.ssh/known_hosts"
_E40_CFG="$HOME/.ssh/config"
_E40_DEBUT_BLOC="# Raccordement au bastion InfoGér (procédure INF-4411)"

panne_E40_v1() {
  wb_exec git01 >/dev/null <<'EOF'
getent shadow git >/dev/null || exit 1
[ -f "$WB_DIR/$WB_EX.expiration-git" ] || getent shadow git | cut -d: -f8 > "$WB_DIR/$WB_EX.expiration-git"
chage -E 0 git
journal "compte git expiré (chage -E 0)"
EOF
  m01_ssh_fermer_maitre
}

panne_E40_v2() {
  local etat tmp hote="$_M01_FQDN_GIT" ligne cle
  etat="$(m01_etat E40)"
  [[ -f "$_E40_KH" ]] || return 1
  ssh-keygen -F "$hote" -f "$_E40_KH" 2>/dev/null | grep -v '^#' > "$etat/known_hosts.orig" || true
  [[ -s "$etat/known_hosts.orig" ]] || { wb_avert "aucune entrée $hote dans $_E40_KH"; return 1; }
  tmp="$(mktemp -d)"
  ssh-keygen -q -t ed25519 -N '' -C '' -f "$tmp/k"
  cle="$(awk '{print $1" "$2}' "$tmp/k.pub")"
  rm -rf "$tmp"
  printf '%s\n' "$cle" > "$etat/cle-factice"
  ssh-keygen -R "$hote" -f "$_E40_KH" >/dev/null 2>&1 || return 1
  rm -f "$_E40_KH.old"
  # Entrée factice au même format que l'existante (hachée ou en clair).
  if grep -q '^|1|' "$etat/known_hosts.orig"; then
    ligne="$(_E40_hacher "$hote") $cle"
  else
    ligne="$hote $cle"
  fi
  printf '%s\n' "$ligne" >> "$_E40_KH"
  m01_ssh_fermer_maitre
}

# _E40_hacher HÔTE — nom d'hôte haché au format known_hosts (|1|sel|HMAC-SHA1).
_E40_hacher() {
  local f sel_hex sel_b64 mac
  f="$(mktemp)"
  head -c 20 /dev/urandom > "$f"
  sel_hex="$(od -An -tx1 "$f" | tr -d ' \n')"
  sel_b64="$(base64 < "$f")"
  rm -f "$f"
  mac="$(printf '%s' "$1" | openssl dgst -sha1 -mac HMAC -macopt "hexkey:$sel_hex" -binary | base64)"
  printf '|1|%s|%s\n' "$sel_b64" "$mac"
}

panne_E40_v3() {
  wb_exec git01 >/dev/null <<'EOF'
f=/var/opt/gitlab/gitlab-shell/config.yml
grep -q '^gitlab_url:' "$f" || exit 1
sauver "$f"
sed -i 's#^gitlab_url:.*#gitlab_url: "http+unix://%2Fvar%2Fopt%2Fgitlab%2Fgitlab-workhorse%2Fworkhorse.sock"#' "$f"
journal "gitlab-shell/config.yml : gitlab_url vers une socket inexistante"
EOF
}

panne_E40_v4() {
  local etat tmp
  etat="$(m01_etat E40)"
  if [[ ! -f "$etat/config.etat" ]]; then
    if [[ -f "$_E40_CFG" ]]; then echo present > "$etat/config.etat"; else echo absent > "$etat/config.etat"; fi
  fi
  grep -qxF "$_E40_DEBUT_BLOC" "$_E40_CFG" 2>/dev/null && return 1
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  touch "$_E40_CFG" && chmod 600 "$_E40_CFG"
  tmp="$(mktemp)"
  # Bloc inséré juste avant le premier « Host »/« Match » : les options globales en tête restent globales.
  awk -v debut="$_E40_DEBUT_BLOC" '
    function bloc() {
      print debut
      print "Host *.par1.medisphere.internal"
      print "    ProxyJump admin@bastion-infoger.medisphere.internal"
      print ""
      fait = 1
    }
    !fait && /^[[:space:]]*(Host|Match)[[:space:]]/ { bloc() }
    { print }
    END { if (!fait) { print ""; bloc() } }
  ' "$_E40_CFG" > "$tmp" && cat "$tmp" > "$_E40_CFG"
  rm -f "$tmp"
  m01_ssh_fermer_maitre
}

verifier_E40() {
  ! m01_ssh_forge_ok
}

annuler_E40() {
  local etat tmp hote="$_M01_FQDN_GIT" cle
  etat="$(m01_etat E40)"
  # v2 : retirer la clé factice ; remettre les entrées d'origine si l'hôte n'est plus connu.
  if [[ -s "$etat/cle-factice" ]]; then
    cle="$(<"$etat/cle-factice")"
    if [[ -f "$_E40_KH" ]] && grep -qF "${cle#* }" "$_E40_KH"; then
      tmp="$(mktemp)"
      grep -vF "${cle#* }" "$_E40_KH" > "$tmp" || true
      cat "$tmp" > "$_E40_KH"
      rm -f "$tmp"
    fi
    if ! ssh-keygen -F "$hote" -f "$_E40_KH" >/dev/null 2>&1 && [[ -s "$etat/known_hosts.orig" ]]; then
      cat "$etat/known_hosts.orig" >> "$_E40_KH"
    fi
    rm -f "$etat/cle-factice" "$etat/known_hosts.orig"
  fi
  # v4 : retirer le bloc injecté (s'il est encore là).
  if [[ -f "$etat/config.etat" ]]; then
    if grep -qxF "$_E40_DEBUT_BLOC" "$_E40_CFG" 2>/dev/null; then
      tmp="$(mktemp)"
      awk -v debut="$_E40_DEBUT_BLOC" '
        $0 == debut { saute = 3; next }
        saute > 0 { saute--; if (saute == 0 && $0 != "") print; next }
        { print }
      ' "$_E40_CFG" > "$tmp" && cat "$tmp" > "$_E40_CFG"
      rm -f "$tmp"
    fi
    if [[ "$(<"$etat/config.etat")" == absent && ! -s "$_E40_CFG" ]]; then
      rm -f "$_E40_CFG"
    fi
    rm -f "$etat/config.etat"
  fi
  # v1, v3 (git01)
  if [[ "${WB_VAR:-}" != 2 && "${WB_VAR:-}" != 4 ]]; then
    wb_exec git01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur git01"
if [ -f "$WB_DIR/$WB_EX.expiration-git" ]; then
  exp="$(cat "$WB_DIR/$WB_EX.expiration-git")"
  chage -E "${exp:--1}" git && rm -f "$WB_DIR/$WB_EX.expiration-git"
  journal "annulation : date d'expiration du compte git rétablie (${exp:-aucune})"
fi
restaurer_fichiers
exit 0
EOF
  fi
  m01_ssh_fermer_maitre
  return 0
}

resume_E40() {
  echo "Plus moyen de cloner ni de pousser en SSH sur git01 (git@git01.par1.medisphere.internal) ; l'interface web fonctionne."
}

symptome_E40() {
  wb_symptome "Ticket INC-2785 — De : Lucas Martin" \
    "Je voulais cloner plateforme/medisphere sur adm01 pour relire une MR, mais" \
    "« git clone git@git01.par1.medisphere.internal:plateforme/medisphere.git » échoue," \
    "et « git push » depuis ~/medisphere aussi. L'interface web, elle, marche très bien." \
    "Je n'ai touché à rien (promis)." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 01 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 01 E40 4 "$@"; }
fi
