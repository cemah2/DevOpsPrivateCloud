# Essai du chemin balisé — `medidoc-chemin-balise`

> Rédigé en M28-E25 (PLAT-2925). Chiffres du lab de référence : remplace-les par les tiens.

| Étape | Qui | Durée |
|---|---|---|
| Formulaire du modèle `nouveau-service` (locataire `medidoc`, squelette Go) | équipe | 2 min |
| Création des projets `medidoc/medidoc-chemin-balise` et `-deploiement`, enregistrement au catalogue | portail | 40 s |
| MR `plateforme/k8s` (espace `medidoc-chemin-balise-dev`) et `plateforme/gitops` (Application) relues et fusionnées | Plateforme | 10 min |
| Premier pipeline (construction BuildKit, analyse, signature, poussée Harbor) | CI | 6 min |
| MR de promotion en dev fusionnée, synchronisation Argo CD, pod prêt | équipe + Argo CD | 3 min |
| Documentation TechDocs publiée et visible | CI + portail | 2 min |
| **Total** | | **≈ 24 min** (contre dix jours et six tickets) |

## Retrait (ordre inverse de la création)
1. Application Argo CD supprimée par MR dans `plateforme/gitops` (elle supprime les objets de l'espace).
2. Espace `medidoc-chemin-balise-dev` supprimé par MR dans `plateforme/k8s`.
3. Entités du catalogue désenregistrées (emplacement supprimé), sinon elles réapparaissent par la découverte tant que les projets existent.
4. Projets GitLab supprimés (après vérification : aucune MR ouverte, aucune image à garder ; dépôt Harbor vidé).
5. Vérification : `kubectl get ns | grep chemin-balise`, catalogue, GitLab, Harbor : plus rien.
