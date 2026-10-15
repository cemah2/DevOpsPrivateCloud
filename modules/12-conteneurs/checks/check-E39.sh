# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# check-E39.sh — M12-E39 « Panne : le disque de l'hôte est plein » : de l'espace libre sur ctr01, la
# pile de recette saine, aucun conteneur à journal sans limite, une rotation des journaux par défaut
# au niveau du démon, peu d'espace récupérable laissé à l'abandon. Lecture seule.

# shellcheck source=_m12-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m12-expert.sh"

title "M12-E39 — Le disque de ctr01 a de la marge et ne se remplira plus de la même façon"
require_cmd jq curl ssh

if _m12x_recette_repond; then
  check_cmd "système de fichiers racine occupé à moins de 85 %" _m12x_jq '.occupation < 85'
  check_cmd "au moins 3 Gio disponibles" _m12x_jq '.libre >= 3221225472'
  for _m12_e39_s in db valkey api doc; do
    check_cmd "recette : $_m12_e39_s démarré et sain" _m12x_sain "$_m12_e39_s"
  done
  # Un journal json-file sans max-size (ou avec une limite démesurée) peut remplir le disque.
  check_cmd "aucun conteneur dont le journal json-file grossit sans limite raisonnable (≤ 1 Gio)" _m12x_jq '
    def octets: if . == null then null else (capture("^(?<n>[0-9.]+)(?<u>[kmgKMG]?)") as $c
      | ($c.n | tonumber) * ({"": 1, "k": 1e3, "m": 1e6, "g": 1e9}[$c.u | ascii_downcase])) end;
    [ (.services[], .autres[]) | select(.statut == "running" and .journal.Type == "json-file")
      | (.journal.Config["max-size"] | octets) as $t
      | select($t == null or $t > 1e9 or ((.journal.Config["max-file"] // "1") | tonumber) * $t > 5e9) ]
    | length == 0'
  check_cmd "démon : rotation des journaux par défaut (log-opts max-size, ou pilote local/journald)" _m12x_jq '
    (.daemon["log-driver"] // "json-file") as $d
    | ($d == "local" or $d == "journald") or ((.daemon["log-opts"] // {})["max-size"] != null)'
  check_cmd "cache de construction récupérable inférieur à 5 Go" _m12x_jq '
    ((.df["Build Cache"].Reclaimable // "0B") | capture("^(?<n>[0-9.]+)(?<u>[kMG]?B)") as $c
      | ($c.n | tonumber) * ({"B": 1, "kB": 1e3, "MB": 1e6, "GB": 1e9}[$c.u])) < 5e9'
  check_cmd "volumes non utilisés inférieurs à 2 Go" _m12x_jq '
    ((.df["Local Volumes"].Reclaimable // "0B") | capture("^(?<n>[0-9.]+)(?<u>[kMG]?B)") as $c
      | ($c.n | tonumber) * ({"B": 1, "kB": 1e3, "MB": 1e6, "GB": 1e9}[$c.u])) < 2e9'
else
  skip "disque et pile de recette" "Docker ne répond pas sur $_m12x_ctr01, ou la pile « recette » n'existe pas"
fi
check_http "API : /pret répond 200" "$_m12x_url_api/pret" 200
check_cmd "panne M12-E39 close (lab/bin/break 12 39 --annuler après réparation)" _m12x_aucune_panne_active E39
