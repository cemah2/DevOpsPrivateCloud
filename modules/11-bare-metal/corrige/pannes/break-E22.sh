# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E22.sh — M11-E22 « Panne : MAAS ne pilote plus les machines »
#
# Préalable : MAAS démarré sur maas01, machines bm* (bm01 et bm03 depuis M11-E10) avec le pilote Proxmox,
# clé d'API de MAAS lisible sur adm01 ($WB_MAAS_KEY_FILE, défaut ~/.config/workbook/maas-api.key).
# Variantes :
#   1. pve01 : le jeton wb-maas@pve!maas expire (date d'expiration passée, « rotation des jetons »)
#      → 401 sur toutes les requêtes de MAAS ;
#   2. pve01 : VM.Audit retiré du rôle WBMaas (« ménage des privilèges : MAAS n'a besoin que
#      d'allumer et d'éteindre ») → 403 sur la lecture de l'état des VMs ;
#   3. pve01 : une VM bm* que MAAS désigne par son NOM est renommée (« <nom>-ancien », bm03 dans le corrigé de M11-E10) → MAAS ne la
#      trouve plus ; sans effet si MAAS désigne les VMs par leur identifiant : variante suivante ;
#   4. maas01 : l'ancre TLS de pve01 retirée du magasin système (update-ca-certificates --fresh)
#      → vérification TLS refusée ; sans effet si le snap n'utilise pas ce magasin : variante suivante.
# Sur pve01, seuls le jeton wb-maas, le rôle WBMaas et le nom d'une VM 2112-2115 sont touchés.
# Valeurs d'origine : /var/lib/workbook/M11-E22.* (pve01, maas01) et ~/.local/state/workbook/M11-E22/.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m11-commun.sh
source "$WB_ROOT/modules/11-bare-metal/corrige/pannes/_m11-commun.sh"

# _e22_toutes_ok — toutes les machines bm* de MAAS ont un état d'alimentation interrogeable.
_e22_toutes_ok() {
  local id nom n=0
  while read -r id nom; do
    [[ -n "$id" ]] || continue
    m11_maas_alim_ok "$id" || return 1
    n=$((n + 1))
  done < <(m11_maas_bm)
  ((n > 0))
}

# _e22_une_ko — au moins une machine bm* n'est plus interrogeable (la cible si elle est connue).
_e22_une_ko() {
  local cible id nom
  cible="$(m11_lire E22 cible)"
  while read -r id nom; do
    [[ -n "$id" ]] || continue
    if [[ -n "$cible" && "$nom" != "$cible" ]]; then continue; fi
    m11_maas_alim_ok "$id" || return 0
  done < <(m11_maas_bm)
  return 1
}

_e22_precondition() {
  command -v jq >/dev/null || { wb_avert "jq absent sur adm01"; return 1; }
  if [[ ! -r "$_M11_MAAS_CLE" ]]; then
    wb_avert "clé d'API de MAAS illisible ($_M11_MAAS_CLE) : voir l'introduction du module"
    return 1
  fi
  if ! _e22_toutes_ok; then
    wb_avert "MAAS n'interroge pas déjà l'alimentation de toutes les machines bm* (MAAS démarré ? pilote Proxmox ?) : lab/bin/check 11 22"
    return 1
  fi
}

_mE22_une() {
  local n="$1" rc=0 id nom param
  m11_effacer E22 cible
  case "$n" in
    1)
      wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || rc=$?
o="$(pveum user token list wb-maas@pve --output-format json 2>/dev/null)" || exit 10
exp="$(printf '%s' "$o" | python3 -c 'import json,sys; t=[x for x in json.load(sys.stdin) if x.get("tokenid")=="maas"]; print(t[0].get("expire",0) if t else "")')"
[ -n "$exp" ] || exit 10
[ -f "$WB_DIR/M11-E22.expire" ] || printf '%s\n' "$exp" >"$WB_DIR/M11-E22.expire"
pose=$(( $(date +%s) - 3600 ))
pveum user token modify wb-maas@pve maas --expire "$pose" >/dev/null || exit 1
printf '%s\n' "$pose" >"$WB_DIR/M11-E22.pose"
journal "jeton wb-maas@pve!maas : expiration $exp → $pose (passée)"
EOF
      ;;
    2)
      wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || rc=$?
