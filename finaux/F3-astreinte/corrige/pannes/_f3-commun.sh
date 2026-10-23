# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq, yq et scripts distants entre apostrophes
# _f3-commun.sh — fonctions PARTAGÉES par les scripts de panne du final F3 (break-S03 à break-S13).
# Préfixe : _f3p_. Sourcé par break-SXX.sh APRÈS lab/lib/pannes-lib.sh (wb_exec, wb_kubectl, wb_avert,
# wb_symptome, WB_EX, WB_VAR…) ; lab/bin/break a déjà chargé lab/lib/check-lib.sh (remote, kube,
# am_api, prom_requete, gitlab_api…). Charge aussi checks/_f3-sante.sh (contrôle de santé _f3s_).
# Rappel : lab/bin/break tourne avec « set -euo pipefail » ; les fonctions d'annulation sont appelées
# hors de tout « if » : aucune commande n'y échoue sans « || true ».
#
# Règles (CONVENTIONS §8, §11.10, §11.11 ; PLAN §4.10 à §4.14 « Pannes ») :
#   - une injection F3 n'a lieu que si le lab est SAIN (_f3p_preparer : contrôle de santé de S01) et si
#     AUCUNE autre panne n'est active (une panne à la fois dans tout le lab, modules compris) ;
#   - tout ce qui est modifié est sauvegardé AVANT (état local ~/.local/state/workbook/F3-SXX/, 700 ;
#     wb_k8s_sauver pour les objets ; « sauver » de pannes-lib sur les hôtes) ;
#   - une modification de dépôt est un COMMIT IDENTIFIABLE (auteur Lucas Martin ou Julien Petit selon
#     l'histoire, marqueur « F3-SXX » dans le message) ; annulation par commit inverse, SEULEMENT si le
#     fichier porte encore exactement le contenu injecté (une réparation n'est jamais défaite), jamais de
#     réécriture d'historique ; si main refuse la poussée directe, MR fusionnée après son pipeline ;
#     si le pipeline refuse la MR, la variante est « sans effet » (la CI a fait son travail : code 10) ;
#   - production : une panne qui touche (même indirectement) mediagenda-db de mediagenda-prod exige une
#     sauvegarde CloudNativePG « completed » de moins de 26 h (_f3p_sauvegarde_prod, qui en lance une
#     sinon) ; aucune donnée applicative modifiée ; kms01 jamais touché ; aucun message perdu ;
#   - l'auto-synchronisation d'Argo CD n'est jamais désactivée ; on rafraîchit ou on synchronise.
#
# Fonctions :
#   _f3p_etat SXX / _f3p_ecrire SXX CLÉ VAL / _f3p_lire SXX CLÉ / _f3p_oublier SXX CLÉ / _f3p_journal SXX msg
#   _f3p_attendre SECONDES cmd…        relance toutes les 10 s jusqu'au succès ou au délai
#   _f3p_essayer SXX NB DÉPART         variantes successives (fonctions _f3p_SXX_une N et _f3p_SXX_defaire N ;
#                                      code 10 = « sans effet sur ce lab », on passe à la suivante)
#   _f3p_preparer SXX [outils…]        outils présents, aucune panne active, lab sain (sinon refus)
#   _f3p_symptome SXX INC "titre" lignes…   symptôme + rappel (main courante, messages, clôture)
#   GitLab : _f3p_gl, _f3p_gl_fichier, _f3p_gl_chercher, _f3p_commit, _f3p_commit_actif, _f3p_retablir
#   Argo CD : _f3p_apps_du_depot PROJET, _f3p_rafraichir APP…, _f3p_app_saine APP
#   Production : _f3p_sauvegarde_prod, _f3p_pg_primaire ESPACE, _f3p_psql ESPACE 'SQL'
#   Mesure : _f3p_latence URL N [PARALLÈLES] (médiane en secondes, requêtes « cache manqué »)
#   Alertmanager : _f3p_am MÉTHODE CHEMIN [JSON]

# Contrôle de santé partagé avec les checks.
# shellcheck source=../../checks/_f3-sante.sh
source "$WB_ROOT/finaux/F3-astreinte/checks/_f3-sante.sh"

