# Final F4 — Phase 2 : Montées — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Les fiches de référence portent des heures et des mesures d'un lab **imaginé** pour montrer la forme : remplace-les par les tiennes.

**Validé hors du lab** (à la rédaction, 23/10/2026) :
- compatibilité de Cilium : documentation `stable` (1.20 : Kubernetes 1.33 à 1.36) et `latest` (« 1.21.0-dev » : 1.34, 1.35, 1.36, 1.37) ; Argo CD 3.5 et KEDA 2.21 d'après le relevé de PLAN §6 ;
- CloudNativePG 1.30, page « Kubernetes Upgrade and Maintenance » : deux PDB par `Cluster`, **bascule avant le drain** quand le nœud du primaire est vidé, `nodeMaintenanceWindow` (`inProgress`, `reusePVC`) conservé pour compatibilité et déconseillé au profit des PDB ; cluster à une instance : drain empêché ;
- Kolla-Ansible, « Operating Kolla » de la série **2026.2** : procédure de série à série (`pip … @stable/2026.2`, ansible-core `>=2.20,<2.21.99`, `install-deps`, comparaison de l'inventaire, `globals.yml`, `kolla-genpwd` + `kolla-mergepwd`, `pull`, `prechecks`, `upgrade` ; `--limit` déconseillé ; SLURP et RabbitMQ) ; la page des notes de version de Kolla-Ansible liste une **23.0.0** pour la série 2026.2 (l'annexe des versions, relevée plus tôt, n'en était qu'à la 23.0.0.0rc1) — confirme sur PyPI ;
- guide de montée d'Argo CD : une page « v3.5 to 3.6 » existe dans la documentation `latest` (contenu non relu à la rédaction : lis-le) ;
- scripts : `bash -n` et `shellcheck` ; YAML et JSON valides.

**Points non testés en conditions réelles** :
- la page « Upgrading kubeadm clusters » et le CHANGELOG de la **1.37** n'ont pas pu être relus à la rédaction : les étapes de RB-142 (M14-E25) restent la référence, à confronter à la page de ta version ;
- `ceph orch host maintenance enter` sous charge (refus sur l'hôte du mgr actif, comportement exact des contrôles) ; playbook `ceph-roulement-systeme.yml` ;
- chemin de l'exemple `passwords.yml` dans un `.venv` créé par `uv` (`share/kolla-ansible/etc_examples/kolla/`) ; prise en charge de Debian 13 par Kolla-Ansible 23.x ;
- pré-arrêt des pods RabbitMQ du Cluster Operator 2.23 pendant un drain (à lire dans le StatefulSet) ;
- variantes de la panne S06 sur `k8s-par1` (sélection de la charge, message exact du webhook, délai d'Argo CD pour signaler l'API retirée).

**Fichiers** : [`fichiers/S03/`](fichiers/S03/) à [`fichiers/S08/`](fichiers/S08/) : `medisphere/…` = `plateforme/medisphere`, `k8s/…`, `gitops/…`, `charts-miroir/…`, `ansible/…`, `openstack/…`, `pve01/…` (script à poser sur `pve01`).

---

### F4-S03 — Go ou no-go : la mineure suivante de Kubernetes

**Solution**

[Matrice](fichiers/S03/medisphere/docs/changements/matrices/compatibilite-kubernetes-1.37.md) et [CHG-3403](fichiers/S03/medisphere/docs/changements/fiches/CHG-3403-go-no-go-kubernetes-1.37.md).

*Inventaire.*

```
admin@adm01:~$ kubectl get deploy,ds,sts -A -o jsonpath='{..image}' | tr ' ' '\n' | sed 's/@.*//' | sort -u
admin@adm01:~/src/k8s$ helmfile -e par1 list
admin@adm01:~$ kubectl -n argocd get applications.argoproj.io -o custom-columns='APP:.metadata.name,CHART:.spec.sources[0].chart,VERSION:.spec.sources[0].targetRevision'
admin@adm01:~$ kubectl get crd -o name | sed 's/.*\///' | awk -F. '{ $1=""; print }' | sort | uniq -c
```

*API.* Côté serveur, sur 7 jours (les compteurs repartent à zéro au redémarrage de chaque kube-apiserver) :

```
admin@adm01:~/src/k8s$ outils/controles-montee.sh api 1.37
```

([`controles-montee.sh`](fichiers/S04/k8s/outils/controles-montee.sh), écrit pour S04 et réutilisé ici.) Côté dépôts : kubeconform `-strict` avec les schémas **natifs** de la cible (`-kubernetes-version 1.37.x`) et nos schémas de CRD, sur les rendus de `plateforme/gitops` et des dépôts de déploiement.

*Analyse au relevé.*

| Bloque ? | Composant | Pourquoi |
|---|---|---|
| **Oui** | Cilium 1.20 | teste 1.33 à 1.36 ; 1.21 (1.34 à 1.37) en développement |
| À monter avant | Argo CD 3.5, KEDA 2.21 | s'arrêtent à 1.36 ; Argo CD 3.6 annoncée le 03/11 |
| À relever | CNPG, ceph-csi, Kyverno, Capsule, kubelet-csr-approver, ESO, opérateurs RabbitMQ… | portent des webhooks à « Fail », des données ou des certificats : un silence ne suffit pas |
| Non | Falco, Tetragon (noyau), outils d'observabilité (clients de l'API) | — |