privs="$(pveum role list --output-format json 2>/dev/null | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin) if x.get("roleid")=="WBMaas"]; print(r[0].get("privs","") if r else "")')"
case ",$privs," in *,VM.Audit,*) ;; *) exit 10 ;; esac
[ -f "$WB_DIR/M11-E22.privs" ] || printf '%s\n' "$privs" >"$WB_DIR/M11-E22.privs"
nv="$(printf '%s' "$privs" | tr ',' '\n' | grep -vx 'VM.Audit' | paste -sd, -)"
[ -n "$nv" ] || exit 10
pveum role modify WBMaas --privs "$nv" >/dev/null || exit 1
printf '%s\n' "$nv" >"$WB_DIR/M11-E22.privs-pose"
journal "rôle WBMaas : « $privs » → « $nv »"
EOF
      ;;
    3)
      # Une machine que MAAS désigne par le NOM de sa VM (paramètre d'alimentation non numérique).
      local trouve=""
      while read -r id nom; do
        [[ -n "$id" ]] || continue
        param="$(m11_maas_json GET "machines/$id/?op=power_parameters" \
          | jq -r 'to_entries[] | select(.key | test("vm_name|node_id|vm_id")) | .value' 2>/dev/null | head -n 1)"
        if [[ "$param" == "$nom" ]]; then trouve="$nom"; break; fi
      done < <(m11_maas_bm)
      [[ -n "$trouve" && -n "${_M11_VMID[$trouve]:-}" ]] || return 10
      m11_ecrire E22 cible "$trouve"
      wb_exec "$WB_PVE_HOST" VMID="${_M11_VMID[$trouve]}" NOM="$trouve" >/dev/null <<'EOF' || rc=$?
[ "$VMID" -ge 2112 ] && [ "$VMID" -le 2115 ] || exit 1
actuel="$(qm config "$VMID" | sed -n 's/^name: //p')"
[ "$actuel" = "$NOM" ] || exit 10
qm set "$VMID" --name "$NOM-ancien" >/dev/null || exit 1
printf '%s %s\n' "$VMID" "$NOM" >"$WB_DIR/M11-E22.nom"
journal "VM $VMID renommée $NOM → $NOM-ancien"
EOF
      ;;
    4)
      m11_existe maas01 || return 10
      m11_wb_exec maas01 >/dev/null <<'EOF' || rc=$?
