# shellcheck shell=bash
# shellcheck disable=SC2154  # PKR_VAR_proxmox_* : chargées par pve_charger_acces (environnement ou fichier)
# outils/pve.sh — accès à l'API Proxmox pour les outils du projet (M03-E09, complété en M03-E10).
# À sourcer. Mêmes accès que Packer : PKR_VAR_proxmox_url, PKR_VAR_proxmox_username,
# PKR_VAR_proxmox_token, PKR_VAR_proxmox_node (environnement en CI, sinon $PVE_PACKER_ENV,
# défaut ~/.config/workbook/pve-packer.env, mode 600). TLS vérifié par le magasin système.

# pve_charger_acces — charge et contrôle les variables d'accès (code 1 si incomplètes).
pve_charger_acces() {
  local f="${PVE_PACKER_ENV:-$HOME/.config/workbook/pve-packer.env}" v
  if [[ -z "${PKR_VAR_proxmox_token:-}" ]]; then
    [[ -r "$f" ]] || { echo "fichier d'accès illisible : $f" >&2; return 1; }
    [[ "$(stat -c %a "$f")" == 600 ]] || { echo "$f doit être en mode 600" >&2; return 1; }
    set -a
    # shellcheck source=/dev/null
    . "$f"
    set +a
  fi
  for v in PKR_VAR_proxmox_url PKR_VAR_proxmox_username PKR_VAR_proxmox_token PKR_VAR_proxmox_node; do
    [[ -n "${!v:-}" ]] || { echo "variable $v absente" >&2; return 1; }
  done
}

# pve_api MÉTHODE CHEMIN [clé=valeur…] — appelle l'API, affiche le champ « data » (JSON).
#   GET/DELETE : paramètres dans l'URL ; POST/PUT : paramètres dans le corps.
#   Erreur HTTP : motif de Proxmox sur la sortie d'erreur, code 1.
#   Le secret passe par un en-tête lu dans un descripteur : jamais dans la liste des processus.
pve_api() {
  local methode="$1" chemin="$2" corps code p
  shift 2
  local args=(-sS --max-time 60 -X "$methode" -o - -w '\n%{http_code}')
  [[ "$methode" == GET || "$methode" == DELETE ]] && args+=(-G)
  for p in "$@"; do args+=(--data-urlencode "$p"); done
  corps="$(curl "${args[@]}" \
    -H @<(printf 'Authorization: PVEAPIToken=%s=%s\n' "$PKR_VAR_proxmox_username" "$PKR_VAR_proxmox_token") \
    "${PKR_VAR_proxmox_url%/}$chemin")" || { echo "API injoignable : $chemin" >&2; return 1; }
  code="${corps##*$'\n'}"
  corps="${corps%$'\n'*}"
  if [[ "$code" != 2?? ]]; then
    echo "API $methode $chemin : HTTP $code $(jq -rc '(.message // .errors // empty) | if type == "string" then . else tojson end' <<<"$corps" 2>/dev/null)" >&2
    return 1
  fi
  jq -c '.data' <<<"$corps"
}

# pve_attendre_tache UPID [DÉLAI_S] — attend la fin d'une tâche, code 1 si elle échoue.
pve_attendre_tache() {
  local upid="$1" delai="${2:-600}" fin statut
  fin=$((SECONDS + delai))
  while ((SECONDS < fin)); do
    statut="$(pve_api GET "/nodes/$PKR_VAR_proxmox_node/tasks/$(jq -rn --arg u "$upid" '$u|@uri')/status")" || return 1
    if [[ "$(jq -r '.status' <<<"$statut")" == stopped ]]; then
      [[ "$(jq -r '.exitstatus' <<<"$statut")" == OK ]] && return 0
      echo "tâche en échec : $(jq -r '.exitstatus' <<<"$statut")" >&2
      return 1
    fi
    sleep 2
  done
  echo "tâche toujours en cours après ${delai} s : $upid" >&2
  return 1
}

# pve_vms — VMs et templates visibles par le jeton (JSON de /cluster/resources).
pve_vms() { pve_api GET /cluster/resources type=vm; }
