# Politiques réseau de MédiAgenda (M15-E17, SEC-1617)

Manifestes **sans espace de noms** : les mêmes fichiers s'appliquent à `mediagenda-dev` et à
`mediagenda-recette` (`task politiques:mediagenda`, ou à la main) :

    kubectl apply -n mediagenda-dev     -f espaces/politiques-mediagenda/
    kubectl apply -n mediagenda-recette -f espaces/politiques-mediagenda/

Étiquettes de pods (MédiAgenda du M14, `mediagenda/api`, `k8s/dev/` et `k8s/recette/`) :
`app.kubernetes.io/name` = `mediagenda-api`, `postgresql`, `valkey`, et pour les tâches
`mediagenda-migration` (Job de chaque version) et `mediagenda-sauvegarde` (CronJob de dev).
Matrice des flux : `docs/kubernetes/reseau/flux-mediagenda.md` (plateforme/medisphere).
