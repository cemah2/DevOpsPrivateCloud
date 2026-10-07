# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E42.sh — M04-E42 « Panne : Molecule échoue avant même de tester »
#
# Tout se passe sur pve01 (les scénarios Molecule de M04-E24 clonent l'image dorée Debian 13
# étiquetée current dans les VMID 2045-2049, VNet vsandbox, adresse lue par l'agent QEMU, avec le
# jeton wb-ansible@pve!ansible). Variantes :
#   1. étiquette current retirée de l'image dorée Debian 13 (« rotation des images » interrompue) :
#      plus aucun template gold+debian13+current ;
#   2. cinq VMs orphelines « instance » (2045 à 2049, pool lab, étiquettes molecule et env-m04,
#      sans disque, arrêtées) laissées par des tests interrompus : plus de VMID libre, ou un clone
#      qui « existe déjà » et ne démarre pas ;
#   3. privilège VM.Clone retiré du rôle WBAnsible (« revue des droits ») : le clonage est refusé ;
#   4. agent QEMU désactivé (agent: 0) sur le template current : le clone démarre, mais son
#      adresse n'est jamais connue, la création expire.
# Sauvegardes : /var/lib/workbook/M04-E42.* sur pve01 (étiquettes, privilèges, réglage agent,
# liste des VMs créées). Annulation : seul ce qui est encore cassé est rétabli ; seules les VMs
# créées par la panne et encore intactes (même nom, sans disque) sont détruites.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m04-commun.sh
source "$WB_ROOT/modules/04-ansible/corrige/pannes/_m04-commun.sh"

# Fonctions communes envoyées à pve01 avant chaque script.
read -r -d '' _E42_PVE <<'PVE' || true
tpl_current() {
  pvesh get /cluster/resources --type vm --output-format json | perl -MJSON::PP -0777 -ne '
    for (@{decode_json($_)}) {
      my %t = map { $_ => 1 } split /[;,]/, ($_->{tags} // "");
      print "$_->{vmid}\n" if $_->{template} && $t{gold} && $t{debian13} && $t{current};
    }'
}
privs_wbansible() {
  pveum role list --output-format json | perl -MJSON::PP -0777 -ne '
    for (@{decode_json($_)}) { print $_->{privs} // "" if $_->{roleid} eq "WBAnsible" }'
}
PVE

_e42_pve() {
  local h="$1"
  shift
  { printf '%s\n' "$_E42_PVE"; cat; } | wb_exec "$h" "$@"
}

_e42_precondition() {
  _e42_pve "$WB_PVE_HOST" >/dev/null <<'EOF'
n="$(tpl_current | grep -c .)"
[ "$n" = 1 ] || { echo "il faut exactement une image dorée gold+debian13+current (trouvées : $n)" >&2; exit 1; }
privs_wbansible | tr ',; ' '\n\n\n' | grep -qx 'VM.Clone' || { echo "le rôle WBAnsible n'a pas VM.Clone" >&2; exit 1; }
for i in 2045 2046 2047 2048 2049; do
  qm status "$i" >/dev/null 2>&1 && { echo "VMID $i occupé : détruis d'abord les instances Molecule" >&2; exit 1; }
done
exit 0
EOF
}

_mE42_une() {
  _e42_pve "$WB_PVE_HOST" N="$1" >/dev/null <<'EOF'
tpl="$(tpl_current | head -n 1)"
case "$N" in
  1)
    tags="$(qm config "$tpl" | sed -n 's/^tags: //p')"
    [ -f "$WB_DIR/M04-E42.tags" ] || printf '%s\t%s\n' "$tpl" "$tags" >"$WB_DIR/M04-E42.tags"
    neuf="$(printf '%s' "$tags" | tr ',;' '\n\n' | grep -vx current | paste -sd ';')"
    qm set "$tpl" --tags "$neuf" >/dev/null || exit 1
    journal "étiquette current retirée du template $tpl ($tags → $neuf)"
    ;;
  2)
    : >"$WB_DIR/M04-E42.vms"
    for i in 2045 2046 2047 2048 2049; do
      qm create "$i" --name instance --pool lab --memory 512 --tags 'env-m04;molecule' \
        --net0 virtio,bridge=vsandbox >/dev/null || exit 1
      printf '%s\n' "$i" >>"$WB_DIR/M04-E42.vms"
    done
    journal "VMs orphelines 2045-2049 (instance, sans disque) créées"
    ;;
  3)
    p="$(privs_wbansible)"
    [ -f "$WB_DIR/M04-E42.privs" ] || printf '%s\n' "$p" >"$WB_DIR/M04-E42.privs"
    neuf="$(printf '%s' "$p" | tr ',; ' '\n\n\n' | grep -v '^$' | grep -vx 'VM.Clone' | paste -sd ',')"
    pveum role modify WBAnsible --privs "$neuf" || exit 1
    journal "VM.Clone retiré du rôle WBAnsible"
    ;;
  4)
    a="$(qm config "$tpl" | sed -n 's/^agent: //p')"
    [ -f "$WB_DIR/M04-E42.agent" ] || printf '%s\t%s\n' "$tpl" "${a:-ABSENT}" >"$WB_DIR/M04-E42.agent"
    qm set "$tpl" --agent 0 >/dev/null || exit 1
    journal "agent QEMU désactivé sur le template $tpl (ancien réglage : ${a:-absent})"
    ;;