# shellcheck disable=SC2034  # utilisées par les scripts qui sourcent ce fichier
{
  _F3P_PROD=mediagenda-prod
  _F3P_RECETTE=mediagenda-recette
  _F3P_CLUSTER=mediagenda-db
  _F3P_POOLER=mediagenda-db-pooler-rw
  _F3P_URL_PROD="${WB_F3_PROD_URL:-https://mediagenda.apps.par1.medisphere.internal}"
  _F3P_URL_RECETTE="${WB_F3_RECETTE_URL:-https://mediagenda-recette.apps.par1.medisphere.internal}"
  _F3P_RACINE="${WB_RACINE_PKI:-/usr/local/share/ca-certificates/medisphere-root-ca.crt}"
  _F3P_API_SEL='app.kubernetes.io/name=mediagenda,app.kubernetes.io/component=api'
  _F3P_LUCAS_NOM="Lucas Martin"
  _F3P_LUCAS_MEL="lucas.martin@medisphere.internal"
  _F3P_JULIEN_NOM="Julien Petit"
  _F3P_JULIEN_MEL="julien.petit@medisphere.internal"
  _F3P_AM_URL="${WB_AM_URL:-http://alertmanager.apps.par1.medisphere.internal:9093}"
}

# ---------------------------------------------------------------------------------------------
# État local (adm01), journal, attente, variantes
# ---------------------------------------------------------------------------------------------

_f3p_etat() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/F3-$1"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$d"
}
_f3p_ecrire() {
  local d
  d="$(_f3p_etat "$1")"
  (umask 077 && printf '%s\n' "$3" >"$d/$2")
}
_f3p_lire() {
  local f
  f="$(_f3p_etat "$1")/$2"
  if [[ -f "$f" ]]; then cat "$f"; fi
}
_f3p_oublier() {
  local d
  d="$(_f3p_etat "$1")"
  rm -rf -- "${d:?}/$2"
}
_f3p_journal() {
  local ex="$1"
  shift
  printf '%s %s [F3-%s variante %s] %s\n' "$(date -Is)" "$(hostname -s)" "$ex" "${WB_VAR:-?}" "$*" >>"$(_f3p_etat "$ex")/journal"
}

_f3p_attendre() {
  local max="$1" t=0
  shift
  while ((t < max)); do
    if "$@"; then return 0; fi
    sleep 10
    t=$((t + 10))
  done
  "$@"
}

# _f3p_essayer SXX NB DÉPART
_f3p_essayer() {
  local ex="$1" nb="$2" depart="$3" i n rc
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    rc=0
    WB_VAR="$n"
    "_f3p_${ex}_une" "$n" || rc=$?
    if ((rc == 0)); then
      WB_VAR="$n"
      _f3p_ecrire "$ex" variante "$n"
      return 0
    fi
    if declare -F "_f3p_${ex}_defaire" >/dev/null; then "_f3p_${ex}_defaire" "$n" || true; fi
    ((rc == 10)) || return 1
    _f3p_journal "$ex" "variante $n sans effet sur ce lab, essai de la suivante"
  done
  wb_avert "aucune variante de F3-$ex n'a d'effet sur ce lab (configuration différente du corrigé)"
  return 1
}

# _f3p_outils [outils…] — outils présents sur adm01 (yq de mikefarah).
_f3p_outils() {
  local c
  for c in kubectl jq curl yq ssh "$@"; do
    command -v "$c" >/dev/null 2>&1 || { echo "outil manquant sur adm01 : $c" >&2; return 1; }
  done
  yq --version 2>/dev/null | grep -q 'mikefarah' || { echo "yq de mikefarah (v4) attendu sur adm01" >&2; return 1; }
}

# _f3p_pannes_actives — liste des pannes marquées actives (modules et finaux), une par ligne.
_f3p_pannes_actives() {
  local d="${XDG_STATE_HOME:-$HOME/.local/state}/workbook/pannes-actives"
  [[ -d "$d" ]] || return 0
  find "$d" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
}

_F3P_REFUS="le lab n'est pas dans l'état attendu ; lance lab/bin/check F3 1"

