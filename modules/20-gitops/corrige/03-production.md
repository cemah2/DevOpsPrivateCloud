# Module 20 — Palier 3 : Production — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Validé hors lab pendant la rédaction** (Argo CD 3.5.5, chart `argo/argo-cd` 10.10.5, Helm 4.3.1, Helmfile 1.8.2, Kustomize 5.8.2, kubeconform 0.7.0) :
- rendu complet de la release `argocd` par `helmfile template` avec les valeurs de M20-E02 et celles de ce palier (`values-rbac.yaml`, `values-durcissement.yaml`, `values-ha.yaml`) : `argocd-rbac-cm` (politique injectée par `readFile`), `argocd-cm`, réplicas, `ARGOCD_CONTROLLER_REPLICAS`, `ARGOCD_API_SERVER_REPLICAS`, PDB, images par empreinte, disparition des NetworkPolicy du chart, `webhook.gitlab.secret` en référence ;
- la politique `policy.csv` et les 28 cas de `rbac-tests.txt` avec la CLI `argocd` 3.5.5 (`outils/argocd-rbac-tests.sh` : 28/28 ; politique cassée : écart détecté) ;
- les manifestes (`kustomize build`, `kubeconform -strict`, schémas Kubernetes 1.36 et CRD du catalogue datreeio) : `agence/` de `formation/gitops-labo`, `composants/argocd-sauvegarde/`, overlay `recette` de MédiDoc ;
- les checks du palier, joués contre des doublures (fixtures) dans les deux sens : vert sur l'état attendu, rouge sur un état fautif ;
- `shellcheck -x` et `bash -n` de tous les scripts.

