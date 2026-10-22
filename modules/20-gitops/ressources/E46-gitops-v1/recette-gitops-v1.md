# Recette gitops-v1 (M20-E46, PLAT-2146)

> Squelette du dossier de recette. À copier dans `docs/livraison/gitops/recette-gitops-v1.md` de
> `plateforme/medisphere`. Une ligne par exigence du ticket ; la preuve est une commande ou un lien
> (MR, pipeline, capture de sortie), jamais « fait ». Dernière ligne : la sortie de
> `lab/bin/check 20 46`, verte.

| # | Exigence | Preuve | Écart éventuel et sa justification |
|---|---|---|---|
| 1 | Toutes les applications sous ApplicationSets, racine Synced | | |
| 2 | Aucune écriture de la CI dans les espaces applicatifs | | |
| 3 | Canary + analyses en recette et en production | | |
| 4 | Une mise en production complète par MR, avec notification reçue | | |
| 5 | Notifications (échec, dégradation, déploiement de prod) | | |
| 6 | Fenêtres de synchronisation et gel des changements | | |
| 7 | RBAC par équipe, admin désactivé | | |
| 8 | Durcissement d'Argo CD (réseau, terminal, sessions, exclusions) | | |
| 9 | `lyo-k3s01` et `flux01` détruites, état `envs/m20` vide | | |
| 10 | Flux réseau du M20 retirés (bordure, matrice), DNS et NetBox nettoyés | | |
| 11 | Plus aucun cluster distant enregistré dans Argo CD | | |
| 12 | Documentation : ADR-0200, RB-200…, promotion, politique de changements, comparatif Flux, sous le capot | | |
| 13 | Étiquette `gitops-v1` posée sur `plateforme/medisphere` | | |

Contrôle global :

```
lab/bin/check 20 46
```
