# Revue de la MR !3 — plateforme/inventaire-images (M26-E22)

> Proposition de corrigé de `~/m26/e22/revue.md`. Gravité : **B** bloquant (on ne fusionne pas),
> **M** majeur (à corriger dans cette MR), **m** mineur (à corriger, peut suivre).
> Version corrigée : [`inventaire-images/`](inventaire-images/).

| # | Fichier : ligne | Défaut | Conséquence concrète | Correction | Grav. |
|---|---|---|---|---|---|
| 1 | `values.yaml` `harbor.token` ; `deployment.yaml` env `HARBOR_TOKEN` | Jeton du robot Harbor **en clair dans Git** | Toute personne qui lit le dépôt (et son historique, pour toujours) pousse ou tire dans Harbor avec ce robot | Jeton dans OpenBao (`kv/plateforme/inventaire/harbor`), `ExternalSecret`, `secretKeyRef` ; **révoquer** le jeton exposé (RB-250) : le retirer du fichier ne suffit pas | B |
| 2 | `Dockerfile` `ARG HARBOR_TOKEN` / `ENV HARBOR_TOKEN=$HARBOR_TOKEN` | Secret **dans l'image** | Visible par `docker history`/`crane config` pour quiconque tire l'image, copié dans chaque réplication | Aucun secret au build ; à l'exécution seulement (même révocation) | B |
| 3 | `deployment.yaml` volume `hostPath: /var/run/containerd/containerd.sock` | Socket du runtime monté | Piloter containerd = lancer un conteneur privilégié sur le nœud = root sur le nœud, et lire tous les conteneurs | Lire les images dans l'API (`status.containerStatuses[].imageID`) ; aucun montage de l'hôte | B |
| 4 | `deployment.yaml` `securityContext.privileged: true` | Conteneur privilégié | Tous les périphériques et toutes les capacités de l'hôte : une faille de l'appli = l'hôte | Supprimé ; contexte « charge sûre » complet (C1-C5) | B |
| 5 | `rbac.yaml` ClusterRole `*`/`*`/`*` + ClusterRoleBinding | Rôle équivalent à `cluster-admin` | Le jeton du pod (monté) lit tous les Secrets et peut tout modifier | ClusterRole `get/list/watch` sur `pods` seulement ; corriger le code qui faisait des appels inutiles | B |
| 6 | `deployment.yaml` `hostNetwork: true` | Réseau de l'hôte | Contourne toutes les politiques réseau, voit les ports locaux du nœud (kubelet, etcd sur un nœud de contrôle) | Supprimé | B |
| 7 | `service.yaml` `type: LoadBalancer` + IP 10.10.41.80 | Page publiée **sans authentification** | La liste des vulnérabilités de toutes nos images, lisible depuis tout le réseau du lab (annoncée en BGP) : une carte pour un attaquant ; adresse de `lb-par1` prise sans réservation (NetBox) ni MR de la plateforme | `ClusterIP` ; publication éventuelle par HTTPRoute derrière OAuth2 Proxy (M24, groupe `securite`) | B |
| 8 | `deployment.yaml` `capabilities.add: [NET_ADMIN, SYS_PTRACE]` | Capacités ajoutées | `NET_ADMIN` : modifier le réseau (avec `hostNetwork` : celui du nœud) ; `SYS_PTRACE` : lire la mémoire d'autres processus | `drop: [ALL]`, aucun ajout | M |
| 9 | `networkpolicy.yaml` `ingress: [{}]`, `egress: [{}]` | Politique « tout autoriser » | Annule le refus par défaut de l'espace : exfiltration libre | Entrée : passerelle ; sorties : DNS, API, Harbor (`CiliumNetworkPolicy`) | M |
| 10 | `Dockerfile` `FROM python:latest` | Image de base flottante, tirée de Docker Hub | Construction non reproductible, image non analysée ni signée, tirée hors de Harbor | Image de la bibliothèque MédiSphère par condensé ; deux étapes | M |
| 11 | `Dockerfile` (pas de `USER`) ; manifeste sans `runAsNonRoot` | Processus root | Root dans le conteneur ; refusé par Pod Security `restricted` (Lucas a déployé dans `default`, sans étiquette Pod Security) | `USER 10004:10004`, `runAsNonRoot`, UID explicites | M |
| 12 | `Dockerfile` `apt-get install curl vim netcat-openbsd tcpdump gcc` | Outils de débogage et compilateur dans l'image | Une boîte à outils offerte à l'attaquant (téléchargement, reverse shell, capture, compilation) ; plus de CVE | Rien dans l'image finale ; débogage par `kubectl debug` (conteneur éphémère) | M |
| 13 | `Dockerfile` `ADD https://dl.k8s.io/…/kubectl` + `chmod 777` | Binaire téléchargé sans vérification, modifiable par tous | Contenu non vérifié ; un processus non root peut le remplacer | Inutile (client Python) ; sinon empreinte vérifiée et `0755` | M |
| 14 | `deployment.yaml` image `:latest`, `imagePullPolicy: Always` | Étiquette mobile | On ne sait pas ce qui tourne ; deux pods peuvent exécuter deux versions ; refusé par la VAP `medisphere-images` (M14) dans un espace d'équipe | `v0.1.0@sha256:…` (Harbor : `v*` immuables, signature) | M |
| 15 | `values.yaml` `resources: {}` ; manifeste sans `resources` | Pas de demandes ni de limite mémoire | Ordonnancement aveugle, fuite mémoire qui affame le nœud ; refusé par `exiger-limites` dans un espace d'équipe | `requests` CPU/mémoire, `limits` mémoire | M |
| 16 | `*.yaml` `namespace: default` | Espace `default` | Aucun Pod Security, aucun quota, aucune politique de l'équipe ; mélange avec tout ce qui y traîne | Espace `inventaire` (restricted, `medisphere.internal/equipe: plateforme`) créé par `plateforme/k8s` | M |
| 17 | `deployment.yaml` pas de `readOnlyRootFilesystem`, pas de seccomp | Système de fichiers inscriptible, pas de filtre d'appels système | Dépôt d'outils dans le conteneur, surface noyau complète | C3, C5 de la norme | m |
| 18 | `Dockerfile` `pip install -r requirements.txt` | Dépendances non épinglées par empreinte | Un paquet modifié sur l'index passe | `--require-hashes` | m |
| 19 | `deployment.yaml` sans sondes | Pas de `readinessProbe`/`livenessProbe` | Trafic envoyé à un pod pas prêt ; pod bloqué jamais redémarré | Sondes `/pret`, `/sante` | m |