**Points non testés en conditions réelles** (signale tes retours, ils corrigent le workbook) :
- politiques Cilium de l'espace `argocd` : port 6443 de l'entité `kube-apiserver` après traduction du Service `kubernetes.default` (Cilium 1.20 sans kube-proxy), et besoin réel de chaque flux (vérifie avec `hubble observe -n argocd --verdict DROPPED` ; le *repo-server* ne parle pas à l'API dans nos relevés de code, à confirmer) ;
- prise en compte à chaud de `server.secretkey` restauré (le runbook redémarre le serveur par prudence) ; conservation des clés posées par Argo CD dans `argocd-secret` quand le chart y écrit `webhook.gitlab.secret` (Helm 4 en *server-side apply* : elles appartiennent à un autre gestionnaire et doivent rester ; contrôle demandé avant/après) ;
- `argocd admin export` avec la configuration du pod (repli sur la configuration *in-cluster* de client-go) et chiffrement par `gpg --recipient-file` dans l'image d'Argo CD ; `rclone` 1.75 avec SeaweedFS (fournisseur `Other`, `--ca-cert` par `RCLONE_CA_CERT`) ;
- comportement du contrôleur avec `resource.respectRBAC: normal` sur un cluster en mode « espaces » (droits minimaux exacts du compte `argocd-gestion` : le Role proposé couvre une application simple ; un type de plus dans Git = une règle de plus) ; textes exacts des refus de l'essai `kube-system` ;
- retrait d'entrées de `metadata.managedFields` par un patch JSON (`outils/nettoyer-gestionnaires.sh`) : accepté par l'API d'après la documentation *Server-Side Apply* (champ modifiable par *update* ou *patch*), essai côté serveur obligatoire avant ;
- noms des jobs du composant `deploiement` du M19 et de ses `inputs` (le check de E30 cherche des mots-clés : `valid`, `kubeconform`, `kustomize`, `verif`, `signature`) ;
- format exact de la sortie de `argocd admin cluster stats` et des textes de condition des fenêtres de synchronisation.

**Faits partagés avec les autres paliers** : comptes locaux d'Argo CD sans point (`karim-benali`, `julien-petit`, `nadia-roussel`, `<MOI-ARGO>` = `<MOI>` avec des tirets) ; valeurs de la release dans `composants/argocd/` (M20-E02) ; politique et tests RBAC dans `releases/argocd/` ; `role:lecture` = `role:readonly` **sans** `logs` (ce que lit `ci-lecture`) ; ApplicationSet `labo-agences` ; Secret de cluster `cluster-lyo-k3s01` ; RB-201 ; ADR-0200.

**Rappel** : une seule VM dans ce palier, `lyo-k3s01` (2201). Fichiers de solution : `corrige/fichiers/M20-E24/` à `M20-E31/`, `M20-E33/`, `M20-E34/`.

---

### M20-E24 — RBAC d'Argo CD et projets par équipe

**Solution**

Fichiers (`plateforme/k8s`) : [politique](fichiers/M20-E24/k8s/releases/argocd/policy.csv), [tests](fichiers/M20-E24/k8s/releases/argocd/rbac-tests.txt), [script des tests](fichiers/M20-E24/k8s/outils/argocd-rbac-tests.sh), [`values-rbac.yaml`](fichiers/M20-E24/k8s/composants/argocd/values-rbac.yaml), [ajouts à la release](fichiers/M20-E24/k8s/releases/argocd.yaml.gotmpl.extrait), [job de pipeline](fichiers/M20-E24/k8s/gitlab-ci.extrait-E24.yml) ; `plateforme/gitops` : rôles de projet [`mediagenda`](fichiers/M20-E24/gitops/projets/mediagenda.extrait-E24.yaml), [`medidoc`](fichiers/M20-E24/gitops/projets/medidoc.extrait-E24.yaml) ; documentation : [`rbac.md`](fichiers/M20-E24/medisphere/docs/livraison/gitops/rbac.md) (réponses de l'étape 1, matrice).

*1. Lecture* — réponses dans `rbac.md`. L'essentiel : `role:readonly` lit **tout**, y compris les journaux des pods (`logs, get, */*`) ; un `policy.default` non vide donne à tout compte authentifié des droits qu'aucun `deny` ne peut retirer (la documentation le dit en avertissement) ; depuis 3.0, `update`/`delete` sur une Application ne portent plus sur ses ressources (`update/*`, `delete/*` pour cela) ; `override` permet de synchroniser des manifestes locaux, et une autre révision avec `requireOverridePrivilegeForRevisionSync` (posé en E25).

*3. Politique* : trois rôles (fichier commenté). Le branchement se fait **dans le fichier de releases**, à côté de la racine de confiance de M20-E02 :

```
          rbac:
            policy.csv: |
              {{- readFile "argocd/policy.csv" | nindent 14 }}
```

`readFile` est relatif au dossier `releases/` (comme `../composants/argocd/medisphere-root-ca.crt` de M20-E02) ; `nindent 14` place le contenu plus à droite que la clé. Vérification du rendu avant tout :

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd template | yq 'select(.kind == "ConfigMap" and .metadata.name == "argocd-rbac-cm")'
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff
```

*4. Tests* :

```
admin@adm01:~/src/k8s$ outils/argocd-rbac-tests.sh
ok    oui <MOI-ARGO> sync applications mediagenda/mediagenda-prod
ok    oui karim-benali update projects mediagenda
…
ok    non inconnu get projects mediagenda
Cas joués : 28 ; écarts ou erreurs : 0
```

Les deux cassures demandées : (a) `sync, mediagenda/*` à la place de `mediagenda/mediagenda-dev` → **aucun** test ne bouge, parce que le `deny` explicite sur la production tient ; (b) même chose **et** suppression du `deny` → `ÉCART attendu non, obtenu oui : julien-petit sync applications mediagenda/mediagenda-prod`, sortie en 1. C'est la démonstration du rôle de chaque couche : les tests décrivent ce qui doit être vrai, les `deny` rendent la politique robuste à l'`allow` trop large de demain.

Deux comportements de la CLI, relevés avec la 3.5.5, qui expliquent le script : `argocd admin settings rbac can` construit un client Kubernetes même avec `--policy-file` (sans kubeconfig : `invalid configuration` ; avec un kubeconfig sans identifiants : il **demande un nom d'utilisateur au terminal** — d'où le kubeconfig factice muni d'un jeton) ; elle sort en 1 pour « No » comme pour une erreur (`'synk' is not a valid action`) : on lit la sortie standard, et l'avertissement de chargement `user defined roles not found in policies: role:admin,role:plateforme-admin` (un rôle qui n'a que des héritages) part sur la sortie d'erreur.

*5. Pipeline* : job `argocd-rbac` (image d'Argo CD de la version déployée, par le cache `quay`, `entrypoint: [""]`), règles : MR qui touche `releases/argocd/`, la release ou le script, et toujours sur `main`. La MR avec la variante (b) échoue au job ; fermée.

*6. Rôles de projet* : rôle `equipe` dans `mediagenda` et `medidoc`, lié aux groupes SSO (`medisphere:mediagenda-devs`, `medisphere:medidoc-devs`), mêmes droits que le rôle global ; inerte jusqu'au M24.

*7. Application* :

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply
admin@adm01:~$ argocd login argocd.apps.par1.medisphere.internal --grpc-web --username julien-petit
admin@adm01:~$ argocd account can-i sync applications mediagenda/mediagenda-prod
no
admin@adm01:~$ argocd app sync mediagenda-prod
FATA[0000] rpc error: code = PermissionDenied desc = permission denied: applications, sync, mediagenda/mediagenda-prod, sub: julien-petit, …
admin@adm01:~$ argocd app sync mediagenda-recette          # accepté
admin@adm01:~$ curl -s -K <(printf 'header = "Authorization: Bearer %s"\n' "$(cat ~/.config/workbook/argocd-checks.token)") \
>   https://argocd.apps.par1.medisphere.internal/api/v1/account/can-i/applications/sync/mediagenda/mediagenda-prod
{"value":"no"}
```

Dans l'interface, `julien-petit` voit les trois Applications de `mediagenda` et seulement elles ; le bouton *Sync* de la production renvoie le refus ci-dessus ; les actions du Rollout de recette (*Promote-Full*, *Abort*) sont proposées.

**Explications**

Argo CD évalue d'abord `policy.default`, puis les politiques du sujet et de ses groupes (Casbin, correspondance par motifs `glob` où `/` n'est pas un séparateur). Le modèle retenu : un rôle par **fonction** (administration, équipe, lecture), des comptes affectés par `g`, aucun droit par défaut. Le rôle de lecture n'hérite **pas** de `role:readonly` parce que celui-ci donne les journaux des pods : sur une plateforme de santé, ils peuvent contenir des données personnelles, et ils se liront dans Loki (M22) avec des droits par locataire. Le compte `admin` reste lié à `role:admin` par la politique intégrée : c'est `admin.enabled: "false"` (M20-E03) qui le neutralise. Les rôles de projet portent la délégation par équipe et sont prêts pour le SSO ; on n'y affecte pas de compte local (un groupe SSO de même nom recevrait les mêmes droits, avertissement de la documentation).

**Alternatives**
- `policy.default: role:readonly` et des `deny` : refusé, un `deny` ne peut pas restreindre le rôle par défaut.
- Politiques directement sur les comptes (`p, julien-petit, …`), recommandé par la documentation quand SSO et comptes locaux coexistent : plus de lignes, mais aucune ambiguïté de nom ; à envisager au M24.
- Politique dans plusieurs clés `policy.<nom>.csv` (une par équipe) : utile si chaque équipe propose sa part par MR ; ici un seul fichier relu par la plateforme.
- `policy.matchMode: regex` : plus expressif (`mediagenda/mediagenda-(dev|recette)`), plus facile à rater (le `.` et les ancres).

**Pièges classiques**
- Croire que `role:readonly` est « sans risque » (journaux des pods).
- Un nom de compte local avec un point (`accounts.julien.petit`) : Argo CD comprend le compte `julien` et un suffixe `petit` inconnu.
- Tester la politique **après** l'avoir appliquée ; ou tester avec `--use-builtin-policy=false` (le serveur, lui, charge la politique intégrée).
- Lire le code de retour de `rbac can` au lieu de sa sortie.
- Indentation de `readFile` : une politique tronquée ou collée à la clé suivante passe le rendu YAML mais pas la validation ; le job de tests l'attrape.
- Oublier `ci-lecture` : les checks du module lisent les clusters et les projets avec son jeton.

**En production chez MédiSphère**
SSO Keycloak (M24) avec des groupes, plus de comptes locaux humains ; jetons de rôle de projet pour les automatisations limitées à un projet ; revue trimestrielle des affectations ; journalisation des refus (`security` des journaux du serveur) remontée dans Loki ; tests RBAC exécutés aussi après chaque montée de version d'Argo CD (changement de sémantique comme en 3.0).

---

### M20-E25 — Durcir Argo CD

**Solution**

Fichiers : [`values-durcissement.yaml`](fichiers/M20-E25/k8s/composants/argocd/values-durcissement.yaml), [exclusions complétées dans `values.yaml`](fichiers/M20-E25/k8s/composants/argocd/values.extrait-E25.yaml), [politiques réseau](fichiers/M20-E25/k8s/composants/reseau/politiques/argocd.yaml), [section Argo CD de la matrice des flux du cluster](fichiers/M20-E25/medisphere/docs/kubernetes/reseau/matrice-flux-cluster.extrait-E25.md), [`durcissement-argocd.md`](fichiers/M20-E25/medisphere/docs/livraison/gitops/durcissement-argocd.md).

*1. Matrice* : lue dans le rendu (ports déclarés, NetworkPolicy du chart qui disent qui parle à Redis et au *repo-server*), confirmée par Hubble :

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd template | yq 'select(.kind == "NetworkPolicy") | .metadata.name + " ← " + ([.spec.ingress[].from[]?.podSelector.matchLabels["app.kubernetes.io/name"]] | join(","))'
admin@adm01:~$ hubble observe -n argocd --since 5m -o compact | awk '{print $2, $3, $4}' | sort | uniq -c | sort -rn | head -30
```

Le chart ne filtre que l'entrée, et laisse **tout** entrer sur `argocd-server` (`ingress: - {}`) ; ses politiques et les nôtres se combineraient par union (la plus large gagne) : d'où `global.networkPolicy.create: false` et une seule source.

*2. Politiques* : application composant par composant, dans l'ordre Redis → *repo-server* → contrôleur → serveur → ApplicationSets → notifications → crochet, puis le refus par défaut **en dernier** (tant qu'il n'est pas posé, un composant sans politique reste ouvert ; une fois posé, tout ce qui n'est pas décrit tombe) :

```
admin@adm01:~/src/k8s$ kubectl --context k8s-par1 apply --server-side --field-manager=plateforme-k8s -f composants/reseau/politiques/argocd.yaml
admin@adm01:~$ hubble observe -n argocd --verdict DROPPED -f       # autre terminal, pendant :
admin@adm01:~$ argocd app get mediagenda-dev --hard-refresh && argocd app sync labo
admin@adm01:~$ kubectl -n argocd exec deploy/argocd-repo-server -- git ls-remote https://github.com/argoproj/argo-cd
fatal: unable to access 'https://github.com/argoproj/argo-cd/': Failed to connect to github.com port 443 … Connection timed out
admin@adm01:~$ hubble observe -n argocd --verdict DROPPED --to-fqdn github.com
… argocd/argocd-repo-server-… -> github.com:443 Policy denied DROPPED (TCP Flags: SYN)
```

Le même `git ls-remote` vers `https://git01.par1.medisphere.internal/formation/gitops-labo.git` aboutit (demande d'identifiants : le flux passe ; le *repo-server* reçoit ses identifiants du contrôleur à chaque requête, pas d'une configuration Git locale). Pas de pod de test portant les étiquettes du *repo-server* : il entrerait dans son Service et recevrait des requêtes du contrôleur.

*3. Interface et API* : `values-durcissement.yaml`. Les capacités : humains `login`, `ci-lecture` `apiKey`. Retirer `apiKey` empêche d'en générer de nouveaux ; les jetons existants d'un compte sont listés dans `argocd-secret` (`accounts.<nom>.tokens`) et se suppriment explicitement :

```
admin@adm01:~$ argocd account get --account julien-petit
admin@adm01:~$ argocd account delete-token --account julien-petit <ID>
```

*4. Applications ailleurs* : `argocd-cmd-params-cm` n'a ni `application.namespaces` ni `applicationsetcontroller.namespaces`, aucun AppProject n'a `sourceNamespaces` (`kubectl get appproj -n argocd -o jsonpath='{..sourceNamespaces}'` vide). Justification dans `durcissement-argocd.md` (mesure 7).

*5. Exclusions* : la liste de M20-E12 est **complétée dans `values.yaml`** (trois types de demandes de Velero) — la redéfinir dans `values-durcissement.yaml` aurait **remplacé** celle d'E12 (Helm fusionne les objets, remplace les listes). Mesure : page *Settings → Clusters → in-cluster* (ressources surveillées), avant/après.

*6. Images* : `global.image.tag: "v3.5.5@sha256:13db…"`, `redis.image.tag: "8.6.4-alpine@sha256:2cc0…"` ; le chart compose `dépôt:étiquette`, ce qui donne bien `…/argocd:v3.5.5@sha256:…`. Relevé des empreintes et vérification :

```
admin@adm01:~$ skopeo inspect --format '{{.Digest}}' docker://quay.io/argoproj/argocd:v3.5.5     # index multi-architecture
admin@adm01:~$ kubectl -n argocd get pods -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' | sort -u
```

*7. Trace* : tableau de `durcissement-argocd.md`. Les événements Kubernetes vivent **1 h** (`--event-ttl` du serveur d'API) : seuls, ils ne prouvent rien la semaine suivante ; `status.history` garde 10 synchronisations ; Git garde tout mais pas l'heure d'application. Le M22 collecte événements et journaux dans Loki.

**Explications**

Le durcissement suit la même logique que pour un serveur : réduire ce qui est joignable (réseau), ce qui est faisable (interface, capacités, `override`), ce qui tourne (empreintes), et rendre visible ce qui se passe. Le *repo-server* est le composant le plus exposé : il exécute `helm` et `kustomize` sur le contenu de dépôts (un dépôt malveillant peut tenter de faire sortir des données) ; le priver d'Internet ferme cette porte. Le contrôleur, lui, reste puissant (droits d'écriture sur tout le cluster) : c'est la limite assumée, listée comme « ouverte ».

**Alternatives**
- Politiques par CIDR (`toCIDR: 10.10.20.12/32`) plutôt que par nom : pas de dépendance au proxy DNS, mais une adresse à maintenir ; le M15 a choisi les noms.
- NetworkPolicy standard au lieu de Cilium : possible pour les flux internes, impossible pour les noms (`toFQDNs`) et l'entité `ingress`.
- Kyverno ou une ValidatingAdmissionPolicy pour imposer les empreintes dans l'espace : plus général, à venir au M26.
- *Sync impersonation* : chaque projet synchronise avec son propre compte de service ; alpha en 3.5.

**Pièges classiques**
- Oublier le crochet `argocd-redis-secret-init` : tout marche aujourd'hui, la **prochaine** `helmfile apply` échoue.
- Poser le refus par défaut avant les autorisations : Applications en `Unknown` le temps de corriger.
- Garder les NetworkPolicy du chart « en plus » : celle du serveur laisse tout entrer.
- Redéfinir `resource.exclusions` (perte des exclusions par défaut) ou `resourceExclusionsAdditional` dans un second fichier (perte de celles d'E12).
- Une empreinte d'**image de plateforme** (une architecture) au lieu de celle de l'index : fonctionne sur amd64, échoue ailleurs ; et à la montée de version, oublier de changer l'empreinte avec la version du chart.

**En production chez MédiSphère**
TLS de bout en bout jusqu'au serveur ; métriques ouvertes à Prometheus seulement (M21) ; alerte sur les refus Hubble de l'espace `argocd` ; empreintes mises à jour par Renovate (M13) avec la version du chart ; revue du durcissement à chaque mineure d'Argo CD (le guide de montée liste les changements de défauts).

---

### M20-E26 — Multi-cluster : le cluster de l'agence LYO1

**Solution**

Fichiers : [VM](fichiers/M20-E26/infra/envs/m20/terraform.tfvars.exemple) (groupe `lyo` du catalogue `hotes.tf` d'E23 : aucune nouvelle déclaration) ; Ansible : [`host_vars`](fichiers/M20-E26/ansible/inventories/lab/host_vars/lyo-k3s01/k3s.yml), [jeton k3s (modèle de Vault)](fichiers/M20-E26/ansible/inventories/lab/group_vars/role_k3s/vault-lab.extrait-E26.yml.exemple), [playbook](fichiers/M20-E26/ansible/playbooks/m20-lyo.yml), [manifestes de gestion](fichiers/M20-E26/ansible/playbooks/files/m20-lyo/argocd-gestion.yaml), [pare-feu](fichiers/M20-E26/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait) ; `plateforme/k8s` : [`values-multicluster.yaml`](fichiers/M20-E26/k8s/composants/argocd/values-multicluster.yaml), [Secret de cluster](fichiers/M20-E26/k8s/outils/secrets-k8s.d/argocd.sh) (module `argocd` d'E06 complété : `secret_cluster_lyo_k3s01`, `verifier_cluster_lyo_k3s01`), [Vault](fichiers/M20-E26/k8s/secrets/argocd.extrait-E26.yml.exemple), sortie du contrôleur dans [`argocd.yaml`](fichiers/M20-E25/k8s/composants/reseau/politiques/argocd.yaml) (règle `lyo-k3s01`) ; `plateforme/gitops` : [ApplicationSet `labo-agences`](fichiers/M20-E26/gitops/applications/labo-agences.yaml), [AppProject `labo`](fichiers/M20-E26/gitops/projets/labo.extrait-E26.yaml) ; `formation/gitops-labo` : [`agence/`](fichiers/M20-E26/gitops-labo/agence/) ; documentation : [`multi-cluster.md`](fichiers/M20-E26/medisphere/docs/livraison/gitops/multi-cluster.md), [matrice des flux](fichiers/M20-E26/medisphere/docs/socle/matrice-flux.extrait-E26.md).

*1. La VM* :

```
admin@adm01:~/src/infra/envs/m20$ tofu plan -out m20.plan        # groupes = ["lyo"] : + module.hote["lyo-k3s01"], + module.dns_hote["lyo-k3s01"]
admin@adm01:~/src/infra/envs/m20$ tofu apply m20.plan
admin@adm01:~/src/ansible$ uv run ansible-inventory --host lyo-k3s01 | jq '.group_names? // empty'   # role_k3s (étiquette role-k3s)
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/m20-lyo.yml
admin@adm01:~$ install -d -m 700 ~/.config/workbook/m20
admin@adm01:~$ ssh lyo-k3s01 sudo cat /etc/rancher/k3s/k3s.yaml | sed 's#https://127.0.0.1:6443#https://lyo-k3s01.par1.medisphere.internal:6443#' \
>   > ~/.config/workbook/m20/lyo-k3s01.kubeconfig && chmod 600 ~/.config/workbook/m20/lyo-k3s01.kubeconfig
admin@adm01:~$ kubectl --kubeconfig ~/.config/workbook/m20/lyo-k3s01.kubeconfig get nodes -o wide
NAME        STATUS   …   VERSION        INTERNAL-IP
lyo-k3s01   Ready    …   v1.36.5+k3s1   10.10.99.61
```

(Le kubeconfig de k3s est **administrateur** du cluster : il reste sur `adm01`, en 600, pour l'exploitation de la plateforme ; Argo CD n'en a pas besoin.)

*2. Compte de gestion* : manifestes déposés dans `/var/lib/rancher/k3s/server/manifests/` par le playbook (k3s les applique et les réapplique s'ils changent). Vérification :

```
admin@adm01:~$ K="kubectl --kubeconfig ~/.config/workbook/m20/lyo-k3s01.kubeconfig"
admin@adm01:~$ $K auth can-i --list --as system:serviceaccount:agence:argocd-gestion -n agence
admin@adm01:~$ $K auth can-i create deployments -n kube-system --as system:serviceaccount:agence:argocd-gestion
no
admin@adm01:~$ $K auth can-i list namespaces --as system:serviceaccount:agence:argocd-gestion
no
```

*3. Lecture* : réponses dans `multi-cluster.md` (champs, `namespaces`, `clusterResources`, `caData`, état `Unknown` sans application).

*4. Flux* : règle `K8S_TRAV` → `LYO_K3S01:6443` sur `gw01` puis `gw02` ; sortie `toFQDNs lyo-k3s01.par1.medisphere.internal:6443` dans la politique du contrôleur. Avec Hubble : `hubble observe -n argocd --to-fqdn lyo-k3s01.par1.medisphere.internal` montre `FORWARDED` depuis le contrôleur seulement.

*5. Secret de cluster* :

```
admin@adm01:~$ $K -n agence get secret argocd-gestion-jeton -o jsonpath='{.data.token}' | base64 -d > /dev/shm/jeton && chmod 600 /dev/shm/jeton
admin@adm01:~$ $K -n agence get secret argocd-gestion-jeton -o jsonpath='{.data.ca\.crt}' | base64 -d > /dev/shm/ca.crt
admin@adm01:~/src/ansible$ uv run ansible-vault edit --vault-id critique@outils/vault-pass-client.sh ~/src/k8s/secrets/argocd.yml   # coller jeton et CA, puis :
admin@adm01:~$ shred -u /dev/shm/jeton /dev/shm/ca.crt
admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer argocd
[OK] argocd/cluster-lyo-k3s01 à jour (https://lyo-k3s01.par1.medisphere.internal:6443, espace agence)
admin@adm01:~$ argocd cluster list
SERVER                                           NAME        VERSION  STATUS   MESSAGE                                                  PROJECT
https://lyo-k3s01.par1.medisphere.internal:6443  lyo-k3s01            Unknown  Cluster has no applications and is not being monitored.
https://kubernetes.default.svc                   in-cluster  1.36     Successful
```

Avant d'appliquer, ajoute `values-multicluster.yaml` à la release (`resource.respectRBAC: normal`) et `helmfile apply` : sans lui, le cache du cluster distant échoue sur le premier type que le compte n'a pas le droit de lister (`Secrets`, `Roles`…).

*6. Projet et ApplicationSet* : MR sur `plateforme/gitops` (projet + `applications/labo-agences.yaml`) et sur `formation/gitops-labo` (`agence/`). Après fusion, la racine crée l'ApplicationSet, qui génère `labo-lyo-k3s01` :

```
admin@adm01:~$ argocd app get labo-lyo-k3s01
Name:               argocd/labo-lyo-k3s01
Project:            labo
Server:             https://lyo-k3s01.par1.medisphere.internal:6443
Namespace:          agence
…
Sync Status:        Synced to main (…)
Health Status:      Healthy
admin@adm01:~$ argocd cluster list | grep lyo         # … Successful
```

*7. Preuves* : `$K -n agence delete deployment labo` → recréé en moins d'une minute (`selfHeal`). Essai `kube-system` : l'AppProject refuse d'abord (destination non autorisée) ; dans un projet d'essai qui l'autoriserait, Argo CD refuse encore (espace non géré, `namespaces: agence`), et en dernier ressort l'API de k3s (aucun droit). Deux niveaux sous le contrôle de la plateforme, un niveau sous le contrôle du cluster distant.

**Explications**

Argo CD gère un cluster distant avec ses propres identifiants : un Secret étiqueté `argocd.argoproj.io/secret-type: cluster`, dont `config` contient un jeton et l'autorité du serveur d'API. `argocd cluster add` crée dans le cluster cible un compte **cluster-admin** (`argocd-manager`) : pratique, refusé ici. Avec un compte limité à un Role, il faut dire au contrôleur où regarder (`namespaces`) et ce qu'il ne gère pas (`clusterResources: "false"`), et lui permettre d'ignorer les types qu'on lui refuse (`resource.respectRBAC`). Le générateur `clusters` d'un ApplicationSet transforme chaque Secret de cluster correspondant au sélecteur en une Application : ajouter une agence devient « ajouter un Secret ». La politique `create-update` et `preserveResourcesOnDeletion` évitent qu'un Secret de cluster supprimé par erreur fasse supprimer les charges de l'agence.

**Alternatives**
- Un Argo CD par site (« hub and spoke » inversé) : autonomie de l'agence si la liaison tombe, une instance de plus à exploiter.
- Le mode agent d'Argo CD (*argocd-agent*, principal/agent) : le cluster distant tire sa configuration ; adapté quand PAR1 ne peut pas joindre l'agence. Hors périmètre.
- Flux à l'agence, piloté depuis le même dépôt : cohérent avec l'ADR si l'agence devient autonome.
- Compte de service par projet (`project` du Secret de cluster) : un cluster réservé à un projet.

**Pièges classiques**
- `insecure: true` « pour voir » : le jeton part chez quiconque répond à cette adresse.
- `caData` avec un chemin ou un PEM non encodé en base64.
- `server` avec l'adresse IP alors que le certificat ne porte que le nom (ou l'inverse) : `tls-san` doit contenir ce qu'on utilise.
- Oublier `namespaces` avec un compte limité : état `Failed` du cluster, messages `forbidden` en boucle dans les journaux du contrôleur.
- Oublier la sortie dans la politique du contrôleur (E25) : `Unknown`, délai dépassé.
- Prendre `Unknown` (aucune application) pour une panne.

**En production chez MédiSphère**
Liaison chiffrée vers l'agence (le tunnel `wg2` du M07 pour un vrai site), rotation trimestrielle du jeton (ou identité courte par OIDC du cluster distant), supervision de l'état des clusters (`argocd_cluster_connection_status`, M21), et une fenêtre de synchronisation propre à l'agence (horaires d'ouverture).

---

### M20-E27 — Haute disponibilité et performance d'Argo CD

**Solution**

Fichiers : [`values-ha.yaml`](fichiers/M20-E27/k8s/composants/argocd/values-ha.yaml), [script des webhooks](fichiers/M20-E27/k8s/outils/argocd-webhooks-gitlab.sh), [Secret du webhook et partition du cluster](fichiers/M20-E27/k8s/outils/secrets-k8s.d/argocd.sh), [Vault](fichiers/M20-E27/k8s/secrets/argocd.extrait-E27.yml.exemple), [pare-feu](fichiers/M20-E27/ansible/inventories/lab/group_vars/role_routeur/pare_feu.yml.extrait), [matrice des flux](fichiers/M20-E27/medisphere/docs/socle/matrice-flux.extrait-E27.md), [`performance.md`](fichiers/M20-E27/medisphere/docs/livraison/gitops/performance.md). Le Secret de cluster de `lyo-k3s01` reçoit `shard=1` (déjà dans la fonction d'E26).

*1. Mesure de départ* : pour chaque essai, une MR qui change une annotation de `overlays/dev` (sans quoi Argo CD rafraîchit mais n'a rien à synchroniser), puis, **au moment de la fusion** :

```
admin@adm01:~$ t0=$(date +%s)
admin@adm01:~$ until debut="$(kubectl -n argocd get applications.argoproj.io mediagenda-dev -o jsonpath='{.status.operationState.startedAt}')" \
>   && [ -n "$debut" ] && [ "$(date -d "$debut" +%s)" -ge "$t0" ]; do sleep 2; done; echo "délai : $(( $(date -d "$debut" +%s) - t0 )) s"
```

Valeurs attendues : de quelques secondes à environ 3 min (`120 s` + jusqu'à `60 s` de gigue), médiane autour de 1 min 30 à 2 min.

*2. Lecture* : partitionnement **par cluster** ; deux clusters → au plus deux partitions utiles ; un réplica perdu → ses clusters attendent le redémarrage du pod (le StatefulSet le recrée avec le même nom, donc la même partition) ; `ARGOCD_API_SERVER_REPLICAS` divise la limite de connexions simultanées ; Redis n'est qu'un cache.

*3. Réplicas et PDB* : `values-ha.yaml`, puis :

```
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd diff | grep -E '^\+.*(replicas|REPLICAS|PodDisruptionBudget)'
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply
admin@adm01:~$ kubectl -n argocd get pods -o wide -l 'app.kubernetes.io/name in (argocd-server,argocd-repo-server)'
admin@adm01:~$ argocd admin cluster stats --namespace argocd        # partition de chaque cluster
```

*4. Panne* : pendant le drainage de `k8s-w02`, la boucle `argocd app list` (via la Gateway) n'échoue pas (deux réplicas du serveur, PDB) ; une MR fusionnée pendant ce temps est synchronisée si la partition de `in-cluster` (0) n'était pas sur `k8s-w02`, sinon après le redémarrage du pod du contrôleur sur `k8s-w01` (quelques dizaines de secondes). Note la partition touchée dans `performance.md`.

*5. Webhooks* :

```
admin@adm01:~$ openssl rand -hex 32 > ~/.config/workbook/argocd-webhook-gitlab.secret && chmod 600 ~/.config/workbook/argocd-webhook-gitlab.secret
admin@adm01:~/src/ansible$ uv run ansible-vault edit … ~/src/k8s/secrets/argocd.yml        # argocd_webhook_gitlab_secret : la même valeur
admin@adm01:~/src/k8s$ outils/secrets-k8s.sh appliquer argocd                                 # Secret argocd-webhook-gitlab
admin@adm01:~/src/k8s$ helmfile -e par1 -l composant=argocd apply                              # webhook.gitlab.secret = $argocd-webhook-gitlab:secret
admin@adm01:~$ kubectl -n argocd get secret argocd-secret -o json | jq -r '.data | keys[]'      # server.secretkey et accounts.* toujours là
```

GitLab (*Admin → Paramètres → Réseau → Requêtes sortantes*) : « Autoriser les requêtes vers le réseau local depuis les webhooks » **décoché**, liste d'autorisation : `argocd.apps.par1.medisphere.internal` et `10.10.41.10`. Règle de bordure `git01` → `GW_PAR1:443`. Puis :

```
admin@adm01:~/src/k8s$ outils/argocd-webhooks-gitlab.sh
[OK] plateforme/gitops : webhook 31 créé
[OK] mediagenda/deploiement : webhook 32 créé
…
```

Test : *Paramètres → Webhooks → Tester → Push events* → `200` ; dans Argo CD, le rafraîchissement suit en quelques secondes (journaux du serveur : `Received push event repo: https://git01.par1.medisphere.internal/mediagenda/deploiement` ; texte à relever). En cas d'échec, le détail de l'événement dans GitLab donne la cause (voir l'indice 2 de l'énoncé).

*6. Réconciliation* : `timeout.reconciliation: 300s`, gigue `60s` (le chart met une somme de contrôle de `argocd-cm` dans les pods : ils redémarrent seuls). Seconde série de mesures : quelques secondes. Ce que le webhook ne signale pas est vu au plus tard en 6 min.

**Explications**

Argo CD est presque sans état : tout est dans les objets Kubernetes. Le serveur et le *repo-server* se multiplient sans précaution ; le contrôleur se **partitionne** par cluster et ne se répartit donc pas sur un seul gros cluster ; le contrôleur d'ApplicationSets élit un meneur. Les webhooks remplacent l'attente de l'interrogation par une notification ; ils ne suppriment pas l'interrogation, qui reste le filet de sécurité. La référence `$argocd-webhook-gitlab:secret` garde le secret hors des valeurs Helm et hors de Git, tout en le faisant revenir avec la release lors d'une reconstruction (E28).

**Alternatives**
- `redis-ha` : vraie HA du cache, au prix de six pods et d'une anti-affinité stricte sur trois nœuds.
- Distribution dynamique des clusters (`controller.dynamicClusterDistribution`, alpha) : reprise des clusters d'un réplica perdu par les autres.
- HPA du *repo-server* (`repoServer.autoscaling`) : utile avec beaucoup de dépôts et de rendus Helm.
- Webhook vers le contrôleur d'ApplicationSets (générateurs Git) : à publier à part, inutile avec nos générateurs de liste et de clusters.

**Pièges classiques**
- Changer `controller.replicas` sans `ARGOCD_CONTROLLER_REPLICAS` (installation à la main) : chaque réplica croit être seul et tous gèrent tout.
- Anti-affinité stricte avec deux nœuds éligibles : plus de place pendant un drainage.
- Webhook en HTTP ou avec la vérification TLS désactivée « parce que ça ne passait pas » : il faut ajouter la racine MédiSphère à GitLab, pas désactiver la vérification.
- « Autoriser les requêtes vers le réseau local » coché globalement : tout webhook d'un projet peut alors viser l'intérieur du lab (SSRF).
- `timeout.reconciliation: 0` (interrogation désactivée) : un webhook perdu = un changement jamais vu.

**En production chez MédiSphère**
Trois travailleurs généralistes et `redis-ha` ; alertes sur `argocd_app_reconcile` et la file du contrôleur (M21) ; webhook aussi depuis Harbor (OCI) le jour où un chart n'est plus épinglé ; tests de panne (perte d'un nœud) dans la recette trimestrielle.

---

### M20-E28 — Sauvegarder et reconstruire Argo CD

**Solution**

Fichiers : `plateforme/k8s` : [`composants/argocd-sauvegarde/`](fichiers/M20-E28/k8s/composants/argocd-sauvegarde/) (Kustomization, compte, CronJob, clé publique), [politique réseau](fichiers/M20-E28/k8s/composants/reseau/politiques/argocd-sauvegarde.yaml), [Taskfile](fichiers/M20-E28/k8s/Taskfile.extrait-E28.yml), [Secret S3](fichiers/M20-E28/k8s/outils/secrets-k8s.d/argocd.sh), [Vault](fichiers/M20-E28/k8s/secrets/argocd.extrait-E28.yml.exemple), [restauration d'`argocd-secret`](fichiers/M20-E28/k8s/outils/argocd-restaurer-secret.sh) ; stockage : [identité et compartiment](fichiers/M20-E28/ansible/inventories/lab/host_vars/s3-01/seaweedfs.yml.extrait), [politique](fichiers/M20-E28/infra/outils/s3/politique-argocd-sauvegardes.json), [cycle de vie](fichiers/M20-E28/infra/outils/s3/cycle-de-vie-argocd-sauvegardes.json), [`s3-argocd-sauvegardes.env`](fichiers/M20-E28/adm01/s3-argocd-sauvegardes.env.exemple) ; documentation : [RB-201](fichiers/M20-E28/medisphere/docs/livraison/gitops/runbooks/RB-201-reconstruire-argo-cd.md), [compte rendu](fichiers/M20-E28/medisphere/docs/livraison/gitops/tests/reconstruction-argo-cd.md).

*1. Inventaire* : RB-201 §2. Ce qui ne revient de nulle part sans l'export : `server.secretkey` et les comptes locaux (`accounts.<nom>.password`, `.passwordMtime`, `.tokens`). Si `server.secretkey` change, tous les jetons (dont `argocd-checks.token` de `ci-lecture`) sont refusés : ce sont des JWT signés par cette clé, et la liste `accounts.ci-lecture.tokens` doit en plus contenir leur identifiant.

*2. Sauvegarde* : clé GPG de sauvegarde créée sur `adm01` dans un `GNUPGHOME` en mémoire, clé privée exportée chiffrée en Vault `critique` (`secrets/argocd-sauvegarde-gpg.cle`) et sur papier, clé publique versionnée :

```
admin@adm01:~$ export GNUPGHOME=$(mktemp -d -p /dev/shm)
admin@adm01:~$ gpg --batch --passphrase '' --quick-generate-key 'Sauvegarde Argo CD <sauvegarde-argocd@medisphere.internal>' rsa4096 encr 3y
admin@adm01:~$ gpg --export --armor sauvegarde-argocd@medisphere.internal > ~/src/k8s/composants/argocd-sauvegarde/argocd-sauvegarde.pub.asc
admin@adm01:~$ gpg --export-secret-keys --armor sauvegarde-argocd@medisphere.internal \
>   | (cd ~/src/k8s && uv run --project ~/src/ansible ansible-vault encrypt --vault-id critique@$HOME/src/ansible/outils/vault-pass-client.sh --output secrets/argocd-sauvegarde-gpg.cle)
admin@adm01:~$ rm -rf "$GNUPGHOME"; unset GNUPGHOME
```

(Clé sans phrase de passe : elle est protégée par le Vault ; une phrase en plus serait une deuxième clé à garder. Choix à écrire dans le registre des secrets.) Identité S3 (rôle `seaweedfs`, puis politique et cycle de vie avec l'identité d'administration, méthode du M14-E24), Secret S3 par `secrets-k8s.sh`, puis :

```
admin@adm01:~/src/k8s$ task argocd-sauvegarde && task argocd-sauvegarde-maintenant
admin@adm01:~$ kubectl -n argocd logs job/argocd-export-manuel-… -c export
export chiffré : argocd-export-20261022T140512Z.yaml.gpg (38211 octets)
admin@adm01:~$ kubectl -n argocd logs job/argocd-export-manuel-… -c envoi
envoyé : argocd-sauvegardes/quotidien/argocd-export-20261022T140512Z.yaml.gpg (38211 octets)
```

Relecture : RB-201 §3.3 (téléchargement, déchiffrement en mémoire, `outils/argocd-restaurer-secret.sh` en essai qui liste les clés).

*3 à 6* : RB-201 §3 à §7, dans l'ordre, chronométrés dans le compte rendu. Points d'attention vécus :
- l'application racine porte (dans Git) le finaliseur et réconcilie ses enfants : si on retire les finaliseurs **avant** d'arrêter le contrôleur, `selfHeal` de la racine les remet ; d'où l'arrêt des contrôleurs en premier ;
- `kubectl delete applicationsets --cascade=orphan` : les Applications générées perdent leur propriétaire mais restent ; elles n'ont pas de finaliseur (`preserveResourcesOnDeletion: true`, E10) ;
- les AppProjects peuvent porter un finaliseur tant que des Applications les référencent : à retirer aussi ;
- les CRD d'Argo CD survivent à `helmfile destroy` (`helm.sh/resource-policy: keep`) ; on les supprime à la main, **sans** toucher à celles d'Argo Rollouts ;
- à la reconstruction, la racine recrée les Applications ; les objets portent déjà l'annotation `argocd.argoproj.io/tracking-id` avec le même nom d'Application : Argo CD les reconnaît, compare, trouve `Synced` ; aucun pod n'est recréé ;
- `argocd-secret` restauré **partiellement** : réappliquer tout l'export recréerait les Applications avant la racine (et des Secrets de dépôts peut-être plus anciens que le Vault).

Vérification finale : `lab/bin/check 20 28` ; comparaison des UID avant/après (aucune différence).

**Explications**

« Tout est dans Git » est vrai pour ce qu'Argo CD **applique**, pas pour Argo CD lui-même : sa configuration revient de Helmfile et du Vault, mais l'état propre à l'instance (clé de signature, mots de passe, liste des jetons) n'existe que dans `argocd-secret`. L'export comble ce trou ; il contient des secrets, d'où le chiffrement **asymétrique** (le cluster n'a que la clé publique : un cluster compromis ne peut pas relire les anciennes sauvegardes) et une identité S3 sans droit de suppression. Le danger de la désinstallation n'est pas Argo CD mais ses **finaliseurs** : la suppression en cascade est une fonction, pas une panne ; il faut la neutraliser explicitement, contrôleurs arrêtés.

**Alternatives**
- « Git suffit » : défendable si l'on accepte de redéfinir les mots de passe des comptes locaux et de régénérer les jetons (et donc de mettre à jour tout ce qui les utilise) ; deviendra presque vrai avec le SSO (M24), où il n'y a plus de mots de passe locaux.
- Velero sur l'espace `argocd` (CRD comprises) : restaure tout, y compris des objets périmés ; utile pour revenir à un instant précis, moins pour une reconstruction propre.
- Hashes `bcrypt` des comptes locaux dans le Vault (`argocd account bcrypt`) injectés par `secrets-k8s.sh` : supprime le besoin de l'export pour les mots de passe, mais pas pour `server.secretkey` (sauf à la gérer aussi par le Vault, ce qui rend la rotation manuelle).
- Export lancé depuis `adm01` par une minuterie (comme le M14-E26) : plus simple, mais dépend du poste d'administration et d'un jeton longue durée de plus.

**Pièges classiques**
- Supprimer l'espace `argocd` contrôleur en marche : suppression en cascade de la production.
- Retirer les finaliseurs contrôleurs en marche : la racine les remet.
- Contrôleur arrêté, finaliseurs oubliés : espace bloqué en `Terminating`.
- Supprimer les CRD `argoproj.io` « toutes » : celles d'Argo Rollouts partent avec, et les Rollouts de MédiAgenda avec elles.
- Déchiffrer l'export sur le disque, ou garder la clé privée dans le cluster.
- Oublier de recréer le CronJob de sauvegarde après la reconstruction (il n'est pas dans la release, exprès).

**En production chez MédiSphère**
Répétition semestrielle sur un cluster jetable (preuve HDS), alerte « dernière sauvegarde d'Argo CD de plus de 26 h » (M21, métrique du CronJob), copie hors site du compartiment vers PAR2, rotation annuelle de la clé de sauvegarde avec conservation des anciennes clés privées pour la durée de rétention.

---

### M20-E29 — Fenêtres de synchronisation et gel des changements

**Solution**

Fichiers : [fenêtre de `mediagenda`](fichiers/M20-E29/gitops/projets/mediagenda.extrait-E29.yaml) (avec l'exemple de gel en commentaire), [fenêtre de `medidoc`](fichiers/M20-E29/gitops/projets/medidoc.extrait-E29.yaml), [`politique-changements.md`](fichiers/M20-E29/medisphere/docs/livraison/gitops/politique-changements.md).

*2.* Du vendredi 16:00 au lundi 08:00 : 2 × 24 + 16 = **64 h**. Fenêtre `deny`, `schedule: "0 16 * * 5"`, `duration: 64h`, `timeZone: Europe/Paris`, `applications: ["*-prod"]`, `manualSync: true`, `description` avec le ticket.

```
admin@adm01:~$ argocd proj windows list mediagenda
admin@adm01:~$ argocd app get mediagenda-prod | grep -E 'SyncWindow|Assigned Windows'
SyncWindow:         Sync Allowed
Assigned Windows:   deny:0 16 * * 5:64h
```

(Le vendredi après 16:00 : `Manual Allowed`.)

*3. Essais* : sur une branche, fenêtre d'essai `deny` dont le cron se déclenche dans la minute (ex. `"<MM> <HH> * * *"` à l'heure de Paris, `duration: 30m`, `applications: ["mediagenda-recette"]`), synchronisée par une Application de test pointant sur la branche… ou, plus simple, la fenêtre ajoutée directement à l'AppProject par MR puis retirée par la MR inverse (recette seulement, 30 min). Constats : commit poussé dans `overlays/recette` → `OutOfSync`, pas de synchronisation automatique ; `kubectl scale … --replicas=0` → pas d'auto-réparation ; `argocd app sync mediagenda-recette` refusé sans `manualSync`, accepté avec ; à la fermeture, synchronisation automatique au rafraîchissement suivant (le commit attendait).

*4-5.* Procédure de gel et dérogation : `politique-changements.md`.

**Explications**

Une fenêtre est évaluée au moment de chaque synchronisation (automatique, manuelle, auto-réparation) : une fenêtre `deny` active les bloque, `manualSync` rouvre les synchronisations manuelles. La règle dit **quand** ; le RBAC dit **qui** (seul `role:plateforme-admin` peut synchroniser la production à la main) ; les deux ensemble donnent « l'astreinte peut corriger, personne d'autre ne peut livrer ». Une durée est une durée réelle : le week-end du changement d'heure, la fenêtre finit à 07:00 ou 09:00 le lundi.

**Alternatives**
- Fenêtres `allow` (mardi et jeudi 10:00-12:00) : plus strict, « tout ce qui n'est pas permis est interdit » ; à envisager pour la production quand les livraisons seront régulières.
- Gel par fenêtre `deny` permanente ajoutée par MR (cron quotidien, 24 h) plutôt qu'à date : plus simple à poser, à ne pas oublier de retirer.
- Kargo et ses étapes de promotion avec vérifications : gère aussi le « quand » au niveau de la promotion.

**Pièges classiques**
- `duration: 64` (sans unité) ou un cron en UTC sans `timeZone` : décalage d'une ou deux heures.
- Une fenêtre `allow` ajoutée « pour essayer » : toutes les Applications qu'elle vise ne se synchronisent **plus** en dehors d'elle.
- Croire que la fenêtre arrête un canary déjà lancé : Argo Rollouts continue ses marches.
- Laisser la fenêtre d'essai sur la recette (le check le détecte).

**En production chez MédiSphère**
Calendrier des gels publié (fin d'année, audits HDS), MR de gel et MR inverse liées au ticket CHG, rapport hebdomadaire des synchronisations manuelles pendant les fenêtres (événements et `status.history` dans Loki, M22).

---

### M20-E30 — Retirer à la CI tout accès en écriture aux applications

**Solution** (une solution possible ; `LIBRE` : d'autres choix sont valables s'ils respectent les exigences)

Fichiers : [configuration de l'agent](fichiers/M20-E30/k8s/.gitlab/agents/k8s-par1/config.yaml), [RBAC de l'agent](fichiers/M20-E30/k8s/rbac/gitlab-agent/10-agent.yaml), [`.gitlab-ci.yml` de `mediagenda/deploiement`](fichiers/M20-E30/deploiement/.gitlab-ci.yml), [nettoyage des gestionnaires de champs](fichiers/M20-E30/k8s/outils/nettoyer-gestionnaires.sh), [`acces-ci.md`](fichiers/M20-E30/medisphere/docs/livraison/gitops/acces-ci.md).

Déroulé :
1. **Inventaire** : `kubectl get rolebindings,clusterrolebindings -A -o json | jq …` (requêtes de `acces-ci.md`) ; `ci_access` actuel ; variables de CI des groupes (`KUBE_*`) ; jobs des pipelines de `mediagenda/deploiement` et `medidoc/deploiement`.
2. **Agent** : MR sur `plateforme/k8s` qui réduit `ci_access` à `formation/ci-labo` ; l'agent relit sa configuration depuis le dépôt (pas de redéploiement). Puis `rbac/gitlab-agent/10-agent.yaml` réduit à `wb-essais` (MR) et suppression des RoleBindings `gitlab-agent-edit` et `gitlab-agent-crd` de `mediagenda-dev` (et de tout autre espace applicatif où l'inventaire en trouve) : `kubectl --context k8s-par1 -n mediagenda-dev delete rolebinding gitlab-agent-edit gitlab-agent-crd` — retirer les objets du dépôt ne les supprime pas (`task appliquer` applique, il ne nettoie pas), d'où la suppression explicite tracée dans le ticket.
3. **Pipelines** : `.gitlab-ci.yml` de `mediagenda/deploiement` et de `medidoc/deploiement` réduits au composant `deploiement` (validation) ; `workflow:rules` sur MR et `main`.
4. **Gestionnaires de champs** : pour chaque objet,

```
admin@adm01:~/src/k8s$ outils/nettoyer-gestionnaires.sh mediagenda-prod deployment/mediagenda
Gestionnaires avant :
  argocd-controller (Apply)
  kubectl (Apply)
  kube-controller-manager (Update, status)
  rollouts-controller (Update)
Gestionnaires après :
  argocd-controller (Apply)
  kube-controller-manager (Update)
  rollouts-controller (Update)
spec inchangée : OK
Essai seulement : relance avec --appliquer.
admin@adm01:~/src/k8s$ outils/nettoyer-gestionnaires.sh mediagenda-prod deployment/mediagenda --appliquer
```

Boucle sur tous les Deployments, StatefulSets et Services des espaces `mediagenda-*` et `medidoc-*` (après revue de l'essai de chacun). Hors heures ouvrées pour la production, comme toute action sur elle.
5. **Preuves** : `kubectl auth can-i create deployments -n mediagenda-dev --as system:serviceaccount:gitlab-agent:gitlab-agent` → `no` (de même dans `mediagenda-recette`, `mediagenda-prod`, `medidoc-*` ; `yes` dans `wb-essais`) et essai depuis un job de `formation/ci-labo` (refus dans `mediagenda-dev`, succès dans `wb-essais`) ; `acces-ci.md`.

**Explications**

Le modèle *pull* ne vaut que si l'ancien chemin *push* est réellement fermé : un RoleBinding oublié, et un jeton de CI volé redonne l'écriture. `ci_access` et RBAC sont deux verrous différents (qui a un contexte ; ce que ce contexte permet) : on ferme les deux. Les gestionnaires de champs racontent l'histoire de chaque objet : `kubectl` (opération `Apply`) pour les `kubectl apply --server-side` du M17 et du job `deployer-dev`, `kubectl-edit`/`kubectl-scale` pour les gestes manuels. Argo CD ne migre d'office que `kubectl-client-side-apply` (option `ClientSideApplyMigration`, gestionnaire configurable par l'annotation `argocd.argoproj.io/client-side-apply-migration-manager`) ; les autres restent co-propriétaires des champs. Les retirer en **appliquant une configuration vide** au nom de `kubectl` supprimerait les champs dont `kubectl` était seul propriétaire (un champ absent de Git, par exemple) : c'est pourquoi le script retire l'**entrée** de propriété, sans toucher aux champs, et vérifie que `.spec` est identique.

**Alternatives**
- Supprimer l'agent `k8s-par1` (et sa release) : plus radical, si plus aucun projet n'en a besoin ; `formation/ci-labo` passerait alors par Argo CD aussi.
- ValidatingAdmissionPolicy qui refuse toute écriture dans les espaces applicatifs sauf par le compte de service du contrôleur d'Argo CD, des contrôleurs connus et un groupe de bris de glace : garde-fou **préventif** (ce check est **constatant**) ; à concevoir avec soin (Rollouts, HPA, CNPG écrivent aussi).
- Remettre `managedFields` à `[{}]` (remise à zéro complète, documentée) : simple, mais efface aussi la propriété d'Argo CD et des contrôleurs jusqu'à leur prochaine écriture.

**Pièges classiques**
- Retirer le fichier du RoleBinding du dépôt et croire qu'il a disparu du cluster.
- Réduire `ci_access` sans retirer les RoleBindings (ou l'inverse).
- Supprimer les jobs de déploiement mais garder une variable `KUBECONFIG` de groupe « pour plus tard ».
- Nettoyer les `managedFields` par une configuration vide appliquée au nom de `kubectl` : champs supprimés.
- Oublier les Services et les StatefulSets (base, Valkey).

**En production chez MédiSphère**
La VAP préventive après une période d'observation (mode `Audit`), revue trimestrielle d'`acces-ci.md`, alerte sur l'apparition d'un gestionnaire de champs humain dans un espace applicatif (audit de l'API, M22).

---

### M20-E31 — ADR : Argo CD, Flux et le modèle de promotion

**Solution**

Modèle : [ADR-0200](fichiers/M20-E31/medisphere/docs/livraison/gitops/adr/ADR-0200-gitops.md) (les chiffres entre chevrons sont à remplacer par **tes** mesures).

**Explications**

Une ADR d'exploitation s'appuie sur ce qu'on a vécu : la mémoire mesurée (E23, E27), la reconstruction (E28), les flux à décrire (E25), le diagnostic des pannes (E35-E42). La décision de référence retient Argo CD pour l'interface et le multi-locataire, la promotion par digest recopié par MR, Helmfile pour la couche de base (y compris Argo CD lui-même, qui ne peut pas dépendre de lui-même), et les Secrets hors Git jusqu'au M25.

**Alternatives** (décisions également défendables)
- Flux, si l'équipe privilégie la simplicité et l'absence d'interface (les équipes lisent l'état dans Grafana) et accepte Flagger pour le progressif.
- Branches par environnement, si les équipes maîtrisent les *cherry-picks* et veulent des droits différents par branche (protection de branche GitLab).
- Kargo dès maintenant, si le nombre de promotions justifie un outil.

**Pièges classiques**
- Comparer des listes de fonctionnalités, pas des mesures.
- Oublier « rien » (la CI qui pousse) comme option : c'est la référence d'avant.
- Ne pas dire ce qui reste sous Helmfile, et pourquoi.
- Pas de condition de révision.

**En production chez MédiSphère**
L'ADR est relue au M24 (SSO), au M25 (Secrets) et à chaque mineure d'Argo CD.

**Grille d'auto-évaluation**
- [ ] Les trois options sont évaluées sur les mêmes critères, avec au moins trois mesures du module.
- [ ] Promotion, frontière Helmfile/Argo CD et Secrets décidés, conséquences écrites (positives et négatives).
- [ ] Conditions de révision datées ou chiffrées.

---

### M20-E32 — Questions de production : GitOps

**Barème** : 2 points par question, total sur 28. 2 = juste, argumenté et chiffré quand c'est possible ; 1 = idée juste mais incomplète ; 0 = faux ou blanc. Pour un QCM, la bonne lettre sans justification vaut 1.

**1. Argo CD arrêté deux heures.** Les applications **tournent** : pods, Services, Gateway, bases ne dépendent pas d'Argo CD. Ce qui ne marche plus : aucune synchronisation (ni promotion, ni correction), aucune auto-réparation (une dérive manuelle reste), aucune détection de dérive ni d'état dans l'interface, plus de notifications, plus de génération d'Applications par les ApplicationSets, plus de webhooks traités (les événements GitLab échouent). Ce qui continue : Argo Rollouts (un canary en cours poursuit ses marches et ses analyses), HPA, contrôleurs, CNPG. Au redémarrage, Argo CD compare et rattrape (`selfHeal` en dev et recette).

**2. Réponse b.** Le *repo-server* ne peut plus récupérer le dépôt : la comparaison échoue (`ComparisonError`, synchronisation `Unknown` après expiration du cache), les ressources restent en place, aucune synchronisation n'est possible. a) faux : Argo CD ne supprime jamais faute de pouvoir lire la source (il faudrait un rendu vide **réussi**). c) faux : le cache des manifestes rendus évite des rendus répétés pour une même révision, mais une synchronisation demande une révision résolue (`ls-remote`) ; à révision connue et en cache, un rafraîchissement simple peut encore réussir un moment — d'où des états mêlés pendant la panne. d) faux : la santé dépend des ressources, pas de Git.

**3. Dossier `overlays/recette` supprimé.** Générateur de **dossiers** : l'élément `recette` disparaît ; avec `create-update`, l'ApplicationSet **ne supprime pas** l'Application `mediagenda-recette` ; celle-ci pointe sur un chemin absent : erreur de comparaison (rendu impossible), ressources **en place** (pas de rendu vide). Avec la politique `sync`, l'ApplicationSet **supprime** l'Application ; si elle porte le finaliseur, ses ressources partent avec (base comprise) ; sans finaliseur (`preserveResourcesOnDeletion`), elles restent orphelines. Éviter : générateur de **liste** (palier 2), `create-update`, `preserveResourcesOnDeletion`, protection de branche et relecture, `Prune=false` sur les objets à données.

**4. `prune` en production.** En dev, un objet retiré de Git doit disparaître (sinon la dérive s'accumule) ; en production, une erreur de rendu ou un fichier déplacé peut supprimer un objet vital (Service, Secret référencé, base). Protections : `Prune=false` (annotation `argocd.argoproj.io/sync-options` sur l'objet) ; `Prune=confirm` (suppression demandée explicitement) ; `PruneLast=true` (suppression après le reste) ; synchronisation manuelle de la production (l'humain voit le diff). Pour le cluster CNPG `mediagenda-db` : `Prune=false` **et** `Delete=false` (l'Application supprimée ne l'emporte pas), plus la classe de stockage `Retain` et les sauvegardes Barman.

**5.** a) **Non** : le jeton n'a aucun droit Kubernetes, et Argo CD ne déploie que `main`. b) **Oui**, c'est exactement ce que permet `api` + `write_repository` : pousser une branche et ouvrir une MR ; ce qui l'arrête : la protection de `main` (fusion par les Maintainers seulement), la relecture, la porte de vérification des signatures (une image non signée par la clé MédiSphère fait échouer le pipeline de MR, M19-E29), et la synchronisation manuelle de la production. c) **Non** : `main` est protégée, seuls les Maintainers fusionnent (le compte du jeton de projet est Developer). d) **Non** : les fenêtres sont dans `plateforme/gitops`, hors de portée de ce jeton. Conséquence : la portée `api` reste trop large (lecture de tout le projet, commentaires) ; un jeton de portée plus fine serait mieux si GitLab le permet.

**6. Secrets hors Git.** Reconstruction : une étape manuelle (`secrets-k8s.sh`, Vault) et l'ordre à respecter (E28) ; rotation : changer le Vault **et** relancer le script, sans trace de déploiement côté Argo CD ; revue : un Secret ne passe pas par MR, son contenu n'est pas relu, son existence n'est pas visible dans Git (référencé par nom seulement). Le M25 (External Secrets + OpenBao) met dans Git la **référence** (`ExternalSecret`), synchronisée par Argo CD, la valeur restant dans le coffre, avec rotation et audit.

**7. `kubectl scale --replicas=0` en recette.** `selfHeal` voit la différence au rafraîchissement suivant (événement de watch : quelques secondes ; au plus `timeout.reconciliation`) et resynchronise : réplicas remis, avec un délai entre deux auto-réparations (`controller.self.heal.timeout.seconds` et recul exponentiel). Le test de charge est faussé, le collègue frustré : il fallait passer par Git ou désactiver l'auto-réparation sur une branche d'essai. Avec un HPA et `ignoreDifferences` sur `/spec/replicas` (+ `RespectIgnoreDifferences`), Argo CD ignore le champ : le `scale` à 0 tient… jusqu'à ce que le HPA remonte au minimum.

**8. Push contre pull.** Droits : la CI détient des droits d'écriture (jetons dans des variables) contre un contrôleur dans le cluster, la CI ne détenant que le droit de proposer. Modification manuelle : en *push*, invisible jusqu'au prochain déploiement qui l'écrase (ou pas) ; en *pull*, détectée (`OutOfSync`) et corrigée si `selfHeal`. Échec à moitié : en *push*, le job échoue, l'état est ce qu'il est, il faut relancer ; en *pull*, l'état désiré reste dans Git, le contrôleur réessaie (`retry`), l'écart reste visible.

**9. Réponse b.** Avec 2 clusters et 3 partitions, l'algorithme par défaut place chaque cluster sur une partition ; une partition au moins reste **vide** : le réplica ne fait rien. a) faux : on ne partitionne pas les Applications d'un cluster. c) faux sans distribution dynamique : la partition est liée au numéro du pod du StatefulSet ; le cluster d'un réplica tombé attend son redémarrage. d) faux : le contrôleur ne sert pas l'interface. La distribution dynamique (alpha, Deployment au lieu de StatefulSet, battements de cœur) redistribue les clusters quand un réplica disparaît.

**10. `Synced` mais en panne.** (1) La configuration décrite est fausse mais valide (variable d'environnement erronée) : santé `Healthy` si les sondes sont trop permissives → sondes `/pret` qui testent les dépendances ; (2) une dépendance externe tombe (base, RGW) après la synchronisation : `Synced` ne dit rien du présent → sonde de disponibilité, supervision (M21) ; (3) le trafic ne va pas aux bons pods (HTTPRoute, poids, Service sans points d'accès) : santé des Services ignorée par défaut → analyse `web` du Rollout, sonde blackbox (M21). `Synced` veut dire « conforme à Git », `Healthy` « les ressources se disent saines » : ni l'un ni l'autre ne dit « le service rend le service ».

**11. Helmfile pour la couche de base.** Argo CD dépend de Cilium (réseau, politiques), CoreDNS, cert-manager (certificat de la Gateway), ceph-csi (volumes) : si Argo CD gérait Cilium et qu'une synchronisation de Cilium échouait à moitié, Argo CD pourrait perdre le réseau, donc la capacité de corriger ; il faudrait revenir à la main de toute façon. Règle : ce qui fait tourner l'outil n'est pas géré par l'outil. On garde un chemin d'administration indépendant (Helmfile depuis `adm01`), et on le documente (ADR-0200).

**12. Classement : b, puis a, puis c, puis d.** b) est la bonne : tout passe par Git, tracé, réversible (MR inverse). a) `--force` ne contourne **pas** une fenêtre `deny` (il force le remplacement des ressources, pas la fenêtre) : inutile, et dangereux (recréation d'objets) ; il ne fonctionnerait qu'avec `manualSync`. c) `kubectl edit` : efficace dans l'urgence, mais hors Git, et la correction sera **défaite** à la fermeture de la fenêtre si Git n'est pas corrigé (auto-réparation ou prochaine synchronisation) ; **parfois acceptable** comme geste de bris de glace si l'incident l'exige et que la MR de correction suit immédiatement, avec ticket INC. d) supprimer l'Application : au mieux inutile, au pire suppression en cascade de la production.

**13. Canary à 25 % à l'ouverture de la fenêtre.** Argo Rollouts continue : marches, pauses, analyses, jusqu'à 100 % ou la pause finale (en production, pause sans durée : il attend une promotion). Argo CD ne synchronise plus la production, mais le Rollout n'en a pas besoin. Ce que tu fais : suivre jusqu'au bout si tout est vert (la règle interdit de **commencer** une livraison, pas de finir proprement), ou `abort` si un doute ; et noter l'écart à la règle (le canary aurait dû être lancé plus tôt).

**14. Preuve d'audit.** Quoi : la MR de promotion (digest, auteur, relecteur, date de fusion) et le commit sur `main` ; qui l'a validé : l'approbation et la fusion dans GitLab (rétention des MR : durée de vie du projet) ; quand c'est arrivé en production et qui l'a lancé : `status.history` de l'Application (10 entrées) et les événements Kubernetes (1 h) — insuffisant seul ; la notification `on-deployed` dans Mailpit (rétention de Mailpit). Ce qui manque avant le M22 : la conservation des événements et des journaux du serveur d'Argo CD et de l'audit de l'API (Loki, rétention `audit` 1 an).

---

### M20-E33 — Accueillir MédiDoc en GitOps

**Solution** (une solution possible ; `LIBRE` : d'autres choix sont valables s'ils respectent les exigences)

Fichiers : `plateforme/k8s` : [`espaces/medidoc-recette/`](fichiers/M20-E33/k8s/espaces/medidoc-recette/), [cloison](fichiers/M20-E33/k8s/composants/reseau/politiques/isolement-medidoc-recette.yaml), [Secrets](fichiers/M20-E33/k8s/outils/secrets-k8s.d/), [Vault](fichiers/M20-E33/k8s/secrets/medidoc-recette.yml.exemple) ; RGW : [politique du compte `medidoc-recette`](fichiers/M20-E33/ceph/politiques/medidoc-recette.json) ; `medidoc/deploiement` : [`overlays/recette/`](fichiers/M20-E33/deploiement/overlays/recette/) ; `plateforme/gitops` : [ApplicationSet `medidoc`](fichiers/M20-E33/gitops/applications/medidoc.yaml), [AppProject](fichiers/M20-E33/gitops/projets/medidoc.extrait-E33.yaml) ; documentation : [note d'accueil](fichiers/M20-E33/medisphere/docs/livraison/gitops/accueil-equipe-gitops.md), [fiche d'équipe](fichiers/M20-E33/medisphere/docs/kubernetes/equipes/medidoc.extrait-E33.md).

Déroulé :
1. **Stockage** : compte `medidoc-recette` et compartiment `medidoc-recette-documents` sur le RGW, par l'IAM du RGW comme `medidoc-app` au M08-E12 (`aws iam create-user`, `put-user-policy` avec la politique fournie, `create-access-key`, compartiment créé avec le compte) ; clés dans le Vault (`secrets/medidoc-recette.yml`).
2. **Plateforme** (MR `plateforme/k8s`) : `espaces/medidoc-recette/` (espace, quota, LimitRange, compte `default`), cloison `isolement-medidoc-recette` ; `task appliquer` ; modules `medidoc-dev` et `medidoc-recette` de `secrets-k8s.sh` (`outils/secrets-k8s.d/`, comme `mediagenda-*` en M20-E12), puis `outils/secrets-k8s.sh appliquer medidoc-recette` et `appliquer medidoc-dev` (qui passe du script du M16 au Vault). Les politiques réseau de l'application (refus par défaut, entrée Gateway, sortie DNS et RGW) viennent de `base/politiques.yaml` de `medidoc/deploiement` (M19-E33) : la recette les reçoit par l'overlay, comme la dev.
3. **Projet et ApplicationSet** (MR `plateforme/gitops`) : destinations `medidoc-dev` et `medidoc-recette`, liste noire `ResourceQuota` et `LimitRange` (choix de M20-E07 : les politiques réseau d'application restent permises à l'équipe), ressources orphelines signalées avec les exceptions de la plateforme (`harbor-pull`, `medidoc-s3`) ; ApplicationSet `medidoc` (éléments `dev` et `recette`, même modèle que `mediagenda`).
4. **Équipe** (MR `medidoc/deploiement`) : `overlays/recette` ; image par **digest** recopié de dev.
5. **Reprise de dev** (méthode d'E08 ; dev était appliqué à la main jusqu'ici) : élément `dev` d'abord sans synchronisation automatique, `argocd app diff medidoc-dev` doit être vide **avant** la première synchronisation (même rendu que l'existant) : ajuster l'overlay `dev` jusqu'à ce qu'il le soit ; aucun pod recréé (UID relevés avant/après).
6. **Contrôles** :

```
admin@adm01:~$ curl -s https://medidoc-recette.apps.par1.medisphere.internal/readyz
{"statut":"pret", …}
admin@adm01:~$ curl -s -F patient=PAT-RECETTE-1 -F fichier=@essai.pdf https://medidoc-recette.apps.par1.medisphere.internal/documents | jq -r .id
admin@adm01:~$ curl -s https://medidoc-dev.apps.par1.medisphere.internal/documents?limite=1000 | jq -r '.[].id' | grep -c <ID>     # 0
admin@adm01:~$ for f in $(git -C ~/src/medidoc-deploiement ls-files '*.yaml' '*.yml'); do grep -l '^kind: Secret' ~/src/medidoc-deploiement/$f; done   # rien
```

(Forme exacte de la réponse de `/readyz` et de la liste : `apps/medidoc/README.md`.)

**Explications**

L'accueil d'une équipe en GitOps sépare deux mondes : ce que la **plateforme** possède (espace, enveloppe, politiques, Secrets, projet, ApplicationSet) et ce que l'**équipe** possède (ses manifestes, ses promotions). L'AppProject matérialise la frontière : destinations limitées, aucun objet de cluster, liste noire de l'enveloppe (quota, LimitRange) ; les invariants réseau sont des refus de cluster, hors d'atteinte du projet. Chaque environnement a ses propres identifiants de stockage : une fuite des identifiants de recette n'expose pas les documents de dev (ni, demain, de production). La cloison réseau sépare même deux espaces de la même équipe.

**Alternatives**
- Générateur de dossiers Git (`overlays/*`) : l'équipe crée un environnement en créant un dossier ; refusé ici (un dossier créé par erreur devient un environnement synchronisé) — le choix du palier 2.
- Espace créé par Argo CD (`CreateNamespace=true` avec `managedNamespaceMetadata`) : moins de MR, mais l'équipe contrôlerait les étiquettes de son espace (Pod Security, équipe) : refusé.
- Un projet Argo CD par environnement (`medidoc-prod` séparé) : utile pour des droits ou des fenêtres très différents.

**Pièges classiques**
- Réutiliser le compte RGW de dev en recette.
- Croire qu'une politique d'espace de l'équipe protège la plateforme : l'équipe peut toujours ouvrir sa propre sortie ; ce qui la borne, c'est la cloison de cluster `isolement-medidoc-recette` (des refus qu'aucune politique d'espace ne lève) et le refus par défaut de la bordure.
- Décrire la même politique (`refus-par-defaut`) dans `plateforme/k8s` **et** dans le dépôt de l'équipe : deux propriétaires, et Argo CD l'adopte à la première synchronisation.
- Créer l'espace par l'overlay de l'équipe (refusé par le projet : `Namespace` est un objet de cluster).
- Oublier la racine MédiSphère (volume) ou le Secret `harbor-pull` : pods en `ContainerCreating` ou `ImagePullBackOff`.
- Ne pas relire `argocd app diff medidoc-dev` avant la reprise : des pods recréés.

**En production chez MédiSphère**
Le gabarit `outils/nouvelle-equipe.sh` (M14-E33) étendu à la partie GitOps (projet, ApplicationSet), la promotion dev → recette par le composant `promotion` du M19, et la production de MédiDoc derrière la même fenêtre et la même synchronisation manuelle que MédiAgenda.

---

### M20-E34 — Une mise en production en temps limité

**Solution** (déroulé de référence ; à ne lire qu'après ta tentative chronométrée)

Modèles : [journal](fichiers/M20-E34/adm01/journal.md), [compte rendu](fichiers/M20-E34/medisphere/docs/livraison/gitops/tests/mise-en-production-chrono.md).

```
admin@adm01:~$ mkdir -p ~/m20/e34 && date -u +%FT%TZ > ~/m20/e34/T0
admin@adm01:~/src/deploiement$ git pull && yq '.images' overlays/recette/kustomization.yaml overlays/prod/kustomization.yaml
admin@adm01:~$ argocd app get mediagenda-prod | grep -E 'Sync Status|Health|SyncWindow'
admin@adm01:~$ argocd proj windows list mediagenda
admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-prod          # état de départ
admin@adm01:~/src/deploiement$ outils/promouvoir.sh recette prod                        # MR ; titre complété : « … (CHG-2134) »
# (validation du pipeline de MR, fusion par un Maintainer)
admin@adm01:~/src/deploiement$ git pull && diff <(grep -o 'sha256:[0-9a-f]*' overlays/recette/kustomization.yaml) <(grep -o 'sha256:[0-9a-f]*' overlays/prod/kustomization.yaml)
admin@adm01:~$ argocd app diff mediagenda-prod                                          # à recopier dans le journal
admin@adm01:~$ argocd app sync mediagenda-prod && argocd app wait mediagenda-prod --sync
admin@adm01:~$ kubectl argo rollouts get rollout mediagenda -n mediagenda-prod --watch   # marches, analyses
admin@adm01:~$ kubectl -n mediagenda-prod get analysisruns -w                            # autre terminal
admin@adm01:~$ while sleep 2; do curl -s -o /dev/null -w '%{http_code}\n' https://mediagenda.apps.par1.medisphere.internal/sante; done | uniq -c   # troisième terminal
admin@adm01:~$ kubectl argo rollouts promote mediagenda -n mediagenda-prod              # à la pause finale, critères réunis
admin@adm01:~$ kubectl -n mediagenda-prod get httproute mediagenda -o jsonpath='{.spec.rules[0].backendRefs}'   # 100 / 0
```

Puis Mailpit (`[Argo CD] mediagenda-prod déployée`, déclencheur `on-deployed` de M20-E19) et le compte rendu poussé sur `main`. Avec `argocd app sync`, la synchronisation est attribuée à ton compte (`initiatedBy.username`) ; une synchronisation par l'interface aussi. La pause finale de la production (ajoutée par l'overlay `prod` en M20-E16) est le moment des contrôles humains : `promote` passe à l'étape suivante (ici la fin), `promote --full` sauterait les marches restantes (à ne pas utiliser à 10 %).

Retour arrière, si une analyse échoue : le Rollout s'interrompt seul (`Degraded`, trafic rendu au stable) ; l'Application passe `Degraded` (notification `on-health-degraded`) ; `git revert` de la MR de promotion, fusion, synchronisation manuelle (révision dans `rollbackWindow` : pas de canary pour revenir).

**Explications**

Une mise en production GitOps est une suite de preuves : le digest promu est **celui** qui a été validé (même empreinte), la synchronisation est **attribuable** (compte nominatif, hors fenêtre), le trafic monte par paliers sous **analyses**, l'équipe est **prévenue**, et le **compte rendu** relie tout (ticket, MR, heures). Le chronomètre force à connaître ses outils (promotion, `argocd app`, `kubectl argo rollouts`) et à préparer son retour arrière **avant** de commencer.

**Alternatives**
Synchronisation et promotion depuis l'interface d'Argo CD (bouton *Sync*, actions du Rollout) : même résultat, mêmes traces ; plus lent à chronométrer, plus lisible pour un observateur.

**Pièges classiques**
- Lancer pendant la fenêtre `deny` (vendredi après 16:00) sans le voir : synchronisation refusée, temps perdu.
- Promouvoir le digest de **dev** au lieu de celui de recette.
- `promote --full` dès la première marche : plus d'analyses ni de paliers.
- Oublier la pause finale de la production et attendre « que ça avance ».
- Synchroniser par une MR fusionnée… sans synchroniser (la production ne se synchronise pas seule).
- Un compte rendu sans heures ni digest.

**En production chez MédiSphère**
Ce déroulé devient la fiche réflexe « mise en production » ; au M21, l'analyse de taux d'erreur (Prometheus) remplace la boucle `curl` manuelle ; au M24, la synchronisation se fait avec l'identité SSO.
