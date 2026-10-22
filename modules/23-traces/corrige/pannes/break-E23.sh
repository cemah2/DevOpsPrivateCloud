# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # SQL et filtres jq entre apostrophes
# break-E23.sh — M23-E23 « Astreinte : l'API est lente »
#
# Combine UNE panne de M23-E19 à M23-E22 (variante tirée au hasard) et UNE lenteur réversible propre à cet
# exercice, sur MédiAgenda de dev :
#   L1. déclencheur « controle_coherence_rdv » (BEFORE INSERT, pg_sleep 0,8 s) posé dans la base mediagenda
#       du cluster CNPG mediagenda-db (espace mediagenda-dev) : chaque prise de rendez-vous attend ;
#       commentaire de la fonction : CHG-5023 (marque de la panne) ; aucune donnée touchée ;
#   L2. commit de Lucas dans mediagenda/deploiement (overlay dev) : limite CPU de l'API à 60m (demande 50m) :
#       étranglement CFS sous la charge du témoin, toutes les routes ralentissent.
#
#   --variante N  (1 à 8) : N = 2 × (panne − 1) + lenteur, panne 1..4 = E19..E22, lenteur 1..2 = L1..L2 ;
#                 la variante de la panne reste tirée au hasard.
#   --annuler     annule la lenteur puis la panne (et toute panne M23-E19 à E22 encore marquée active).
#
# Avant la première injection : témoin de trafic et chaîne de traces sains (une seule fois, puis
# _M23_ASTREINTE=1 dispense chaque panne de ces contrôles).

_WB_E23_DIR="$(dirname "${BASH_SOURCE[0]}")"
WB_PANNES_LIB=1
# shellcheck source=break-E19.sh
source "$_WB_E23_DIR/break-E19.sh"
# shellcheck source=break-E20.sh
source "$_WB_E23_DIR/break-E20.sh"
# shellcheck source=break-E21.sh
source "$_WB_E23_DIR/break-E21.sh"
# shellcheck source=break-E22.sh
source "$_WB_E23_DIR/break-E22.sh"
unset WB_PANNES_LIB

declare -A _E23_NB=([E19]=4 [E20]=3 [E21]=3 [E22]=3)
_E23_PANNES=(E19 E20 E21 E22)
_E23_MARQUE=CHG-5023

# ---------------------------------------------------------------------------
# Lenteur L1 : déclencheur PostgreSQL (base de dev)
# ---------------------------------------------------------------------------

_e23_primaire() {
  wb_kubectl -n "$_M23_NS_AGENDA" get pods -l cnpg.io/cluster=mediagenda-db -o json 2>/dev/null | jq -r '
    [.items[] | select(.metadata.labels["cnpg.io/instanceRole"] == "primary" or .metadata.labels.role == "primary")
     | select(.status.phase == "Running") | .metadata.name][0] // empty' | grep .
}

# _e23_psql — psql dans le conteneur postgres du primaire (connexion locale), SQL lu sur l'entrée standard.
_e23_psql() {
  local p
  p="$(_e23_primaire)" || return 1
  wb_kubectl -n "$_M23_NS_AGENDA" exec -i "$p" -c postgres -- psql -X -q -t -A -v ON_ERROR_STOP=1 -d mediagenda
}

_e23_l1_poser() {
  _e23_psql >/dev/null <<SQL
CREATE OR REPLACE FUNCTION public.controle_coherence_rdv() RETURNS trigger LANGUAGE plpgsql AS \$\$
BEGIN
  -- Contrôle de cohérence des créneaux demandé par l'audit (à optimiser).
  PERFORM pg_sleep(0.8);
  RETURN NEW;
END
\$\$;
COMMENT ON FUNCTION public.controle_coherence_rdv() IS 'Contrôle de cohérence des créneaux ($_E23_MARQUE)';
DROP TRIGGER IF EXISTS controle_coherence_rdv ON public.rendez_vous;
CREATE TRIGGER controle_coherence_rdv BEFORE INSERT ON public.rendez_vous
  FOR EACH ROW EXECUTE FUNCTION public.controle_coherence_rdv();
SQL
}

# _e23_l1_actif — le déclencheur marqué existe ET une insertion (annulée) prend plus de 0,7 s.
_e23_l1_actif() {
  local r
  r="$(_e23_psql <<'SQL' 2>/dev/null
SELECT count(*) FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
 WHERE t.tgname = 'controle_coherence_rdv' AND obj_description(p.oid, 'pg_proc') LIKE '%CHG-5023%';
BEGIN;
CREATE TEMP TABLE _t ON COMMIT DROP AS SELECT clock_timestamp() AS d;
INSERT INTO public.rendez_vous (patient, praticien, debut, duree_minutes, motif)
  VALUES ('Patient Témoin', 'dr-temoin-sonde', now() + interval '400 days', 30, 'mesure');
SELECT extract(epoch FROM clock_timestamp() - d) > 0.7 FROM _t;
ROLLBACK;
SQL
)" || return 1
  [[ "$(head -n 1 <<<"$r")" == 1 && "$(tail -n 1 <<<"$r")" == t ]]
}

