#!/usr/bin/env bash
# outils/secret-id-enveloppe.sh — délivrer le secret_id d'un rôle AppRole par ENVELOPPEMENT de réponse
# (M25-E28, SEC-2628). Projet plateforme/secrets, sur adm01, avec une session « bao login -method=oidc »
# (plateforme-admin).
#
# Demande un secret_id NEUF enveloppé (TTL d'enveloppement 5 min par défaut) et n'affiche que le
# JETON D'ENVELOPPEMENT : il ne contient pas le secret_id ; il ne sert qu'une fois ; s'il est
# intercepté et déballé par un tiers, le destinataire voit l'échec et l'audit dit qui a déballé.
# Sortie : le jeton d'enveloppement (une ligne), à passer au destinataire (variable d'Ansible
# openbao_instantane_secret_id_enveloppe, ou « bao unwrap » sur la machine de medictl).
#
# Usage : outils/secret-id-enveloppe.sh <RÔLE> [TTL=5m]      ex. outils/secret-id-enveloppe.sh medictl
set -euo pipefail
role="${1:?usage : $0 <RÔLE> [TTL]}"
ttl="${2:-5m}"
[[ "$role" =~ ^[a-z0-9-]+$ ]] || { echo "nom de rôle invalide" >&2; exit 2; }
command -v bao >/dev/null || { echo "bao absent" >&2; exit 2; }
bao token lookup >/dev/null 2>&1 || { echo "aucune session OpenBao : bao login -method=oidc" >&2; exit 2; }
# -field=wrapping_token : seule la valeur du jeton d'enveloppement sort (pas d'accessor, pas de
# secret_id). Les métadonnées du secret_id (accessor) se lisent après coup par sys/wrapping/lookup.
bao write -f -wrap-ttl="$ttl" -field=wrapping_token "auth/approle/role/$role/secret-id"