## Erreurs ou choix ?

- **Erreurs** (le résultat contredit l'intention ou une règle écrite) : 1 à 7, 9, 14, 16.
- **Choix à discuter avec Lucas** : la publication de la page (7 : faut-il la publier ?), la fréquence de
  rafraîchissement (charge sur Harbor), le passage par l'API plutôt que par containerd (3 : il voulait
  « aller plus vite » ; l'API suffit largement à cette échelle).

## Commentaire de revue (MR !3)

> Merci Lucas, l'outil répond à un vrai besoin et le code est clair. Je bloque la fusion pour trois raisons,
> par ordre d'urgence :
> 1. **Le jeton du robot Harbor est compromis** (dans `values.yaml`, le manifeste et l'image). Je l'ai
>    révoqué dans Harbor ; le nouveau est dans OpenBao, lu par un `ExternalSecret`. Plus jamais de secret
>    au build ni dans Git (RB-250).
> 2. **Le pod a les clés du cluster** : socket containerd, `privileged`, `hostNetwork` et un rôle `*`. Tu
>    n'as besoin que de lire les pods : `status.containerStatuses[].imageID` te donne le condensé exact,
>    sans toucher aux nœuds. Rôle réduit à `pods` en lecture.
> 3. **La page des vulnérabilités ne se publie pas sans authentification** : `ClusterIP` pour l'instant ;
>    on la mettra derrière OAuth2 Proxy si Sophie veut l'ouvrir.
>
> Le reste (image de base, utilisateur, outils de débogage, ressources, espace) est dans ma branche
> `revue-e22`, avec la norme « charge sûre » en lien. On en parle demain dix minutes ?
