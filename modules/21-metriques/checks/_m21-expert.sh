# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq/yq et commandes distantes entre apostrophes
# _m21-expert.sh — fonctions partagées par les vérifications du palier 4 et du mini-projet du module 21
# (check-E35 à check-E46). Sourcé par ces scripts, jamais lancé seul. Lecture seule : vue globale
# (prom_api, prom_requete), Alertmanager (am_api), Grafana (jeton Viewer), Mailpit (lecture), kubectl
# avec le compte des checks (fonction « kube »), API GitLab en lecture, commandes de consultation sur
# mon01 et les VMs (sudo -n : systemctl is-active, cat, curl locaux).
# Préfixe _m21x_ : évite les collisions quand check-E43 et check-E46 chargent plusieurs checks.

_m21x_ns=wb-pannes
_m21x_sup=supervision
_m21x_depot="${WB_DEPOT:-$HOME/medisphere}"
_m21x_mon01="${WB_M21_MON01:-mon01}"
_m21x_rb="docs/observabilite/metriques/runbooks"

# _m21x_kq 'filtre jq' ARGS… — 0 si « kube get ARGS -o json » satisfait le filtre.
_m21x_kq() {
  local f="$1"
  shift
  kube get "$@" -o json 2>/dev/null | jq -e "$f" >/dev/null 2>&1
}

# _m21x_nb 'PromQL' — nombre de séries renvoyées par la vue globale (0 en cas d'erreur).
_m21x_nb() {
  local n
  n="$(prom_requete "$1" 2>/dev/null | jq -r '.data.result | length' 2>/dev/null)" || n=0
  printf '%s\n' "${n:-0}"
}
# _m21x_val 'PromQL' — valeur du premier résultat (vide si aucun).
_m21x_val() { prom_requete "$1" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null; }
# _m21x_vide 'PromQL' — la requête ne renvoie aucune série (et la vue globale répond).
_m21x_vide() {
  prom_requete "$1" 2>/dev/null | jq -e '.status == "success" and (.data.result | length == 0)' >/dev/null 2>&1
}
# _m21x_non_vide 'PromQL'
_m21x_non_vide() { [[ "$(_m21x_nb "$1")" -gt 0 ]]; }

# _m21x_vue_globale — la vue globale (10.10.41.60) répond.
_m21x_vue_globale() { [[ "$(_m21x_val 'vector(1)')" == 1 ]]; }

# _m21x_am_config_json — configuration chargée par Alertmanager du cluster, en JSON.
_m21x_am_config_json() { am_api status 2>/dev/null | jq -r '.config.original // empty' | yq -o=json '.' 2>/dev/null; }

# _m21x_regles_json — groupes de règles vus par la vue globale (JSON).
_m21x_regles_json() { prom_api 'rules' 2>/dev/null; }

# _m21x_regle_chargee NOM — une règle (alerte ou enregistrement) de ce nom est chargée.
_m21x_regle_chargee() {
  _m21x_regles_json | jq -e --arg n "$1" '[.data.groups[]?.rules[]? | select(.name == $n)] | length > 0' >/dev/null 2>&1
}
# _m21x_regle_qui 'regex' — une règle d'alerte chargée a une expression qui correspond.
_m21x_regle_qui() {
  _m21x_regles_json | jq -e --arg r "$1" '[.data.groups[]?.rules[]? | select(.type == "alerting") | select(.query | test($r))] | length > 0' >/dev/null 2>&1
}

