# Données après la reconstruction de `k8s-par1` (CHG-3107)

> Modèle du corrigé de F1-S11. Les valeurs sont les tiennes. Les lignes « rendez-vous » gardent ce
> format (le contrôle `lab/bin/check F1 11` lit les deux premiers nombres de chaque ligne).

| | |
|---|---|
| Gel | <AAAA-MM-JJ HH:MM> (`~/day0/compteurs-gel.txt`, 10-gel.sh) |
| Comparaison | <AAAA-MM-JJ HH:MM>, **avant** la réouverture (60-donnees.sh, étape 3) |
| Méthode | `SELECT count(*) FROM rendez_vous` sur le primaire (`kubectl cnpg psql`), au gel puis après la récupération ; files : API de gestion de RabbitMQ (compte `wb-checks`) ; ExternalSecrets et certificats : `kubectl get … -A` |

## Comparaison

| Élément | Au gel | Après |
|---|---|---|
| rendez-vous (prod) | <N> | <N> |
| rendez-vous (recette) | <N> | <N> |
| messages en file `notifications` (recette, prod) | 0, 0 | 0, 0 |
| files, vhosts, types et arguments (`files-gel.tsv`) | <N> files | identiques (aucune différence) |
| ExternalSecrets | <N> | <N> (tous `Ready`) |
| Certificats cert-manager | <N> | <N> (tous `Ready`) |
| Rendez-vous pris entre S04 et le gel | <N> (expliqués : <ex. trafic de recette des tests nocturnes>) | — |

## Bases

| Base | Récupérée depuis (`serverName`) | Archive désormais sous | Première sauvegarde après récupération | Durée de la récupération |
|---|---|---|---|---|
| `mediagenda-recette/mediagenda-db` | `mediagenda-db` | `mediagenda-db-day0` | `<nom>` <HH:MM> | <durée> |
| `mediagenda-prod/mediagenda-db` | `mediagenda-db-prod` | `mediagenda-db-prod-day0` | `<nom>` <HH:MM> | <durée> |
| `portail/portail-db` | `portail-db` | `portail-db-day0` | `<nom>` <HH:MM> | <durée> |
| `mediagenda-secours/mediagenda-db-secours` | `mediagenda-db-prod-day0` (réplica) | — (n'archive pas) | — | <durée> |

Les anciens préfixes (`mediagenda-db/`, `mediagenda-db-prod/`, `portail-db/` de `s3://cnpg-k8s-par1/`) ne
sont plus élagués par personne (la rétention de 14 jours est appliquée par le cluster qui écrit) :
même décision que les volumes RBD (`volumes-ancien-cluster.md`) : conservés jusqu'à la revue, puis
supprimés par un geste daté.

## Restauré par Velero

Rien. (Ou : objet, espace, sauvegarde, raison — un objet à la fois, jamais un espace entier.)

## OpenBao

Autorités des nouveaux clusters CNPG copiées sur `vault01-03` (MR `plateforme/ansible` !<N>,
`coffre.yml`) : identifiants dynamiques de recette et de production de nouveau délivrés à <HH:MM>.

## Réouverture

Production synchronisée en entier à <HH:MM>, annoncée par Nadia à <HH:MM>. **Coupure totale : <durée>.**
