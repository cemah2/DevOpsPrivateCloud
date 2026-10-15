# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq et commandes entre apostrophes
#
# check-E21.sh — M12-E21 : Construire les images en CI sans mode privilégié
# À lancer depuis adm01. Lecture seule : API GitLab en GET (fichiers, pipelines, jobs), lecture de
# config.toml sur runner02 (sudo), API du registre de travail en GET (compte plateforme).

# shellcheck source=_m12-operationnel.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-operationnel.sh"

title "M12-E21 — Construire les images en CI sans mode privilégié"
require_cmd jq curl

# --- 1. Le gabarit ---------------------------------------------------------------------------------------------
_m12o_e21_tpl="$(_m12o_fichier plateforme/ci-templates templates/image.yml v1)"
check_cmd "plateforme/ci-templates (branche v1) : templates/image.yml avec .hadolint et .image-construction" \
  bash -c 'grep -Eq "^\.hadolint:" <<<"$1" && grep -Eq "^\.image-construction:" <<<"$1"' _ "$_m12o_e21_tpl"
check_cmd "image.yml : BuildKit sans privilège (buildctl-daemonless.sh, image rootless épinglée)" \
  bash -c 'grep -q "buildctl-daemonless.sh" <<<"$1" && grep -Eq "buildkit:v0\.34\.[0-9]+-rootless@sha256:" <<<"$1"' _ "$_m12o_e21_tpl"
check_cmd "image.yml : variables IMAGE, ETIQUETTES, FICHIER, CONTEXTE, ARGS_CONSTRUCTION, PLATEFORMES" \
  bash -c 'for v in IMAGE ETIQUETTES FICHIER CONTEXTE ARGS_CONSTRUCTION PLATEFORMES; do grep -Eq "^\s+$v:" <<<"$1" || exit 1; done' _ "$_m12o_e21_tpl"

# --- 2. Le runner --------------------------------------------------------------------------------------------------
_m12o_e21_conf="$(_m12o_ssh "$_M12O_RUNNER02" 'sudo -n cat /etc/gitlab-runner/config.toml')"
_m12o_e21_secopt="$(sed -nE 's/^\s*security_opt\s*=\s*(\[.*\])\s*$/\1/p' <<<"$_m12o_e21_conf" | head -n 1)"
check_cmd "runner02 : exceptions seccomp et apparmor accordées" \
  bash -c 'grep -Eq "seccomp[=:]unconfined" <<<"$1" && grep -Eq "apparmor[=:]unconfined" <<<"$1"' _ "$_m12o_e21_secopt"
check_cmd "runner02 : rien d'autre dans security_opt (pas de label=disable, systempaths…)" \
  bash -c '[ -n "$1" ] && [ "$(grep -o "\"[^\"]*\"" <<<"$1" | grep -Evc "^\"(seccomp|apparmor)[=:]unconfined\"$|^\"no-new-privileges(:true|=true)?\"$")" -eq 0 ]' _ "$_m12o_e21_secopt"
check_cmd "runner02 : toujours sans mode privilégié" \
  bash -c '[ -n "$1" ] && ! grep -Eq "^\s*privileged\s*=\s*true" <<<"$1"' _ "$_m12o_e21_conf"

# --- 3. Les projets ---------------------------------------------------------------------------------------------------
for _m12o_e21_p in mediagenda/api medidoc/medidoc; do
  _m12o_e21_ci="$(_m12o_fichier "$_m12o_e21_p" .gitlab-ci.yml)"
  check_cmd "$_m12o_e21_p (main) : .gitlab-ci.yml inclut templates/image.yml de plateforme/ci-templates" \
    bash -c 'grep -q "plateforme/ci-templates" <<<"$1" && grep -q "templates/image.yml" <<<"$1"' _ "$_m12o_e21_ci"
  check_cmd "$_m12o_e21_p (main) : aucun mot de passe dans .gitlab-ci.yml" \
    _m12o_absent "$_m12o_e21_ci" '(REGISTRE_MOT_DE_PASSE|PASSWORD|MOT_DE_PASSE)\s*:\s*["'"'"']?[A-Za-z0-9]{6,}'
  _m12o_e21_pl="$(_m12o_dernier_pipeline "$_m12o_e21_p")"
  check_cmd "$_m12o_e21_p : dernier pipeline de main réussi" _m12o_json "$_m12o_e21_pl" '.status == "success"'
  _m12o_e21_jobs="$(_m12o_jobs_pipeline "$_m12o_e21_p" "$(jq -r '.id // empty' <<<"${_m12o_e21_pl:-null}" 2>/dev/null || true)")"
  check_cmd "$_m12o_e21_p : job hadolint réussi" _m12o_json "$_m12o_e21_jobs" \
    '[.[] | select((.name | test("hadolint"; "i")) and .status == "success")] | length >= 1'
  check_cmd "$_m12o_e21_p : job de construction réussi sur un runner d'étiquette docker" _m12o_json "$_m12o_e21_jobs" \
    '[.[] | select((.name | test("image|constru|build|publi|push"; "i")) and .status == "success" and ((.tag_list // []) | index("docker")))] | length >= 1'
done

# --- 4. Le registre -------------------------------------------------------------------------------------------------------
check_cmd "adm01 : identifiants du registre lisibles ($_M12O_REGISTRE_ENV)" _m12o_registre_lisible
for _m12o_e21_d in mediagenda/api medidoc/medidoc; do
  check_cmd "registre : $_m12o_e21_d:1.0.0 en linux/amd64 et linux/arm64" _m12o_multi_plateformes "$_m12o_e21_d" 1.0.0
  check_cmd "registre : une image main-<SHA> de $_m12o_e21_d" \
    bash -c 'grep -Eq "^main-[0-9a-f]{7,}$" <<<"$1"' _ "$(_m12o_etiquettes "$_m12o_e21_d")"
done
check_cmd "plateforme/medisphere (main) : docs/conteneurs/construction-ci.md" \
  bash -c 'grep -Eiq "privil" <<<"$1" && grep -Eiq "seccomp" <<<"$1"' _ "$(_m12o_fichier plateforme/medisphere docs/conteneurs/construction-ci.md)"
