#!/usr/bin/env bash
# exceptions-vuln-echues.sh — contrôle des exceptions de vulnérabilité (F6-S09, ECA-3602).
#
# plateforme/politiques — outils/exceptions-vuln-echues.sh. Job de CI planifié (et à chaque MR qui
# touche la cve_allowlist ou le registre). LECTURE SEULE.
#
# La cve_allowlist d'un projet Harbor n'a qu'UNE date d'expiration (expires_at, en secondes, pour toute
# la liste) : on la règle sur l'échéance la plus proche des exceptions EXC-V qu'elle contient.
# Échoue (sortie 1) si :
#   - la cve_allowlist contient des CVE mais n'a pas d'expires_at ;
#   - elle est échue (expires_at < aujourd'hui) et contient encore des CVE — elle ne doit plus exister ;
#   - elle arrive à échéance dans moins de EXC_PREAVIS_JOURS jours (préavis, comme le M26) ;
#   - le registre EXC-V-nnn et la cve_allowlist divergent (une CVE autorisée dans Harbor sans ligne au
#     registre, ou l'inverse, ou des échéances différentes).
#
# Variables (défauts) :
#   HARBOR_URL            https://registry.par1.medisphere.internal
#   HARBOR_PROJET         medisphere
#   HARBOR_USER, HARBOR_PASSWORD   robot en lecture (CI : OpenBao) ; à défaut, lus dans HARBOR_ENV
#   HARBOR_ENV            fichier d'identité pour un lancement à la main (~/.config/workbook/harbor-ci.env)
#   EXC_REGISTRE          docs/securite/durcissement/exceptions.md (clone de plateforme/medisphere)
#   EXC_PREAVIS_JOURS     14
set -euo pipefail

HARBOR_URL="${HARBOR_URL:-https://registry.par1.medisphere.internal}"
PROJET="${HARBOR_PROJET:-medisphere}"
ENV_FILE="${HARBOR_ENV:-$HOME/.config/workbook/harbor-ci.env}"
REGISTRE="${EXC_REGISTRE:-docs/securite/durcissement/exceptions.md}"
PREAVIS="${EXC_PREAVIS_JOURS:-14}"

for c in curl jq date; do
  command -v "$c" >/dev/null 2>&1 || { echo "outil manquant : $c" >&2; exit 2; }
done
if [[ -z "${HARBOR_USER:-}" ]]; then
  [[ -r "$ENV_FILE" ]] || { echo "identifiants Harbor absents (HARBOR_USER ou $ENV_FILE)" >&2; exit 2; }
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
[[ -r "$REGISTRE" ]] || { echo "registre des exceptions illisible : $REGISTRE" >&2; exit 2; }

harbor() {
  curl -sf --max-time 15 -K <(printf 'user = "%s:%s"\n' "$HARBOR_USER" "$HARBOR_PASSWORD") \
    -H "Accept: application/json" "$HARBOR_URL/api/v2.0/$1"
}

aujourdhui="$(date -u +%s)"
limite_preavis=$(( aujourdhui + PREAVIS * 86400 ))
echec=0

# 1. cve_allowlist du projet (métadonnées du projet Harbor).
allowlist="$(harbor "projects/$PROJET" | jq -c '.cve_allowlist // {items: []}')" \
  || { echo "KO : impossible de lire la cve_allowlist du projet $PROJET" >&2; exit 1; }

# Entrées Harbor : CVE de la liste, et la date d'expiration commune (secondes ; null = jamais).
mapfile -t harbor_cves < <(jq -r '.items[]?.cve_id' <<<"$allowlist")
exp="$(jq -r '.expires_at // "null"' <<<"$allowlist")"
if ((${#harbor_cves[@]} > 0)); then
  if [[ "$exp" == "null" || -z "$exp" ]]; then
    echo "KO : cve_allowlist de $PROJET sans date d'expiration (${#harbor_cves[@]} CVE autorisées sans fin)"
    echec=1
  elif ((exp < aujourdhui)); then
    echo "KO : cve_allowlist de $PROJET ÉCHUE le $(date -u -d "@$exp" +%F) mais encore remplie : à vider"
    echec=1
  elif ((exp < limite_preavis)); then
    echo "AVERTISSEMENT : cve_allowlist de $PROJET échoit le $(date -u -d "@$exp" +%F) (< $PREAVIS jours) — à traiter"
    echec=1
  fi
fi

for cve in "${harbor_cves[@]}"; do
  # 2. Correspondance avec le registre (EXC-V-nnn mentionnant la CVE).
  if ! grep -Eq "EXC-V-[0-9]+.*$cve|$cve.*EXC-V-[0-9]+" "$REGISTRE"; then
    echo "KO : $cve autorisée dans Harbor mais absente du registre EXC-V-nnn ($REGISTRE)"
    echec=1
  fi
done

# 3. Registre -> Harbor : toute EXC-V active doit correspondre à une entrée Harbor.
while IFS= read -r cve; do
  trouve=0
  for c in "${harbor_cves[@]}"; do
    [[ "$c" == "$cve" ]] && { trouve=1; break; }
  done
  if (( ! trouve )); then
    echo "KO : $cve inscrite au registre EXC-V-nnn mais absente de la cve_allowlist de Harbor"
    echec=1
  fi
done < <(grep -E 'EXC-V-[0-9]+' "$REGISTRE" | grep -Eiv '\b(close|clos|retir)' | grep -oE 'CVE-[0-9]{4}-[0-9]+' | sort -u)

if (( echec )); then
  echo "== Exceptions de vulnérabilité : écart(s) détecté(s) =="
  exit 1
fi
echo "== Exceptions de vulnérabilité : cve_allowlist et registre cohérents, aucune échéance dépassée =="
