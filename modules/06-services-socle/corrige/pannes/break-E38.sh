# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M06-E38 « Panne : connexion SSH par certificat refusée »
#
# Cible tirée au hasard parmi nbx01, ca01 et dns02 (hôtes qui acceptent les certificats d'utilisateur,
# dont l'agent QEMU répond et qui ont un compte de secours `secours`). Variantes :
#   1. TrustedUserCAKeys : le fichier contient la clé publique de la CA d'HÔTE au lieu de celle de la
#      CA d'UTILISATEUR (confusion lors d'un « redéploiement ») ;
#   2. AuthorizedPrincipalsFile de admin : le principal « admin » devient « Admin » (« normalisation ») ;
#   3. /etc/ssh/sshd_config.d/00-anssi.conf : PubkeyAcceptedAlgorithms sans les algorithmes de
#      certificats (*-cert-v01@openssh.com) — durcissement recopié d'un guide ;
#   4. RevokedKeys : la clé de admin (celle que porte ton certificat sur adm01) est ajoutée à la liste
#      de révocation (KRL) de l'hôte, au lieu de la clé d'un portable perdu.
# Le script ne touche jamais à la clé ni au compte de secours. Annulation par l'agent QEMU (SSH est en
# cause) ; rien n'est rétabli qui a déjà été réparé.
# Sauvegardes : /var/lib/workbook/M06-E38.* sur la cible ; cible tirée : ~/.local/state/workbook/M06-E38/.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m06-commun.sh
source "$WB_ROOT/modules/06-services-socle/corrige/pannes/_m06-commun.sh"

# _e38_eligible HÔTE — accepte les certificats d'utilisateur, SSH par certificat OK, agent, secours.
_e38_eligible() {
  local h="$1"
  m06_ssh_ok "$h" || return 1
  m06_agent_ok "${_M06_VMID[$h]}" || return 1
  m06_wb_exec "$h" >/dev/null 2>&1 <<'EOF'
t="$(sshd -T 2>/dev/null | awk '$1 == "trustedusercakeys" { print $2 }')"
[ -n "$t" ] && [ "$t" != none ] && [ -s "$t" ] && getent passwd secours >/dev/null
EOF
}

