# Module 04 — Corrigé du palier 3 : Production

> ⚠️ Corrigé — à lire après avoir cherché.

Points non testés en conditions réelles (signale tes retours) : les playbooks Molecule `create.yml`/`destroy.yml` et la flotte de l'E25 ont été validés (syntaxe, ansible-lint profil `production`, expressions Jinja sur des réponses d'API réalistes, garde-fous) mais pas contre un vrai Proxmox VE 9 ; la liste exacte des privilèges du rôle `WBAnsible` (en particulier la visibilité du nœud par `GET /nodes` sans `Sys.Audit`) ; l'option GitLab ≥ 18.1 d'accès des pipelines de MR aux variables protégées ; les droits des fichiers de variables CI de type fichier sur `runner01`. Semaphore UI 2.19.16 (configuration, TLS intégré, CLI `users`, jetons, API) a été essayé sur une base SQLite locale, pas avec PostgreSQL ni à travers l'interface. Ils sont signalés « ⚠️ à vérifier » à l'endroit concerné.

Les fichiers de solution sont dans [`fichiers/`](fichiers/) : un dossier par exercice, qui reproduit l'arborescence du projet `plateforme/ansible` (`fichiers/M04-EXX/ansible/…`) ou de `plateforme/medisphere` (`fichiers/M04-EXX/medisphere/…`).

---

### M04-E24 — Molecule : tester un rôle sur des VMs éphémères

**Solution**

*1. Le jeton.* Appels nécessaires et privilège exigé par l'API de Proxmox VE 9 (section *permissions* de chaque chemin) :

| Appel | Chemin | Privilège |
|---|---|---|
| Lister les VMs et templates | `GET /cluster/resources` | `VM.Audit` (une VM n'apparaît que si on l'a) |
| Cloner | `POST /nodes/{node}/qemu/{vmid}/clone` | `VM.Clone` sur le template ; `VM.Allocate` sur le nouveau VMID **ou** le pool ; `Datastore.AllocateSpace` sur le stockage ; `SDN.Use` sur le VNet utilisé |
| Étiquettes, notes, `onboot` | `PUT …/config` (`tags`, `description`, `onboot`) | `VM.Config.Options` |
| Mémoire, cœurs | `PUT …/config` (`memory`, `cores`) | `VM.Config.Memory`, `VM.Config.CPU` |
| cloud-init | `PUT …/config` (`ciuser`, `sshkeys`, `ipconfig0`, `ciupgrade`) | `VM.Config.Cloudinit` |
| Démarrer, arrêter | `POST …/status/start`, `…/stop` | `VM.PowerMgmt` (le lecteur cloud-init est régénéré au démarrage : `Datastore.AllocateSpace`) |
| Adresse par l'agent | `GET …/agent/network-get-interfaces` | `VM.GuestAgent.Audit` (ou `Unrestricted`, beaucoup trop large) |
| Supprimer | `DELETE /nodes/{node}/qemu/{vmid}` | `VM.Allocate` |

```
root@pve01:~# pveum role modify WBAnsible --append 1 --privs "VM.Clone,VM.Allocate,VM.Config.Options,VM.Config.Memory,VM.Config.CPU,VM.Config.Cloudinit,VM.PowerMgmt,VM.GuestAgent.Audit,Datastore.AllocateSpace,SDN.Use"
root@pve01:~# for c in '--users wb-ansible@pve' '--tokens wb-ansible@pve!ansible'; do
>   pveum acl modify /storage/local-nvme --roles WBAnsible $c
>   pveum acl modify /sdn/zones/lab/vsandbox --roles WBAnsible $c
> done
root@pve01:~# pveum user token permissions wb-ansible@pve ansible --path /pool/lab
```

L'ACL sur `/pool/lab` (E13) couvre les templates (dans le pool depuis M03) et les instances (créées avec `pool=lab`). Avec la séparation des privilèges, chaque ACL est posée pour l'utilisateur **et** pour le jeton : les droits effectifs sont l'intersection. ⚠️ À vérifier sur ta version : `community.proxmox.proxmox_kvm` vérifie l'existence du nœud par `GET /nodes`, qui peut ne lister un nœud qu'aux comptes ayant `Sys.Audit` dessus ; si le module répond « node … does not exist in cluster », ajoute `Sys.Audit` sur `/nodes/<NOEUD>` (lecture de l'état du nœud seulement) et note-le.

Ce que le jeton **ne doit pas** avoir : `VM.Console` (session sur la console des VMs du socle), `VM.GuestAgent.Unrestricted` (exécution de commandes root dans **toutes** les VMs du pool, socle compris, par l'agent), `Sys.Modify`, `Permissions.Modify`. Rappel : le pool `lab` contient aussi le socle ; ce jeton peut donc arrêter ou supprimer `gw01`. C'est la raison d'être des garde-fous de `destroy.yml` (et une limite à écrire dans le registre des secrets ; une ACL par VMID, `/vms/2045` à `/vms/2049`, serait plus étroite mais ne couvre pas le clonage depuis un template qui change de VMID chaque semaine).

*2. Structure* (fichiers complets dans [`fichiers/M04-E24/ansible/`](fichiers/M04-E24/ansible/)) :

```
.config/molecule/config.yml            base commune, fusionnée sous chaque molecule.yml
molecule/_commun/create.yml            clonage, cloud-init, démarrage, adresse, SSH
molecule/_commun/prepare.yml           fin de cloud-init, cache APT
molecule/_commun/destroy.yml           suppression avec garde-fous
molecule/_commun/menage.yml            instances orphelines (planifié en E27)
molecule/_commun/inventaire/00-groupes.yml, group_vars/molecule.yml
molecule/base/{molecule.yml, converge.yml, verify.yml, inventaire/hosts.yml}
molecule/ssh_durci/{…}
```

Molecule 26 lit `.config/molecule/config.yml` à la racine du dépôt Git et le fusionne sous chaque `molecule.yml` ; les chemins de `ansible: playbooks:` sont relatifs au dossier du scénario, d'où `../_commun/create.yml`. L'approche ansible-native : pas de section `platforms`, un inventaire Ansible ordinaire passé par `ansible: executor: args: ansible_playbook: [--inventory=…]` (deux sources : `molecule/_commun/inventaire/`, qui porte les `group_vars` du groupe `molecule`, et l'inventaire du scénario, qui déclare l'instance et son VMID). Les variables `${MOLECULE_PROJECT_DIRECTORY}` et `${MOLECULE_SCENARIO_DIRECTORY}` sont substituées par Molecule.

Ajout au `.gitignore` du projet :

```
# Molecule (M04-E24) : adresses écrites par create.yml, effacées par destroy.yml
molecule/*/inventaire/host_vars/*/execution.yml
```

*3. `create.yml`* : [`molecule/_commun/create.yml`](fichiers/M04-E24/ansible/molecule/_commun/create.yml). Points clés :
- l'image se choisit par étiquettes au moment du test (`gold` + `debian13` + `current`, exactement une) : le VMID du template change chaque semaine (M03) ;
- **clone lié** (`full: false`) : quelques secondes au lieu d'une copie complète, conforme au contrat de consommation des images (« clone lié : VMs éphémères seulement, détruites dans l'heure », `docs/socle/images.md`) ; tant que l'instance existe, la rotation des images (M03-E16) refuse de supprimer son template — c'est voulu ;
- `update: true` après le clonage : **remplace** les étiquettes héritées (`gold;debian13;current` deviendraient celles d'une VM ordinaire : un inventaire dynamique la classerait parmi les images), pose `ciuser`, une clé publique **générée pour le scénario** (`ssh-keygen` dans le dossier éphémère), `ipconfig0=ip=dhcp`, `ciupgrade: false` (on teste l'image publiée, pas une mise à niveau au démarrage) ;
- le VNet n'est pas modifié (le changer exigerait `update_unsafe`) : il est **vérifié** (`bridge=vsandbox`) ;
- l'adresse vient de l'agent : `proxmox_vm_info` avec `config: current` **et** `network: true` (le code du module n'interroge l'agent que si la configuration est demandée et que la VM tourne ; tant que l'agent ne répond pas, il renvoie une liste vide avec un avertissement : d'où `until`/`retries`) ;
- l'adresse est **écrite** dans `inventaire/host_vars/<instance>/execution.yml` : `converge`, `idempotence`, `verify` sont des exécutions séparées d'`ansible-playbook`, qui relisent l'inventaire sur disque ; un `add_host` ne survivrait pas à `create.yml` (c'est aussi ce que lisent `molecule login` et `molecule list`).

Exemple de déroulement :

```
admin@adm01:~/src/ansible$ set -a; . ~/.config/workbook/pve-ansible.env; set +a
admin@adm01:~/src/ansible$ uv run molecule test -s base
INFO     Found config file /home/admin/src/ansible/.config/molecule/config.yml
CRITICAL 'molecule/default/molecule.yml' glob failed.  Exiting.
INFO     default scenario not found, disabling shared state.
INFO     [base > destroy] Executing
…
TASK [Résumé] ******************************************************************
ok: [localhost] => (item=m04-mol-base) => {
    "msg": "m04-mol-base : VMID 2045, 10.10.99.137, depuis deb13-gold-20261005-1 (9012)"
}
INFO     [base > converge] Executed: Successful
INFO     [base > idempotence] Executed: Successful
INFO     [base > verify] Executed: Successful
INFO     [base > destroy] Executed: Successful
```

La ligne `CRITICAL … glob failed` est sans conséquence : Molecule cherche un scénario nommé `default` pour l'état partagé, n'en trouve pas, et continue. Ordres de grandeur sur `pve01` : création 40 à 70 s (clone lié, démarrage, agent, SSH), prepare 15 à 30 s, converge et idempotence 1 à 2 min chacun selon le rôle, destroy 5 à 10 s.

*4. `destroy.yml`* : [`molecule/_commun/destroy.yml`](fichiers/M04-E24/ansible/molecule/_commun/destroy.yml). Il lit l'état de chaque VMID (liste vide si la VM n'existe pas : rien à faire, succès), puis **refuse** si la VM n'est pas dans 2045-2049, est un template, ou ne porte ni le nom de l'instance ni l'étiquette `molecule` ; sinon `state: absent`, `force: true` (arrêt brutal : c'est une instance jetable), `purge: true` (retirée des tâches de sauvegarde et de réplication). Il échoue aussi si l'accès à l'API manque, plutôt que de « réussir » sans rien détruire. Test du garde-fou :

```
admin@adm01:~$ ssh pve01 qm create 2047 --name essai-garde-fou --pool lab --memory 128
admin@adm01:~/src/ansible$ cp -r molecule/ssh_durci /tmp/scenario-pf && sed -i 's/m04-mol-ssh/m04-mol-pf/; s/2046/2047/' /tmp/scenario-pf/inventaire/hosts.yml
```

Plus simple : crée temporairement `molecule/pare_feu/` (inventaire `m04-mol-pf`, VMID 2047) et lance `uv run molecule destroy -s pare_feu` : l'assertion échoue avec « REFUS : le VMID 2047 (« essai-garde-fou ») n'est pas une instance Molecule de ce scénario ». Puis `ssh pve01 qm destroy 2047`.

*5. `prepare.yml`* : `cloud-init status --wait` rend 0 (terminé sans erreur), 1 (erreur) ou 2 (terminé avec des erreurs récupérables, « degraded », depuis cloud-init 23.4) ; le playbook s'arrête sur 1 et signale 2. Puis `apt update` avec `cache_valid_time`.

*6. Scénarios.* `converge.yml` applique le rôle sans variable. `verify.yml` lit l'état : `timedatectl show --property=Timezone --value`, `chronyc -n sources` (une seule source, la passerelle `ansible_facts['default_ipv4']['gateway']`, ici 10.10.99.1), `systemd-analyze cat-config systemd/journald.conf` (configuration **effective**, fichiers `.d` compris), `apt-config dump APT::Periodic::Unattended-Upgrade`, `sshd -T` (configuration effective, après `Include` et ordre des fichiers), et pour `ssh_durci` une tentative d'authentification par mot de passe **depuis le contrôleur** (`delegate_to: localhost`) qui doit échouer sur `Permission denied (publickey)`. Les valeurs attendues sont celles du rôle `base` de l'E10 : adapte-les si ton rôle a d'autres paramètres.

