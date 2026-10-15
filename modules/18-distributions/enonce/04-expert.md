# Module 18 — Palier 4 : Expert

Chaque distribution a été installée, montée de version, sauvegardée et restaurée. Nadia Roussel pose la question de l'astreinte : « Le jour où un nœud k3s de l'agence ne revient pas, où Talos refuse sa configuration, où une machine Cluster API reste coincée ou où RKE2 refuse de démarrer, qui sait où regarder ? Chaque distribution range ses journaux, ses fichiers et ses erreurs ailleurs. » Karim Benali a préparé quatre pannes, une par distribution, tirées des tickets des forums et des problèmes connus de chaque projet. Tu descends ensuite sous le capot de k3s, puis tu passes les questions qu'on pose en entretien.

La méthode reste celle des modules précédents : observer avant d'agir, formuler une hypothèse, la tester par la mesure la moins invasive, corriger à la racine, prévenir la récidive. Les distributions y ajoutent trois règles :
- **Trouve d'abord qui parle.** Un symptôme Kubernetes (`NotReady`, machine bloquée) a presque toujours sa cause un étage plus bas : le service de la distribution (`k3s`, `k3s-agent`, `rke2-server`), l'API de l'OS (`talosctl`), le fournisseur d'infrastructure (CAPMOX, Proxmox). Chaque distribution a son journal : `journalctl -u k3s-agent`, `journalctl -u rke2-server`, `talosctl logs`, `talosctl dmesg`, les journaux des contrôleurs Cluster API.
- **La distribution est une configuration.** Un fichier (`config.yaml`, `config.yaml.d/`, `registries.yaml`), une configuration de machine Talos, un objet Cluster API. La réparation se fait dans **le code** (rôle Ansible, `talos/noeuds/`, `capi/`), puis on la rejoue. Une correction à la main sur le nœud est permise pour rétablir le service ; elle n'est terminée que lorsque le code et le nœud sont d'accord (rôle rejoué sans changement, `talos/appliquer.sh … --essai` vide).
- **Ne détruis pas ce que tu ne sais pas reconstruire.** Interdits dans ce palier : réinstaller un nœud, `talosctl reset` d'un nœud de contrôle, `k3s-uninstall.sh`, supprimer une `Machine`, un `Cluster` ou une VM 5180-5189 à la main, `--cluster-reset` sans instantané vérifié. Aucune des pannes n'exige plus qu'un fichier, un service ou un objet corrigé.

> **Rappels** : tout se lance depuis `adm01`.
> - Fichiers d'accès : `~/.config/workbook/m18/` (`k3s-ha.kubeconfig`, `rke2.kubeconfig`, `talosconfig`, `talos.kubeconfig`, `talos-secrets.yaml`, `k3s01.kubeconfig`, `capi-essai.kubeconfig`).
> - Code : `~/src/distributions` (`talos/appliquer.sh`, `talos/noeuds/`, `capi/capi-essai/`), `~/src/ansible` (rôles `k3s`, `rke2`), `~/src/infra` (`envs/m18`).

**État de départ attendu** (fin du palier 3) :
- banc k3s etcd de M18-E14 : `k3s-ha01` (serveur) et `k3s-ha02` (agent), tous deux `Ready` ;
- `rke2-01..03` (pour E22) : trois serveurs `Ready`, profil CIS, reconstruits par le code s'ils ont été détruits (introduction du palier 3) ;
- `talos-essai` (pour E20) : `talos-01` (10.10.99.85, plan de contrôle), `talos-02` et `talos-03` (10.10.99.86-87), Talos v1.14.2, Kubernetes v1.36.5, `talosctl health` vert, reconstruit de la même façon ;
- `capi-essai` en v1.36.5 sur le template 9061 (M18-E13), 1 nœud de contrôle + 2 travailleurs, `MachineHealthCheck` en place ;
- `lab/bin/check 18 13` et `lab/bin/check 18 14` verts.

> ⚠️ **Mémoire** : une panne à la fois, avec seulement le banc concerné (et `k3s01`, toujours là). Les autres bancs sont détruits ou au repos (introduction du palier 3) ; `capi-essai` doit être réveillé pour E21. `k8s-par1` reste arrêté.

## Règles du jeu des pannes (M18-E19 à M18-E22)

- Les pannes s'injectent **depuis `adm01`**, à la racine de ta copie du workbook :
  ```
  admin@adm01:~/DevOpsPrivateCloud$ lab/bin/break 18 19
  ```
  Le script tire une variante au hasard et n'affiche que le **symptôme**, comme un ticket. Chaque panne a 3 ou 4 variantes : refais l'exercice jusqu'à les avoir toutes rencontrées (`--variante N` force une variante, sans dire laquelle est laquelle). Si une variante n'a pas d'effet sur ton lab, le script en essaie une autre ou s'annule.
