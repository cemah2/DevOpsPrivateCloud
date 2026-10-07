# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M05-E38 « Panne : l'apply échoue sur un refus de droits »
#
# Le ticket demande une VM d'environnement de plus (VMID libre de 2050-2059, préférence 2057) et
# 512 Mo de mémoire en plus pour les VMs de envs/lab-m05. Le plan passe (lecture seule), l'apply
# échoue sur « Permission check failed ». Variantes (identité : le jeton wb-tofu@pve!tofu s'il a
# des droits séparés, sinon l'utilisateur wb-tofu@pve) :
#   1. le privilège VM.Config.Memory est retiré du rôle personnalisé qui le donnait : la création
#      peut réussir, la modification de mémoire échoue (apply partiel) ;
#   2. l'ACL qui donne SDN.Use sur le VNet vsandbox (ou sa zone) est supprimée : la nouvelle VM ne
#      peut pas être branchée ;
#   3. l'ACL qui donne Datastore.AllocateSpace sur local-nvme (ou /storage) est supprimée : le
#      clonage échoue ;
#   4. le privilège VM.PowerMgmt est retiré du rôle : la VM est créée, son démarrage échoue — la
#      ressource est marquée « tainted » dans l'état.
# Sauvegardes : ~/.local/state/workbook/M05-E38/ (rôles et ACL d'origine) et journal sur pve01.
# Annulation : un privilège n'est rajouté que s'il manque encore, une ACL n'est recréée que si elle
# manque encore (une réparation de l'apprenant n'est jamais écrasée). Rien n'est supprimé d'autre.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m05-commun.sh
source "$WB_ROOT/modules/05-iac/corrige/pannes/_m05-commun.sh"

_E38_USER="wb-tofu@pve"
_E38_TOKEN="wb-tofu@pve!tofu"

# _e38_identite — « token wb-tofu@pve!tofu » (droits séparés) ou « user wb-tofu@pve ».
_e38_identite() {
  local ps
  ps="$(remote "$WB_PVE_HOST" "pveum user token list $_E38_USER --output-format json" 2>/dev/null \
    | jq -r '.[] | select(.tokenid == "tofu") | .privsep // 1' 2>/dev/null)" || return 1
  [[ -n "$ps" ]] || return 1
  if [[ "$ps" == 1 ]]; then printf 'token %s\n' "$_E38_TOKEN"; else printf 'user %s\n' "$_E38_USER"; fi
}

# _e38_acl TYPE UGID — entrées d'ACL de l'identité : « chemin rôle propagate ».
_e38_acl() {
  remote "$WB_PVE_HOST" "pveum acl list --output-format json" 2>/dev/null \
    | jq -r --arg t "$1" --arg u "$2" '.[] | select(.type == $t and .ugid == $u) | "\(.path) \(.roleid) \(.propagate // 1)"' 2>/dev/null || true
}

_e38_roles_json() { remote "$WB_PVE_HOST" "pveum role list --output-format json" 2>/dev/null || true; }

# _e38_role_a ROLE PRIV — 0 si le rôle contient le privilège.
_e38_role_a() {
  _e38_roles_json | jq -e --arg r "$1" --arg p "$2" \
    '.[] | select(.roleid == $r) | (.privs // "") | split(",") | index($p)' >/dev/null 2>&1
}

_e38_role_special() {
  _e38_roles_json | jq -e --arg r "$1" '.[] | select(.roleid == $r) | (.special // 0) == 1' >/dev/null 2>&1
}

# Variantes 1 et 4 : retirer PRIV de chaque rôle personnalisé de l'identité qui le contient.
_e38_retirer_priv() {
  local priv="$1" type ugid roles r privs neuves fait=0 d
  d="$(m05_etat E38)"
  read -r type ugid < <(_e38_identite) || return 1
  roles="$(_e38_acl "$type" "$ugid" | awk '{ print $2 }' | sort -u)"
  for r in $roles; do
    _e38_role_a "$r" "$priv" || continue
    if _e38_role_special "$r"; then return 10; fi
    privs="$(_e38_roles_json | jq -r --arg r "$r" '.[] | select(.roleid == $r) | .privs')"
    neuves="$(tr ',' '\n' <<<"$privs" | grep -vx "$priv" | paste -sd ',' -)"
    [[ -n "$neuves" ]] || return 10
    printf '%s\t%s\n' "$r" "$priv" >>"$d/privs-retires"
    wb_exec "$WB_PVE_HOST" ROLE="$r" PRIVS="$neuves" PRIV="$priv" >/dev/null <<'EOF' || return 1
pveum role modify "$ROLE" --privs "$PRIVS" || exit 1
journal "rôle $ROLE : privilège $PRIV retiré"
EOF
    fait=1
  done
  ((fait)) || return 10
  m05_journal E38 "$priv retiré des rôles de $ugid"
}

# Variantes 2 et 3 : supprimer l'ACL la plus précise qui donne PRIV sur l'un des CHEMINS (dans l'ordre).
_e38_retirer_acl() {
  local priv="$1" type ugid chemin ligne p r prop opt d
  shift
  d="$(m05_etat E38)"
  read -r type ugid < <(_e38_identite) || return 1
  if [[ "$type" == token ]]; then opt="--tokens"; else opt="--users"; fi
  for chemin in "$@"; do
    while read -r p r prop; do
      [[ "$p" == "$chemin" ]] || continue
      _e38_role_a "$r" "$priv" || continue
      ligne="$(printf '%s\t%s\t%s\t%s\t%s' "$p" "$r" "$prop" "$opt" "$ugid")"
      printf '%s\n' "$ligne" >>"$d/acl-retirees"
      wb_exec "$WB_PVE_HOST" CHEMIN="$p" ROLE="$r" OPT="$opt" UGID="$ugid" >/dev/null <<'EOF' || return 1
pveum acl delete "$CHEMIN" --roles "$ROLE" "$OPT" "$UGID" || exit 1
journal "ACL supprimée : $CHEMIN $ROLE $UGID"
EOF
      m05_journal E38 "ACL $p ($r) de $ugid supprimée"
      return 0
    done < <(_e38_acl "$type" "$ugid")
  done
  return 10
}

