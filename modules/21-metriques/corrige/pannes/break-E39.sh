# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq/yq entre apostrophes
# break-E39.sh — M21-E39 « Panne : les données anciennes ont disparu »
#
# AUCUNE donnée n'est supprimée du compartiment thanos-k8s-par1 : les pannes coupent l'accès ou
# l'envoi, jamais les blocs.
#   1. Secret de configuration du stockage objet (thanos-objstore, hors Git) « restauré depuis une
#      ancienne version du coffre » : secret_key fausse ; seuls les pods du Store Gateway sont
#      redémarrés (le sidecar et le Compactor gardent leur configuration chargée… jusqu'à leur
#      prochain redémarrage) ;
#   2. MR de Lucas sur les valeurs de kps : objectStorageConfig retiré de prometheus.prometheusSpec.thanos
#      (« le sidecar n'a besoin que du gRPC ») : les Prometheus redémarrent, le sidecar n'envoie plus
#      aucun bloc. La même MR pose disableCompaction: true (« comme le recommande la doc Thanos ») :
#      GARDE-FOU de données. Sans lui, l'opérateur rendrait la compaction locale normale à Prometheus,
#      qui fusionnerait les blocs de 2 h non envoyés ; or le sidecar n'envoie que des blocs de niveau 1 :
#      ces heures-là manqueraient pour toujours au compartiment. Avec lui, les blocs restent de 2 h et
#      partent dès que l'apprenant a remis le stockage objet ;
#   3. MR de Lucas sur thanos/ : --min-time=-2d ajouté au Store Gateway (« le Store ne sert que le
#      récent, ça le soulage ») : tout ce qui a plus de deux jours n'est plus servi par le Store
#      (variante retenue seulement si le Store sert des données de plus de trois jours).

# shellcheck source=../../../../lab/lib/pannes-lib.sh
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m21-commun.sh
source "$WB_ROOT/modules/21-metriques/corrige/pannes/_m21-commun.sh"

_E39_MARQUE="medisphere.internal/restaure-depuis"
_E39_ORIG=""