# _f3p_preparer SXX [outils…] — contrôle préalable de TOUTE injection F3. Refuse (code 1) si un outil
# manque, si une panne est déjà active, ou si le contrôle de santé de S01 n'est pas vert.
_f3p_preparer() {
  local ex="$1" actives
  shift
  _f3p_outils "$@" || { echo "Injection refusée : $_F3P_REFUS (outils)." >&2; return 1; }
  actives="$(_f3p_pannes_actives | grep -vx "F3-$ex" || true)"
  if [[ -n "$actives" ]]; then
    {
      echo "Injection refusée : une panne est déjà active ($(paste -sd' ' - <<<"$actives"))."
      echo "Une seule panne à la fois : répare-la, vérifie, puis clos-la (lab/bin/break … --annuler)."
    } >&2
    return 1
  fi
  echo "Contrôle de santé préalable…"
  if ! _f3s_sain; then
    echo "Injection refusée : $_F3P_REFUS" >&2
    return 1
  fi
  _f3p_ecrire "$ex" debut "$(date +%s)"
}

# _f3p_symptome SXX INC "titre" lignes… — symptôme suivi du rappel commun à tous les incidents.
_f3p_symptome() {
  local ex="$1" inc="$2" titre="$3" n
  shift 3
  n="$((10#${ex#S}))"
  wb_symptome "$titre" "$@" \
    "" \
    "Rappels : ouvre $inc dans la main courante (docs/exploitation/journal/, entrée [ouverture]), qualifie" \
    "la gravité, envoie les messages d'état au rythme de ta procédure (objet « [$inc] … »), consigne chaque" \
    "action et décision. Une fois réparé : lab/bin/check F3 $n, puis lab/bin/break F3 $n --annuler" \
    "pour clore l'injection (l'annulation ne défait jamais ta réparation)."
}

# ---------------------------------------------------------------------------------------------
# GitLab (jeton d'administration du lab) : commits identifiables et commits inverses
# ---------------------------------------------------------------------------------------------

_f3p_enc() { jq -rn --arg v "$1" '$v | @uri'; }

_f3p_gl_cfg() {
  local f="${WB_GITLAB_ADMIN_TOKEN_FILE:-$HOME/.config/workbook/gitlab-admin.token}"
  [[ -r "$f" ]] || { wb_avert "jeton GitLab d'administration illisible : $f (WB_GITLAB_ADMIN_TOKEN_FILE)"; return 1; }
  printf 'header = "PRIVATE-TOKEN: %s"\n' "$(tr -d '[:space:]' <"$f")"
}

# _f3p_gl MÉTHODE CHEMIN — API v4 ; corps JSON sur l'entrée standard pour POST/PUT.
_f3p_gl() {
  local m="$1" url="${WB_GITLAB_URL:-https://git01.par1.medisphere.internal}/api/v4/$2" cfg
  cfg="$(_f3p_gl_cfg)" || return 1
  if [[ "$m" == GET || "$m" == DELETE ]]; then
    curl -sf --max-time 30 -X "$m" -K <(printf '%s\n' "$cfg") "$url" </dev/null
  else
    curl -sf --max-time 60 -X "$m" -H "Content-Type: application/json" --data-binary @- -K <(printf '%s\n' "$cfg") "$url"
  fi
}

_f3p_gl_fichier() {
  _f3p_gl GET "projects/$(_f3p_enc "$1")/repository/files/$(_f3p_enc "$2")/raw?ref=${3:-main}"
}

# _f3p_gl_chercher PROJET 'texte' — chemins des fichiers de main qui contiennent le texte (recherche
# de blobs du projet ; repli : parcours des YAML de l'arbre).
_f3p_gl_chercher() {
  local p r f page=1
  p="$(_f3p_enc "$1")"
  r="$(_f3p_gl GET "projects/$p/search?scope=blobs&search=$(_f3p_enc "$2")&per_page=50" 2>/dev/null)" || r=""
  if [[ -n "$r" ]] && jq -e 'length > 0' <<<"$r" >/dev/null 2>&1; then
    jq -r '.[].path' <<<"$r" | sort -u
    return 0
  fi
  while ((page <= 20)); do
    r="$(_f3p_gl GET "projects/$p/repository/tree?ref=main&recursive=true&per_page=100&page=$page" 2>/dev/null)" || return 0
    while IFS= read -r f; do
      _f3p_gl_fichier "$1" "$f" 2>/dev/null | grep -qF -- "$2" && printf '%s\n' "$f"
    done < <(jq -r '.[]? | select(.type == "blob") | .path | select(test("\\.ya?ml$|\\.txt$"))' <<<"$r")
    (($(jq 'length' <<<"$r") < 100)) && return 0
    page=$((page + 1))
  done
}