_m05E38_une() {
  local n="$1" sto="${WB_STORAGE_NVME:-local-nvme}"
  case "$n" in
    1) _e38_retirer_priv VM.Config.Memory ;;
    2) _e38_retirer_acl SDN.Use /sdn/zones/lab/vsandbox /sdn/zones/lab ;;
    3) _e38_retirer_acl Datastore.AllocateSpace "/storage/$sto" /storage ;;
    4) _e38_retirer_priv VM.PowerMgmt ;;
  esac
}

_e38_injecter() {
  local vmid
  m05_prerequis envs || return 1
  _e38_identite >/dev/null || { wb_avert "jeton $_E38_TOKEN introuvable sur pve01 (M05-E03)"; return 1; }
  vmid="$(m05_vmid_libre 2057)" || { wb_avert "aucun VMID libre dans 2050-2059"; return 1; }
  m05_ecrire E38 vmid "$vmid"
  m05_essayer E38 4 "$1"
}

panne_E38_v1() { _e38_injecter 1; }
panne_E38_v2() { _e38_injecter 2; }
panne_E38_v3() { _e38_injecter 3; }
panne_E38_v4() { _e38_injecter 4; }

verifier_E38() {
  local d r priv p
  d="$(m05_etat E38)"
  if [[ -s "$d/privs-retires" ]]; then
    while IFS=$'\t' read -r r priv; do
      _e38_role_a "$r" "$priv" && return 1
    done <"$d/privs-retires"
    return 0
  fi
  if [[ -s "$d/acl-retirees" ]]; then
    local type ugid
    read -r type ugid < <(_e38_identite) || return 1
    while IFS=$'\t' read -r p r _; do
      _e38_acl "$type" "$ugid" | awk -v p="$p" -v r="$r" '$1 == p && $2 == r { f = 1 } END { exit !f }' && return 1
    done <"$d/acl-retirees"
    return 0
  fi
  return 1
}

annuler_E38() {
  local d r priv p prop opt u type ugid
  d="$(m05_etat E38)"
  if [[ -f "$d/privs-retires" ]]; then
    while IFS=$'\t' read -r r priv; do
      [[ -n "$r" ]] || continue
      if _e38_role_a "$r" "$priv"; then
        m05_journal E38 "annulation : $priv déjà présent dans $r"
        continue
      fi
      wb_exec "$WB_PVE_HOST" ROLE="$r" PRIV="$priv" >/dev/null <<'EOF' || wb_avert "pve01 : privilège à rajouter à la main"
pveum role modify "$ROLE" --privs "$PRIV" --append 1 && journal "annulation : $PRIV rajouté au rôle $ROLE"
EOF
    done <"$d/privs-retires"
    rm -f -- "$d/privs-retires"
  fi
  if [[ -f "$d/acl-retirees" ]]; then
    while IFS=$'\t' read -r p r prop opt u; do
      [[ -n "$p" ]] || continue
      if [[ "$opt" == --tokens ]]; then type=token; else type=user; fi
      ugid="$u"
      if _e38_acl "$type" "$ugid" | awk -v p="$p" -v r="$r" '$1 == p && $2 == r { f = 1 } END { exit !f }'; then
        m05_journal E38 "annulation : ACL $p ($r) déjà présente"
        continue
      fi
      wb_exec "$WB_PVE_HOST" CHEMIN="$p" ROLE="$r" PROP="$prop" OPT="$opt" UGID="$ugid" >/dev/null <<'EOF' || wb_avert "pve01 : ACL à recréer à la main"
pveum acl modify "$CHEMIN" --roles "$ROLE" "$OPT" "$UGID" --propagate "$PROP" && journal "annulation : ACL $CHEMIN $ROLE $UGID recréée"
EOF
    done <"$d/acl-retirees"
    rm -f -- "$d/acl-retirees"
  fi
  rm -f -- "$d/variante"
}

resume_E38() {
  echo "La demande de Julien sur envs/lab-m05 (VM $(m05_lire E38 vmid) et mémoire en plus) : plan correct, apply en échec sur un refus de droits."
}

symptome_E38() {
  local vmid
  vmid="$(m05_lire E38 vmid)"
  wb_symptome "Ticket DEV-680 — De : Julien Petit" \
    "Pour la campagne de tests de charge de MédiAgenda, j'ai besoin dans envs/lab-m05 :" \
    "  - d'une VM d'environnement de plus, VMID $vmid, construite comme les autres ;" \
    "  - de 512 Mo de mémoire en plus pour chacune des VMs existantes de l'environnement." \
    "Fais la modification (MR, comme d'habitude) et applique-la. Lucas a essayé hier soir :" \
    "« le plan est parfait, mais l'apply s'arrête sur une erreur de droits Proxmox »." \
    "Je veux l'environnement complet, et pas de droits en plus de ce qui est nécessaire." \
    "" \
    "Temps cible : 40 min. Contrôle : lab/bin/check 05 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 05 E38 4 "$@"; }
fi
