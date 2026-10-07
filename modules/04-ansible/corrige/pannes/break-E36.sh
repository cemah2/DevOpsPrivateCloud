# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # commandes entre apostrophes évaluées sur l'hôte distant
# break-E36.sh — M04-E36 « Panne : le playbook passe mais rien ne change »
#
# Le ticket demande l'avertissement légal avant authentification (Banner) par le rôle ssh_durci, sur
# dns01 d'abord. Variantes :
#   1. copie de travail : copie figée du rôle dans playbooks/roles/ssh_durci (« Lucas a testé
#      une version du rôle à côté du playbook ») — les rôles voisins du playbook passent AVANT
#      roles_path : les modifications de roles/ssh_durci sont ignorées ;
#   2. copie de travail : ansible.cfg reçoit [tags] run = pare_feu (« tests de Lucas sur gw01 ») —
#      seules les tâches étiquetées pare_feu s'exécutent, le reste est sauté sans un mot ;
#   3. dns01 : /etc/ssh/sshd_config.d/00-infoger.conf (« paramètres hérités d'InfoGér ») fixe
#      Banner none ; sshd garde la PREMIÈRE valeur lue, et ce fichier est lu avant celui du
#      rôle (01-ssh-durci.conf) : le fichier du rôle change, la configuration effective non ;
#   4. pve01 + copie de travail : VM 2040 « dns01-essai » (clone lié de l'image dorée current,
#      VNet vsandbox, étiquette env-m04) et inventories/lab/host_vars/dns01/zz-essai.yml qui
#      redirige ansible_host de dns01 vers elle : le playbook modifie… la copie.
# Sauvegardes : ~/.local/state/workbook/M04-E36/ (copie de travail), /var/lib/workbook/M04-E36.*
# sur dns01 (v3) et pve01 (v4 : VMID créé). Annulation : ce qui a été modifié depuis l'injection
# (réparation) est laissé ; la VM 2040 n'est détruite que si c'est bien celle de la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m04-commun.sh
source "$WB_ROOT/modules/04-ansible/corrige/pannes/_m04-commun.sh"

_E36_VMID=2040
_E36_NOM=dns01-essai

# Le rôle ssh_durci est-il appelé par son nom court depuis un playbook de playbooks/ ?
_e36_role_appele() {
  grep -rEqs '(^|[^.[:alnum:]_])ssh_durci([^[:alnum:]_]|$)' "$_M04_SRC/playbooks" --include='*.yml' --include='*.yaml'
}

_e36_ip_essai() {
  local d
  d="$(m04_etat E36)"
  [[ -s "$d/ip-essai" ]] && cat "$d/ip-essai"
}

_mE36_une() {
  local n="$1" d ip
  d="$(m04_etat E36)"
  case "$n" in
    1)
      [[ -d "$_M04_SRC/roles/ssh_durci" ]] || return 10
      [[ ! -e "$_M04_SRC/playbooks/roles/ssh_durci" ]] || return 10
      _e36_role_appele || return 10
      if [[ -d "$_M04_SRC/playbooks/roles" ]]; then
        m04_sauver E36 "$_M04_SRC/playbooks/roles/ssh_durci" || return 1
        cp -a "$_M04_SRC/roles/ssh_durci" "$_M04_SRC/playbooks/roles/ssh_durci" || return 1
        m04_noter E36 "$_M04_SRC/playbooks/roles/ssh_durci"
      else
        m04_sauver E36 "$_M04_SRC/playbooks/roles" || return 1
        mkdir -p "$_M04_SRC/playbooks/roles"
        cp -a "$_M04_SRC/roles/ssh_durci" "$_M04_SRC/playbooks/roles/ssh_durci" || return 1
        m04_noter E36 "$_M04_SRC/playbooks/roles"
      fi
      m04_journal E36 "copie figée de roles/ssh_durci dans playbooks/roles/ssh_durci"
      ;;
    2)
      grep -Eq '^[[:space:]]*\[tags\]' "$_M04_SRC/ansible.cfg" && return 10
      m04_sauver E36 "$_M04_SRC/ansible.cfg" || return 1
      m04_ini_set "$_M04_SRC/ansible.cfg" tags run pare_feu \
        "Lucas : tests du rôle pare_feu sur gw01, ne lancer que ses tâches (provisoire)" || return 1
      m04_noter E36 "$_M04_SRC/ansible.cfg"
      m04_journal E36 "ansible.cfg : [tags] run = pare_feu"
      ;;
    3)
      local rc=0
      m04_wb_exec dns01 >/dev/null <<'EOF' || rc=$?
