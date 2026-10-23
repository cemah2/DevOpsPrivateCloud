# Revue des changements du trimestre (F4)

> Revue après mise en œuvre, sans recherche de coupable. Chiffres : fiches CHG et sonde de continuité
> (F4-S02). Exemple de structure : les valeurs sont les tiennes.

## Synthèse
| CHG | Objet | Catégorie | Décision | Fenêtre prévue / réelle | Interruption promise / **mesurée** | Retour arrière | Écarts |
|---|---|---|---|---|---|---|---|
| CHG-3403 | Kubernetes mineure suivante | normal | no-go (Cilium) puis <go/no-go> | — | — | — | — |
| CHG-3404 | Montée de Kubernetes (ou Cilium + remplacement immuable) | normal | | | 0 erreur 5xx, ≤ 30 s / <N> s | testé ? utilisé ? | |
| CHG-3405 | Composants de plateforme (GitOps) | normal | | | | | |
| CHG-3407 | Ceph sous charge | normal | | | | | |
| CHG-3408 | OpenStack 2026.1 → 2026.2 | normal | | | | | |
| CHG-3410 | Migration des VMs d'InfoGér | normal | fait | 2 vagues | ≤ 1 h / ≤ 2 h ; mesuré : | testé (réimport 18 min) | `AllowUsers` d'InfoGér |
| CHG-3412 | Legacy-RDV sur Kubernetes | normal | fait | sans coupure | 0 / 0 | | |
| CHG-3413 | Bascule de Legacy-RDV | normal | fait | 15 min | ≤ 900 s / <N> s | testé, non utilisé | |
| CHG-3414 | Décommissionnement de legacy-rdv01 | normal | fait | — | 0 | irréversible (sauvegarde finale) | |

## Ce qui a marché
- Les mesures de la sonde ont tranché chaque débat (« ça a coupé ? » → chiffre).
- Les no-go écrits (CHG-3403) : la chaîne de compatibilité a évité une montée cassée.
- Les répétitions : la bascule réelle a duré ce que la répétition annonçait.

## Ce qui a coûté
- Inventaire d'InfoGér faux : la dépendance `stats01` → `legacy-rdv01` découverte par l'audit hors ligne, pas par la fiche.
- …

## Actions
| Action | Responsable | Échéance | Suivi |
|---|---|---|---|
| Ajouter au modèle de fiche une ligne « copies de données recensées » | <MOI> | <DATE> | MR !<N> |
| Décommissionner `stats01` (sans lecteur) | <MOI> | trimestre suivant | CHG-35xx |
| FTPS ou SFTP avec les partenaires, fin de l'exception FTP | Sophie Laurent / Nadia Roussel | <DATE> | |
| … | | | |
