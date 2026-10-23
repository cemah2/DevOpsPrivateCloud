# shellcheck shell=bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2016  # filtres jq entre apostrophes
# break-E40.sh — M25-E40 « Panne : permission denied »
#
# Julien (groupe mediagenda) ne peut plus toucher à kv/mediagenda/dev/. Modification DIRECTE de la
# configuration d'OpenBao (dérive par rapport à plateforme/secrets), avec le jeton d'administration de
# l'apprenant. Variantes :
#   1. « + » à la place de « * » : mediagenda-dev ne vise plus que kv/data/mediagenda/<un segment>
#      (motif « kv/data/mediagenda/+ ») ; rien sous dev/ ne correspond plus ;
#   2. préfixe KV v2 oublié : « kv/mediagenda/dev/* » au lieu de « kv/data/mediagenda/dev/* » ;
#   3. politique « gel-inventaire » (deny sur les MÊMES motifs que mediagenda-dev) ajoutée au groupe
#      externe mediagenda : deny l'emporte, immédiatement, sur les jetons existants ;
#   4. alias du groupe externe renommé « MediAgenda » : la revendication « groups » (mediagenda) ne
#      correspond plus ; effet à la prochaine connexion de Julien (jeton suivant : default seulement).
#
# Sauvegardes : ~/.local/state/workbook/M25-E40/ (texte de la politique, politiques du groupe, nom de
# l'alias). Annulation : remise de ces valeurs (identiques à plateforme/secrets : une réparation par
# tofu apply n'est pas défaite), suppression de gel-inventaire si elle porte la marque M25-E40.

# shellcheck source=../../../../lab/lib/pannes-lib.sh disable=SC1091
source "$WB_ROOT/lab/lib/pannes-lib.sh"
# shellcheck source=_m25-commun.sh
source "$WB_ROOT/modules/25-secrets/corrige/pannes/_m25-commun.sh"

_E40_POL=mediagenda-dev
_E40_GROUPE=mediagenda
_E40_GEL=gel-inventaire
_E40_ALIAS_FAUX=MediAgenda

# _e40_politique NOM — texte de la politique ACL (vide si absente).
_e40_politique() { m25_api GET "sys/policies/acl/$1" 2>/dev/null | jq -r '.data.policy // empty' 2>/dev/null || true; }
# _e40_ecrire_politique NOM (texte sur l'entrée standard)
_e40_ecrire_politique() { jq -Rs '{policy: .}' | m25_api PUT "sys/policies/acl/$1" - >/dev/null; }
_e40_groupe() { m25_api GET "identity/group/name/$_E40_GROUPE" 2>/dev/null; }

# _e40_pret — état d'entrée conforme au corrigé (M25-E05/E06/E08) ; sauvegarde (une seule fois).
_e40_pret() {
  local p g
  m25_jeton_charger || return 1
  p="$(_e40_politique "$_E40_POL")"
  grep -qF 'path "kv/data/mediagenda/dev/*"' <<<"$p" || { wb_avert "politique $_E40_POL inattendue (M25-E05/E08 faits ?)"; return 1; }
  g="$(_e40_groupe)" || { wb_avert "groupe externe $_E40_GROUPE introuvable (M25-E06 fait ?)"; return 1; }
  jq -e '.data.type == "external" and .data.alias.name == "mediagenda"' >/dev/null 2>&1 <<<"$g" \
    || { wb_avert "groupe $_E40_GROUPE sans alias « mediagenda » : état de départ inattendu"; return 1; }
  m25_ecrire_si_absent E40 politique.hcl "$p"
  m25_ecrire_si_absent E40 groupe.json "$(jq -c '{policies: .data.policies, alias_id: .data.alias.id,
    alias_nom: .data.alias.name, accessor: .data.alias.mount_accessor, groupe_id: .data.id}' <<<"$g")"
}

panne_E40_v1() {
  _e40_pret || return 1
  m25_lire E40 politique.hcl \
    | sed -e 's#^path "kv/data/mediagenda/dev/\*"#path "kv/data/mediagenda/+"#' \
          -e 's#^path "kv/metadata/mediagenda/dev/\*"#path "kv/metadata/mediagenda/+"#' \
          -e '1i # Simplification (PLAT-2640) : un seul motif pour les secrets MédiAgenda, « + » = tout sous-dossier.' \
    | _e40_ecrire_politique "$_E40_POL" || return 1
  m25_journal E40 "politique $_E40_POL : motifs dev/* remplacés par +"
}

panne_E40_v2() {
  _e40_pret || return 1
  m25_lire E40 politique.hcl \
    | sed -e 's#^path "kv/data/mediagenda/dev/\*"#path "kv/mediagenda/dev/*"#' \
          -e '1i # Chemins alignés sur ceux de la CLI (bao kv put -mount=kv mediagenda/dev/...) (PLAT-2640).' \
    | _e40_ecrire_politique "$_E40_POL" || return 1
  m25_journal E40 "politique $_E40_POL : préfixe data/ retiré"
}

