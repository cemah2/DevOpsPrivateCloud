# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M05-E40 « Panne : l'état ne correspond plus à la réalité »
#
# Le ticket demande une VM d'environnement de plus dans envs/lab-m05 (VMID libre, préférence 2058).
# Le plan ou l'apply de envs/lab-m05 ne fait pas ce qu'on attend. Variantes :
#   1. état distant envs : une VM d'environnement est retirée de l'état (« tofu state rm », copie de
#      l'objet faite avant) : le plan veut la créer alors qu'elle existe ;
#   2. pve01 : une VM d'environnement est modifiée hors IaC (mémoire +1 Go, étiquette essai-perf,
#      description) « pour les tests de charge » : le plan veut défaire la modification ;
#   3. pve01 : une VM non gérée (clone lié de l'image current, arrêtée, étiquette env-m05, pool lab)
#      occupe déjà le VMID demandé par le ticket : l'apply échoue, la VM n'est dans aucun état.
# Sauvegardes : /var/lib/workbook/M05-E40/ sur adm01 (objet d'état et versions, v1),
# ~/.local/state/workbook/M05-E40/ (valeurs d'origine, v2). Annulation : v1 n'est restaurée que si
# la version courante de l'état est encore celle de la panne ; v2 n'est défaite que si l'état
# OpenTofu n'a pas adopté les nouvelles valeurs ; la VM de v3 n'est détruite que si elle porte
# encore son nom et n'a pas été importée dans un état.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m05-commun.sh
source "$WB_ROOT/modules/05-iac/corrige/pannes/_m05-commun.sh"

_E40_NOM_V3=m05-charge-manuel

# _e40_vm_env JSON — « adresse vmid » de la première VM de l'état envs dans 2050-2059.
_e40_vm_env() { m05_vms_etat "$1" | awk '$2 >= 2050 && $2 <= 2059 { print $1, $2; exit }'; }

# _e40_memoire_etat VMID — mémoire « dedicated » enregistrée dans l'état envs pour cette VM.
_e40_memoire_etat() {
  m05_show_json "$_M05_ENVS" | jq -r --argjson id "$1" '
    def res: (.resources // []) + ((.child_modules // []) | map(res) | add // []);
    (.values.root_module // {}) | res | .[]
    | select(.type == "proxmox_virtual_environment_vm" and .values.vm_id == $id)
    | (.values.memory // [])[0].dedicated // empty' 2>/dev/null | head -n 1
}

_m05E40_une() {
  local n="$1" j adr id vmid rc=0 mem tpl
  j="$(m05_show_json "$_M05_ENVS")"
  read -r adr id < <(_e40_vm_env "$j") || true
  vmid="$(m05_lire E40 vmid)"
  case "$n" in
    1)
      [[ -n "$adr" ]] || return 10
      m05_s3_sauver E40 "$_M05_CLE_ENVS" || return 1
      m05_tofu "$_M05_ENVS" state rm -lock-timeout=60s "$adr" >/dev/null 2>&1 || { wb_avert "tofu state rm a échoué"; return 1; }
      m05_s3_noter E40 "$_M05_CLE_ENVS"
      m05_ecrire E40 cible "$adr $id"
      m05_journal E40 "état envs : $adr (VM $id) retiré de l'état"
      ;;
    2)
      [[ -n "$id" ]] || return 10
      mem="$(remote "$WB_PVE_HOST" "qm config $id" 2>/dev/null | sed -n 's/^memory: //p')"
      [[ "$mem" =~ ^[0-9]+$ ]] || return 10
      wb_exec "$WB_PVE_HOST" VMID="$id" MEM="$mem" >/dev/null <<'EOF' || rc=$?
c="$(qm config "$VMID")" || exit 1
tags="$(printf '%s\n' "$c" | sed -n 's/^tags: //p')"
printf '%s\n' "$MEM" > "$WB_DIR/M05-E40.memoire"
printf '%s\n' "$tags" > "$WB_DIR/M05-E40.tags"
printf '%s\n' "$c" | sed -n 's/^description: //p' > "$WB_DIR/M05-E40.description"
neuf=$((MEM + 1024))
qm set "$VMID" --memory "$neuf" --tags "${tags:+$tags;}essai-perf" \
  --description "Mémoire augmentée pour les tests de charge MédiAgenda (Julien, à la main)" >/dev/null || exit 1
printf '%s\n' "$neuf" > "$WB_DIR/M05-E40.memoire-injectee"
journal "VM $VMID : memory $MEM -> $neuf, étiquette essai-perf, description (hors IaC)"
EOF
      ((rc == 0)) || return "$rc"
      m05_ecrire E40 cible "- $id"
      m05_ecrire E40 memoire-etat "$(_e40_memoire_etat "$id")"
      ;;
    3)
      tpl="$(m05_tpl_current | head -n 1)"
      [[ -n "$tpl" ]] || return 10
      wb_exec "$WB_PVE_HOST" VMID="$vmid" TPL="$tpl" NOM="$_E40_NOM_V3" >/dev/null <<'EOF' || rc=$?
qm status "$VMID" >/dev/null 2>&1 && exit 10
qm clone "$TPL" "$VMID" --name "$NOM" --pool lab >/dev/null || exit 1
printf '%s\n' "$VMID" > "$WB_DIR/M05-E40.vm"
qm set "$VMID" --tags env-m05 --memory 1024 --onboot 0 \
  --description "VM de test de charge créée à la main par Julien (provisoire)" >/dev/null || exit 1
journal "VM $VMID ($NOM) clonée depuis $TPL, non gérée par OpenTofu"
EOF
      ((rc == 0)) || { _e40_detruire_v3; return "$rc"; }
      m05_ecrire E40 cible "- $vmid"
      ;;
  esac
}