esac
exit 0
EOF
}

panne_E42_v1() { _e42_precondition && _mE42_une 1; }
panne_E42_v2() { _e42_precondition && _mE42_une 2; }
panne_E42_v3() { _e42_precondition && _mE42_une 3; }
panne_E42_v4() { _e42_precondition && _mE42_une 4; }

verifier_E42() {
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  _e42_pve "$WB_PVE_HOST" N="${WB_VAR:-0}" >/dev/null <<'EOF'
case "$N" in
  1) [ -z "$(tpl_current)" ] ;;
  2) for i in 2045 2046 2047 2048 2049; do qm status "$i" >/dev/null 2>&1 || exit 1; done ;;
  3) ! privs_wbansible | tr ',; ' '\n\n\n' | grep -qx 'VM.Clone' ;;
  4) t="$(cut -f1 "$WB_DIR/M04-E42.agent")"; qm config "$t" | grep -Eq '^agent: (0|enabled=0)' ;;
  *) exit 1 ;;
esac
EOF
}

annuler_E42() {
  _e42_pve "$WB_PVE_HOST" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01"
if [ -f "$WB_DIR/M04-E42.tags" ]; then
  IFS="$(printf '\t')" read -r t tags <"$WB_DIR/M04-E42.tags"
  if [ -z "$(tpl_current)" ] && qm config "$t" >/dev/null 2>&1; then
    qm set "$t" --tags "$tags" >/dev/null && journal "annulation : étiquettes du template $t rétablies"
  else
    journal "annulation : une image current existe déjà (réparation), étiquettes laissées"
  fi
  rm -f "$WB_DIR/M04-E42.tags"
fi
if [ -f "$WB_DIR/M04-E42.vms" ]; then
  while read -r i; do
    [ -n "$i" ] || continue
    c="$(qm config "$i" 2>/dev/null)" || continue
    if printf '%s\n' "$c" | grep -q '^name: instance$' && ! printf '%s\n' "$c" | grep -Eq '^(scsi|virtio|sata|ide|efidisk)[0-9]+:'; then
      qm stop "$i" >/dev/null 2>&1 || true
      qm destroy "$i" --purge 1 >/dev/null && journal "annulation : VM orpheline $i détruite"
    else
      journal "annulation : VM $i modifiée depuis l'injection, laissée telle quelle"
    fi
  done <"$WB_DIR/M04-E42.vms"
  rm -f "$WB_DIR/M04-E42.vms"
fi
if [ -f "$WB_DIR/M04-E42.privs" ]; then
  if ! privs_wbansible | tr ',; ' '\n\n\n' | grep -qx 'VM.Clone'; then
    pveum role modify WBAnsible --privs "$(cat "$WB_DIR/M04-E42.privs")" && journal "annulation : privilèges de WBAnsible rétablis"
  else
    journal "annulation : VM.Clone déjà rendu (réparation), rôle laissé tel quel"
  fi
  rm -f "$WB_DIR/M04-E42.privs"
fi
if [ -f "$WB_DIR/M04-E42.agent" ]; then
  IFS="$(printf '\t')" read -r t a <"$WB_DIR/M04-E42.agent"
  if qm config "$t" 2>/dev/null | grep -Eq '^agent: (0|enabled=0)'; then
    if [ "$a" = ABSENT ]; then qm set "$t" --delete agent >/dev/null; else qm set "$t" --agent "$a" >/dev/null; fi
    journal "annulation : réglage de l'agent du template $t rétabli"
  else
    journal "annulation : agent déjà réactivé (réparation), laissé tel quel"
  fi
  rm -f "$WB_DIR/M04-E42.agent"
fi
exit 0
EOF
}

resume_E42() {
  echo "Molecule échoue sur tous les rôles dès l'étape de création des instances, avant tout test ; la CI est rouge."
}

symptome_E42() {
  wb_symptome "Ticket DEV-582 — De : Julien Petit" \
    "Toutes les MR de plateforme/ansible sont bloquées : le job molecule échoue, et pas sur mes" \
    "tests, il n'arrive même pas à les lancer. En local, « molecule test » sur le rôle base fait" \
    "pareil : il s'arrête pendant la création des instances. Personne n'a touché à molecule/" \
    "depuis des semaines. Il faut débloquer la CI, et que ça ne se reproduise pas sans prévenir." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 04 42"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 04 E42 4 "$@"; }
fi
