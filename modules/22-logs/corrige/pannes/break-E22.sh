# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # expressions yq, sed et LogQL entre apostrophes
# break-E22.sh — M22-E22 « Panne : les journaux d'une équipe ont disparu »
#
# Toujours par un commit de Lucas dans plateforme/observabilite, jamais en touchant aux données :
#   1. règles d'affectation du locataire dans la configuration d'Alloy (lignes « regex » qui citent
#      mediagenda) : MédiAgenda retiré de l'alternative « (mediagenda|medidoc)-.+ » (ou « mediagenda-… »
#      rendu inopérant) « parce qu'il a son propre pipeline » : les journaux de MédiAgenda partent dans le
#      locataire plateforme. Sans effet si aucune règle de ce genre n'est trouvée dans alloy/ ;
#   2. en-tête X-Scope-OrgID de la source Grafana « Loki — mediagenda » changé en « mediagenda-prod »
#      (locataire inexistant) dans le fichier qui la provisionne : Grafana n'affiche plus rien pour
#      l'équipe, Loki a tout. Sans effet si la source n'est pas provisionnée par un fichier du dépôt ;
#   3. surcharge max_query_lookback: 10m pour le locataire medidoc (« les requêtes de MédiDoc sur 30
#      jours fatiguent Loki ») : tout ce qui a plus de 10 minutes « disparaît » des requêtes de MédiDoc,
#      alors que rien n'est supprimé (la rétention n'est PAS touchée).
# Annulation : commit inverse si le fichier est encore exactement dans l'état injecté.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m22-commun.sh
source "$WB_ROOT/modules/22-logs/corrige/pannes/_m22-commun.sh"

# Variante 1 : des flux d'espaces mediagenda-* arrivent dans le locataire plateforme (5 dernières min).
_e22_v1_effective() {
  (($(m22_nb_lignes plateforme '{namespace=~"mediagenda-.+"}' 5m) > 0))
}
# Variante 2 : le ConfigMap provisionné par Grafana porte le faux locataire.
_e22_v2_effective() {
  wb_kubectl get configmaps -A -o json 2>/dev/null |
    jq -e '[.items[].data // {} | to_entries[] | .value | select(test("Loki — mediagenda") and test("mediagenda-prod"))] | length > 0' >/dev/null 2>&1 ||
    wb_kubectl -n supervision get secrets -o json 2>/dev/null |
    jq -e '[.items[].data // {} | to_entries[] | .value | @base64d | select(test("Loki — mediagenda") and test("mediagenda-prod"))] | length > 0' >/dev/null 2>&1
}
# Variante 3 : la limite publiée pour medidoc vaut 10m.
_e22_v3_effective() { [[ "$(m22_limite medidoc max_query_lookback)" == 10m ]]; }

_m22E22_une() {
  local n="$1" chemin
  case "$n" in
    1)
      chemin="$(m22_git_chercher 'regex.*mediagenda' | grep -E '^alloy/' | head -n 1)" || chemin=""
      [[ -n "$chemin" ]] || return 10
      _m22_transformer() {
        # Sur les règles « regex » qui affectent le locataire : MédiAgenda retiré de l'alternative
        # « (mediagenda|medidoc) » ou « mediagenda-… » rendu inopérant (« mediagenda_… »).
        sed -E '/regex/ { /mediagenda/ { s/\(mediagenda\|/(/g; s/\|mediagenda\)/)/g; s/mediagenda-/mediagenda_/g } }'
      }
      m22_git_modifier E22 "$chemin" "refactor(alloy): MédiAgenda a son pipeline dédié, plus besoin de l'affecter ici (M22-E22)