# _f3p_gl_pousser PROJET MESSAGE NOM COURRIEL ACTIONS_JSON — commit sur main ; si refusé, branche +
# MR fusionnée après son pipeline (≤ 15 min). Code 10 si la MR n'a pas pu être fusionnée (CI rouge).
_f3p_gl_pousser() {
  local p msg="$2" nom="$3" mel="$4" actions="$5" br r iid i etat
  p="$(_f3p_enc "$1")"
  if jq -n --arg m "$msg" --arg n "$nom" --arg e "$mel" --argjson a "$actions" \
    '{branch: "main", commit_message: $m, author_name: $n, author_email: $e, actions: $a}' |
    _f3p_gl POST "projects/$p/repository/commits" >/dev/null 2>&1; then
    return 0
  fi
  br="wb-f3-$(date +%s)-$RANDOM"
  jq -n --arg b "$br" --arg m "$msg" --arg n "$nom" --arg e "$mel" --argjson a "$actions" \
    '{branch: $b, start_branch: "main", commit_message: $m, author_name: $n, author_email: $e, actions: $a}' |
    _f3p_gl POST "projects/$p/repository/commits" >/dev/null || return 1
  r="$(jq -n --arg b "$br" --arg t "${msg%%$'\n'*}" \
    '{source_branch: $b, target_branch: "main", title: $t, remove_source_branch: true}' |
    _f3p_gl POST "projects/$p/merge_requests")" || return 1
  iid="$(jq -r '.iid' <<<"$r")"
  for ((i = 0; i < 90; i++)); do
    sleep 10
    printf '{"auto_merge": true}' | _f3p_gl PUT "projects/$p/merge_requests/$iid/merge" >/dev/null 2>&1 ||
      printf '{"merge_when_pipeline_succeeds": true}' | _f3p_gl PUT "projects/$p/merge_requests/$iid/merge" >/dev/null 2>&1 || true
    etat="$(_f3p_gl GET "projects/$p/merge_requests/$iid" | jq -r '.state' 2>/dev/null)" || etat=""
    [[ "$etat" == merged ]] && return 0
    [[ "$etat" == closed ]] && break
    if ((i > 6)); then
      # pipeline de la MR en échec : la CI a refusé le changement, on referme proprement
      if _f3p_gl GET "projects/$p/merge_requests/$iid/pipelines" 2>/dev/null | jq -e '.[0].status == "failed"' >/dev/null 2>&1; then
        break
      fi
    fi
  done
  _f3p_gl PUT "projects/$p/merge_requests/$iid" <<<'{"state_event": "close"}' >/dev/null 2>&1 || true
  _f3p_gl DELETE "projects/$p/repository/branches/$(_f3p_enc "$br")" >/dev/null 2>&1 || true
  wb_avert "la MR !$iid de $1 n'a pas été fusionnée (pipeline refusé ou trop long) : refermée"
  return 10
}