_e23_l1_retirer() {
  local r
  r="$(_e23_psql <<'SQL' 2>/dev/null
SELECT count(*) FROM pg_proc WHERE proname = 'controle_coherence_rdv'
   AND obj_description(oid, 'pg_proc') LIKE '%CHG-5023%';
SQL
)" || { wb_avert "base de dev injoignable : déclencheur controle_coherence_rdv non vérifié"; return 0; }
  if [[ "$r" == 1 ]]; then
    _e23_psql >/dev/null <<'SQL' || wb_avert "retrait du déclencheur controle_coherence_rdv impossible"
DROP TRIGGER IF EXISTS controle_coherence_rdv ON public.rendez_vous;
DROP FUNCTION IF EXISTS public.controle_coherence_rdv();
SQL
  fi
}

# ---------------------------------------------------------------------------
# Lenteur L2 : limite CPU de l'API (commit dans l'overlay dev)
# ---------------------------------------------------------------------------

_e23_l2_poser() {
  local dep i ops tmp
  read -r dep i <<<"$(m23_charge "$_M23_NS_AGENDA" mediagenda)" || true
  [[ -n "${dep:-}" ]] || return 1
  ops="$(wb_kubectl -n "$_M23_NS_AGENDA" get deployment "$dep" -o json | jq -c --argjson i "$i" '
    .spec.template.spec.containers[$i].resources as $r
    | [ (if $r.limits then {op: "add", path: "/spec/template/spec/containers/\($i)/resources/limits/cpu", value: "60m"}
         else {op: "add", path: "/spec/template/spec/containers/\($i)/resources/limits", value: {cpu: "60m"}} end),
        (if $r.requests then {op: "add", path: "/spec/template/spec/containers/\($i)/resources/requests/cpu", value: "50m"}
         else {op: "add", path: "/spec/template/spec/containers/\($i)/resources/requests", value: {cpu: "50m"}} end) ]')" || return 1
  tmp="$(m23_etat E23)/tmp"
  mkdir -p "$tmp"
  m23_overlay_avec_patch "$_M23_DEPOT_AGENDA" "$dep" "$ops" "$tmp/kustomization.yaml" || return 1
  m23_commit E23 l2 "$_M23_DEPOT_AGENDA" "dev : ressources de l'API alignées sur le quota d'équipe" \
    "$_M23_OVERLAY" "$tmp/kustomization.yaml" || return 1
  m23_ecrire E23 l2-charge "$dep $i"
  m23_argo_rafraichir "$_M23_NS_AGENDA"
  m23_attendre 420 m23_deploiement_a "$_M23_NS_AGENDA" "$dep" "$i" '.resources.limits.cpu == "60m"'
}

_e23_l2_actif() {
  local dep i
  read -r dep i <<<"$(m23_lire E23 l2-charge)" || true
  [[ -n "${dep:-}" ]] && m23_commit_actif E23 l2 &&
    m23_deploiement_a "$_M23_NS_AGENDA" "$dep" "$i" '.resources.limits.cpu == "60m"'
}

_e23_l2_retirer() {
  if m23_commit_actif E23 l2; then
    m23_retablir E23 l2 || true
    m23_argo_rafraichir "$_M23_NS_AGENDA"
  else
    m23_oublier E23 git-l2
  fi
  m23_oublier E23 l2-charge
}

_e23_lenteur_poser() {
  case "$1" in
    1) _e23_l1_poser && m23_attendre 60 _e23_l1_actif ;;
    2) _e23_l2_poser ;;
  esac
}
_e23_lenteur_active() {
  case "$1" in
    1) _e23_l1_actif ;;
    2) _e23_l2_actif ;;
  esac
}
_e23_lenteur_retirer() {
  case "$1" in
    1) _e23_l1_retirer ;;
    2) _e23_l2_retirer ;;
    *) _e23_l1_retirer; _e23_l2_retirer ;;
  esac
}

# ---------------------------------------------------------------------------
# Annulation et injection
# ---------------------------------------------------------------------------