d=/etc/ssh/sshd_config.d
f="$d/00-infoger.conf"
grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config || exit 10
[ -e "$f" ] && exit 10
# Le fichier doit être lu le premier : aucun fichier existant ne doit le précéder.
premier="$(LC_ALL=C ls "$d" 2>/dev/null | grep '\.conf$' | LC_ALL=C sort | head -n 1)"
if [ -n "$premier" ] && [ "$(printf '%s\n%s\n' "$premier" 00-infoger.conf | LC_ALL=C sort | head -n 1)" != 00-infoger.conf ]; then
  exit 10
fi
sauver "$f"
cat >"$f" <<'CONF'
# Paramètres hérités de l'infogérance (contrat InfoGér, INF-2291).
# Ne pas supprimer sans l'accord du prestataire.
Banner none
CONF
chmod 644 "$f"
noter_injecte "$f"
if ! sshd -t; then restaurer_fichiers; exit 1; fi
systemctl reload ssh
journal "$f posé (Banner none, lu avant les autres fichiers)"
EOF
      return "$rc"
      ;;
    4)
      local cle rc=0
      cle="$(cat "$HOME/.ssh/id_ed25519.pub" 2>/dev/null)" || true
      [[ -n "$cle" ]] || { wb_avert "clé publique ~/.ssh/id_ed25519.pub introuvable"; return 1; }
      ip="$(wb_exec "$WB_PVE_HOST" VMID="$_E36_VMID" NOM="$_E36_NOM" CLE="$cle" <<'EOF'
qm status "$VMID" >/dev/null 2>&1 && { echo "VMID $VMID déjà utilisé : variante inapplicable" >&2; exit 10; }
tpl="$(pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -0777 -ne '
  for (@{decode_json($_)}) {
    my %t = map { $_ => 1 } split /[;,]/, ($_->{tags} // "");
    print "$_->{vmid}\n" if $_->{template} && $t{gold} && $t{debian13} && $t{current};
  }' | head -n 1)"
[ -n "$tpl" ] || { echo "aucune image dorée gold+debian13+current" >&2; exit 1; }
printf '%s\n' "$VMID" >"$WB_DIR/M04-E36.vm"
k="$(mktemp)"; printf '%s\n' "$CLE" >"$k"
qm clone "$tpl" "$VMID" --name "$NOM" --pool lab >/dev/null || { rm -f "$k" "$WB_DIR/M04-E36.vm"; exit 1; }
qm set "$VMID" --tags env-m04 --ipconfig0 ip=dhcp --ciuser admin --sshkeys "$k" --memory 1024 \
  --description "Copie de dns01 pour tester le rôle ssh_durci (Lucas)" >/dev/null
rm -f "$k"
qm start "$VMID" >/dev/null || exit 1
journal "VM $VMID ($NOM) clonée depuis $tpl et démarrée"
for _ in $(seq 1 80); do
  ip="$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | perl -MJSON::PP -0777 -ne '
    my $d = eval { decode_json($_) } or exit;
    $d = $d->{result} if ref $d eq "HASH";
    for my $i (@$d) { for my $a (@{ $i->{"ip-addresses"} // [] }) {
      if ($a->{"ip-address"} =~ /^10\.10\.99\./) { print $a->{"ip-address"}; exit } } }')"
  [ -n "$ip" ] && { printf '%s\n' "$ip"; exit 0; }
  sleep 3
done
echo "pas d'adresse DHCP pour la VM $VMID" >&2
exit 1
EOF
      )" || rc=$?
      if ((rc != 0)); then
        _e36_detruire_vm
        return "$rc"
      fi
      printf '%s\n' "$ip" >"$d/ip-essai"
      local i pret=0
      for i in $(seq 1 40); do
        if ssh -o ControlPath=none -o BatchMode=yes -o ConnectTimeout=3 "admin@$ip" true >/dev/null 2>&1; then
          pret=1
          break
        fi
        sleep 3
      done
      ((pret)) || { wb_avert "la VM $_E36_VMID ne répond pas en SSH ($i essais)"; _e36_detruire_vm; return 1; }
      m04_poser E36 "$_M04_SRC/inventories/lab/host_vars/dns01/zz-essai.yml" <<YML || return 1
---
# Lucas : essai du rôle ssh_durci sur une copie avant de toucher au vrai dns01.
ansible_host: $ip
YML
      m04_journal E36 "host_vars/dns01/zz-essai.yml : ansible_host $ip (VM $_E36_VMID)"
      ;;
  esac
}

