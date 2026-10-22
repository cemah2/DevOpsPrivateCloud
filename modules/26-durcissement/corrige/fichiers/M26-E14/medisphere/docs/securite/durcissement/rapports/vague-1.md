# Vague 1 — <AAAA-MM-JJ> (M26-E14, CHG-2714)

Hôtes : `mon01`, `nbx01`, `s3-01`. Exécution : `<toi>` ; relecture du `--check --diff` : Karim Benali.
Sessions de secours ouvertes : oui (trois sessions root). Instantanés PBS du jour : oui.

| Hôte | CIS avant | CIS après | ANSSI avant | ANSSI après | Exceptions | Redémarrage requis |
|---|---|---|---|---|---|---|
| mon01 | <score> | <score> | <score> | <score> | 3 (communes) | non (/tmp déjà en tmpfs) |
| nbx01 | <score> | <score> | <score> | <score> | 4 (+ service_nginx_disabled) | non |
| s3-01 | <score> | <score> | <score> | <score> | 3 | non |

Scores : `playbooks/conformite-mesure.yml -e vague=1 -e moment=avant|apres` ; rapports HTML dans
`~/m26/conformite/<hôte>/` sur `adm01` (non versionnés : ils décrivent les faiblesses de l'hôte).

## Incidents et retours arrière

<aucun | description, durée, retour arrière appliqué>

## Écarts restants (règles en échec, non justifiées) et décision

| Règle | Hôtes | Pourquoi elle échoue | Décision (corriger dans le rôle / exception RB-261 / accepter jusqu'à…) |
|---|---|---|---|

## Exceptions ajoutées

<lien vers la MR de group_vars/all/durcissement.yml, validée par Sophie Laurent>
