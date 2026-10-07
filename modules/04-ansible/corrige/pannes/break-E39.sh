# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E39.sh — M04-E39 « Panne : l'inventaire dynamique est vide »
#
# Cible : l'inventaire dynamique inventories/lab/proxmox.yml (plugin community.proxmox.proxmox,
# compte wb-ansible@pve, jeton wb-ansible@pve!ansible). Variantes :
#   1. pve01 : ACL de l'UTILISATEUR wb-ansible@pve retirées sur /pool/lab (« revue des accès ») ;
#      avec un jeton à privilèges séparés, droits effectifs = intersection : l'API répond 200 avec
#      une liste VIDE, sans aucune erreur ;
#   2. pve01 : jeton wb-ansible@pve!ansible expiré (date d'expiration passée) : 401, le plugin
#      échoue, Ansible n'affiche qu'un avertissement et continue avec un inventaire vide ;
#   3. copie de travail : want_facts passe à false dans proxmox.yml (« inventaire 3 fois plus
#      rapide ») : proxmox_tags_parsed (et l'adresse vue par l'agent) n'existent plus, les
#      keyed_groups ne produisent aucun groupe ; les VMs sont là, les groupes socle/role_* vides ;
#   4. copie de travail : proxmox.yml renommé inventories/lab/pve-lab.yml (« convention de
#      nommage ») : le plugin refuse un fichier dont le nom ne finit pas par proxmox.yml/.yaml.
# Sauvegardes : /var/lib/workbook/M04-E39.* sur pve01 ; ~/.local/state/workbook/M04-E39/ sur adm01.
# Annulation : seul ce qui est encore cassé est rétabli (ACL encore absentes, jeton encore expiré,
# fichiers encore tels que posés).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m04-commun.sh
source "$WB_ROOT/modules/04-ansible/corrige/pannes/_m04-commun.sh"

# _e39_nb_socle — nombre d'hôtes du groupe socle (récursivement) vus par l'inventaire dynamique seul.
_e39_nb_socle() {
  local j
  j="$(m04_ansible ansible-inventory -i "$_M04_INV_DYN" --list 2>/dev/null)" || j='{}'
  jq '. as $inv
      | def h($g): ($inv[$g].hosts // []) + (($inv[$g].children // []) | map(h(.)) | add // []);
      h("socle") | unique | length' <<<"$j" 2>/dev/null || echo 0
}

_e39_precondition() {
  m04_prerequis || return 1
  [[ -f "$_M04_SRC/$_M04_INV_DYN" ]] || { wb_avert "$_M04_INV_DYN absent (M04-E13)"; return 1; }
  local nb
  nb="$(_e39_nb_socle)"
  [[ "$nb" =~ ^[1-9] ]] || { wb_avert "l'inventaire dynamique ne voit déjà aucun hôte du groupe socle : lab/bin/check 04 39"; return 1; }
}

_mE39_une() {
  local n="$1" f="$_M04_SRC/$_M04_INV_DYN"
  case "$n" in
    1)
      wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || return 10
lignes="$(pveum acl list --output-format json | perl -MJSON::PP -0777 -ne '
  for (@{decode_json($_)}) {
    print "$_->{roleid} ", ($_->{propagate} // 1), "\n"
      if $_->{path} eq "/pool/lab" && $_->{type} eq "user" && $_->{ugid} eq "wb-ansible\@pve";
  }')"
[ -n "$lignes" ] || { echo "aucune ACL utilisateur wb-ansible@pve sur /pool/lab" >&2; exit 1; }
[ -f "$WB_DIR/M04-E39.acl" ] || printf '%s\n' "$lignes" >"$WB_DIR/M04-E39.acl"
printf '%s\n' "$lignes" | while read -r role _; do
  pveum acl delete /pool/lab --users wb-ansible@pve --roles "$role" || exit 1
done || exit 1
journal "ACL utilisateur wb-ansible@pve retirées de /pool/lab ($(printf '%s' "$lignes" | tr '\n' ' '))"
EOF
      ;;
    2)
      wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || return 10
j="$(pveum user token list wb-ansible@pve --output-format json)" || exit 1
exp="$(printf '%s' "$j" | perl -MJSON::PP -0777 -ne 'for (@{decode_json($_)}) { print $_->{expire} // 0 if $_->{tokenid} eq "ansible" }')"
[ -n "$exp" ] || { echo "jeton wb-ansible@pve!ansible introuvable" >&2; exit 1; }
[ -f "$WB_DIR/M04-E39.expire" ] || printf '%s\n' "$exp" >"$WB_DIR/M04-E39.expire"
pveum user token modify wb-ansible@pve ansible --expire "$(( $(date +%s) - 3600 ))" >/dev/null || exit 1
journal "jeton wb-ansible@pve!ansible : expiration $exp → il y a une heure"
EOF
      ;;
    3)
      grep -Eq '^want_facts:[[:space:]]*(true|True|yes)[[:space:]]*(#.*)?$' "$f" || return 10
      m04_sauver E39 "$f" || return 1
      sed -i -E 's/^want_facts:[[:space:]]*(true|True|yes)[[:space:]]*(#.*)?$/want_facts: false  # Lucas : inventaire 3 fois plus rapide sans les détails de chaque VM/' "$f"
      m04_noter E39 "$f"
      m04_journal E39 "proxmox.yml : want_facts false"
      ;;
    4)
      local neuf="$_M04_SRC/inventories/lab/pve-lab.yml"
      [[ -e "$neuf" ]] && return 10
      m04_sauver E39 "$f" || return 1
      m04_sauver E39 "$neuf" || return 1
      mv "$f" "$neuf"
      m04_noter E39 "$f"
      m04_noter E39 "$neuf"
      m04_journal E39 "proxmox.yml renommé pve-lab.yml"
      ;;
  esac
  if [[ "$(_e39_nb_socle)" != 0 ]]; then
    _e39_defaire
    return 10
  fi
}

