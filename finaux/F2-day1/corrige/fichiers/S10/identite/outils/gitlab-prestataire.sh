#!/usr/bin/env bash
# outils/gitlab-prestataire.sh — accès GitLab d'une personne d'une équipe externe (F2-S10, SEC-3210).
# Rangé dans plateforme/identite, appelé par la CI de l'équipe en code (S02) pour les équipes ext-*, ou
# à la main pour un essai. Idempotent. Jeton : GITLAB_TOKEN (compte de service svc-synchro-identite,
# administrateur : seul un administrateur peut marquer un utilisateur « externe »), jamais en argument.
#
# Usage : gitlab-prestataire.sh --projet GROUPE/PROJET --expiration AAAA-MM-JJ [--niveau developer|reporter]
#                               [--groupe-propre GROUPE] [--simulation] IDENTIFIANT…
#
# Pour chaque personne :
#   1. l'utilisateur GitLab existe (créé à la première connexion SSO) : sinon, signalé et ignoré ;
#   2. il est marqué EXTERNE (il ne voit pas les projets internes, ne crée ni groupe ni projet) ;
#   3. il est membre DIRECT du projet, au niveau donné, avec la date d'expiration (GitLab le retire
#      seul à cette date) ; aucune appartenance de groupe n'est créée, et toute appartenance à un groupe
#      autre que le groupe propre de l'équipe (--groupe-propre, créé par l'équipe en code) est signalée.
# Codes retour : 0 succès, 1 erreur, 2 usage, 3 au moins une personne absente de GitLab.
set -euo pipefail

GITLAB_URL="${GITLAB_URL:-https://git01.par1.medisphere.internal}"
usage() { sed -n 's/^# Usage : //p; s/^#                               /    /p' "${BASH_SOURCE[0]}" | head -n 2 >&2; exit 2; }

api() {
  local m="$1" p="$2"
  shift 2
  curl -sf --max-time 30 -X "$m" -H @<(printf 'PRIVATE-TOKEN: %s\n' "$GITLAB_TOKEN") "$GITLAB_URL/api/v4/$p" "$@"
}
enc() { jq -rn --arg s "$1" '$s|@uri'; }

main() {
  local projet="" expiration="" niveau=developer simulation=0 absent=0 propre="" gpropre=0 u uid pid acces m
  while (($#)); do
    case "$1" in
      --projet) (($# >= 2)) || usage; projet="$2"; shift 2 ;;
      --expiration) (($# >= 2)) || usage; expiration="$2"; shift 2 ;;
      --niveau) (($# >= 2)) || usage; niveau="$2"; shift 2 ;;
      --groupe-propre) (($# >= 2)) || usage; propre="$2"; shift 2 ;;
      --simulation) simulation=1; shift ;;
      -h | --help) usage ;;
      --) shift; break ;;
      -*) usage ;;
      *) break ;;
    esac
  done
  (($# >= 1)) && [[ -n "$projet" && "$expiration" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
  case "$niveau" in developer) acces=30 ;; reporter) acces=20 ;; *) usage ;; esac
  [[ -n "${GITLAB_TOKEN:-}" ]] || { echo "GITLAB_TOKEN absent" >&2; exit 1; }
  (( $(date -d "$expiration" +%s) > $(date +%s) )) || { echo "date d'expiration passée : $expiration" >&2; exit 2; }

  pid="$(api GET "projects/$(enc "$projet")" | jq -r '.id // empty')" || { echo "projet introuvable : $projet" >&2; exit 1; }
  [[ -n "$pid" ]] || { echo "projet introuvable : $projet" >&2; exit 1; }

  if [[ -n "$propre" ]]; then
    gpropre="$(api GET "groups/$(enc "$propre")" | jq -r '.id // 0')" || gpropre=0
  fi

  for u in "$@"; do
    uid="$(api GET "users?username=$(enc "$u")" | jq -r '.[0].id // empty')"
    if [[ -z "$uid" ]]; then
      echo "$u : pas encore d'utilisateur GitLab (première connexion SSO à faire) — ignoré" >&2
      absent=1
      continue
    fi
    if ((simulation)); then
      echo "$u (id $uid) : serait marqué externe et membre $niveau de $projet jusqu'au $expiration"
      continue
    fi
    api PUT "users/$uid" --data-urlencode "external=true" >/dev/null
    if m="$(api GET "projects/$pid/members/$uid" 2>/dev/null)"; then
      if ! jq -e --argjson a "$acces" --arg e "$expiration" '.access_level == $a and .expires_at == $e' <<<"$m" >/dev/null; then
        api PUT "projects/$pid/members/$uid" --data-urlencode "access_level=$acces" --data-urlencode "expires_at=$expiration" >/dev/null
      fi
    else
      api POST "projects/$pid/members" --data-urlencode "user_id=$uid" --data-urlencode "access_level=$acces" \
        --data-urlencode "expires_at=$expiration" >/dev/null
    fi
    # Contrôle : aucune appartenance de GROUPE (héritage) pour un prestataire, hors de son groupe propre.
    if api GET "users/$uid/memberships?per_page=100" |
      jq -e --argjson g "$gpropre" '[.[] | select(.source_type == "Namespace" and .source_id != $g)] | length > 0' >/dev/null; then
      echo "ATTENTION : $u est membre d'un groupe GitLab autre que ${propre:-le sien} (accès hérités) : à retirer" >&2
      exit 1
    fi
    echo "$u : externe, $niveau de $projet jusqu'au $expiration"
  done
  ((absent == 0)) || exit 3
}

main "$@"
