# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# break-S07.sh — F3-S07 « Mardi soir : incident chronométré » (tirage dans un réservoir de pannes)
#
# Le script tire UNE panne parmi des pannes déjà corrigées dans les modules (réservoir ci-dessous) et
# l'injecte en appelant le script du module lui-même (lab/bin/break <module> <exercice>, sous-processus) :
# ses contrôles préalables, sa sauvegarde, son constat et son annulation s'appliquent tels quels. Le
# contrôle de santé du final (S01) est fait avant, comme pour tout incident F3.
#   --variante N  force la N-ième panne du réservoir (1 à 5) ; si elle ne peut pas être injectée sur ce
#                 lab, la suivante est essayée.
# Réservoir (WB_F3_S07_RESERVOIR, « module:exercice » séparés par des espaces) :
#   1. 15:40  M15-E40 — un certificat n'est jamais délivré (émetteur ACME, TSIG, sélecteur DNS-01)
#   2. 16:41  M16-E41 — l'archivage des WAL de mediagenda-db (recette) échoue
#   3. 27:20  M27-E20 — MédiNotif (recette) ne consomme plus
#   4. 27:22  M27-E22 — le cache Valkey de la recette ne sert plus
#   5. 28:19  M28-E19 — MédiNotif (recette) ne monte plus en charge (KEDA)
# Toutes ces pannes visent la RECETTE ou des objets d'essai : jamais la production.
# État : ~/.local/state/workbook/F3-S07/tirage (« module:exercice »), lu par check-S07.

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_f3-commun.sh
source "$WB_ROOT/finaux/F3-astreinte/corrige/pannes/_f3-commun.sh"

read -r -a _S07_RESERVOIR <<<"${WB_F3_S07_RESERVOIR:-15:40 16:41 27:20 27:22 28:19}"

_s07_cle() {
  local mod ex
  IFS=: read -r mod ex <<<"$1"
  printf 'M%02d-E%02d\n' "$((10#$mod))" "$((10#$ex))"
}

_s07_injecter() {
  local depart="$1" nb="${#_S07_RESERVOIR[@]}" i n c mod ex sortie
  _f3p_preparer S07 || return 1
  sortie="$(_f3p_etat S07)/symptome"
  for ((i = 0; i < nb; i++)); do
    n=$(((depart - 1 + i) % nb + 1))
    c="${_S07_RESERVOIR[n - 1]}"
    IFS=: read -r mod ex <<<"$c"
    _f3p_journal S07 "essai de la panne $c"
    if "$WB_ROOT/lab/bin/break" "$mod" "$ex" >"$sortie" 2>&1; then
      _f3p_ecrire S07 tirage "$c"
      WB_VAR="$n"
      _f3p_journal S07 "panne $c injectée"
      return 0
    fi
    _f3p_journal S07 "panne $c impossible sur ce lab : $(tail -n 3 "$sortie" | tr '\n' ' ')"
  done
  echo "Aucune panne du réservoir n'a pu être injectée (voir $(_f3p_etat S07)/journal) : rien n'est cassé." >&2
  return 1
}

panne_S07_v1() { _s07_injecter 1; }
panne_S07_v2() { _s07_injecter 2; }
panne_S07_v3() { _s07_injecter 3; }
panne_S07_v4() { _s07_injecter 4; }
panne_S07_v5() { _s07_injecter 5; }

verifier_S07() {
  local c
  c="$(_f3p_lire S07 tirage)"
  [[ -n "$c" ]] && wb_marqueur_existe "$(_s07_cle "$c")"
}

annuler_S07() {
  local c mod ex
  c="$(_f3p_lire S07 tirage)"
  if [[ -n "$c" ]]; then
    IFS=: read -r mod ex <<<"$c"
    "$WB_ROOT/lab/bin/break" "$mod" "$ex" --annuler >/dev/null 2>&1 || wb_avert "annulation de la panne $c à relancer : lab/bin/break $mod $ex --annuler"
  fi
  _f3p_oublier S07 tirage
  _f3p_oublier S07 symptome
}

resume_S07() { echo "incident du soir (panne tirée au hasard)"; }

symptome_S07() {
  local f
  f="$(_f3p_etat S07)/symptome"
  wb_symptome "INC-5907 — Mardi, 21 h 04 — CHRONOMÉTRÉ : 45 min, sans corrigé" \
    "Le téléphone d'astreinte sonne. Voici ce qui arrive (tel quel) :"
  # Le texte du module, sans ses lignes d'outillage (commandes de contrôle et d'injection du module).
  if [[ -f "$f" ]]; then
    grep -Ev '^Injection en cours|lab/bin/(check|break)' "$f" | sed 's/^/  │ /'
  fi
  printf '\n'
  _f3p_symptome S07 INC-5907 "Règles du chronométré" \
    "Chrono lancé MAINTENANT. 45 min pour rétablir le service, sans ouvrir aucun corrigé (modules compris)." \
    "Messages d'état toutes les 15 min au plus, consignés dans la main courante ([état]) et envoyés." \
    "Note l'heure de l'appel comme heure d'ouverture de INC-5907."
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main F3 S07 5 "$@"; }
fi