# _f3p_commit SXX CLÉ PROJET "message" lucas|julien CHEMIN FICHIER_LOCAL [CHEMIN FICHIER_LOCAL…]
_f3p_commit() {
  local ex="$1" cle="$2" projet="$3" msg="$4" qui="$5" d actions='[]' chemin local_ n=0 action nom mel rc=0
  shift 5
  if [[ "$qui" == julien ]]; then nom="$_F3P_JULIEN_NOM" mel="$_F3P_JULIEN_MEL"; else nom="$_F3P_LUCAS_NOM" mel="$_F3P_LUCAS_MEL"; fi
  d="$(_f3p_etat "$ex")/git-$cle"
  rm -rf -- "$d"
  mkdir -p "$d" && chmod 700 "$d"
  printf '%s\n' "$projet" >"$d/projet"
  : >"$d/fichiers"
  while (($# >= 2)); do
    chemin="$1" local_="$2"
    shift 2
    n=$((n + 1))
    if _f3p_gl_fichier "$projet" "$chemin" >"$d/orig-$n" 2>/dev/null; then
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
  _f3p_gl_pousser "$projet" "$msg

F3-$ex" "$nom" "$mel" "$actions" || rc=$?
  if ((rc != 0)); then
    rm -rf -- "$d"
    return "$rc"
  fi
  : >"$d/injecte"
  _f3p_journal "$ex" "commit ($qui) sur $projet : $(cut -f2 "$d/fichiers" | paste -sd' ' -) [$cle]"
}

# _f3p_commit_actif SXX CLÉ — au moins un fichier porte encore exactement le contenu injecté.
_f3p_commit_actif() {
  local d projet n chemin f r=1
  d="$(_f3p_etat "$1")/git-$2"
  [[ -f "$d/injecte" ]] || return 1
  projet="$(<"$d/projet")"
  while IFS=$'\t' read -r n chemin; do
    f="$(mktemp)"
    if _f3p_gl_fichier "$projet" "$chemin" >"$f" 2>/dev/null && cmp -s "$f" "$d/injecte-$n"; then r=0; fi
    rm -f "$f"
  done <"$d/fichiers"
  return "$r"
}

# _f3p_retablir SXX CLÉ — commit inverse des fichiers encore dans l'état injecté.
_f3p_retablir() {
  local ex="$1" cle="$2" d projet n chemin actions='[]' f
  d="$(_f3p_etat "$ex")/git-$cle"
  [[ -f "$d/fichiers" ]] || return 0
  projet="$(<"$d/projet")"
  while IFS=$'\t' read -r n chemin; do
    f="$(mktemp)"
    if _f3p_gl_fichier "$projet" "$chemin" >"$f" 2>/dev/null && cmp -s "$f" "$d/injecte-$n"; then
      if [[ -e "$d/absent-$n" ]]; then
        actions="$(jq --arg c "$chemin" '. + [{action: "delete", file_path: $c}]' <<<"$actions")"
      else
        actions="$(jq --arg c "$chemin" --rawfile t "$d/orig-$n" '. + [{action: "update", file_path: $c, content: $t}]' <<<"$actions")"
      fi
    else
      _f3p_journal "$ex" "annulation : $projet/$chemin modifié depuis la panne, laissé tel quel"
    fi
    rm -f "$f"
  done <"$d/fichiers"
  if [[ "$(jq 'length' <<<"$actions")" -gt 0 ]]; then
    _f3p_gl_pousser "$projet" "Annulation de l'injection F3-$ex (lab/bin/break F3 $((10#${ex#S})) --annuler)" \
      "Lab workbook" "workbook@medisphere.internal" "$actions" ||
      wb_avert "commit inverse impossible sur $projet : remets toi-même le contenu d'origine (copies : $d)"
  fi
  rm -rf -- "$d"
  _f3p_journal "$ex" "annulation des commits [$cle]"
}

# ---------------------------------------------------------------------------------------------
# Argo CD
# ---------------------------------------------------------------------------------------------

# _f3p_apps_du_depot PROJET — Applications dont une source pointe vers le dépôt PROJET.
_f3p_apps_du_depot() {
  wb_kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null |
    jq -r --arg p "$1" '.items[] | select([.spec.source.repoURL?, .spec.sources[]?.repoURL] | map(select(. != null)) | any(test($p))) | .metadata.name'
}

_f3p_rafraichir() {
  local a
  for a in "$@"; do
    [[ -n "$a" ]] || continue
    wb_kubectl -n argocd annotate applications.argoproj.io "$a" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
  done
}

_f3p_app_saine() {
  wb_kubectl -n argocd get applications.argoproj.io "$1" -o json 2>/dev/null |
    jq -e '.status.sync.status == "Synced" and .status.health.status == "Healthy"' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------------------------
# Production : sauvegarde préalable, PostgreSQL
# ---------------------------------------------------------------------------------------------

_f3p_sauvegarde_recente() {
  wb_kubectl -n "$_F3P_PROD" get backups.postgresql.cnpg.io -o json 2>/dev/null | jq -e --arg c "$_F3P_CLUSTER" '
    [.items[] | select(.spec.cluster.name == $c) | select(.status.phase == "completed")
     | select(((.status.stoppedAt // .status.completedAt // "1970-01-01T00:00:00Z") | sub("\\.[0-9]+"; "") | fromdateiso8601) > (now - 93600))]
    | length > 0' >/dev/null 2>&1
}

# _f3p_sauvegarde_prod — sauvegarde « completed » de moins de 26 h de mediagenda-db (prod), sinon en lance
# une (méthode plugin Barman Cloud, comme les sauvegardes planifiées du M16/M27) et attend 20 min au plus.
# La sauvegarde créée est CONSERVÉE (jamais supprimée).
_f3p_sauvegarde_prod() {
  local nom
  if _f3p_sauvegarde_recente; then return 0; fi
  nom="f3-avant-incident-$(date +%Y%m%d%H%M)"
  echo "Aucune sauvegarde récente de $_F3P_CLUSTER ($_F3P_PROD) : sauvegarde préalable $nom (jusqu'à 20 min)…"
  wb_kubectl apply -f - >/dev/null <<EOF || return 1
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: $nom
  namespace: $_F3P_PROD
  labels:
    medisphere.internal/origine: workbook-f3
spec:
  cluster:
    name: $_F3P_CLUSTER
  method: plugin
  pluginConfiguration:
    name: barman-cloud.cloudnative-pg.io
EOF
  if ! _f3p_attendre 1200 _f3p_sauvegarde_recente; then
    echo "La sauvegarde préalable de la production n'est pas « completed » : rien n'est cassé." >&2
    return 1
  fi
}

_f3p_pg_primaire() {
  wb_kubectl -n "$1" get clusters.postgresql.cnpg.io "$_F3P_CLUSTER" -o jsonpath='{.status.currentPrimary}' 2>/dev/null | grep .
}

# _f3p_psql ESPACE 'SQL' — sur la base mediagenda du primaire, en superutilisateur par le socket local
# (comme « kubectl cnpg psql ») ; sortie -At.
_f3p_psql() {
  local p
  p="$(_f3p_pg_primaire "$1")" || return 1
  printf '%s\n' "$2" | wb_kubectl -n "$1" exec -i "$p" -c postgres -- psql -X -q -At -v ON_ERROR_STOP=1 -d mediagenda 2>/dev/null
}

# _f3p_cnpg_sain ESPACE — toutes les instances prêtes, cluster sain.
_f3p_cnpg_sain() {
  wb_kubectl -n "$1" get clusters.postgresql.cnpg.io "$_F3P_CLUSTER" -o json 2>/dev/null | jq -e '
    (.status.readyInstances // 0) == .spec.instances and (.status.phase // "") == "Cluster in healthy state"' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------------------------
# Mesure côté utilisateur
# ---------------------------------------------------------------------------------------------

# _f3p_latence URL N [PARALLÈLES=1] — médiane (s) de N requêtes de créneaux qui MANQUENT le cache
# (praticien aléatoire) ; « 99 » pour une requête en échec ou au-delà de 20 s.
_f3p_latence() {
  local url="$1" n="$2" par="${3:-1}" jour tmp i
  jour="$(date -d '+30 days' +%F)"
  tmp="$(mktemp)"
  for ((i = 0; i < n; i++)); do
    (
      t="$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --max-time 20 --cacert "$_F3P_RACINE" \
        "$url/api/v1/creneaux?date=$jour&praticien=sonde-f3-$RANDOM$RANDOM" 2>/dev/null)" || t="000 99"
      read -r code duree <<<"$t"
      if [[ "$code" == 200 ]]; then echo "$duree"; else echo 99; fi
    ) >>"$tmp" &
    if (((i + 1) % par == 0)); then wait; fi
  done
  wait
  sort -n "$tmp" | awk '{v[NR] = $1} END {if (NR == 0) print 99; else print v[int((NR + 1) / 2)]}'
  rm -f "$tmp"
}

# _f3p_superieur A B — vrai si A > B (nombres décimaux).
_f3p_superieur() { awk -v a="$1" -v b="$2" 'BEGIN {exit !(a > b)}'; }

# ---------------------------------------------------------------------------------------------
# Alertmanager du cluster (écriture : silences)
# ---------------------------------------------------------------------------------------------

_f3p_am() {
  local m="$1" chemin="$2" corps="${3:-}"
  if [[ -n "$corps" ]]; then
    printf '%s' "$corps" | curl -sf --max-time 20 -X "$m" -H "Content-Type: application/json" --data-binary @- "$_F3P_AM_URL/api/v2/$chemin"
  else
    curl -sf --max-time 20 -X "$m" -H "Accept: application/json" "$_F3P_AM_URL/api/v2/$chemin"
  fi
}