_e36_detruire_vm() {
  wb_exec "$WB_PVE_HOST" VMID="$_E36_VMID" NOM="$_E36_NOM" >/dev/null <<'EOF' || wb_avert "VM $_E36_VMID : destruction à vérifier sur pve01"
[ -f "$WB_DIR/M04-E36.vm" ] || exit 0
if qm config "$VMID" 2>/dev/null | grep -q "^name: $NOM\$"; then
  qm stop "$VMID" --skiplock 1 >/dev/null 2>&1 || true
  qm destroy "$VMID" --purge 1 >/dev/null && journal "annulation : VM $VMID ($NOM) détruite"
else
  journal "annulation : VM $VMID absente ou renommée, rien à détruire"
fi
rm -f "$WB_DIR/M04-E36.vm"
EOF
  rm -f "$(m04_etat E36)/ip-essai"
}

_e36_injecter() {
  m04_prerequis || return 1
  m04_instantane E36
  m04_essayer E36 4 "$1"
}

panne_E36_v1() { _e36_injecter 1; }
panne_E36_v2() { _e36_injecter 2; }
panne_E36_v3() { _e36_injecter 3; }
panne_E36_v4() { _e36_injecter 4; }

verifier_E36() {
  local ip
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) [[ -d "$_M04_SRC/playbooks/roles/ssh_durci" ]] && _e36_role_appele ;;
    2) [[ "$(m04_ansible ansible-config dump --only-changed 2>/dev/null)" == *TAGS_RUN* ]] ;;
    3) remote dns01 'f=$(grep -lEis "^[[:space:]]*Banner" $(LC_ALL=C ls -d /etc/ssh/sshd_config.d/*.conf | LC_ALL=C sort) | head -n 1); [ "$f" = /etc/ssh/sshd_config.d/00-infoger.conf ]' ;;
    4)
      ip="$(_e36_ip_essai)"
      [[ -n "$ip" ]] \
        && m04_ansible ansible-inventory --host dns01 2>/dev/null | jq -e --arg ip "$ip" '.ansible_host == $ip' >/dev/null \
        && [[ "$(ssh -o ControlPath=none -o BatchMode=yes "admin@$ip" hostname 2>/dev/null)" == "$_E36_NOM" ]]
      ;;
    *) return 1 ;;
  esac
}

annuler_E36() {
  m04_restaurer E36
  m04_wb_exec dns01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur dns01"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
if sshd -t; then systemctl reload ssh; else echo "sshd -t échoue sur dns01 : vérifie /etc/ssh/sshd_config.d" >&2; fi
journal "annulation : sshd_config.d rétabli (sauf réparation)"
EOF
  _e36_detruire_vm
}

resume_E36() {
  echo "Le rôle ssh_durci appliqué sur dns01 se termine sans erreur, mais la bannière légale SSH demandée par Sophie ne s'affiche pas."
}

symptome_E36() {
  wb_symptome "Ticket SEC-580 — De : Sophie Laurent" \
    "Exigence de l'audit HDS : un avertissement légal doit s'afficher AVANT l'authentification SSH" \
    "(« Accès réservé aux personnes autorisées par MédiSphère. Toute connexion est journalisée. »)." \
    "Ajoute-le au rôle ssh_durci lui-même (règle pour toutes les machines, pas un réglage" \
    "d'inventaire) et applique-le sur dns01 d'abord, comme d'habitude." \
    "(Note de Lucas, qui a essayé hier : « le playbook passe, tout est vert, mais sur dns01" \
    "« sudo sshd -T | grep -i banner » répond toujours none. Je n'y comprends rien. »)" \
    "Je veux la bannière effective sur dns01, et l'explication." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 04 36"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 04 E36 4 "$@"; }
fi
