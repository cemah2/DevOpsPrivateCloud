# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-E38.sh — M21-E38 « Panne : Prometheus déborde »
#
# L'application témoin (wb-pannes, 2 pods) se met à exposer mediagenda_rapports_requetes_total avec une
# étiquette à valeurs non bornées par nature, mais BORNÉE ici à 30 000 valeurs par pod (60 000
# séries au plus, atteintes en 3 minutes : 2 500 nouvelles valeurs par pod et par tranche de 15 s,
# chaque valeur ne revient qu'une collecte sur douze : c'est du « churn »). La borne est choisie pour
# rester sous la limite mémoire de Prometheus d'E30 (budget de 300 000 séries pour 3 Gio) : la panne
# doit se voir, pas faire tomber les deux réplicas en OOM (le rejeu du WAL les ferait retomber) :
#   1. un identifiant de requête (requete_id) ;
#   2. le chemin HTTP brut, identifiant de rendez-vous compris (chemin="/api/v1/rendezvous/123456") ;
#   3. l'adresse de courriel du patient (utilisateur="patient000123@exemple.invalid") : cardinalité
#      ET donnée personnelle dans la supervision (RGPD, HDS).
# Rien n'est supprimé : les séries déjà ingérées quittent la tête à la compaction suivante et restent
# dans les blocs (locaux puis Thanos) jusqu'à leur rétention. Annulation : retour de l'état témoin à
# « cardinalite: aucune » (les relabelings posés par l'apprenant restent).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m21-commun.sh
source "$WB_ROOT/modules/21-metriques/corrige/pannes/_m21-commun.sh"

_E38_GENRES=(- requete_id chemin utilisateur)
_E38_TETE='max(prometheus_tsdb_head_series{namespace="supervision"})'

_e38_tete() { m21_prom_valeur "$_E38_TETE" | cut -d. -f1; }
_e38_deborde() {
  local b t
  b="$(m21_lire E38 base)"
  t="$(_e38_tete)"
  [[ -n "$b" && -n "$t" ]] && ((t >= b + 40000))
}

_m21E38_une() {
  local n="$1" b
  m21_ecrire E38 variante "$n"
  b="$(_e38_tete)"
  [[ -n "$b" ]] || { wb_avert "prometheus_tsdb_head_series illisible par la vue globale"; return 1; }
  m21_ecrire E38 base "$b"
  m21_temoin_etat ".cardinalite = \"${_E38_GENRES[n]}\"" || return 1
  m21_journal E38 "variante $n : cardinalité ${_E38_GENRES[n]} activée (séries en tête au départ : $b)"
  echo "Montée de la cardinalité en cours (jusqu'à 10 min)…"
  if ! m21_attendre 600 _e38_deborde; then
    m21_temoin_etat '.cardinalite = "aucune"' || true
    wb_avert "la tête de Prometheus n'a pas grossi : la cible témoin est-elle collectée (sampleLimit, relabeling déjà posé) ?"
    return 1
  fi
}

panne_E38_v1() { m21_preparer && m21_essayer E38 3 1; }
panne_E38_v2() { m21_preparer && m21_essayer E38 3 2; }
panne_E38_v3() { m21_preparer && m21_essayer E38 3 3; }

verifier_E38() { _e38_deborde; }

annuler_E38() {
  m21_temoin_etat '.cardinalite = "aucune"' 2>/dev/null || wb_avert "état des témoins non remis à « aucune »"
  m21_oublier E38 base
  m21_oublier E38 variante
  m21_journal E38 "annulation"
}

resume_E38() { echo "La mémoire des deux Prometheus grimpe depuis un quart d'heure ; le nombre de séries en tête a bondi."; }

symptome_E38() {
  wb_symptome "Ticket INC-4838 — De : Karim Benali" \
    "La mémoire des deux réplicas de Prometheus grimpe depuis un quart d'heure et le nombre de séries" \
    "en tête a pris plusieurs dizaines de milliers d'un coup (prometheus_tsdb_head_series). Grafana" \
    "commence à ramer. L'équipe MédiAgenda a branché ce matin son « module de rapports » sur" \
    "l'application de recette de wb-pannes. Trouve ce qui gonfle, protège Prometheus tout de suite," \
    "puis prépare ce qu'on dit à l'équipe." \
    "" \
    "Temps cible : 45 min. Contrôle : lab/bin/check 21 38"
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 21 E38 3 "$@"; }
fi
