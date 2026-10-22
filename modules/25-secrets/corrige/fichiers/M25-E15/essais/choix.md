# M25-E15 — Redémarrer sur changement d'un Secret : le choix (modèle)

| Solution | Comment | Pour un Secret produit DANS le cluster par ESO | Pour un Rollout en `workloadRef` | Coût |
|---|---|---|---|---|
| **Reloader** (stakater) | contrôleur qui surveille les Secrets et redémarre les charges de travail annotées | oui : il voit le Secret changer, quelle qu'en soit l'origine | oui, en nommant le Secret (`secret.reloader.stakater.com/reload`) et en stratégie `restart` (`spec.restartAt`, pas de révision) | un contrôleur de plus, qui **lit les Secrets** des espaces surveillés |
| Empreinte dans le gabarit (`checksum/secret` en annotation) | Helm ou Kustomize calculent l'empreinte du contenu et l'écrivent dans le gabarit | **non** : l'outil qui rend les manifestes (Argo CD) ne connaît pas la valeur, qui n'existe que dans le cluster (et ne doit pas en sortir) | non : modifier le gabarit du Deployment = nouvelle révision = canary complet, bloqué en prod à la marche manuelle | rien à installer ; ne marche que si la valeur est dans Git (SOPS, Sealed Secrets) |
| L'application relit (fichier monté + reconnexion) | Secret monté en volume (mis à jour par le kubelet en ~1 min), l'application relit à l'échec d'authentification | oui | oui (aucun redémarrage) | code applicatif (MédiAgenda lit une variable d'environnement : ticket DEV pour Julien) |

Retenu : **Reloader 1.4.22** (chart `reloader` 2.2.18, publié le 30/09/2026, image `ghcr.io/stakater/reloader:v1.4.22`), stratégie `restart` pour les Rollouts, `annotations` pour les Deployments, limité à trois espaces. La relecture par l'application reste l'objectif (ticket DEV-2615 ouvert pour MédiAgenda).