n=0
for f in /usr/local/share/ca-certificates/*.crt; do
  [ -f "$f" ] || continue
  # Ancre de pve01 (M02-E08) : sujet « Proxmox… » / « PVE… », ou fichier nommé pve*
  if openssl x509 -in "$f" -noout -subject 2>/dev/null | grep -Eqi 'proxmox|pve' || case "$(basename "$f")" in pve*) true ;; *) false ;; esac; then
    sauver "$f"
    rm -f "$f"
    noter_injecte "$f"
    n=$((n + 1))
  fi
done
[ "$n" -gt 0 ] || exit 10
update-ca-certificates --fresh >/dev/null 2>&1
snap restart maas >/dev/null 2>&1 || true
journal "$n ancre(s) Proxmox retirée(s) du magasin système, MAAS redémarré"
EOF
      if ((rc == 0)); then sleep 30; fi
      ;;
  esac
  ((rc == 0)) || { _e22_defaire "$n"; return "$rc"; }
  sleep 5
  _e22_une_ko || { _e22_defaire "$n"; return 10; }
}

_e22_defaire() {
  case "$1" in
    1)
      wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01 (expiration du jeton wb-maas@pve!maas)"
[ -f "$WB_DIR/M11-E22.expire" ] || exit 0
orig="$(cat "$WB_DIR/M11-E22.expire")"; pose="$(cat "$WB_DIR/M11-E22.pose" 2>/dev/null)"
cur="$(pveum user token list wb-maas@pve --output-format json 2>/dev/null | python3 -c 'import json,sys; t=[x for x in json.load(sys.stdin) if x.get("tokenid")=="maas"]; print(t[0].get("expire",0) if t else "")')"
if [ -n "$cur" ] && [ "$cur" = "$pose" ]; then
  pveum user token modify wb-maas@pve maas --expire "$orig" >/dev/null
  journal "annulation : expiration du jeton rétablie ($orig)"
else
  journal "annulation : jeton modifié ou recréé depuis l'injection (réparation), laissé tel quel"
fi
rm -f "$WB_DIR/M11-E22.expire" "$WB_DIR/M11-E22.pose"
EOF
      ;;
    2)
      wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01 (rôle WBMaas)"
[ -f "$WB_DIR/M11-E22.privs" ] || exit 0
orig="$(cat "$WB_DIR/M11-E22.privs")"; pose="$(cat "$WB_DIR/M11-E22.privs-pose" 2>/dev/null)"
cur="$(pveum role list --output-format json 2>/dev/null | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin) if x.get("roleid")=="WBMaas"]; print(r[0].get("privs","") if r else "")')"
trie() { printf '%s' "$1" | tr ',' '\n' | sort | paste -sd, -; }
if [ -n "$cur" ] && [ "$(trie "$cur")" = "$(trie "$pose")" ]; then
  pveum role modify WBMaas --privs "$orig" >/dev/null
  journal "annulation : privilèges de WBMaas rétablis ($orig)"
else
  journal "annulation : rôle WBMaas modifié depuis l'injection (réparation), laissé tel quel"
fi
rm -f "$WB_DIR/M11-E22.privs" "$WB_DIR/M11-E22.privs-pose"
EOF
      ;;
    3)
      wb_exec "$WB_PVE_HOST" >/dev/null <<'EOF' || wb_avert "annulation incomplète sur pve01 (nom d'une VM bm*)"
[ -f "$WB_DIR/M11-E22.nom" ] || exit 0
read -r vmid nom <"$WB_DIR/M11-E22.nom"
if [ "$(qm config "$vmid" 2>/dev/null | sed -n 's/^name: //p')" = "$nom-ancien" ]; then
  qm set "$vmid" --name "$nom" >/dev/null
  journal "annulation : VM $vmid renommée $nom"
else
  journal "annulation : VM $vmid déjà renommée (réparation), laissée telle quelle"
fi
rm -f "$WB_DIR/M11-E22.nom"
EOF
      ;;
    4)
      if m11_existe maas01; then
        m11_wb_exec maas01 >/dev/null <<'EOF' || wb_avert "annulation incomplète sur maas01 (magasin de certificats)"
[ -f "$WB_DIR/$WB_EX.manifeste" ] || exit 0
garder_reparations
restaurer_fichiers
update-ca-certificates >/dev/null 2>&1
snap restart maas >/dev/null 2>&1 || true
EOF
      fi
      ;;
  esac
}

_e22_injecter() {
  _e22_precondition || return 1
  m11_essayer E22 4 "$1"
}

panne_E22_v1() { _e22_injecter 1; }
panne_E22_v2() { _e22_injecter 2; }
panne_E22_v3() { _e22_injecter 3; }
panne_E22_v4() { _e22_injecter 4; }

verifier_E22() { _e22_une_ko; }

annuler_E22() {
  case "${WB_VAR:-}" in
    [1-4]) _e22_defaire "$WB_VAR" ;;
    *) _e22_defaire 4; _e22_defaire 3; _e22_defaire 2; _e22_defaire 1 ;;
  esac
  m11_effacer E22 cible
}

resume_E22() {
  case "${WB_VAR:-0}" in
    3) echo "MAAS ne trouve plus l'une des machines bm* ; les autres répondent." ;;
    *) echo "MAAS n'arrive plus à interroger ni piloter l'alimentation des machines bm*." ;;
  esac
}

symptome_E22() {
  local -a l
  case "${WB_VAR:-0}" in
    3) l=("Dans MAAS, une des machines bm* est passée en état d'alimentation « Error » (ou « Unknown »)"
      "et refuse toute action : « Failed to query node's BMC ». L'autre machine répond"
      "normalement. Il y a eu du rangement dans les VMs de pve01 cette semaine.") ;;
    1) l=("Dans MAAS, toutes les machines bm* sont passées en état d'alimentation « Error » :"
      "« Failed to query node's BMC », aucune action possible. Rien n'a changé dans MAAS."
      "Sophie a lancé hier une campagne de rotation des jetons d'automatisation.") ;;
    2) l=("Dans MAAS, toutes les machines bm* sont passées en état d'alimentation « Error » :"
      "« Failed to query node's BMC ». Rien n'a changé dans MAAS. Sophie a fait hier une revue"
      "des droits des comptes de service sur pve01 : « MAAS n'a besoin que d'allumer et éteindre ».") ;;
    *) l=("Dans MAAS, toutes les machines bm* sont passées en état d'alimentation « Error » :"
      "« Failed to query node's BMC ». Rien n'a changé dans MAAS ni sur pve01. maas01 a eu"
      "ses mises à jour de sécurité hier.") ;;
  esac
  wb_symptome "Ticket INC-3844 — De : Claire Morel" "${l[@]}" "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 11 22"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 11 E22 4 "$@"; }
fi
