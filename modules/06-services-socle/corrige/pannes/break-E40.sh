# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E40.sh — M06-E40 « Panne : l'inventaire NetBox ne renvoie plus d'hôtes »
#
# Variantes :
#   1. NetBox : l'étiquette « socle » renommée « socle-par1 » (nom et slug) dans l'interface (« pour
#      préparer PAR2 ») → le groupe socle (et tout filtre tag: socle) se vide ;
#   2. NetBox : les VMs étiquetées socle passent au statut « planned » (« script de synchronisation
#      lancé avec un mauvais statut ») → sans effet si ton inventaire ne filtre pas sur le statut ;
#   3. copie de travail ~/src/ansible : « virtual_machines: false » dans le fichier d'inventaire NetBox
#      (exemple recopié d'un inventaire d'équipements physiques).
# Le script essaie la variante tirée, puis les suivantes, jusqu'à en trouver une qui vide le groupe
# socle de ton inventaire NetBox. Écritures NetBox avec le jeton d'automatisation
# (~/.config/workbook/netbox-auto.token) ; valeurs d'origine dans ~/.local/state/workbook/M06-E40/.
# L'annulation ne rétablit que ce qui porte encore la valeur posée par la panne.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m06-commun.sh
source "$WB_ROOT/modules/06-services-socle/corrige/pannes/_m06-commun.sh"

_E40_JETON="$_M06_CFG/netbox-auto.token"

# _e40_nb MÉTHODE CHEMIN [JSON] — appel de l'API NetBox avec le jeton d'écriture.
_e40_nb() {
  local m="$1" p="$2" d="${3:-}"
  [[ -r "$_E40_JETON" ]] || return 1
  if [[ -n "$d" ]]; then
    curl -sf --max-time 20 -X "$m" -H "Authorization: Bearer $(<"$_E40_JETON")" \
      -H "Content-Type: application/json" -H "Accept: application/json" -d "$d" "$_M06_NETBOX_URL/api/$p"
  else
    curl -sf --max-time 20 -X "$m" -H "Authorization: Bearer $(<"$_E40_JETON")" \
      -H "Accept: application/json" "$_M06_NETBOX_URL/api/$p"
  fi
}

# _e40_nb_socle — nombre d'hôtes du groupe socle de l'inventaire NetBox (vide si erreur).
_e40_nb_socle() {
  local inv j
  inv="$(m06_inv_netbox)" || return 1
  j="$(m06_ansible ansible-inventory -i "$inv" --list 2>/dev/null)" || return 1
  m06_hotes_groupe "$j" socle | grep -c . || true
}

_e40_precondition() {
  local inv nb
  if ! inv="$(m06_inv_netbox)"; then
    wb_avert "aucun inventaire NetBox (plugin netbox.netbox.nb_inventory) dans $_M06_ANSIBLE/inventories : M06-E12"
    return 1
  fi
  if [[ -n "$(git -C "$_M06_ANSIBLE" status --porcelain 2>/dev/null)" ]] && [[ -z "${_M06_ASTREINTE:-}" ]]; then
    wb_avert "la copie de travail $_M06_ANSIBLE contient des modifications non commitées : commite-les ou mets-les de côté (git stash)"
    return 1
  fi
  nb="$(_e40_nb_socle)"
  if [[ -z "$nb" || "$nb" == 0 ]]; then
    wb_avert "l'inventaire NetBox ($inv) ne renvoie déjà aucun hôte dans le groupe socle : lab/bin/check 06 40"
    return 1
  fi
  m06_ecrire E40 avant "$nb"
}