# _e39_store_pods — pods du Store Gateway (conteneur lancé avec l'argument « store »).
_e39_store_pods() {
  wb_kubectl -n "$_M21_SUP" get pods -o json 2>/dev/null | jq -r '
    .items[] | select(any(.spec.containers[]; ((.command // []) + (.args // [])) | index("store") != null)) | .metadata.name'
}
# _e39_store_secret — « secret clé » de la configuration objstore du Store (fichier monté ou variable).
_e39_store_secret() {
  local p
  p="$(_e39_store_pods | head -n 1)"
  [[ -n "$p" ]] || return 1
  wb_kubectl -n "$_M21_SUP" get pod "$p" -o json | jq -r '
    .spec as $s
    | ([$s.containers[] | select(((.command // []) + (.args // [])) | index("store") != null)][0]) as $c
    | ((($c.command // []) + ($c.args // [])) | map(select(startswith("--objstore.config-file="))) | .[0] // "" | sub("^--objstore.config-file="; "")) as $f
    | if $f != "" then
        ($f | split("/")) as $parts | ($parts[:-1] | join("/")) as $dir | $parts[-1] as $base
        | ([$c.volumeMounts[]? | select(.mountPath == $dir or ($f | startswith(.mountPath + "/")))][0]) as $m
        | ([$s.volumes[] | select(.name == $m.name)][0].secret) as $sec
        | if $sec == null then empty
          else "\($sec.secretName) \(([$sec.items[]? | select(.path == $base) | .key][0]) // $base)" end
      else
        ([$c.env[]? | select(.valueFrom.secretKeyRef != null and (.name | test("OBJSTORE"; "i"))) | .valueFrom.secretKeyRef][0])
        | if . == null then empty else "\(.name) \(.key)" end
      end'
}
_e39_store_ko() {
  m21_prom_api stores 2>/dev/null | jq -e '[.data.store[]? | select(.lastError == null)] | length == 0' >/dev/null 2>&1
}
_e39_store_min() { m21_prom_api stores 2>/dev/null | jq -r '[.data.store[]? | select(.lastError == null) | .minTime] | min // empty'; }
_e39_store_recent() {
  local m
  m="$(_e39_store_min)"
  [[ -n "$m" ]] && (((m / 1000) >= $(date +%s) - 2 * 86400 - 7200))
}
_e39_sidecar_sans_envoi() {
  wb_kubectl -n "$_M21_SUP" get statefulsets -o json 2>/dev/null | jq -e '
    [.items[].spec.template.spec.containers[] | select(.name == "thanos-sidecar")
     | (((.args // []) + [.env[]?.name]) | map(test("objstore"; "i")) | any)]
    | length > 0 and all(. == false)' >/dev/null 2>&1
}
_e39_redemarrer_store() {
  local p
  for p in $(_e39_store_pods); do
    wb_kubectl -n "$_M21_SUP" delete pod "$p" --wait=false >/dev/null 2>&1 || true
  done
}

# Variante 2 : retrait TEXTUEL du bloc objectStorageConfig (commentaires d'en-tête compris), pour que
# la MR de Lucas et la MR d'annulation soient des diffs propres ; le bloc et la ligne qui le précède
# (ancre) sont gardés dans l'état local pour la réinsertion.
read -r -d '' _E39_PY_RETIRER <<'PY' || true
import sys, re
etat = sys.argv[1]
lignes = sys.stdin.read().split("\n")
idx = [i for i, l in enumerate(lignes) if re.match(r"^\s*objectStorageConfig:\s*(#.*)?$", l)]
if len(idx) != 1:
    sys.exit(1)
i = idx[0]
retrait = len(lignes[i]) - len(lignes[i].lstrip())
fin = i + 1
while fin < len(lignes) and (lignes[fin].strip() == "" or len(lignes[fin]) - len(lignes[fin].lstrip()) > retrait):
    fin += 1
while fin > i + 1 and lignes[fin - 1].strip() == "":
    fin -= 1
debut = i
while debut > 0 and lignes[debut - 1].strip().startswith("#") and len(lignes[debut - 1]) - len(lignes[debut - 1].lstrip()) == retrait:
    debut -= 1
if debut == 0:
    sys.exit(1)
# Clé « thanos: » qui contient le bloc : disableCompaction se pose à côté, dans prometheusSpec.
j = i - 1
while j >= 0 and not (re.match(r"^\s*thanos:\s*(#.*)?$", lignes[j]) and len(lignes[j]) - len(lignes[j].lstrip()) < retrait):
    j -= 1
if j < 0:
    sys.exit(1)
ind = lignes[j][:len(lignes[j]) - len(lignes[j].lstrip())]
if any(re.match("^" + ind + r"disableCompaction:", l) for l in lignes):
    sys.exit(1)
open(etat + "/bloc.txt", "w").write("\n".join(lignes[debut:fin]))
open(etat + "/ancre.txt", "w").write(lignes[debut - 1])
ajout = [ind + "# M21-E39 (Lucas) : compaction locale coupée, comme le recommande la doc Thanos pour le sidecar",
         ind + "disableCompaction: true"]
sys.stdout.write("\n".join(lignes[:j] + ajout + lignes[j:debut] + lignes[fin:]))
PY
read -r -d '' _E39_PY_REMETTRE <<'PY' || true
import sys
etat = sys.argv[1]
texte = sys.stdin.read()
lignes = texte.split("\n")
bloc = open(etat + "/bloc.txt").read().split("\n")
ancre = open(etat + "/ancre.txt").read()
if ancre not in lignes:
    sys.exit(1)
i = lignes.index(ancre)
lignes = lignes[:i + 1] + bloc + lignes[i + 1:]
# Retire le disableCompaction de la panne s'il est encore là (marque de Lucas suivie de la clé).
for k in range(len(lignes) - 1):
    if lignes[k].strip().startswith("# M21-E39 (Lucas)") and lignes[k + 1].strip() == "disableCompaction: true":
        del lignes[k:k + 2]
        break
sys.stdout.write("\n".join(lignes))
PY
_e39_t2() {
  local c
  c="$(cat)"
  yq -e '.prometheus.prometheusSpec.thanos | has("objectStorageConfig")' >/dev/null 2>&1 <<<"$c" || return 1
  python3 -c "$_E39_PY_RETIRER" "$(m21_etat E39)" <<<"$c"
}
_e39_i2() {
  local c
  c="$(cat)"
  if yq -e '.prometheus.prometheusSpec.thanos | has("objectStorageConfig")' >/dev/null 2>&1 <<<"$c"; then
    printf '%s\n' "$c"
  else
    python3 -c "$_E39_PY_REMETTRE" "$(m21_etat E39)" <<<"$c"
  fi
}
_e39_t3() {
  yq '(select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select((.args // []) | any_c(. == "store")))
      |= (.args = ([.args[] | select(test("^--min-time=") | not)] + ["--min-time=-2d"]))'
}
_e39_i3() {
  A="$_E39_ORIG" yq '(select(.kind == "Deployment" or .kind == "StatefulSet") | .spec.template.spec.containers[] | select((.args // []) | any_c(. == "--min-time=-2d")))
      |= (.args = ([.args[] | select(. != "--min-time=-2d")] + [strenv(A)] | map(select(. != ""))))'
}

_m21E39_une() {
  local n="$1" l s k j f
  m21_ecrire E39 variante "$n"
  case "$n" in
    1)
      ! _e39_store_ko || return 10
      l="$(_e39_store_secret)" || return 10
      read -r s k <<<"$l"
      [[ -n "$s" && -n "$k" ]] || return 10
      m21_ecrire E39 secret "$s $k"
      m21_sauver_objet E39 secret "$s" "$_M21_SUP"
      j="$(wb_kubectl -n "$_M21_SUP" get secret "$s" -o json)" || return 1
      f="$(jq -r --arg k "$k" '.data[$k] // empty | @base64d' <<<"$j" |
        sed -E 's/^([[:space:]]*secret_key:[[:space:]]*)("?)([^"[:space:]]+)("?)[[:space:]]*$/\1\2\30\4/')"
      grep -q 'secret_key' <<<"$f" || { m21_oublier_objet E39 secret "$s" "$_M21_SUP"; return 10; }
      # Empreinte du contenu faussé : l'annulation ne restaure que si le Secret l'a encore (une
      # réparation par secrets-k8s.sh, ou une rotation de clé, n'est jamais défaite).
      m21_ecrire E39 secret-faux "$(printf '%s' "$f" | base64 -w0 | sha256sum | cut -d' ' -f1)"
      jq --arg k "$k" --arg v "$f" --arg m "$_E39_MARQUE" '
        del(.metadata.resourceVersion, .metadata.managedFields)
        | .data[$k] = ($v | @base64) | .metadata.annotations[$m] = "coffre-2026-06"' <<<"$j" |
        wb_kubectl replace -f - >/dev/null || return 1
      _e39_redemarrer_store
      m21_journal E39 "variante 1 : secret $s ($k) faussé, Store redémarré"
      m21_attendre 300 _e39_store_ko || { _e39_defaire 1; return 10; }
      ;;
    2)
      f="$(m21_git_valeurs_kps)" || return 10
      m21_git_lire "$_M21_PROJ_OBS" "$f" | yq -e '.prometheus.prometheusSpec.thanos | has("objectStorageConfig")' >/dev/null 2>&1 || return 10
      m21_ecrire E39 orig present
      echo "Les deux réplicas de Prometheus vont redémarrer l'un après l'autre (quelques minutes)…"
      m21_git_transformer E39 fichier "$_M21_PROJ_OBS" "$f" \
        "refactor(kps): le sidecar Thanos n'a besoin que du gRPC (M21-E39)" _e39_t2 || return
      m21_attendre 420 _e39_sidecar_sans_envoi || { _e39_defaire 2; return 10; }
      ;;
    3)
      l="$(_e39_store_min)"
      [[ -n "$l" ]] && (((l / 1000) < $(date +%s) - 3 * 86400)) || return 10
      f="$(m21_git_trouver "$_M21_PROJ_OBS" '(.kind == "Deployment" or .kind == "StatefulSet") and ([.spec.template.spec.containers[] | (.args // []) | any_c(. == "store")] | any)' thanos)" || return 10
      _E39_ORIG="$(m21_git_lire "$_M21_PROJ_OBS" "$f" | yq '.spec.template.spec.containers[]? | .args[]? | select(test("^--min-time="))' | head -n 1)"
      m21_ecrire E39 orig "$_E39_ORIG"
      m21_git_transformer E39 fichier "$_M21_PROJ_OBS" "$f" \
        "perf(thanos): le Store ne sert que les données récentes (M21-E39)" _e39_t3 || return
      m21_attendre 480 _e39_store_recent || { _e39_defaire 3; return 10; }
      ;;
  esac
  m21_journal E39 "variante $n posée"
}

_e39_defaire() {
  local s k j
  _E39_ORIG="$(m21_lire E39 orig)"
  case "$1" in
    1)
      read -r s k <<<"$(m21_lire E39 secret)"
      [[ -n "${s:-}" ]] || return 0
      j="$(wb_kubectl -n "$_M21_SUP" get secret "$s" -o json 2>/dev/null)" || j=""
      # Restaure seulement si le contenu est encore celui de la panne (marque ET empreinte) ; sinon
      # l'apprenant a réparé (secrets-k8s.sh) : on retire juste la marque si elle traîne.
      if jq -e --arg m "$_E39_MARQUE" '.metadata.annotations[$m] == "coffre-2026-06"' >/dev/null 2>&1 <<<"$j" &&
        [[ "$(jq -r --arg k "$k" '.data[$k] // ""' <<<"$j" | tr -d '\n' | sha256sum | cut -d' ' -f1)" == "$(m21_lire E39 secret-faux)" ]]; then
        m21_restaurer_objet E39 secret "$s" "$_M21_SUP"
        _e39_redemarrer_store
      else
        m21_oublier_objet E39 secret "$s" "$_M21_SUP"
        if [[ -n "$j" ]]; then
          wb_kubectl -n "$_M21_SUP" annotate secret "$s" "$_E39_MARQUE-" >/dev/null 2>&1 || true
        fi
      fi
      m21_oublier E39 secret
      m21_oublier E39 secret-faux
      ;;
    2) [[ -n "$_E39_ORIG" ]] && m21_git_defaire E39 fichier _e39_i2 "revert(kps): stockage objet du sidecar rétabli (M21-E39, annulation)" ;;
    3) m21_git_defaire E39 fichier _e39_i3 "revert(thanos): --min-time du Store rétabli (M21-E39, annulation)" ;;
  esac
  return 0
}

panne_E39_v1() { m21_preparer && m21_essayer E39 3 1; }
panne_E39_v2() { m21_preparer && m21_essayer E39 3 2; }
panne_E39_v3() { m21_preparer && m21_essayer E39 3 3; }

verifier_E39() {
  case "$WB_VAR" in
    1) _e39_store_ko ;;
    2) _e39_sidecar_sans_envoi ;;
    3) _e39_store_recent ;;
  esac
}

annuler_E39() {
  local v="${WB_VAR:-}"
  [[ "$v" =~ ^[1-3]$ ]] || v="$(m21_lire E39 variante)"
  [[ -n "$v" ]] && _e39_defaire "$v"
  m21_oublier E39 variante
  m21_oublier E39 orig
  m21_oublier E39 bloc.txt
  m21_oublier E39 ancre.txt
  m21_journal E39 "annulation"
}

resume_E39() {
  case "${WB_VAR:-}" in
    2) echo "Les sidecars Thanos n'envoient plus rien vers le compartiment depuis le dernier redémarrage de Prometheus." ;;
    *) echo "Les vues longues de Grafana (30 j, 90 j, 6 mois) sont vides ou incomplètes au-delà de quelques jours." ;;
  esac
}

symptome_E39() {
  case "${WB_VAR:-}" in
    2)
      wb_symptome "Ticket INC-4839 — De : Karim Benali" \
        "Revue de capacité : sur le tableau Thanos, les sidecars n'ont plus aucune activité d'envoi" \
        "vers thanos-k8s-par1 depuis le dernier redémarrage des Prometheus (thanos_shipper_* a disparu)." \
        "Aucune alerte, aucune erreur évidente. Dans quinze jours, on perd l'historique sans le savoir." \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 21 39"
      ;;
    *)
      wb_symptome "Ticket INC-4839 — De : Claire Morel" \
        "Je prépare le rapport trimestriel : dans Grafana, les vues longues (30 jours, 90 jours, 6 mois)" \
        "sont vides ou s'arrêtent après quelques jours, et certaines affichent un avertissement de" \
        "réponse partielle. Les vues courtes sont normales. On a payé un stockage objet pour garder" \
        "deux ans : qu'est-ce qui se passe, et est-ce qu'on a perdu quelque chose ?" \
        "" \
        "Temps cible : 45 min. Contrôle : lab/bin/check 21 39"
      ;;
  esac
}

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 21 E39 3 "$@"; }
fi