- **Avant d'injecter**, lance le contrôle de l'exercice (`lab/bin/check 18 19`) : il doit être vert. Les scripts refusent de casser un banc qui n'est pas sain.
- **Ne lis pas** les scripts de `corrige/pannes/`, ni `/var/lib/workbook/` sur les nœuds, ni `~/.local/state/workbook/` sur `adm01` : ils contiennent la cause.
- Une seule panne active à la fois par exercice. Si tu abandonnes, `lab/bin/break 18 19 --annuler` remet l'état sain. C'est un filet de sécurité, pas un correctif : compte l'exercice comme non réussi.
- **Quand tu as réparé**, lance aussi `--annuler` pour **clore** la panne : sinon elle reste marquée active et bloque le mini-projet. L'annulation ne rétablit que ce qui est encore dans l'état cassé et ne revient jamais sur ta réparation (pour E21, elle remet aussi le nombre de travailleurs d'origine).
- Les pannes n'agissent que sur les VMs du module (`k3s-ha01/02`, `rke2-01..03`, `talos-01..03`), sur les objets Cluster API de l'espace `capi-essai` de `k3s01`, sur ta copie `~/src/distributions` (branche locale, jamais de `git push`) et sur ton poste (`~/.config/workbook/m18/`, toujours sauvegardé avant). Pour E21, elles touchent aussi **deux réglages Proxmox propres au module** : l'expiration du jeton `wb-capi@pve!capi` et l'appartenance du template de `capi-essai` au pool `lab`. Elles ne touchent jamais `k8s-par1`, la bordure, `pbs01` ni le réseau de `pve01`.
- Si SSH vers un nœud refuse ta connexion, tu as toujours la console de la VM dans Proxmox et l'agent QEMU (`qm guest exec <VMID> -- <commande>` depuis `pve01`, en lecture d'abord). Le refus lui-même est un indice.
- **Tiens un journal de diagnostic** pour chaque panne, dans `docs/socle/journal/` de `~/medisphere` (publié par MR) : heure, hypothèse, commande, résultat observé, conclusion.
- Le **temps cible** est indicatif. Le dépasser n'est pas un échec ; corriger sans comprendre en est un.

---

### M18-E19 — Panne : le nœud k3s ne rejoint plus le cluster  `BF` `★★`

> **Ticket INC-4519** — *De : Nadia Roussel*
> *(Le détail s'affiche à l'injection.)* Depuis l'intervention de cette nuit sur le banc, `k3s-ha02` est `NotReady` et ne revient pas. C'est la répétition de ce qui arrivera à l'agence de Lyon : il faut savoir trouver seul pourquoi un nœud k3s ne rejoint plus son serveur, sans le réinstaller.

**Objectifs pédagogiques**
- Suivre l'enregistrement d'un agent k3s : jeton, adresse du serveur, superviseur, certificats, horloge, réseau.
- Lire le journal de `k3s-agent` et relier chaque message à une étape de l'enregistrement.
- Corriger dans le rôle Ansible et rédiger RB-183.

**Prérequis** : M18-E03, M18-E07, M18-E14 (banc `k3s-ha01`/`k3s-ha02`) ; `lab/bin/check 18 19` vert avant l'injection.
**Durée indicative** : 30 min (temps cible).

**Contexte technique** : l'agent `k3s-ha02` est configuré par le rôle `k3s` (`k3s_role: agent`, `k3s_url`, jeton du Vault `lab`) ; ses fichiers sont sous `/etc/rancher/k3s/`. Le serveur est `k3s-ha01` (`https://k3s-ha01.par1.medisphere.internal:6443`).

**Injection** : `lab/bin/break 18 19` (4 variantes).

