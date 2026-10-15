# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E20.sh — M17-E20 « Panne : le rendu du chart échoue »
#
# La panne crée dans ~/src/mediagenda-chart une branche locale « lucas/… » partie de HEAD, y commite au
# nom de Lucas Martin une « petite modif sans risque » et y laisse l'apprenant. Rien n'est poussé, la
# branche d'origine n'est pas touchée. Variantes :
#   1. values.yaml : config.cacheTtl passe de 60 à "60s" → refus par values.schema.json (type) ;
#   2. templates/deployment.yaml : « include "mediagenda.envConnexion" . | nindent 12 » devient
#      « | indent 12 » → la première variable se colle à « env: » : YAML invalide ;
#   3. templates/_helpers.tpl : le gabarit mediagenda.valkeyUrl lit .Values.externalValkey.uri au lieu
#      de .url → « required » échoue avec un message qui nomme pourtant une valeur bien présente
#      (et « helm lint » passe : le mode lint rend « required » non bloquant).
# Annulation : retour à la branche d'origine ; la branche de Lucas n'est supprimée que si son sommet
# est encore le commit injecté (sinon elle porte les corrections de l'apprenant).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m17-commun.sh
source "$WB_ROOT/modules/17-packaging/corrige/pannes/_m17-commun.sh"

_E20_DIR="charts/mediagenda"

# _e20_rendu — 0 si le chart de la copie de travail se rend avec les valeurs du pipeline.
_e20_rendu() {
  m17_helm template mediagenda "$_M17_CHART/$_E20_DIR" -n mediagenda-recette \
    --set medisphere.environnement=recette >/dev/null 2>&1
}

_mE20_une() {
  local v="$1" f br msg
  case "$v" in
    1)
      f="$_M17_CHART/$_E20_DIR/values.yaml"
      grep -Eq '^  cacheTtl: 60$' "$f" 2>/dev/null || return 10
      sed -i -E 's/^  cacheTtl: 60$/  cacheTtl: "60s"   # durée lisible (Lucas)/' "$f"
      br="lucas/ttl-lisible"; msg="feat: TTL du cache exprimé en durée lisible"
      ;;
    2)
      f="$_M17_CHART/$_E20_DIR/templates/deployment.yaml"
      grep -q 'include "mediagenda.envConnexion" . | nindent 12' "$f" 2>/dev/null || return 10
      sed -i 's/include "mediagenda.envConnexion" . | nindent 12/include "mediagenda.envConnexion" . | indent 12/' "$f"
      br="lucas/alignement"; msg="style: alignement des variables d'environnement"
      ;;
    3)
      f="$_M17_CHART/$_E20_DIR/templates/_helpers.tpl"
      grep -q '\.Values\.externalValkey\.url -}}' "$f" 2>/dev/null || return 10
      sed -i 's/\.Values\.externalValkey\.url -}}/.Values.externalValkey.uri -}}/' "$f"
      br="lucas/nommage-url"; msg="refactor: nommage cohérent des URL de connexion"
      ;;
  esac
  git -C "$_M17_CHART" rev-parse --verify --quiet "refs/heads/$br" >/dev/null && { git -C "$_M17_CHART" checkout --quiet -- .; return 10; }
  m17_branche_lucas "$_M17_CHART" "$br" "$msg" || { git -C "$_M17_CHART" checkout --quiet -- . 2>/dev/null || true; return 1; }
  m17_journal E20 "branche $br créée dans $_M17_CHART ($msg)"
}

_e20_injecter() {
  m17_outils git helm || return 1
  m17_git_propre "$_M17_CHART" || return 1
  [[ -d "$_M17_CHART/$_E20_DIR" ]] || { wb_avert "$_M17_CHART/$_E20_DIR introuvable (projet mediagenda/chart, M17-E03)"; return 1; }
  if ! _e20_rendu; then
    wb_avert "le chart de ta copie ne se rend pas avant la panne (dépendances construites ? « helm dependency build $_E20_DIR »)"
    return 1
  fi
  m17_essayer E20 3 "$1"
}

panne_E20_v1() { _e20_injecter 1; }
panne_E20_v2() { _e20_injecter 2; }
panne_E20_v3() { _e20_injecter 3; }

verifier_E20() { ! _e20_rendu; }

annuler_E20() { m17_branche_annuler E20; }

resume_E20() { echo "La branche laissée par Lucas dans la copie du chart ne se rend plus (helm template échoue)."; }

symptome_E20() {
  local br
  read -r _ br _ <<<"$(m17_lire E20 git)"
  wb_symptome "Ticket INC-4420 — De : Julien Petit" \
    "Lucas a laissé sa branche « ${br:-lucas/…} » dans ta copie de mediagenda/chart (~/src/mediagenda-chart)," \
    "et tu y es maintenant. Il m'a dit « petite modif sans risque ». Je dois livrer aujourd'hui :" \
    "« helm template » échoue, je ne comprends pas pourquoi. Corrige sur sa branche, par un nouveau commit," \
    "que je puisse ouvrir la MR." \
    "" \
    "Temps cible : 30 min. Contrôle : lab/bin/check 17 20"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 17 E20 3 "$@"; }
fi
