#!/usr/bin/env bash
# creer-mr-lucas.sh — M01-E21 : Lucas Martin (stagiaire) ouvre une merge request à relire.
#
# Usage (depuis adm01) :
#   modules/01-git/ressources/M01-E21/creer-mr-lucas.sh
#
# Effets sur plateforme/medisphere, une seule fois, au nom de lucas.martin
# (jeton d'emprunt d'identité d'un jour, révoqué en fin de script) :
#   - branche lucas/verif-certificats, 4 commits créés par l'API ;
#   - merge request vers main, avec toi ($WB_MOI) comme relecteur.
# Le « jeton GitLab » écrit par Lucas dans son script est FACTICE (il ne donne accès à rien),
# mais il a la forme d'un vrai : traite-le comme tel dans ta revue.
set -euo pipefail

WB_EX="M01-E21"
# shellcheck source=../lib/gitlab-ressources.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/gitlab-ressources.sh"

PROJET="plateforme/medisphere"
BRANCHE="lucas/verif-certificats"
AUTEUR_NOM="Lucas Martin"
AUTEUR_MAIL="lucas.martin.perso@example.org"

[[ $# -eq 0 ]] || { echo "Usage : $0" >&2; exit 2; }
gl_prerequis_api base64
pid="$(gl_id_projet "$PROJET")"
[[ -n "$pid" ]] || gl_erreur "projet $PROJET introuvable (voir M01-E06)"
if gl_api GET "projects/$pid/repository/branches/$(gl_enc "$BRANCHE")" >/dev/null 2>&1; then
  gl_erreur "la branche $BRANCHE existe déjà : la MR de Lucas est déjà créée."
fi

tmp="$(mktemp -d)"
trap 'gl_rendre_jetons; rm -rf "$tmp"' EXIT
gl_emprunter lucas.martin JETON_LUCAS

# commit_lucas MESSAGE FICHIER_ACTIONS_JSON — crée un commit sur la branche, au nom de Lucas
commit_lucas() {
  jq -c --arg b "$BRANCHE" --arg m "$1" --arg n "$AUTEUR_NOM" --arg e "$AUTEUR_MAIL" \
     '{branch:$b, commit_message:$m, author_name:$n, author_email:$e, actions:.}' "$2" > "$tmp/corps.json"
  _gl_appel "$JETON_LUCAS" POST "projects/$pid/repository/commits" \
    -H 'Content-Type: application/json' --data-binary @"$tmp/corps.json" >/dev/null
}

gl_api_jeton "$JETON_LUCAS" POST "projects/$pid/repository/branches" \
  "$(jq -nc --arg b "$BRANCHE" '{branch:$b, ref:"main"}')" >/dev/null

# --- 1. Le script, première version ------------------------------------------------------------
cat > "$tmp/script-v1.sh" <<'EOF'
#!/bin/bash
# script de Lucas pour verifier les certificats du socle

HOSTS="10.10.20.12 10.10.20.10 pve01"

for h in $HOSTS
do
  date_fin=$(echo | openssl s_client -connect $h:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
  jours=$(( ($(date -d "$date_fin" +%s) - $(date +%s)) / 86400 ))
  echo "$h : $jours jours"
done
echo "OK"
EOF
jq -n --rawfile c "$tmp/script-v1.sh" \
  '[{action:"create", file_path:"scripts/verifier-certificats.sh", content:$c}]' > "$tmp/a1.json"
commit_lucas "ajout script" "$tmp/a1.json"

# --- 2. Documentation (fins de ligne Windows) et capture d'écran ------------------------------------
printf '%s\r\n' \
  "# Certificats du socle" "" \
  "Le script scripts/verifier-certificats.sh verifie les dates d'expiration." \
  "Il cree une issue dans GitLab quand un certificat expire dans moins de 30 jours." \
  "Voir la capture pour le resultat." > "$tmp/certificats.md"
head -c 716800 /dev/urandom | base64 -w0 > "$tmp/capture.b64"
jq -n --rawfile c "$tmp/certificats.md" --rawfile p "$tmp/capture.b64" \
  '[{action:"create", file_path:"docs/socle/certificats.md", content:$c},
    {action:"create", file_path:"docs/socle/capture-certificats.png", content:$p, encoding:"base64"}]' > "$tmp/a2.json"
commit_lucas "wip" "$tmp/a2.json"

# --- 3. Création d'une issue en cas d'expiration proche ------------------------------------------
cat > "$tmp/script-v2.sh" <<'EOF'
#!/bin/bash
# script de Lucas pour verifier les certificats du socle
TOKEN=@FAUX_JETON@   # mon jeton gitlab pour creer les issues

HOSTS="10.10.20.12 10.10.20.10 pve01"

for h in $HOSTS
do
  date_fin=$(echo | openssl s_client -connect $h:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
  jours=$(( ($(date -d "$date_fin" +%s) - $(date +%s)) / 86400 ))
  echo "$h : $jours jours"
  if [ $jours -lt 30 ]; then
    curl -k -X POST -H "PRIVATE-TOKEN: $TOKEN" "https://10.10.20.12/api/v4/projects/1/issues?title=Certificat $h expire dans $jours jours"
  fi
done
echo "OK"
EOF
# Faux jeton au format GitLab, assemblé à l'exécution : un littéral « glpat-… » dans ce
# dépôt déclencherait la détection de secrets de GitHub (et c'est bien ce qu'on veut apprendre).
faux_jeton="glpat""-Lm8Qz2RtXv4Kp9WbNc7D"
sed -i "s/@FAUX_JETON@/$faux_jeton/" "$tmp/script-v2.sh"
jq -n --rawfile c "$tmp/script-v2.sh" \
  '[{action:"update", file_path:"scripts/verifier-certificats.sh", content:$c}]' > "$tmp/a3.json"
commit_lucas "fix" "$tmp/a3.json"

# --- 4. Matrice des flux (si le fichier existe) ---------------------------------------------------
if gl_api GET "projects/$pid/repository/files/$(gl_enc docs/socle/matrice-flux.md)/raw?ref=main" > "$tmp/matrice.md" 2>/dev/null; then
  printf '| adm01 | tout le lab | tous | tous | vérification des certificats (Lucas) |\n' >> "$tmp/matrice.md"
  jq -n --rawfile c "$tmp/matrice.md" \
    '[{action:"update", file_path:"docs/socle/matrice-flux.md", content:$c}]' > "$tmp/a4.json"
  commit_lucas "update matrice" "$tmp/a4.json"
fi

# --- La merge request ----------------------------------------------------------------------------
relecteurs='[]'
if [[ -n "${WB_MOI:-}" ]]; then
  relecteurs="[$(gl_id_utilisateur "$WB_MOI")]"
fi
iid="$(gl_api_jeton "$JETON_LUCAS" POST "projects/$pid/merge_requests" "$(jq -nc --arg b "$BRANCHE" --argjson r "$relecteurs" \
  '{source_branch:$b, target_branch:"main", title:"Ajout script certifs", description:"", reviewer_ids:$r,
    remove_source_branch:false}')" | jq -r .iid)"

gl_msg "Lucas a ouvert la MR !$iid dans $PROJET. À toi de la relire (ticket PLAT-231)."
