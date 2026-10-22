# formation/gitops-labo — application d'essai « labo » (M20-E04)

Petite application jetable pour apprendre Argo CD sans risquer MédiAgenda : un serveur nginx sans
privilège qui sert une page dont le texte vient d'une ConfigMap. Elle est déployée dans l'espace
`wb-essais` par Argo CD (jamais par `kubectl apply`).

| Fichier | Contenu |
|---|---|
| `k8s/kustomization.yaml` | liste des objets, étiquettes communes |
| `k8s/configmap.yaml` | ConfigMap `labo-page` : la page servie (`index.html`) |
| `k8s/deployment.yaml` | Deployment `labo` : 2 réplicas, image par le cache Harbor, sans privilège |
| `k8s/service.yaml` | Service `labo` : port 80 vers le port 8080 des pods |

Pour changer ce que sert l'application : modifie `k8s/configmap.yaml`, pousse sur `main`, et regarde
Argo CD faire le reste. Le nom de la ConfigMap reste fixe : un changement de la page ne recrée pas
les pods (nginx relit le fichier monté ; la mise à jour du volume par le kubelet prend jusqu'à une
minute environ).

Copie ce dossier tel quel à la racine du projet GitLab `formation/gitops-labo` (branche `main`).
