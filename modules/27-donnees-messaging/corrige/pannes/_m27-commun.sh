# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq, yq et SQL entre apostrophes
# _m27-commun.sh — fonctions partagées par les scripts de panne du module 27 (M27-E19 à M27-E23).
#
# Sourcé par break-EXX.sh APRÈS lab/lib/pannes-lib.sh (wb_kubectl, wb_avert, wb_k8s_sauver, WB_EX, WB_VAR…) ;
# lab/bin/break a déjà chargé lab/lib/check-lib.sh (prom_requete, harbor_api, remote).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées hors de
# tout « if » : aucune commande ne doit y échouer sans « || true ».
#
# Principes (CONVENTIONS §8, PLAN §4.10 à §4.13 « Pannes ») :
#   - ENVIRONNEMENT VISÉ : LA RECETTE (mediagenda-recette, medinotif-recette, vhost medinotif-recette de la
#     grappe messagerie/rabbitmq). Jamais un espace *-prod, jamais le vhost medinotif-prod.
#   - une panne de configuration GitOps passe par un COMMIT IDENTIFIABLE sur main (auteur Lucas Martin,
#     marqueur M27-EXX), poussé par l'API GitLab avec le jeton d'administration du lab
#     (WB_GITLAB_ADMIN_TOKEN_FILE) ; MR fusionnée automatiquement si la poussée directe est refusée.
#     L'annulation est un COMMIT INVERSE, seulement si le fichier porte encore exactement le contenu injecté
#     (une réparation n'est jamais défaite) ; jamais de réécriture d'historique ;
#   - un objet modifié directement dans le cluster est sauvegardé avant (wb_k8s_sauver, dans
#     ~/.local/state/workbook/k8s/) et n'est remis que s'il porte encore la valeur injectée ;
#   - données : aucune suppression de PVC, de sauvegarde ni de WAL archivé ; aucun DELETE de lignes
#     applicatives ; les gestes SQL de panne ne touchent que des droits, des sessions ou l'historique Flyway,
#     et sont annulés à l'identique ;
#   - messagerie : export des définitions (grappe et vhost) AVANT toute injection, réimport du vhost à
#     l'annulation tant que la panne est encore en place ; aucune purge, aucun message supprimé (un message
#     qui doit sortir d'une file part au rebut) ; jamais de mode qui perd des messages ;
#   - l'auto-synchronisation d'Argo CD n'est jamais désactivée : rafraîchissement ou opération de
#     synchronisation seulement.
#
# Variables facultatives de lab/lab.env (voir corrige/.lab-env-B.txt) :
#   WB_M27_IMAGE_AGENDA         image du témoin de trafic (défaut : celle de MédiAgenda en recette)
#   WB_M27_TRAFIC_URL           URL publiée de MédiAgenda recette
#   WB_M27_APP_AGENDA           Application Argo CD de MédiAgenda recette (défaut mediagenda-recette)
#   WB_M27_APP_NOTIF            Application Argo CD de MédiNotif recette (défaut medinotif-recette)
#   WB_M27_VALKEY_ADMIN_USER    utilisateur d'administration de Valkey (défaut admin)
#   WB_M27_VALKEY_ADMIN_SECRET  Secret de mediagenda-recette qui porte son mot de passe (défaut valkey-admin)
#   WB_M27_VALKEY_ADMIN_CLE     clé du mot de passe dans ce Secret (défaut mot_de_passe)
#   WB_RABBITMQ_URL             URL de l'API de gestion (défaut https://rabbitmq.apps.par1.medisphere.internal)
#   WB_RACINE_PKI               racine MédiSphère sur adm01

# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
{
  _M27_NS_PANNES=wb-pannes
  _M27_NS_AGENDA=mediagenda-recette
  _M27_NS_NOTIF=medinotif-recette
  _M27_NS_MSG=messagerie
  _M27_VHOST=medinotif-recette
  _M27_FILE=notifications
  _M27_REBUT=notifications.rebut
  _M27_U_NOTIF=medinotif-recette
  _M27_U_AGENDA=mediagenda-recette
  _M27_CLUSTER=mediagenda-db
  _M27_POOLER=mediagenda-db-pooler-rw
  _M27_JOB_MIGR=mediagenda-migrations
  _M27_RMQ_POD=rabbitmq-server-0
  _M27_DEPOT_DONNEES=plateforme/donnees
  _M27_DEPOT_K8S=plateforme/k8s
  _M27_DEPOT_AGENDA=mediagenda/deploiement
  _M27_DEPOT_NOTIF=medinotif/deploiement
  _M27_TOPOLOGIE=topologie/medinotif-recette
  _M27_OVERLAY=overlays/recette/kustomization.yaml
  _M27_APP_AGENDA="${WB_M27_APP_AGENDA:-mediagenda-recette}"
  _M27_APP_NOTIF="${WB_M27_APP_NOTIF:-medinotif-recette}"
  _M27_LUCAS_NOM="Lucas Martin"
  _M27_LUCAS_COURRIEL="lucas.martin@medisphere.internal"
  _M27_RMQ_URL="${WB_RABBITMQ_URL:-https://rabbitmq.apps.par1.medisphere.internal}"
}