# _e38_cles_cert — clés publiques (une par ligne) des certificats d'utilisateur de adm01.
_e38_cles_cert() {
  local c
  for c in "$HOME"/.ssh/*-cert.pub; do
    [[ -f "$c" && -f "${c%-cert.pub}.pub" ]] || continue
    cat "${c%-cert.pub}.pub"
  done
}

_e38_cible() { m06_lire E38 cible; }

_e38_precondition() {
  local -a ok=() cands=(nbx01 ca01 dns02)
  local h
  if [[ -z "$(_e38_cles_cert)" ]]; then
    wb_avert "aucun certificat d'utilisateur (~/.ssh/*-cert.pub) sur adm01 : M06-E20"
    return 1
  fi
  for h in "${cands[@]}"; do
    m06_fermer_ssh "$h"
    if _e38_eligible "$h"; then ok+=("$h"); fi
  done
  if ((${#ok[@]} == 0)); then
    wb_avert "aucun hôte n'accepte les certificats d'utilisateur avec agent QEMU et compte secours (nbx01, ca01, dns02) : lab/bin/check 06 38"
    return 1
  fi
  m06_ecrire E38 cible "${ok[RANDOM % ${#ok[@]}]}"
}

_mE38_une() {
  local n="$1" h rc=0 ca_hote cles
  h="$(_e38_cible)"
  ca_hote="$(awk '$1 == "@cert-authority" { print $3, $4; exit }' "$HOME/.ssh/known_hosts" /etc/ssh/ssh_known_hosts 2>/dev/null)"
  cles="$(_e38_cles_cert)"
  m06_wb_exec "$h" N="$n" CA_HOTE="$ca_hote" CLES="$cles" >/dev/null <<'EOF' || rc=$?
t="$(sshd -T 2>/dev/null | awk '$1 == "trustedusercakeys" { print $2 }')"
case "$N" in
  1)
    [ -n "$CA_HOTE" ] || CA_HOTE="$(ssh-keygen -q -t ed25519 -N '' -f "$WB_DIR/M06-E38.ca-fantome" <<<y >/dev/null 2>&1; cut -d' ' -f1,2 "$WB_DIR/M06-E38.ca-fantome.pub")"
    rm -f "$WB_DIR/M06-E38.ca-fantome" "$WB_DIR/M06-E38.ca-fantome.pub"
    grep -qF "$CA_HOTE" "$t" && exit 10
    sauver "$t"
    printf '%s CA SSH MédiSphère (redéploiement)\n' "$CA_HOTE" >"$t"
    noter_injecte "$t"
    journal "$t : clé de la CA d'hôte à la place de la CA d'utilisateur"
    ;;
  2)
    p="$(sshd -T 2>/dev/null | awk '$1 == "authorizedprincipalsfile" { print $2 }')"
    [ -n "$p" ] && [ "$p" != none ] || exit 10
    p="$(printf '%s' "$p" | sed 's#%u#admin#g; s#%h#/home/admin#g; s#%%#%#g')"
    case "$p" in /*) ;; *) p="/home/admin/$p" ;; esac
    [ -f "$p" ] || exit 10
    grep -q '^admin$' "$p" || exit 10
    sauver "$p"
    # Seul « admin » change : si ton certificat porte aussi un autre principal listé, la variante est sans effet.
    sed -i 's/^admin$/Admin/' "$p"
    noter_injecte "$p"
    journal "$p : principal admin renommé Admin"
    ;;
  3)
    f=/etc/ssh/sshd_config.d/00-anssi.conf
    [ -e "$f" ] && exit 10
    sauver "$f"
    cat >"$f" <<'CONF'
# Durcissement ANSSI (guide « OpenSSH », recopié le 06/10, CHG-7xx en attente)
PubkeyAcceptedAlgorithms ssh-ed25519,ecdsa-sha2-nistp256,rsa-sha2-512,rsa-sha2-256
CONF
    noter_injecte "$f"
    journal "$f : algorithmes de clés publiques sans certificats"
    ;;
  4)
    [ -n "$CLES" ] || exit 10
    # Jamais la clé de bris de glace : si le compte secours l'autorise, on ne révoque rien.
    printf '%s\n' "$CLES" | while read -r ty cle _; do
      grep -qsF "$ty $cle" /home/secours/.ssh/authorized_keys && exit 1
    done || exit 10
    printf '%s\n' "$CLES" >"$WB_DIR/M06-E38.cles-revoquees"
    k="$(sshd -T 2>/dev/null | awk '$1 == "revokedkeys" { print $2 }')"
    if [ -n "$k" ] && [ "$k" != none ]; then
      sauver "$k"
      if [ -s "$k" ]; then ssh-keygen -k -u -f "$k" "$WB_DIR/M06-E38.cles-revoquees" >/dev/null 2>&1 || exit 1
      else ssh-keygen -k -f "$k" "$WB_DIR/M06-E38.cles-revoquees" >/dev/null 2>&1 || exit 1; fi
      noter_injecte "$k"
    else
      k=/etc/ssh/revoked_keys
      f=/etc/ssh/sshd_config.d/00-revocation.conf
      [ -e "$f" ] && exit 10
      sauver "$k"; sauver "$f"
      ssh-keygen -k -f "$k" "$WB_DIR/M06-E38.cles-revoquees" >/dev/null 2>&1 || exit 1
      printf '# Révocation des clés (perte du portable de Lucas, SEC-7xx)\nRevokedKeys %s\n' "$k" >"$f"
      noter_injecte "$k"; noter_injecte "$f"
    fi
    journal "clé(s) de admin@adm01 ajoutée(s) à la KRL $k"
    ;;
esac
sshd -t || exit 1
systemctl reload ssh
EOF
  if ((rc != 0)); then
    _e38_defaire
    return "$rc"
  fi
  m06_fermer_ssh "$h"
  sleep 2
  if m06_ssh_ok "$h"; then
    # La connexion passe encore (autre principal, clé de admin encore autorisée en clair…).
    m06_journal E38 "variante $n sans effet sur $h"
    _e38_defaire
    return 10
  fi
}

# _e38_defaire — par l'agent QEMU ; ne restaure que les fichiers encore dans l'état de la panne.
_e38_defaire() {
  local h
  h="$(_e38_cible)"
  [[ -n "$h" ]] || return 0
  m06_wb_exec_invite "${_M06_VMID[$h]}" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur $h (agent QEMU) : vérifie sshd"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
rm -f "$WB_DIR/M06-E38.cles-revoquees"
if sshd -t; then systemctl reload ssh; else journal "annulation : sshd -t en échec, rechargement non fait"; exit 1; fi
EOF
  m06_fermer_ssh "$h"
}

_e38_injecter() {
  _e38_precondition || return 1
  m06_essayer E38 4 "$1"
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }
panne_E38_v4() { _e38_injecter 4; }

verifier_E38() {
  local h
  h="$(_e38_cible)"
  [[ -n "$h" ]] || return 1
  m06_fermer_ssh "$h"
  # Panne effective ET accès de secours intact (agent QEMU).
  ! m06_ssh_ok "$h" && m06_agent_ok "${_M06_VMID[$h]}"
}

annuler_E38() {
  _e38_defaire
  rm -f "$(m06_etat E38)/cible"
}

resume_E38() {
  echo "SSH vers $(_e38_cible) refusé pour admin (« Permission denied (publickey) ») depuis adm01, alors que les autres hôtes acceptent."
}

symptome_E38() {
  local h
  h="$(_e38_cible)"
  wb_symptome "Ticket INC-3344 — De : Karim Benali" \
    "Impossible d'entrer sur $h depuis le bastion : « admin@${_M06_IP[$h]}: Permission denied (publickey) »." \
    "Mon certificat SSH est frais (je l'ai renouvelé ce matin) et il passe sur les autres hôtes." \
    "Je dois intervenir sur $h avant midi. Ne touche pas à la clé de bris de glace pour" \
    "« dépanner » : Sophie veut savoir ce qui a changé sur $h." \
    "" \
    "Accès de secours : agent QEMU (qm guest exec ${_M06_VMID[$h]}) et compte secours (console)." \
    "Temps cible : 45 min. Contrôle : lab/bin/check 06 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 06 E38 4 "$@"; }
fi
