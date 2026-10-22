# Module 20 — Palier 1 : Découverte — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Ce corrigé suit l'ordre de l'énoncé. Les questionnaires (E01, E09) sont argumentés et les QCM expliquent pourquoi les autres options sont fausses. Les fichiers complets sont dans [`fichiers/`](fichiers/), exercice par exercice ; chaque dossier reproduit l'arborescence du projet concerné (`k8s/` pour `plateforme/k8s`, `gitops/` pour `plateforme/gitops`, `deploiement/` pour `mediagenda/deploiement`, `ansible/` pour `plateforme/ansible`, `medisphere/` pour la documentation). Un fichier n'apparaît que dans l'exercice qui le crée ou le modifie : `M20-E02/` (release, valeurs, espace), `M20-E03/` (valeurs avec les comptes, rôle `outils_k8s`, `wb-checks-livraison`), `M20-E05/` (valeurs avec le diff côté serveur), `M20-E06/` (dépôt `plateforme/gitops`, module `argocd` de `secrets-k8s.sh`), `M20-E07/` (AppProjects, objets de l'espace de production), `M20-E08/` (Application `mediagenda-dev`, base protégée, procédure). L'application d'essai est dans [`../ressources/E04-gitops-labo/`](../ressources/E04-gitops-labo/).

**Ce qui a été vérifié à la rédaction** :
- le chart **`argo/argo-cd` 10.10.5** (Argo CD **v3.5.5**, publié le 15/10/2026 dans l'index `argoproj.github.io/argo-helm`) : `helm template` (Helm 4.3.1) avec les valeurs d'E02, d'E03 et d'E05 ; rendu par **Helmfile 1.8.2** avec la base `_communs.yaml` du M17 (`helmfile build` et `template`) : `readFile` relatif au fichier de release, liste `repositories` qui **remplace** celle de la base ; 54 objets rendus, validés par `kubeconform` 0.7 (schémas Kubernetes 1.36 et Gateway API) ; tous les pods du rendu respectent Pod Security `restricted` (contrôle des `securityContext` par script) ; les NetworkPolicy créées par défaut par le chart ont été lues ;
- images : `quay.io/argoproj/argocd:v3.5.5`, `docker.io/library/redis:8.6.4-alpine`, `nginxinc/nginx-unprivileged:1.30.6-alpine` existent ; l'image nginx a été lancée en système de fichiers racine en lecture seule, `/tmp` en tmpfs, sans aucune capacité, UID 101 : elle sert la page ;
- **Argo CD v3.5.5 réellement exécuté** (binaires de l'image officielle : `argocd-server`, `argocd-repo-server`, `argocd-application-controller`) contre un plan de contrôle Kubernetes **1.36.5** réel (etcd 3.6.8, kube-apiserver et kube-controller-manager officiels, sans kubelet : les objets sont créés, les pods restent `Pending`), avec les CRD et ConfigMaps du chart, et un serveur Git HTTP local à authentification basique. Ont été constatés : comptes locaux (dont le **découpage d'un nom contenant un point**), `update-password`, jeton à expiration de `ci-lecture` et réponses de l'API (`/api/v1/session/userinfo`, `/api/v1/account`, `/api/v1/account/ci-lecture`, `can-i`), désactivation d'`admin` (champ `enabled` absent de la réponse) ; `argocd repo add`, Application créée par la CLI, diff, synchronisation, annotation de suivi, historique ; dérive et auto-réparation ; une étiquette **ajoutée** à la main conservée, une étiquette **modifiée** rétablie ; *prune* qui n'agit qu'après un rafraîchissement ; passage au *server-side apply* (migration des gestionnaires, annotation `last-applied-configuration` retirée, ReplicaSet inchangé) ; modèles `repo-creds`, racine qui se gère elle-même et adopte `labo` ; AppProjects en trois MR et messages de refus (destination, `ResourceQuota`) ; avertissement `SharedResourceWarning` ; reprise de l'overlay `dev` du M17 appliqué par `kubectl apply --server-side` : **ReplicaSet et pods inchangés**, génération du Deployment passée de 1 à 2, gestionnaires `kubectl` et `argocd-controller` copropriétaires ; faux `OutOfSync` d'une HTTPRoute supprimé par le diff côté serveur ; suppression `--cascade=false` puis recréation de `labo` par la racine ;
- rôle `outils_k8s` modifié : `ansible-lint` 26.10 (profil `production`, ansible-core 2.21) et `--syntax-check` ; empreinte de `argocd-linux-amd64` relevée dans `cli_checksums.txt` de la v3.5.5 et recalculée sur le binaire ;
- module `secrets-k8s.d/argocd.sh` exécuté contre le plan de contrôle de test (création et vérification des quatre `repo-creds`, avec `yq` 4.48) ; `instantane.sh` exécuté ; tous les scripts et checks : `shellcheck -x` et `bash -n` ; les checks E03 à E08 joués contre l'installation de test (les contrôles GitLab et de pods prêts y sont KO, faute de GitLab et de kubelet) ;
- manifestes : `yamllint`, `kubeconform -strict` (AppProjects et Applications validés contre les schémas tirés des CRD du chart 10.10.5) ; `kustomize build` (5.8.1) des overlays `dev` et `prod` du M17 modifiés.

**Points non testés en conditions réelles**, à vérifier sur ton lab et à signaler s'ils diffèrent :
- l'installation complète dans `k8s-par1` (pods qui démarrent, Gateway Cilium, ExternalDNS, `/healthz`, interface) ; les sorties montrées sont **représentatives** ;
- la CLI en `--grpc-web` à travers la Gateway Cilium (méthode documentée pour un mandataire qui ne relaie pas gRPC en HTTP/2 ; la connexion sans `--grpc-web` peut aussi bien échouer que se bloquer) ;
- la tenue des flux longs de l'interface (événements serveur) à travers Envoy : si l'interface cesse de se rafraîchir toutes les quelques dizaines de secondes, regarde `rules[].timeouts` de la route (`server.httproute.rules`) ;
- la santé d'un Cluster CNPG réel dans Argo CD (l'installation de test n'avait pas l'opérateur ; un Cluster sans statut fait échouer le calcul de santé) et l'effet du webhook de CNPG sur le diff côté serveur ;
- la surcharge d'un job venu d'un **composant** CI/CD par une redéclaration dans `.gitlab-ci.yml` (comportement documenté pour les `include` ; à vérifier avec ta version du composant `deploiement`) ;
- le comportement du serveur quand `argocd-initial-admin-secret` est supprimé **et** qu'`admin` est réactivé plus tard (le Secret n'est pas recréé si `argocd-secret` contient déjà un mot de passe `admin` : comportement lu dans la documentation, non rejoué).

---

### M20-E01 — Test de positionnement : déploiement et GitOps

**Barème** : 2 points par question. 2 = complet et justifié ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Total sur 36. En dessous de 18, relis les « Concepts clés » de l'introduction avant E04. Les questions 1 à 4 sont reprises en E05 et E09, 5 à 8 en E05 et E08, 9 à 12 au palier 2 (E14), 13 à 15 en E03, E06, E12, 16 à 18 en E02.

**Réponses argumentées — pousser ou tirer**

**1. *Push* et *pull*.** *Push* : la CI détient des identifiants qui écrivent dans le cluster (ici le contexte de l'agent GitLab, M19-E18) et applique à l'instant d'un événement (la fusion). Entre deux fusions, personne ne regarde : une modification à la main reste en place jusqu'au prochain déploiement, qui l'écrasera peut-être, ou peut-être pas (un champ que le manifeste ne mentionne pas). *Pull* : un contrôleur **dans** le cluster détient les droits sur le cluster et seulement un accès en **lecture** au dépôt ; il compare en permanence Git et le cluster. Une modification à la main est vue à la comparaison suivante (`OutOfSync`), et effacée si l'auto-réparation est active. Le changement est toujours initié par un commit, jamais par la CI elle-même.

**2. Réponse C (fausse).** Le contrôleur **va chercher** l'état dans le dépôt : c'est lui qui joint la forge, pas l'inverse. Un webhook de la forge vers le contrôleur (M20-E27) n'est qu'une accélération (« regarde maintenant »), jamais le canal du déploiement. A est vrai (c'est l'intérêt de sécurité, demande de Sophie, E30) ; B est vrai (auto-réparation) ; D est vrai (accès en lecture au dépôt, jetons de déploiement d'E04 et E06).

**3. Boucle de réconciliation.** Un programme qui, en boucle, lit l'état voulu, observe l'état réel, calcule l'écart et agit pour le réduire, sans fin. Dans `k8s-par1` : le contrôleur des ReplicaSets (un pod supprimé est recréé), celui des Deployments (changement d'image → nouveau ReplicaSet), le kubelet (un conteneur qui meurt est relancé), l'opérateur CNPG (une instance PostgreSQL qui tombe est reconstruite), cert-manager (un certificat proche de l'échéance est renouvelé). Argo CD applique le même principe un étage au-dessus : l'état voulu est dans Git, l'état réel est l'ensemble des objets de l'API.

**4. Dérive.** L'écart entre l'état réel et l'état voulu. Sans erreur dans le dépôt : (a) une modification à la main (`kubectl edit`, `kubectl scale`, l'incident de lundi) ; (b) un autre contrôleur qui écrit dans le même champ (un HPA qui change `spec.replicas`, un webhook de mutation qui ajoute un conteneur, un opérateur qui remplit des valeurs par défaut) ; (c) un objet supprimé ou créé hors du chemin GitOps (un Secret créé à la main, un objet resté d'une ancienne version) ; on peut ajouter (d) une valeur rendue différemment (version de Kustomize ou de Helm différente entre l'outil GitOps et le poste qui a appliqué). Seule la (a) est vraiment une « faute » ; les autres sont des cohabitations à décrire (`ignoreDifferences`, E12).

**Réponses argumentées — rendre et appliquer**

**5. Rendu.** Argo CD sait rendre un dossier de manifestes, un dossier Kustomize et un chart Helm (son *repo-server* embarque Kustomize 5.8.1 et Helm 4.2.1 en 3.5). Lui donner un **rendu commité** (le choix de MédiSphère au M17, ADR-0170) : la MR montre exactement ce qui changera dans le cluster, le rendu est vérifié une fois (signature du chart, M17), et il ne dépend pas de la version de l'outil de rendu d'Argo CD. On perd : un rendu à régénérer et à commiter à chaque changement du chart ou des valeurs (un outil de plus, `outils/rendre-base.sh`), et des MR plus volumineuses. Lui donner chart + valeurs : moins de fichiers, mais la vérité de ce qui est appliqué n'est plus lisible dans Git, et un changement de version du rendu d'Argo CD peut changer les objets sans commit (dérive au sens 4d). Argo CD 3.5 propose aussi le *Source Hydrator* (bêta) : Argo CD rend et commite lui-même (E09).

**6. *Client-side* et *server-side*.** `kubectl apply` (client) calcule un correctif à trois voies entre le manifeste, l'objet vivant et l'annotation `kubectl.kubernetes.io/last-applied-configuration` qu'il a posée la fois précédente : c'est elle, **dans l'objet**, qui mémorise « ce que j'ai appliqué ». `kubectl apply --server-side` envoie le manifeste à l'API, qui enregistre **par champ** quel gestionnaire (*field manager*) l'a posé (`metadata.managedFields`) ; un champ qu'un gestionnaire cesse de déclarer lui est retiré, et supprimé s'il n'a plus de propriétaire. Pour un outil qui applique en boucle, c'est ce qui permet de supprimer un champ retiré de Git sans toucher à ceux posés par d'autres (un contrôleur, un opérateur), et de détecter un conflit au lieu d'écraser en silence. L'annotation du mode client, elle, peut dépasser la taille maximale (262 144 octets) sur de gros objets (CRD).

**7. Réponse B.** Un conflit (`409`, « conflict with "<gestionnaire>" … .spec.replicas ») : l'API refuse qu'un gestionnaire change un champ possédé par un autre, sauf si l'appelant force (`--force-conflicts` ; Argo CD force toujours en *server-side apply*). A est le comportement du *client-side apply* ; C n'existe pas ; D décrit le cas où les deux posent la **même** valeur : ils deviennent copropriétaires, sans conflit (c'est ce qui arrive à la reprise d'E08).