**Travail demandé**
1. Constate depuis le cluster (`kubectl get nodes`, conditions et événements du nœud), puis sur `k3s-ha02` : état du service, journal **depuis le dernier démarrage**, configuration effective (fichiers de `/etc/rancher/k3s/`, unité systemd et son fichier d'environnement).
2. Reconstitue la séquence d'enregistrement d'un agent k3s (page *Architecture* et page *token* de la doc) : quelle étape échoue ? Teste chaque hypothèse par une commande qui ne modifie rien. Exemples : joindre le superviseur, comparer l'empreinte de la CA avec celle que porte le jeton, comparer les horloges des deux nœuds.
3. Corrige à la racine (rôle Ansible, variables, ou service du nœud) et rejoue le rôle sur `k3s-ha02` ; il doit finir sans changement au second passage. Le nœud revient `Ready` sans réinstallation.
4. Rédige `docs/kubernetes/distributions/runbooks/RB-183-noeud-k3s-ne-rejoint-pas.md` : symptômes, ordre des vérifications, messages typiques et leur cause, correctifs, ce qu'on ne fait jamais (supprimer le Secret `<nœud>.node-password.k3s` sans comprendre, réinstaller).

**Critères de réussite**
- [ ] `k3s-ha02` est `Ready`, `k3s-agent` est actif sans redémarrage depuis 5 minutes, et son horloge est synchronisée.
- [ ] La configuration de l'agent désigne `k3s-ha01` sur le port 6443 avec un jeton accepté. Le rôle rejoué ne change rien.
- [ ] Ton journal relie le message du journal de l'agent à la cause. RB-183 est publié.

**Vérification** : `lab/bin/check 18 19`

<details><summary>Indice 1</summary>

L'agent fait plusieurs requêtes **avant** d'être un kubelet : il télécharge la CA (sans authentification), la compare au jeton, puis demande ses certificats au superviseur avec le jeton. Le premier message d'erreur après le démarrage dit à quelle de ces étapes il s'est arrêté.
</details>

<details><summary>Indice 2</summary>

Un jeton au format sécurisé commence par `K10` et contient l'empreinte SHA-256 de la CA du cluster. `curl -sk https://<serveur>:6443/cacerts | sha256sum` donne celle du serveur. Et le superviseur de k3s n'écoute pas sur le même port que celui de RKE2.
</details>

<details><summary>Indice 3</summary>

« Certificat pas encore valide » et « certificat expiré » ne parlent pas toujours du certificat : ils parlent aussi de l'heure de la machine qui le vérifie.
</details>

---

### M18-E20 — Panne : le nœud Talos refuse sa configuration  `BF` `★★★`

> **Ticket INC-4520** — *De : Karim Benali*
> *(Le détail s'affiche à l'injection : selon le cas, c'est `talosctl` qui ne parle plus au cluster, un nœud qui a disparu, ou le correctif de Lucas qui ne passe pas.)* Talos n'a pas de SSH : on ne peut pas « aller voir ». C'est précisément le test. Répare avec `talosctl`, le code de `plateforme/distributions` et rien d'autre.

**Objectifs pédagogiques**
- Diagnostiquer un nœud Talos sans shell : `talosctl` (`version`, `get`, `logs`, `dmesg`, `service`, `health`), la console Proxmox en lecture, le mode maintenance.
- Distinguer une erreur d'identité du client (`talosconfig`), une erreur de configuration (validation des documents) et un nœud sans configuration.
- Reconstruire ce qui manque à partir du paquet de secrets et du code, jamais à la main.

**Prérequis** : M18-E05, M18-E06, M18-E14 ; `lab/bin/check 18 20` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique** : `talos/appliquer.sh <nœud> [--maintenance|--essai]` applique la configuration générée (`generer.sh` : `talos-secrets.yaml`, `versions.env` et les correctifs de `talos/patches/{commun,controlplane,worker}/`) avec le correctif propre au nœud (`talos/noeuds/<nœud>.yaml`). En 1.14, la plupart des champs `v1alpha1` sont remplacés par des documents dédiés (`KubeNodeConfig`, `KubeletConfig`, `HostnameConfig`…), et un champ `v1alpha1` et le document qui le remplace s'excluent. Le paquet de secrets (`talos-secrets.yaml`) est la seule source de l'identité du cluster ; il est aussi dans le Vault `lab` (`talos/secrets/talos-secrets.yaml.vault`).

**Injection** : `lab/bin/break 18 20` (3 variantes). Une variante peut créer une branche locale `lucas/…` dans `~/src/distributions` et t'y laisser ; `--annuler` te ramène sur ta branche d'origine et ne supprime la branche de Lucas que si tu n'y as rien ajouté.

> ⚠️ **Attention** : si un nœud est en mode maintenance, il accepte **n'importe quelle** configuration envoyée avec `--insecure`, sans authentification. Avant de lui en envoyer une, vérifie que l'adresse est bien celle de la VM attendue (console Proxmox, adresse MAC, VMID), et n'envoie que la configuration générée par `generer.sh` pour **ce** nœud.

**Travail demandé**
1. Établis les faits sans rien modifier :
   - `talosctl version` vers chaque nœud ;
   - `talosctl -n <IP> get machinestatus`, `service`, `logs machined` ;
   - console de la VM dans Proxmox (lecture seule) ;
   - état des nœuds dans Kubernetes.

   Pour chaque nœud, dis à quel étage est la panne : client, configuration, nœud.
2. Selon le cas :
   - **client** : compare ce que contient ton `talosconfig` (`talosctl config info`, certificats du contexte) avec l'identité du cluster ;
   - **configuration** : rejoue le correctif en mode essai et lis le refus mot à mot ;
   - **nœud** : reconnais le mode maintenance et ce qu'il implique.
3. Répare **depuis le code et le paquet de secrets**, jamais en éditant une configuration de machine à la main (`talosctl edit` est interdit ici) :
   - un `talosconfig` se régénère ;
   - un correctif se corrige sur la branche, par un nouveau commit Conventional Commits (garde ce que Lucas voulait faire, si c'est légitime) ;
   - un nœud se reconfigure avec `talos/appliquer.sh`.
4. Vérifie par `talosctl health` et `kubectl get nodes`, puis montre que `talos/appliquer.sh <nœud> --essai` ne propose plus aucun changement.
5. Rédige `docs/kubernetes/distributions/runbooks/RB-184-talos-diagnostic.md` : arbre de décision client / configuration / nœud, commandes de chaque branche, ce qu'on ne fait jamais (`--insecure` vers une adresse non vérifiée, `reset` du nœud de contrôle, `edit` en production).

**Critères de réussite**
- [ ] `talosctl` répond sur les trois nœuds avec ton `talosconfig`, en 600, qui a le rôle `os:admin` et dont le certificat est signé par la CA du cluster.
- [ ] Les trois nœuds sont `Ready` dans Kubernetes. Aucun n'est en maintenance, `talosctl health` est vert.
- [ ] Si une branche `lucas/*` existe : elle passe `talos/appliquer.sh <nœud> --essai` sans erreur et ses étiquettes de zone sont appliquées aux deux travailleurs (`topology.kubernetes.io/zone` = `par1-baie-b` pour `talos-02`, `par1-baie-c` pour `talos-03`).
- [ ] Ton journal situe la panne à son étage avec la preuve. RB-184 est publié.

**Vérification** : `lab/bin/check 18 20`

<details><summary>Indice 1</summary>

L'API Talos est en TLS **mutuel** : le client vérifie le nœud avec la CA écrite dans le `talosconfig`, et le nœud vérifie le certificat client avec la CA de sa configuration. Un `talosconfig` d'un **autre** cluster échoue des deux côtés. `talosctl config info` montre la fin de validité et les rôles du contexte courant.
</details>

<details><summary>Indice 2</summary>

Un nœud en maintenance répond à `talosctl … --insecure get disks`, mais pas aux commandes authentifiées. Il a perdu sa configuration, pas son disque système : regarde ce que contient sa partition `STATE`. La console Proxmox affiche le tableau de bord de Talos et l'adresse du nœud.
</details>

<details><summary>Indice 3</summary>

La validation d'une configuration Talos est stricte : un champ inconnu ou un champ `v1alpha1` qui coexiste avec le document qui le remplace sont refusés **avant** toute application. Le message nomme le document et le champ. Compare avec la page de référence du document en 1.14.
</details>

---

### M18-E21 — Panne : la machine reste en Provisioning  `BF` `★★★`

> **Ticket INC-4521** — *De : Julien Petit* — *Copie : Karim Benali*
> J'ai demandé un troisième travailleur sur `capi-essai` pour un test de charge. Karim a passé le `MachineDeployment` à 3 il y a vingt minutes. La nouvelle machine n'avance pas. *(Le détail s'affiche à l'injection.)*

**Objectifs pédagogiques**
- Suivre une machine Cluster API à travers ses contrôleurs : `Machine` → `ProxmoxMachine` (CAPMOX) → IPAM (*in-cluster*) → Proxmox → amorçage kubeadm.
- Lire les conditions, raisons et événements de chaque objet, et les journaux de `capmox-controller-manager` et du fournisseur IPAM.
- Corriger la cause sans supprimer d'objet Cluster API, et écrire RB-180.

**Prérequis** : M18-E08, M18-E10, M18-E12, M18-E13 ; `lab/bin/check 18 21` vert avant l'injection.
**Durée indicative** : 45 min (temps cible).

**Contexte technique**
- Cluster de gestion `k3s01`, espace `capi-essai`. Contrôleurs dans les espaces `capi-system`, `capi-kubeadm-bootstrap-system`, `capi-kubeadm-control-plane-system`, `capmox-system` et celui du fournisseur IPAM (`kubectl get deploy -A | grep -i capi`).
- CAPMOX parle à l'API Proxmox avec les identifiants du Secret `capi-essai-proxmox` (jeton `wb-capi@pve!capi`, rôle `WBCapi`, ACL sur le pool `lab`) ; il prend les adresses dans le pool `capi-essai-v4-icip` (10.10.40.150-169) ; il clone le template de `capi-essai` (VMID 9061, M18-E13) dans la plage 5180-5189.
- Les phases d'une `Machine` sont : `Pending`, `Provisioning`, `Provisioned`, `Running`, `Deleting`, `Failed`. Les raisons de la condition `VirtualMachineProvisioned` d'une `ProxmoxMachine` sont dans les types de l'API `v1alpha2` de CAPMOX.

**Injection** : `lab/bin/break 18 21` (3 variantes). La panne fait elle-même le passage à 3 travailleurs (comme Karim) ; `--annuler` revient au nombre d'origine.

> ⚠️ **Attention** : ne supprime pas la `Machine` bloquée « pour qu'elle reparte ». Tant que la cause est là, sa remplaçante se bloquera au même endroit, et une suppression au mauvais moment peut laisser une VM orpheline dans Proxmox ou une adresse réservée. Si tu touches aux droits Proxmox, ne donne **jamais** plus que ce que le rôle `WBCapi` prévoit (M18-E08).

**Travail demandé**
1. Descends la chaîne, objet par objet, sans rien modifier :
   - `clusterctl describe cluster capi-essai -n capi-essai --show-conditions all` ;
   - la `Machine` neuve, puis sa `ProxmoxMachine` : conditions, raison, message, `status` ;
   - les événements de l'espace ;
   - les réservations d'adresses (`IPAddressClaim`, `IPAddress`, état du pool) ;
   - les journaux de `capmox-controller-manager` filtrés sur la machine.
2. Formule l'hypothèse et prouve-la **de l'autre côté** :
   - côté Proxmox : `pveum` (jetons, rôles, ACL), `pvesh get /pools/lab`, journal des tâches ;
   - ou côté cluster de gestion : qui réserve les adresses du pool, et pourquoi.
3. Corrige la cause (dans le code quand elle y est : `plateforme/infra` ou `plateforme/ansible` pour Proxmox, `capi/` pour les objets) et laisse les contrôleurs reprendre **seuls**. La machine doit passer `Running` sans être recréée à la main.
4. Rédige `docs/kubernetes/distributions/runbooks/RB-180-machine-capi-bloquee.md` :
   - tableau phase/condition/raison → étage → commande de preuve → correctif ;
   - au moins les causes jeton, droits ou template, adresses, point d'accès de l'API (VIP occupée ou injoignable) et amorçage kubeadm ;
   - ce qu'on ne fait jamais ;
   - quand mettre le cluster en pause (`spec.paused`).

**Critères de réussite**
- [ ] Toutes les machines de `capi-essai` sont `Running` et le `MachineDeployment` a tous ses réplicas prêts (3 si la panne est encore active, le nombre d'origine après `--annuler`).
- [ ] Le jeton `wb-capi@pve!capi` est valide (pas d'expiration passée), le template de `capi-essai` est dans le pool `lab`, et le pool d'adresses a au moins deux adresses libres. Aucune réservation d'adresses étrangère à Cluster API ne traîne dans `capi-essai`.
- [ ] Le rôle `WBCapi` n'a pas reçu de privilège en plus de ceux du code de M18-E08.
- [ ] Ton journal suit la machine d'objet en objet jusqu'à la cause. RB-180 est publié.

**Vérification** : `lab/bin/check 18 21`

<details><summary>Indice 1</summary>

Commence par savoir **si une VM existe** pour la nouvelle machine (champ `virtualMachineID` de la `ProxmoxMachine`, tâches de `pve01`). Sans VM, la machine n'a pas passé l'appel de clone : identité, droits, template. Avec une VM arrêtée, elle attend la suite : adresse, données d'amorçage, démarrage. La raison de la condition `VirtualMachineProvisioned` te dit laquelle attend.
</details>

<details><summary>Indice 2</summary>

Un jeton Proxmox peut être valide en apparence (il existe, ses droits sont bons) et pourtant refusé. `pveum user token list wb-capi@pve` affiche des colonnes que l'on ne lit jamais. Pour les droits, `pveum user permissions` sur le jeton et sur le chemin de la VM ou du template est plus parlant qu'une liste d'ACL.
</details>

<details><summary>Indice 3</summary>

Un pool d'adresses *in-cluster* compte les adresses réservées, pas les machines. Une réservation est un objet `IPAddressClaim` : qui l'a créée, pour quel propriétaire ? Une réservation sans propriétaire Cluster API n'est pas une machine.
</details>

---

### M18-E22 — Panne : RKE2 ne démarre plus  `BF` `★★★`

> **Ticket INC-4522** — *De : Sophie Laurent* — *Copie : Nadia Roussel*
> *(Le détail s'affiche à l'injection.)* Après une intervention sur `rke2-03`, le service `rke2-server` ne repart plus et le nœud est `NotReady`. Les deux autres serveurs tiennent le quorum, mais je ne veux pas de solution qui affaiblisse le profil CIS : pas de `profile:` retiré, pas de `protect-kernel-defaults: false`, pas de SELinux en permissif.

**Objectifs pédagogiques**
- Lire les échecs de démarrage de RKE2 : vérifications de l'hôte du profil CIS, lecture de la configuration, extraction du *runtime*, tirage des images du plan de contrôle.
- Retrouver la cause dans `journalctl -u rke2-server` et dans les fichiers de `/etc/rancher/rke2/` et `/var/lib/rancher/rke2/`.
- Rétablir le nœud sans affaiblir le durcissement, puis corriger le rôle `rke2`.

**Prérequis** : M18-E04, M18-E15 ; `lab/bin/check 18 22` vert avant l'injection.
**Durée indicative** : 40 min (temps cible).

**Contexte technique** : `rke2-01..03` sont trois serveurs (etcd à trois membres). La panne ne touche **qu'un** serveur, et le quorum reste garanti tant que les deux autres tournent. Configuration : `/etc/rancher/rke2/config.yaml` (rôle `rke2`, M18-E04), fragments `config.yaml.d/` (E14), `registries.yaml`. RKE2 est installé par RPM : son fichier de paramètres noyau CIS est sous `/usr/share/rke2/`.

**Injection** : `lab/bin/break 18 22` (4 variantes).

> ⚠️ **Attention** : ne redémarre jamais `rke2-server` sur un **deuxième** serveur pendant la panne : le quorum etcd tomberait. Ne lance pas `rke2-killall.sh` ni `--cluster-reset` : aucune variante n'en a besoin. Et rappelle-toi la mise en garde du guide de durcissement : redémarrer `systemd-sysctl` sur un nœud en service peut avoir des effets de bord ; préfère appliquer le seul fichier concerné.

**Travail demandé**
1. Lis le journal **depuis le dernier démarrage** (`journalctl -u rke2-server -b --no-pager`) jusqu'à la **première** erreur fatale, pas la dernière ligne. Compare les fichiers de configuration avec ceux de `rke2-01` et avec ce que génère le rôle (`--check --diff` limité à `rke2-03`).
2. Relie l'erreur à une exigence documentée (guide de durcissement, page de configuration du serveur, page des registres privés). Vérifie l'hypothèse sur le nœud par une lecture : compte, paramètre noyau, syntaxe YAML, nom d'image.
3. Rétablis le nœud **sans affaiblir le profil** : utilisateur, paramètres, fichier de configuration ou registre corrigés. Attention aux droits et au contexte SELinux des fichiers que tu touches. Le nœud doit revenir `Ready` et rejoindre etcd.
4. Corrige le rôle `rke2` si la cause y est, ou rends l'erreur impossible à reproduire si elle venait d'ailleurs (par exemple, validation de la syntaxe avant redémarrage dans le gestionnaire du rôle). Rejoue le rôle sur les trois serveurs, **un par un**.
5. Rédige `docs/kubernetes/distributions/runbooks/RB-185-rke2-ne-demarre-pas.md` : messages typiques et leur cause, vérifications de l'hôte du profil CIS, ce qu'on ne fait jamais.

**Critères de réussite**
- [ ] `rke2-server` est actif sur les trois serveurs, les trois nœuds sont `Ready`, etcd a trois membres sains.
- [ ] Le profil `cis` est toujours actif, etcd tourne sous l'utilisateur `etcd`, les paramètres noyau du profil sont appliqués, SELinux est en mode *enforcing*.
- [ ] `/etc/rancher/rke2/config.yaml` est un YAML valide identique à celui que produit le rôle ; les images du plan de contrôle viennent d'un registre joignable.
- [ ] Ton journal cite la première erreur fatale et sa cause. RB-185 est publié.

**Vérification** : `lab/bin/check 18 22`

<details><summary>Indice 1</summary>

RKE2 s'arrête à la **première** vérification qui échoue, et son message nomme ce qu'il attendait : un compte, un paramètre et sa valeur, une ligne de fichier. Avant cela, il lit sa configuration : une erreur de syntaxe y arrête tout, avec un numéro de ligne.
</details>

<details><summary>Indice 2</summary>

Si le service démarre mais que le nœud reste `NotReady`, ce n'est plus RKE2 qui échoue, c'est ce qu'il lance. Regarde les pods statiques (`/var/lib/rancher/rke2/agent/pod-manifests/`) et ce que le kubelet arrive à tirer (`crictl` de RKE2, avec son socket sous `/run/k3s/containerd/`). Un nom d'image se lit en entier, registre compris.
</details>

<details><summary>Indice 3</summary>

Un compte système recréé « à l'identique » par la commande du guide n'a pas forcément le même UID que l'ancien. Regarde à qui appartiennent les fichiers d'etcd (`ls -n`) avant de recréer quoi que ce soit.
</details>

---

### M18-E23 — Sous le capot : k3s, un binaire, une base, un superviseur  `LAB` `★★★`

> **Ticket PLAT-1923** — *De : Karim Benali*
> On dit que k3s est « Kubernetes en un binaire ». Je veux savoir ce que ça veut dire vraiment, pour pouvoir dépanner l'agence de Lyon sans lire le code : où sont les composants, où sont les données, qui écoute sur quel port, ce que fait le superviseur, et en quoi c'est différent de `k8s-par1`.

**Objectifs pédagogiques**
- Décrire l'architecture d'un serveur k3s : processus unique, composants en goroutines, binaires extraits, containerd embarqué.
- Lire la base SQLite de kine et la comparer au modèle clé-valeur d'etcd (révisions, compactage, *watch*).
- Comprendre le superviseur : `/cacerts`, enregistrement des agents, répartiteur local des agents.

**Prérequis** : M18-E03, M18-E14 (banc etcd), M14-E44 (sous le capot de kubeadm).
**Durée indicative** : 2 h 30.

**Contexte technique** : tout se fait **en lecture** sur `k3s01` (SQLite) et sur le banc `k3s-ha01`/`k3s-ha02` (etcd, agent). La base SQLite ne s'interroge **jamais** en place : on en fait une copie cohérente (`sqlite3 … ".backup"`) dans un dossier temporaire en `root`, on interroge la copie, on l'efface. `sqlite3` s'installe par `apt` sur les nœuds Debian.

> ⚠️ **Attention** : `k3s01` est le cluster de gestion de `capi-essai`. Aucune commande de ce lab ne doit écrire dans `/var/lib/rancher/k3s/` ni redémarrer `k3s`. La copie de la base contient les Secrets du cluster (chiffrés depuis M18-E15, mais aussi des objets non chiffrés) : elle reste en `root`, dans un dossier en 700, et elle est effacée à la fin.

**Travail demandé**
1. **Un binaire.** Sur `k3s01` :
   - `ls -l /usr/local/bin/` : qui pointe vers quoi ?
   - `/var/lib/rancher/k3s/data/` : que contient le dossier extrait, et pourquoi un nom haché ?
   - l'arbre des processus du service (`systemd-cgls -u k3s.service`, `ps -o pid,ppid,cmd --forest`) ;
   - les ports en écoute (`ss -ltnp`).

   Où sont le serveur d'API, l'ordonnanceur et le contrôleur ? Compare avec les pods statiques de kubeadm (M14-E04, M14-E44).
2. **Une base.** Copie la base de `k3s01` et lis le schéma de la table `kine` :
   - à quoi correspondent les colonnes `id`, `name`, `created`, `deleted`, `prev_revision` ?
   - suis la vie d'une ConfigMap de `wb-essais` : création, deux modifications, suppression, avec une copie entre chaque étape. Combien de lignes, quelles révisions ?
   - retrouve la ligne qui sert au compactage et explique comment kine reproduit la sémantique de révision d'etcd sur une base SQL.
   - sur `k3s-ha01`, fais la même observation avec `etcdctl` (certificats sous `/var/lib/rancher/k3s/server/tls/etcd/`) et compare.
3. **Un superviseur.**
   - Depuis `adm01`, interroge le port 6443 de `k3s-ha01` sans authentification : `/cacerts`, `/ping`. Que répond le superviseur, et qu'est-ce que le serveur d'API répondrait sur la même adresse ?
   - Sur l'agent `k3s-ha02`, relève les ports en écoute locale du processus `k3s agent` et la configuration du kubelet (`--kubeconfig`, adresse du serveur dans `/var/lib/rancher/k3s/agent/kubelet.kubeconfig`). Par où l'agent parle-t-il au serveur, et que se passe-t-il quand on ajoute un deuxième serveur ?
   - Retrouve le Secret qui protège l'identité de l'agent (`*.node-password.k3s`) et le fichier correspondant sur l'agent. Ne les modifie pas.
4. **containerd embarqué et modules intégrés.**
   - Socket, configuration générée et gabarit de containerd ; commandes `k3s crictl` et `k3s ctr`.
   - Où `registries.yaml` est-il traduit ?
   - Les manifestes de `/var/lib/rancher/k3s/server/manifests/` et les objets `AddOn` : dépose dans ce dossier un manifeste d'une ConfigMap `addon-temoin` dans `wb-essais`, observe l'`AddOn` créé, puis retire le fichier et observe ce que devient la ConfigMap. Lis la page *Packaged Components* de la doc pour savoir ce qui est attendu.
5. **Synthèse.** `docs/kubernetes/distributions/analyses/k3s-sous-le-capot.md` (deux pages) : schéma des processus et des ports, emplacement de chaque donnée, tableau « ce que j'aurais cherché sur kubeadm / où c'est sur k3s », et cinq commandes de dépannage pour l'agence de Lyon.

**Critères de réussite**
- [ ] La synthèse est publiée. Elle décrit le processus unique et les binaires extraits, la table `kine` et la vie d'une clé avec ses révisions, le superviseur (`/cacerts`, enregistrement, répartiteur de l'agent), containerd embarqué et les `AddOn`.
- [ ] Le tableau de correspondance kubeadm → k3s contient au moins huit lignes.
- [ ] Aucune copie de la base ne reste sur `k3s01` ; la ConfigMap `addon-temoin` et son `AddOn` n'existent plus à la fin.

**Vérification** : `lab/bin/check 18 23`

**Pour aller plus loin** (facultatif) : kine expose aussi une API compatible etcd sur un socket local du serveur. Trouve-le (`ss -lxp`) et interroge-le avec `etcdctl`. Quelles commandes marchent, lesquelles ne marchent pas, et pourquoi ?

---

### M18-E24 — Questions expert : distributions et cycle de vie  `Q` `★★★`

**Objectifs pédagogiques** : vérifier que tu sais raisonner sur les distributions et sur Cluster API au-delà des manipulations : modèles d'état, sécurité, défaillances.
**Prérequis** : M18-E01 à M18-E23.
**Durée indicative** : 1 h 30.

Réponds par écrit, en argumentant. Pour les questions à choix, dis aussi pourquoi les autres options sont fausses.

1. k3s range sa PKI dans la base, chiffrée par une clé dérivée du jeton du serveur ; kubeadm la laisse en fichiers sous `/etc/kubernetes/pki`. Donne un avantage et un risque de chaque approche pour la reconstruction d'un nœud de contrôle, puis pour la fuite d'une sauvegarde.
2. Sur un cluster k3s de trois serveurs, on lance `k3s token rotate`. Quelles opérations deviennent impossibles avec les instantanés etcd **antérieurs** à la rotation, et que faut-il conserver ?
3. QCM. Tu dois restaurer un cluster RKE2 de trois serveurs. Quelle séquence est correcte ?
   - a) `--cluster-reset` sur les trois serveurs avec le même instantané, puis démarrage simultané ;
   - b) arrêt des trois serveurs et de leurs conteneurs, `--cluster-reset` sur un seul, démarrage de celui-ci, puis les deux autres vidés de leur base et démarrés un par un ;
   - c) `--cluster-reset` sur un serveur pendant que les deux autres continuent de tourner pour garder le quorum ;
   - d) restauration PBS des trois VMs à la même heure.
