# Politiques réseau de MédiAgenda (M15-E17, SEC-1617)

Manifestes **sans espace de noms** : les mêmes fichiers s'appliquent à `mediagenda-dev` et à
`mediagenda-recette` (`task politiques:mediagenda`, ou à la main) :

    kubectl apply -n mediagenda-dev     -f espaces/politiques-mediagenda/
    kubectl apply -n mediagenda-recette -f espaces/politiques-mediagenda/

Étiquettes de pods supposées (MédiAgenda du M14) : `app.kubernetes.io/name: mediagenda-api`,
`postgresql`, `valkey`. Si les tiennes diffèrent, change-les ICI et seulement ici.
Matrice des flux : `docs/kubernetes/reseau/flux-mediagenda.md` (plateforme/medisphere).
