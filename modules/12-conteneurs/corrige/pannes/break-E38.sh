# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M12-E38 « Panne : la construction échoue ou ignore le cache »
#
# Contexte de construction de l'API de recette : /srv/recette/api sur ctr01 (« docker compose build
# api »). Pile remise à sa version de référence avant l'injection. Variantes :
#   1. contexte : .dockerignore supprimé et une sauvegarde de 4 Gio (dump-recette-2026-10.sql,
#      fichier préalloué) laissée dans le répertoire → 4 Gio envoyés au constructeur, recopiés par
#      « COPY . . » à chaque modification du code, cache de construction qui gonfle ;
#   2. ordre des couches : Dockerfile « simplifié » (COPY . . avant l'installation des dépendances,
#      sans montage de cache) → toute modification du code relance le téléchargement de toutes les
#      dépendances ;
#   3. mandataire : compose.yaml transmet HTTP(S)_PROXY de l'ancien prestataire (proxy.infoger.lan,
#      introuvable) à la construction, et le cache de construction a été purgé (docker builder prune)
#      → « uv sync » ne peut plus rien télécharger : la construction échoue ;
#   4. .dockerignore : une ligne « *.lock » ajoutée (« fichiers de verrou de l'éditeur ») → uv.lock
#      n'est plus envoyé : « "/uv.lock": not found », la construction échoue.
# Annulation : fichiers de référence (pile réinstallée), fichier de 4 Gio supprimé.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m12-commun.sh
source "$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-commun.sh"

_e38_dockerfile_v2() {
  cat <<'EOF'
# syntax=docker/dockerfile:1
# Image de recette de MédiAgenda — version « simplifiée » (Lucas) : tout le projet d'un coup.

FROM python:3.13-slim-trixie AS construction
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/app/.venv
WORKDIR /app
COPY . .
RUN uv sync --locked --no-dev --no-editable

FROM python:3.13-slim-trixie
RUN useradd --system --uid 10001 --user-group --no-create-home --home-dir /app mediagenda
WORKDIR /app
COPY --from=construction /app/.venv /app/.venv
COPY migrations /app/migrations
ENV PATH=/app/.venv/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    MEDIAGENDA_MIGRATIONS_DIR=/app/migrations
USER 10001:10001
EXPOSE 8000
ENTRYPOINT ["python", "-m", "mediagenda"]
EOF
}

_mE38_une() {
  case "$1" in
    1)
      m12_exec "$_M12_CTR01" <<'EOF' || return $?
[ -f "$R/api/.dockerignore" ] || exit 10
sauver "$R/api/.dockerignore"
rm -f "$R/api/.dockerignore"
fallocate -l 4G "$R/api/dump-recette-2026-10.sql" || exit 1
touch -d '2 days ago' "$R/api/dump-recette-2026-10.sql"
journal ".dockerignore supprimé, fichier de 4 Gio dans le contexte"
EOF
      ;;
    2)
      m12_exec "$_M12_CTR01" DOCKERFILE="$(_e38_dockerfile_v2)" <<'EOF' || return $?
grep -q -- '--no-install-project' "$R/api/Dockerfile" || exit 10
sauver "$R/api/Dockerfile"
printf '%s\n' "$DOCKERFILE" > "$R/api/Dockerfile"
journal "Dockerfile de l'API réordonné (COPY . . avant les dépendances, sans cache)"
EOF
      ;;
    3)
      m12_compose_remplacer '    build:
      context: ./api' '    build:
      context: ./api
      # Repris du vieux projet InfoGér (Lucas)
      args:
        HTTP_PROXY: http://proxy.infoger.lan:3128
        HTTPS_PROXY: http://proxy.infoger.lan:3128' || return $?
      m12_exec "$_M12_CTR01" <<'EOF' || return 1
docker builder prune -af >/dev/null 2>&1 || exit 1
journal "proxy InfoGér dans build.args de l'API, cache de construction purgé"
EOF
      ;;
    4)
      m12_exec "$_M12_CTR01" <<'EOF' || return $?
[ -f "$R/api/.dockerignore" ] || exit 10
sauver "$R/api/.dockerignore"
printf '%s\n' "# Fichiers de verrou de l'éditeur (Lucas)" "*.lock" >> "$R/api/.dockerignore"
journal "*.lock ajouté à .dockerignore"
EOF
      ;;
  esac
}

# _e38_casse — la variante est-elle effective ? (3 et 4 : la construction échoue réellement)
_e38_casse() {
  m12_exec "$_M12_CTR01" VAR="$WB_VAR" <<'EOF' >/dev/null 2>&1
case "$VAR" in
  1) [ ! -e "$R/api/.dockerignore" ] && [ -f "$R/api/dump-recette-2026-10.sql" ] ;;
  2) ! grep -q -- '--no-install-project' "$R/api/Dockerfile" ;;
  *) ! timeout 600 docker compose -f "$R/compose.yaml" --project-directory "$R" build api </dev/null ;;
esac
EOF
}

panne_E38_v1() { m12_recette_preparer && m12_essayer E38 4 1; }
panne_E38_v2() { m12_recette_preparer && m12_essayer E38 4 2; }
panne_E38_v3() { m12_recette_preparer && m12_essayer E38 4 3; }
panne_E38_v4() { m12_recette_preparer && m12_essayer E38 4 4; }

verifier_E38() { _e38_casse; }

annuler_E38() {
  m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1 || true
rm -f "$R/api/dump-recette-2026-10.sql"
rm -f "$WB_DIR/$WB_EX".*
journal "annulation"
EOF
  m12_recette_reinitialiser
  m12_oublier E38
}

resume_E38() {
  echo "La reconstruction de l'image de recette de l'API (docker compose build api) échoue ou n'en finit plus."
}

symptome_E38() {
  local detail
  case "$WB_VAR" in
    1) detail="Depuis hier, « docker compose build api » met plusieurs minutes au lieu de quelques secondes dès qu'on touche au code (et la première fois même sans rien toucher), et le disque de ctr01 se remplit à chaque essai." ;;
    2) detail="Depuis que Lucas a « simplifié » le Dockerfile, chaque modification d'une seule ligne de code relance le téléchargement de toutes les dépendances : plus d'une minute par essai au lieu de quelques secondes." ;;
    *) detail="Depuis ce matin, « docker compose build api » échoue. Lucas a « repris des réglages de l'ancien projet » et « fait de la place » sur ctr01 hier soir." ;;
  esac
  wb_symptome "Ticket INC-3944 — De : Julien Petit" \
    "$detail" \
    "Sur ctr01, dans /srv/recette : sudo docker compose build api. L'image doit se reconstruire" \
    "correctement ET vite. Explique-moi aussi comment on s'en serait aperçu en revue." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 12 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 12 E38 4 "$@"; }
fi
