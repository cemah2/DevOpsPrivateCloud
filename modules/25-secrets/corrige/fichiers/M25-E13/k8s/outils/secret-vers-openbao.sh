#!/usr/bin/env bash
# outils/secret-vers-openbao.sh — recopie un Secret EXISTANT du cluster vers un chemin KV v2 d'OpenBao,
# clés et valeurs identiques, sans rien afficher ni écrire sur le disque (M25-E13, PLAT-2613).
#
#   outils/secret-vers-openbao.sh copier   <espace> <secret> <chemin-kv>   # ex. supervision grafana-admin plateforme/grafana/admin
#   outils/secret-vers-openbao.sh comparer <espace> <secret> <chemin-kv>   # empreintes clé par clé, sans valeur
#
# Codes : 0 identique (ou copié), 1 erreur ou différence, 2 usage, 3 coffre illisible pour toi (les
# secrets d'APPLICATION sont en écriture seule pour plateforme-admin : comparer après synchronisation).
#
# Prérequis : kubectl avec un contexte qui lit les Secrets (plateforme-admins, ou admin.conf en bris de
# glace) ; session OpenBao qui peut écrire le chemin (« bao login -method=oidc », plateforme-admin).
# Refuse d'écraser un chemin KV qui a déjà une version (une recopie ne doit jamais effacer une valeur
# plus récente du coffre). Les valeurs ne passent que par des tubes : ni argument de processus, ni
# fichier, ni écran. Valeurs TEXTE seulement (un Secret binaire est refusé : KV v2 stocke du JSON).
set -euo pipefail

usage() { echo "Usage : $0 copier|comparer <espace> <secret> <chemin-kv>" >&2; exit 2; }
(($# == 4)) || usage
action="$1" espace="$2" secret="$3" chemin="$4"
[[ "$chemin" =~ ^[a-z0-9][a-z0-9/_-]*$ && "$chemin" != *//* ]] || { echo "chemin KV invalide : $chemin" >&2; exit 2; }
for c in kubectl bao jq sha256sum base64; do command -v "$c" >/dev/null || { echo "outil manquant : $c" >&2; exit 2; }; done
export BAO_ADDR="${BAO_ADDR:-https://openbao.par1.medisphere.internal:8200}"

# Les données du Secret (base64), jamais décodées à l'écran.
donnees_secret() { kubectl get secret "$secret" -n "$espace" -o json | jq -c '.data // {}'; }

empreinte() { sha256sum | cut -c1-16; }

case "$action" in
  copier)
    if bao kv metadata get -mount=kv "$chemin" >/dev/null 2>&1; then
      echo "refus : kv/$chemin existe déjà (versions présentes) ; compare plutôt : $0 comparer $espace $secret $chemin" >&2
      exit 1
    fi
    d="$(donnees_secret)" || { echo "Secret $espace/$secret illisible" >&2; exit 1; }
    [[ "$(jq 'length' <<<"$d")" -gt 0 ]] || { echo "Secret $espace/$secret vide" >&2; exit 1; }
    # Refus des valeurs non UTF-8 (binaires) : @base64d les altérerait.
    while IFS= read -r cle; do
      if ! jq -r --arg k "$cle" '.[$k]' <<<"$d" | base64 -d | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
        echo "refus : la clé « $cle » n'est pas du texte UTF-8 (binaire) ; à traiter à part" >&2
        exit 1
      fi
    done < <(jq -r 'keys[]' <<<"$d")
    jq 'map_values(@base64d)' <<<"$d" | bao kv put -mount=kv "$chemin" - >/dev/null
    bao kv metadata put -mount=kv -max-versions=10 \
      -custom-metadata=origine="secret:$espace/$secret" -custom-metadata=ticket=PLAT-2613 "$chemin" >/dev/null
    echo "[OK] $espace/$secret → kv/$chemin ($(jq -r 'keys | join(", ")' <<<"$d"))"
    rc=0
    "$0" comparer "$espace" "$secret" "$chemin" || rc=$?
    if ((rc == 3)); then
      echo "[--] comparaison impossible : ta politique ne lit pas kv/$chemin (dépôt en écriture seule des"
      echo "     secrets d'application) ; compare après la synchronisation : outils/secrets-k8s.sh verifier <composant>"
      rc=0
    fi
    exit "$rc"
    ;;
  comparer)
    d="$(donnees_secret)" || { echo "Secret $espace/$secret illisible" >&2; exit 1; }
    kv="$(bao kv get -mount=kv -format=json "$chemin" 2>/dev/null | jq -c '.data.data')" || kv=""
    [[ -n "$kv" && "$kv" != null ]] || { echo "kv/$chemin illisible (absent, ou politique sans lecture)" >&2; exit 3; }
    ko=0
    while IFS= read -r cle; do
      a="$(jq -r --arg k "$cle" '.[$k]' <<<"$d" | base64 -d | empreinte)"
      if jq -e --arg k "$cle" 'has($k)' <<<"$kv" >/dev/null; then
        b="$(jq -j --arg k "$cle" '.[$k]' <<<"$kv" | empreinte)"
      else
        b="(absente)"
      fi
      if [[ "$a" == "$b" ]]; then echo "[OK] $cle : empreinte $a"; else echo "[KO] $cle : Secret $a ≠ coffre $b"; ko=1; fi
    done < <(jq -r 'keys[]' <<<"$d")
    extra="$(jq -r --argjson s "$d" 'keys - ($s | keys) | join(", ")' <<<"$kv")"
    [[ -z "$extra" ]] || { echo "[KO] clés du coffre absentes du Secret : $extra"; ko=1; }
    exit "$ko"
    ;;
  *) usage ;;
esac