Le stage.match « mediagenda » s'occupe déjà de ses journaux. -- Lucas" || return $?
      m22_attendre 480 _e22_v1_effective || return 1
      ;;
    2)
      chemin="$(m22_git_chercher 'Loki — mediagenda' | head -n 1)" || chemin=""
      [[ -n "$chemin" ]] || return 10
      _m22_transformer() {
        local f
        f="$(mktemp)"
        cat >"$f"
        # Dans les 25 lignes qui suivent le nom de la source : la valeur de httpHeaderValue1 « mediagenda ».
        local l
        l="$(awk '/Loki — mediagenda/ { r = NR } r && NR > r && NR <= r + 25 && /httpHeaderValue1/ && /mediagenda/ { print NR; exit }' "$f")"
        if [[ -z "$l" ]]; then rm -f "$f"; return 10; fi
        sed -E "${l}s/(httpHeaderValue1[\"']?[[:space:]]*[:=][[:space:]]*)[\"']?mediagenda[\"']?/\1\"mediagenda-prod\"/" "$f"
        rm -f "$f"
      }
      m22_git_modifier E22 "$chemin" "fix(grafana): locataire de la source MédiAgenda aligné sur l'environnement de prod (M22-E22)

-- Lucas" || return $?
      m22_attendre 480 _e22_v2_effective || return 1
      ;;
    3)
      _m22_transformer() {
        local f
        f="$(mktemp)"
        cat >"$f"
        yq -e '.loki.runtimeConfig.overrides' "$f" >/dev/null 2>&1 || { rm -f "$f"; return 10; }
        yq '.loki.runtimeConfig.overrides.medidoc.max_query_lookback = "10m"' "$f"
        rm -f "$f"
      }
      m22_git_modifier E22 "$_M22_F_LOKI" "perf(loki): MédiDoc ne remonte pas si loin (M22-E22)

Les requêtes de MédiDoc sur 30 jours fatiguent Loki. -- Lucas" || return $?
      m22_attendre 420 _e22_v3_effective || return 1
      ;;
  esac
  m22_journal E22 "variante $n posée"
}

panne_E22_v1() { m22_preparer && m22_essayer E22 3 1; }
panne_E22_v2() { m22_preparer && m22_essayer E22 3 2; }
panne_E22_v3() { m22_preparer && m22_essayer E22 3 3; }

verifier_E22() {
  case "$WB_VAR" in
    1) _e22_v1_effective ;;
    2) _e22_v2_effective ;;
    3) _e22_v3_effective ;;
    *) return 1 ;;
  esac
}

annuler_E22() {
  m22_git_annuler E22 || true
  m22_journal E22 "annulation"
}

resume_E22() {
  case "${WB_VAR:-}" in
    3) echo "Dans Grafana, les journaux de MédiDoc de plus de quelques minutes ont « disparu »." ;;
    *) echo "L'équipe MédiAgenda ne voit plus aucun journal récent dans sa source Grafana." ;;
  esac
}

symptome_E22() {
  case "${WB_VAR:-}" in
    3)
      wb_symptome "Ticket INC-4922 — De : Julien Petit (pour l'équipe MédiDoc)" \
        "L'équipe MédiDoc ne retrouve plus ses journaux d'hier, ni même ceux de ce matin : dans" \
        "Grafana (source « Loki — medidoc »), seules les dernières minutes s'affichent. Ils ont" \
        "besoin des journaux de la semaine pour une réclamation client. Ont-ils été supprimés ?" \
        "Je ne veux surtout pas qu'on touche à la rétention sans comprendre." \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 22 22"
      ;;
    *)
      wb_symptome "Ticket INC-4922 — De : Julien Petit" \
        "Depuis ce matin, la source « Loki — mediagenda » de Grafana ne montre plus aucun journal" \
        "récent de MédiAgenda (dev, recette, prod). Les pods tournent et écrivent, kubectl logs" \
        "le montre. Les autres équipes voient leurs journaux. On a perdu nos journaux ?" \
        "" \
        "Temps cible : 30 min. Contrôle : lab/bin/check 22 22"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 22 E22 3 "$@"; }
fi