_e39_defaire() {
  m04_restaurer E39
  wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01"
if [ -f "$WB_DIR/M04-E39.acl" ]; then
  nb="$(pveum acl list --output-format json | perl -MJSON::PP -0777 -ne '
    my $n = 0;
    for (@{decode_json($_)}) { $n++ if $_->{path} eq "/pool/lab" && $_->{type} eq "user" && $_->{ugid} eq "wb-ansible\@pve" }
    print $n')"
  if [ "${nb:-0}" = 0 ]; then
    ok=1
    while read -r role prop; do
      [ -n "$role" ] || continue
      pveum acl modify /pool/lab --users wb-ansible@pve --roles "$role" --propagate "${prop:-1}" || ok=0
    done <"$WB_DIR/M04-E39.acl"
    [ "$ok" = 1 ] && rm -f "$WB_DIR/M04-E39.acl" && journal "annulation : ACL utilisateur wb-ansible@pve rétablies"
  else
    rm -f "$WB_DIR/M04-E39.acl"
    journal "annulation : ACL utilisateur déjà remise (réparation), laissée telle quelle"
  fi
fi
if [ -f "$WB_DIR/M04-E39.expire" ]; then
  actuel="$(pveum user token list wb-ansible@pve --output-format json | perl -MJSON::PP -0777 -ne '
    for (@{decode_json($_)}) { print $_->{expire} // 0 if $_->{tokenid} eq "ansible" }')"
  if [ -n "$actuel" ] && [ "$actuel" != 0 ] && [ "$actuel" -le "$(date +%s)" ]; then
    pveum user token modify wb-ansible@pve ansible --expire "$(cat "$WB_DIR/M04-E39.expire")" \
      && rm -f "$WB_DIR/M04-E39.expire" && journal "annulation : expiration du jeton rétablie"
  else
    rm -f "$WB_DIR/M04-E39.expire"
    journal "annulation : jeton déjà prolongé ou remplacé (réparation), laissé tel quel"
  fi
fi
exit 0
EOF
}

_e39_injecter() {
  _e39_precondition || return 1
  m04_instantane E39
  m04_essayer E39 4 "$1"
}

panne_E39_v1() { _e39_injecter 1; }
panne_E39_v2() { _e39_injecter 2; }
panne_E39_v3() { _e39_injecter 3; }
panne_E39_v4() { _e39_injecter 4; }

verifier_E39() { [[ "$(_e39_nb_socle)" == 0 ]]; }

annuler_E39() { _e39_defaire; }

resume_E39() {
  echo "L'inventaire dynamique Proxmox ne renvoie plus aucun hôte du socle (groupes vides), alors que les VMs tournent."
}

symptome_E39() {
  wb_symptome "Ticket INC-3145 — De : Karim Benali" \
    "Le contrôle de dérive de cette nuit n'a rien contrôlé : pas un seul hôte vérifié dans son" \
    "rapport. Et « ansible-inventory -i inventories/lab/proxmox.yml --graph » ne me donne plus" \
    "aucun hôte dans socle ni dans les groupes role_*, alors que toutes les VMs tournent dans" \
    "Proxmox. Un inventaire qui peut se vider sans faire ÉCHOUER franchement la vérification," \
    "c'est une supervision aveugle : trouve la cause, et dis-moi comment on s'assure qu'un" \
    "inventaire vide ou illisible arrête tout." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 04 39"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 04 E39 4 "$@"; }
fi