Décision : **no-go**. Ce qui se fait quand même : Cilium à sa dernière corrective 1.20 (prépare la suite : la 1.21 accepte encore 1.36), remplacement immuable d'un travailleur, correctif 1.36 s'il sort. Conditions de révision : Cilium 1.21 stable **et** installée en 1.36 ; Argo CD et KEDA qui déclarent 1.37 ; plus aucun « à relever » ; métrique des API vide.

*Ce qui change quand Cilium 1.21 est publiée.* Le blocage principal tombe. L'ordre devient : (1) Cilium 1.20 → 1.21 sur un cluster encore en 1.36 (changement séparé : guide de montée de Cilium, contrôle préalable, lecture des *Upgrade Notes* de la 1.21) ; (2) composants qui ne déclaraient pas 1.37 (Argo CD 3.6, KEDA, CHG-3405) ; (3) relecture de la matrice et du CHANGELOG 1.37 ; (4) décision **go** si tout est **D** ; (5) montée par le playbook du M14, sous la sonde (CHG-3404 issue « go »).

**Explications**

La compatibilité se **déclare** : un projet qui ne liste pas une version ne l'a pas testée, même si « ça marche chez d'autres ». Le CNI est l'élément le plus critique : il porte le réseau de chaque pod, les politiques, la Gateway et le chiffrement. Un no-go argumenté n'est pas un échec : 1.36 est maintenue jusqu'en juin 2027 ; monter maintenant n'apporte rien qu'on ne puisse avoir dans six semaines.

**Alternatives**
- Monter malgré Cilium « parce que ça marche » sur un cluster jetable : un essai n'est pas une déclaration ; l'éditeur ne corrigera pas un bogue sur une version non prise en charge.
- Changer de CNI : hors de proportion.
- Cluster neuf en 1.37 à côté et migration des charges (« bleu/vert de cluster ») : la vraie réponse immuable, au prix d'un second cluster (mémoire du lab).

**Pièges classiques**
- Ne regarder que la couche de base et oublier les opérateurs et leurs webhooks.
- Lire « dernière version testée » comme « maximum supporté » sans vérifier la page de **la** version installée.
- Compter la métrique des API sur une heure : un appel quotidien (CronJob, sauvegarde) passe inaperçu.
- Écrire « no-go » sans dire ce qui se fait à la place ni quand on revoit la décision.

**En production chez MédiSphère**
La matrice est générée et tenue à jour par un job (versions installées, pages de compatibilité) ; chaque nouvelle mineure de Kubernetes ouvre une issue de suivi ; la revue de la décision est inscrite au calendrier des changements.

---

### F4-S04 — Monter Kubernetes sans interruption