_e40_injecter() {
  local vmid
  m05_prerequis envs || return 1
  if [[ -z "$(_e40_vm_env "$(m05_show_json "$_M05_ENVS")")" ]]; then
    wb_avert "l'état de envs/lab-m05 ne contient aucune VM 2050-2059 : applique d'abord l'environnement (M05-E15)"
    return 1
  fi
  vmid="$(m05_vmid_libre 2058)" || { wb_avert "aucun VMID libre dans 2050-2059"; return 1; }
  m05_ecrire E40 vmid "$vmid"
  m05_essayer E40 3 "$1"
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }

verifier_E40() {
  local adr id
  read -r adr id < <(m05_lire E40 cible) || return 1
  # shellcheck disable=SC2031  # WB_VAR est fixé par wb_main (ou par l'astreinte) avant l'appel
  case "${WB_VAR:-}" in
    1) ! m05_vms_etat "$(m05_show_json "$_M05_ENVS")" | awk -v a="$adr" '$1 == a { f = 1 } END { exit !f }' \
      && remote "$WB_PVE_HOST" "qm status $id" >/dev/null 2>&1 ;;
    2) remote "$WB_PVE_HOST" "qm config $id" 2>/dev/null | grep -q '^tags:.*essai-perf' ;;
    3) remote "$WB_PVE_HOST" "qm config $id" 2>/dev/null | grep -q "^name: $_E40_NOM_V3\$" ;;
    *) return 1 ;;
  esac
}

_e40_detruire_v3() {
  local vmid geree=0
  vmid="$(m05_lire E40 vmid)"
  [[ -n "$vmid" ]] || return 0
  if m05_vms_etat "$(m05_show_json "$_M05_ENVS")" | awk -v i="$vmid" '$2 == i { f = 1 } END { exit !f }'; then
    geree=1
  fi
  wb_exec "$WB_PVE_HOST" VMID="$vmid" NOM="$_E40_NOM_V3" GEREE="$geree" >/dev/null <<'EOF' || wb_avert "VM $vmid : destruction à vérifier sur pve01"
[ -f "$WB_DIR/M05-E40.vm" ] || exit 0
if [ "$GEREE" = 1 ]; then
  journal "annulation : VM $VMID importée dans l'état OpenTofu, laissée en place"
elif qm config "$VMID" 2>/dev/null | grep -q "^name: $NOM\$"; then
  qm stop "$VMID" --skiplock 1 >/dev/null 2>&1 || true
  qm destroy "$VMID" --purge 1 >/dev/null && journal "annulation : VM $VMID ($NOM) détruite"
else
  journal "annulation : VM $VMID absente ou renommée, rien à détruire"
fi
rm -f "$WB_DIR/M05-E40.vm"
EOF
}