*7. Interruption.* Un `Ctrl+C` pendant `converge` arrête Molecule sans exécuter `destroy` : la VM 2045 reste, avec son `execution.yml`. `uv run molecule destroy -s base` nettoie (c'est le premier pas de `molecule test` de toute façon) ; en CI, `after_script` le fait (E27), et `menage.yml` rattrape les cas restants.

*8. Idempotence.* Avec `ansible.builtin.command: /bin/true` sans `changed_when` dans `base`, l'étape `idempotence` échoue :

```
CRITICAL Idempotence test failed because of the following tasks:
*  => base : Tâche de démonstration
```

*9.* `git status` propre (règle `.gitignore`), MR, fusion.

**Explications**

Molecule n'est qu'un orchestrateur de séquence : il appelle `ansible-playbook` sur des playbooks dans un ordre donné, avec un `ansible.cfg` qu'il génère (`ANSIBLE_CONFIG` pointe vers son dossier éphémère, d'où `roles_path` et `collections_path` repris dans `cfg`). L'étape `idempotence` rejoue `converge` et échoue si une tâche annonce un changement : c'est la vérification la plus rentable d'un rôle. L'étape `verify` doit porter sur l'état observable (ce qu'un auditeur constaterait), pas répéter les tâches du rôle (un test qui relit le fichier que le rôle vient d'écrire ne prouve rien). Les VMs plutôt que des conteneurs : `systemd`, `sshd`, `nftables`, `chrony` et `journald` se comportent dans une VM comme en production, sans `privileged`.

La clé d'hôte : Molecule désactive par défaut `host_key_checking` ; on la réactive, avec `StrictHostKeyChecking=accept-new` et un `UserKnownHostsFile` propre au scénario. La première clé est acceptée (une VM neuve n'a pas d'autre moyen de la publier, sauf à la lire par l'agent), une clé qui **change** en cours de test est refusée, et rien ne pollue `~/.ssh/known_hosts` (les adresses DHCP de `vsandbox` sont réutilisées d'une VM à l'autre : sans fichier dédié, le test suivant échouerait sur « REMOTE HOST IDENTIFICATION HAS CHANGED »).

**Alternatives**
- Pilote `molecule-plugins[docker]` ou `podman` (conteneurs) : bien plus rapide, mais `systemd` et le réseau demandent des contorsions, et on teste autre chose que la production. Vu au module 12.
- Plateformes déclarées (`platforms:` + `instance_config.yml`, approche « pré-ansible-native ») : toujours prise en charge ; moins naturelle pour plusieurs instances et groupes.
- Clone complet : indépendant du template (la rotation peut le supprimer pendant le test), mais une copie de disque à chaque test.
- Testinfra (pytest) comme vérificateur : plus expressif pour les tests complexes, au prix d'une dépendance Python de plus.

**Pièges classiques**
- Oublier que Molecule ignore le `ansible.cfg` du projet : « role 'base' not found », collections introuvables.
- `proxmox_vm_info` avec `network: true` mais sans `config:` : jamais d'adresse, la boucle `until` tourne jusqu'au bout.
- Garder les étiquettes héritées du template : l'instance apparaît comme une image `current` (inventaire dynamique, sélection des images d'OpenTofu au M05 : une VM « current » qui n'est pas un template casse les sélections).
- Une clé SSH commune à tous les tests (celle de `adm01`) : le test passe sur ton poste et échoue en CI.
- `StrictHostKeyChecking=no` « parce que c'est un test » : tu habitues l'équipe à désactiver la vérification, et un test sur une instance usurpée passerait.
- Un `destroy.yml` qui « réussit » sans accès à l'API : la VM reste et le test suivant échoue au clonage.
- `verify.yml` qui lit les fichiers posés par le rôle au lieu de la configuration effective (`sshd -T`, `systemd-analyze cat-config`).

**En production chez MédiSphère**
Tous les rôles du socle ont un scénario ; la CI les lance sur les rôles modifiés (E27) et une fois par semaine sur tous (nouvelle image dorée = nouvel environnement de test). Un scénario Rocky 10 par rôle multi-distribution. Les temps de test sont suivis (module 21) : un rôle dont le test dépasse dix minutes est découpé.

---

### M04-E25 — Mises à jour progressives : `serial` et tolérance aux échecs

**Solution**

Playbook : [`playbooks/maj-progressive.yml`](fichiers/M04-E25/ansible/playbooks/maj-progressive.yml). Structure : un premier play qui écrit la ligne de journal (une fois par exécution), puis le play de mise à jour avec `serial: [1, 2]`, `max_fail_percentage: 0`, `order: sorted`, et pour chaque nœud : `pre_tasks` (drapeau `MAINTENANCE`, attente que le contrôleur voie `503`), `tasks` (nginx, panne simulée, modèles, `flush_handlers`), `post_tasks` (retrait du drapeau, contrôle de santé depuis le contrôleur qui exige `ok <version>`). Handlers : `nginx -t` **puis** rechargement, dans cet ordre de définition.

```
admin@adm01:~/src/ansible$ mkdir -p ~/m04/e25 && cp -r ~/DevOpsPrivateCloud/modules/04-ansible/ressources/M04-E25/* ~/m04/e25/
admin@adm01:~/src/ansible$ set -a; . ~/.config/workbook/pve-ansible.env; set +a
admin@adm01:~/src/ansible$ uv run ansible-playbook ~/m04/e25/flotte.yml -e etat=present
admin@adm01:~/src/ansible$ uv run ansible-playbook -i ~/m04/e25/flotte-hosts.yml playbooks/maj-progressive.yml -e version=1.0
admin@adm01:~/src/ansible$ uv run ansible-playbook -i ~/m04/e25/flotte-hosts.yml playbooks/maj-progressive.yml -e version=2.0
```

Pendant la mise à jour, dans l'autre terminal :

```
admin@adm01:~$ ~/m04/e25/sonde-flotte.sh
14:02:11  10.10.99.42=200(1.0)  10.10.99.43=200(1.0)  10.10.99.44=200(1.0)  | en service : 3/3
14:02:12  10.10.99.42=503  10.10.99.43=200(1.0)  10.10.99.44=200(1.0)  | en service : 2/3
…
14:02:19  10.10.99.42=200(2.0)  10.10.99.43=503  10.10.99.44=503  | en service : 1/3  <<< SOUS LE MINIMUM
```

La dernière ligne n'est **pas** une erreur de la sonde : avec des lots de deux sur trois nœuds, le second lot retire deux nœuds à la fois. Pour garder deux nœuds en service, le lot doit valoir `1` (`serial: 1`) — c'est la première leçon de l'exercice : la taille de lot fixe la capacité minimale pendant la mise à jour. Version retenue pour une flotte de trois : `serial: 1` ; pour une flotte de dix : `[1, "20%"]` avec une capacité dimensionnée pour supporter 20 % de nœuds hors service.

*Expériences* (comportement vérifié avec ansible-core 2.21) :

1. `echec_sur=['m04-web1']` : le canari échoue dans un lot d'un seul hôte ; **tous** les hôtes du lot ont échoué, Ansible arrête le play (« NO MORE HOSTS LEFT »), quel que soit `max_fail_percentage`. `m04-web2` et `m04-web3` ne sont pas touchés ; `m04-web1` reste en maintenance (drapeau posé, pas de remise en service) : il sort de la répartition, c'est le comportement voulu.
2. `echec_sur=['m04-web2']`, lots `[1, 2]` : `max_fail_percentage` est évalué **après chaque tâche**, pas seulement à la fin du lot : dès que `m04-web2` échoue (1 sur 2 = 50 % > 0 %), le play s'arrête. `m04-web3` a exécuté les `pre_tasks` (il est **en maintenance**) mais pas la mise à jour : deux nœuds hors service, un seul sert l'ancienne version. Il faut le remettre en service (relancer avec une version saine).
3. Avec `serial: 1`, `m04-web3` n'est jamais touché (le lot de `m04-web2` ne contient que lui). `any_errors_fatal: true` avec des lots de deux donne ici le même résultat que `max_fail_percentage: 0` ; la différence apparaît avec une tolérance non nulle : `any_errors_fatal` arrête tout dès le premier échec, `max_fail_percentage: 50` laisserait `m04-web3` finir.
4. Lot de trois, un échec : 33,3 % ; `max_fail_percentage: 30` → 33,3 > 30, arrêt ; `max_fail_percentage: 34` → 33,3 < 34, les deux autres nœuds sont mis à jour. Le seuil doit être **dépassé**.
5. `order: shuffle` tire l'ordre des hôtes à chaque exécution (évite que le même nœud soit toujours le canari, ou répartit la charge d'un dépôt) ; `throttle: 1` limite **une tâche** à un hôte à la fois même dans un lot plus grand (téléchargement depuis un miroir, appel à une API à quota, inscription dans un répartiteur qui ne supporte pas les écritures concurrentes) : c'est la tâche `Installer nginx` du corrigé.

Journal : une ligne par exécution grâce au play séparé ; `run_once` dans le play à `serial` s'exécuterait une fois **par lot**.

```
admin@adm01:~$ cat ~/m04/e25/deploiements.log
2026-10-12T14:01:58+0200 version=1.0 operateur=admin cibles=m04-web1,m04-web2,m04-web3
2026-10-12T14:02:10+0200 version=2.0 operateur=admin cibles=m04-web1,m04-web2,m04-web3
```

**Explications**

`serial` découpe un play en plusieurs passes ; `pre_tasks`, rôles, `tasks`, handlers et `post_tasks` s'exécutent intégralement pour un lot avant de passer au suivant. Les échecs se comptent par lot. `max_fail_percentage` arrête le play dès que la proportion d'hôtes en échec **du lot** dépasse la valeur ; `any_errors_fatal` l'arrête au premier échec ; sans l'un ni l'autre, Ansible continue les lots suivants tant qu'un lot n'a pas échoué en entier — exactement ce qu'on ne veut pas pour une mise à jour progressive. Le contrôle de santé fait par le contrôleur (`delegate_to: localhost`) teste le chemin réseau qu'emprunte un client ; le même contrôle fait sur le nœud lui-même (`curl localhost`) passerait même si le pare-feu ou l'écoute étaient faux.

**Alternatives**
- `serial` avec un vrai répartiteur (HAProxy, module 07) et le module `community.general.haproxy` délégué au répartiteur ; ou une sortie de répartition par l'API d'un équilibreur cloud.
- Rolling update porté par l'orchestrateur (Kubernetes `RollingUpdate`, module 14) : le même raisonnement (`maxUnavailable`, `maxSurge`, *readiness probe*).
- Bleu/vert : une seconde flotte complète, bascule d'un coup, retour arrière instantané ; coûte le double de capacité.

**Pièges classiques**
- `serial` en pourcentage arrondi vers le bas (25 % de 3 = 0 → Ansible prend 1) : vérifie la taille réelle des lots dans la sortie.
- Mettre la ligne de journal ou l'annonce dans le play à `serial` avec `run_once` : une fois par lot.
- Contrôler la santé depuis le nœud : faux positif quand l'écoute ou le filtrage sont mauvais.
- Recharger nginx sans `nginx -t` : une configuration invalide arrête le service au lieu de faire échouer la tâche.
- Remettre en service avant d'avoir appliqué les handlers (pas de `flush_handlers`) : le nœud revient avec l'ancienne configuration chargée.
- Oublier qu'un arrêt de play laisse dans le lot courant des nœuds en maintenance qui n'ont pas échoué.

**En production chez MédiSphère**
Capacité calculée pour `N − taille de lot` nœuds ; canari observé plusieurs minutes (taux d'erreur, latence, module 21) avant les lots suivants (`pause` avec durée, ou pipeline en deux étapes) ; procédure de retour arrière écrite (redéployer la version précédente avec le même playbook). Pour le socle, où chaque hôte est unique, `serial: 1` et un ordre explicite (jamais `gw01` en même temps qu'un autre).