# _m21x_aucune_panne_active [EXX…] — aucune des pannes listées (ou M21-* si aucune) n'est marquée.
_m21x_aucune_panne_active() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives" e
  if (($# == 0)); then
    [[ -z "$(find "$d" -maxdepth 1 -name 'M21-E*' 2>/dev/null)" ]]
    return
  fi
  for e in "$@"; do
    [[ ! -e "$d/M21-$e" ]] || return 1
  done
}

# _m21x_temoins — les témoins du palier 4 existent (créés à la première injection).
_m21x_temoins() { kube -n "$_m21x_ns" get deploy temoin-metriques >/dev/null 2>&1; }

# _m21x_app_ok APP — Application Argo CD Synced, Healthy, dernière opération réussie.
_m21x_app_ok() {
  _m21x_kq '.status.sync.status == "Synced" and .status.health.status == "Healthy"
            and ((.status.operationState.phase // "Succeeded") == "Succeeded")' -n argocd applications.argoproj.io "$1"
}

# _m21x_mon01 'commande' — commande de consultation en root sur mon01 ; code de retour.
_m21x_mon01() { remote "$_m21x_mon01" "sudo -n bash -c $(printf '%q' "$1")" </dev/null >/dev/null 2>&1; }
# _m21x_mon01_sortie 'commande' — idem, sortie standard.
_m21x_mon01_sortie() { remote "$_m21x_mon01" "sudo -n bash -c $(printf '%q' "$1")" </dev/null 2>/dev/null; }

# _M21X_UNITE — préambule distant : retrouver une unité systemd par son binaire et une option.
_M21X_UNITE='unite_de() { local u x; for u in $(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | awk "{print \$1}"); do
    x="$(systemctl show -p ExecStart --value "$u" 2>/dev/null | sed -n "s/.*path=\([^ ;]*\).*/\1/p" | head -n 1)"
    [ "$(basename "${x:-/}")" = "$1" ] && { echo "$u"; return 0; }; done; return 1; }
option_de() { systemctl show -p ExecStart --value "$1" 2>/dev/null | tr " ;" "\n\n" | sed -n "s/^--$2=\(.*\)/\1/p; /^--$2\$/{n;p}" | head -n 1; }'

# _m21x_doc_commite MOTIF — un fichier du dépôt de documentation correspond au motif, il est suivi par
# git et sans modification en attente.
_m21x_doc_commite() {
  (
    cd "$_m21x_depot" 2>/dev/null || exit 1
    shopt -s nullglob
    # shellcheck disable=SC2206  # motif de chemin voulu
    local -a f=($1)
    ((${#f[@]} > 0)) || exit 1
    git ls-files --error-unmatch "${f[0]}" >/dev/null 2>&1 && [[ -z "$(git status --porcelain -- "${f[0]}")" ]]
  )
}

# _m21x_doc_contient MOTIF 'regex' — le premier fichier correspondant au motif contient la regex.
_m21x_doc_contient() {
  (
    cd "$_m21x_depot" 2>/dev/null || exit 1
    shopt -s nullglob
    # shellcheck disable=SC2206
    local -a f=($1)
    ((${#f[@]} > 0)) || exit 1
    grep -Eqi -- "$2" "${f[0]}"
  )
}

# _m21x_git_brut PROJET CHEMIN — contenu d'un fichier sur main (API GitLab, jeton de lecture).
_m21x_git_brut() {
  gitlab_api "projects/$(jq -rn --arg v "$1" '$v|@uri')/repository/files/$(jq -rn --arg v "$2" '$v|@uri')/raw?ref=main"
}
# _m21x_git_arbre PROJET DOSSIER — chemins des fichiers du dossier (récursif, 100 au plus).
_m21x_git_arbre() {
  gitlab_api "projects/$(jq -rn --arg v "$1" '$v|@uri')/repository/tree?ref=main&recursive=true&per_page=100&path=$(jq -rn --arg v "$2" '$v|@uri')" |
    jq -r '.[] | select(.type == "blob") | .path'
}
# _m21x_pipeline_main_vert PROJET — le dernier pipeline de main a réussi.
_m21x_pipeline_main_vert() {
  gitlab_api "projects/$(jq -rn --arg v "$1" '$v|@uri')/pipelines?ref=main&per_page=1" 2>/dev/null |
    jq -e '.[0].status == "success"' >/dev/null 2>&1
}

# _m21x_courriels 'recherche Mailpit' DEPUIS_EPOCH — nombre de messages correspondants reçus depuis
# (vide si Mailpit ne répond pas : le contrôle qui l'utilise passe alors au rouge).
_m21x_courriels() {
  mailpit_api "search?query=$(jq -rn --arg v "$1" '$v|@uri')&limit=200" 2>/dev/null |
    jq -r --argjson t "${2:-0}" '
      def epoque: sub("\\.[0-9]+"; "")
        | if test("Z$") then fromdateiso8601
          else capture("^(?<d>.{19})(?<s>[+-])(?<h>[0-9]{2}):(?<m>[0-9]{2})$")
               | ((.d + "Z") | fromdateiso8601) - ((if .s == "+" then 1 else -1 end) * ((.h | tonumber) * 3600 + (.m | tonumber) * 60))
          end;
      [.messages[]? | select((.Created | epoque) >= $t)] | length' 2>/dev/null
}

# _M21X_JQ_SECONDES — définition jq « secondes » : durée Prometheus (1h30m, 45s…) en secondes.
_M21X_JQ_SECONDES='def secondes: [scan("([0-9]+)(ms|s|m|h|d|w|y)")]
  | map((.[0] | tonumber) * ({"ms": 0.001, "s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800, "y": 31536000}[.[1]])) | add // 0;'

# _m21x_routes_json — toutes les routes de la configuration d'Alertmanager (objets), en JSON.
_m21x_routes_json() { _m21x_am_config_json | jq -c '[.route | .. | objects | select(has("receiver") or has("matchers") or has("group_by"))]' 2>/dev/null; }