**8. Reprise d'un objet existant.** Le pod n'est recréé que si le **modèle de pod** (`spec.template`) change : un nouveau ReplicaSet n'est créé que pour un nouveau modèle (son nom porte l'empreinte du modèle). Si le fichier est identique, seuls des métadonnées de l'objet changent (l'annotation de suivi posée par l'outil) : aucun pod n'est recréé. Cela dépend donc (a) du rendu exact (même version, mêmes étiquettes, mêmes valeurs par défaut), (b) de ce que l'outil ajoute (Argo CD : une annotation sur l'objet, **pas** sur le modèle de pod, en suivi par annotation ; l'ancien suivi par étiquette ajoutait aussi des étiquettes), (c) de la méthode d'application (en mode client, l'outil pourrait supprimer des champs qu'il croit siens). C'est l'objet de l'E08.

**Réponses argumentées — versions et promotion**

**9. Digest.** Une étiquette, même immuable dans Harbor, est un **nom** résolu au moment du tirage : immuable par politique d'un registre (une politique se désactive, un registre se migre, un cache peut servir autre chose), alors qu'un digest est l'empreinte du contenu, vérifiable partout. Le digest rend le dépôt GitOps autosuffisant (ce qui tourne est exactement écrit), fait correspondre ce que Git décrit et ce que Cosign a signé (la signature porte sur le digest, M13), et rend toute promotion visible dans le diff (le digest change, pas seulement un texte). C'est le choix de la promotion du M19-E17.