---

### M04-E26 — Performances d'Ansible

**Solution**

Fichiers : [`playbooks/mesure-perf.yml`](fichiers/M04-E26/ansible/playbooks/mesure-perf.yml), [`outils/mesurer-perf.sh`](fichiers/M04-E26/ansible/outils/mesurer-perf.sh), [`docs/performances.md`](fichiers/M04-E26/ansible/docs/performances.md) (tableau d'exemple, méthode, lecture), [`ansible.cfg`](fichiers/M04-E26/ansible/ansible.cfg) (état de fin d'E26).

```
admin@adm01:~/src/ansible$ outils/mesurer-perf.sh -l "référence (forks 10)"
  exécution 1/5 : 23.10 s
  …
| référence (forks 10) | 5 | 21.4 | 22.0 | 23.1 |
admin@adm01:~/src/ansible$ ANSIBLE_FORKS=1 outils/mesurer-perf.sh -l "forks=1"
admin@adm01:~/src/ansible$ ANSIBLE_PIPELINING=False outils/mesurer-perf.sh -l "sans pipelining"
admin@adm01:~/src/ansible$ ANSIBLE_SSH_ARGS="-o ControlMaster=no -o ControlPath=none" outils/mesurer-perf.sh -l "sans multiplexage"
admin@adm01:~/src/ansible$ outils/mesurer-perf.sh -l "faits min" -- -e '{"sous_ensemble": ["min"]}'
admin@adm01:~/src/ansible$ outils/mesurer-perf.sh -l "sans faits" -- -e collecte=false
admin@adm01:~/src/ansible$ install -d -m 700 ~/.cache/ansible/faits
admin@adm01:~/src/ansible$ ANSIBLE_CACHE_PLUGIN=jsonfile ANSIBLE_CACHE_PLUGIN_CONNECTION=~/.cache/ansible/faits ANSIBLE_GATHERING=smart outils/mesurer-perf.sh -l "cache jsonfile + smart"
admin@adm01:~/src/ansible$ ANSIBLE_STRATEGY=free outils/mesurer-perf.sh -l "stratégie free"
admin@adm01:~/src/ansible$ ANSIBLE_CALLBACKS_ENABLED=ansible.posix.timer,ansible.posix.profile_tasks \
>   uv run ansible-playbook -i inventories/lab/hosts.yml -i ~/m04/e25/flotte-hosts.yml playbooks/mesure-perf.yml
```

`gather_subset` de la collecte **implicite** passe par `module_defaults` sur `ansible.builtin.setup` : un `setup` explicite serait exécuté à chaque fois et ignorerait le cache (`gathering = smart` ne concerne que la collecte implicite du play).

*Mécanismes* (détail dans `docs/performances.md`) : `forks` = nombre d'hôtes traités en parallèle par tâche (stratégie `linear` : tous les hôtes finissent la tâche avant la suivante) ; *pipelining* = le module passe par l'entrée standard de `python3` dans **une** commande SSH au lieu de plusieurs (création du dossier temporaire, copie, exécution, nettoyage) ; multiplexage = une connexion maître par hôte réutilisée par toutes les tâches (`ControlPersist=60s` par défaut) ; collecte de faits = un module `setup` par hôte, le plus lourd de tous ; cache `jsonfile` = un fichier par hôte, relu tant que `fact_caching_timeout` n'est pas atteint.

*Faits périmés* : avec le cache, change le `/etc/motd` d'un nœud : aucun fait ne le reflète (le motd n'est pas un fait) ; change plutôt son adresse ou installe un noyau : `ansible_facts['default_ipv4']` et `ansible_facts['kernel']` restent ceux du cache jusqu'à expiration ou `--flush-cache`. D'où un délai court (2 h) et la règle : en CI, jamais de cache (E27).

**Explications**

À cinq ou huit hôtes, le temps est dominé par les allers-retours SSH par tâche et par la collecte de faits, pas par le travail des modules : *pipelining* et multiplexage divisent le nombre de connexions, le cache évite la collecte. `forks` n'aide qu'au-delà du nombre d'hôtes traités ensemble ; il coûte de la mémoire sur le contrôleur (un processus par *fork*). La stratégie `free` gagne quand les hôtes sont de vitesse différente (le plus lent ne bloque plus les autres) ; elle rend l'ordre non déterministe et ne convient pas à un `site.yml` où l'ordre compte.

**Alternatives**
- Mitogen (stratégie de remplacement du transport) : gains annoncés importants ; sa compatibilité suit ansible-core avec retard — vérifie la matrice avant de l'adopter, et garde un moyen de s'en passer.
- `async` + `poll: 0` puis `async_status` : pour une tâche longue (mise à jour de paquets sur 50 hôtes).
- Cache de faits Redis (`community.general.redis`) partagé entre contrôleurs ; inutile à cette échelle.

**Pièges classiques**
- Changer plusieurs paramètres à la fois : on ne sait plus lequel agit.
- Mesurer une seule fois : la première exécution ouvre les connexions maîtres, les suivantes en profitent.
- `ANSIBLE_SSH_ARGS="-o ControlPersist=…"` sans `ControlMaster=auto` : plus de multiplexage du tout.
- Croire que `gather_subset` se règle encore dans `ansible.cfg` (supprimé de la configuration).
- *Pipelining* avec `requiretty` dans `sudoers` (CentOS ancien) : échec de `become`.
- Laisser `profile_tasks` actif en permanence : journaux CI illisibles.