_E23_annuler() {
  local etat panne var lenteur ex
  etat="$(wb_marqueur_lire M23-E23)"
  read -r panne lenteur <<<"${etat:-}" || true
  WB_EX=M23-E23
  WB_VAR=0
  _e23_lenteur_retirer "${lenteur:-tout}"
  for ex in "${_E23_PANNES[@]}"; do
    if [[ "${panne%%:*}" == "$ex" ]] || wb_marqueur_existe "M23-$ex"; then
      var="$(wb_marqueur_lire "M23-$ex")"
      [[ -n "$var" ]] || var="${panne#*:}"
      WB_EX="M23-$ex"
      WB_VAR="${var:-annulation}"
      "annuler_$ex" || true
      wb_marqueur_suppr "M23-$ex"
    fi
  done
  WB_EX=M23-E23
  m23_oublier E23 tmp
  wb_marqueur_suppr M23-E23
  echo "Astreinte M23-E23 annulée : lenteur et panne retirées. Contrôle : lab/bin/check 23 23"
}

main() {
  local var="" annuler=0
  while (($#)); do
    case "$1" in
      --variante)
        if (($# < 2)); then echo "--variante attend un numéro" >&2; return 2; fi
        var="$2"; shift 2 ;;
      --variante=*) var="${1#*=}"; shift ;;
      --annuler) annuler=1; shift ;;
      *) echo "Option inconnue : $1 (attendu : --variante N, --annuler)" >&2; return 2 ;;
    esac
  done
  if ((annuler)); then
    _E23_annuler
    return 0
  fi

  local ex
  for ex in E23 "${_E23_PANNES[@]}"; do
    if wb_marqueur_existe "M23-$ex"; then
      echo "Une panne M23-$ex est encore active. Répare-la ou annule-la avant de prendre l'astreinte." >&2
      return 1
    fi
  done
  [[ -n "$var" ]] || var=$((RANDOM % 8 + 1))
  if ! [[ "$var" =~ ^[0-9]+$ ]] || ((var < 1 || var > 8)); then
    echo "Variante invalide : $var (1 à 8)" >&2
    return 2
  fi
  local p=$(((var - 1) / 2)) lenteur=$(((var - 1) % 2 + 1))
  ex="${_E23_PANNES[p]}"

  echo "Injection en cours (une panne et une lenteur : compte 5 à 20 minutes)…"
  WB_EX=M23-E23
  WB_VAR="$var"
  command -v yq >/dev/null || { echo "yq (mikefarah) est requis sur adm01." >&2; return 1; }
  m23_trafic || { echo "Témoin de trafic impossible : rien n'est cassé." >&2; return 1; }
  m23_sain || { echo "Chaîne de traces pas saine avant l'astreinte : rien n'est cassé." >&2; return 1; }
  wb_marqueur_ecrire M23-E23 "- $lenteur"

  # 1. La lenteur d'abord (les traces la montrent encore), 2. puis la panne de la chaîne d'observabilité.
  if ! _e23_lenteur_poser "$lenteur" || ! _e23_lenteur_active "$lenteur"; then
    echo "La lenteur n'a pas pu être posée ni constatée : remise en état, rien n'est cassé." >&2
    _E23_annuler >/dev/null
    return 1
  fi
  m23_journal E23 "lenteur L$lenteur posée"

  _M23_ASTREINTE=1
  local v=$((RANDOM % ${_E23_NB[$ex]} + 1))
  WB_EX="M23-$ex"
  WB_VAR="$v"
  if ! "panne_${ex}_v${v}" >/dev/null || ! "verifier_$ex" 2>/dev/null; then
    unset _M23_ASTREINTE
    echo "La panne $ex n'a pas pu être posée ni constatée : remise en état, rien n'est cassé." >&2
    wb_marqueur_ecrire "M23-$ex" "$WB_VAR"
    wb_marqueur_ecrire M23-E23 "$ex:$WB_VAR $lenteur"
    _E23_annuler >/dev/null
    return 1
  fi
  unset _M23_ASTREINTE
  wb_marqueur_ecrire "M23-$ex" "$WB_VAR"
  local resume
  resume="$("resume_$ex")"
  WB_EX=M23-E23
  wb_marqueur_ecrire M23-E23 "$ex:$(wb_marqueur_lire "M23-$ex") $lenteur"

  wb_symptome "Ticket INC-5023 — De : Nadia Roussel (responsable astreinte) — priorité P2" \
    "Tu es d'astreinte. Mardi, 7 h 40 : Julien signale que l'API MédiAgenda de dev est lente — la prise" \
    "de rendez-vous traîne, les tests de bout en bout de 9 h vont échouer. En plus, ce matin :" \
    "- $resume" \
    "Trouve où passe le temps en croisant métriques, journaux, traces et profils, rétablis le service et" \
    "l'observabilité par le code, tiens-moi informée toutes les 30 min, puis rédige le post-mortem avec" \
    "le modèle de l'équipe (modules/00-lab/ressources/M00-E46/modele-post-mortem.md)." \
    "" \
    "Témoin de trafic : wb-pannes/trafic-agenda (ne pas l'arrêter : c'est lui qui « fait » les utilisateurs)." \
    "Temps cible : 2 h (rétablissement) + 45 min (post-mortem). Contrôle : lab/bin/check 23 23"
}