4. Talos n'a pas de SSH. Cite trois situations d'astreinte où c'est un avantage, et deux où c'est un inconvénient. Comment l'équipe s'organise-t-elle pour ces deux dernières (accès console, paquet de secrets, nœud de secours) ?
5. Pourquoi une `Machine` Cluster API n'est-elle jamais « réparée en place » ? Donne deux conséquences sur la conception des images de nœud et une sur les données locales des nœuds.
6. Un `MachineHealthCheck` a `unhealthyLessThanOrEqualTo: 40%` sur un `MachineDeployment` de 2 machines. Une machine tombe. Que se passe-t-il, et pourquoi ? Même question avec 5 machines dont 3 tombent.
7. Le cluster de gestion `k3s01` est perdu pendant une semaine. Que deviennent `capi-essai`, ses certificats (rotation du KCP), une machine qui tombe pendant ce temps, et l'expiration du kubeconfig stocké dans le Secret `capi-essai-kubeconfig` ?
8. QCM. Pourquoi le gabarit CAPMOX monte-t-il `super-admin.conf` dans kube-vip pendant `kubeadm init`, et plus ensuite ?
   - a) parce que kube-vip a besoin des droits `system:masters` en permanence ;
   - b) parce que, pendant l'init, le RBAC qui donne ses droits à `admin.conf` (groupe `kubeadm:cluster-admins`) n'existe pas encore, et kube-vip doit déjà porter la VIP pour que l'API soit joignable ;
   - c) parce que `admin.conf` n'est créé qu'après l'init ;
   - d) parce que kube-vip ne sait pas lire un kubeconfig à certificat client.
9. Deux fournisseurs d'infrastructure dans un même cluster de gestion (E16). Qu'est-ce qui lie leurs versions ? Que vérifies-tu dans `metadata.yaml` et dans `go.mod` d'un fournisseur avant de l'installer, et que fais-tu si les deux sont incompatibles ?
10. RKE2 avec le profil `cis` vérifie les paramètres noyau au démarrage, mais ne les pose pas. Pourquoi ce choix de conception ? Qu'aurait-on perdu si RKE2 les avait posés lui-même ?
11. kine fait d'une base SQL un magasin compatible etcd. Quelles propriétés d'etcd sont plus difficiles à garantir avec PostgreSQL ou MySQL en base externe (pense *watch*, révisions, compactage, haute disponibilité), et dans quel cas choisirais-tu quand même une base externe pour l'agence de Lyon ?
12. Tu dois proposer une montée de version de l'agence de Lyon (k3s, trois serveurs) par system-upgrade-controller. Écris le plan (deux `Plan`), et dis ce qui empêche la montée de casser le quorum.

Auto-évaluation : réponses argumentées dans le corrigé.
