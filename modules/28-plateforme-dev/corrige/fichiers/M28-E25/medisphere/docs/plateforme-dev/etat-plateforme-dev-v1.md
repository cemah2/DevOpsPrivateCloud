# État livré `plateforme-dev-v1`

> Note de livraison (M28-E25, PLAT-2925). Étiquette `plateforme-dev-v1` sur `plateforme/medisphere`.

## Ce qui est livré
| Brique | État |
|---|---|
| Autoscaling | HPA `mediagenda` (recette 2-4, prod 3-6) ; KEDA `medinotif` (recette 0-5, prod 2-8 ; file, cron, débit de publication, repli) ; VPA en `Off` partout ; alertes KEDA |
| Capacité | `medisphere-critique` > `standard` > `ci` > `lot` ; production en `critique` avec PDB ; budgets globaux des locataires ; rapport VPA mensuel en MR ; tableau « Capacité et locataires » |
| Locataires | `mediagenda`, `medidoc`, `medinotif` (Capsule 0.15.1) ; cloison réseau par locataire ; `locataires-placement`, `locataires-pod-security` ; essais d'isolation consignés |
| Portail | Backstage 1.56.<z>, deux réplicas, `portail-db` sauvegardée, métriques et alertes, modèle `nouveau-service` éprouvé (`chemin-balise-essai.md`) |

## Ce que trouvent le M29 et les finaux
- Les essais de charge (k6-operator) tournent en classe **`medisphere-lot`** (sans préemption) dans `k6`/`wb-essais`.
- Chaos Mesh ne vise jamais `*-prod` ; les espaces des locataires sont `restricted` : un espace d'expériences de chaos est une exception à écrire.
- `docs/plateforme-dev/sous-le-capot.md` décrit les points de défaillance de l'autoscaling et des webhooks à éprouver.

## Ce qui reste à traiter
- Classe de priorité des composants de plateforme (aujourd'hui 0, sous `lot`).
- Niveau PSA par défaut du cluster (`AdmissionConfiguration`), au lieu des seules étiquettes par espace.
- Migration des champs dépréciés de Capsule 0.15 (`additionalMetadataList`, `forbiddenLabels`) vers les règles de métadonnées.
- `requests` obligatoires dans les espaces des locataires (action du post-mortem INC-5523).