# ---------------------------------------------------------------------------
# État local (adm01) et journal
# ---------------------------------------------------------------------------

# m27_etat EXX — dossier d'état local de la panne (créé en 700).
m27_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/M27-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
m27_journal() {
  local ex="$1" d
  shift
  d="$(m27_etat "$ex")"
  printf '%s %s [M27-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$d/journal"
}
m27_lire() {
  local f
  f="$(m27_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
m27_ecrire() {
  local d
  d="$(m27_etat "$1")"
  printf '%s\n' "$3" >"$d/$2"
  chmod 600 "$d/$2"
}
m27_oublier() {
  local d
  d="$(m27_etat "$1")"
  rm -rf -- "${d:?}/$2"
}

# m27_attendre SECONDES commande… — relance la commande toutes les 10 s jusqu'à succès ou délai.
m27_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# m27_essayer EXX NB DÉPART — essaie les variantes à partir de DÉPART ; une variante qui renvoie 10 est
# « sans effet sur ce lab » (configuration différente de celle du corrigé) : on passe à la suivante.
m27_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_m27${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      return 0
    fi
    ((rc == 10)) || return 1
  done
  wb_avert "aucune variante de M27-$ex n'a d'effet sur ce lab (configuration différente du corrigé)"
  return 1
}

# ---------------------------------------------------------------------------
# GitLab (jeton d'administration du lab) : commits de Lucas et commits inverses
# ---------------------------------------------------------------------------

_m27_gl_jeton() {
  local f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton GitLab d'administration illisible : $f (WB_GITLAB_ADMIN_TOKEN_FILE)"; return 1; }
  printf 'header = "PRIVATE-TOKEN: %s"\n' "$(<"$f")"
}

# m27_gl MÉTHODE CHEMIN — appel de l'API v4 ; corps JSON lu sur l'entrée standard pour POST et PUT.
m27_gl() {
  local m="$1" url="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4/$2" cfg
  cfg="$(_m27_gl_jeton)" || return 1
  if [[ "$m" == GET ]]; then
    curl -sf --max-time 30 -K <(printf '%s\n' "$cfg") "$url" </dev/null
  else
    curl -sf --max-time 60 -X "$m" -H "Content-Type: application/json" --data-binary @- -K <(printf '%s\n' "$cfg") "$url"
  fi
}

_m27_enc() { jq -rn --arg v "$1" '$v | @uri'; }

# m27_gl_fichier PROJET CHEMIN — contenu brut du fichier sur main (code 1 s'il n'existe pas).
m27_gl_fichier() {
  m27_gl GET "projects/$(_m27_enc "$1")/repository/files/$(_m27_enc "$2")/raw?ref=main"
}

# m27_gl_arbre PROJET DOSSIER — chemins des fichiers sous DOSSIER (récursif) sur main.
m27_gl_arbre() {
  local p page=1 r
  p="$(_m27_enc "$1")"
  while ((page < 20)); do
    r="$(m27_gl GET "projects/$p/repository/tree?ref=main&path=$(_m27_enc "$2")&recursive=true&per_page=100&page=$page")" || return 1
    jq -r '.[]? | select(.type == "blob") | .path' <<<"$r"
    [[ "$(jq 'length' <<<"$r")" -ge 100 ]] || return 0
    page=$((page + 1))
  done
}

# _m27_gl_pousser PROJET MESSAGE NOM COURRIEL ACTIONS_JSON — commit sur main ; si la poussée directe est
# refusée (branche protégée), branche + MR fusionnée automatiquement (attente bornée de la fusion).
_m27_gl_pousser() {
  local p msg="$2" nom="$3" mel="$4" actions="$5" br r iid i etat
  p="$(_m27_enc "$1")"
  if jq -n --arg m "$msg" --arg n "$nom" --arg e "$mel" --argjson a "$actions" \
    '{branch: "main", commit_message: $m, author_name: $n, author_email: $e, actions: $a}' |
    m27_gl POST "projects/$p/repository/commits" >/dev/null 2>&1; then
    return 0
  fi
  br="wb-m27-$(date +%s)-$RANDOM"
  jq -n --arg b "$br" --arg m "$msg" --arg n "$nom" --arg e "$mel" --argjson a "$actions" \
    '{branch: $b, start_branch: "main", commit_message: $m, author_name: $n, author_email: $e, actions: $a}' |
    m27_gl POST "projects/$p/repository/commits" >/dev/null || return 1
  r="$(jq -n --arg b "$br" --arg t "$msg" \
    '{source_branch: $b, target_branch: "main", title: $t, remove_source_branch: true}' |
    m27_gl POST "projects/$p/merge_requests")" || return 1
  iid="$(jq -r '.iid' <<<"$r")"
  for ((i = 0; i < 60; i++)); do
    sleep 10
    printf '{"auto_merge": true}' | m27_gl PUT "projects/$p/merge_requests/$iid/merge" >/dev/null 2>&1 || true
    etat="$(m27_gl GET "projects/$p/merge_requests/$iid" | jq -r '.state' 2>/dev/null)" || etat=""
    [[ "$etat" == merged ]] && return 0
    [[ "$etat" == closed ]] && return 1
  done
  wb_avert "la MR !$iid de $1 n'a pas été fusionnée en 10 min (pipeline ?)"
  return 1
}