panne_E40_v3() {
  local g
  _e40_pret || return 1
  printf '%s\n' \
    '# gel-inventaire — M25-E40 (panne) : « gel des secrets de développement pendant le relevé de' \
    '# Sophie (SEC-2602) : plus aucune modification par les équipes, sauf nouvel ordre ».' \
    'path "kv/data/mediagenda/dev/*" {' '  capabilities = ["deny"]' '}' '' \
    'path "kv/metadata/mediagenda/dev/*" {' '  capabilities = ["deny"]' '}' \
    | _e40_ecrire_politique "$_E40_GEL" || return 1
  g="$(m25_lire E40 groupe.json)"
  jq -c --arg gel "$_E40_GEL" '{policies: ((.policies // []) + [$gel] | unique)}' <<<"$g" \
    | m25_api POST "identity/group/name/$_E40_GROUPE" - >/dev/null || return 1
  m25_journal E40 "politique $_E40_GEL (deny) créée et ajoutée au groupe $_E40_GROUPE"
}

panne_E40_v4() {
  local g
  _e40_pret || return 1
  g="$(m25_lire E40 groupe.json)"
  jq -c --arg n "$_E40_ALIAS_FAUX" '{name: $n, mount_accessor: .accessor, canonical_id: .groupe_id}' <<<"$g" \
    | m25_api POST "identity/group-alias/id/$(jq -r .alias_id <<<"$g")" - >/dev/null || return 1
  m25_journal E40 "alias du groupe $_E40_GROUPE renommé $_E40_ALIAS_FAUX"
}

verifier_E40() {
  local p g
  m25_jeton_charger || return 1
  case "$WB_VAR" in
    1) p="$(_e40_politique "$_E40_POL")"; grep -qF 'path "kv/data/mediagenda/+"' <<<"$p" && ! grep -qF 'kv/data/mediagenda/dev/*' <<<"$p" ;;
    2) p="$(_e40_politique "$_E40_POL")"; grep -qF 'path "kv/mediagenda/dev/*"' <<<"$p" && ! grep -qF 'kv/data/mediagenda/dev/*' <<<"$p" ;;
    3) g="$(_e40_groupe)"; jq -e --arg gel "$_E40_GEL" '(.data.policies // []) | index($gel) != null' >/dev/null 2>&1 <<<"$g" ;;
    4) g="$(_e40_groupe)"; jq -e --arg n "$_E40_ALIAS_FAUX" '.data.alias.name == $n' >/dev/null 2>&1 <<<"$g" ;;
    *) return 1 ;;
  esac
}

annuler_E40() {
  local g p
  if ! m25_jeton_charger; then
    wb_avert "annulation impossible sans jeton plateforme-admin : connecte-toi puis relance « lab/bin/break 25 40 --annuler »"
    wb_avert "(ou rejoue plateforme/secrets : tofu apply ramène tout sauf la politique $_E40_GEL, à supprimer)"
    return 0
  fi
  if m25_existe E40 politique.hcl; then
    m25_lire E40 politique.hcl | _e40_ecrire_politique "$_E40_POL" || wb_avert "politique $_E40_POL non restaurée"
  fi
  g="$(m25_lire E40 groupe.json)"
  if [[ -n "$g" ]]; then
    jq -c '{policies: .policies}' <<<"$g" | m25_api POST "identity/group/name/$_E40_GROUPE" - >/dev/null \
      || wb_avert "politiques du groupe $_E40_GROUPE non restaurées"
    jq -c '{name: .alias_nom, mount_accessor: .accessor, canonical_id: .groupe_id}' <<<"$g" \
      | m25_api POST "identity/group-alias/id/$(jq -r .alias_id <<<"$g")" - >/dev/null \
      || wb_avert "alias du groupe $_E40_GROUPE non restauré"
  fi
  p="$(_e40_politique "$_E40_GEL")"
  if grep -q 'M25-E40' <<<"$p"; then
    m25_api DELETE "sys/policies/acl/$_E40_GEL" >/dev/null || wb_avert "politique $_E40_GEL non supprimée"
  fi
  m25_journal E40 "annulation"
  m25_oublier E40 politique.hcl
  m25_oublier E40 groupe.json
}

symptome_E40() {
  wb_symptome "INC-5240 — De : Julien Petit — « permission denied » sur nos secrets de développement" \
    "Depuis ce matin (après reconnexion par le SSO), toute lecture ou écriture sous kv/mediagenda/dev/" \
    "répond « permission denied », en CLI comme dans l'interface web. Julien est toujours dans le" \
    "groupe mediagenda de l'annuaire et n'a rien changé. Si son jeton d'hier marche encore, demande-lui" \
    "de se reconnecter avant de conclure." \
    "Temps cible : 40 min. Contrôle : lab/bin/check 25 40"
}

resume_E40() { echo "Julien (mediagenda) reçoit « permission denied » sur kv/mediagenda/dev/ depuis sa reconnexion"; }

if [[ -z "${WB_PANNES_LIB:-}" ]]; then
  main() { wb_main 25 E40 4 "$@"; }
fi