**10. Branches ou dossiers.** Une **branche par environnement** : la promotion est une fusion (l'historique de `prod` est celui de ce qui y est passé), mais les branches divergent vite (correctifs appliqués dans une seule, conflits, *cherry-picks*), un écart de configuration propre à l'environnement est difficile à garder hors de la fusion, et la comparaison entre environnements se fait par `git diff` de branches. Un **dossier par environnement** sur une branche (overlays, notre choix) : tout est visible d'un coup d'œil, les différences entre environnements sont explicites et petites, une promotion est une MR qui recopie une valeur (le digest) d'un dossier à l'autre ; mais rien n'empêche techniquement de modifier `prod` sans passer par `recette` (d'où des règles de MR et l'outillage de promotion, E14).

**11. Réponse B.** Le retour arrière est un **commit** : `git revert` du commit de promotion, relu et fusionné, et le contrôleur applique l'état précédent. Tout reste tracé, et Git reste la vérité. A redéploierait peut-être une ancienne image, mais Git dirait toujours la nouvelle : la prochaine réconciliation remettrait la mauvaise version. C est une dérive volontaire, effacée par l'auto-réparation (et ignorée de Git). D coupe le service et ne change rien à Git. Argo CD a un `argocd app rollback`, mais il exige que la synchronisation automatique soit désactivée : c'est une mesure d'urgence, pas la méthode (E14).

**12. *Prune*.** Avec la suppression automatique, un objet créé par l'outil et qui disparaît de Git est supprimé du cluster à la synchronisation suivante. Scénario destructeur : un fichier renommé ou déplacé dans un mauvais dossier, une erreur de `kustomization.yaml` (une ressource oubliée), une MR qui supprime le fichier d'une base de données ou d'un PVC : la base est supprimée. D'où `Prune=false` (et `Delete=false`) sur les objets qui portent des données (E08), `PruneLast`, `Prune=confirm`, et pas de suppression automatique en production (E14, E41).

**Réponses argumentées — secrets et sécurité**

**13. Secrets et Git.** Le base64 est un **encodage**, pas un chiffrement : n'importe qui qui lit le dépôt (toute personne qui a l'accès, tout clone, toute sauvegarde, tout runner de CI qui le clone) lit le secret, pour toujours (l'historique de Git ne s'efface pas vraiment). Approches : (a) les secrets restent **hors de Git** et sont créés par un autre chemin (notre `secrets-k8s.sh` depuis Ansible Vault, jusqu'au M25) ; (b) les secrets sont **chiffrés dans Git** (Sealed Secrets, SOPS + age/KMS) et déchiffrés dans le cluster ; (c) Git ne contient qu'une **référence** et un opérateur va chercher la valeur dans un coffre (External Secrets Operator + OpenBao, notre cible au M25). (d) Les plugins de gestion de configuration qui injectent des secrets dans les manifestes au rendu sont déconseillés par Argo CD lui-même (le secret passe par le cache du *repo-server*).

**14. Le contrôleur, administrateur de fait.** Le contrôleur d'Argo CD a des droits très larges sur le cluster (le chart lui donne tout, `*` sur `*`). Qui peut écrire dans un dépôt que lit une Application capable de créer des objets de cluster (le dépôt de la racine, ou tout dépôt d'un projet qui permet des objets de cluster ou l'espace `argocd`) peut donc créer n'importe quel objet, y compris un `ClusterRoleBinding` vers `cluster-admin`. Protections : branche principale protégée, fusion par MR relue par des personnes habilitées (Maintainers), pas de poussée directe ; AppProjects qui limitent sources, destinations et types d'objets (E07) ; jetons de lecture à portée minimale ; journal d'audit ; et, à terme, droits du contrôleur réduits par projet (comptes de service de destination, alpha).

**15. Réponse B.** Un jeton de **déploiement** : lié à un projet ou un groupe, portée `read_repository` seule (lecture du code, rien d'autre), indépendant d'une personne (il survit au départ de quelqu'un), avec une expiration et une révocation propres. A donnerait à Argo CD (et à quiconque lit son Secret) les droits d'un administrateur de la forge sur toute l'instance. C ne sert qu'à un runner pour prendre des jobs, pas à cloner. D exposerait le dépôt à tous les comptes de l'instance, et rendrait toute la configuration de la plateforme lisible.

**Réponses argumentées — ce que tu sais d'Argo CD**

**16. Composants.** **argocd-server** : l'API (gRPC et REST), l'interface web, l'authentification et le RBAC d'Argo CD ; **argocd-repo-server** : clone les dépôts et rend les manifestes (Kustomize, Helm, dossiers), avec un cache — c'est **lui** qui joint la forge ; **argocd-application-controller** : compare l'état rendu et l'état du cluster, calcule la santé, synchronise — c'est lui qui a des droits sur l'API Kubernetes (le serveur en a aussi, plus restreints : lire les objets, supprimer à la demande, journaux) ; **argocd-applicationset-controller** : génère des Applications à partir des ApplicationSets ; **argocd-notifications-controller** : envoie les notifications ; **Redis** : cache (état des objets, manifestes rendus), sans données à sauvegarder ; **Dex** (facultatif) : fournisseur OIDC intégré pour le SSO ; **commit-server** (facultatif, *Source Hydrator*).

**17. Statuts.** `Synced` : les objets vivants correspondent à ce que Git décrit. `Degraded` : au moins un objet ne fonctionne pas (un Deployment dont les pods ne deviennent pas prêts dans le délai, un pod en `CrashLoopBackOff`). Exemple de `Synced` + `Degraded` : Git référence une image qui plante au démarrage ; tout est appliqué fidèlement, et rien ne marche. `OutOfSync` + `Healthy` : quelqu'un a passé `labo` à 4 réplicas à la main, tout fonctionne mais le cluster ne ressemble plus à Git (E05) ; ou un nouveau commit vient d'arriver et n'est pas encore appliqué.

**18. Pourquoi Helmfile pour Argo CD.** Argo CD qui se gère lui-même fonctionne (c'est même documenté), mais une erreur dans ses propres valeurs (une image introuvable, un RBAC cassé, une mauvaise version de CRD) peut le rendre incapable d'appliquer la correction : il faut alors le réparer… sans lui. Même raisonnement pour ce dont il dépend (CNI, DNS, stockage, certificats) : si Cilium tombe à cause d'une synchronisation, Argo CD ne joint plus rien. MédiSphère garde donc une **couche de base** sous Helmfile, appliquée par une personne avec une procédure (diff, MR), et confie à Argo CD tout ce qui est au-dessus (PLAN §4.11). Le prix : cette couche n'est pas réconciliée en continu (E09, question 5).

---

### M20-E02 — Installer Argo CD par Helmfile

**Solution**

*A. Lire le chart.*

1. Les objets rendus par défaut (chart 10.10.5) : 3 CRD (`applications`, `applicationsets`, `appprojects`), les ClusterRoles et liaisons du contrôleur, du serveur et de l'ApplicationSet, les Deployments (serveur, *repo-server*, Redis, Dex, ApplicationSet, notifications) et le StatefulSet du contrôleur, les ConfigMaps (`argocd-cm`, `argocd-cmd-params-cm`, `argocd-rbac-cm`, `argocd-tls-certs-cm`, `argocd-ssh-known-hosts-cm`, `argocd-gpg-keys-cm`, `argocd-notifications-cm`…), les Secrets `argocd-secret` et `argocd-notifications-secret`, et **des NetworkPolicy d'entrée pour chaque composant** (`global.networkPolicy.create: true` dans ce chart). Images : `quay.io/argoproj/argocd` (étiquette = `appVersion`, v3.5.5), `ghcr.io/dexidp/dex`, et Redis depuis `ecr-public.aws.com/docker/library/redis` (copie ECR de l'image officielle de Docker Hub). Par défaut : Dex actif, `admin` actif (mot de passe aléatoire dans `argocd-initial-admin-secret`, créé au premier démarrage), serveur en TLS avec un certificat auto-signé, aucune ressource demandée. Les **hooks** : le *Job* `argocd-redis-secret-init` (et son compte de service, son rôle, sa liaison), en `pre-install,pre-upgrade` : il génère le mot de passe de Redis dans le Secret `argocd-redis` avant que Redis et les composants qui s'y connectent ne démarrent.
2. ```
   admin@adm01:~$ skopeo inspect --format '{{.Digest}}' docker://registry.par1.medisphere.internal/quay/argoproj/argocd:v3.5.5
   sha256:…
   admin@adm01:~$ skopeo inspect --format '{{.Digest}}' docker://registry.par1.medisphere.internal/dockerhub/library/redis:8.6.4-alpine
   sha256:…
   ```
   Le chart prend Redis dans la galerie publique d'ECR, qui republie les images officielles de Docker Hub (`docker/library/redis`) : la même image (même nom, même étiquette) est disponible par notre cache `dockerhub`. On préfère un cache existant, analysé par Harbor, à un nouveau registre amont.

*B. La release.* Fichiers : [`espaces/argocd.yaml`](fichiers/M20-E02/k8s/espaces/argocd.yaml), [`composants/argocd/values.yaml`](fichiers/M20-E02/k8s/composants/argocd/values.yaml), [`releases/argocd.yaml.gotmpl`](fichiers/M20-E02/k8s/releases/argocd.yaml.gotmpl). La racine se copie depuis `adm01` : `cp /usr/local/share/ca-certificates/medisphere-root-ca.crt composants/argocd/medisphere-root-ca.crt` (certificat public : il se versionne ; le fichier n'est pas fourni dans le corrigé, c'est **ta** racine).

3. `task espaces` crée l'espace avec les étiquettes PSA. Contrôle préalable, sans rien installer :
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd template > ~/m20/e02/rendu.yaml
   admin@adm01:~/src/k8s$ kubectl --context k8s-par1 apply --dry-run=server -n argocd -f ~/m20/e02/rendu.yaml 2>&1 | grep -i 'pod-security\|violate' || echo "aucun avertissement PSA"
   ```
   (Les CRD n'étant pas encore installées, le *dry-run* signale aussi des types inconnus : seul l'avertissement de Pod Security compte ici.) Tous les pods du chart 10.10.5 déclarent `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault` et aucun volume `hostPath` : `restricted` passe.
4. Les écarts aux défauts, tous commentés dans le fichier : `global.image.repository` (cache `quay`, l'étiquette suit la version du chart), `global.priorityClassName: medisphere-critique`, journaux JSON, `dex.enabled: false`, `configs.cm` (`admin.enabled: true` pour l'instant, `application.resourceTrackingMethod: annotation`, `exec.enabled: false`), `configs.params."server.insecure": true`, un réplica et des ressources par composant, Redis par le cache `dockerhub`, `server.httproute` (parent `passerelles/gw-par1`, `sectionName: https`, nom `argocd.apps.par1.medisphere.internal`). Les chiffres de mémoire : le contrôleur garde en cache l'état de **tous** les objets surveillés (512 Mio demandés, 1 Gio de limite) ; le *repo-server* lance `kustomize` et `helm` (pics à chaque rendu : 256 Mio, limite 768 Mio) ; le reste est léger. Total demandé ≈ 1,1 Gio. Pas de limite de CPU (étranglement inutile sur des pics courts, comme partout dans `k8s-par1`).
5. La release reprend la forme du M17 : `bases: [_communs.yaml]` puis un document avec `repositories` et `releases`. Le domaine vient de l'environnement (`argocd.{{ .Values.domaineApps }}`) ; la racine est lue par `readFile` (chemin relatif au fichier de release) et indentée par `nindent`, deux fois (pour `git01` et `registry`). La liste `repositories` de ce fichier **remplace** celle de `_communs.yaml` (constaté avec `helmfile build`) : sans conséquence, ce fichier n'a besoin que du dépôt `argo`.
6. Le rendu montre la route, les images de Harbor et `argocd-tls-certs-cm` avec deux entrées PEM. Puis :
   ```
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff | grep -E '^argocd, ' | head
   argocd, argocd-application-controller, StatefulSet (apps) has been added:
   argocd, argocd-applicationset-controller, Deployment (apps) has been added:
   …
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply
   admin@adm01:~$ kubectl --context k8s-par1 -n argocd get pods
   NAME                                                READY   STATUS    RESTARTS   AGE
   argocd-application-controller-0                     1/1     Running   0          2m
   argocd-applicationset-controller-6c9…-…             1/1     Running   0          2m
   argocd-notifications-controller-5d8…-…              1/1     Running   0          2m
   argocd-redis-7f4…-…                                 1/1     Running   0          2m
   argocd-repo-server-84b…-…                           1/1     Running   0          2m
   argocd-server-6fd…-…                                1/1     Running   0          2m
   ```
   Le *Job* `argocd-redis-secret-init` passe d'abord parce que c'est un hook `pre-install` : Helm l'exécute et attend sa fin avant de créer le reste ; sans le Secret `argocd-redis` qu'il crée, Redis et les composants qui lisent son mot de passe ne démarreraient pas.

*C. Constater.*

7. ```
   admin@adm01:~$ kubectl --context k8s-par1 -n argocd get httproute argocd-server -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {end}'
   Accepted=True ResolvedRefs=True
   admin@adm01:~$ dig +short argocd.apps.par1.medisphere.internal
   10.10.41.10
   admin@adm01:~$ curl -sS https://argocd.apps.par1.medisphere.internal/healthz
   ok
   ```
   Le navigateur reçoit le certificat **joker** `*.apps.par1.medisphere.internal` de `gw-par1` (émis par step-ca via cert-manager, M15-E14) : aucun certificat propre à Argo CD.
8. Réponse à Karim. *Pourquoi à la Gateway* : un seul point de terminaison TLS pour tout `*.apps` (certificat joker automatique, en-têtes de sécurité, politique TLS au même endroit, M15) ; aucun certificat de plus à gérer ; Argo CD se comporte comme toute application publiée. *Ce qui circule en clair* : la requête déchiffrée entre l'Envoy de la Gateway et le pod `argocd-server`, sur le port 80 : en clair **dans le nœud** (Envoy et le pod sur le même nœud), et dans le tunnel **chiffré par WireGuard** entre deux nœuds (M15-E24). Les échanges internes d'Argo CD (serveur ↔ *repo-server*) restent en TLS (certificat auto-signé du *repo-server*, non vérifié par défaut : `server.repo.server.strict.tls: "false"`). *Pour du bout en bout* : soit un écouteur **TLS passthrough** sur une Gateway (comme `gw-partenaires` au M15) et un certificat propre à Argo CD émis par cert-manager (`server.certificate` du chart) : c'est un écouteur de plus, géré par la plateforme ; soit une `BackendTLSPolicy` (la Gateway rechiffre vers le pod) : le chart l'indique comme non prise en charge par Cilium, à vérifier dans la documentation de Cilium 1.20 avant d'y compter. *Ce qu'on perd* : la confidentialité vis-à-vis de quelqu'un qui aurait la main sur un nœud (qui, de toute façon, lit les Secrets du nœud) ; la défense en profondeur. Noté pour l'E25 (durcissement), qui ajoute la politique réseau du serveur (seule la Gateway le joint).

**Explications**

Argo CD est livré comme n'importe quel chart tiers du M17 : lu, réglé par écart aux défauts, épinglé, rendu et comparé avant d'être appliqué. La différence avec les releases précédentes est son **rôle** : il aura bientôt plus de pouvoir sur le cluster que quiconque, d'où l'exigence sur l'accès (E03) et sur le cloisonnement (E07).

`server.insecure` ne veut pas dire « sans sécurité » : le serveur ne termine pas TLS lui-même et accepte HTTP **derrière** un mandataire qui, lui, termine TLS. Sans ce réglage, le serveur répondrait à la Gateway par une redirection vers HTTPS, et l'interface tournerait en boucle. La CLI parle gRPC ; à travers une route HTTP, elle doit encapsuler gRPC dans HTTP/1.1 (`--grpc-web`), sinon Envoy reçoit du gRPC sur un amont qu'il traite en HTTP/1.1.

Le suivi des ressources par **annotation** est le défaut depuis Argo CD 3.0 ; l'écrire explicitement documente le choix (il conditionne la reprise d'E08). L'étiquette `argocd.argoproj.io/instance` que pose encore le chart dans `argocd-cm` (`application.instanceLabelKey`) n'est plus qu'informative.

Les **NetworkPolicy** du chart sont des règles d'**entrée** : Redis n'accepte que le serveur, le *repo-server* et le contrôleur ; le *repo-server* n'accepte que les composants d'Argo CD (et les métriques) ; le serveur accepte tout (il faut bien que la Gateway le joigne). Elles ne filtrent pas la sortie : c'est l'objet de l'E25 (CiliumNetworkPolicy, le *repo-server* ne sort que vers `git01` et `reg01`).

**Alternatives**

- **Manifestes d'installation amont** (`install.yaml` de chaque version) : simples, mais aucun réglage hors correctifs Kustomize, et pas de diff de release ; Helmfile reste le chemin de la couche de base (M17).
- **Opérateur Argo CD** (`argocd-operator`, objet `ArgoCD`) : réglages par une CRD, montées gérées par l'opérateur ; un composant de plus dans la couche de base, et une documentation décalée par rapport au chart amont. Pertinent si l'on gère beaucoup d'instances.
- **Argo CD en mode « cœur »** (`--core`, sans serveur ni interface) : la CLI parle directement à l'API Kubernetes ; utile pour un petit cluster sans interface, pas pour une équipe.
- **Ingress** au lieu de la Gateway API : ingress-nginx est retiré par son projet (M15) ; la Gateway API est la norme du cluster.

**Pièges classiques**

- Oublier `server.insecure` : redirections en boucle, ou `ERR_TOO_MANY_REDIRECTS` dans le navigateur.
- Une HTTPRoute sans `hostnames` : elle prend **tous** les noms de l'écouteur `*.apps`, et capture le trafic des autres applications.
- L'espace sans l'étiquette `medisphere.internal/exposition: oui` : la route reste `Accepted=False` (`NotAllowedByListeners`).
- Chercher le certificat d'Argo CD dans l'espace `argocd` : il n'y en a pas, c'est le joker de la Gateway.
- Laisser Dex actif « au cas où » : un composant exposé de plus, sans usage avant le M24.
- Croire que `helm uninstall` ou une erreur de valeurs n'a pas d'effet sur les applications : à partir de l'E06, supprimer Argo CD **avec** ses CRD supprimerait toutes les Applications (et, par leurs finaliseurs, leurs charges). Le chart garde ses CRD à la désinstallation (`crds.keep: true`) : ne change pas ce réglage (E28).
- Comparer `helmfile diff` d'un chart qui a des hooks : les hooks n'apparaissent pas comme les autres objets ; lis le rendu (`template`).

**En production chez MédiSphère**

Argo CD est un composant **critique** : PriorityClass `medisphere-critique`, supervision dès le M21 (métriques du contrôleur et du *repo-server*, alerte sur les applications `OutOfSync`/`Degraded` de production), haute disponibilité au M20-E27 (réplicas, *sharding*, Redis HA), sauvegarde et procédure de reconstruction au M20-E28. Les montées de version du chart suivent les notes de version du chart **et** le guide de montée d'Argo CD, une mineure à la fois, avec un `helmfile diff` relu en MR. La version de la CLI suit celle du serveur (E03).

---

### M20-E03 — Accéder à Argo CD : interface, CLI et comptes locaux

**Solution**

*A. La CLI.* La ligne utile de `cli_checksums.txt` :
```
c3ddfa606fc3e89ab14f55bda6600b207c355b028f8eaabe69b817a4c4621aba  argocd-linux-amd64
```
Rôle [`outils_k8s`](fichiers/M20-E03/ansible/roles/outils_k8s/) : liste `outils_k8s_binaires_nus` dans [`defaults/main.yml`](fichiers/M20-E03/ansible/roles/outils_k8s/defaults/main.yml) (nom, version, URL, empreinte `sha256:` écrite dans les valeurs), nouveau fichier [`tasks/binaire_nu.yml`](fichiers/M20-E03/ansible/roles/outils_k8s/tasks/binaire_nu.yml) (dossier versionné, `get_url` avec `checksum`, lien), appel dans [`tasks/main.yml`](fichiers/M20-E03/ansible/roles/outils_k8s/tasks/main.yml) et complétion bash, [`meta/argument_specs.yml`](fichiers/M20-E03/ansible/roles/outils_k8s/meta/argument_specs.yml). Le fichier reprend aussi la version d'`etcdctl` (3.6.8) passée au M14-E25. Le traitement des archives (`binaire.yml`) n'est pas touché.
```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/outils-k8s.yml
admin@adm01:~$ argocd version --client --short
argocd: v3.5.5+a5038b0
```

*B. Les comptes.* Valeurs : [`composants/argocd/values.yaml`](fichiers/M20-E03/k8s/composants/argocd/values.yaml) (état final, `admin.enabled: false`). À l'étape 2, le même fichier avec `admin.enabled: true`.

2. Capacités : `login` (interface et CLI par mot de passe) et `apiKey` (jetons d'API). Un compte authentifié sans rôle, avec `policy.default` vide, se connecte… et ne voit rien : aucune Application, aucun projet. C'est le comportement voulu : un rôle s'attribue explicitement.
   Le point dans un nom : Argo CD découpe chaque clé de `argocd-cm` qui commence par `accounts.` sur les **points** (`accounts.<nom>` ou `accounts.<nom>.<suffixe>`). `accounts.karim.benali: login` devient le compte **`karim`**, avec un réglage inconnu `benali`, et **sans capacité** :
   ```
   admin@adm01:~$ argocd account list
   NAME          ENABLED  CAPABILITIES
   admin         true     login
   ci-lecture    true     apiKey
   karim         true
   ```
   (constaté sur Argo CD 3.5.5). D'où les tirets. Ton compte : `<MOI>` avec des tirets, `<MOI-ARGO>`.
3. ```
   admin@adm01:~$ argocd admin initial-password -n argocd
   admin@adm01:~$ argocd login argocd.apps.par1.medisphere.internal --grpc-web --username admin
   Password:
   'admin:login' logged in successfully
   Context 'argocd.apps.par1.medisphere.internal' updated
   admin@adm01:~$ argocd account update-password --account <MOI-ARGO>
   *** Enter password of currently logged in user (admin):
   *** Enter new password for user <MOI-ARGO>:
   *** Confirm new password for user <MOI-ARGO>:
   Password updated
   ```
   `argocd admin initial-password` lit le Secret avec **ton** kubeconfig (il affiche le mot de passe : ne le fais pas devant un écran partagé, et il disparaît à l'étape 7). `--grpc-web` encapsule les appels gRPC de la CLI dans des requêtes HTTP/1.1 que la route HTTP relaie ; sans lui, la CLI tente du gRPC sur HTTP/2 que la Gateway transmet à un amont HTTP/1.1 : erreurs de protocole ou attente sans fin. La session (un jeton signé par le serveur) est dans `~/.config/argocd/config`, en 600 : à traiter comme un secret.
4. ```
   admin@adm01:~$ argocd login argocd.apps.par1.medisphere.internal --grpc-web --username <MOI-ARGO>
   admin@adm01:~$ for c in karim-benali julien-petit nadia-roussel; do argocd account update-password --account "$c"; done
   admin@adm01:~$ argocd account can-i sync applications '*'
   yes
   ```
   Sous `nadia-roussel` (rôle `readonly`) : `no`. Les mots de passe vont dans `plateforme/k8s/secrets/argocd-comptes.yml` (Vault `critique`), lu par personne d'autre que toi : ils ne servent qu'à la première connexion.

*C. Le compte des vérifications.*

5. ```
   admin@adm01:~$ install -m 600 /dev/null ~/.config/workbook/argocd-checks.token
   admin@adm01:~$ argocd account generate-token --account ci-lecture --id checks-$(date +%Y%m%d) --expires-in 90d > ~/.config/workbook/argocd-checks.token
   admin@adm01:~$ curl -sS -K <(printf 'header = "Authorization: Bearer %s"\n' "$(<~/.config/workbook/argocd-checks.token)") \
       https://argocd.apps.par1.medisphere.internal/api/v1/session/userinfo
   {"loggedIn":true,"username":"ci-lecture","iss":"argocd"}
   admin@adm01:~$ argocd account get --account ci-lecture
   Name:               ci-lecture
   Enabled:            true
   Capabilities:       apiKey

   Tokens:
   ID               ISSUED AT             EXPIRING AT
   checks-20261023  2026-10-23T10:12:41Z  2027-01-21T10:12:41Z
   ```
   Révocation : `argocd account delete-token --account ci-lecture checks-20261023` (le jeton est un JWT signé par le serveur ; Argo CD garde la liste des identifiants valides du compte et refuse les autres). La rotation consiste à générer le suivant avant l'échéance, à remplacer le fichier, puis à supprimer l'ancien.
6. [`rbac/wb-checks-livraison.yaml`](fichiers/M20-E03/k8s/rbac/wb-checks-livraison.yaml) : les règles du M19 inchangées, plus `get`/`list`/`watch` sur `applications`, `applicationsets`, `appprojects` d'`argoproj.io`. Ces objets ne contiennent que des descriptions (sources, destinations, statuts) ; les identifiants des dépôts et des clusters sont des **Secrets** étiquetés `argocd.argoproj.io/secret-type`, et `wb-checks` n'a jamais le droit de lire un Secret.
   ```
   admin@adm01:~/src/k8s$ task appliquer
   admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/k8s-checks.kubeconfig auth can-i list applications.argoproj.io -n argocd
   yes
   ```

*D. Fermer `admin`.*

7. ```
   admin@adm01:~$ argocd account can-i update projects '*'
   yes
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff     # admin.enabled: "true" -> "false" dans argocd-cm
   admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply
   admin@adm01:~$ argocd login argocd.apps.par1.medisphere.internal --grpc-web --username admin
   FATA[0002] rpc error: code = Unauthenticated desc = Account admin is disabled
   admin@adm01:~$ kubectl --context k8s-par1 -n argocd delete secret argocd-initial-admin-secret
   ```
   (Avec le bon mot de passe, le message dit que le compte est désactivé ; avec un mauvais, seulement « Invalid username or password » : le serveur vérifie le mot de passe **avant** l'état du compte, pour ne rien révéler à qui ne le connaît pas.)
   Le changement d'`argocd-cm` change l'annotation `checksum/cm` des modèles de pod du serveur, du *repo-server* et du contrôleur : ils redémarrent (quelques secondes sans interface).
8. Fiche d'accès : voir la rubrique « En production ».

**Explications**

Les comptes locaux d'Argo CD sont décrits dans `argocd-cm` (qui existe et ce qu'il peut faire) et leurs **secrets** (mot de passe haché, jetons valides) dans `argocd-secret`, écrits par le serveur. C'est pourquoi les comptes sont dans les valeurs Helm (relues en MR), et les mots de passe hors de Git, saisis par `update-password`. Le chart gère `argocd-secret` (`configs.secret.createSecret`), mais ne déclare pas les clés que le serveur y ajoute (`admin.password`, `accounts.<nom>.password`…) : une montée de la release ne les écrase pas (Helm 4 en *server-side apply* ne touche que les champs qu'il déclare).

Le RBAC d'Argo CD est **le sien**, distinct du RBAC Kubernetes : `role:admin` et `role:readonly` sont intégrés (`builtin-policy.csv`), et `policy.csv` lie des sujets (comptes, groupes SSO) à des rôles. `role:readonly` lit tout (applications, projets, dépôts, comptes, journaux des pods) mais n'agit sur rien : exactement ce qu'il faut aux vérifications.

Un compte désactivé reste listé : `admin` apparaît dans `GET /api/v1/account` **sans** champ `enabled` (la valeur fausse est omise par le format JSON de l'API) ; le check d'E03 en tient compte.

**Alternatives**

- **SSO dès maintenant** (Dex ou OIDC vers un fournisseur externe) : la cible, au M24 (Keycloak). Les comptes locaux sont un pis-aller assumé, nominatif, en attendant.
- **Jeton de projet** (rôle d'AppProject, `argocd proj role create-token`) au lieu d'un compte : jeton limité à un projet, adapté à une CI qui synchronise une seule application ; inadapté à des vérifications qui lisent tout.
- **Désactiver `admin` sans comptes locaux** et passer par `argocd --core` (droits Kubernetes de la personne) : possible, mais l'interface et le RBAC d'Argo CD ne servent plus.

**Pièges classiques**

- Un point dans un nom de compte : compte tronqué, sans capacité, et la personne ne peut pas se connecter.
- Désactiver `admin` avant d'avoir vérifié un autre administrateur : plus personne ne peut administrer Argo CD (retour arrière par Helmfile, voir l'énoncé).
- Un jeton sans `--expires-in` : valable pour toujours, dans un fichier sur un poste.
- Un jeton passé en argument (`curl -H "Authorization: Bearer …"`) : visible dans `ps` et dans l'historique du shell.
- Modifier `argocd-cm` à la main : la prochaine `helmfile apply` l'écrase, et le dépôt ne dit plus la vérité.
- Oublier `--grpc-web` dans un script : il fonctionne « parfois » depuis un autre réseau, jamais à travers la Gateway.

**En production chez MédiSphère**

`docs/livraison/gitops/acces.md` décrit : l'URL ; `argocd login argocd.apps.par1.medisphere.internal --grpc-web --username <compte>` ; les comptes et leurs rôles (avec les tirets) ; le jeton `ci-lecture` (identifiant, échéance au calendrier de l'équipe, rotation : générer, remplacer, supprimer l'ancien) ; le **bris de glace** : réactiver `admin` par Helmfile, lui donner un mot de passe (procédure de la documentation, `argocd admin` sur le cluster avec l'identité `cluster-admin`), l'utiliser, le redésactiver, consigner dans `docs/kubernetes/journal/`. Au M24, les comptes locaux des personnes disparaissent au profit du SSO ; `ci-lecture` reste (compte technique).

---

### M20-E04 — Première Application

**Solution**

1. Le dossier `k8s/` contient un `kustomization.yaml` : le *repo-server* le reconnaît à ce fichier et lance `kustomize build` (Kustomize 5.8.1 embarqué). Sans lui, il appliquerait tels quels les fichiers YAML du dossier (type « Directory »).
2. Jeton de **groupe** : un seul jeton pour tous les dépôts du groupe `formation` (les essais à venir), une seule rotation ; sa portée `read_repository` ne permet que de cloner. Ton jeton personnel ferait d'Argo CD… toi : tous tes droits, et il cesserait de fonctionner à ton départ ou à la rotation de ton jeton. Vault : `argocd_depots.formation.utilisateur: argocd-formation`, `jeton: gldt-…` dans `plateforme/k8s/secrets/argocd.yml` (modèle : [`secrets/argocd.yml.exemple`](fichiers/M20-E06/k8s/secrets/argocd.yml.exemple)).
3. ```
   admin@adm01:~$ argocd repo add https://git01.par1.medisphere.internal/formation/gitops-labo.git --username argocd-formation
   Password:
   Repository 'https://git01.par1.medisphere.internal/formation/gitops-labo.git' added
   admin@adm01:~$ argocd repo list
   TYPE  NAME  REPO                                                              INSECURE  OCI    LFS    CREDS  STATUS      MESSAGE  PROJECT
   git         https://git01.par1.medisphere.internal/formation/gitops-labo.git  false     false  false  false  Successful
   admin@adm01:~$ kubectl --context k8s-par1 -n argocd get secrets -l argocd.argoproj.io/secret-type
   NAME              TYPE     DATA   AGE
   repo-2197647746   Opaque   4      12s
   ```
   Argo CD a créé un Secret `repo-<empreinte>` (étiquette `argocd.argoproj.io/secret-type: repository`, clés `type`, `url`, `username`, `password`). Le certificat de `git01` a été vérifié contre la racine MédiSphère de `argocd-tls-certs-cm` (E02), montée dans le *repo-server* sous `/app/config/tls/git01.par1.medisphere.internal`.
4. ```
   admin@adm01:~$ argocd app get labo
   Name:               argocd/labo
   Project:            default
   Server:             https://kubernetes.default.svc
   Namespace:          wb-essais
   URL:                https://argocd.apps.par1.medisphere.internal/applications/labo
   Source:
   - Repo:             https://git01.par1.medisphere.internal/formation/gitops-labo.git
     Target:           main
     Path:             k8s
   SyncWindow:         Sync Allowed
   Sync Policy:        Manual
   Sync Status:        OutOfSync from main (49dbcc2)
   Health Status:      Missing

   GROUP  KIND        NAMESPACE  NAME       STATUS     HEALTH   HOOK  MESSAGE
          ConfigMap   wb-essais  labo-page  OutOfSync  Missing
          Service     wb-essais  labo       OutOfSync  Missing
   apps   Deployment  wb-essais  labo       OutOfSync  Missing
   ```
   Rien n'existe encore : `OutOfSync` (Git décrit des objets absents) et `Missing`. Le diff montre chaque objet entier, avec ce qui n'est pas dans tes fichiers : les étiquettes communes ajoutées par Kustomize (`app.kubernetes.io/part-of`, `medisphere.internal/proprietaire`), l'espace `wb-essais` (destination) et l'annotation `argocd.argoproj.io/tracking-id: labo:apps/Deployment:wb-essais/labo`.
5. ```
   admin@adm01:~$ argocd app sync labo
   …
   Phase:              Succeeded
   Message:            successfully synced (all tasks run)

   GROUP  KIND        NAMESPACE  NAME       STATUS  HEALTH       HOOK  MESSAGE
          ConfigMap   wb-essais  labo-page  Synced                     configmap/labo-page created
          Service     wb-essais  labo       Synced  Healthy            service/labo created
   apps   Deployment  wb-essais  labo       Synced  Progressing        deployment.apps/labo created
   ```
   `Progressing` le temps que les pods deviennent prêts, puis `Healthy`. Annotations du Deployment : `argocd.argoproj.io/tracking-id` (posée par Argo CD : `<application>:<groupe>/<type>:<espace>/<nom>`), `kubectl.kubernetes.io/last-applied-configuration` (application côté client, par défaut) et `deployment.kubernetes.io/revision` (posée par le contrôleur des Deployments). Gestionnaire de champs : `argocd-controller`, opération `Update` (c'est la signature du *client-side apply* ; l'E05 change cela).
6. ```
   admin@adm01:~$ argocd app set labo --sync-policy automated
   admin@adm01:~/src/gitops-labo$ sed -i 's/version 1/version 2/' k8s/configmap.yaml && git commit -am "feat: page en version 2" && git push
   admin@adm01:~$ argocd app get labo -o json | jq -c '[.status.history[] | {revision: .revision[0:7], initiatedBy}]'
   [{"revision":"49dbcc2","initiatedBy":{"username":"<MOI-ARGO>"}},{"revision":"e9167d2","initiatedBy":{"automated":true}}]
   ```
   Délai : jusqu'à **3 minutes** (`timeout.reconciliation: 120s` + jusqu'à 60 s d'aléa, `argocd-cm`) : Argo CD interroge le dépôt périodiquement. Pour accélérer sans rien changer : `argocd app get labo --refresh` (ou *Refresh* dans l'interface). Durablement : un webhook de GitLab vers Argo CD (M20-E27).
7. Seule la ConfigMap a changé, pas le modèle de pod : aucun pod recréé. Le kubelet met à jour les volumes ConfigMap montés à sa propre période de synchronisation (de l'ordre de la minute, cache compris) ; nginx relit le fichier à chaque requête. (Un montage `subPath` ne serait **jamais** mis à jour : piège classique.)

**Explications**

Une Application ne contient pas les manifestes : elle **pointe** vers eux. Le *repo-server* clone (avec les identifiants du dépôt), rend (Kustomize), met en cache par révision ; le contrôleur compare ce rendu aux objets vivants et calcule la santé de chacun (règles intégrées par type : un Deployment est sain quand ses réplicas à jour sont disponibles ; un Service l'est toujours, sauf un `LoadBalancer` sans adresse). Les statuts de l'Application sont l'agrégat de ceux des objets.

L'annotation de suivi est la mémoire d'Argo CD : sans elle, un objet n'est pas « à lui » (il ne le supprimera jamais par *prune*, il ne le compte pas dans l'application). La synchronisation automatique ne s'enclenche que lorsqu'une **nouvelle révision** apparaît et que l'application est `OutOfSync` : d'où une seule synchronisation automatique par commit (lis l'historique).

**Alternatives**

- Créer l'Application par un fichier YAML (`argocd app create -f` ou `kubectl apply` d'un objet `Application`) plutôt que par options de la CLI : c'est ce que fait l'E06, dans Git.
- Lire le dépôt en SSH (clé de déploiement, `argocd-ssh-known-hosts-cm`) : possible ; HTTPS + jeton de déploiement est plus simple derrière notre pare-feu (un seul port, 443) et suit la forge (M01).
- Dossier de manifestes sans Kustomize : plus simple encore, mais pas d'étiquettes communes ni de transformation d'image par overlay.

**Pièges classiques**

- Donner le **nom** du jeton de déploiement au lieu de son **nom d'utilisateur** : `authentication required`.
- Une Application en `default` qui pointe vers un espace absent : `namespaces "…" not found` à la synchronisation (pas de `CreateNamespace`, voulu).
- Attendre trois minutes à chaque essai : `--refresh`.
- Modifier la page dans le cluster (`kubectl edit configmap`) pour « tester vite » : c'est une dérive (E05).

**En production chez MédiSphère**

Les Applications ne sont jamais créées par la CLI : elles sont dans `plateforme/gitops` (E06), dans un projet qui limite ce qu'elles peuvent faire (E07). La CLI sert à lire (`get`, `diff`, `history`) et, en urgence encadrée, à synchroniser.

---

### M20-E05 — Synchronisation, santé, dérive et auto-réparation

**Solution**

*A. Dérive.*

1. ```
   admin@adm01:~$ kubectl --context k8s-par1 -n wb-essais scale deploy/labo --replicas=4
   admin@adm01:~$ argocd app get labo | grep -E 'Sync Status|Health Status'
   Sync Status:        OutOfSync from main (e9167d2)
   Health Status:      Healthy
   admin@adm01:~$ argocd app diff labo
   ===== apps/Deployment wb-essais/labo ======
   187c187
   <   replicas: 4
   ---
   >   replicas: 2
   ```
   Quatre pods tournent, `OutOfSync` mais `Healthy` (tout fonctionne). La synchronisation automatique ne corrige rien : elle réagit à une **nouvelle révision de Git**, et la révision `e9167d2` a déjà été synchronisée (« Automated Sync Semantics » : une seule tentative par commit).
2. ```
   admin@adm01:~$ argocd app set labo --self-heal
   admin@adm01:~$ kubectl --context k8s-par1 -n wb-essais get deploy labo -o jsonpath='{.spec.replicas}'
   2
   ```
   Quelques secondes (la première tentative d'auto-réparation part après un délai court, puis les suivantes s'espacent : paramètres `controller.self.heal.*` de `argocd-cmd-params-cm`). L'historique ne gagne **pas** de ligne : une auto-réparation resynchronise la même révision, et l'historique ne garde qu'une entrée par révision déployée.
3. L'étiquette **nouvelle** (`essai=main`) reste ; l'étiquette **modifiée** (`app.kubernetes.io/part-of`) est rétablie à sa valeur de Git. Argo CD ne compare que ce que Git déclare : un champ ajouté par quelqu'un d'autre n'est pas une différence (en *client-side apply*, il n'est ni dans le manifeste ni dans `last-applied-configuration` ; en *server-side apply*, il n'appartient pas à `argocd-controller`). C'est voulu (des contrôleurs ajoutent des champs en permanence), et c'est une limite : une dérive par **ajout** passe inaperçue.

*B. Suppression.*

4. Après le retrait du fichier, la ConfigMap reste dans le cluster ; l'application est `OutOfSync` et l'objet porte `requiresPruning: true` :
   ```
   admin@adm01:~$ argocd app get labo -o json | jq -c '.status.resources[] | select(.name=="labo-essai")'
   {"version":"v1","kind":"ConfigMap","namespace":"wb-essais","name":"labo-essai","status":"OutOfSync","requiresPruning":true}
   ```
   Le journal du contrôleur le dit : `Skipping auto-sync: need to prune extra resources only but automated prune is disabled`.
5. Elle ne disparaît pas tout de suite : la révision courante a déjà été synchronisée (une fois, sans suppression). Elle disparaît à la **prochaine comparaison** de l'application (réconciliation périodique, ou tout de suite avec `argocd app get labo --refresh`), qui relance une synchronisation automatique, avec suppression cette fois. Constaté : `Adding resource result, status: 'Pruned'`. Autre chemin, explicite : `argocd app sync labo --prune`.

*C. Méthode d'application et comparaison.*

6. Avant : gestionnaire `argocd-controller` en `Update`, annotation `last-applied-configuration`. Après `ServerSideApply=true` et une synchronisation :
   ```
   admin@adm01:~$ kubectl --context k8s-par1 -n wb-essais get deploy labo --show-managed-fields -o json | jq -c '[.metadata.managedFields[] | {manager, operation}]'
   [{"manager":"argocd-controller","operation":"Apply"},{"manager":"kube-controller-manager","operation":"Update"}]
   ```
   L'annotation `last-applied-configuration` a disparu et la propriété des champs est passée d'une opération `Update` à une opération `Apply` du même gestionnaire : c'est la **migration du client-side apply** d'Argo CD (activée par défaut, option `ClientSideApplyMigration`), qui réécrit les `managedFields` avant d'appliquer. Aucun pod recréé (même ReplicaSet), le modèle de pod n'a pas changé.
7. Sans diff côté serveur, Argo CD compare son rendu à l'objet vivant en « normalisant » de son côté ; avec, il demande à l'API un *server-side apply* **à blanc** et compare le résultat à l'objet vivant : tout ce que l'API, les CRD (valeurs par défaut de leurs schémas) et les webhooks de validation ajoutent est pris en compte. Cas réel constaté à la rédaction : la HTTPRoute de MédiAgenda, appliquée telle que rendue par le chart, reste `OutOfSync` en diff classique (l'API ajoute `group`, `kind`, `weight` aux `backendRefs`) alors que `argocd app diff` n'affiche rien ; avec le diff côté serveur, elle est `Synced`. Valeurs : [`values.yaml`](fichiers/M20-E05/k8s/composants/argocd/values.yaml) (`configs.params."controller.diff.server.side": "true"`). Le contrôleur redémarre seul : son modèle de pod porte l'annotation `checksum/cmd-params`, calculée par le chart à partir de `argocd-cmd-params-cm`.
8. Réglages retenus (à reprendre dans RB-200, E22) :

   | Environnement | Synchronisation | `selfHeal` | `prune` | Raison |
   |---|---|---|---|---|
   | `dev` | automatique | oui | oui | Git fait foi, cycle court ; données protégées par `Prune=false` |
   | `recette` | automatique | oui | oui | même chose ; c'est là qu'on doit voir une dérive tout de suite |
   | `prod` | **manuelle** | sans objet | **non** (suppression à la main, relue) | chaque changement est une décision ; une suppression est vue avant d'être faite |

**Explications**

Trois mécanismes distincts : la **comparaison** (toujours active, elle produit `OutOfSync`), la **synchronisation automatique** (déclenchée par un nouveau commit), l'**auto-réparation** (déclenchée par un changement du cluster). La suppression est une option de la synchronisation, pas un mécanisme de plus : elle n'agit qu'à une synchronisation.

Le *server-side apply* change ce qu'Argo CD « possède » : un champ qu'il n'a jamais posé n'est jamais effacé par lui, et un champ qu'il a posé puis retiré de Git est supprimé proprement (s'il n'a pas d'autre propriétaire). C'est la base de la cohabitation avec les contrôleurs (HPA, opérateurs) au palier 2 (E12).

**Alternatives**

- `Replace=true` (remplacement de l'objet) : pour les rares objets que *apply* ne sait pas modifier ; destructeur (recrée l'objet), jamais par défaut.
- Diff côté serveur par Application (annotation `argocd.argoproj.io/compare-options: ServerSideDiff=true`) plutôt que global : utile pour un essai ; MédiSphère le veut partout.
- `ignoreDifferences` pour masquer un faux `OutOfSync` : à réserver aux vrais partages de champs (E12), pas aux valeurs par défaut que le diff côté serveur comprend.

**Pièges classiques**

- Croire que la synchronisation automatique corrige une dérive : non, c'est `selfHeal`.
- Activer `prune` et s'étonner que rien ne se passe : il faut une synchronisation (rafraîchissement, commit, ou `sync --prune`).
- Activer `prune` sur une application qui porte des données sans `Prune=false` sur ces objets.
- `selfHeal` sur une application dont un autre contrôleur modifie un champ que Git déclare (HPA et `replicas`) : bataille permanente (E39), visible dans l'historique des événements, pas dans celui de l'application.
- Oublier que la dérive par **ajout** (un conteneur *sidecar* ajouté à la main dans une liste que Git déclare, un champ nouveau) n'est pas toujours vue.

**En production chez MédiSphère**

Réglages de la table ci-dessus, posés par l'ApplicationSet de MédiAgenda (E10) ; diff côté serveur global ; alerte sur toute application de production `OutOfSync` depuis plus de quinze minutes (M21) ; et une dérive en production se traite comme un incident : qui, quand, pourquoi (journal d'audit de l'API, M14-E27).

---

### M20-E06 — Le dépôt `plateforme/gitops` et l'application racine

**Solution**

*A. Les identifiants.*

1. Un modèle d'identifiants (`repo-creds`) vaut pour **toute** URL qui commence par son préfixe : un nouveau dépôt du groupe est lisible sans rien déclarer, et un jeton se change en un seul endroit. Quand plusieurs préfixes correspondent, Argo CD prend le **plus long** (« best match »), indépendamment de l'ordre de déclaration. Un modèle par groupe, parce qu'un jeton de déploiement de groupe ne lit que son groupe.
2. Script : modification de `secrets-k8s.sh` décrite dans [`secrets-k8s.sh.extrait-E06`](fichiers/M20-E06/k8s/outils/secrets-k8s.sh.extrait-E06) (trois changements : composant accepté s'il a un module, Vault déchiffré, appel de `secrets_<composant>_<mode>`), module [`secrets-k8s.d/argocd.sh`](fichiers/M20-E06/k8s/outils/secrets-k8s.d/argocd.sh), modèle du Vault [`secrets/argocd.yml.exemple`](fichiers/M20-E06/k8s/secrets/argocd.yml.exemple). Le jeton passe par une substitution de processus (`--from-file=password=<(printf …)`), le Secret est appliqué en *server-side apply* sous le gestionnaire `secrets-k8s`.
   ```
   admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer argocd && outils/secrets-k8s.sh verifier argocd
   [OK] argocd/repo-creds-plateforme à jour (https://git01.par1.medisphere.internal/plateforme/, argocd-plateforme)
   …
   [OK] argocd/repo-creds-formation identique au Vault
   admin@adm01:~$ argocd repocreds list
   URL PATTERN                                         USERNAME           SSH_CREDS  TLS_CREDS
   https://git01.par1.medisphere.internal/plateforme/  argocd-plateforme  false      false
   https://git01.par1.medisphere.internal/mediagenda/  argocd-mediagenda  false      false
   https://git01.par1.medisphere.internal/medidoc/     argocd-medidoc     false      false
   https://git01.par1.medisphere.internal/formation/   argocd-formation   false      false
   ```
3. `argocd repo rm https://git01.par1.medisphere.internal/formation/gitops-labo.git`, puis `argocd app get labo --hard-refresh` (nouvelle lecture du dépôt, sans le cache) : `labo` reste `Synced`, sans `ComparisonError`. Le dépôt n'est plus déclaré ; ses identifiants viennent du modèle `formation`.

*B. Le dépôt et la racine.* Fichiers : [`README.md`](fichiers/M20-E06/gitops/README.md), [`racine/racine.yaml`](fichiers/M20-E06/gitops/racine/racine.yaml), [`racine/applications.yaml`](fichiers/M20-E06/gitops/racine/applications.yaml), [`applications/labo.yaml`](fichiers/M20-E06/gitops/applications/labo.yaml).

4. Une Application de `racine/` peut créer d'autres Applications dans **n'importe quel** projet : qui fusionne dans `plateforme/gitops` décide de ce que fait Argo CD, donc de ce que fait le contrôleur, administrateur de fait du cluster. D'où `main` protégée, fusion par les seuls Maintainers, relecture du champ `project`.
5. Le finaliseur sur `labo` : supprimer `labo` (fichier retiré de Git, ou `argocd app delete`) doit supprimer ses objets, sinon ils restent orphelins dans `wb-essais`. Surtout pas sur `racine` ni `applications` : leur suppression (une erreur dans un fichier, un `delete` malheureux) déclencherait en cascade la suppression de **toutes** les Applications filles… qui, si elles ont ce finaliseur, supprimeraient leurs charges. Sans finaliseur, supprimer la racine n'enlève que l'objet `racine`.
6. ```
   admin@adm01:~/src/gitops$ kubectl --context k8s-par1 apply --server-side --field-manager=amorcage -f racine/racine.yaml
   application.argoproj.io/racine serverside-applied
   admin@adm01:~$ argocd app list
   NAME                 CLUSTER                         NAMESPACE  PROJECT  STATUS  HEALTH   SYNCPOLICY  …  PATH
   argocd/applications  https://kubernetes.default.svc  argocd     default  Synced  Healthy  Auto-Prune  …  applications
   argocd/labo          https://kubernetes.default.svc  wb-essais  default  Synced  Healthy  Auto-Prune  …  k8s
   argocd/racine        https://kubernetes.default.svc  argocd     default  Synced  Healthy  Auto-Prune  …  racine
   admin@adm01:~$ kubectl --context k8s-par1 -n argocd get applications -o custom-columns='NOM:.metadata.name,SUIVI:.metadata.annotations.argocd\.argoproj\.io/tracking-id'
   NOM            SUIVI
   applications   racine:argoproj.io/Application:argocd/applications
   labo           applications:argoproj.io/Application:argocd/labo
   racine         racine:argoproj.io/Application:argocd/racine
   ```
   `racine` gère `racine` et `applications` ; `applications` gère `labo`. `labo` n'a pas été recréée : même objet (même `creationTimestamp`), mêmes pods ; Argo CD a appliqué par-dessus la même spécification, plus le finaliseur et l'annotation de suivi.
7. L'étiquette ajoutée à `racine.yaml` apparaît sur l'objet `racine` après la fusion (au plus trois minutes) : la racine s'est synchronisée elle-même. Puis :
   ```
   admin@adm01:~$ argocd app delete labo --cascade=false --yes
   application 'labo' deleted
   admin@adm01:~$ kubectl --context k8s-par1 -n argocd get application labo -o jsonpath='{.metadata.creationTimestamp}'
   2026-10-23T11:02:17Z
   ```
   `applications` (auto-réparation) recrée `labo` dans les secondes qui suivent ; ses objets dans `wb-essais` n'ont pas bougé (même ReplicaSet). Effet de bord à connaître : l'**historique** de `labo` est reparti de zéro (il vit dans l'objet Application, pas dans Git). Le check d'E04 et d'E05 en tient compte.

**Explications**

L'*App of Apps* n'a rien de spécial : une Application dont les manifestes sont des Applications. La racine qui se décrit elle-même ferme la boucle : après l'amorçage, **tout** ce qui concerne Argo CD au-dessus de sa release est dans Git, y compris la façon dont la racine se synchronise. Reconstruire (E28), c'est réinstaller la release, recréer les Secrets, appliquer `racine.yaml` : le reste revient seul.

Deux niveaux (racine → groupes → applications) plutôt qu'une racine qui lit tout le dépôt en récursif : chaque dossier a son Application, lue sans récursion, avec `include: "*.yaml"` ; un sous-dossier de valeurs (M21-M23) n'est jamais appliqué par accident, et chaque groupe a son projet (E07) et ses options. Le motif `*` d'un `include` Argo CD peut traverser les `/` : une racine récursive filtrée par motif est plus fragile qu'il n'y paraît.

**Alternatives**

- **ApplicationSet générateur « Git directories »** à la place de la racine pour les applications : c'est le palier 2 (E10) pour MédiAgenda ; la racine reste utile pour amorcer (projets, ApplicationSets eux-mêmes).
- **Racine par Helmfile** (objet `Application` dans `extraObjects` du chart, ou chart `argocd-apps`) : l'amorçage serait automatique à l'installation ; mais la racine dépendrait de la release d'Argo CD (une erreur dans l'un casse l'autre), et elle cesserait d'être décrite dans `plateforme/gitops`.
- **Un dépôt par équipe** pour les Applications (chaque équipe gère ses Applications) : avec « Applications in any namespace » (`application.namespaces`) ; plus d'autonomie, plus de surface (E25).

**Pièges classiques**

- Créer la racine à la main avec une spécification **différente** du fichier : la première synchronisation la modifie (parfois de façon inattendue, par exemple le projet).
- Mettre le finaliseur `resources-finalizer` sur la racine : un `delete` emporte tout.
- Supprimer `labo` sans `--cascade=false` alors qu'elle a le finaliseur : ses objets sont supprimés, puis recréés quand la racine la recrée (coupure).
- Retirer `racine/racine.yaml` du dépôt : la racine se supprime elle-même.
- Oublier `--hard-refresh` pour tester des identifiants : le cache du *repo-server* répond sans relire le dépôt.
- Croire que l'historique d'une Application survit à sa recréation.

**En production chez MédiSphère**

`plateforme/gitops` est le dépôt le plus sensible de la plateforme après `plateforme/k8s` : Maintainers restreints (toi, Karim Benali), MR obligatoire, notification sur chaque fusion (E19), webhook vers Argo CD (E27). Les jetons de déploiement ont une échéance au calendrier ; leur rotation : nouveau jeton, Vault, `secrets-k8s.sh appliquer argocd`, vérification, révocation de l'ancien.

---

### M20-E07 — AppProjects : cloisonner les équipes

**Solution**

*A. Concevoir.*

1. Types rendus (M17-E09) : `dev` — Deployment, StatefulSet (Valkey), Cluster CNPG, Services, ConfigMaps, ServiceAccount, HTTPRoute, NetworkPolicy ×3, CiliumNetworkPolicy ×2 ; `recette` — le même ensemble sans la base (gérée par `plateforme/k8s` depuis le M16) ; `prod` — le même ensemble, plus un PodDisruptionBudget, **et** `Namespace`, `ResourceQuota`, `LimitRange` (fichier `overlays/prod/espace.yaml`). Ces trois derniers seraient refusés : ils appartiennent à la plateforme, comme pour `dev` et `recette` (`plateforme/k8s/espaces/`).
2. Les NetworkPolicy de `mediagenda-dev` viennent de trois sources : le **chart** (`mediagenda`, politique d'entrée de l'API), le component **`dependances`** (`mediagenda-db`, `valkey`), et `plateforme/k8s` (`refus-par-defaut` et les politiques de `espaces/politiques-mediagenda/`, M15-E17). Interdire le type `NetworkPolicy` au projet casserait MédiAgenda (ses propres politiques seraient refusées à la synchronisation). Réponse proposée dans la MR : `NetworkPolicy` reste **permis** aux équipes (micro-segmentation de leur application) ; les invariants de la plateforme sont des **refus de cluster** (CiliumClusterwideNetworkPolicy `isolement-*`, M15-E28), qu'aucune politique d'espace ne peut lever, et des objets de cluster qu'aucun projet d'équipe ne peut créer. Reste un risque : une équipe pourrait déclarer dans son dépôt une politique **nommée** `refus-par-defaut` et l'écraser (Argo CD force la propriété des champs) ; la parade est hors d'Argo CD (règle d'admission au M26, Kyverno), ou un renommage de la politique de plateforme dans un espace de noms d'objets réservé. Écart assumé et documenté par rapport au ticket.
3. Ressource orpheline : un objet d'espace de **premier niveau** (sans `ownerReferences`), dans une destination du projet, qu'aucune Application ne suit. Jamais orphelins : les types interdits par le projet, le ServiceAccount `default`, la ConfigMap `kube-root-ca.crt`, le Service `kubernetes`. Coût : Argo CD doit surveiller **tous** les objets des espaces de destination (mémoire et requêtes du contrôleur) : à réserver aux espaces bien délimités. Activé sur `mediagenda` et `medidoc` ; pas sur `labo` (`wb-essais` est partagé par les essais) ni sur `plateforme` (l'espace `argocd` contient la release). Exclusions pour MédiAgenda : le Secret `harbor-pull` (créé par la plateforme) et la NetworkPolicy `refus-par-defaut` ; les Secrets de CNPG ont un propriétaire (le Cluster) et ne sont pas orphelins.

*B. Les objets d'espace de la production.* Fichiers : [`espaces/mediagenda-prod/`](fichiers/M20-E07/k8s/espaces/mediagenda-prod/) de `plateforme/k8s` (mêmes noms et valeurs que l'overlay), [`overlays/prod/espace.yaml`](fichiers/M20-E07/deploiement/overlays/prod/espace.yaml) de `mediagenda/deploiement` (ne garde que `refus-par-defaut`).

4. Ordre : d'abord `task espaces` (le gestionnaire `plateforme-k8s` devient copropriétaire des champs, mêmes valeurs, aucun conflit), ensuite le retrait de l'overlay. Retirer des objets d'un overlay appliqué par `kubectl apply` ne les supprime pas (rien ne fait de *prune*) ; Argo CD ne les supprimera pas non plus (il ne les a jamais suivis). Dans l'autre ordre, il y aurait un intervalle où plus aucun dépôt ne décrit l'espace de production. `managedFields` du ResourceQuota : avant, `kubectl` (`Apply`) ; après, `kubectl` et `plateforme-k8s` (`Apply`), copropriétaires. L'ancien gestionnaire `kubectl` disparaîtra en M20-E30.

*C. Les projets.* Fichiers : [`projets/`](fichiers/M20-E07/gitops/projets/) et [`racine/projets.yaml`](fichiers/M20-E07/gitops/racine/projets.yaml), [`racine/racine.yaml`](fichiers/M20-E07/gitops/racine/racine.yaml) et [`racine/applications.yaml`](fichiers/M20-E07/gitops/racine/applications.yaml) (projet `plateforme`), [`applications/labo.yaml`](fichiers/M20-E07/gitops/applications/labo.yaml) (projet `labo`). Les fichiers montrent l'état **final** ; dans la MR 1, `racine/projets.yaml` porte `project: default`.

5. ```
   admin@adm01:~$ argocd proj list
   NAME        DESCRIPTION                     DESTINATIONS                              SOURCES                                          CLUSTER-RESOURCE-WHITELIST  NAMESPACE-RESOURCE-BLACKLIST  …  ORPHANED-RESOURCES
   default                                     *,*                                       *                                                */*                         <none>                           disabled
   labo        Essais de la plateforme …       https://kubernetes.default.svc,wb-essais  https://git01…/formation/gitops-labo.git         <none>                      2 resources                      disabled
   mediagenda  MédiAgenda (équipe de Julien…   3 destinations                            https://git01…/mediagenda/deploiement.git        <none>                      2 resources                      enabled (warn=true, ignored 2)
   medidoc     MédiDoc — dev, recette          2 destinations                            https://git01…/medidoc/deploiement.git           <none>                      2 resources                      enabled (warn=true, ignored 2)
   plateforme  Services de plateforme …        https://kubernetes.default.svc,argocd     https://git01…/plateforme/gitops.git             */*                         <none>                           disabled
   ```
   (Colonnes abrégées.) Le finaliseur `resources-finalizer.argocd.argoproj.io` d'un AppProject empêche sa suppression tant qu'une Application s'y range.
6. Dans la MR 1, le projet `plateforme` n'existe pas encore : une Application qui le référence serait invalide (« project plateforme does not exist »)… et si c'est la racine, elle ne peut plus se synchroniser pour créer ce projet. Il faut que l'Application `projets` ait créé les projets **avant** qu'une autre Application s'y range. Après la MR 1, attends `projets` `Synced` (`argocd app get projets --refresh`).
7. Verrouiller `default` en dernier : tant qu'une Application y est, la verrouiller la rend invalide. Après la MR 3 :
   ```
   admin@adm01:~$ argocd proj get default
   Name:                        default
   Description:                 Verrouillé — utiliser plateforme, mediagenda, medidoc ou labo
   Destinations:                <none>
   Repositories:                <none>
   …
   ```

*D. Prouver.*

8. ```
   admin@adm01:~$ argocd app create essai-destination --project labo --repo https://git01.par1.medisphere.internal/formation/gitops-labo.git --path k8s --dest-server https://kubernetes.default.svc --dest-namespace mediagenda-dev
   FATA[0000] rpc error: code = InvalidArgument desc = application spec for essai-destination is invalid: InvalidSpecError: application destination server 'https://kubernetes.default.svc' and namespace 'mediagenda-dev' do not match any of the allowed destinations in project 'labo'
   admin@adm01:~$ argocd app create essai-projet --project labo --repo https://git01.par1.medisphere.internal/formation/gitops-labo.git --revision essai-projet --path essai --dest-server https://kubernetes.default.svc --dest-namespace wb-essais
   admin@adm01:~$ argocd app sync essai-projet
   …  ResourceQuota  wb-essais  quota-essai  Unknown  Missing  resource :ResourceQuota is not permitted in project labo
   Phase:              Failed
   Message:            one or more synchronization tasks are not valid: resource :ResourceQuota is not permitted in project labo
   admin@adm01:~$ argocd app delete essai-projet --yes
   ```
   Le refus d'un type arrive à la **synchronisation** (la création est acceptée) ; celui d'une destination dès la **création**. Pourquoi un dossier à part : une Application qui rendrait `k8s/` déploierait les **mêmes** objets que `labo` ; Argo CD le signale (condition `SharedResourceWarning` : « Deployment/labo is part of applications argocd/essai-projet and labo ») et, à la synchronisation, réécrirait leur annotation de suivi : `labo` perdrait ses objets au profit de l'essai (et sa suppression les emporterait).
9. Voir le `README.md` de `plateforme/gitops`, section « Projets » (à ajouter) : un tableau projet → sources → destinations → objets permis, et la procédure « ajouter une équipe » (projet, espace dans `plateforme/k8s`, jeton de groupe, modèle d'identifiants).

**Explications**

Un AppProject est une **politique** évaluée par Argo CD avant de rendre et avant d'appliquer : sources (motifs d'URL), destinations (serveur + espace, ou nom de cluster), types d'objets (listes blanches et noires par groupe et type). Il ne remplace pas le RBAC Kubernetes : le contrôleur garde ses droits sur le cluster ; c'est Argo CD qui s'interdit d'en faire usage hors du projet. D'où l'importance de la protection du dépôt de la racine (E06) et, à terme, de comptes de service par destination.

Les deux listes ne se lisent pas de la même façon : `clusterResourceWhitelist` vide = **rien** permis ; `namespaceResourceWhitelist` vide = **tout** permis (d'où `namespaceResourceBlacklist`). Le groupe d'API compte : `NetworkPolicy` est dans `networking.k8s.io` (l'exemple de la page « Declarative Setup » l'écrit dans le groupe vide : il ne filtrerait rien).

**Alternatives**

- Un projet par **environnement** (`mediagenda-prod` séparé) : utile si les règles diffèrent (fenêtres de synchronisation, rôles) ; MédiSphère met les fenêtres et les rôles dans le même projet avec des motifs par application (E24, E29).
- `namespaceResourceWhitelist` (liste blanche des types d'espace permis) : plus strict, mais chaque nouveau type (Rollout au palier 2, ServiceMonitor au M21) demande une MR de la plateforme. Écart possible plus tard, une fois le catalogue de types stabilisé.
- `sourceNamespaces` et Applications dans les espaces des équipes : pour l'autonomie des équipes (E25).

**Pièges classiques**

- Tout faire dans une seule MR : la racine se retrouve dans un projet qui n'existe pas encore.
- Verrouiller `default` avant d'en avoir sorti toutes les Applications.
- Écrire `group: ''` pour `NetworkPolicy`.
- `orphanedResources: {warn: false}` pour « désactiver » : la surveillance reste active (et coûteuse).
- Une destination `namespace: '*'` dans le projet `plateforme` « pour plus tard » : c'est donner l'espace `kube-system` au dépôt de la racine.
- Tester un refus avec une Application qui partage les objets d'une autre.

**En production chez MédiSphère**

Chaque équipe a son projet ; un nouvel espace ou un nouveau type d'objet passe par une MR de la plateforme. Le projet `plateforme` est le seul à pouvoir créer des objets de cluster, depuis le seul dépôt `plateforme/gitops`. Les rôles de projet (synchroniser `dev` et `recette`, lire `prod`) et les fenêtres de synchronisation viennent au palier 3 (E24, E29). Les avertissements d'orphelins de `mediagenda-*` sont relus chaque semaine : un orphelin, c'est soit un oubli dans Git, soit un geste manuel à expliquer.

---

### M20-E08 — Reprendre MédiAgenda dev sous Argo CD sans coupure

**Solution**

*A. Avant.*

1. Avec l'outil fourni :
   ```
   admin@adm01:~$ ~/DevOpsPrivateCloud/modules/20-gitops/ressources/E08-reprise/instantane.sh mediagenda-dev mediagenda > ~/m20/e08/avant.txt
   admin@adm01:~$ cat ~/m20/e08/avant.txt
   = révision du Deployment : 7
   = image(s) : registry.par1.medisphere.internal/medisphere/mediagenda-api@sha256:…
   ~ génération : 9
   ~ suivi Argo CD : (aucun)
   ~ gestionnaire : kubectl (Apply)
   ~ gestionnaire : kube-controller-manager (Update)
   = ReplicaSet mediagenda-6b985974bf révision 7 créé 2026-10-20T14:03:11Z réplicas 1
   = ReplicaSet mediagenda-5d4c7f9b8c révision 6 créé 2026-10-17T09:41:52Z réplicas 0
   = pod mediagenda-6b985974bf-t4dd8 créé 2026-10-20T14:03:11Z redémarrages 0
   ```
   (Valeurs représentatives : ta révision et tes noms diffèrent.) Le gestionnaire du job `deployer-dev` est celui qu'il a donné à `kubectl apply --server-side` : `kubectl` par défaut, ou le nom passé par `--field-manager` si le M19-E18 en a fixé un.
2. Surcharge du job dans le `.gitlab-ci.yml` de `mediagenda/deploiement` (après l'`include` du composant) :
   ```yaml
   # M20-E08 (DEV-2108) : mediagenda-dev est appliqué par Argo CD (plateforme/gitops,
   # applications/mediagenda-dev.yaml). Le job du composant « deploiement » ne doit plus tourner.
   # Retrait complet des jobs de déploiement : M20-E30.
   deployer-dev:
     rules:
       - when: never
   ```
   Un job défini par un `include` (composant compris) se fusionne avec une définition locale du même nom : la clé `rules` locale remplace celle du composant, et le job n'est jamais créé. La validation (`deploiement:valider`, vérification des signatures) reste. Vérification : le pipeline de la fusion n'a plus de `deployer-dev`, et l'environnement `dev` de GitLab montre que le dernier déploiement réussi porte sur le **dernier** commit de `main` (sinon, la première synchronisation d'Argo CD livrerait les commits intermédiaires : ce ne serait plus une reprise, mais un déploiement).
3. [`components/dependances/postgresql.yaml`](fichiers/M20-E08/deploiement/components/dependances/postgresql.yaml) : `Prune=false` empêche la suppression de la base par une synchronisation (fichier retiré, renommé, `kustomization.yaml` cassé) ; `Delete=false` empêche sa suppression avec l'Application (cascade). Personne n'applique plus ce fichier tant qu'Argo CD ne gère pas `dev` : l'annotation sera posée **par la synchronisation de reprise** (elle apparaît dans le diff, c'est attendu). Le component sert aussi à la production : elle en bénéficiera au palier 2.

*B. La reprise.* Fichier : [`applications/mediagenda-dev.yaml`](fichiers/M20-E08/gitops/applications/mediagenda-dev.yaml) (état final : synchronisation automatique ; à l'étape 4, sans le bloc `automated`).

4. Après la fusion, `applications` crée `mediagenda-dev` : **`OutOfSync`** (aucun objet ne porte encore l'annotation de suivi : pour Argo CD, il doit la poser partout), santé `Healthy` (les objets existent et fonctionnent).
5. Le diff (sortie abrégée, constatée sur la même overlay) :
   ```
   admin@adm01:~$ argocd app diff mediagenda-dev
   ===== /ConfigMap mediagenda-dev/mediagenda ======
   8a9,10
   >   annotations:
   >     argocd.argoproj.io/tracking-id: mediagenda-dev:/ConfigMap:mediagenda-dev/mediagenda
   …
   ===== apps/Deployment mediagenda-dev/mediagenda ======
   4a5
   >     argocd.argoproj.io/tracking-id: mediagenda-dev:apps/Deployment:mediagenda-dev/mediagenda
   …
   ===== postgresql.cnpg.io/Cluster mediagenda-dev/mediagenda-db ======
   3a4,6
   >   annotations:
   >     argocd.argoproj.io/sync-options: Prune=false,Delete=false
   >     argocd.argoproj.io/tracking-id: mediagenda-dev:postgresql.cnpg.io/Cluster:mediagenda-dev/mediagenda-db
   ```
   Attendu : l'annotation de suivi sur chaque objet, et l'annotation de protection de la base. **Bloquant** : toute ligne sous `spec.template` d'un Deployment ou d'un StatefulSet (image, digest, variable, étiquette du modèle, ressources) : la synchronisation créerait un nouveau ReplicaSet (ou redémarrerait Valkey). Causes typiques : `main` en avance sur ce qui tourne (une promotion fusionnée après le dernier `deployer-dev`), ou un geste manuel passé (la dérive de l'E01).
6. ```
   admin@adm01:~$ argocd app sync mediagenda-dev --dry-run
   admin@adm01:~$ argocd app sync mediagenda-dev
   …
   Phase:              Succeeded
   Message:            successfully synced (all tasks run)
   admin@adm01:~$ ~/DevOpsPrivateCloud/modules/20-gitops/ressources/E08-reprise/instantane.sh mediagenda-dev mediagenda > ~/m20/e08/apres.txt
   admin@adm01:~$ diff ~/m20/e08/avant.txt ~/m20/e08/apres.txt
   3,4c3,4
   < ~ génération : 9
   < ~ suivi Argo CD : (aucun)
   ---
   > ~ génération : 10
   > ~ suivi Argo CD : mediagenda-dev:apps/Deployment:mediagenda-dev/mediagenda
   5a6
   > ~ gestionnaire : argocd-controller (Apply)
   ```
   Aucune ligne `=` n'a changé : même révision, mêmes ReplicaSets, mêmes pods. La **génération** a augmenté : pour un Deployment, l'API l'incrémente quand la spécification **ou les annotations** changent ; la révision, elle, ne bouge que si le modèle de pod change. Les **gestionnaires** : `argocd-controller` a appliqué (en forçant la reprise des champs, `--force-conflicts`) les mêmes valeurs que `kubectl` ; pour chaque champ de même valeur, les deux sont copropriétaires, et `kubectl` reste listé. Ce n'est pas gênant tant que personne n'applique plus sous ce nom ; c'est un piège si l'on retire un champ de Git (l'ancien gestionnaire, encore propriétaire, le maintient) : M20-E30 nettoie. `curl -sS https://mediagenda-dev.apps.par1.medisphere.internal/sante` répond `{"statut":"ok",…}` pendant et après.
7. MR : bloc `automated` (`prune`, `selfHeal`) et `spec.info.reprise` à l'heure réelle (UTC). Les âges des pods et le ReplicaSet n'ont pas bougé.

*C. Écrire.* [`docs/livraison/gitops/reprise-sans-coupure.md`](fichiers/M20-E08/medisphere/docs/livraison/gitops/reprise-sans-coupure.md).

**Explications**

Une reprise sans coupure tient à une propriété de Kubernetes : un pod n'est remplacé que si le **modèle de pod** change. Argo CD, en suivi par annotation, n'écrit que dans les métadonnées de l'objet ; en *server-side apply*, il ne touche pas aux champs qu'il ne déclare pas. Si son rendu est identique à ce qui a été appliqué (même overlay, même révision, même version de Kustomize : 5.8.1 des deux côtés), rien d'autre ne change. Toute la méthode consiste à **prouver** cette identité avant d'appliquer (diff), et à la vérifier après (instantané).

Le *dry-run* (`argocd app sync --dry-run`) passe par l'API en mode « à blanc » : il valide aussi les webhooks d'admission et les droits du contrôleur, ce que le diff seul ne fait pas.

**Alternatives**

- Reprise **avec** synchronisation automatique dès la création : fonctionne si le diff est vide d'avance, mais on découvre un écart en production plutôt qu'en relecture.
- `argocd app create --upsert` puis `sync --resource` objet par objet (Deployment en dernier) : plus fin, utile pour une charge plus grosse.
- Option `ServerSideApply=true` **et** un gestionnaire de migration (`argocd.argoproj.io/client-side-apply-migration-manager`) : sert à reprendre des objets appliqués en *client-side* (`kubectl apply` sans `--server-side`) ; ici l'ancien chemin était déjà en *server-side*.

**Pièges classiques**

- Laisser tourner `deployer-dev` pendant la reprise : deux écrivains, des dérives qui vont et viennent.
- Reprendre alors que `main` a une promotion non déployée : la « reprise » livre une version.
- Mettre le finaliseur `resources-finalizer` sur `mediagenda-dev` : en E10, le remplacement par l'ApplicationSet supprimerait MédiAgenda.
- Oublier `CreateNamespace=false` et `ServerSideApply=true` : application côté client, annotation `last-applied-configuration` de plusieurs dizaines de kilo-octets sur la HTTPRoute et le Deployment, gestionnaires mêlés.
- Juger la reprise à la santé de l'application seulement : une application `Healthy` peut avoir recréé tous ses pods. La preuve, ce sont le ReplicaSet et l'âge des pods.
- La base sans `Prune=false` : la première erreur de chemin dans l'overlay la supprime.

**En production chez MédiSphère**

La procédure servira trois fois encore : recette et production de MédiAgenda (palier 2, par l'ApplicationSet), MédiDoc (E33). Pour la production, la reprise se fait dans une fenêtre de changement (CHG-), avec Julien au téléphone, la supervision ouverte (M21) et une photographie archivée dans le ticket. La suppression de l'ancien gestionnaire de champs (`kubectl`) est faite en E30 pour tous les espaces.

---

### M20-E09 — Questions : les principes du GitOps

**1. Les quatre principes** (OpenGitOps 1.0) : l'état voulu est **déclaratif** (nos overlays et Applications décrivent ce qui doit exister, pas comment le créer) ; **versionné et immuable** (`main` protégée de `plateforme/gitops` et `mediagenda/deploiement`, historique complet, rendu commité du chart, images par digest) ; **tiré automatiquement** (le *repo-server* d'Argo CD lit Git, personne ne pousse dans le cluster pour les charges reprises) ; **réconcilié en continu** (le contrôleur compare toutes les trois minutes et corrige la dérive avec `selfHeal`, E05).

**2. Git n'est pas dans les principes.** Ils parlent d'un **magasin d'état** (*state store*) : un système qui stocke l'état voulu de façon versionnée et immuable, avec un historique complet. Git en est la réalisation la plus courante ; un registre OCI (artefacts de manifestes signés, adressés par digest) ou un compartiment S3 versionné et verrouillé peuvent en tenir lieu (Flux sait tirer des artefacts OCI, Argo CD 3.x aussi pour des sources OCI).

**3. Immuabilité de `main`.** Git permet de réécrire l'historique (`push --force`) ; ce qui l'empêche chez nous, c'est la **forge** : branche protégée, poussée directe interdite, poussée forcée refusée, fusion par MR. Les étiquettes `vX.Y.Z` sont protégées aussi (M01). L'immuabilité est donc une propriété de la configuration de GitLab, à vérifier (M01-E11) et à superviser, pas de Git lui-même.

**4. Amorçage.** Un geste d'amorçage est inévitable (installer l'agent, lui dire où regarder) ; le principe est respecté si l'état qu'il crée est lui-même versionné et repris ensuite par la réconciliation. C'est le cas : `racine.yaml` est dans Git, la racine se gère elle-même, et refaire le geste après une reconstruction donne le même résultat (E28). L'entorse serait un état créé à la main **et** non décrit (comme `labo` en E04).

**5. La couche de base.** Elle est déclarative et versionnée (Helmfile dans `plateforme/k8s`), mais ni **tirée** automatiquement ni **réconciliée** en continu : appliquée par une personne, sa dérive n'est vue qu'au prochain `helmfile diff`. Compensations : diff systématique avant `apply`, MR, et un contrôle de dérive (`helmfile diff --detailed-exitcode`, M17-E10, à planifier : piste du « pour aller plus loin » de M17-E16). Pour aller plus loin : une seconde instance minimale (ou Flux, E23) qui gère la couche de base, ou des Applications Argo CD en synchronisation manuelle pour au moins **voir** la dérive. Choix assumé (ADR-0200) : ne pas faire dépendre Argo CD de lui-même.

**6. Secrets.** Les valeurs des Secrets ne sont ni déclarées dans le magasin d'état ni réconciliées : un Secret supprimé à la main n'est recréé que si quelqu'un relance `secrets-k8s.sh`. Le principe « déclaratif » (et « réconcilié ») est en défaut pour eux. Au M25, External Secrets Operator : Git déclare une **référence** (`ExternalSecret` : quel secret, où dans OpenBao), un opérateur la réconcilie en continu ; la valeur reste dans le coffre, l'état voulu est entièrement dans Git.

**7. Fréquence.** Comparaison toutes les 120 s + jusqu'à 60 s d'aléa (`timeout.reconciliation`), auto-réparation quelques secondes après une dérive détectée ; un webhook de la forge (E27) ou un rafraîchissement manuel raccourcit le délai sur un commit. Une synchronisation **manuelle** en production reste compatible : la **réconciliation** (comparaison, détection de l'écart, alerte) est continue ; c'est l'**application** qui attend une décision humaine. Certains y voient un écart au quatrième principe ; c'est un compromis assumé (E14, ADR-0200).

**8. `selfHeal`.** Ce qu'on veut : l'incident de lundi (`kubectl scale` en recette) est effacé en quelques secondes et visible. Obstacle : en pleine panne, une modification à chaud (augmenter une limite de mémoire) est effacée aussitôt. Gestion sans renoncer : la correction passe par Git même en urgence (MR « urgence », fusion rapide) ; à défaut, désactiver temporairement la synchronisation automatique de **cette** application (tracé, ticket), corriger, reporter dans Git, réactiver ; ou une fenêtre de synchronisation d'urgence (E29).

**9. HPA et `replicas`.** Deux écrivains sur le même champ : l'HPA change `spec.replicas`, Argo CD (avec `selfHeal`) le remet à la valeur de Git, l'HPA le rechange : une bataille, des pods créés et supprimés (E39). Ce n'est pas une violation du principe, c'est un **défaut de déclaration** : l'état voulu dit deux choses contradictoires. Solutions : retirer `replicas` du manifeste quand un HPA existe (l'HPA devient seul propriétaire ; c'est la solution propre en *server-side apply*), ou déclarer la différence ignorée (`ignoreDifferences` sur `/spec/replicas` avec `RespectIgnoreDifferences=true`, E12).

**10. *Server-side apply* et suivi.** Le *server-side apply* attribue chaque champ à un gestionnaire : Argo CD ne déclare et ne réconcilie **que** ce que Git décrit, sans effacer ce qu'un opérateur ou un contrôleur ajoute (valeurs par défaut de CNPG, statuts, poids posés par Argo Rollouts) ; l'état voulu reste « tout ce que Git déclare », sans faux écarts. L'annotation de suivi rend la propriété des **objets** explicite : Argo CD sait ce qui est à lui (et peut le supprimer), ce qui est à une autre application (avertissement de partage), et ce qui n'est à personne (orphelins). Les deux rendent la réconciliation sûre en présence d'autres acteurs.

**11. Les MR de promotion de la CI.** Ce n'est pas une entorse : la CI écrit dans **Git** (une MR, relue et fusionnée par un humain), jamais dans le **cluster**. Le modèle *pull* porte sur l'accès au système géré ; que des automates proposent des changements de l'état voulu est normal (Renovate fait de même pour les versions), tant que le changement passe par le magasin d'état et ses contrôles. L'entorse, c'est `deployer-dev` (retiré de `dev` en E08, partout en E30).

**12. Réponse à Claire** (exemple) :
> Oui pour les applications reprises (MédiAgenda dev aujourd'hui, recette et production au palier 2) : leur état voulu est déclaratif, versionné et protégé dans GitLab, tiré et réconcilié en continu par Argo CD, et toute dérive est visible. Trois écarts : (1) la CI écrit encore dans les autres espaces applicatifs — retrait en M20-E30 ; (2) les Secrets sont hors du magasin d'état — External Secrets et OpenBao au M25 ; (3) la couche de base (dont Argo CD) n'est pas réconciliée en continu — choix assumé, compensé par des diffs systématiques et un contrôle de dérive, à trancher dans l'ADR-0200 (M20-E31). La production restera synchronisée à la main : la réconciliation y est continue, l'application est une décision.