_e40_defaire_v2() {
  local id mem_etat_avant mem_etat
  read -r _ id < <(m05_lire E40 cible) || return 0
  mem_etat_avant="$(m05_lire E40 memoire-etat)"
  [[ -n "$id" && -n "$mem_etat_avant" ]] || return 0
  mem_etat="$(_e40_memoire_etat "$id")"
  if [[ -n "$mem_etat" && "$mem_etat" != "$mem_etat_avant" ]]; then
    m05_journal E40 "annulation : l'état OpenTofu a adopté la nouvelle mémoire de $id, VM laissée telle quelle"
    wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || true
rm -f "$WB_DIR"/M05-E40.memoire* "$WB_DIR/M05-E40.tags" "$WB_DIR/M05-E40.description"
EOF
    return 0
  fi
  wb_exec "$WB_PVE_HOST" VMID="$id" >/dev/null <<'EOF' || wb_avert "pve01 : VM $id à remettre à la main (mémoire, étiquettes, description)"
[ -f "$WB_DIR/M05-E40.memoire" ] || exit 0
c="$(qm config "$VMID")" || exit 0
if [ "$(printf '%s\n' "$c" | sed -n 's/^memory: //p')" = "$(cat "$WB_DIR/M05-E40.memoire-injectee")" ]; then
  qm set "$VMID" --memory "$(cat "$WB_DIR/M05-E40.memoire")" >/dev/null && journal "annulation : mémoire de $VMID rétablie"
fi
if printf '%s\n' "$c" | grep -q '^tags:.*essai-perf'; then
  t="$(cat "$WB_DIR/M05-E40.tags")"
  if [ -n "$t" ]; then qm set "$VMID" --tags "$t" >/dev/null; else qm set "$VMID" --delete tags >/dev/null; fi
  journal "annulation : étiquettes de $VMID rétablies"
fi
if printf '%s\n' "$c" | grep -q '^description: .*tests de charge MédiAgenda'; then
  d="$(cat "$WB_DIR/M05-E40.description")"
  if [ -n "$d" ]; then qm set "$VMID" --description "$d" >/dev/null; else qm set "$VMID" --delete description >/dev/null; fi
fi
rm -f "$WB_DIR"/M05-E40.memoire* "$WB_DIR/M05-E40.tags" "$WB_DIR/M05-E40.description"
EOF
}

annuler_E40() {
  m05_s3_restaurer E40 || true
  _e40_defaire_v2 || true
  _e40_detruire_v3 || true
  rm -f -- "$(m05_etat E40)/cible" "$(m05_etat E40)/memoire-etat" "$(m05_etat E40)/variante"
}

resume_E40() {
  echo "Ajouter la VM $(m05_lire E40 vmid) à envs/lab-m05 : le plan ou l'apply annonce des choses que personne n'a demandées, ou échoue."
}

symptome_E40() {
  local vmid
  vmid="$(m05_lire E40 vmid)"
  wb_symptome "Ticket DEV-682 — De : Julien Petit" \
    "Encore une VM pour les tests de charge, s'il te plaît : dans envs/lab-m05, VMID $vmid," \
    "construite comme les autres. Lucas a préparé la modification mais n'ose pas appliquer :" \
    "« le plan annonce des choses que je n'ai pas demandées », et chez lui l'apply a fini en erreur." \
    "Je ne veux rien perdre de ce qui tourne (une VM d'environnement sert à mes tests en ce moment)." \
    "Remets OpenTofu et Proxmox d'accord, puis ajoute ma VM." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 05 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 05 E40 3 "$@"; }
fi
