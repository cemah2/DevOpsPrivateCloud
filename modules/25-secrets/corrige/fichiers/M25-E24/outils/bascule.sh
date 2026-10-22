#!/usr/bin/env bash
# outils/bascule.sh — mesure d'une bascule du coffre (M25-E24, PLAT-2624). Rangé dans plateforme/secrets.
#
# Écrit un secret témoin toutes les 250 ms par le nom du service (la VIP), note l'heure, le résultat
# et le nœud qui a répondu, puis résume : nombre d'échecs, plus longue indisponibilité en écriture.
# À lancer sur adm01 avec une session « bao login -method=oidc » valide (jeton dans ~/.vault-token,
# lu par la CLI : aucun jeton sur la ligne de commande). Chemin témoin : kv/wb-essais/bascule (la
# politique plateforme-admin y écrit ; rien de secret n'y est écrit : un compteur).
#
# Usage : outils/bascule.sh <ÉTIQUETTE> [DURÉE_S=120]      ex. outils/bascule.sh step-down 90
#         (pendant ce temps, provoque la bascule dans un autre terminal)
# Sortie : ~/m25/e24/bascule-<ÉTIQUETTE>-<horodatage>.tsv et un résumé à l'écran.
set -Eeuo pipefail

etiquette="${1:?usage : $0 <ÉTIQUETTE> [DURÉE_S]}"
duree="${2:-120}"
[[ "$etiquette" =~ ^[a-z0-9-]+$ ]] || { echo "étiquette : minuscules, chiffres, tirets" >&2; exit 2; }
[[ "$duree" =~ ^[0-9]+$ ]] || { echo "durée en secondes" >&2; exit 2; }

export BAO_ADDR="${BAO_ADDR:-https://openbao.par1.medisphere.internal:8200}"
chemin="${BASCULE_CHEMIN:-kv/wb-essais/bascule}"
command -v bao >/dev/null || { echo "bao absent" >&2; exit 2; }
bao token lookup >/dev/null 2>&1 || { echo "aucune session OpenBao valide : bao login -method=oidc" >&2; exit 2; }

dossier="$HOME/m25/e24"
install -d -m 0700 "$dossier"
sortie="$dossier/bascule-$etiquette-$(date +%Y%m%dT%H%M%S).tsv"
printf 'epoque_ms\theure\tn\tresultat\tactif\n' >"$sortie"

fin=$(( $(date +%s) + duree ))
n=0
while (( $(date +%s) < fin )); do
  n=$((n + 1))
  t="$(date +%s%3N)"
  if bao kv put -mount="${chemin%%/*}" "${chemin#*/}" n="$n" >/dev/null 2>&1; then
    r=ok
  else
    r=echec
  fi
  # Qui est actif, vu par la VIP (sys/leader est lisible sans jeton ; vide si personne ne répond).
  actif="$(curl -s --max-time 1 "$BAO_ADDR/v1/sys/leader" 2>/dev/null | jq -r '.leader_address // empty' 2>/dev/null \
    | sed -E 's#https://([^.]+).*#\1#')" || actif=""
  printf '%s\t%s\t%s\t%s\t%s\n' "$t" "$(date +%T.%3N)" "$n" "$r" "${actif:--}" >>"$sortie"
  sleep 0.25
done

# Résumé : échecs, et plus longue fenêtre sans écriture réussie (de la dernière réussite avant
# l'échec à la première réussite après).
awk -F'\t' 'NR > 1 {
    if ($4 == "ok") {
      if (dernier_ok != "" && trou) { d = $1 - dernier_ok; if (d > max) { max = d; debut = h_ok; fin = $2 } }
      dernier_ok = $1; h_ok = $2; trou = 0
    } else { echecs++; trou = 1 }
    if ($5 != "-" && $5 != actif_prec) { if (actif_prec != "") bascules = bascules " " actif_prec "→" $5 " (" $2 ")"; actif_prec = $5 }
  }
  END {
    printf "écritures : %d, échecs : %d\n", NR - 1, echecs + 0
    if (max > 0) printf "plus longue indisponibilité en écriture : %.2f s (de %s à %s)\n", max / 1000, debut, fin
    else print "aucune indisponibilité en écriture"
    printf "changements de nœud actif :%s\n", (bascules == "" ? " aucun" : bascules)
  }' "$sortie"
echo "détail : $sortie"
