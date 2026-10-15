# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E35.sh — M12-E35 « Panne : le conteneur s'arrête aussitôt »
#
# Pile de recette de ctr01 (/srv/recette, projet Compose « recette »), remise à sa version de
# référence avant l'injection. Variantes :
#   1. « alignement des noms » : la variable MEDIAGENDA_VALKEY_URL de l'API est renommée
#      MEDIAGENDA_VALKEY_URI dans compose.yaml → l'API s'arrête aussitôt (code 2, variable obligatoire
#      absente) et redémarre en boucle (restart: unless-stopped) ;
#   2. « simplification » : un « entrypoint: ["python -m mediagenda"] » (forme exec avec une seule
#      chaîne) est ajouté à l'API → le conteneur ne démarre même pas (exec: "python -m mediagenda":
#      executable file not found in $PATH, code 127, état created/exited) ;
#   3. « MédiDoc 1.1.0-rc1 » : le Dockerfile de MédiDoc est remplacé par celui de Lucas, sans
#      CGO_ENABLED=0 (binaire lié dynamiquement à la glibc) avec une image finale « scratch » →
#      « exec /medidoc: no such file or directory », code 255, redémarrage en boucle.
# Annulation : pile de recette remise à sa version de référence (et image de référence de MédiDoc).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m12-commun.sh
source "$WB_ROOT/modules/12-conteneurs/corrige/pannes/_m12-commun.sh"

_e35_dockerfile_rc1() {
  cat <<'EOF'
# syntax=docker/dockerfile:1
# MédiDoc 1.1.0-rc1 — Dockerfile « simplifié » (Lucas) : une seule commande de compilation,
# image finale minimale.

FROM golang:1.26-trixie AS construction
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath -ldflags "-s -w -X main.version=1.1.0-rc1" -o /out/medidoc ./cmd/medidoc

FROM scratch
COPY --from=construction /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=construction /out/medidoc /medidoc
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/medidoc"]
EOF
}

_mE35_une() {
  case "$1" in
    1)
      m12_compose_remplacer '      MEDIAGENDA_VALKEY_URL: "redis://valkey:6379/0"
      MEDIAGENDA_VERSION: "recette"' '      MEDIAGENDA_VALKEY_URI: "redis://valkey:6379/0"
      MEDIAGENDA_VERSION: "recette"' || return $?
      m12_compose up -d --no-deps --no-build api || true
      ;;
    2)
      m12_compose_remplacer '    image: recette/mediagenda-api:plateau
    restart: unless-stopped
    cap_drop: [ALL]' '    image: recette/mediagenda-api:plateau
    entrypoint: ["python -m mediagenda"]
    restart: unless-stopped
    cap_drop: [ALL]' || return $?
      # « up » échoue (le conteneur ne peut pas démarrer) : c'est la panne.
      m12_compose up -d --no-deps --no-build api || true
      ;;
    3)
      m12_exec "$_M12_CTR01" DOCKERFILE="$(_e35_dockerfile_rc1)" <<'EOF' || return 1
sauver "$R/doc/Dockerfile"
sauver "$R/compose.yaml"
printf '%s\n' "$DOCKERFILE" > "$R/doc/Dockerfile"
remplacer_ "$R/compose.yaml" "    image: recette/medidoc:plateau" "    image: recette/medidoc:1.1.0-rc1" || exit 10
dc build doc >>/var/lib/workbook/m12-compose.log 2>&1 || exit 1
dc up -d --no-deps doc >>/var/lib/workbook/m12-compose.log 2>&1 || true
journal "MédiDoc 1.1.0-rc1 (binaire dynamique sur scratch) déployé"
EOF
      ;;
  esac
}

# _e35_arrete — 0 si le service visé ne tourne pas normalement (arrêté, en boucle ou jamais démarré).
_e35_arrete() {
  local s=api e
  [[ "$WB_VAR" == 3 ]] && s=doc
  e="$(m12_etat_service "$s")"
  [[ "$e" != running* ]] || (( ${e##* } >= 1 ))
}

panne_E35_v1() { m12_recette_preparer && m12_essayer E35 3 1; }
panne_E35_v2() { m12_recette_preparer && m12_essayer E35 3 2; }
panne_E35_v3() { m12_recette_preparer && m12_essayer E35 3 3; }

verifier_E35() { sleep 10; m12_attendre 60 _e35_arrete; }

annuler_E35() {
  if [[ -z "${_M12_ASTREINTE:-}" ]]; then
    m12_recette_reinitialiser
  fi
  m12_exec "$_M12_CTR01" <<'EOF' >/dev/null 2>&1 || true
docker image rm recette/medidoc:1.1.0-rc1 >/dev/null 2>&1 || true
rm -f "$WB_DIR/$WB_EX".*
journal "annulation"
EOF
  m12_oublier E35
}

resume_E35() {
  case "${WB_VAR:-1}" in
    3) echo "Depuis le déploiement de MédiDoc 1.1.0-rc1 par Lucas, http://ctr01.par1.medisphere.internal:8080/healthz ne répond plus." ;;
    *) echo "L'API de recette de MédiAgenda (http://ctr01.par1.medisphere.internal:8000) ne répond plus depuis la dernière modification de compose.yaml." ;;
  esac
}

symptome_E35() {
  local detail
  case "$WB_VAR" in
    3) detail="Lucas a livré hier soir MédiDoc 1.1.0-rc1 sur la recette (« juste un Dockerfile plus simple »). Depuis, http://ctr01.par1.medisphere.internal:8080/healthz ne répond plus. Lucas : « l'image se construit sans erreur, je ne comprends pas »." ;;
    2) detail="Lucas a « simplifié » le service api du fichier compose.yaml de la recette hier soir. Depuis, plus rien ne répond sur http://ctr01.par1.medisphere.internal:8000, et « docker compose up » affiche une erreur qu'il n'a pas notée." ;;
    *) detail="Lucas a « aligné les noms de variables » dans compose.yaml de la recette hier soir. Depuis, plus rien ne répond sur http://ctr01.par1.medisphere.internal:8000 ; « docker compose ps » montre l'API qui redémarre sans cesse." ;;
  esac
  wb_symptome "Ticket INC-3941 — De : Julien Petit" \
    "$detail" \
    "La recette de ce matin est bloquée. Remets le service en route sans perdre la base de recette," \
    "et explique-moi comment on aurait pu le voir avant le déploiement." \
    "" \
    "Pile : ctr01, /srv/recette (sudo docker compose …). Temps cible : 30 min. Contrôle : lab/bin/check 12 35"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 12 E35 3 "$@"; }
fi