**Solution** (solution de référence pour l'issue **no-go** ; issue « go » décrite ensuite)

Fichiers : [CHG-3404](fichiers/S04/medisphere/docs/changements/fiches/CHG-3404-kubernetes-cilium-remplacement.md), [RB-341](fichiers/S04/medisphere/docs/changements/runbooks/RB-341-monter-kubernetes-sous-la-sonde.md), [`outils/controles-montee.sh`](fichiers/S04/k8s/outils/controles-montee.sh), extraits de versions ([Cilium](fichiers/S04/k8s/releases/10-reseau.yaml.gotmpl.extrait-F4), [`kubernetes.yml`](fichiers/S04/ansible/inventories/lab/group_vars/k8s_par1/kubernetes.yml.extrait-F4), [`kubeadm-config.yaml`](fichiers/S04/k8s/cluster/kubeadm-config.yaml.extrait-F4), [`outils_k8s`](fichiers/S04/ansible/inventories/lab/host_vars/adm01/outils_k8s.yml.extrait-F4)).

*Avant le go.*

```
admin@adm01:~/src/resilience$ outils/sonde-continuite.sh demarrer CHG-3404 4h
admin@adm01:~/src/k8s$ task etcd:instantane
admin@adm01:~/src/k8s$ outils/controles-montee.sh avant
```

*Cilium (corrective).* Fusion de la MR de `plateforme/k8s`, puis :

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=cilium diff
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=cilium apply
admin@adm01:~$ cilium status --wait && kubectl -n kube-system rollout status ds/cilium
```

Le DaemonSet remplace les agents en roulement ; le chemin de données eBPF reste en place pendant le redémarrage de l'agent d'un nœud : les connexions établies continuent, les nouvelles attendent quelques secondes.

*Remplacement immuable de `k8s-w01`.* Image dorée reconstruite (`plateforme/images`), essayée sur une VM jetable, puis :

```
admin@adm01:~/src/k8s$ outils/controles-montee.sh noeud k8s-w01
admin@adm01:~$ kubectl cordon k8s-w01                       # CNPG bascule si le primaire est ici
admin@adm01:~$ kubectl cnpg status mediagenda-db -n mediagenda-prod
admin@adm01:~$ kubectl drain k8s-w01 --ignore-daemonsets --delete-emptydir-data --timeout=15m
admin@adm01:~$ kubectl delete node k8s-w01
admin@adm01:~/src/infra$ tofu -chdir=envs/k8s state list | grep '"k8s-w01"'
admin@adm01:~/src/infra$ tofu -chdir=envs/k8s plan -replace='<ADRESSE-DE-LA-VM-k8s-w01>'    # 1 à remplacer, 0 autre
admin@adm01:~/src/infra$ tofu -chdir=envs/k8s apply -replace='<ADRESSE-DE-LA-VM-k8s-w01>'
admin@adm01:~/src/k8s$ task noeuds -- --limit k8s-w01,k8s-cp01
admin@adm01:~/src/k8s$ task etiquettes
admin@adm01:~$ kubectl get csr | grep k8s-w01                 # certificat de service du kubelet approuvé
admin@adm01:~/src/k8s$ outils/controles-montee.sh avant
```

Ce qui rend la VM neuve identique aux autres vient du code : MAC et adresses (`noeuds.tf`), carte du VLAN 30 (M16), `vm.max_map_count` (rôle `k8s_travailleur`, M19), configuration du kubelet (`serverTLSBootstrap`, `seccompDefault`, M26), étiquettes de zone (`task etiquettes`), inscription FreeIPA (rôle `freeipa_client` : l'hôte existe déjà dans l'annuaire, la réinscription est à vérifier sur ta version), rôles transverses (`durcissement`, `node_exporter`, `alloy`). La clé d'hôte SSH change : les certificats d'hôte de step-ca (M06) évitent l'alerte sur `adm01`.

*Mesure.* `outils/mesurer-interruption.sh <DÉBUT> <FIN>` ; en-tête de CHG-3404 rempli ; `lab/bin/check F4 4`.

*Issue « go » (quand la chaîne est prête).* (1) Cilium 1.21 : `helm` du guide de montée de Cilium — DaemonSet de contrôle préalable, puis `helmfile apply` de la 1.21 avec les valeurs relues ; (2) MR des versions (extraits) ouvertes, non fusionnées ; (3) le playbook du M14-E25, inchangé :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/k8s-montee-version.yml -e k8s_cible=1.37.<CORRECTIF>
```

avec `outils/controles-montee.sh noeud <nœud>` avant chaque travailleur (le playbook draine depuis `adm01` : ajoute l'appel en tâche déléguée, ou lance-le par nœud avec `--limit`) ; (4) après : fusion des MR, rôles rejoués sans changement, `outils_k8s` (kubectl 1.37), `outils/schemas-crd.sh generer`, `verifier`, `publier "$(date +%Y.%m.%d)"`, instantané etcd de la 1.37.

**Explications**
- **L'éviction et ses gardiens** : un drain ne supprime rien, il demande l'éviction ; l'API la refuse si une PDB l'interdit (429), et la refuse toujours pour un pod couvert par plusieurs PDB. Le drain réessaie sans fin : d'où les contrôles **avant**.
- **CNPG** : le cordon déclenche une bascule voulue du primaire (quelques secondes, absorbées par le pooler) ; c'est la raison pour laquelle on ne tue jamais un primaire et qu'on laisse l'opérateur faire.
- **RabbitMQ** : le pré-arrêt des pods attend que les files quorum gardent leur majorité ; le drain d'un nœud RabbitMQ est donc lent par construction, et sûr.
- **Immuable plutôt qu'en place** : une VM neuve depuis l'image dorée ne garde aucune dérive (paquets, fichiers oubliés) ; c'est aussi ce que fait Cluster API (M18).

**Alternatives**
- Ajouter un quatrième travailleur, déplacer, retirer l'ancien (M14-E17) : zéro perte de capacité, mais 10 Go de plus pendant la fenêtre (mémoire du lab).
- Mise à jour des paquets sur place (`apt`), redémarrage : plus rapide, garde les dérives.
- `nodeMaintenanceWindow` de CNPG : seulement pour un cluster à une instance, au prix d'une coupure.

**Pièges classiques**
- `kubectl drain --disable-eviction` ou suppression d'une PDB « pour passer » : on retire précisément la protection qui évitait la coupure.
- Monter la mineure avant le CNI ; monter les travailleurs avant le plan de contrôle.
- Oublier `schemas-crd` : la CI valide les MR suivantes contre des schémas qui ne correspondent plus au cluster.
- Fusionner la MR des versions **avant** : le prochain passage d'Ansible fait la montée hors fenêtre (ou la refuse).
- `tofu apply` sans `-replace` après un changement d'image : rien ne se passe (l'image n'est lue qu'à la création), ou tout est recréé si le module change.

**En production chez MédiSphère**
Les travailleurs sont remplacés chaque mois par l'image du mois (changement standard) ; les montées de mineure suivent la publication de la matrice ; un environnement de préproduction de même version reçoit chaque changement une semaine avant.

---

### F4-S05 — Monter les composants de plateforme par GitOps

**Solution**

Fichiers : [CHG-3405](fichiers/S05/medisphere/docs/changements/fiches/CHG-3405-composants-plateforme.md), [RB-342](fichiers/S05/medisphere/docs/changements/runbooks/RB-342-monter-un-composant-de-plateforme.md), [`outils/inventaire-api-supprimees.sh`](fichiers/S05/k8s/outils/inventaire-api-supprimees.sh), extraits [`charts-miroir`](fichiers/S05/charts-miroir/charts.extrait-F4.yaml), [Application `kyverno`](fichiers/S05/gitops/plateforme/kyverno.extrait-F4.yaml), [release `argocd`](fichiers/S05/k8s/releases/argocd.extrait-F4.yaml.gotmpl), [release `cnpg`](fichiers/S05/k8s/releases/30-stockage.extrait-F4.yaml.gotmpl).

*Où vit chaque composant* (ADR-0200) :

| Composant | Chemin de la montée |
|---|---|
| Argo CD | `plateforme/k8s` : `releases/argocd.yaml.gotmpl`, `helmfile -e par1 -l composant=argocd diff` puis `apply` |
| CloudNativePG (+ plugin Barman Cloud) | `plateforme/k8s` : `releases/30-stockage.yaml.gotmpl`, Helmfile ; effet sur les instances : RB-164 |
| Kyverno, KEDA, Argo Rollouts, ESO… | `plateforme/charts-miroir` (`charts.yaml`), puis `plateforme/gitops` (`targetRevision` de l'Application) |

*Avant toute MR.*

```
admin@adm01:~/src/k8s$ outils/inventaire-api-supprimees.sh
== Kyverno : ClusterPolicy / Policy (kyverno.io)
  clusterpolicies.kyverno.io : aucun objet
…
== CloudNativePG : Cluster avec spec.backup.barmanObjectStore
  aucun
admin@adm01:~$ helm show values oci://registry.par1.medisphere.internal/charts/kyverno --version 3.9.2 > /tmp/avant.yaml
admin@adm01:~$ helm show values oci://registry.par1.medisphere.internal/charts/kyverno --version <NOUVELLE> > /tmp/apres.yaml
admin@adm01:~$ diff -u /tmp/avant.yaml /tmp/apres.yaml | less
```

*Vagues* : une par composant, mesurée, contrôle de passage **fonctionnel** (politique qui refuse un pod non signé en recette, base qui archive, `ScaledObject` qui réagit à la profondeur de la file). Au relevé, seule une partie des mineures est publiée : la solution de référence prend Argo CD 3.6 et Kyverno 1.20 (si publiées), la dernière corrective de CNPG 1.30 et la mineure de KEDA qui déclare 1.37 — ce qui fait avancer la matrice de S03.

*Après* : `outils/schemas-crd.sh generer`, `publier` ; matrice de S03 mise à jour.

**Explications**
- **CRD avant contrôleurs** : un contrôleur neuf qui démarre sur des CRD anciennes échoue ou ignore des champs ; Argo CD applique les CRD avant les ressources qui les utilisent dans une même synchronisation ; quand un projet livre ses CRD à part (chart séparé, `vendor/`), c'est à toi d'ordonner (vagues, `needs`).
- **Revert plutôt que *rollback*** : avec la synchronisation automatique, le *rollback* de l'interface d'Argo CD est refusé, et Git cesserait de dire la vérité. Le revert garde l'historique.
- **Les CRD ne redescendent pas** : une version stockée changée laisse les objets dans la nouvelle forme ; le retour arrière d'un contrôleur n'est sûr que si l'ancienne version accepte les CRD nouvelles — c'est dans les notes de version ou le guide de montée.

**Alternatives**
- Tout par Argo CD, y compris Argo CD lui-même (*self-managed*) : possible, mais une synchronisation ratée coupe l'outil qui la réparerait (ADR-0200).
- Une MR qui monte tout d'un coup : impossible d'attribuer une régression.

**Pièges classiques**
- Monter Argo CD par `plateforme/gitops` (il n'y est pas).
- Ne lire que les notes de la dernière version alors qu'on en saute plusieurs.
- Oublier le miroir : l'Application pointe une version absente de Harbor (`ComparisonError`), et l'on « répare » en ouvrant Internet au *repo-server*.
- Supprimer l'ancienne version du miroir le jour même : plus de retour arrière.
- CNPG 1.31 alors qu'un `ScheduledBackup` utilise encore la méthode intégrée par défaut (pas de `method: plugin`).

**En production chez MédiSphère**
Renovate ouvre les MR du miroir et de `plateforme/gitops` avec les notes de version ; les montées de composants deviennent des changements standard quand le composant a déjà été monté sans incident deux fois.

---

### F4-S06 — Panne : la montée qui bloque

**Démarche de diagnostic**

*Symptômes → hypothèses.* Pendant une montée, trois mécanismes peuvent bloquer : l'**éviction** (le drain ne finit pas), l'**admission** (rien ne se crée), la **synchronisation GitOps** (Argo CD en erreur). Le symptôme dit lequel regarder ; on ne relance rien avant de savoir.

#### Variante 1 — le drain ne finit jamais (PDB à `maxUnavailable: 0`)

1. Le nœud est cordonné, il porte encore un ou plusieurs pods hors DaemonSets :
   ```
   admin@adm01:~$ kubectl get pods -A --field-selector spec.nodeName=<NŒUD> -o wide | grep -v -e cilium -e node-exporter -e alloy
   ```
2. Relancer le drain **à blanc côté serveur** dit ce qu'il refuse sans rien changer :
   ```
   admin@adm01:~$ kubectl drain <NŒUD> --ignore-daemonsets --delete-emptydir-data --dry-run=server
   ```
   Le message nomme le pod et parle de *disruption budget* (« Cannot evict pod as it would violate the pod's disruption budget »).
3. Quelle PDB, combien de perturbations autorisées, qui l'a créée :
   ```
   admin@adm01:~$ kubectl get pdb -A -o wide
   admin@adm01:~$ kubectl -n <ESPACE> get pdb maintenance-montee -o yaml   # maxUnavailable: 0, étiquettes, managedFields
   ```
   `ALLOWED DISRUPTIONS 0`, `maxUnavailable: 0`, étiquette `auteur: lucas.martin`, gestionnaire `kubectl-client-side-apply` : objet créé à la main, absent de tout dépôt (`git grep maintenance-montee` dans les dépôts de déploiement : rien).
4. **Cause racine** : une PDB qui interdit toute éviction volontaire bloque tout drain du nœud qui porte un pod couvert.
5. **Correctif** : avec l'accord de son auteur (tracé dans la fiche), supprimer la PDB (`kubectl -n <ESPACE> delete pdb maintenance-montee`) — si une protection est voulue, elle se déclare **dans le dépôt** de l'application, avec `maxUnavailable: 1` ou `minAvailable` < réplicas — puis relancer le drain, ou `kubectl uncordon <NŒUD>` si la fenêtre est terminée et qu'on reporte.
6. **Prévention** : contrôles **au** go/no-go et avant chaque drain (`controles-montee.sh`), alerte sur les PDB à 0 perturbation autorisée depuis 1 h (hors primaires CNPG), politique Kyverno qui refuse `maxUnavailable: 0`.

#### Variante 2 — plus aucun pod ne se crée (webhook à « Fail » sans point d'accès)

1. Le contrôleur n'arrive pas à créer : les événements du ReplicaSet le disent.
   ```
   admin@adm01:~$ kubectl -n mediagenda-recette get rs,pods
   admin@adm01:~$ kubectl -n mediagenda-recette get events --sort-by=.lastTimestamp | tail
   ```
   `FailedCreate … failed calling webhook "pods.verification-montee.medisphere.internal" … no endpoints available for service "verification-montee"` (ou un délai dépassé).
2. Le webhook, son service, sa portée :
   ```
   admin@adm01:~$ kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations
   admin@adm01:~$ kubectl get validatingwebhookconfiguration medisphere-verification-montee -o yaml
   admin@adm01:~$ kubectl -n wb-pannes get svc,endpointslices
   ```
   `failurePolicy: Fail`, `namespaceSelector` sur la recette et `wb-essais`, Service sans sélecteur ni point d'accès, étiquette `auteur: lucas.martin`.
3. **Cause racine** : un webhook de validation à « Fail » dont le service ne répond pas refuse **toute** admission qu'il vise ; un drain qui évince des pods de ces espaces les détruit sans qu'ils puissent revenir.
4. **Correctif** : supprimer la configuration de webhook orpheline (et son Service), vérifier que le ReplicaSet recrée le pod manquant, contrôler les webhooks légitimes (Kyverno, Capsule, ESO, cert-manager) : chacun a des points d'accès prêts.
5. **Prévention** : `controles-montee.sh avant` liste les webhooks « Fail » sans point d'accès ; un webhook d'essai se pose en `failurePolicy: Ignore`, avec un `namespaceSelector` étroit et un `timeoutSeconds` court ; politique : création de `ValidatingWebhookConfiguration` réservée à Argo CD (RBAC).

#### Variante 3 — Argo CD en erreur (API retirée dans un manifeste)

1. L'Application de la recette :
   ```
   admin@adm01:~$ argocd app get <APPLICATION-DE-LA-RECETTE>      # ou kubectl -n argocd get applications.argoproj.io <APP> -o yaml
   ```
   Condition `ComparisonError` ou `SyncError` qui parle de `policy/v1beta1` / `PodDisruptionBudget` (« could not find the requested resource », « no matches for kind »).
2. Ce qui a changé dans le dépôt :
   ```
   admin@adm01:~/src/mediagenda-deploiement$ git log -3 --stat -- overlays/recette/
   ```
   Commit de Lucas : `overlays/recette/pdb-maintenance.yaml` en `policy/v1beta1` (API retirée depuis 1.25, jamais servie en 1.36) ajouté aux `resources`.
3. **Cause racine** : un manifeste dans une version d'API que l'API ne sert plus ; Argo CD ne peut ni comparer ni appliquer. (Bonus de la variante : cette PDB aurait doublé celle du chart, et un pod couvert par deux PDB ne s'évince pas.)
4. **Correctif** : MR qui retire le fichier (ou le réécrit en `policy/v1` **s'il** est utile, en vérifiant qu'aucune autre PDB ne couvre les mêmes pods), synchronisation, Application `Synced/Healthy`.
5. **Prévention** : le composant CI/CD `validation` (kubeconform `-strict` avec les schémas de la version du cluster) aurait refusé la MR : vérifie qu'il est **obligatoire** dans `mediagenda/deploiement` (pipeline requis pour fusionner, poussée directe sur `main` interdite). Si l'injection a réussi, c'est qu'il ne l'était pas.

Post-mortem de référence (variante 1) : [`INC-6006-montee-qui-bloque.md`](fichiers/S06/medisphere/docs/changements/post-mortems/INC-6006-montee-qui-bloque.md).

**Explications**

Les trois mécanismes sont des **protections** : la PDB protège la disponibilité, le webhook la conformité, la validation de schéma la cohérence du dépôt. Chacun bloque quand il est mal réglé, et les trois se manifestent au pire moment (pendant une fenêtre) parce que c'est là qu'on évince, qu'on recrée et qu'on synchronise en masse. Le réflexe de « forcer » (drain sans éviction, `failurePolicy: Ignore` partout, synchronisation avec `--force`) retire la protection au lieu de corriger son réglage.

**Alternatives**
- Variante 1 : patcher la PDB (`maxUnavailable: 1`) au lieu de la supprimer — acceptable en urgence si son auteur veut la garder, à reporter dans le dépôt.
- Variante 2 : passer le webhook en `Ignore` pour finir la fenêtre — seulement si son propriétaire est identifié et d'accord ; ici il est orphelin, on le retire.

**Pièges classiques**
- `kubectl drain --disable-eviction` : contourne les PDB, donc aussi celles de CNPG et de RabbitMQ.
- Supprimer une PDB gérée par CNPG parce qu'elle « bloque » : c'est celle qui protège le primaire.
- Supprimer **tous** les webhooks qui échouent, y compris ceux de Kyverno ou de Capsule.
- Corriger la variante 3 dans le cluster (création d'une PDB `policy/v1` à la main) : Argo CD reste en erreur, le dépôt est toujours faux.
- Uncordonner le nœud avant d'avoir compris : on perd l'état qui explique la panne.

**En production chez MédiSphère**
Les contrôles avant drain font partie du playbook de montée (tâche déléguée qui échoue au premier KO) ; alertes sur les PDB bloquantes et sur les webhooks sans point d'accès ; RBAC qui réserve les webhooks et les PDB des espaces applicatifs à Argo CD.

---

### F4-S07 — Monter Ceph sous charge

**Solution**

Fichiers : [CHG-3407](fichiers/S07/medisphere/docs/changements/fiches/CHG-3407-ceph-sous-charge.md) (variante `systeme`), [RB-343](fichiers/S07/medisphere/docs/changements/runbooks/RB-343-ceph-sous-charge.md), [`playbooks/ceph-roulement-systeme.yml`](fichiers/S07/ansible/playbooks/ceph-roulement-systeme.yml), sonde RGW ([extrait](fichiers/S07/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait-F4-S07)), variables de la variante `ceph-orch` ([`ceph_image`](fichiers/S07/ansible/inventories/lab/group_vars/env_m08/ceph.yml.extrait-F4), [`ceph_noeud_version`](fichiers/S07/ansible/inventories/lab/group_vars/role_ceph/ceph_noeud.yml.extrait-F4)).

*Choisir.* Notes de version de Tentacle (dernière corrective publiée ?) ; sur chaque hôte : `dnf check-update`. Au relevé, 20.2.4 est la dernière : variante **systeme**.

*Variante systeme.* Sonde lancée, groupe `continuite-rgw` ajouté, ligne de base. Puis un hôte à la fois, en commençant par celui qui ne porte pas le mgr actif :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ceph-roulement-systeme.yml --limit ceph03
[admin@ceph01 ~]$ sudo ceph -s ; sudo ceph orch host ls          # pendant : ceph03 en maintenance, OSD de ceph03 noout, PG dégradés
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ceph-roulement-systeme.yml --limit ceph02
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/ceph-roulement-systeme.yml --limit ceph01
```

*Variante ceph-orch.* RB-082 du M08 sous la sonde : image tirée d'avance sur chaque hôte, `ceph orch upgrade check`, `noautoscale`, `ceph orch upgrade start --image quay.io/ceph/ceph:v20.2.<CORRECTIVE> --daemon-types mgr` puis le reste, pause au milieu des OSD, `unset noautoscale`, MR `ceph_image`/`ceph_noeud_version` fusionnée, rôle `ceph_noeud`.

*Après.* `ceph health` (`HEALTH_OK`), `ceph osd dump | grep flags` (aucun `noout`), `ceph orch host ls` (aucune maintenance), `ceph osd pool ls detail` (autoscaler `on`) ; journaux de Loki et du sidecar de Thanos sans erreur d'écriture vers le RGW ; mesure.

**Explications**

Le mode maintenance de cephadm fait ce qu'on ferait à la main, avec des contrôles : il vérifie que l'arrêt des démons de l'hôte est sans danger (mon : quorum restant ; OSD : PG qui gardent `min_size`), pose `noout` sur l'hôte (sans lui, au bout de `mon_osd_down_out_interval` les OSD seraient sortis et Ceph recopierait des données inutilement), puis arrête les démons. Au retour, les PG rattrapent les écritures manquées (*recovery*) : c'est la pointe de latence que la sonde voit, sans erreur.

**Alternatives**
- `ceph osd set noout` global + arrêt manuel : même effet, moins de garde-fous.
- Remplacer les hôtes (VM neuve, nouvel hôte ajouté, ancien retiré par l'orchestrateur) : immuable, mais déplace des données (durée, charge).
- Mise à jour du seul noyau avec *live patching* : hors périmètre de Rocky sans abonnement.

**Pièges classiques**
- Deux hôtes à la fois (ou l'hôte suivant avant `HEALTH_OK`) : des PG passent sous `min_size`, les écritures se bloquent.
- Mettre à jour `cephadm`/`ceph-common` avec le système : versions désalignées des démons.
- Oublier de sortir de maintenance ou de retirer `noout` : le cluster reste « dégradé » sans le dire fort.
- Mettre l'hôte du mgr actif en maintenance sans basculer d'abord.

**En production chez MédiSphère**
Mise à jour mensuelle des hôtes en changement standard (minuterie qui ouvre la fiche courte, playbook, mesure automatique) ; noyau redémarré dans la même fenêtre ; supervision des latences des PVC pendant la *recovery*.

---

### F4-S08 — Monter OpenStack de 2026.1 à 2026.2

**Solution**

Fichiers : [CHG-3408](fichiers/S08/medisphere/docs/changements/fiches/CHG-3408-openstack-2026.2.md), [RB-344](fichiers/S08/medisphere/docs/changements/runbooks/RB-344-monter-openstack-de-serie.md), [`pyproject` (extrait)](fichiers/S08/openstack/pyproject.extrait-F4.toml), [`globals.yml` (extrait)](fichiers/S08/openstack/etc/kolla/globals.yml.extrait-F4), [`outils/fusionner-mots-de-passe.sh`](fichiers/S08/openstack/outils/fusionner-mots-de-passe.sh), [`pve01/profil-k8s.sh`](fichiers/S08/pve01/profil-k8s.sh), sondes ([groupes](fichiers/S08/ansible/inventories/lab/host_vars/mon01/supervision_temoin.yml.extrait-F4-S08), [module `http_2xx_clair`](fichiers/S08/ansible/roles/supervision_temoin/templates/blackbox-module-http-clair.extrait.yml)).

*Décider.* Kolla-Ansible 23.x **stable** sur PyPI ? Oui (23.0.0 listée par les notes de version de la série 2026.2) → `go` ; sinon `no-go` et la même procédure en **répétition** sur la rc, suivie d'un retour en 2026.1 par restauration.

*Préparer (sans rien interrompre).*

```
admin@adm01:~/src/openstack$ git worktree add ~/src/openstack-2026.2 -b serie-2026.2
admin@adm01:~/src/openstack-2026.2$ $EDITOR pyproject.toml           # kolla-ansible==23.x, ansible-core>=2.20,<2.22
admin@adm01:~/src/openstack-2026.2$ uv lock && uv sync --frozen && uv run kolla-ansible install-deps
admin@adm01:~/src/openstack-2026.2$ diff -u inventaire/multinode "$(uv run python -c 'import sys;print(sys.prefix)')/share/kolla-ansible/ansible/inventory/multinode"
admin@adm01:~/src/openstack-2026.2$ outils/fusionner-mots-de-passe.sh
clés ajoutées : …
admin@adm01:~/src/openstack-2026.2$ $EDITOR etc/kolla/globals.yml   # openstack_release: "2026.2" + notes de version
```

`fusionner-mots-de-passe.sh` applique la procédure officielle (`kolla-genpwd` sur l'exemple de la nouvelle version, `kolla-mergepwd --old … --new … --final …`) à un fichier chiffré : le clair n'existe que dans `/dev/shm` (700, effacé à la sortie), et le script **refuse** si une valeur existante a changé.

*Le jour J* (fiche, étapes 1 à 9) :

```
root@pve01:~# ./profil-k8s.sh arreter
root@pve01:~# for v in 2101 2102 2103; do qm start $v; done          # ou tofu apply de envs/openstack + outils/deployer.sh deploy
admin@adm01:~/src/openstack$ uv run kolla-ansible mariadb-backup -i inventaire/multinode --configdir etc/kolla --full
admin@adm01:~/src/openstack-2026.2$ uv run kolla-ansible pull -i inventaire/multinode --configdir etc/kolla
admin@adm01:~/src/openstack-2026.2$ uv run kolla-ansible prechecks -i inventaire/multinode --configdir etc/kolla
admin@adm01:~/src/openstack$ git switch main && git pull                 # après fusion de la MR serie-2026.2
admin@adm01:~/src/openstack$ uv sync --frozen && outils/deployer.sh upgrade
admin@adm01:~/src/observabilite$ outils/mesurer-interruption.sh <DÉBUT> <FIN> temoin 'continuite-openstack.*'
root@pve01:~# ./profil-k8s.sh demarrer
```

La sauvegarde de la base est envoyée sur PBS `par1/openstack` par le service du M10-E25 (`wb-backup-socle` élément `openstack`), puis vérifiée (`proxmox-backup-client snapshot list … --ns par1/openstack`). `deployer.sh` refuse tout autre état que `origin/main` au pipeline vert et pose l'étiquette `deploye-*`.

*Vérifier* : services de calcul, agents OVN, services Cinder, instance neuve avec volume, répartiteur OVN, Horizon ; images des conteneurs `…:2026.2-…` sur chaque nœud (`docker ps --format '{{.Image}}'`).

**Explications**
- `kolla-ansible upgrade` recrée chaque conteneur depuis la nouvelle image **et** lance les migrations de schéma de chaque service, dans l'ordre des dépendances : c'est ce qui le distingue de `deploy` (RB-101).
- La coupure du plan de données vient surtout des redémarrages d'OVS et des conteneurs OVN de la passerelle (`osctl01`, seule) et de `nova_libvirt` : avec un seul contrôleur réseau, l'objectif ne peut pas être zéro ; d'où 60 s.
- L'arbre de travail séparé garde l'environnement 2026.1 **exécutable** : le retour arrière (restauration de la base + `deploy-containers` avec les images 2026.1 encore présentes) n'attend pas une réinstallation de dépendances.
- Mesure par le témoin : le cluster est éteint ; `mesure-groupes` exclut les sondes des services arrêtés par la contrainte de mémoire.

**Alternatives**
- Réinstaller en 2026.2 et restaurer les données : plus long, plus risqué, perd l'historique des migrations.
- Montée service par service (`upgrade --tags`) : permise par Kolla, utile pour isoler un service problématique ; l'ordre devient ton problème.
- Construire les images 2026.2 soi-même ou les recopier dans Harbor (étiquettes immuables) : maîtrise de ce qui tourne.

**Pièges classiques**
- `uv add kolla-ansible==23…` dans l'environnement 2026.1 : plus de retour arrière rapide.
- ansible-core hors plage (trop récent ou trop ancien) : erreurs au chargement des collections.
- `kolla-mergepwd` sur un fichier chiffré, ou clair laissé dans `/tmp`.
- `--limit` « pour aller plus vite ».
- `prune-images` avant la clôture.
- Oublier de redémarrer `k8s-par1` après la fenêtre (ou le redémarrer avant que `ceph-par1` soit en `HEALTH_OK`).

**En production chez MédiSphère**
Trois contrôleurs (plan de contrôle et passerelles réseau redondants), une recette Kolla qui reçoit la série une semaine avant, images recopiées dans Harbor ; la montée de série devient un changement normal semestriel, préparé dès la publication de la stable.
