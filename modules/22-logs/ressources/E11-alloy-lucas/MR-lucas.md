# MR !41 — plateforme/observabilite — « Alloy : config simplifiée »

**Auteur** : Lucas Martin — **Relecteurs demandés** : Karim Benali, toi

> Salut ! J'ai repris la config de l'agent : avec la mienne on récupère **tout** (toutes les
> étiquettes Kubernetes, tous les niveaux, tout le journal), on triera dans Grafana. J'ai aussi mis
> l'authentification que j'ai vue dans un tuto, et `latest` pour ne plus avoir à monter de version.
> J'ai vérifié : `alloy validate` passe sans erreur, donc la config est bonne.
> Il reste juste à coller le contenu de `config.alloy` dans `values.yaml` au moment du déploiement.

Fichiers : `config.alloy`, `values.yaml`.