_mE40_une() {
  local n="$1" d j id ids inv f
  d="$(m06_etat E40)"
  case "$n" in
    1)
      j="$(_e40_nb GET 'extras/tags/?slug=socle')" || return 10
      id="$(jq -r '.results[0].id // empty' <<<"$j")"
      [[ -n "$id" ]] || return 10
      jq -c '.results[0] | {id, name, slug}' <<<"$j" >"$d/etiquette"
      _e40_nb PATCH "extras/tags/$id/" '{"name": "socle-par1", "slug": "socle-par1"}' >/dev/null || return 1
      m06_journal E40 "étiquette NetBox $id : socle → socle-par1"
      ;;
    2)
      j="$(_e40_nb GET 'virtualization/virtual-machines/?tag=socle&limit=0')" || return 10
      jq -c '[.results[] | select(.status.value != "planned") | {id, status: .status.value}]' <<<"$j" >"$d/statuts"
      ids="$(jq -c '[.[] | {id, status: "planned"}]' "$d/statuts")"
      [[ "$ids" != "[]" ]] || return 10
      _e40_nb PATCH 'virtualization/virtual-machines/' "$ids" >/dev/null || return 1
      m06_journal E40 "VMs du socle passées en planned : $(jq -r 'map(.id) | join(",")' "$d/statuts")"
      ;;
    3)
      inv="$(m06_inv_netbox)" || return 10
      f="$_M06_ANSIBLE/$inv"
      m06_sauver E40 "$f" || return 1
      if grep -Eq '^virtual_machines:' "$f"; then
        sed -i -E 's/^virtual_machines:.*/virtual_machines: false  # inventaire des équipements (exemple de la doc)/' "$f"
      else
        printf 'virtual_machines: false  # inventaire des équipements (exemple de la doc)\n' >>"$f"
      fi
      m06_noter E40 "$f"
      m06_journal E40 "$inv : virtual_machines: false"
      ;;
  esac
  sleep 2
  if [[ "$(_e40_nb_socle)" =~ ^[1-9] ]]; then
    m06_journal E40 "variante $n sans effet sur ton inventaire"
    _e40_defaire "$n"
    return 10
  fi
}

_e40_defaire() {
  local d id j cur
  d="$(m06_etat E40)"
  case "$1" in
    1)
      [[ -f "$d/etiquette" ]] || return 0
      id="$(jq -r .id "$d/etiquette")"
      cur="$(_e40_nb GET "extras/tags/$id/" | jq -r '.slug // empty')" || cur=""
      if [[ "$cur" == socle-par1 ]]; then
        _e40_nb PATCH "extras/tags/$id/" "$(jq -c '{name, slug}' "$d/etiquette")" >/dev/null \
          || wb_avert "étiquette NetBox $id non rétablie (fais-le à la main : nom et slug « socle »)"
        m06_journal E40 "annulation : étiquette $id rétablie"
      else
        m06_journal E40 "annulation : étiquette $id déjà modifiée (réparation), laissée telle quelle"
      fi
      rm -f "$d/etiquette"
      ;;
    2)
      [[ -f "$d/statuts" ]] || return 0
      j="$(_e40_nb GET 'virtualization/virtual-machines/?status=planned&limit=0')" || j='{"results":[]}'
      # Seules les VMs encore en « planned » retrouvent leur statut d'origine.
      cur="$(jq -c --argjson orig "$(cat "$d/statuts")" \
        '[.results[] | .id as $i | ($orig[] | select(.id == $i))]' <<<"$j")" || cur="[]"
      if [[ "$cur" != "[]" ]]; then
        _e40_nb PATCH 'virtualization/virtual-machines/' "$cur" >/dev/null \
          || wb_avert "statuts NetBox non rétablis : $cur"
      fi
      m06_journal E40 "annulation : statuts rétablis pour $(jq -r 'map(.id) | join(",")' <<<"$cur")"
      rm -f "$d/statuts"
      ;;
    3) m06_restaurer E40 ;;
  esac
}

_e40_injecter() {
  _e40_precondition || return 1
  m06_essayer E40 3 "$1"
}

panne_E40_v1() { _e40_injecter 1; }
panne_E40_v2() { _e40_injecter 2; }
panne_E40_v3() { _e40_injecter 3; }

verifier_E40() {
  local nb
  nb="$(_e40_nb_socle)"
  [[ -n "$nb" && "$nb" == 0 ]]
}

annuler_E40() {
  case "${WB_VAR:-}" in
    [1-3]) _e40_defaire "$WB_VAR" ;;
    *) _e40_defaire 3; _e40_defaire 2; _e40_defaire 1 ;;
  esac
}

resume_E40() {
  echo "Le contrôle de dérive échoue sur son garde-fou : l'inventaire NetBox ne contient plus aucun hôte du socle."
}

symptome_E40() {
  wb_symptome "Ticket INC-3346 — De : Nadia Roussel" \
    "Le contrôle de dérive de cette nuit (site.yml --check, inventaire NetBox) a échoué en" \
    "quelques secondes, sur le garde-fou de tête de site.yml : le groupe socle est vide." \
    "« ansible-inventory --graph » avec l'inventaire NetBox ne montre plus aucun hôte du socle ;" \
    "avec l'inventaire Proxmox, tout est là. Personne n'a touché au projet Ansible, paraît-il." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 06 40"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 06 E40 3 "$@"; }
fi
