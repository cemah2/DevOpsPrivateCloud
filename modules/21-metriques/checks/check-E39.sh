# shellcheck shell=bash
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# shellcheck source-path=SCRIPTDIR
# check-E39.sh — M21-E39 « Panne : les données anciennes ont disparu » : Thanos Query voit les deux
# sidecars et un Store sains, le Store ne limite pas la fenêtre servie, les sidecars ont leur stockage
# objet et n'échouent pas à envoyer, RB-219, panne close. Lecture seule.

# shellcheck source=_m21-expert.sh
source "$(dirname "${BASH_SOURCE[0]}")/_m21-expert.sh"

title "M21-E39 — L'historique long est servi"
require_cmd jq kubectl curl

_m21_e39_stores="$(prom_api stores 2>/dev/null)" || _m21_e39_stores=""
if [[ -z "$_m21_e39_stores" ]]; then
  skip "Thanos Query" "l'API /api/v1/stores de la vue globale ne répond pas (lab/bin/check 21 24)"
else
  check_cmd "Thanos Query : au moins deux sidecars sains" \
    jq -e '[.data.sidecar[]? | select(.lastError == null)] | length >= 2' <<<"$_m21_e39_stores"
  check_cmd "Thanos Query : au moins un Store Gateway sain" \
    jq -e '[.data.store[]? | select(.lastError == null)] | length >= 1' <<<"$_m21_e39_stores"
  check_cmd "aucun composant de stockage en erreur vu par Thanos Query" \
    jq -e '[.data[]?[]? | select(.lastError != null)] | length == 0' <<<"$_m21_e39_stores"
fi
check_cmd "Store Gateway : pas de --min-time récent (moins de 30 jours) qui masque l'historique" \
  _m21x_kq '[.items[].spec.containers[] | select(((.command // []) + (.args // [])) | index("store") != null)
             | (.args // [])[] | select(test("^--min-time=-[0-9]+[smhd]$"))
             | capture("^--min-time=-(?<n>[0-9]+)(?<u>[smhd])$") | select((.u != "d") or ((.n | tonumber) < 30))] | length == 0' \
  -n supervision pods
check_cmd "Store Gateway : pods prêts" \
  _m21x_kq '[.items[] | select(any(.spec.containers[]; ((.command // []) + (.args // [])) | index("store") != null))
             | all(.status.containerStatuses[]?; .ready)] | length > 0 and all' -n supervision pods
check_cmd "sidecars Thanos : stockage objet configuré dans les StatefulSets de Prometheus" \
  _m21x_kq '[.items[].spec.template.spec.containers[] | select(.name == "thanos-sidecar")
             | (((.args // []) + [.env[]?.name]) | map(test("objstore"; "i")) | any)] | length >= 1 and all' \
  -n supervision statefulsets
if _m21x_vue_globale; then
  check_cmd "sidecars : l'expéditeur de blocs tourne (thanos_shipper_uploads_total présent)" \
    _m21x_non_vide 'thanos_shipper_uploads_total'
  check_cmd "sidecars : aucun échec d'envoi de bloc depuis 6 h" \
    _m21x_vide 'sum(increase(thanos_shipper_upload_failures_total[6h])) > 0'
  check_cmd "une alerte détecte un sidecar sans expéditeur (métrique d'envoi absente)" \
    _m21x_regle_qui '(unless|absent).*thanos_shipper_uploads_total'
fi
check_cmd "RB-219 : section sur l'historique long (Thanos)" _m21x_doc_contient "$_m21x_rb/RB-219-*.md" '^#+ .*(Thanos|historique|long terme)'
check_cmd "panne M21-E39 close (lab/bin/break 21 39 --annuler après réparation)" _m21x_aucune_panne_active E39