**En production chez MédiSphère**
Une mesure de référence de `site.yml` (callback `timer`) suivie dans le temps : une dérive de durée est un symptôme (DNS lent, hôte saturé, rôle qui grossit — panne de l'E41). Au-delà de 50 hôtes : inventaire découpé par service, `site.yml` par périmètre, contrôleur dimensionné (CPU et mémoire pour les *forks*).

---

### M04-E27 — Chaîne CI Ansible : lint, Molecule, `--check` en MR, application contrôlée

**Solution**

Fichiers : [`.gitlab-ci.yml`](fichiers/M04-E27/ansible/.gitlab-ci.yml), [`outils/ci-secrets.sh`](fichiers/M04-E27/ansible/outils/ci-secrets.sh), [`outils/recap-ansible.sh`](fichiers/M04-E27/ansible/outils/recap-ansible.sh), [`outils/cles-hote-socle.sh`](fichiers/M04-E27/ansible/outils/cles-hote-socle.sh), [`playbooks/controleurs-ansible.yml`](fichiers/M04-E27/ansible/playbooks/controleurs-ansible.yml), [`inventories/lab/host_vars/adm01/main.yml`](fichiers/M04-E27/ansible/inventories/lab/host_vars/adm01/main.yml), règles attendues sur `gw01` : [`gw01-flux-ansible.nft`](fichiers/M04-E27/gw01-flux-ansible.nft).

*1. Identité.*

```
admin@adm01:~$ ssh-keygen -t ed25519 -C ansible-ci -N "" -f ~/.config/workbook/ansible-ci
```

(Sans phrase de passe : c'est une identité de machine, protégée par GitLab ; la copie de `adm01` est supprimée une fois la variable CI créée.) Dans `ms_cles_admin` (E10/E14 : une liste de lignes au format `authorized_keys`, consommée par `base_utilisateurs`), une entrée de plus :

```yaml
ms_cles_admin:
  - "ssh-ed25519 <CLE-PUBLIQUE-ADM01> admin@adm01"
  - 'from="10.10.20.15" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA…XXXX ansible-ci'
```

(Les options comme `from=` se placent en tête de ligne, comme dans le fichier `authorized_keys` lui-même : `ansible.posix.authorized_key` les accepte telles quelles dans `key`. Sur `adm01`, `host_vars/adm01/base.yml` remplace `ms_cles_admin` : il doit lui aussi recevoir la ligne `ansible-ci`.) Variables CI (*Settings > CI/CD > Variables*) : `ANSIBLE_CI_SSH_KEY` (type fichier, protégée ; une clé multiligne ne peut pas être masquée), `VAULT_PASS_LAB` (fichier, protégée, masquée si ton mot de passe satisfait les règles de masquage), `PROXMOX_URL`, `PROXMOX_USER`, `PROXMOX_TOKEN_ID` (protégées), `PROXMOX_TOKEN_SECRET` (protégée, masquée et cachée).

`adm01` : `ansible_connection` devient une expression évaluée sur le contrôleur, `local` seulement si le contrôleur **est** `adm01`. Sans cela, `appliquer` exécuterait sur `runner01` les tâches prévues pour `adm01` (sshd, utilisateurs, outils), en local.

*2. Flux.* Deux règles, rendues par le rôle `pare_feu` à partir de sa description des flux, appliquées depuis `adm01` avec le filet anti-coupure :

```
iifname $V_INFRA ip saddr { $RUNNER01, $SEM01 } tcp dport 22 accept      (input : SSH vers gw01)
iifname $V_INFRA ip saddr { $RUNNER01, $SEM01 } oifname $V_MGMT ip daddr $ADM01 tcp dport 22 accept   (forward)
```

(`SEM01` arrive en E28 ; tu peux n'écrire que `runner01` maintenant.) Tests depuis `runner01` : `timeout 5 bash -c 'exec 3<>/dev/tcp/10.10.10.1/22'`, idem pour 10.10.10.10. Les autres hôtes du socle sont dans le VLAN de `runner01` : pas de règle. Matrice des flux : deux lignes « runner01 → gw01 / adm01, TCP 22, CI Ansible (M04-E27) ».

*3. Clés d'hôte.* `adm01` connaît déjà toutes les clés d'hôte du socle (confiance établie en M00 et M01, en comparant les empreintes à la console). [`outils/cles-hote-socle.sh`](fichiers/M04-E27/ansible/outils/cles-hote-socle.sh) récupère la clé ed25519 annoncée par chaque hôte et la **compare** à celle de `~/.ssh/known_hosts` (`ssh-keygen -F`, qui retrouve aussi les entrées hachées) ; il n'écrit `inventories/lab/known_hosts` que si tout concorde. Ce fichier public est versionné (un changement de clé d'hôte passe par une MR) et installé dans `/etc/ssh/ssh_known_hosts` de `runner01` par `playbooks/controleurs-ansible.yml`.

```
admin@adm01:~/src/ansible$ outils/cles-hote-socle.sh --ecrire
OK  adm01 (10.10.10.10) SHA256:4pM2…
OK  dns01 (10.10.20.10) SHA256:Qn8y…
OK  git01 (10.10.20.12) SHA256:7cVx…
OK  gw01 (10.10.10.1) SHA256:hZ1k…
OK  runner01 (10.10.20.15) SHA256:Wb3r…
Écrit : inventories/lab/known_hosts (à relire et committer).
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/controleurs-ansible.yml --limit runner01 --diff
```

*4. Le pipeline.* Lecture du fichier par blocs :
- `.ansible` : `uv sync --locked`, collections de `collections/requirements.yml` (le `git clean` de chaque job efface `.venv` et les collections ignorées : le cache de `uv` rend `uv sync` rapide ; les collections se retéléchargent, ~15 s) ;
- `.socle` : ajoute `outils/ci-secrets.sh` (copie de la clé en 600 avec saut de ligne final garanti, `ANSIBLE_PRIVATE_KEY_FILE`, `ANSIBLE_VAULT_IDENTITY_LIST=lab@$VAULT_PASS_LAB` qui remplace le chemin de `adm01` écrit dans `ansible.cfg`) et un `after_script` qui efface la copie ;
- `ansible-lint` : rapport Code Climate pour le widget « Code Quality » de la MR, et lisible dans le journal ;
- `secrets-indisponibles` : dans une MR issue d'une branche non protégée, échoue en expliquant ;
- `molecule:<rôle>` : `rules:changes` sur le rôle, son scénario et l'outillage commun, `resource_group: molecule-$SCENARIO`, `after_script` qui détruit l'instance (y compris si le job est annulé, GitLab ≥ 17.0 ; pas après un dépassement de délai, d'où `molecule-menage` planifié avec `PLANIF=menage-molecule`) ;
- `check-socle` : `--check --diff`, journal et JUnit en artefacts 90 jours, échec si `outils/recap-ansible.sh` rend 2 ou 3 (hôte injoignable, tâche en erreur, exécution interrompue) ; des changements sont attendus ;
- `appliquer` : manuel, `main`, `environment: lab/socle` (palier `production`), `resource_group: socle-lab`, `interruptible: false`, puis seconde passe en `--check` qui doit rendre 0 ; variable de job manuel `LIMITE` pour une ré-application ciblée (ADR-0040) ; artefacts conservés un an (preuve d'audit).

Variables d'environnement communes : `ANSIBLE_CACHE_PLUGIN=memory` et `ANSIBLE_GATHERING=implicit` (faits frais), `ANSIBLE_NOCOLOR=1` (journaux analysables), `JUNIT_OUTPUT_DIR`.

*5. Branches.* *Settings > Repository > Protected branches* : `conf/*`, *Allowed to merge* : Maintainers, *Allowed to push and merge* : Maintainers (ou Developers + Maintainers selon l'équipe). *Settings > CI/CD > Variables* : cocher *Allow merge request pipelines to access protected variables and runners* (GitLab ≥ 18.1 ; ⚠️ à vérifier sur ta version : intitulé et emplacement). Conditions : branche source et cible protégées, même projet, et l'auteur du pipeline peut fusionner dans la cible. **Qui peut lire la clé `ansible-ci` désormais** : tout Maintainer du projet (variables), et quiconque peut pousser du code exécuté dans un job d'une branche protégée — donc tout compte autorisé à pousser sur `conf/*`. C'est la raison de limiter ce droit aux Maintainers, et de la restriction `from=10.10.20.15` (la clé volée ne sert que depuis `runner01`).

*6. La preuve.* Une MR `conf/motd-socle` : `ansible-lint` vert, `molecule:base` vert, `check-socle` montre le *diff* du motd sur les cinq hôtes. Après fusion, pipeline de `main` : `appliquer` attend une action (« manual ») ; lancé, il applique, puis la convergence rend `changed=0`. Une MR depuis `essai` (non protégée) : `secrets-indisponibles` échoue avec son message, aucun autre job du socle. Deux `appliquer` : le second affiche « Waiting for resource: socle-lab ».

*7.* Registre des secrets : `ansible-ci` (clé ed25519, portée : `admin` sur le socle depuis 10.10.20.15, détenteur : variable CI protégée, rotation : 6 mois ou départ d'un Maintainer, révocation : retrait de la clé du rôle `base` + application).

**Explications**

Le pipeline sépare ce qui ne demande aucun secret (lint, gabarits communs) de ce qui en demande (Molecule, aperçu, application). Dans GitLab CE, la protection d'un environnement n'existe pas ; on l'obtient par trois mécanismes : la branche protégée (un job manuel de `main` ne peut être lancé que par qui peut fusionner dans `main`), les variables protégées (absentes ailleurs) et, en E30, la **portée d'environnement** des variables (disponible au niveau projet dans CE). `resource_group` sérialise les jobs du même groupe tous pipelines confondus. L'aperçu en MR n'est fiable que si les rôles savent fonctionner en `--check` (E29). L'application suivie d'un `--check` à zéro prouve à la fois le succès et l'idempotence sur l'infrastructure réelle.

Le risque principal à connaître : un pipeline de MR exécute le code **de la branche** ; si les secrets y sont disponibles, celui qui peut pousser la branche peut les lire (en modifiant `.gitlab-ci.yml`). D'où les branches `conf/*` protégées : on ne donne les secrets qu'à du code poussé par des personnes de confiance, et relu avant fusion.

**Alternatives**
- Pas d'aperçu en MR, seulement sur `main` avant `appliquer` : plus simple, mais le relecteur ne voit pas l'effet du changement.
- Secrets posés sur `runner01` (fichiers lisibles par `gitlab-runner`) : disponibles pour **tout** job de **tout** projet sur ce runner. Refusé.
- Runner dédié et « protégé » (ne prend que les jobs des branches protégées) pour le socle, et un autre pour le reste ; utile quand d'autres équipes partageront `runner01`.
- GitLab Premium : environnements protégés avec approbation (deux personnes pour appliquer).

**Pièges classiques**
- `ansible_connection: local` pour `adm01` appliqué depuis `runner01`.
- Clé privée collée sans saut de ligne final, ou lisible par d'autres : `Load key "…": invalid format` / `UNPROTECTED PRIVATE KEY FILE`.
- `host_key_checking = False` « pour la CI » : n'importe quelle machine qui répond à 10.10.10.1 reçoit la configuration et les secrets.
- `ssh-keyscan` sans comparaison : on publie la clé d'un éventuel imposteur.
- `rules:changes` sans les fichiers communs (`molecule/_commun/`, `uv.lock`) : une mise à jour d'outillage qui casse les tests passe inaperçue.
- `when: manual` sur un job qui a des `rules` (il se met dans la règle).
- Oublier que `after_script` tourne dans un nouveau shell (refaire `uv run`).
- Redémarrer `gitlab-runner` depuis un job qui tourne sur `runner01` (rôle `gitlab_runner`) : le job est tué au milieu. Le runner relit `config.toml` tout seul ; un rechargement (`SIGHUP`) suffit, jamais un redémarrage pendant un job.

**En production chez MédiSphère**
Runner dédié au socle, protégé ; approbation à deux pour `appliquer` (Premium ou outil externe) ; artefacts d'application conservés selon la politique d'archivage HDS ; alerte si `appliquer` n'a pas tourné depuis 30 jours alors que `main` a avancé (changements fusionnés mais jamais appliqués).

---

### M04-E28 — Semaphore UI : exécuter Ansible avec traçabilité

**Solution**

Fichiers : rôle [`roles/semaphore/`](fichiers/M04-E28/ansible/roles/semaphore/), [`playbooks/sem01.yml`](fichiers/M04-E28/ansible/playbooks/sem01.yml), [`inventories/lab/host_vars/sem01/main.yml`](fichiers/M04-E28/ansible/inventories/lab/host_vars/sem01/main.yml) et le modèle en clair [`vault.yml.exemple`](fichiers/M04-E28/ansible/inventories/lab/host_vars/sem01/vault.yml.exemple), création de la VM [`creer-sem01.sh`](fichiers/M04-E28/creer-sem01.sh), certificat [`pki-provisoire-sem01.cnf`](fichiers/M04-E28/pki-provisoire-sem01.cnf).

*1. La VM.*

```
admin@adm01:~$ ~/DevOpsPrivateCloud/modules/04-ansible/corrige/fichiers/M04-E28/creer-sem01.sh
admin@dns01:~$ echo 'host-record=sem01.par1.medisphere.internal,sem01,10.10.20.41' | sudo tee -a /etc/dnsmasq.d/medisphere.conf && sudo systemctl restart dnsmasq
```

(Si le rôle `dnsmasq` existe déjà dans ton projet, ajoute l'enregistrement à ses variables plutôt qu'à la main.) Inventaire statique :

```yaml
    role_semaphore:
      hosts:
        sem01:
          ansible_host: 10.10.20.41
```

`~/.ssh/config` : alias `sem01` (HostName 10.10.20.41, User admin). Puis `uv run ansible-playbook playbooks/sem01.yml --tags …` pour `base` et `ssh_durci` (ou tout le playbook une fois le rôle `semaphore` prêt).

*2. Le certificat.* Ajoute les sections de [`pki-provisoire-sem01.cnf`](fichiers/M04-E28/pki-provisoire-sem01.cnf) à `~/pki-provisoire/pki-provisoire.cnf`, puis, comme pour `git01` :

```
admin@adm01:~/pki-provisoire$ (umask 077; openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out sem01.key)
admin@adm01:~/pki-provisoire$ openssl req -new -config pki-provisoire.cnf -section req_sem01 -key sem01.key -out sem01.csr
admin@adm01:~/pki-provisoire$ openssl x509 -req -in sem01.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 397 -sha256 \
>   -extfile pki-provisoire.cnf -extensions v3_serveur_sem01 -out sem01.crt
admin@adm01:~/pki-provisoire$ cat sem01.crt ca.crt > ~/src/ansible/inventories/lab/files/sem01-chaine.crt
```

La clé `sem01.key` rejoint `host_vars/sem01/vault.yml` (`vault_semaphore_tls_cle`), qui est chiffré avant tout commit.

*3. Le rôle.* Lecture des choix :
- paquet : `get_url` avec `checksum: sha256:…` (l'empreinte du fichier `semaphore_2.19.16_checksums.txt` : `56c4ac99…85b8`) puis `apt: deb:` ; le paquet ne dépend que de `git` et ne contient que `/usr/bin/semaphore` ;
- PostgreSQL : des `psql` en lecture décident, des `psql` en écriture agissent seulement si besoin ; le mot de passe passe par `PGPASSWORD` (environnement) pour le test et par l'**entrée standard** pour `ALTER ROLE`, jamais en argument (visible dans `ps` par tous les comptes) ; tâches en `no_log` ;
- `config.json` (modèle [`config.json.j2`](fichiers/M04-E28/ansible/roles/semaphore/templates/config.json.j2)) en 0640 `root:semaphore`, avec `diff: false` : un `--diff` afficherait les clés de chiffrement dans un journal ; `mfa.totp` (et non `auth.totp` comme dans un exemple ancien de la documentation : le code 2.19 lit `mfa`) ; `env_vars.ANSIBLE_HOST_KEY_CHECKING: "True"` (voir 4) ;
- TLS intégré : `port: ":443"`, `tls.enabled`, `cert_file`, `key_file`, `http_redirect_port: 80` (redirection 307 vers `web_host`) ;
- unité systemd ([`semaphore.service.j2`](fichiers/M04-E28/ansible/roles/semaphore/templates/semaphore.service.j2)) : `User=semaphore`, `AmbientCapabilities=CAP_NET_BIND_SERVICE` (et rien d'autre dans `CapabilityBoundingSet`), `NoNewPrivileges`, `ProtectSystem=strict` avec `/var/lib/semaphore` en écriture (dépôts clonés, `~/.ansible`, `~/.ssh/known_hosts`) ;
- administrateur : `semaphore users list` puis `semaphore users add` seulement s'il manque (la CLI n'accepte le mot de passe qu'en argument : exposition brève dans `ps`, assumée sur une VM à un seul administrateur, `no_log`, mot de passe changé à la première connexion).

Deux passages : le second rend `changed=0` et ne redémarre rien.

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/sem01.yml --diff
…
sem01     : ok=41   changed=19   unreachable=0    failed=0    skipped=2    rescued=0    ignored=0
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/sem01.yml
sem01     : ok=39   changed=0    unreachable=0    failed=0    skipped=4    rescued=0    ignored=0
admin@adm01:~$ curl -sS https://sem01.par1.medisphere.internal/api/ping
pong
admin@adm01:~$ curl -sSI http://sem01.par1.medisphere.internal/ | head -2
HTTP/1.1 307 Temporary Redirect
Location: https://sem01.par1.medisphere.internal/
```

*4. Lecture du code* (étiquette `v2.19.16`) :
- `db_lib/AnsiblePlaybook.go`, `makeCmd` : Semaphore ajoute `ANSIBLE_HOST_KEY_CHECKING=False` à l'environnement de **chaque** `ansible-playbook`, puis les variables de `env_vars` de `config.json`, puis celles du groupe de variables. En Go, quand une variable est présente plusieurs fois, la **dernière** l'emporte : `env_vars: {"ANSIBLE_HOST_KEY_CHECKING": "True"}` rétablit la vérification pour toutes les tâches du serveur. Encore faut-il que les clés d'hôte soient connues : `/etc/ssh/ssh_known_hosts` de `sem01`, installé par `playbooks/controleurs-ansible.yml` (E27, `hosts: role_runner:role_semaphore`).
- `pkg/ssh/agent.go`, `GetGitEnv` : pour un dépôt en SSH, `GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"` ; une option `-o` en ligne de commande l'emporte sur tout fichier de configuration (`ssh_config_path` ne peut pas la corriger). Un attaquant capable de se faire passer pour `git01` dans le VLAN INFRA servirait **son** code, exécuté avec une clé `root` sur tout le socle. Choix retenu : dépôt en **HTTPS**, TLS vérifié par le magasin système de `sem01` (CA provisoire présente dans l'image dorée), avec un **jeton de déploiement** GitLab de portée `read_repository` (*Settings > Repository > Deploy tokens*), stocké dans le magasin de clés comme « Login with password » (identifiant du jeton, valeur du jeton). Contrepartie : Semaphore construit l'URL avec l'identifiant et le jeton (`https://<id>:<jeton>@git01…`) — visible dans les processus de `sem01` et dans le `.git/config` des copies de travail sous `/var/lib/semaphore/tmp` (lisible par `semaphore` seulement). Le jeton ne donne qu'un accès en lecture au dépôt (dont les secrets sont chiffrés) : risque bien moindre qu'une exécution de code non vérifiée. Une clé de déploiement SSH en lecture seule reste acceptable si l'on assume l'absence de vérification du serveur ; écris ton choix.

*5. Le projet.* Dans l'interface (*New Project* « Socle MédiSphère ») :
- *Key Store* : « gitlab-deploy-token » (*Login with password*), « ansible-semaphore » (*SSH*, identifiant `admin`, clé privée générée sur `adm01` comme en E27 et autorisée par le rôle `base` avec `from="10.10.20.41"`), « vault-lab » (*Login with password*, identifiant vide, mot de passe Vault `lab`) ;
- *Repositories* : `https://git01.par1.medisphere.internal/plateforme/ansible.git`, branche `main`, clé « gitlab-deploy-token » ;
- *Inventory* : type *File*, chemin `inventories/lab/hosts.yml` (relatif au dépôt), identifiant utilisateur « ansible-semaphore » ;
- *Variable Groups* : « socle », variables `{}`, variable d'environnement `ANSIBLE_VAULT_IDENTITY_LIST=lab@prompt` ;
- *Task Templates* (*Ansible Playbook*) : « Socle — vérifier » (`playbooks/site.yml`, arguments `["--check", "--diff"]`, coffre « vault-lab » nommé `lab`) et « Socle — appliquer » (mêmes paramètres sans `--check`).

Échec typique au premier lancement : `The vault password file /var/lib/semaphore/.config/workbook/ansible-vault.pass was not found`. `ansible.cfg` du dépôt désigne un fichier de `adm01`. Semaphore, lui, ajoute `--vault-id=lab@prompt` et répond à l'invite « Vault password (lab): ». La variable d'environnement `ANSIBLE_VAULT_IDENTITY_LIST=lab@prompt` du groupe de variables **remplace** la liste de `ansible.cfg` : Ansible pose alors deux fois la question (une par entrée), et Semaphore répond aux deux. C'est un contournement : l'E30 le remplace par un script client.

*6. Équipe.* Comptes locaux créés dans *Users* (ou `semaphore users add` sans `--admin`), puis *Team* du projet : `nadia.roussel` → *Task Runner*, `karim.benali` → *Manager*. Compte de vérification :

```
admin@sem01:~$ sudo -u semaphore semaphore users add --config /etc/semaphore/config.json \
>   --login workbook-checks --name "Vérifications du workbook" --email workbook-checks@medisphere.internal \
>   --password "$(openssl rand -base64 24)"
admin@sem01:~$ sudo -u semaphore semaphore users token create --config /etc/semaphore/config.json \
>   --login workbook-checks --name checks --ttl 2160h
<JETON>
admin@adm01:~$ (umask 077; read -rs j && printf '%s' "$j" > ~/.config/workbook/semaphore-checks.token)
```

Puis *Team* : `workbook-checks` → *Guest*. Second facteur : *User* (menu du compte) → *TOTP* pour l'administrateur (activé côté serveur par `mfa.totp.enabled`).

*7. Comparaison* (exemple de tableau) :

| | CI GitLab | Semaphore |
|---|---|---|
| Qui applique | Maintainers (job manuel de `main`) | Rôles *Owner*, *Manager*, *Task Runner* du projet |
| Journal | Job + déploiement `lab/socle`, artefacts 1 an, lié au commit et à la MR | Historique des tâches dans PostgreSQL, lié au commit cloné, pas à la MR |
| Secrets | Variables protégées (Maintainers) | Magasin chiffré par `access_key_encryption` (administrateurs, et quiconque a la base **et** `config.json`) |
| Clé sur le socle | `ansible-ci`, depuis 10.10.20.15 | `ansible-semaphore`, depuis 10.10.20.41 |
| Exclusion mutuelle | `resource_group: socle-lab` (entre jobs GitLab seulement) | Une tâche à la fois par modèle (option), rien vis-à-vis de GitLab |

*8.* Matrice des flux (`sem01` → `gw01`/`adm01` TCP 22 ; VPN et MGMT → `sem01` TCP 443 et 80, déjà couverts), registre des secrets (`access_key_encryption` et les deux clés de cookies : Vault `lab` en E28, `critique` en E30 ; mot de passe PostgreSQL ; jeton de déploiement ; clé `ansible-semaphore` ; jeton `workbook-checks`), inventaire du socle (`sem01`, VM d'environnement), sauvegarde : `semaphore projects export` et `pg_dump semaphore`, plus la sauvegarde nocturne du pool `lab` par PBS.

**Explications**

Installer l'orchestrateur avec Ansible a deux mérites : `sem01` est reconstructible en quelques minutes à l'identique (seule la base porte de l'état), et sa configuration passe par la même revue que le reste. La clé `access_key_encryption` chiffre tout le magasin de clés dans la base : la perdre rend le magasin illisible (il faut ressaisir toutes les clés) ; la voler avec une copie de la base donne toutes les clés du socle. C'est pourquoi `config.json` est illisible pour les autres comptes et pourquoi cette clé est classée `critique` en E30. BoltDB a disparu en 2.19 ; SQLite est le défaut, PostgreSQL est retenu pour la cohérence avec le reste de la plateforme (NetBox au module 06, sauvegardes `pg_dump`) et parce que la haute disponibilité de Semaphore exige une base externe.

**Alternatives**
- Image Docker officielle (`semaphoreui/semaphore`) : installation en une commande, mais Docker n'arrive qu'au module 12, et le conteneur embarque son propre Ansible.
- Proxy inverse (nginx, Caddy) devant Semaphore plutôt que le TLS intégré : utile pour un sous-chemin, une authentification en amont ou plusieurs services ; il faut alors gérer le WebSocket `/api/ws` et un délai de lecture supérieur à deux minutes.
- AWX : voir E32 et l'ADR de l'E31.

**Pièges classiques**
- Croire que Semaphore vérifie les clés d'hôte : il impose le contraire par défaut.
- Passer le mot de passe Vault en variable d'environnement « en clair » dans le groupe de variables au lieu du magasin ou d'un secret.
- `config.json` en 0644 (créé par `semaphore setup` dans le dossier courant) : clés lisibles par tous.
- Exemple ancien de documentation : `"auth": {"totp": …}` ignoré silencieusement ; c'est `mfa`.
- Lancer le service en root pour écouter sur 443.
- Oublier `web_host` : redirections et cookies `Secure` faux, connexion impossible derrière un nom.
- Inventaire de type *File* avec un chemin absolu vers `adm01` : il est lu **sur `sem01`**, relatif au dépôt cloné.

**En production chez MédiSphère**
Authentification par l'IdP (OIDC, module 24) et plus de comptes locaux ; base PostgreSQL sauvegardée et restauration testée ; supervision (`/api/ping`, tâches en échec) ; mises à jour de Semaphore par MR (variable `semaphore_version` + empreinte) ; journalisation des événements (`log.events`) vers la plateforme de logs (module 22). Le sort de `sem01` est tranché par l'ADR-0040.

---

### M04-E29 — Détecter la dérive de configuration

**Solution** (une solution de référence ; d'autres sont valables si elles respectent les contraintes)

Fichiers : [`outils/derive.sh`](fichiers/M04-E29/ansible/outils/derive.sh), [`outils/alerte-derive.sh`](fichiers/M04-E29/ansible/outils/alerte-derive.sh), [`.gitlab-ci.yml`](fichiers/M04-E29/ansible/.gitlab-ci.yml) (état E27 + job `derive`), `outils/recap-ansible.sh` de l'E27.

*L'outil.* `outils/derive.sh` lance `site.yml --check --diff` avec des faits frais (`ANSIBLE_CACHE_PLUGIN=memory`, `ANSIBLE_GATHERING=implicit`), un rapport JUnit où chaque tâche « changed » est un cas en échec (`JUNIT_FAIL_ON_CHANGE=true`, `JUNIT_HIDE_TASK_ARGUMENTS=true`), puis interprète le récapitulatif : 0 conforme, 1 dérive, 2 erreur (y compris un code d'Ansible non nul avec un récapitulatif propre : Vault, syntaxe, inventaire). Il écrit `derive.log`, `junit/*.xml` et `resume.json` (verdict, hôtes qui changeraient, hôtes en échec, commit). Le même outil sert partout :

```
admin@adm01:~/src/ansible$ outils/derive.sh
hotes=5 ok=187 changed=0 unreachable=0 failed=0 hotes_changes=- hotes_en_echec=-
Dérive : conforme (code ansible 0, commit 3f9c2ab) — rapport dans rapports/derive/
admin@adm01:~/src/ansible$ echo $?
0
```

Dans Semaphore, un modèle de type *Shell* qui exécute `outils/derive.sh` (avec `ANSIBLE_PLAYBOOK=ansible-playbook`, car `uv` n'y est pas) donne le même verdict.

*La planification.* *Build > Pipeline schedules* : « Détection de dérive », `30 6 * * *`, fuseau Europe/Paris, cible `main`, variable `PLANIF=derive`. Job `derive` : `resource_group: socle-lab` (jamais pendant `appliquer`), artefacts 90 jours, rapport JUnit, et en cas de verdict non conforme : `outils/alerte-derive.sh` puis échec du job (pipeline planifié rouge : seconde alerte, notification au propriétaire de la planification si le courriel est configuré).

*L'alerte.* Jeton d'accès de **projet** `bot-derive` (*Settings > Access tokens*, rôle *Reporter*, portée `api`, expiration 1 an) en variable `DERIVE_TOKEN` protégée, masquée et cachée. `alerte-derive.sh` cherche un ticket ouvert étiqueté `derive` ; s'il existe, ajoute un commentaire, sinon le crée. Le jeton passe par un fichier d'en-tête (`curl -H @fichier`), jamais en argument. Le ticket ne contient que des noms d'hôtes, des totaux et le lien vers les artefacts : jamais d'extrait du journal (un *diff* peut être sensible).

*La démonstration.*

```
admin@adm01:~$ ssh dns01 'echo "modifié à la main" | sudo tee -a /etc/motd'
admin@adm01:~$ ssh gw01 'echo "X11Forwarding yes" | sudo tee /etc/ssh/sshd_config.d/99-manuel.conf'
```

*Pipeline schedules* → *Run* (ou attendre 6 h 30) : job `derive` en échec, ticket « Dérive de configuration du socle » créé avec `dns01`, `gw01`. Correction **par application** : job `appliquer` de `main` (le rôle `base` réécrit le motd ; pour le fichier `99-manuel.conf`, le rôle `ssh_durci` ne le supprime que s'il gère le contenu de `sshd_config.d/` — s'il ne le fait pas, la détection ne le voit pas non plus : voir les limites). Nouvelle exécution de la planification : conforme, job vert ; fermeture du ticket avec un commentaire (cause, correction, prévention).

*Faux positifs typiques à corriger dans les rôles* :
- `command`/`shell` sans `changed_when` : changent à chaque fois ; en `--check`, sautées (rien à voir) — mais une tâche de **lecture** dont dépend la suite doit avoir `check_mode: false` et `changed_when: false` ;
- tâche qui dépend d'un paquet installé par une tâche précédente : en `--check`, le paquet n'est pas installé, le service n'existe pas, la tâche échoue → `ignore_errors: "{{ ansible_check_mode }}"` ou une condition sur l'existence ;
- modèle qui contient une date ou un horodatage : change à chaque exécution ;
- `get_url` sans `checksum` vers une URL qui renvoie un contenu variable.

**Explications**

La dérive est l'écart entre l'état réel et l'état que `main` produirait. `--check` la mesure **du point de vue des rôles** : ce qu'aucun rôle ne gère (un fichier ajouté dans un dossier dont le rôle ne gère qu'un fichier, un paquet installé à la main, un utilisateur créé) est invisible. La détection prouve donc la conformité aux rôles, pas l'absence de modification. Pour la seconde, il faut des rôles qui gèrent des dossiers entiers (`sshd_config.d/` exclusif), et des outils complémentaires (AIDE, auditd et journaux centralisés, module 22 et 26).

Trois issues distinctes : une erreur d'exécution n'est pas une conformité (un hôte injoignable ne dérive pas « moins »). Le JUnit avec `fail_on_change` donne à l'auditeur une liste lisible des tâches qui changeraient, conservée 90 jours.

**Alternatives**
- Planification dans Semaphore plutôt que GitLab (même outil, autre journal).
- Correction automatique (`appliquer` déclenché par la détection) : tentant, mais on écrase une intervention d'urgence non encore reportée dans le code ; à réserver à des parcs homogènes et à des écarts connus.
- Mode *pull* (`ansible-pull`, Puppet) : convergence continue, voir E32.

**Pièges classiques**
- Détection avec le cache de faits du poste : faits périmés, résultat faux.
- Compter les « changed » dans un journal coloré (codes ANSI) : le motif ne correspond pas.
- Considérer un hôte injoignable comme conforme.
- Mettre le journal entier dans le ticket.
- Un jeton personnel (le tien) pour l'alerte : s'il quitte l'équipe, l'alerte s'arrête ; et il a bien plus de droits que nécessaire.
- Détection et application simultanées : la détection voit un état intermédiaire.

**En production chez MédiSphère**
Nombre d'hôtes en dérive exporté comme métrique (fichier pour le collecteur `textfile`, module 21) et alerte si la détection n'a pas tourné depuis 26 h ; rapport mensuel des dérives (cause, délai de correction) pour la revue de conformité HDS.

---

### M04-E30 — Vault en production : séparation et rotation

**Solution**

Fichiers : [`outils/vault-pass-client.sh`](fichiers/M04-E30/ansible/outils/vault-pass-client.sh), [`outils/secrets-dans-journal.py`](fichiers/M04-E30/ansible/outils/secrets-dans-journal.py), [`outils/publier-journal.sh`](fichiers/M04-E30/ansible/outils/publier-journal.sh), [`outils/ci-secrets.sh`](fichiers/M04-E30/ansible/outils/ci-secrets.sh) (révisé), [`ansible.cfg`](fichiers/M04-E30/ansible/ansible.cfg), [`.gitlab-ci.yml`](fichiers/M04-E30/ansible/.gitlab-ci.yml) (état E30), runbook [`RB-041`](fichiers/M04-E30/medisphere/docs/socle/runbooks/RB-041-rotation-vault.md).

*1. Inventaire* (exemple ; tes noms de variables suivent tes rôles) :

| Variable | Consommateur | Gravité | Identité | Rotation |
|---|---|---|---|---|
| `vault_gitlab_runner_jeton` (`glrt-…`) | `runner01` (rôle `gitlab_runner`) | critique : se faire passer pour le runner, recevoir les jobs de `main` et leurs variables protégées | `critique` | 6 mois, et à tout départ |
| `vault_semaphore_access_key_encryption`, `…cookie_hash`, `…cookie_encryption` | `sem01` | critique (magasin de clés du socle) | `critique` | à la reconstruction de `sem01` (changer la première = ressaisir le magasin) |
| `vault_semaphore_tls_cle` | `sem01` | critique (usurpation de l'interface) | `critique` | avec le certificat (397 jours) |
| `vault_semaphore_db_mot_de_passe`, `vault_semaphore_admin_mot_de_passe` | `sem01` | élevée | `lab` | 6 mois |
| autres secrets d'exploitation du socle (E12) | selon le rôle | moyenne | `lab` | 6 mois |

*2. Séparation.*

```
admin@adm01:~/src/ansible$ (umask 077; openssl rand -base64 32 > ~/.config/workbook/ansible-vault-critique.pass)
admin@adm01:~/src/ansible$ uv run ansible-vault decrypt inventories/lab/host_vars/sem01/vault.yml
admin@adm01:~/src/ansible$ # déplacer les variables critiques dans vault-critique.yml (même dossier), puis :
admin@adm01:~/src/ansible$ uv run ansible-vault encrypt --encrypt-vault-id critique inventories/lab/host_vars/sem01/vault-critique.yml
admin@adm01:~/src/ansible$ uv run ansible-vault encrypt --encrypt-vault-id lab inventories/lab/host_vars/sem01/vault.yml
admin@adm01:~/src/ansible$ head -1 inventories/lab/host_vars/sem01/vault-critique.yml
$ANSIBLE_VAULT;1.2;AES256;critique
```

(`vault.yml` et `vault-critique.yml` du même dossier `host_vars/sem01/` sont tous deux chargés : Ansible lit tous les fichiers d'un dossier `host_vars/<hôte>/`.) `ansible.cfg` : `vault_identity_list = lab@outils/vault-pass-client.sh, critique@outils/vault-pass-client.sh` et `vault_id_match = True`.

Observation demandée : sans mot de passe pour `critique` (pipeline de MR), Ansible affiche seulement

```
[WARNING]: Error in vault password file loading (critique): Vault password client script …/outils/vault-pass-client.sh returned non-zero (1) when getting secret for vault-id=critique: …
```

et continue ; une tâche qui **utilise** une variable `critique` échoue (« Decryption failed (no vault secrets were found that could decrypt) »). Une tâche sautée par son `when` ne développe pas ses arguments et ne déchiffre rien. Pour que `check-socle` réussisse sans `critique` alors que le rôle `gitlab_runner` utilise le jeton : les tâches qui consomment un secret `critique` portent l'étiquette `critique`, et `check-socle` tourne avec `--skip-tags critique` (le job `appliquer` et la détection, dans l'environnement `lab/socle`, ont l'identité et ne sautent rien). Attention à ne pas citer une variable `critique` dans un nom de tâche ou un `when` d'une tâche non étiquetée.

Distribution : CI — `VAULT_PASS_CRITIQUE` (fichier, protégée, **portée d'environnement `lab/socle`**), reçue par `appliquer` (`environment: lab/socle`) et `derive` (`environment: {name: lab/socle, action: verify}`, qui reçoit les variables de l'environnement sans créer de déploiement) ; Semaphore — secrets de type variable d'environnement `VAULT_MDP_LAB` et `VAULT_MDP_CRITIQUE` du groupe de variables (passés au processus, pas en argument) ; poste — les deux fichiers de `~/.config/workbook/`.

*3. Le script client* : cherche `VAULT_PASS_<ID>` (chemin, CI), puis `VAULT_MDP_<ID>` (valeur, Semaphore), puis `~/.config/workbook/ansible-vault-<id>.pass` (et `ansible-vault.pass` pour `lab`) ; refuse un fichier accessible au groupe ou aux autres ; échoue avec un message sans le mot de passe. Bascule : `ci-secrets.sh` n'exporte plus `ANSIBLE_VAULT_IDENTITY_LIST` (il remet les fichiers de variables en 600) ; dans Semaphore, retirer `ANSIBLE_VAULT_IDENTITY_LIST=lab@prompt` et les coffres des modèles.

```
admin@adm01:~/src/ansible$ env -i PATH=/usr/bin:/bin HOME=/nonexistent outils/vault-pass-client.sh --vault-id critique; echo $?
vault-pass-client : aucun mot de passe pour l'identité « critique » (VAULT_PASS_CRITIQUE, VAULT_MDP_CRITIQUE, ~/.config/workbook/)
1
```

*4. Fuites.* Reproduction : `uv run ansible-playbook playbooks/site.yml --check --diff --limit runner01` avec un rôle `gitlab_runner` dont le modèle de `config.toml` contient le jeton : le *diff* l'affiche en clair dans le journal du job — lisible par tout membre du projet ayant accès aux journaux. Correctifs : `diff: false` sur les tâches de modèle/copie qui écrivent un secret (le contenu n'est plus montré, le changement si) ; `no_log: true` sur les tâches qui **passent** un secret en argument (commande `gitlab-runner register --token …`, `psql`) ; les deux si nécessaire. `no_log` cache aussi les messages d'erreur : à réserver aux tâches qui le méritent. Garantie automatique : `outils/secrets-dans-journal.py` déchiffre les fichiers Vault du projet (avec les identités disponibles), cherche chaque valeur (telle quelle, ligne par ligne pour les clés PEM, en base64) dans les journaux et rapports JUnit, et n'affiche que des **noms** ; `outils/publier-journal.sh` n'affiche le journal qu'après ce contrôle, sinon il vide les fichiers (pas d'artefact qui garde le secret) et fait échouer le job.

```
admin@adm01:~/src/ansible$ echo "+ token = $(uv run ansible localhost -m debug -a var=vault_gitlab_runner_jeton 2>/dev/null | grep -o 'glrt-[^"]*')" > /tmp/essai.log
admin@adm01:~/src/ansible$ uv run python outils/secrets-dans-journal.py /tmp/essai.log; rm /tmp/essai.log
FUITE : vault_gitlab_runner_jeton (inventories/lab/host_vars/runner01/vault-critique.yml) apparaît dans /tmp/essai.log
1 secret(s) trouvé(s) : ne publie pas ce journal.
```

*5. Rotation* : RB-041, procédures A (`rekey` d'une identité, distribution aux trois consommateurs, vérification) et B (changement réel d'un secret : mot de passe PostgreSQL de Semaphore — le rôle détecte que l'ancien ne passe plus, exécute `ALTER ROLE`, réécrit `config.json`, redémarre).

**Explications**

Ansible Vault chiffre des **données** avec une clé dérivée d'un mot de passe par identité ; il ne gère ni les personnes, ni les droits, ni l'audit. La séparation par identités limite ce que révèle la fuite d'**un** mot de passe et permet de donner moins à certains exécutants (le `check-socle` de MR n'a jamais `critique`). `vault_id_match` évite d'essayer tous les mots de passe sur chaque fichier (et rend l'erreur explicite). L'historique Git est la limite majeure : un ancien commit reste déchiffrable avec l'ancien mot de passe ; seul le changement des secrets eux-mêmes protège après une fuite. Les secrets en clair dans les journaux sont la fuite la plus fréquente en pratique : `--diff`, `-vvv`, messages d'erreur ; GitLab ne masque que les **variables CI** masquées, pas les valeurs déchiffrées par Ansible.

**Alternatives**
- Un seul mot de passe par environnement plutôt que par gravité : plus simple, moins fin.
- Client Vault qui lit dans un gestionnaire (`pass`, GPG, trousseau) : le mot de passe n'est plus en clair sur disque.
- OpenBao/Vault (module 25) : secrets lus à l'exécution, par consommateur authentifié, avec audit et rotation automatique (secrets dynamiques) ; Ansible Vault ne garde alors que le minimum pour démarrer.
- SOPS + age (module 25) : chiffrement par clé publique, plusieurs destinataires, rotation d'un destinataire sans changer les autres.

**Pièges classiques**
- `ansible-vault rekey` sur des valeurs chiffrées en ligne (`!vault |`) : non pris en charge, il faut les rechiffrer une à une.
- Croire qu'un `rekey` « révoque » une fuite.
- Une variable cachée de GitLab ne se modifie pas : il faut la supprimer et la recréer (et l'oublier dans un environnement).
- Chemin relatif du script client résolu depuis le dossier courant : Ansible lancé depuis `playbooks/` ne trouve plus le mot de passe.
- `no_log` partout : plus aucun diagnostic possible ; `diff: false` suffit souvent.
- Un secret court (`motd`, mots de 3 lettres) mis dans Vault : faux positifs de la détection, et ce n'était pas un secret.

**En production chez MédiSphère**
Rotation inscrite au calendrier (registre des secrets avec échéances, alerte 15 jours avant), exercée au moins une fois par an en conditions réelles ; détection des fuites dans tous les journaux d'outils (pas seulement Ansible) ; au module 25, migration des secrets `critique` vers OpenBao avec une identité par consommateur.

---

### M04-E31 — ADR : comment exécuter Ansible chez MédiSphère

**Solution**

ADR exemplaire : [`ADR-0040-execution-ansible.md`](fichiers/M04-E31/medisphere/docs/socle/adr/ADR-0040-execution-ansible.md). Grille d'auto-évaluation : [`grille-evaluation.md`](fichiers/M04-E31/grille-evaluation.md). Note ton ADR **avant** de lire l'exemple.

L'exemple retient la CI comme **seul** exécutant qui applique, une procédure de bris de glace depuis `adm01`, la détection de dérive quotidienne, et la destruction de `sem01` en fin de module (Semaphore évalué, non retenu à cinq hôtes ; rôle conservé). D'autres décisions sont acceptables si elles traitent l'exclusion mutuelle et le cycle de vie de `sem01` (voir la grille).

**Explications**

La question centrale n'est pas « quel outil est le meilleur » mais « combien d'exécutants peuvent **écrire** sur le socle, et comment on le prouve ». Un seul exécutant qui écrit rend la traçabilité et l'exclusion mutuelle gratuites ; chaque exécutant supplémentaire coûte une clé `root`, un magasin de secrets, un journal à rapprocher et un mécanisme de verrou. Le bris de glace est indispensable (la forge peut tomber) et doit rester **exceptionnel et visible** : ticket, journal versionné, retour au chemin normal constaté.

**Alternatives**
Voir l'analyse des options de l'ADR et la section « Décisions également valables » de la grille.

**Pièges classiques**
- Un ADR qui ne tranche pas la concurrence (« on fera attention »).
- Garder `sem01` sans en tirer les conséquences (VMID 2041 d'environnement, pas de sauvegarde applicative, pas de supervision).
- Un bris de glace sans trace ou sans retour au chemin normal : il devient le chemin normal.
- Écarter AWX sans raison factuelle (dernière version, dépendances, coût d'exploitation).

**En production chez MédiSphère**
L'ADR est relu par Sophie (sécurité) et Nadia (exploitation) ; la procédure de bris de glace est répétée une fois par semestre (exercice « GitLab indisponible ») ; la décision est revue quand le parc ou l'équipe double.

---

### M04-E32 — Questions : Ansible, Puppet (OpenVox), Salt, AWX

**1. *Push* et *pull*.** *Push* (Ansible) : le contrôleur initie des connexions SSH vers les hôtes ; la vérité est le dépôt du contrôleur ; une machine éteinte pendant l'application est simplement manquée (« UNREACHABLE ») et ne sera à jour qu'à la prochaine exécution qui la vise ; flux : contrôleur → hôtes TCP 22. *Pull* (agent Puppet, `ansible-pull`) : chaque hôte interroge régulièrement un serveur (catalogue Puppet, dépôt Git) et converge seul ; la vérité est sur le serveur ou le dépôt ; une machine éteinte rattrape à son prochain cycle ; flux : hôtes → serveur (Puppet : TCP 8140 vers le serveur ; `ansible-pull` : accès au dépôt Git). Le *push* donne un contrôle fin du moment et de l'ordre ; le *pull* donne une convergence continue sans orchestrateur.

**2. QCM — réponse b.** Depuis 2025, Perforce distribue Puppet sous une licence propriétaire « Puppet Core » ; la communauté a créé OpenVox (fork du code libre, paquets disponibles pour Debian 13). a) est l'ancienne situation ; c) faux, Puppet reste installable sur site ; d) faux, OpenVox existe et est maintenu.

**3. Équivalent Ansible** : `ansible.builtin.copy: src: ntp.conf dest: /etc/ntp.conf` (fichier dans `files/` du rôle) ou `template`. Moment : Puppet compile d'abord un **catalogue** complet (graphe de ressources), puis l'applique dans l'ordre des dépendances déclarées (`require`, `before`, `notify`/`subscribe`) — l'ordre d'écriture dans le manifeste n'a pas de sens propre. Ansible exécute les tâches **dans l'ordre du playbook**, l'une après l'autre ; les handlers remplacent `notify`/`subscribe` pour les redémarrages. Conséquence pour une migration : il faut linéariser le graphe de Puppet et vérifier que chaque `require` devient un ordre de tâches.

**4. Salt** : le bus d'événements (ZeroMQ, connexions permanentes des *minions* vers le *master*) permet des commandes quasi instantanées sur des milliers d'hôtes, une réaction à des événements (*reactor*, *beacons* : un fichier modifié déclenche une correction) et une orchestration plus rapide qu'en SSH. Inconvénient historique : le *master* est un point central exposé ; en 2020, CVE-2020-11651 (contournement d'authentification) et CVE-2020-11652 (traversée de répertoires) permettaient à quiconque joignait les ports 4505/4506 d'exécuter des commandes en root sur le *master* et donc sur **tous** les *minions* ; des *masters* exposés sur Internet ont été massivement compromis. Leçon générale : un serveur de configuration centralisé est la cible la plus rentable d'une infrastructure.

**5. QCM — réponse b.** AWX n'a publié aucune version depuis la 24.6.1 (juillet 2024) ; Red Hat a suspendu son développement public pour une refonte. a) décrit la situation d'avant 2024 ; c) faux, Semaphore UI est un projet indépendant ; d) faux, l'opérateur AWX tourne sur tout Kubernetes, mais il **exige** Kubernetes.

**6. AWX/AAP fait, Semaphore libre ne fait pas** (2.19) : flux de travail avec approbations (*workflows*, réservés à Semaphore Pro), inventaires dynamiques synchronisés avec historique et « smart inventories », RBAC très fin par objet, *execution environments* (conteneurs d'exécution versionnés), intégration à des coffres externes plus large (certaines intégrations de Semaphore sont aussi réservées aux éditions payantes). **Raisons de préférer Semaphore ici** : un binaire et une base, installable par un rôle Ansible sur une petite VM (AWX exige Kubernetes, qui n'arrive qu'au module 14) ; projet actif avec des versions fréquentes (AWX gelé) ; l'équipe de quatre personnes n'a pas besoin du RBAC d'AWX, et le coût d'exploitation compte (l'expérience d'InfoGér).

**7. « Sans agent »** : il faut un serveur SSH, un compte avec `sudo`, et **Python** sur l'hôte (les modules sont des programmes Python copiés puis exécutés). Sans Python sur `gw01`, toute tâche échoue (« /usr/bin/python3: not found ») sauf `ansible.builtin.raw` (commande brute par SSH, sans Python) et `ansible.builtin.script` : on réinstalle Python par `raw` (`apt-get install -y python3`), puis on reprend. C'est aussi ainsi qu'on amorce des images minimales ou des équipements réseau.

**8. Idempotence** : appliquer deux fois donne le même état, la seconde fois sans rien changer. Puppet : chaque ressource compare l'état réel à l'état voulu (idempotent par construction). Ansible : chaque **module** compare et rapporte `changed` ; `command`/`shell` ne savent pas ce que fait la commande, donc annoncent toujours un changement. Trois façons : `creates`/`removes` (la commande ne s'exécute que si un fichier existe ou non) ; `changed_when` (et `failed_when`) sur une condition lue dans la sortie ; une tâche de lecture préalable (`stat`, requête) qui conditionne l'action par `when` (motif des tâches PostgreSQL de l'E28). La meilleure : un vrai module.

**9. QCM — réponse b.** L'agent Puppet s'exécute par défaut toutes les 30 minutes (`runinterval`). a) Ansible n'agit que quand on le lance ; c) sans planification, Semaphore attend qu'on lance une tâche ; d) Molecule teste, il n'applique rien en production.

**10. Migration des manifestes Puppet d'InfoGér** : (1) inventaire : lister les classes et les nœuds, exécuter `puppet agent --noop` sur chaque serveur pour connaître l'état réellement géré, et relever les ressources effectives (`puppet resource …`) ; (2) découpage : une classe ou un module Puppet → un rôle Ansible, variables Hiera → `group_vars`/`host_vars` ; (3) écriture des rôles avec Molecule, en traduisant le graphe de dépendances en ordre de tâches et handlers ; (4) **preuve** : sur un serveur, appliquer le rôle Ansible en `--check --diff` **pendant** que Puppet le gère encore : un diff vide signifie que le rôle produit exactement l'état de Puppet ; tout écart est un oubli ou une différence voulue à documenter ; (5) bascule serveur par serveur : arrêter l'agent Puppet (`puppet agent --disable` puis désinstallation), appliquer Ansible, intégrer à la détection de dérive.

**11.** **Chef** : modèle *pull* avec agent, recettes en Ruby (DSL), serveur Chef ; puissant mais demande des compétences Ruby et un serveur, communauté en recul depuis le rachat par Progress. **CFEngine** : le pionnier (1993), agent très léger en C, convergence par promesses, extrêmement économe en ressources ; langage déroutant et écosystème restreint. Aucun n'apporte assez par rapport à Ansible, déjà maîtrisé et utilisé par Kolla-Ansible (module 10).

**12.** Un outil *pull* toutes les 30 minutes **corrige** la dérive à chaque cycle : un écart dure au plus 30 minutes, mais il est **effacé** (une modification d'urgence non reportée dans le code est perdue sans que personne ne le sache, sauf rapport de l'agent). Ta détection (E29) **constate** la dérive une fois par jour, sans corriger : l'écart peut durer jusqu'à 24 h, mais il est tracé, signalé et analysé. Pour l'audit HDS, les deux prouvent quelque chose de différent : le *pull* prouve la convergence (à condition de conserver ses rapports), la détection prouve la conformité à une date et la gestion des écarts. La bonne réponse dépend du risque : pour le socle, détecter et analyser ; pour un parc homogène nombreux, converger.

**Grille d'auto-évaluation** : 1 point par question correctement argumentée (QCM : bonne réponse **et** pourquoi les autres sont fausses). 10 ou plus : maîtrisé ; 7 à 9 : relis la documentation d'OpenVox et l'histoire des CVE Salt ; moins de 7 : refais la lecture des sections « modèle d'exécution » des quatre outils.

---

### M04-E33 — Questions de production : configuration à l'échelle

**1.** Stratégie `linear`, `forks = 50` : 500 hôtes en 10 vagues de 50 ; une collecte de 3 s par hôte → environ 10 × 3 = 30 s, plus le coût du contrôleur (lancer 500 processus, recevoir 500 jeux de faits : en pratique 45 à 60 s). `gather_subset: [min]` divise la durée par 2 à 5 (pas de matériel, de montages, de paquets) ; un cache de faits la supprime pour les exécutions suivantes (au prix de faits périmés) ; `strategy: free` ne change rien à la collecte (elle est parallèle), mais évite ensuite qu'un hôte lent bloque chaque tâche. Facteur limitant : le **contrôleur** — CPU et mémoire pour 50 *forks* (≈ 50 × 60 Mo), descripteurs de fichiers, et sa bande passante vers les hôtes.

**2. QCM — réponse b.** 25 % de 10 = 2,5 → 2 hôtes par lot ; 1 échec sur 2 = 50 % > 20 % : le play s'arrête (dès la tâche en échec, sans passer au lot suivant ; l'autre hôte du lot s'arrête aussi). a) confond le pourcentage du lot avec celui de l'inventaire ; c) décrit `any_errors_fatal` ; d) faux, les deux se combinent.

**3.** Rôles partagés : dans une **collection** versionnée (`medisphere.socle`, E18) publiée avec des étiquettes SemVer ; chaque projet consommateur l'épingle dans son `collections/requirements.yml` (version exacte), et monte de version par une MR testée (Molecule, `check`). Un changement incompatible = version majeure, annoncée, avec la précédente maintenue un temps. Jamais de `ref: main` d'un rôle partagé dans la production d'une autre équipe. `medisphere.socle` contient ce qui est commun à **plusieurs** projets (base, ssh_durci, modules maison) ; les rôles propres au socle restent dans `plateforme/ansible`.

**4.** `--check` simule chaque tâche isolément, sans les effets des tâches précédentes. Exemples : (a) une tâche qui démarre un service installé par une tâche précédente : en simulation le paquet n'est pas installé, le service n'existe pas (échec ou faux résultat) ; (b) une tâche `command` (enregistrement du runner, `psql`) est sautée : on ne sait pas si elle réussira ; (c) le rechargement de nftables : la validation `nft -c` d'un fichier qui n'a pas été écrit, ou le filet anti-coupure qui ne peut rien prouver en simulation ; aussi les modules qui ne supportent pas le mode `check` (sautés), et tout ce qui dépend du réseau au moment réel.

**5.** Un `site.yml` unique : une seule commande pour tout converger, utile pour la détection de dérive et la reconstruction ; mais chaque changement touche (au moins en lecture) tout le parc, l'aperçu en MR se connecte partout, le rayon d'action d'une erreur est maximal. Un playbook par service : changements ciblés, exécutions rapides, droits séparés. À 500 hôtes : un playbook par service (`dns.yml`, `runner.yml`…), et `site.yml` réduit à une suite d'`import_playbook` utilisée pour la dérive et la reconstruction, jamais pour un changement courant ; la CI ne lance que le playbook du service modifié.

**6.** Options : (a) **cache du plugin d'inventaire** (`cache: true`, `cache_plugin`, `cache_timeout`) : plus rapide, mais une VM créée ou détruite n'apparaît qu'à l'expiration ; (b) **inventaire matérialisé** (un job exporte l'inventaire dynamique dans un fichier versionné) : stable, relisible en MR, mais en retard sur la réalité et à régénérer ; (c) **NetBox comme source de vérité** (module 06, plugin `netbox.netbox.nb_inventory`) : l'inventaire décrit ce qui **doit** exister, pas ce que l'hyperviseur voit ; robuste à une panne de Proxmox, mais il faut tenir NetBox à jour (et détecter l'écart entre NetBox et Proxmox). Risque commun : appliquer sur un inventaire faux (un hôte manquant n'est simplement pas configuré, en silence) → contrôle du nombre d'hôtes attendus en tête de playbook.

**7. QCM — réponse a.** `defaults/main.yml` du rôle (priorité la plus basse), surchargé par `group_vars` puis `host_vars`, et `-e` (priorité la plus haute, toujours). b) `vars/main.yml` a une priorité **supérieure** aux `group_vars`/`host_vars` d'inventaire : un groupe ne pourrait plus la surcharger ; c) ne permet pas la surcharge par hôte de façon propre et met tout au même endroit ; d) un `set_fact` écrase les variables d'inventaire et ne se surcharge que par `-e`.

**8.** Non : `ignore_errors` masque **toutes** les erreurs, y compris les vraies, et la tâche suivante travaille sur un état faux. Alternatives selon la cause : réseau ou dépôt intermittent → `retries`/`until`/`delay` ; verrou APT (`unattended-upgrades` en cours) → `lock_timeout` du module `apt` ; service lent à démarrer → `wait_for` sur le port ou `until` sur le statut ; erreur attendue et connue → `failed_when` précis sur le code ou le message ; rattrapage → `block`/`rescue` avec une action de repli explicite.

**9.** ADR-0040 : procédure de bris de glace depuis `adm01` (ticket INC, suspension des planifications, exécution limitée, journal versionné, MR de régularisation). Il faut **avant** la panne : un clone à jour de `plateforme/ansible` sur `adm01` (ou un miroir), l'environnement `uv` et les collections installés (pas de téléchargement possible si la forge est la cause… ou si Internet tombe), les mots de passe Vault et la clé SSH d'administration sur `adm01`, l'accès console de `gw01` (`qm terminal 1000`), et une procédure répétée à froid.

**10.** VMs : vrai `systemd`, vrai noyau (nftables, sysctl), vrais services, même image que la production — mais 40 à 70 s de création et des ressources limitées (5 VMID). Conteneurs : quelques secondes, des dizaines en parallèle, mais un faux environnement (pas de noyau à soi, `systemd` difficile). Pour 30 rôles en moins de 15 minutes : ne tester que les rôles modifiés (`rules:changes`) ; paralléliser (plusieurs runners, plus de VMID réservés, ou des scénarios qui partagent une instance) ; conteneurs pour les rôles qui ne touchent ni noyau ni `systemd`, VMs pour les autres ; image dorée qui contient déjà les prérequis ; et un test complet de tous les rôles une fois par nuit plutôt qu'à chaque MR.

**11. QCM — réponse b.** Le journal d'un job est lisible par les membres du projet qui ont accès aux journaux (par défaut à partir de *Reporter* ; tout le monde si le projet est public ou si les pipelines sont publics). GitLab ne masque que les valeurs des **variables CI masquées**, pas un secret déchiffré par Ansible et imprimé par `--diff`. a) faux pour cette raison ; c) et d) sous-estiment les droits par défaut. D'où `diff: false`/`no_log` et la vérification automatique des journaux (E30).

**12.** Indicateurs mensuels : (a) **taux de conformité** : part des détections quotidiennes « conformes » (seuil : < 90 % → revue) ; (b) **délai de correction d'une dérive** : de la détection à la détection conforme suivante (seuil : > 2 jours ouvrés) ; (c) **délai fusion → application** : changements fusionnés mais pas appliqués (seuil : > 7 jours, ou tout changement non appliqué à la fin du mois) ; (d) **taux d'échec des applications** (`appliquer` en échec / total, seuil : > 10 %) ; et en complément la couverture de tests (rôles avec scénario Molecule : 100 % visé) et la durée de `site.yml` (dérive de durée > 50 % → enquête).

**Grille d'auto-évaluation** : 1 point par question correctement argumentée (QCM : bonne réponse **et** réfutation des autres). 10 ou plus : maîtrisé ; 7 à 9 : refais les expériences de l'E25 et relis `docs/performances.md` ; moins de 7 : reprends le palier 3 dans l'ordre.

---

### M04-E34 — Un rôle complet en temps limité

**Solution** — rôle de référence (réalisable en 1 h 30 à 2 h quand on connaît ses gabarits)

Fichiers : [`roles/node_exporter/`](fichiers/M04-E34/ansible/roles/node_exporter/) (`defaults`, `handlers`, `meta/main.yml`, `meta/argument_specs.yml`, `tasks`, `templates`, `README.md`), [`molecule/node_exporter/`](fichiers/M04-E34/ansible/molecule/node_exporter/), job CI : [`gitlab-ci-extrait.yml`](fichiers/M04-E34/ansible/gitlab-ci-extrait.yml).

Correspondance exigences → tâches → vérifications :

| Exigence | Tâche du rôle | Vérification (`verify.yml`) |
|---|---|---|
| X1 paquet, service | `apt` (sans *recommends*), `systemd_service` `started`/`enabled` | `ActiveState == active`, `UnitFileState == enabled` |
| X2 écoute | `--web.listen-address={{ adresse }}:{{ port }}`, adresse = `ansible_facts['default_ipv4']['address']` | `ss -Hltn sport = :9100` : l'adresse principale, ni `0.0.0.0`, ni `*`, ni `[::]`, ni `127.0.0.1` |
| X3 collecteurs | `--no-collector.<nom>` par élément de la liste | aucune métrique `node_zfs_` |
| X4 systemd | `--collector.systemd.unit-include=(ssh\|chrony\|…)[.]service` | `node_systemd_unit_state{name="ssh.service"` présent, `cron.service` absent |
| X5 textfile | modèle `medisphere.prom` (groupes `role_*` ou `aucun`), écriture atomique par le module `template` | `medisphere_info{role="role_test",site="par1"} 1`, fichier en 0644 |
| X6 redémarrage | handler unique notifié par le seul fichier de paramètres ; `flush_handlers` | étape `idempotence` de Molecule |
| X7 validation | `meta/argument_specs.yml` + `assert` de plage en première tâche | — (essai manuel avec `-e node_exporter_port=80`) |
| X8 qualité | FQCN, `ansible_facts[…]`, conditions booléennes | job `ansible-lint` (profil `production`) |
| X9, X10 | — | scénario `node_exporter` (2049), job `molecule:node_exporter` |
| X11 | `README.md` | relecture de la MR |

Le piège principal du cahier des charges est X4 : `/etc/default/prometheus-node-exporter` est un `EnvironmentFile` lu par systemd puis développé par `$ARGS` dans `ExecStart` ; l'en-tête du fichier Debian prévient qu'une barre oblique inverse doit y être doublée **deux fois** (`\\\\.` pour `\.`). La classe `[.]` évite toute barre oblique. Second piège : au premier passage, le paquet démarre le service sur toutes les adresses ; sans `flush_handlers` immédiat, il y reste jusqu'à la fin du play. Troisième : la vérification HTTP doit partir de l'instance elle-même (vers son adresse principale), car `runner01` n'a que le port 22 vers `vsandbox`.

Déroulé type :

| Jalon | Ce qu'on fait | Temps typique |
|---|---|---|
| T0 → T1 | Lecture, squelette du rôle (copié de `base`), `defaults`, `argument_specs`, tâches, modèles ; inventaire du scénario (2049, groupe `role_test`) ; `uv run molecule converge -s node_exporter` | 45 à 60 min |
| T1 → T2 | `verify.yml`, `uv run molecule test -s node_exporter` complet (idempotence) | 30 à 40 min |
| T2 → T3 | `uv run ansible-lint --profile production roles/node_exporter molecule/node_exporter`, README, job CI, branche `conf/node-exporter`, MR | 20 à 25 min |
| T3 → T4 | Pipeline de MR (lint, Molecule sur `runner01`, `check-socle` inchangé), description de la MR | 15 à 20 min |

**Grille d'auto-évaluation** (à remplir après le chrono) :

| Critère | Points |
|---|---|
| Les onze exigences sont couvertes par une tâche **et** une vérification | /4 |
| Écoute restreinte prouvée par `ss` (pas seulement par la configuration) | /2 |
| Pas de barre oblique inverse dans `ARGS`, ou échappement correct et expliqué | /2 |
| Idempotence au premier essai complet, sans redémarrage superflu | /2 |
| `argument_specs` complet (types, défauts, descriptions) et refus du port hors plage avant toute action | /2 |
| `ansible-lint` profil `production` sans exclusion ajoutée pour l'occasion | /2 |
| README utile (variables, exemple, limites) et MR décrite (fait, testé, non testé) | /2 |
| T4 − T0 ≤ 2 h 30 | /4 |

**Total : /20.** 16 ou plus : rôle livrable. Moins de 12 : refais l'exercice sur un autre rôle (par exemple un rôle `motd_conformite` ou `journald_distant`) après avoir préparé un squelette de rôle à toi (`ansible-galaxy role init --role-skeleton`).

**Explications**

Le CHRONO mesure la capacité à livrer un rôle **complet** sans aide : le code est la partie la plus courte ; ce qui prend du temps est la vérification observable, la qualité (lint, contrat de variables) et l'intégration (CI, MR). D'où l'intérêt d'avoir industrialisé E24 et E27 : un nouveau rôle hérite de tout (scénario commun, job CI sur modèle).

**Pièges classiques**
- Écouter sur `:9100` « en attendant le pare-feu ».
- Vérifier la configuration au lieu de l'écoute réelle.
- Écrire le fichier `.prom` avec `lineinfile` ou `shell >` : fichier partiel lisible par le collecteur.
- Redémarrer le service à chaque passage (handler notifié par une tâche qui change toujours).
- Oublier le job CI : la MR « passe » sans que le rôle soit testé.

**En production chez MédiSphère**
Au module 21 : TLS et authentification de l'exportateur (`--web.config.file`, certificats de step-ca), flux 9100 ouverts sur `gw01` depuis Prometheus seulement, application à tout le socle par `site.yml`, et alertes sur `medisphere_info` absent (hôte qui n'est plus supervisé).