# m27_commit EXX CLÉ PROJET "message" CHEMIN FICHIER_LOCAL [CHEMIN FICHIER_LOCAL…]
#   Remplace (ou crée) chaque CHEMIN de main avec le contenu de FICHIER_LOCAL, au nom de Lucas. Mémorise,
#   par CLÉ, le contenu d'origine (ou son absence) et le contenu injecté, pour le commit inverse.
m27_commit() {
  local ex="$1" cle="$2" projet="$3" msg="$4" d actions='[]' chemin local_ n=0 action
  shift 4
  d="$(m27_etat "$ex")/git-$cle"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$projet" >"$d/projet"
  : >"$d/fichiers"
  while (($# >= 2)); do
    chemin="$1" local_="$2"
    shift 2
    n=$((n + 1))
    if m27_gl_fichier "$projet" "$chemin" >"$d/orig-$n" 2>/dev/null; then
      action=update
    else
      action=create
      : >"$d/orig-$n"
      touch "$d/absent-$n"
    fi
    cp "$local_" "$d/injecte-$n"
    printf '%s\t%s\n' "$n" "$chemin" >>"$d/fichiers"
    actions="$(jq --arg c "$chemin" --arg a "$action" --rawfile t "$local_" '. + [{action: $a, file_path: $c, content: $t}]' <<<"$actions")"
  done
  _m27_gl_pousser "$projet" "$msg

M27-$ex (lab/bin/break 27 ${ex#E})" "$_M27_LUCAS_NOM" "$_M27_LUCAS_COURRIEL" "$actions" || {
    rm -rf -- "$d"
    return 1
  }
  m27_journal "$ex" "commit de Lucas sur $projet ($(cut -f2 "$d/fichiers" | paste -sd' ' -)) [$cle]"
}

# m27_retablir EXX CLÉ — commit inverse : chaque fichier qui porte ENCORE exactement le contenu injecté
# reprend son contenu d'origine (ou est supprimé s'il n'existait pas) ; les autres ne sont pas touchés.
m27_retablir() {
  local ex="$1" cle="$2" d projet n chemin actions='[]' f
  d="$(m27_etat "$ex")/git-$cle"
  [[ -f "$d/fichiers" ]] || return 0
  projet="$(<"$d/projet")"
  while IFS=$'\t' read -r n chemin; do
    f="$(mktemp)"
    if m27_gl_fichier "$projet" "$chemin" >"$f" 2>/dev/null && cmp -s "$f" "$d/injecte-$n"; then
      if [[ -e "$d/absent-$n" ]]; then
        actions="$(jq --arg c "$chemin" '. + [{action: "delete", file_path: $c}]' <<<"$actions")"
      else
        actions="$(jq --arg c "$chemin" --rawfile t "$d/orig-$n" '. + [{action: "update", file_path: $c, content: $t}]' <<<"$actions")"
      fi
    else
      m27_journal "$ex" "annulation : $projet/$chemin modifié depuis la panne, laissé tel quel"
    fi
    rm -f "$f"
  done <"$d/fichiers"
  if [[ "$(jq 'length' <<<"$actions")" -gt 0 ]]; then
    _m27_gl_pousser "$projet" "Annulation de la panne M27-$ex (lab/bin/break 27 ${ex#E} --annuler)" \
      "Lab workbook" "workbook@medisphere.internal" "$actions" ||
      wb_avert "commit inverse impossible sur $projet : remets toi-même le contenu d'origine (copie : $d)"
  fi
  rm -rf -- "$d"
  m27_journal "$ex" "annulation des commits [$cle]"
}

# m27_commit_actif EXX CLÉ — le commit de la panne est encore en place (au moins un fichier injecté).
m27_commit_actif() {
  local d projet n chemin f r=1
  d="$(m27_etat "$1")/git-$2"
  [[ -f "$d/fichiers" ]] || return 1
  projet="$(<"$d/projet")"
  while IFS=$'\t' read -r n chemin; do
    f="$(mktemp)"
    if m27_gl_fichier "$projet" "$chemin" >"$f" 2>/dev/null && cmp -s "$f" "$d/injecte-$n"; then r=0; fi
    rm -f "$f"
  done <"$d/fichiers"
  return "$r"
}

# m27_doc_trouver PROJET DOSSIER 'filtre jq sur un document' — « CHEMIN<TAB>INDEX » du premier document YAML
# (sous DOSSIER, sur main) qui satisfait le filtre. Les documents sont lus en JSON (yq) puis filtrés par jq.
m27_doc_trouver() {
  local projet="$1" dossier="$2" filtre="$3" f c i
  for f in $(m27_gl_arbre "$projet" "$dossier" | grep -E '\.ya?ml$'); do
    c="$(m27_gl_fichier "$projet" "$f" 2>/dev/null)" || continue
    i="$(yq -o=json -I=0 '.' <<<"$c" 2>/dev/null | jq -s -r "[to_entries[] | select(.value | $filtre) | .key][0] // empty" 2>/dev/null)" || continue
    if [[ -n "$i" ]]; then
      printf '%s\t%s\n' "$f" "$i"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Argo CD : rafraîchissement et synchronisation (jamais de changement de politique)
# ---------------------------------------------------------------------------

m27_argo_rafraichir() {
  local a
  for a in "$@"; do
    wb_kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
  done
}

# m27_argo_synchroniser APP — lance une opération de synchronisation (comme « argocd app sync »), au nom
# de lucas.martin, si aucune n'est en cours.
m27_argo_synchroniser() {
  local phase
  phase="$(wb_kubectl -n argocd get applications.argoproj.io "$1" -o jsonpath='{.status.operationState.phase}' 2>/dev/null)" || return 1
  [[ "$phase" == Running ]] && return 0
  wb_kubectl -n argocd patch applications.argoproj.io "$1" --type merge \
    -p '{"operation":{"initiatedBy":{"username":"lucas.martin"},"sync":{"revision":"main","syncStrategy":{"hook":{}}}}}' >/dev/null
}

# m27_app_suivie KIND NOM ESPACE — nom de l'Application Argo CD qui suit l'objet (annotation de suivi), sinon vide.
m27_app_suivie() {
  wb_kubectl -n "$3" get "$1" "$2" -o json 2>/dev/null |
    jq -r '.metadata.annotations["argocd.argoproj.io/tracking-id"] // "" | split(":")[0]'
}

# m27_overlay_avec_patch PROJET 'cible JSON' OPS_JSON SORTIE — écrit dans SORTIE la kustomization de l'overlay
# recette de PROJET complétée d'un patch JSON 6902 (cible : {"group":…, "kind":…, "name":…}). yq requis.
m27_overlay_avec_patch() {
  local projet="$1" cible="$2" ops="$3" sortie="$4" orig
  orig="$(mktemp)"
  m27_gl_fichier "$projet" "$_M27_OVERLAY" >"$orig" || { rm -f "$orig"; return 1; }
  CIBLE="$cible" PATCH="$(yq -P '.' <<<"$ops")" yq '.patches += [{"target": (strenv(CIBLE) | from_json), "patch": strenv(PATCH)}]' "$orig" >"$sortie" ||
    { rm -f "$orig"; return 1; }
  rm -f "$orig"
}

# m27_deploiement_a ESPACE DEPLOYMENT 'filtre jq sur le Deployment' — déployé, à jour, et filtre satisfait.
m27_deploiement_a() {
  wb_kubectl -n "$1" get deployment "$2" -o json 2>/dev/null | jq -e "
    ($3)
    and (.status.observedGeneration // 0) >= .metadata.generation
    and (.status.updatedReplicas // 0) == (.spec.replicas // 1)" >/dev/null 2>&1
}

# m27_patch_env ESPACE DEPLOYMENT VARIABLE VALEUR — opérations JSON 6902 qui posent VARIABLE=VALEUR dans le
# conteneur qui porte des variables MEDINOTIF_* (sinon le premier) ; env l'emporte sur envFrom.
m27_patch_env() {
  local d
  d="$(wb_kubectl -n "$1" get deployment "$2" -o json 2>/dev/null)" || return 1
  jq -c --arg v "$3" --arg val "$4" '
    (.spec.template.spec.containers | to_entries
     | (map(select([.value.env[]?.name, (.value.envFrom[]?.configMapRef.name // empty)] | any(test("MEDINOTIF|medinotif")))) + .)[0].key) as $i
    | .spec.template.spec.containers[$i] as $c
    | ([$c.env[]?.name] | index($v)) as $j
    | if $j != null then [{op: "replace", path: "/spec/template/spec/containers/\($i)/env/\($j)", value: {name: $v, value: $val}}]
      elif ($c.env // null) != null then [{op: "add", path: "/spec/template/spec/containers/\($i)/env/-", value: {name: $v, value: $val}}]
      else [{op: "add", path: "/spec/template/spec/containers/\($i)/env", value: [{name: $v, value: $val}]}] end' <<<"$d"
}

# ---------------------------------------------------------------------------
# PostgreSQL (recette) : psql dans le primaire, en superutilisateur par le socket local (comme kubectl cnpg psql)
# ---------------------------------------------------------------------------

m27_pg_primaire() {
  wb_kubectl -n "$_M27_NS_AGENDA" get cluster.postgresql.cnpg.io "$_M27_CLUSTER" -o jsonpath='{.status.currentPrimary}' 2>/dev/null | grep .
}

# m27_psql 'SQL' — exécute sur la base mediagenda du primaire ; sortie « -At » (une valeur par ligne).
m27_psql() {
  local p
  p="$(m27_pg_primaire)" || return 1
  printf '%s\n' "$1" | wb_kubectl -n "$_M27_NS_AGENDA" exec -i "$p" -c postgres -- psql -X -q -At -v ON_ERROR_STOP=1 -d mediagenda 2>/dev/null
}

# m27_cluster_sain — mediagenda-db (recette) : toutes les instances prêtes, état sain.
m27_cluster_sain() {
  wb_kubectl -n "$_M27_NS_AGENDA" get cluster.postgresql.cnpg.io "$_M27_CLUSTER" -o json 2>/dev/null | jq -e '
    (.status.readyInstances // 0) == .spec.instances and .spec.instances >= 2
    and (.status.phase // "") == "Cluster in healthy state"' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# RabbitMQ : API de gestion avec le compte par défaut de l'opérateur (bris de glace, Secret lu par
# l'administrateur du lab), commandes dans un nœud. Jamais sur le vhost de production.
# ---------------------------------------------------------------------------

_m27_rmq_cfg() {
  local s u p
  s="$(wb_kubectl -n "$_M27_NS_MSG" get secret rabbitmq-default-user -o json 2>/dev/null)" || return 1
  u="$(jq -r '.data.username // empty | @base64d' <<<"$s")"
  p="$(jq -r '.data.password // empty | @base64d' <<<"$s")"
  [[ -n "$u" && -n "$p" ]] || return 1
  printf 'user = "%s:%s"\n' "$u" "$p"
}
m27_rmq_admin_nom() {
  wb_kubectl -n "$_M27_NS_MSG" get secret rabbitmq-default-user -o json 2>/dev/null | jq -r '.data.username // empty | @base64d'
}

# m27_rmq MÉTHODE CHEMIN [CORPS_JSON] — appel de l'API de gestion (/api/CHEMIN).
m27_rmq() {
  local m="$1" chemin="$2" corps="${3:-}" cfg
  cfg="$(_m27_rmq_cfg)" || { wb_avert "compte par défaut de RabbitMQ illisible (Secret $_M27_NS_MSG/rabbitmq-default-user)"; return 1; }
  if [[ -n "$corps" ]]; then
    curl -sf --max-time 30 -X "$m" -H "Content-Type: application/json" --data-binary "$corps" \
      -K <(printf '%s\n' "$cfg") "$_M27_RMQ_URL/api/$chemin"
  else
    curl -sf --max-time 30 -X "$m" -K <(printf '%s\n' "$cfg") -H "Accept: application/json" "$_M27_RMQ_URL/api/$chemin"
  fi
}

# m27_rmq_file [FILE] — JSON de la file (vhost de recette).
m27_rmq_file() { m27_rmq GET "queues/$_M27_VHOST/$(_m27_enc "${1:-$_M27_FILE}")"; }

# m27_rmq_ctl ARGS… — rabbitmqctl/rabbitmq-queues dans le premier nœud (cookie Erlang, sans mot de passe).
m27_rmq_ctl() { wb_kubectl -n "$_M27_NS_MSG" exec "$_M27_RMQ_POD" -c rabbitmq -- "$@"; }

# m27_rmq_exporter EXX — export des définitions de la grappe et du vhost de recette, avant toute injection.
m27_rmq_exporter() {
  local d
  d="$(m27_etat "$1")"
  [[ -s "$d/definitions-vhost.json" ]] && return 0
  m27_rmq GET definitions >"$d/definitions-grappe.json" || { wb_avert "export des définitions impossible : rien n'est cassé"; return 1; }
  m27_rmq GET "definitions/$_M27_VHOST" >"$d/definitions-vhost.json" || return 1
  chmod 600 "$d"/definitions-*.json
  jq -e '.queues | length > 0' "$d/definitions-vhost.json" >/dev/null || return 1
  m27_journal "$1" "définitions exportées (grappe et vhost $_M27_VHOST)"
}

# m27_rmq_reimporter EXX — réimporte les définitions du vhost de recette (ajouts et mises à jour seulement).
m27_rmq_reimporter() {
  local d
  d="$(m27_etat "$1")"
  [[ -s "$d/definitions-vhost.json" ]] || return 0
  if m27_rmq POST "definitions/$_M27_VHOST" "$(cat "$d/definitions-vhost.json")" >/dev/null; then
    m27_journal "$1" "définitions du vhost $_M27_VHOST réimportées"
  else
    wb_avert "réimport des définitions impossible (copie : $d/definitions-vhost.json)"
  fi
}

# m27_rmq_permission_trouver UTILISATEUR — « CHEMIN<TAB>INDEX » de la Permission déclarée pour UTILISATEUR
# sur le vhost de recette, dans la topologie de plateforme/donnees.
m27_rmq_permission_trouver() {
  m27_doc_trouver "$_M27_DEPOT_DONNEES" "$_M27_TOPOLOGIE" \
    "(.kind == \"Permission\") and ((.spec.vhost // \"\") == \"$_M27_VHOST\")
     and (((.spec.user // \"\") == \"$1\") or ((.spec.userReference.name // \"\") | test(\"^$1$\")))"
}

# m27_rmq_politique_trouver — « CHEMIN<TAB>INDEX » de la Policy du vhost de recette qui s'applique à la file.
m27_rmq_politique_trouver() {
  m27_doc_trouver "$_M27_DEPOT_DONNEES" "$_M27_TOPOLOGIE" \
    "(.kind == \"Policy\") and ((.spec.vhost // \"/\") == \"$_M27_VHOST\")
     and ((.spec.applyTo // \"queues\") | test(\"^(queues|all|quorum_queues)$\"))
     and (.spec.pattern as \$p | \"$_M27_FILE\" | test(\$p))"
}

# m27_rmq_modifier_doc EXX CLÉ CHEMIN INDEX 'expression yq' "message" — applique l'expression (affectation,
# ex. « .spec.x = 1 » ou « .spec.y |= sub(…) ») au document INDEX du fichier de topologie (les autres sont
# recopiés) et le commite au nom de Lucas ; 10 si rien ne change.
m27_rmq_modifier_doc() {
  local ex="$1" cle="$2" chemin="$3" idx="$4" expr="$5" msg="$6" tmp
  tmp="$(m27_etat "$ex")/tmp-$cle"
  mkdir -p "$tmp"
  m27_gl_fichier "$_M27_DEPOT_DONNEES" "$chemin" >"$tmp/orig.yaml" || return 1
  IDX="$idx" yq "with(select(documentIndex == (strenv(IDX) | to_number)); $expr)" "$tmp/orig.yaml" >"$tmp/neuf.yaml" || return 1
  cmp -s "$tmp/orig.yaml" "$tmp/neuf.yaml" && return 10
  m27_commit "$ex" "$cle" "$_M27_DEPOT_DONNEES" "$msg" "$chemin" "$tmp/neuf.yaml"
}

# ---------------------------------------------------------------------------
# Témoin de trafic (espace wb-pannes) : la recette de MédiAgenda comme la verraient les centres
# ---------------------------------------------------------------------------

m27_image_agenda() {
  local img
  if [[ -n "${WB_M27_IMAGE_AGENDA:-}" ]]; then printf '%s\n' "$WB_M27_IMAGE_AGENDA"; return 0; fi
  img="$(wb_kubectl -n "$_M27_NS_AGENDA" get pods -o json 2>/dev/null | jq -r '
    [.items[].spec.containers[].image | select(test("/medisphere/mediagenda-api[:@]"))][0] // empty')"
  [[ -n "$img" ]] || return 1
  printf '%s\n' "$img"
}

# Une requête de créneaux par seconde, la liste toutes les trois, et toutes les dix secondes la création
# d'un rendez-vous factice (« Patient Témoin », praticien dr-temoin-N, dans 1 à 10 mois) suivie de son
# annulation : chaque création déclenche une demande de notification (M27-E08).
_m27_trafic_script() {
  cat <<'PY'
import json, os, random, ssl, time, urllib.error, urllib.request
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

CIBLE = os.environ["CIBLE"].rstrip("/")
CTX = ssl.create_default_context(cafile=os.environ.get("CA", "/etc/racine/racine.crt"))
PARIS = ZoneInfo("Europe/Paris")
STATS = {"ok": 0, "erreurs": 0, "crees": 0}


def requete(methode, chemin, corps=None):
    donnees = json.dumps(corps).encode() if corps is not None else None
    r = urllib.request.Request(CIBLE + chemin, data=donnees, method=methode,
                               headers={"Content-Type": "application/json", "User-Agent": "trafic-recette/1.0"})
    try:
        with urllib.request.urlopen(r, timeout=20, context=CTX) as rep:
            STATS["ok"] += 1
            return rep.status, rep.read()
    except urllib.error.HTTPError as e:
        STATS["erreurs"] += 1
        return e.code, b""
    except Exception as e:
        STATS["erreurs"] += 1
        print(json.dumps({"niveau": "WARNING", "message": "échec", "chemin": chemin, "erreur": str(e)}), flush=True)
        return 0, b""


def cycle_creation():
    jour = date.today() + timedelta(days=random.randint(30, 300))
    debut = datetime(jour.year, jour.month, jour.day, random.choice([8, 9, 10, 11, 14, 15, 16, 17]),
                     random.choice([0, 30]), tzinfo=PARIS)
    corps = {"patient": "Patient Témoin", "praticien": f"dr-temoin-{random.randint(1, 5)}",
             "debut": debut.isoformat(), "duree_minutes": 30, "motif": "contrôle"}
    statut, rep = requete("POST", "/api/v1/rendez-vous", corps)
    if statut == 201:
        STATS["crees"] += 1
        rdv = json.loads(rep)["id"]
        requete("DELETE", f"/api/v1/rendez-vous/{rdv}")


def main():
    print(json.dumps({"niveau": "INFO", "message": "démarrage", "cible": CIBLE}), flush=True)
    i, dernier = 0, time.monotonic()
    while True:
        i += 1
        jour = (date.today() + timedelta(days=random.randint(1, 14))).isoformat()
        requete("GET", f"/api/v1/creneaux?date={jour}&praticien=dr-temoin-{random.randint(1, 5)}")
        if i % 3 == 0:
            requete("GET", "/api/v1/rendez-vous?limite=20")
        if i % 10 == 0:
            cycle_creation()
        if time.monotonic() - dernier > 60:
            print(json.dumps({"niveau": "INFO", "message": "bilan", **STATS}), flush=True)
            dernier = time.monotonic()
        time.sleep(1)


if __name__ == "__main__":
    main()
PY
}

_m27_trafic_manifeste() {
  cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trafic-recette
  namespace: $_M27_NS_PANNES
  labels: {app.kubernetes.io/name: trafic-recette, medisphere.internal/ticket: PLAT-2819}
spec:
  replicas: 1
  selector: {matchLabels: {app.kubernetes.io/name: trafic-recette}}
  template:
    metadata:
      labels: {app.kubernetes.io/name: trafic-recette}
    spec:
      automountServiceAccountToken: false
      imagePullSecrets: [{name: harbor-pull}]
      securityContext: {runAsNonRoot: true, runAsUser: 10001, seccompProfile: {type: RuntimeDefault}}
      containers:
        - name: trafic
          image: $1
          command: ["python", "/trafic/trafic.py"]
          env:
            - {name: CIBLE, value: "${WB_M27_TRAFIC_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"}
            - {name: CA, value: /etc/racine/racine.crt}
          resources: {requests: {cpu: 10m, memory: 48Mi}, limits: {cpu: 200m, memory: 96Mi}}
          securityContext: {allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: {drop: ["ALL"]}}
          volumeMounts:
            - {name: script, mountPath: /trafic, readOnly: true}
            - {name: racine, mountPath: /etc/racine, readOnly: true}
      volumes:
        - {name: script, configMap: {name: trafic-recette}}
        - {name: racine, configMap: {name: racine-medisphere}}
EOF
}

m27_trafic_pret() {
  wb_kubectl -n "$_M27_NS_PANNES" get deploy trafic-recette -o json 2>/dev/null | jq -e '(.status.availableReplicas // 0) >= 1' >/dev/null 2>&1
}

# m27_trafic — crée le témoin s'il n'existe pas (espace, Secret harbor-pull, racine), puis attend qu'il tourne.
m27_trafic() {
  local img racine="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}" tmp
  if ! wb_kubectl -n "$_M27_NS_PANNES" get deploy trafic-recette >/dev/null 2>&1; then
    echo "Première injection du palier 4 : création du témoin de trafic dans l'espace $_M27_NS_PANNES (1 à 2 min)…"
    [[ -r "$racine" ]] || { echo "Racine MédiSphère illisible : $racine (WB_RACINE_PKI)." >&2; return 1; }
    img="$(m27_image_agenda)" || { echo "Image MédiAgenda introuvable : renseigne WB_M27_IMAGE_AGENDA dans lab/lab.env." >&2; return 1; }
    if ! wb_kubectl get namespace "$_M27_NS_PANNES" >/dev/null 2>&1; then
      wb_kubectl create namespace "$_M27_NS_PANNES" >/dev/null || return 1
      wb_kubectl label namespace "$_M27_NS_PANNES" pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null || return 1
    fi
    if ! wb_kubectl -n "$_M27_NS_PANNES" get secret harbor-pull >/dev/null 2>&1; then
      wb_kubectl -n "$_M27_NS_AGENDA" get secret harbor-pull -o json |
        jq --arg ns "$_M27_NS_PANNES" '{apiVersion, kind, type, data, metadata: {name: "harbor-pull", namespace: $ns}}' |
        wb_kubectl apply -f - >/dev/null || { echo "Secret harbor-pull introuvable dans $_M27_NS_AGENDA." >&2; return 1; }
    fi
    wb_kubectl -n "$_M27_NS_PANNES" create configmap racine-medisphere --from-file=racine.crt="$racine" \
      --dry-run=client -o yaml | wb_kubectl apply -f - >/dev/null || return 1
    tmp="$(mktemp -d)"
    _m27_trafic_script >"$tmp/trafic.py"
    wb_kubectl -n "$_M27_NS_PANNES" create configmap trafic-recette --from-file=trafic.py="$tmp/trafic.py" \
      --dry-run=client -o yaml | wb_kubectl apply -f - >/dev/null || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    _m27_trafic_manifeste "$img" | wb_kubectl apply -f - >/dev/null || return 1
  fi
  m27_attendre 180 m27_trafic_pret || {
    echo "Le témoin de trafic ($_M27_NS_PANNES/trafic-recette) ne démarre pas (kubectl -n $_M27_NS_PANNES describe pod) : rien n'est cassé." >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Santé avant injection
# ---------------------------------------------------------------------------

m27_api_prete() {
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${WB_M27_TRAFIC_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}/pret")" || code=""
  [[ "$code" == 200 ]]
}

m27_consommateur_present() {
  m27_rmq_file 2>/dev/null | jq -e '(.consumers // 0) >= 1' >/dev/null 2>&1
}

# m27_preparer QUOI… — préconditions communes (yq, témoin, base et API de recette saines) et propres à la
# panne : « base » (rien de plus), « messagerie » (consommateur présent), « valkey » (valkey-0 prêt).
# Pendant l'astreinte M27-E23 (_M27_ASTREINTE=1), break-E23 les a déjà faites.
m27_preparer() {
  local q
  if [[ -n "${_M27_ASTREINTE:-}" ]]; then return 0; fi
  command -v yq >/dev/null || { echo "yq (mikefarah) est requis sur adm01 pour les pannes du module 27." >&2; return 1; }
  m27_trafic || return 1
  m27_cluster_sain || { echo "mediagenda-db (recette) n'est pas sain : répare d'abord (kubectl cnpg status). Rien n'est cassé." >&2; return 1; }
  m27_attendre 120 m27_api_prete || { echo "MédiAgenda recette ne répond pas 200 sur /pret : la recette doit marcher avant d'être cassée." >&2; return 1; }
  for q in "$@"; do
    case "$q" in
      base) ;;
      messagerie)
        m27_attendre 120 m27_consommateur_present || { echo "La file $_M27_FILE ($_M27_VHOST) n'a pas de consommateur : répare d'abord (lab/bin/check 27 20)." >&2; return 1; }
        ;;
      valkey)
        wb_kubectl -n "$_M27_NS_AGENDA" get pod valkey-0 -o json 2>/dev/null |
          jq -e 'any(.status.conditions[]?; .type == "Ready" and .status == "True")' >/dev/null ||
          { echo "valkey-0 (recette) n'est pas prêt : répare d'abord (lab/bin/check 27 22)." >&2; return 1; }
        ;;
    esac
  done
}

# m27_debut EXX — mémorise l'heure de fin d'injection (epoch).
m27_debut() { m27_ecrire "$1" debut "$(date +%s)"; }

# m27_prom_positif 'PromQL' — au moins une valeur strictement positive.
m27_prom_positif() {
  prom_requete "$1" 2>/dev/null | jq -e '[.data.result[]?.value[1] | tonumber | select(. > 0)] | length > 0' >/dev/null 2>&1
}
