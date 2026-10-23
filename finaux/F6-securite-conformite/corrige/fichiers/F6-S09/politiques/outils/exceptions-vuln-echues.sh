#!/usr/bin/env bash
# exceptions-vuln-echues.sh — contrôle des exceptions de vulnérabilité (F6-S09, ECA-3602).
#
# plateforme/politiques — outils/exceptions-vuln-echues.sh. Job de CI planifié (et à chaque MR qui
# touche la cve_allowlist ou le registre). LECTURE SEULE.
#
# Échoue (sortie 1) si :
#   - une entrée de la cve_allowlist de Harbor n'a pas d'expires_at ;
#   - une entrée est échue (expires_at < aujourd'hui) — elle ne doit plus exister ;
#   - une entrée arrive à échéance dans moins de WB_F6_PREAVIS_JOURS jours (préavis, comme le M26) ;
#   - le registre EXC-V-nnn et la cve_allowlist divergent (une CVE autorisée dans Harbor sans ligne au
#     registre, ou l'inverse, ou des échéances différentes).
#
# Variables (défauts) :
#   WB_F6_HARBOR_URL      https://registry.par1.medisphere.internal
#   WB_F6_HARBOR_PROJET   medisphere
#   WB_F6_HARBOR_ENV      ~/.config/workbook/harbor-ci.env  (HARBOR_USER=, HARBOR_PASSWORD= ; robot CI)
#   WB_F6_REGISTRE        docs/securite/durcissement/exceptions.md  (copie locale dans le dépôt medisphere)
#   WB_F6_PREAVIS_JOURS   14
set -euo pipefail

HARBOR_URL="${WB_F6_HARBOR_URL:-https://registry.par1.medisphere.internal}"
PROJET="${WB_F6_HARBOR_PROJET:-medisphere}"
ENV_FILE="${WB_F6_HARBOR_ENV:-$HOME/.config/workbook/harbor-ci.env}"
REGISTRE="${WB_F6_REGISTRE:-docs/securite/durcissement/exceptions.md}"
PREAVIS="${WB_F6_PREAVIS_JOURS:-14}"

for c in curl jq date; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 2; }
done
[[ -r "$ENV_FILE" ]] || { echo "identifiants Harbor illisibles : $ENV_FILE" >&2; exit 2; }
[[ -r "$REGISTRE" ]] || { echo "registre des exceptions illisible : $REGISTRE" >&2; exit 2; }

harbor() {
  curl -sf --max-time 15 -K <(
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASSWORD"
  ) -H "Accept: application/json" "$HARBOR_URL/api/v2.0/$1"
}

aujourdhui="$(date -u +%s)"
limite_preavis=$(( aujourdhui + PREAVIS * 86400 ))
echec=0

# 1. cve_allowlist du projet (métadonnées du projet Harbor).
allowlist="$(harbor "projects/$PROJET" | jq -c '.cve_allowlist // {items: []}')" \
  || { echo "KO : impossible de lire la cve_allowlist du projet $PROJET" >&2; exit 1; }

# Entrées Harbor : [{cve_id, expires_at(epoch|null)}]
mapfile -t harbor_cves < <(jq -r '.items[]? | [.cve_id, (.expires_at // "null")] | @tsv' <<<"$allowlist")

for ligne in "${harbor_cves[@]}"; do
  cve="${ligne%%$'\t'*}"
  exp="${ligne##*$'\t'}"
  if [[ "$exp" == "null" || -z "$exp" ]]; then
    echo "KO : exception sans date d'expiration dans Harbor : $cve"
    echec=1
    continue
  fi
  if (( exp < aujourdhui )); then
    echo "KO : exception ÉCHUE toujours présente dans Harbor : $cve (expirée le $(date -u -d "@$exp" +%F))"
    echec=1
  elif (( exp < limite_preavis )); then
    echo "AVERTISSEMENT : exception $cve échoit le $(date -u -d "@$exp" +%F) (< $PREAVIS jours) — à traiter"
    echec=1
  fi
  # 2. Correspondance avec le registre (EXC-V-nnn mentionnant la CVE).
  if ! grep -Eq "EXC-V-[0-9]+.*$cve|$cve.*EXC-V-[0-9]+" "$REGISTRE"; then
    echo "KO : $cve autorisée dans Harbor mais absente du registre EXC-V-nnn ($REGISTRE)"
    echec=1
  fi
done

# 3. Registre -> Harbor : toute EXC-V active doit correspondre à une entrée Harbor.
while IFS= read -r cve; do
  trouve=0
  for ligne in "${harbor_cves[@]}"; do
    [[ "${ligne%%$'\t'*}" == "$cve" ]] && { trouve=1; break; }
  done
  if (( ! trouve )); then
    echo "KO : $cve inscrite au registre EXC-V-nnn mais absente de la cve_allowlist de Harbor"
    echec=1
  fi
done < <(grep -oE 'CVE-[0-9]{4}-[0-9]+' "$REGISTRE" | sort -u)

if (( echec )); then
  echo "== Exceptions de vulnérabilité : écart(s) détecté(s) =="
  exit 1
fi
echo "== Exceptions de vulnérabilité : cve_allowlist et registre cohérents, aucune échéance dépassée =="
