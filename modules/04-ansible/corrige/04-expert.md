# Module 04 — Palier 4 : Expert — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Les corrigés des pannes suivent la trame habituelle : **symptômes → hypothèses → commandes de diagnostic dans l'ordre → cause racine (par variante) → correctif → prévention**. La démarche compte plus que le correctif : « j'ai relancé le playbook et ça remarche » est un échec pédagogique, et dans ce palier c'est souvent **pire** qu'un échec : relancer un playbook sur un projet dont on ne connaît pas l'état propage la panne.

Les scripts d'injection sont dans `corrige/pannes/` (`_m04-commun.sh` contient les fonctions partagées : sauvegarde et restauration exactes de la copie de travail, lancement d'Ansible comme l'apprenant, exécution par l'agent QEMU). Chaque modification est journalisée sur l'hôte touché dans `/var/lib/workbook/pannes.log` (copie d'origine dans `/var/lib/workbook/M04-EXX.*`), et sur `adm01` dans `~/.local/state/workbook/M04-EXX/` (avec un instantané de l'arbre de travail pris avant la panne).

Les sorties reproduites sont **représentatives** : chemins temporaires, numéros, horodatages et formulations exactes varient selon ta version. Les messages d'Ansible, d'`ansible-vault`, du plugin d'inventaire `community.proxmox.proxmox` 2.1 et de `ansible-config` ont été relevés avec ansible-core 2.21 ; ceux de `sshd`, PAM et Proxmox sont ceux de la documentation et des sources.

**Points non testés en conditions réelles** (signale-les si ton comportement diffère) : message exact du client SSH pour un compte expiré (E35 v4) ; refus de `root` selon que `ssh_durci` impose `PermitRootLogin no` ou que seule la commande forcée de cloud-init s'applique (E35 v2) ; délai réel d'un `logger --tcp` vers une adresse sans machine sur le même VLAN (E41 v4, ~3 s par appel attendus) ; comportement de `create.yml` de ton scénario Molecule face à des VMID occupés (E42 v2, dépend de ton M04-E24) ; modification de `agent` sur un template par `qm set` (E42 v4).

---

## Méthode commune aux pannes Ansible

1. **Reproduire avec la commande la plus courte.** Un module `ping`, un `ansible-vault view`, un `ansible-inventory --graph`, un `--list-tasks` : on isole l'étage avant de relancer tout `site.yml`.
2. **Demander à Ansible ce qu'il croit.** Trois commandes répondent à « avec quoi Ansible travaille-t-il vraiment ? » sans rien exécuter sur les cibles :
   ```
   admin@adm01:~/src/ansible$ uv run ansible-config dump --only-changed      # configuration effective et sa source
   admin@adm01:~/src/ansible$ uv run ansible-inventory --host dns01           # variables d'inventaire fusionnées
   admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --list-tasks --list-hosts
   ```
3. **Regarder ce qui a bougé.** `git status` et `git diff` dans `~/src/ansible` : le projet est versionné, toute différence avec le dernier commit est suspecte. Mais toutes les pannes ne passent pas par là (hôtes, `pve01`, `~/.config/workbook`).
4. **Mesurer l'état effectif sur la cible**, pas le fichier : `sshd -T`, `systemctl show`, `timedatectl`, `chronyc`.
5. **Corriger à la source, dans le dépôt**, et prouver l'idempotence : second passage `changed=0`.
6. **Prévenir** : quel test (Molecule, `--check` en CI, garde-fou dans un playbook) aurait arrêté la panne avant la production ?

Et une règle de sécurité : **avant de relancer, `--check --diff --limit`**. Dans E37, une relance de `site.yml` passe tout le socle en UTC ; dans E36 variante 4, elle durcit une VM de test au lieu de `dns01`.

---

### M04-E35 — Panne : « UNREACHABLE » sur une partie du socle

**Démarche de diagnostic**

*Symptôme* : `ansible socle -m ansible.builtin.ping` répond `pong` partout sauf sur une machine, en `UNREACHABLE!`.

*Hypothèses* : machine éteinte ; réseau ; adresse fausse dans l'inventaire ; mauvais compte ; clé SSH refusée ; clé d'hôte changée ; compte bloqué côté machine ; `sshd` arrêté (c'est E40).

**Étape 1 — Lire le message en entier.** `UNREACHABLE` veut dire qu'Ansible n'a rien pu exécuter : le texte qui suit vient de `ssh`.

```
admin@adm01:~/src/ansible$ uv run ansible socle -m ansible.builtin.ping -o
gw01 | SUCCESS => {"changed": false,"ping": "pong"}
dns01 | UNREACHABLE!: Failed to connect to the host via ssh: ssh: connect to host 10.10.20.253 port 22: No route to host
…
```

**Étape 2 — Ce qu'Ansible croit savoir.**

```
admin@adm01:~/src/ansible$ uv run ansible-inventory --host dns01 | jq '{ansible_host, ansible_user}'
admin@adm01:~/src/ansible$ git status --short
```

**Étape 3 — La commande `ssh` exacte, rejouée à la main.**

```
admin@adm01:~/src/ansible$ uv run ansible dns01 -m ansible.builtin.ping -vvvv 2>&1 | grep -m1 'SSH: EXEC'
<10.10.20.253> SSH: EXEC ssh -vvv -C -o ControlMaster=auto -o ControlPersist=60s -o KbdInteractiveAuthentication=no … -o 'User="admin"' -o ConnectTimeout=10 -o 'ControlPath="/home/admin/.ansible/cp/4f2a1c9e0b"' 10.10.20.253 '/bin/sh -c '"'"'echo ~admin && sleep 0'"'"''
admin@adm01:~$ ssh -o ControlPath=none -v admin@10.10.20.253 true
```

Le `-o ControlPath=none` n'est pas un détail : une connexion maîtresse encore ouverte (multiplexage de `~/.ssh/config` ou socket d'Ansible dans `~/.ansible/cp`) ferait **réussir** le test à la main alors que toute nouvelle connexion échoue.

**Variante 1 — clés d'hôte de `git01` régénérées.**

```
git01 | UNREACHABLE!: Failed to connect to the host via ssh: @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
…
Host key verification failed.
```

`git push` vers `git@git01.par1.medisphere.internal` échoue de la même façon (même `sshd`). Avant d'accepter quoi que ce soit, il faut prouver que la nouvelle clé est celle de `git01` et pas celle d'un intermédiaire : on la lit **par un autre canal** (l'agent QEMU, qui ne passe pas par le réseau) et on compare avec ce que présente le serveur.

```
root@pve01:~# qm guest exec 1004 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
{ "exitcode" : 0, "out-data" : "256 SHA256:Qm4Lk…Zt0 root@git01 (ED25519)\n", … }
root@pve01:~# qm guest exec 1004 -- ls -l --time-style=full-iso /etc/ssh/
admin@adm01:~$ ssh-keyscan -t ed25519 10.10.20.12 2>/dev/null | ssh-keygen -lf -
256 SHA256:Qm4Lk…Zt0 10.10.20.12 (ED25519)
```

Mêmes empreintes, fichiers de clés récents : la clé a été régénérée **sur** `git01` (journal : `journalctl -u ssh` montre le redémarrage ; personne n'a prévenu). Cause racine : clés d'hôte recréées hors procédure. Correctif : retirer les anciennes entrées puis accepter la nouvelle clé, une fois prouvée :

```
admin@adm01:~$ ssh-keygen -R 10.10.20.12 ; ssh-keygen -R git01 ; ssh-keygen -R git01.par1.medisphere.internal
admin@adm01:~$ ssh -o ControlPath=none -o StrictHostKeyChecking=ask git01 true      # répondre yes après comparaison
admin@adm01:~$ ssh -o ControlPath=none -T git@git01.par1.medisphere.internal         # « Welcome to GitLab »
```

À répercuter partout où la clé de `git01` est connue : `runner01` (`known_hosts` de `gitlab-runner` si des jobs clonent en SSH), le `known_hosts` de la CI de `plateforme/ansible` (variable `SSH_KNOWN_HOSTS` de M04-E27 si tu l'as créée), Semaphore (`sem01`). L'annulation de la panne détecte que `adm01` accepte les nouvelles clés et les **garde**.

`host_key_checking = False` n'est pas un correctif : il supprime exactement le contrôle qui vient de te protéger (une machine qui se fait passer pour `git01` recevrait tes playbooks, tes secrets déchiffrés et tes commandes `become`).

**Variante 2 — `ansible_user: root` pour le groupe `role_runner`.**

```
runner01 | UNREACHABLE!: Failed to connect to the host via ssh: root@10.10.20.15: Permission denied (publickey).
admin@adm01:~/src/ansible$ git status --short
?? inventories/lab/group_vars/role_runner/zz-connexion.yml
admin@adm01:~/src/ansible$ uv run ansible-inventory --host runner01 | jq .ansible_user
"root"
```

`root` est refusé par `sshd` (`PermitRootLogin no` du rôle `ssh_durci`). Si ton rôle ne l'impose pas encore, c'est la commande forcée que cloud-init place dans `/root/.ssh/authorized_keys` qui répond (« Please login as the user "admin" rather than the user "root" ») : la tâche échoue alors autrement, mais la cause est la même. Cause racine : une variable de connexion posée au niveau d'un groupe (et `group_vars/<groupe>` l'emporte sur `group_vars/all`). Correctif : supprimer le fichier, et répondre à l'argument de Lucas : on se connecte en `admin` et on **élève** (`become`) seulement ce qui en a besoin ; la documentation de GitLab Runner parle de l'utilisateur du **service**, pas de celui de la connexion d'administration.

**Variante 3 — `ansible_host` de `dns01` pointé vers 10.10.20.253.**

```
dns01 | UNREACHABLE!: Failed to connect to the host via ssh: ssh: connect to host 10.10.20.253 port 22: No route to host
admin@adm01:~/src/ansible$ grep -rn ansible_host inventories/lab/host_vars/dns01/
inventories/lab/host_vars/dns01/zz-migration.yml:3:ansible_host: 10.10.20.253
```

`No route to host` (et non `Connection timed out`) : `gw01` route bien vers le VLAN 20 mais personne ne répond à l'ARP pour .253 ; il renvoie un ICMP « hôte injoignable ». `host_vars/dns01/` (dossier) est chargé **après** une éventuelle valeur du fichier d'inventaire et l'emporte (`inventory host_vars` > `inventory file host vars`). Cause racine : un reste d'essai de migration (adresse de la plage de tests .250-.254) rangé sous `dns01`. Correctif : supprimer le fichier ; une migration se prépare sur une copie de l'inventaire, jamais dans `host_vars/` du socle.

**Variante 4 — compte `admin` expiré sur `runner01`.**

```
runner01 | UNREACHABLE!: Failed to connect to the host via ssh: Your account has expired; please contact your system administrator.
Connection closed by 10.10.20.15 port 22
```

La clé est acceptée, puis PAM (pile `account` de `sshd`) refuse la session. `ssh runner01` échoue aussi : on passe par l'agent.

```
root@pve01:~# qm guest exec 1007 -- chage -l admin
… "out-data" : "Last password change : …\nPassword expires : never\n…\nAccount expires : Jan 01, 1970\n…"
root@pve01:~# qm guest exec 1007 -- journalctl -u ssh -n 5 --no-pager
… pam_unix(sshd:account): account admin has expired (account expired)
root@pve01:~# qm guest exec 1007 -- chage -E -1 admin
```

Cause racine : `chage -E 0` (expiration au 1er janvier 1970) lors d'une « revue des comptes » qui visait un autre compte. Correctif : `chage -E -1 admin` (pas d'expiration ; c'est l'état normal d'un compte d'administration cloud-init), puis retrouver qui a lancé la revue et sur quelle liste.

**Vérification** : `lab/bin/check 04 35`, puis le `--check` complet du socle ; `lab/bin/break 04 35 --annuler` pour clore.

**Explications**

Ansible distingue `UNREACHABLE` (le plugin de connexion lève une erreur : code 255 de `ssh`, ou impossibilité de créer le dossier temporaire) de `FAILED` (le module a tourné et a échoué). Un hôte `UNREACHABLE` est retiré du jeu pour la suite (sauf `ignore_unreachable`), et le récapitulatif le compte à part. Les paramètres de connexion (`ansible_host`, `ansible_user`, `ansible_port`, `ansible_ssh_common_args`…) sont des **variables** : elles suivent la précédence comme les autres, et c'est pour ça qu'un fichier oublié dans `group_vars/` ou `host_vars/` peut couper un hôte.

**Alternatives**
- `ansible-console` ou `ansible -m ansible.builtin.raw -a 'id'` pour tester la connexion sans Python.
- Certificats d'hôte SSH signés par une CA (M06, step-ca) : `known_hosts` fait confiance à la CA, une régénération signée ne déclenche plus d'alerte, une clé non signée oui.

**Pièges classiques**
- Tester à la main en profitant d'une connexion multiplexée encore ouverte : tout « marche ».
- `ssh-keygen -R` puis accepter aveuglément la nouvelle clé (`StrictHostKeyChecking=accept-new`) sans comparer les empreintes.
- Corriger dans `hosts.yml` alors que la valeur vient d'un `host_vars/` qui l'emporte.
- Oublier les autres consommateurs de la clé d'hôte (CI, Semaphore, `runner01`).

**En production chez MédiSphère**
Un playbook `verifier-acces.yml` (connexion, `sudo -n`, Python, espace de `~/.ansible/tmp`) ouvre chaque intervention et chaque pipeline ; la CI échoue sur un `UNREACHABLE` au lieu de le laisser passer ; les clés d'hôte sont signées par la CA SSH (M06) ; la « revue des comptes » est elle-même un playbook relu en MR, pas une série de `chage` à la main.

---

### M04-E36 — Panne : le playbook passe mais rien ne change

**Démarche de diagnostic**

*Symptôme* : bannière ajoutée au rôle `ssh_durci` (le rôle de M04-E11 a une variable prévue, `ssh_durci_banniere`, chemin d'un fichier que le rôle doit aussi déposer, par exemple `/etc/issue.net`), passage sur `dns01` sans erreur, `sudo sshd -T | grep -i banner` → `banner none`.

*Hypothèses*, dans l'ordre de la chaîne : (a) le code exécuté n'est pas celui que j'ai modifié ; (b) la tâche n'a pas été sélectionnée ; (c) elle a tourné sur une autre machine ; (d) le fichier a changé mais le service ne l'a pas pris en compte (rechargement, ordre de lecture).

**Une commande par maillon.**

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --limit dns01 --list-tasks | grep -i ssh_durci   # (a)(b)
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --limit dns01 --tags ssh -vv --check --diff | grep -E 'task path|changed|---|\+\+\+'  # (a)
admin@adm01:~/src/ansible$ uv run ansible-config dump --only-changed                                      # (b)
admin@adm01:~/src/ansible$ uv run ansible-inventory --host dns01 | jq .ansible_host                      # (c)
admin@adm01:~/src/ansible$ uv run ansible dns01 -m ansible.builtin.command -a hostname                   # (c)
admin@dns01:~$ sudo grep -rin banner /etc/ssh/sshd_config /etc/ssh/sshd_config.d/                         # (d)
admin@dns01:~$ sudo sshd -T | grep -i banner                                                             # (d)
admin@adm01:~/src/ansible$ git status --short
```

(Les étiquettes et le nom du playbook sont ceux de ton projet : `site.yml` ou `socle-base.yml`, `--tags ssh` ou `ssh_durci`.)

**Variante 1 — copie figée du rôle dans `playbooks/roles/ssh_durci`.**

`--list-tasks` montre bien les tâches `ssh_durci : …`, mais `-vv` révèle leur fichier :

```
task path: /home/admin/src/ansible/playbooks/roles/ssh_durci/tasks/main.yml:2
```

et `git status` : `?? playbooks/roles/`. Ansible cherche un rôle appelé par son nom court d'abord dans un dossier `roles/` **à côté du playbook**, ensuite dans `roles_path`, enfin dans le dossier du playbook lui-même. La copie de Lucas (prise avant ta modification) gagne : ta modification de `roles/ssh_durci` n'est jamais lue, le playbook passe, `changed=0`. Correctif : supprimer `playbooks/roles/` (après avoir vérifié qu'il ne contient rien d'autre d'utile : `diff -r playbooks/roles/ssh_durci roles/ssh_durci`), relancer.

**Variante 2 — `[tags] run = pare_feu` dans `ansible.cfg`.**

```
admin@adm01:~/src/ansible$ uv run ansible-config dump --only-changed | grep TAGS
TAGS_RUN(/home/admin/src/ansible/ansible.cfg) = ['pare_feu']
admin@adm01:~/src/ansible$ git diff ansible.cfg
+[tags]
+# Lucas : tests du rôle pare_feu sur gw01, ne lancer que ses tâches (provisoire)
+run = pare_feu
```

La configuration fixe la valeur **par défaut** de `--tags` : toutes les tâches non étiquetées `pare_feu` sont sautées, sans message (seule la collecte des faits, étiquetée `always`, tourne : récapitulatif `ok=1 changed=0`). `--list-tasks` ne montre plus que les tâches `pare_feu`. Correctif : retirer la section (un réglage de débogage n'a rien à faire dans le `ansible.cfg` partagé ; pour soi : `ANSIBLE_RUN_TAGS` le temps d'une commande).

**Variante 3 — `/etc/ssh/sshd_config.d/00-infoger.conf` sur `dns01`.**

Le passage modifie bien le fichier du rôle (`--diff` le montre, le handler recharge `ssh`), mais :

```
admin@dns01:~$ sudo grep -rin banner /etc/ssh/sshd_config.d/
/etc/ssh/sshd_config.d/00-infoger.conf:3:Banner none
/etc/ssh/sshd_config.d/01-ssh-durci.conf:35:Banner /etc/issue.net
```

`sshd_config(5)` : « pour chaque mot-clé, la **première** valeur obtenue est utilisée ». Les fichiers inclus sont lus par ordre alphabétique, et l'`Include` est en tête de `sshd_config` : `00-infoger.conf` passe avant le fichier du rôle. (C'est l'inverse de systemd, où la dernière surcharge l'emporte : deux logiques à ne pas confondre.) Le rôle de M04-E11 contrôle déjà la configuration **effective** après rechargement… mais seulement pour les réglages de sa liste (`permitrootlogin`, `passwordauthentication`, `maxauthtries`…) : `banner` n'y est pas, d'où un passage vert. Cause racine : un fichier hérité du prestataire, non géré par Ansible. Correctif propre : décider du sort du fichier avec son propriétaire (le contrat InfoGér est terminé), puis le **gérer** : l'ajouter à `ssh_durci_fichiers_obsoletes` (variable du rôle prévue pour retirer les fichiers posés à la main, M04-E11) et ajouter `('banner ' ~ ssh_durci_banniere) in _ssh_durci_effectif.stdout_lines` aux assertions d'état effectif du rôle (quand une bannière est demandée). La prochaine fois, le rôle échouera avec son message « un autre fichier lu avant lui fixe ces valeurs ».

**Variante 4 — `ansible_host` de `dns01` redirigé vers la VM 2040.**

```
admin@adm01:~/src/ansible$ uv run ansible-inventory --host dns01 | jq .ansible_host
"10.10.99.143"
admin@adm01:~/src/ansible$ uv run ansible dns01 -m ansible.builtin.command -a hostname
dns01 | CHANGED | rc=0 >>
dns01-essai
admin@adm01:~/src/ansible$ git status --short
?? inventories/lab/host_vars/dns01/zz-essai.yml
```

Le rôle a été appliqué… à `dns01-essai` (VM 2040, clone de l'image dorée sur `vsandbox`). Le `Host 10.10.99.*` de `~/.ssh/config` (pas de vérification de clé d'hôte pour le bac à sable, M00-E15) a même rendu la connexion silencieuse. Correctif : supprimer le fichier, vérifier que plus rien ne vise une adresse de `vsandbox` (`grep -rn '10\.10\.99\.' inventories/`), détruire la VM 2040 **après** avoir vérifié ce qu'elle est (`qm config 2040` : nom, étiquette `env-m04`, description) : `qm stop 2040 && qm destroy 2040 --purge`. Prévention : les essais se font dans Molecule (M04-E24), jamais en redirigeant un hôte du socle.

**Dans toutes les variantes** : appliquer le rôle sur `dns01`, vérifier `sshd -T` (`banner /etc/issue.net`) et une nouvelle connexion (`ssh -o ControlPath=none dns01 true` affiche le texte), relancer : `changed=0`.

**Explications**

Un récapitulatif sans `failed` dit seulement que les tâches **sélectionnées**, du code **résolu**, sur les hôtes **ciblés**, n'ont pas échoué. Chaque maillon a son instrument : `--list-tasks` et `task path` (code), `ansible-config dump` et `--list-tasks` (sélection), `ansible-inventory --host` et un `hostname` (cible), `sshd -T`/`systemctl show` (effet). Le rôle `ssh_durci` de M04-E11 a la bonne structure (contrôle de `sshd -T` après rechargement) : chaque réglage ajouté au rôle doit l'être **aussi** à ses assertions, sinon le contrôle ne couvre pas la demande.

**Alternatives** : `ansible-playbook --check --diff` sur la cible montre déjà si le fichier changerait ; un test Molecule `verify` qui lit `sshd -T` aurait attrapé les variantes 1 à 3 (pas la 4, qui est un problème d'inventaire de production).

**Pièges classiques**
- Ajouter `--tags ssh_durci` en ligne de commande « pour forcer » (variante 2 contournée, pas corrigée).
- Ajouter le réglage dans `/etc/ssh/sshd_config` avec un `lineinfile` : il est lu **après** les fichiers inclus et ne gagne pas non plus.
- Supprimer `00-infoger.conf` à la main sans changer le rôle : il reviendra au prochain script du prestataire, ou un autre fichier prendra sa place.
- Conclure de `changed: true` sur la tâche que le service a la nouvelle valeur.

**En production chez MédiSphère**
Les rôles de sécurité vérifient l'état **effectif** (`sshd -T`, `systemctl show`) de **chaque** réglage qu'ils posent ; `ssh_durci` échoue si un fichier qu'il ne gère pas contredit ses réglages ; un test de dépôt refuse `playbooks/roles/` et toute section `[tags]` dans `ansible.cfg` ; les audits de Sophie lisent `sshd -T` collecté par le contrôle de dérive.

---

### M04-E37 — Panne : la variable n'a pas la valeur attendue

**Démarche de diagnostic**

*Symptôme* : `dns01` en UTC, le reste du socle en Europe/Paris ; le rôle `base` est censé imposer Europe/Paris.

**Étape 1 — Mesurer l'étendue avant de toucher à quoi que ce soit.** (Variable du rôle : `base_fuseau_horaire`, dans `roles/base/defaults/main.yml` depuis M04-E10 ; adapte si ton rôle la nomme autrement.)

```
admin@adm01:~/src/ansible$ uv run ansible socle -m ansible.builtin.command -a 'timedatectl show -p Timezone --value' -o
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --check --diff --tags base 2>&1 | grep -B2 -A6 -i timezone
```

Selon la variante, le `--check` annonce un passage en UTC sur `dns01` seul (variantes 1 et 4) ou sur **tout le socle** (variantes 2 et 3). C'est ce que Nadia redoutait : la « correction par relance » aurait mis tout le socle en UTC.

**Étape 2 — Pourquoi l'ad hoc ne suffit pas.**

```
admin@adm01:~/src/ansible$ uv run ansible-inventory --host dns01 | jq .base_fuseau_horaire
```

`ansible-inventory` ne montre que l'inventaire (fichiers d'inventaire, `group_vars`/`host_vars` de l'inventaire). Il ne voit ni les `vars/` d'un rôle, ni les `group_vars` voisins du **playbook**, ni les `vars` de jeu. Pour la valeur effective, il faut un jeu :

```yaml
# /tmp/sonde.yml n'irait pas : les group_vars du playbook se cherchent à côté du playbook.
# playbooks/sonde-fuseau.yml (non commité)
- name: Valeur effective de base_fuseau_horaire
  hosts: dns01
  gather_facts: false
  roles:
    - role: base
  tasks:
    - name: Afficher
      ansible.builtin.debug:
        var: base_fuseau_horaire
      tags: [sonde]
```

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/sonde-fuseau.yml --check --tags sonde
ok: [dns01] => { "base_fuseau_horaire": "UTC" }
admin@adm01:~/src/ansible$ grep -rn 'base_fuseau_horaire' inventories/ playbooks/ roles/ ; git status --short
```

**Étape 3 — Classer les définitions.** Extrait utile de la liste officielle (*Understanding variable precedence*, du moins au plus prioritaire) :

| Rang | Source | Où dans le projet |
|---|---|---|
| 2 | `defaults/` du rôle | `roles/base/defaults/main.yml` (Europe/Paris) |
| 4 | `group_vars/all` de l'inventaire | `inventories/lab/group_vars/all/` |
| 5 | `group_vars/all` du playbook | `playbooks/group_vars/all/` |
| 6 | `group_vars/<groupe>` de l'inventaire | `inventories/lab/group_vars/role_dns/` |
| 9 | `host_vars/` de l'inventaire | `inventories/lab/host_vars/dns01/` |
| 12 | `vars:` du jeu | |
| 15 | `vars/` du rôle | `roles/base/vars/main.yml` |
| 22 | `-e` | (toujours gagnant) |

**Variante 1 — `inventories/lab/host_vars/dns01/zz-infoger.yml`** (rang 9). Visible dans `ansible-inventory --host dns01`. Touche `dns01` seul. Correctif : supprimer le fichier.

**Variante 2 — `roles/base/vars/main.yml`** (rang 15). **Invisible** dans `ansible-inventory` ; l'emporte sur tout l'inventaire, donc sur **tous** les hôtes : le `--check` de l'étape 1 prévoit UTC partout. C'est l'erreur classique « valeur mise dans `vars/` au lieu de `defaults/` » : `vars/` sert aux constantes internes du rôle, que l'inventaire ne doit pas pouvoir changer. Correctif : retirer la ligne (ou le fichier s'il ne contient que ça).

**Variante 3 — `playbooks/group_vars/all/zz-lucas.yml`** (rang 5). Invisible dans `ansible-inventory` ; l'emporte sur `inventories/lab/group_vars/all` pour tous les playbooks de `playbooks/`. Piège : la commande ad hoc `ansible dns01 -m debug -a var=base_fuseau_horaire` montre Europe/Paris (elle ne charge pas les `group_vars` du playbook), le jeu montre UTC. Correctif : supprimer `playbooks/group_vars/` ; règle d'équipe : un seul emplacement de `group_vars`, celui de l'inventaire.

**Variante 4 — `inventories/lab/group_vars/role_dns/zz-dns.yml`** (rang 6). Un groupe enfant l'emporte sur `all` ; touche tous les membres de `role_dns` (aujourd'hui `dns01`, demain `dns02`). Correctif : supprimer le fichier.

**Dans tous les cas** : remettre `dns01` à l'heure par le **rôle**, pas par `timedatectl` à la main :

```
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --tags base --limit dns01 --check --diff
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --tags base --limit dns01
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --tags base --check   # aucun changement de fuseau prévu
```

**Explications**

La précédence est **par source**, pas par fichier : à rang égal (plusieurs fichiers d'un même dossier `host_vars/dns01/`), l'ordre alphabétique des fichiers décide, ce qui explique les préfixes `zz-` des pannes. Les valeurs sont évaluées **paresseusement** : la valeur affichée par la sonde est celle qu'utiliserait la tâche du rôle. Le changement de fuseau de `dns01` est visible tout de suite (journaux en UTC), mais l'origine (la surcharge) n'agit qu'au prochain passage : c'est ce décalage qui rend ce genre de panne trompeur.

**Alternatives**
- Le module `ansible.builtin.debug` avec `var: hostvars['dns01']['base_fuseau_horaire']` dans un jeu sur `localhost` donne aussi la valeur d'inventaire, pas celle des rôles.
- `ansible-playbook … -e base_fuseau_horaire=Europe/Paris` « corrige » le passage : c'est un contournement (rang 22), pas une correction, et il masque la définition fautive.

**Pièges classiques**
- Croire `ansible-inventory --host` exhaustif.
- Relancer `site.yml` sans `--check` (variantes 2 et 3 : tout le socle en UTC).
- Corriger par `timedatectl set-timezone` sur `dns01` : le prochain passage remet UTC.
- Ajouter une valeur Europe/Paris **plus prioritaire** au lieu de retirer la fausse : deux définitions qui s'affrontent, la panne reviendra.

**En production chez MédiSphère**
Convention d'équipe écrite dans `CONTRIBUTING.md` : variables d'un rôle préfixées par son nom, valeurs par défaut dans `defaults/`, surcharges uniquement dans `inventories/<env>/group_vars|host_vars`, jamais de `group_vars` à côté des playbooks ni de `vars/` modifiables ; un test de dépôt (la sonde, en CI) vérifie les valeurs effectives des variables critiques (fuseau, serveurs de temps, comptes) pour chaque groupe ; Molecule vérifie l'état effectif (`timedatectl`).

---

### M04-E38 — Panne : « Decryption failed »

**Démarche de diagnostic**

*Symptôme* : tout s'arrête au chargement de l'inventaire (les `group_vars/all/vault.yml` sont déchiffrés à ce moment-là), même `ansible-inventory --graph`.

La chaîne, depuis M04-E30 : `ansible.cfg` → `vault_identity_list = lab@outils/vault-pass-client.sh, critique@outils/vault-pass-client.sh` (et `vault_id_match = True`) → le script client lit, pour l'identité `lab`, `~/.config/workbook/ansible-vault-lab.pass` ou à défaut `ansible-vault.pass` (et refuse un fichier lisible par d'autres) → le mot de passe déchiffre les fichiers dont l'en-tête porte l'étiquette `lab`. Si ton projet en est resté au fichier lu directement (`lab@~/.config/workbook/ansible-vault.pass`, M04-E12), la chaîne est plus courte, mêmes maillons.

**Étape 1 — La commande la plus courte et son message exact.**

```
admin@adm01:~/src/ansible$ uv run ansible-vault view inventories/lab/group_vars/all/vault.yml >/dev/null
```

| Message | Ce qu'il dit |
|---|---|
| `Decryption failed (no vault secrets were found that could decrypt)` | des secrets ont été essayés (ou aucun n'était éligible), aucun ne convient |
| `Error in vault password file loading (lab): Vault password client script … returned non-zero (1) when getting secret for vault-id=lab: b'vault-pass-client : refus, … (mode 644, attendu 600)'` | le script client refuse le fichier (droits) ; suivi de `Decryption failed` |
| `Problem running vault password script … ([Errno 8] Exec format error …). If this is not a script, remove the executable bit from the file.` | (identité lue directement dans le fichier) le fichier de mot de passe est **exécutable** : Ansible l'exécute |
| `Vault format unhexlify error` / `Vault vaulttext format error` | le fichier chiffré est abîmé (structure) |

(`>/dev/null` : on ne veut pas afficher les secrets si ça marche. Les avertissements qui précèdent l'erreur sont souvent plus parlants qu'elle.)

**Étape 2 — Inventaire de la chaîne, sans rien afficher en clair.**

```
admin@adm01:~/src/ansible$ uv run ansible-config dump --only-changed | grep -i vault
DEFAULT_VAULT_ID_MATCH(/home/admin/src/ansible/ansible.cfg) = True
DEFAULT_VAULT_IDENTITY_LIST(/home/admin/src/ansible/ansible.cfg) = ['lab@outils/vault-pass-client.sh', 'critique@outils/vault-pass-client.sh']
admin@adm01:~$ ls -l --time-style=long-iso ~/.config/workbook/ansible-vault*
admin@adm01:~/src/ansible$ outils/vault-pass-client.sh --vault-id lab >/dev/null && echo "le script fournit un secret"
admin@adm01:~/src/ansible$ head -n 1 inventories/lab/group_vars/all/vault.yml
admin@adm01:~/src/ansible$ git status --short ; git diff --stat
```

**Variante 1 — rotation à moitié faite.** Le fichier de mot de passe de l'identité `lab` modifié hier soir, un `….pass.ancien-AAAAMMJJ` à côté, aucun fichier chiffré modifié dans Git : le mot de passe a changé, les fichiers sont toujours chiffrés avec l'ancien. Test sans rien écraser :

```
admin@adm01:~/src/ansible$ uv run ansible-vault view --vault-id lab@$HOME/.config/workbook/ansible-vault.pass.ancien-20261006 inventories/lab/group_vars/all/vault.yml >/dev/null && echo "ancien mot de passe valide"
```

Deux issues correctes :
- **revenir en arrière** (le plus sûr à 16 h) : remettre l'ancien mot de passe dans le fichier (`mv`, mode 600), puis planifier une vraie rotation ;
- **terminer la rotation** : `ansible-vault rekey --vault-id lab@<ancien> --new-vault-id lab@<nouveau>` sur **tous** les fichiers chiffrés sous l'identité `lab` et chaînes `!vault` du projet (`grep -rl '\$ANSIBLE_VAULT;1.2;AES256;lab' inventories/ roles/ playbooks/`), MR, mise à jour de la variable CI de type fichier `VAULT_PASS_LAB` (M04-E27/E30) et du secret de Semaphore, **puis** suppression de l'ancien fichier.

Dans les deux cas, l'ancien fichier ne doit pas rester (`shred -u` ou `rm` : il est sur un disque chiffré ou non, c'est la politique de Sophie qui tranche).

**Variante 2 — droits « harmonisés ».** `ls -l` : `-rw-r--r--` (ou `-rwx------` si ton projet lit le fichier directement). Avec le script client, le refus est **voulu** (M04-E30 : un secret lisible par d'autres est refusé) et le message le dit. Sans script client, un fichier de mot de passe exécutable est traité comme un **script** et son exécution échoue (`Exec format error`). Correctif : `chmod 600`. Expliquer à Lucas que « harmoniser les droits » d'un dossier de secrets (`chmod -R 644`, `chmod -R 700`) change le sens ou la recevabilité d'un fichier pour Ansible.

**Variante 3 — en-tête réétiqueté.**

```
admin@adm01:~/src/ansible$ head -n 1 inventories/lab/group_vars/all/vault.yml
$ANSIBLE_VAULT;1.2;AES256;critique
admin@adm01:~/src/ansible$ git diff --stat
 inventories/lab/group_vars/all/vault.yml | 2 +-
```

Une seule ligne a changé : l'en-tête. L'étiquette d'un fichier 1.2 n'est qu'une **indication** : le corps chiffré n'en dépend pas. Avec `vault_id_match = True`, Ansible n'essaie que le secret étiqueté `critique`… qui n'est pas le bon mot de passe → `Decryption failed`. (Si ton projet n'avait pas `vault_id_match`, la panne l'a ajouté, avec l'étiquette `prod` : `git diff ansible.cfg` le montre.) Lucas croyait « classer » le fichier en le réétiquetant ; un changement d'identité se fait par `ansible-vault rekey --vault-id lab@… --new-vault-id critique@…`, avec le mot de passe de l'identité cible. Correctif : `git restore inventories/lab/group_vars/all/vault.yml` (et `ansible.cfg` si besoin).

**Variante 4 — fichier rechiffré par Lucas.** `git diff --stat` : `vault.yml` entièrement modifié, en-tête normal, `ansible.cfg` et mot de passe intacts. Le fichier a été rechiffré (`rekey`) avec un mot de passe inconnu. Correctif : `git restore inventories/lab/group_vars/all/vault.yml` (le dépôt fait foi) ; si Lucas avait **aussi** modifié des valeurs, elles sont à refaire avec le bon mot de passe.

**Vérification** : `ansible-inventory --graph`, un `--check` du socle, `lab/bin/check 04 38`, puis `--annuler`. Vérifie aussi l'historique du shell (`history | grep -i vault`) : aucun mot de passe tapé en clair.

**Explications**

Ansible lit les secrets de coffre depuis `vault_identity_list` (et `--vault-id`, `--vault-password-file`) : chaque entrée `étiquette@source`, où la source est un fichier (lu, blancs de fin retirés), un script exécutable (un script dont le nom finit par `-client` reçoit `--vault-id <étiquette>`), ou `prompt`. Un secret introuvable n'est qu'un **avertissement** : l'erreur ne vient qu'au moment où un fichier en a besoin. Un fichier chiffré au format 1.2 porte une étiquette dans son en-tête ; sans `vault_id_match`, elle oriente l'ordre des essais sans les restreindre ; avec, elle les restreint. Le message `Decryption failed` est générique : il faut regarder **quels** secrets étaient disponibles, et les avertissements qui précèdent.

**Alternatives** : un script client qui interroge un gestionnaire de secrets (`pass`, `secret-tool` ou, au module 25, Vault/OpenBao) au lieu de lire un fichier sur le disque de `adm01` ; SOPS + age pour les secrets partagés entre outils (module 25).

**Pièges classiques**
- `ansible-vault decrypt` « pour voir » : le fichier passe en clair dans l'arbre de travail, et un `git add -A` plus tard il est dans l'historique. On utilise `view` (et jamais `cat` du résultat dans un terminal partagé).
- Désactiver `vault_id_match` ou ajouter `--vault-password-file` à la main dans les commandes pour « faire passer » : la cause reste.
- Oublier la CI et Semaphore après une rotation.

**En production chez MédiSphère**
La rotation du mot de passe du coffre est un runbook (RB-04x) exécuté en entier ou pas du tout : nouveau secret, `rekey` de tous les fichiers en une MR, mise à jour des variables CI et de Semaphore, test, suppression de l'ancien ; inscription au registre des secrets (`docs/socle/registre-secrets.md`). Au module 25, le mot de passe sort du disque de `adm01` (script client vers OpenBao).

---

### M04-E39 — Panne : l'inventaire dynamique est vide

**Démarche de diagnostic**

*Symptôme* : `ansible-inventory -i inventories/lab/proxmox.yml --graph` n'affiche aucun hôte sous `socle` ni `role_*`.

**Étape 1 — Lire tout, en verbeux.**

```
admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/proxmox.yml --graph -vvv 2>&1 | less
admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/proxmox.yml --list | jq 'keys'
```

Trois signatures :
- **un avertissement d'analyse** (`Failed to parse inventory with 'auto' plugin`, `Unable to parse … as an inventory source`, `No inventory was parsed`) : le plugin a échoué ;
- **aucun avertissement et aucun hôte** : le plugin a réussi, l'API a répondu… vide ;
- **des hôtes, mais dans des groupes `proxmox_*` seulement** : l'API répond, les groupes du projet ne se construisent pas.

**Étape 2 — L'API avec le même jeton, sans Ansible.**

```
admin@adm01:~$ set -a; . ~/.config/workbook/pve-ansible.env; set +a
admin@adm01:~$ curl -s -o /tmp/vms.json -w '%{http_code}\n' --cacert "$REQUESTS_CA_BUNDLE" \
    -H @<(printf 'Authorization: PVEAPIToken=%s!%s=%s\n' "$PROXMOX_USER" "$PROXMOX_TOKEN_ID" "$PROXMOX_TOKEN_SECRET") \
    "$PROXMOX_URL/api2/json/cluster/resources?type=vm" && jq '.data | length' /tmp/vms.json && rm /tmp/vms.json
```

(Adapte la variable de CA à ce que ton M04-E13 a mis dans `pve-ansible.env`. L'en-tête est passé par un descripteur pour que le secret n'apparaisse pas dans `ps`.)

**Variante 1 — ACL de l'utilisateur retirées (réponse 200, liste vide).** `curl` : `200`, `0` VM. Aucune erreur nulle part : le jeton est valide, il ne **voit** rien.

```
root@pve01:~# pveum user token permissions wb-ansible@pve ansible --path /pool/lab
root@pve01:~# pveum acl list | grep wb-ansible
│ /pool/lab │ ansible … token … WBAnsible │       (l'ACL du jeton est là, celle de l'utilisateur non)
```

Avec un jeton à **privilèges séparés**, les droits effectifs sont l'**intersection** de ceux de l'utilisateur et de ceux du jeton (M02-E36) : sans ACL utilisateur, l'intersection est vide. Correctif : remettre l'ACL **de l'utilisateur** sur `/pool/lab` avec le rôle `WBAnsible` (celle de M04-E13, pas un rôle plus large) : `pveum acl modify /pool/lab --users wb-ansible@pve --roles WBAnsible`. Puis documenter dans l'inventaire des comptes pourquoi cette ACL est nécessaire, pour que la prochaine revue des accès ne la retire pas.

**Variante 2 — jeton expiré (401).** L'avertissement du plugin cite `401 Client Error: authentication failure for url: …/api2/json/cluster/resources?type=vm` ; `curl` : `401`. Comme `proxmox.yml` est la seule source, le `unparsed_is_failed` posé en M04-E13 transforme cet avertissement en erreur finale (`No inventory was parsed`, code 1) : la dérive de la nuit a dû dire « erreur », pas « conforme ».

```
root@pve01:~# pveum user token list wb-ansible@pve
│ ansible │ … │ expire : <date passée> │ privsep 1 │
```

Correctif : prolonger le jeton (`pveum user token modify wb-ansible@pve ansible --expire <epoch>`) en restant dans la politique d'expiration de Sophie, ou en créer un nouveau (et mettre à jour `pve-ansible.env`, la variable CI et Semaphore) ; inscrire l'échéance au registre des secrets avec une alerte avant expiration.

**Variante 3 — `want_facts: false`.** `curl` : `200`, toutes les VMs ; et pourtant `--list` ne contient **aucun** hôte (seulement des groupes `proxmox_*` vides) : pas d'avertissement non plus.

```
admin@adm01:~/src/ansible$ git diff inventories/lab/proxmox.yml
-want_facts: true
+want_facts: false  # Lucas : inventaire 3 fois plus rapide sans les détails de chaque VM
admin@adm01:~/src/ansible$ uv run ansible-doc -t inventory community.proxmox.proxmox | grep -A3 -i 'want_facts'
```

La documentation le dit : `proxmox_tags_parsed` (et toute la configuration de la VM : `proxmox_ipconfig0`, les étiquettes analysées) n'existent que si `want_facts` est vrai. Or les `filters` de M04-E13 gardent une VM si `'socle' in (proxmox_tags_parsed | default([]))` : sans les faits, la liste vaut `[]`, **toutes** les VMs sont écartées, sans erreur (le `default([])` qui protégeait d'une erreur de modèle masque aussi la panne). Correctif : remettre `want_facts: true`. Pour la vitesse, les vraies options sont `facts_concurrency` (requêtes parallèles), `want_post_filter_facts` avec des `filters` qui n'utilisent que les données de base, et le cache d'inventaire.

**Variante 4 — fichier renommé.**

```
admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/pve-lab.yml --graph -vvv 2>&1 | grep -i proxmox
Skipping due to inventory source not ending in "proxmox.yaml" nor "proxmox.yml"
[WARNING]: Failed to parse inventory with 'auto' plugin: inventory source '…/pve-lab.yml' could not be verified by inventory plugin 'community.proxmox.proxmox'
```

(Et `-i inventories/lab/proxmox.yml` : le fichier n'existe plus, `Unable to parse … as an inventory source`, puis, `unparsed_is_failed` oblige, `No inventory was parsed` et code 1.) Le plugin n'accepte que des fichiers dont le nom finit par `proxmox.yml` ou `proxmox.yaml`. Correctif : `git mv` inverse (ou `lab.proxmox.yml` si la convention de nommage l'exige vraiment, et mettre à jour toutes les références).

**Rendre l'inventaire vide bloquant** (étape 5) :
- `unparsed_is_failed = True` (posé en M04-E13) couvre déjà les variantes 2 et 4 **tant que `proxmox.yml` est la seule source** ; `[inventory] any_unparsed_is_failed = True` va plus loin : toute source illisible fait échouer la commande, même quand une autre (`-i hosts.yml` de secours, inventaire de la flotte) s'analyse encore ;
- `strict: true` n'est **pas** la solution ici : M04-E13 le laisse à `false` exprès (le `compose` d'`ansible_host` échoue pour `gw01`, installé sans cloud-init), et il ne verrait pas la variante 3 (le `default([])` des filtres ne lève aucune erreur) ;
- et surtout une **assertion de nombre**, seule défense contre la variante 1 (réponse vide valide), en tête du playbook de dérive :

```yaml
- name: L'inventaire voit tout le socle
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Cinq hôtes dans socle, un par groupe de rôle
      ansible.builtin.assert:
        that:
          - groups['socle'] | default([]) | length == 5
          - groups['role_dns'] | default([]) | length >= 1
        fail_msg: "Inventaire incomplet ({{ groups['socle'] | default([]) | length }} hôte(s) dans socle) : contrôle de dérive annulé"
```

**Explications**

Le plugin appelle d'abord `/cluster/resources?type=vm`, puis, avec `want_facts`, la configuration et l'état de chaque VM ; il construit des groupes `proxmox_*` (nœud, état, pool), puis les groupes du projet par `keyed_groups`/`groups`, et filtre par `filters`. Par défaut, un échec du plugin n'est qu'un **avertissement** pour Ansible (une source parmi d'autres) — M04-E13 a déjà durci ce cas (`unparsed_is_failed`). Mais une réponse **vide** n'est pas un échec du tout : aucun réglage d'analyse ne la voit. D'où l'adage : un contrôle qui ne voit rien doit le dire.

**Pièges classiques**
- Donner `PVEAuditor` sur `/` au jeton « pour que ça marche » : il verrait les VMs personnelles de `pve01`.
- Désactiver la séparation des privilèges du jeton (même cause, effet plus large).
- Se fier au code retour de `ansible-inventory` : non nul pour les variantes 2 et 4 (grâce à `unparsed_is_failed`), mais 0 pour les variantes 1 et 3 — les plus sournoises.

**En production chez MédiSphère**
Le contrôle de dérive et la CI commencent par l'assertion de nombre ; `any_unparsed_is_failed` est activé ; l'expiration des jetons d'automatisation est suivie (registre des secrets, alerte à J-30) ; une revue des accès Proxmox se fait par MR sur un fichier d'ACL décrit en code (module 05 : provider Proxmox).

---

### M04-E40 — Panne : `sshd` ne redémarre plus après le playbook

**Démarche de diagnostic**

*Symptôme* : `Connection refused` sur `runner01:22` ; le runner prend des jobs (il ne dépend pas de `sshd` : il ouvre lui-même ses connexions **vers** GitLab).

**Étape 1 — Depuis `adm01`.**

```
admin@adm01:~$ ssh -o ControlPath=none -o ConnectTimeout=5 runner01 true
ssh: connect to host 10.10.20.15 port 22: Connection refused
admin@adm01:~$ ping -c 2 10.10.20.15
```

`Connection refused` (RST) et non un délai : la machine répond, rien n'écoute sur le port 22. Ni le réseau, ni le pare-feu.

**Étape 2 — Par l'agent QEMU.**

```
root@pve01:~# qm guest cmd 1007 ping
root@pve01:~# qm guest exec 1007 -- systemctl status ssh --no-pager
root@pve01:~# qm guest exec 1007 -- journalctl -u ssh -n 30 --no-pager
root@pve01:~# qm guest exec 1007 -- sshd -t
```

Lis `out-data` **et** `err-data` : `sshd` écrit ses diagnostics sur la sortie d'erreur.

**Variante 1 — faute de frappe dans un fichier hérité.**

```
"err-data" : "/etc/ssh/sshd_config.d/20-infoger.conf: line 2: Bad configuration option: PermitRootLogn\n/etc/ssh/sshd_config.d/20-infoger.conf: terminating, 1 bad configuration options\n", "exitcode" : 255
```

`ssh.service` lance `sshd -t` en `ExecStartPre` : le démarrage échoue avant même le démon. Correctif : corriger (ou supprimer, décision documentée) le fichier ; `sshd -t` ; `systemctl restart ssh`.

**Variante 2 — clés d'hôte absentes.** `sshd: no hostkeys available -- exiting.` ; `ls /etc/ssh/` : plus de `ssh_host_*`. Elles ont été supprimées (le script de « préparation au clonage » de M03-E07 lancé sur une machine en service : il retire précisément les clés d'hôte). Elles ne reviendront pas : régénère-les (`ssh-keygen -A`), redémarre, puis applique la démarche de M04-E35 variante 1 sur `adm01` (empreinte lue par l'agent, `ssh-keygen -R`, acceptation) et chez les autres consommateurs.

```
root@pve01:~# qm guest exec 1007 -- ssh-keygen -A
root@pve01:~# qm guest exec 1007 -- systemctl restart ssh
root@pve01:~# qm guest exec 1007 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

**Variante 3 — `ListenAddress` d'une adresse qui n'existe pas.** `sshd -t` **réussit** (il ne lie aucun port) ; le journal du service dit :

```
error: Bind to port 22 on 10.10.20.115 failed: Cannot assign requested address.
fatal: Cannot bind any address.
```

Correctif : retirer le fichier `40-ecoute.conf` (ou y mettre l'adresse réelle de `runner01`, 10.10.20.15, si restreindre l'écoute a un sens : sur une machine à une seule interface, non). C'est la variante qui montre la limite de **toute** validation statique.

**Variante 4 — clés privées en 0644.**

```
Permissions 0644 for '/etc/ssh/ssh_host_ed25519_key' are too open.
…
Unable to load host key: /etc/ssh/ssh_host_ed25519_key
sshd: no hostkeys available -- exiting.
```

Correctif : `chmod 600 /etc/ssh/ssh_host_*_key` (et `644` pour les `.pub`), redémarrer. Les clés n'ont pas changé : `adm01` les reconnaît. Chercher la tâche coupable (un `ansible.builtin.file` avec `recurse: true` et `mode:` sur `/etc/ssh`) dans les rôles : `grep -rn 'recurse' roles/`.

**Étape 3 — Retour à la normale**, depuis `adm01` avec une **nouvelle** connexion, puis Ansible :

```
admin@adm01:~$ ssh -o ControlPath=none runner01 'sudo sshd -t && systemctl is-active ssh'
admin@adm01:~/src/ansible$ uv run ansible runner01 -m ansible.builtin.ping
```

Si tu as posé un mot de passe de secours pour la console : `qm guest exec 1007 -- passwd -l admin`.

**Étape 4 — Pourquoi les validations n'ont rien empêché.**

Le rôle de M04-E11 fait déjà bien les choses : `validate: /usr/sbin/sshd -t -f %s` refuse un fichier **du rôle** invalide, le handler `Valider la configuration complète de sshd` lance `sshd -t` (tous les fichiers inclus) **avant** le rechargement, le rechargement (`reloaded`) ne coupe pas le démon, et `sshd -T` est contrôlé ensuite. Mais chaque validation ne vaut que pour **l'instant** où elle tourne et **ce** qu'elle teste :

| Variante | `validate:` (fichier seul) | `sshd -t` du handler (hier soir) | Ce qui a manqué |
|---|---|---|---|
| 1 — faute dans `20-infoger.conf` | ne lit pas ce fichier | ne tourne que si le fichier du rôle change ; et le fichier a été remis **après** le passage (« ménage » de Lucas) | une validation de la configuration complète à **chaque** passage, dont le `--check` nocturne de la dérive |
| 2 — clés d'hôte supprimées | — | idem : supprimées après | le rôle ne vérifie pas la présence des clés |
| 3 — `ListenAddress` inexistante | — | `sshd -t` ne lie aucun port : il **passe** | une vérification que l'adresse appartient à la machine, et la preuve que `sshd` écoute après rechargement |
| 4 — clés privées en 0644 | — | changées après (rôle d'un collègue) | le rôle ne gère pas les droits des clés |

Dans tous les cas, le défaut n'est devenu visible qu'au **redémarrage** de la nuit (mise à jour d'`openssh-server`) : un `sshd` déjà en mémoire continue de tourner avec sa configuration, quel que soit l'état du disque.

**Renforcement du rôle** : [`fichiers/M04-E40/ssh_durci-renforcement.yml`](fichiers/M04-E40/ssh_durci-renforcement.yml), à intégrer au rôle de M04-E11 (testé : `ansible-lint` profil `production` sur le rôle complété) :
- assertion sur les adresses d'écoute éventuelles (`ssh_durci_options.ListenAddress`) : elles doivent appartenir à `ansible_facts['all_ipv4_addresses']` (variante 3) ;
- présence d'au moins une clé d'hôte (variante 2 : le rôle échoue et renvoie au runbook au lieu de régénérer à l'aveugle) et droits `0600 root:root` des clés privées gérés par le rôle (variante 4 : corrigé à chaque passage) ;
- `sshd -t` en tâche de lecture (`changed_when: false`, `check_mode: false`) **à chaque passage** : le `--check` nocturne de M04-E29 voit un fichier invalide ajouté à la main (variante 1) **avant** que la prochaine mise à jour ne redémarre le service ;
- après `flush_handlers`, `wait_for` du port 22 **depuis le contrôleur** : `sshd -T` lit la configuration, il ne prouve pas que le démon écoute.

**Explications**

Trois niveaux de vérification, trois couvertures : la syntaxe d'un fichier (`validate`), la configuration complète à un instant donné (`sshd -t`), le démarrage réel (lier le port, charger les clés). Les deux premiers sont statiques ; le dernier ne se vérifie qu'**en faisant** (rechargement suivi d'un test du port, Molecule). Et comme la configuration peut changer **entre** deux passages, la validation doit aussi tourner dans le contrôle de dérive : c'est ce qui transforme une panne de 6 h du matin en alerte de la veille.

**Pièges classiques**
- Redémarrer la VM « pour voir » : `sshd` ne démarre pas mieux au boot, et tu perds l'état du journal.
- `chmod -R` sur `/etc/ssh` par l'agent pour « remettre les droits » : les `.pub` et `sshd_config` n'ont pas les mêmes droits que les clés privées.
- Accepter les nouvelles clés d'hôte (variante 2) sans comparer les empreintes.
- Laisser un mot de passe de console actif après l'intervention.

**En production chez MédiSphère**
Runbook « plus de SSH sur une VM du socle » : symptôme → `qm guest cmd <VMID> ping` → `systemctl status ssh` / `journalctl -u ssh` / `sshd -t` par l'agent → correctif → nouvelle connexion → `ansible -m ping` → retrait de tout accès de secours. Les rôles qui touchent `sshd` sont testés dans Molecule avec un fichier invalide injecté (étape `prepare`) ; le pipeline d'application (M04-E27) applique d'abord un hôte, vérifie le port 22, puis le reste (`serial`).

---

### M04-E41 — Panne : le playbook est devenu très lent

**Démarche de diagnostic**

*Symptôme* : `site.yml` passe de ~4 min à plus de 20 min, sans erreur.

**Étape 1 — Mesurer.**

```
admin@adm01:~/src/ansible$ time uv run ansible socle -b -m ansible.builtin.command -a true -o
admin@adm01:~/src/ansible$ ANSIBLE_CALLBACKS_ENABLED=ansible.posix.profile_tasks,ansible.posix.timer \
    uv run ansible-playbook playbooks/site.yml --tags base --check
```

`profile_tasks` donne la durée de chaque tâche (cumulée sur les hôtes), `timer` la durée totale. Référence saine sur le socle : la commande ad hoc en 3 à 6 s, chaque tâche du rôle `base` en moins d'une seconde.

**Étape 2 — Décomposer.** Uniforme sur toutes les tâches et tous les hôtes → transport ou parallélisme. Concentré sur un hôte → cet hôte. On compte les connexions :

```
admin@adm01:~/src/ansible$ uv run ansible dns01 -b -m ansible.builtin.command -a true -vvvv 2>&1 | grep -c 'SSH: EXEC'
```

Avec multiplexage et pipelining : 1 ou 2 `EXEC`, la connexion maîtresse est réutilisée (`mux_client_request_session` dans la sortie `-vvvv`). Sans : une négociation SSH complète par commande, et plusieurs commandes par tâche (`mkdir`, `PUT`, `chmod`, exécution, `rm`).

**Étape 3 — Configuration effective, toutes sources.**

```
admin@adm01:~/src/ansible$ uv run ansible-config dump --only-changed
admin@adm01:~/src/ansible$ uv run ansible-config dump -t connection ssh | grep -E '^(ssh_args|pipelining|control_path)'
admin@adm01:~/src/ansible$ uv run ansible-inventory --list | jq '._meta.hostvars | map_values({ansible_ssh_args, ansible_pipelining})'
```

**Variante 1 — `forks = 1`.** `DEFAULT_FORKS(…/ansible.cfg) = 1` ; `git diff ansible.cfg` montre le commentaire de Lucas. Les hôtes sont traités un par un : sur 5 hôtes, environ 5 fois plus long. Mesure : la commande ad hoc passe de ~4 s à ~15 s. Correctif : remettre la valeur du projet (`forks = 20` dans le projet de référence, mesurée et justifiée en M04-E26).

**Variante 2 — `ssh_args` sans multiplexage, pipelining coupé (dans `ansible.cfg`).**

```
ssh_args(/home/admin/src/ansible/ansible.cfg) = -C -o ControlMaster=no -o ServerAliveInterval=30
pipelining(/home/admin/src/ansible/ansible.cfg) = False
```

`ssh_args` **remplace** la valeur par défaut (`-C -o ControlMaster=auto -o ControlPersist=60s`) : plus de multiplexage. Et sans pipelining, chaque tâche fait 4 à 5 allers-retours SSH, chacun avec sa négociation complète (~0,3 à 1 s). Correctif : retirer ces lignes. Si un vrai problème de socket bloqué existait (« ControlSocket … already exists, disabling multiplexing »), le traiter (supprimer le socket orphelin dans `~/.ansible/cp/`), pas désactiver le multiplexage.

**Variante 3 — même chose, par des variables d'inventaire.** `ansible.cfg` est intact et `ansible-config dump` ne montre rien d'anormal : c'est le piège. Les variables `ansible_ssh_args` et `ansible_pipelining` (voir `ansible-doc -t connection ssh`, rubrique `vars` de chaque option) l'emportent sur la configuration :

```
admin@adm01:~/src/ansible$ git status --short
?? inventories/lab/group_vars/all/zz-ssh-debug.yml
```

Correctif : supprimer le fichier. Règle : une option de connexion de débogage se passe en ligne de commande (`-e` ou variable d'environnement) le temps d'un essai, jamais dans `group_vars/all`.

**Variante 4 — `sudo` lent sur `git01`.** `profile_tasks` : toutes les tâches à ~6 s, mais `-vvvv` montre que `dns01`, `gw01`, `runner01` répondent vite et que le jeu attend `git01` à chaque tâche. Sur `git01` :

```
admin@git01:~$ time sudo -n true
real    0m6.04s
admin@git01:~$ sudo grep -n pam_exec /etc/pam.d/sudo
16:session optional pam_exec.so quiet /usr/local/sbin/ms-audit-sudo
admin@git01:~$ cat /usr/local/sbin/ms-audit-sudo
admin@git01:~$ sudo tcpdump -ni any -c 6 'arp and host 10.10.20.250'      # pendant un « sudo true » dans une autre session
ARP, Request who-has 10.10.20.250 tell 10.10.20.12, length 28   (×3, sans réponse)
```

Le script d'« audit HDS » envoie un message syslog en **TCP** vers 10.10.20.250, adresse où rien ne répond : chaque ouverture **et** chaque fermeture de session `sudo` attend l'échec de résolution ARP (~3 s). Avec `become`, chaque tâche paie deux fois. Et avec la stratégie `linear`, tous les hôtes attendent `git01` avant de passer à la tâche suivante : un seul hôte lent ralentit **tout** le playbook. Correctif : retirer la ligne de `/etc/pam.d/sudo` et le script (après avoir prévenu Sophie : le besoin d'audit est réel) ; la journalisation centralisée des `sudo` se fera par journald → collecteur (module 22), de façon **asynchrone**. Prévention : `/etc/pam.d/` est géré par le rôle `base` (fichier connu, dérive détectée).

**Tableau avant/après** (exemple de ce qu'on attend dans le journal) :

| Mesure | Avant | Après |
|---|---|---|
| `ansible socle -b -m command -a true` | 31 s | 4 s |
| `site.yml --tags base --check` (timer) | 18 min 40 s | 3 min 50 s |
| `SSH: EXEC` pour une tâche avec `become` sur `dns01` | 5 | 1 |
| `time sudo -n true` sur `git01` | 6,0 s | 0,02 s |

**Explications**

Le coût d'une tâche est : établissement de connexion (amorti par `ControlPersist`) + transferts (supprimés par le pipelining) + élévation (`sudo`, PAM) + exécution du module. `forks` fixe combien d'hôtes sont traités en parallèle ; la stratégie `linear` attend que **tous** les hôtes aient fini une tâche avant la suivante. `strategy: free` laisserait les hôtes rapides avancer, mais le playbook finirait quand même quand `git01` aurait fini ses 40 tâches à 6 s : on déplace l'attente, on ne la supprime pas. `serial` découpe en lots et ralentit encore.

**Pièges classiques**
- Ajouter `strategy: free` ou augmenter `forks` à 50 sans avoir mesuré.
- Chercher dans `ansible.cfg` seulement (variante 3).
- Oublier que `ansible-config dump --only-changed` sans `-t connection ssh` ne montre pas les options du plugin de connexion lues dans `[ssh_connection]`.

**En production chez MédiSphère**
Le pipeline de dérive publie sa durée et échoue au-delà du double de la durée habituelle ; `profile_tasks` est activé en CI ; la configuration de PAM et de `sudo` est gérée par le rôle `base` ; une mesure de référence (`time ansible socle -b -m command -a true`) figure dans le runbook RB-040.

---

### M04-E42 — Panne : Molecule échoue avant même de tester

**Démarche de diagnostic**

*Symptôme* : `molecule test` (en CI et en local) s'arrête pendant `create`.

**Étape 1 — Isoler l'étape.**

```
admin@adm01:~/src/ansible$ set -a; . ~/.config/workbook/pve-ansible.env; set +a
admin@adm01:~/src/ansible$ uv run molecule destroy -s base && uv run molecule --debug create -s base 2>&1 | tail -40
```

La séquence par défaut de `molecule test` est : `dependency`, `cleanup`, `destroy`, `syntax`, `create`, `prepare`, `converge`, `idempotence`, `side_effect`, `verify`, `cleanup`, `destroy` (ton `.config/molecule/config.yml` de M04-E24 la redéfinit : relis-la). Un échec dans `create` est l'échec d'une **tâche** de ton `create.yml` : lis son module et son message.

**Étape 2 — Les dépendances, sans Molecule.**

```
root@pve01:~# pvesh get /cluster/resources --type vm --output-format json \
    | perl -MJSON::PP -0777 -ne 'for (@{decode_json($_)}) { print "$_->{vmid} $_->{name} [$_->{tags}]\n" if $_->{template} }'
root@pve01:~# qm config <VMID-TEMPLATE> | grep -E '^(agent|tags|name)'
root@pve01:~# pveum role list | grep WBAnsible
root@pve01:~# pveum user token permissions wb-ansible@pve ansible --path /vms/<VMID-TEMPLATE>
root@pve01:~# qm list | awk 'NR==1 || ($1 >= 2045 && $1 <= 2049)'
```

**Variante 1 — plus d'image `current`.** La liste des templates montre `deb13-gold-…` avec `[debian13;gold]` seulement. L'assertion de `create.yml` (M04-E24) le dit : `0 template(s) gold/debian13/current trouvé(s) : il en faut exactement un`. Cause : la rotation (M03-E16) ou une publication a retiré l'étiquette sans la reposer (publication interrompue). Correctif : **pas** de `qm set --tags` à la main sur n'importe quel template : relancer la publication de M03 (`outils/publier-image.sh <VMID>` après `tests/tester-image.sh`) pour l'image validée la plus récente ; vérifier qu'il en reste exactement une.

**Variante 2 — VMID occupés.** `qm list` montre cinq VMs `instance`, étiquettes `env-m04;molecule`, arrêtées, **sans disque** (`qm config 2045` : aucune ligne `scsi0`/`virtio0`). Le garde-fou de `create.yml` refuse de toucher une VM qui n'est pas une instance du scénario : `Le VMID 2045 est occupé par « instance », qui n'est pas une instance de ce scénario. Rien n'a été modifié…`. (Sans ce garde-fou, `proxmox_kvm` aurait répondu `vmid 2045 with VM name … already exists` **sans échouer**, puis l'attente d'adresse aurait expiré : la VM n'a ni disque ni agent.) Ce sont des restes de tests interrompus, ou d'une autre main. Avant de détruire : vérifier que ce sont bien des instances jetables (étiquette `molecule`, plage 2045-2049, pas de disque ou disque de clone, aucune activité) ; puis `qm destroy <VMID> --purge` une par une. Le ménage planifié de M04-E27 (`molecule/_commun/menage.yml`) les aurait-il supprimées ? Regarde ses critères : une VM dont le nom n'est pas celui d'une instance connue est-elle prise en compte ?

**Variante 3 — `VM.Clone` retiré du rôle `WBAnsible`.** Le module de clonage échoue avec `403 Forbidden: Permission check failed (/vms/<VMID-TEMPLATE>, VM.Clone)`. `pveum role list` le confirme. Correctif : remettre exactement la liste de privilèges de M04-E13 (`pveum role modify WBAnsible --privs '<liste>'`, sans `--append` si tu remets toute la liste) ; tracer la décision de la revue des droits (pourquoi `VM.Clone` est nécessaire).

**Variante 4 — agent désactivé sur le template.** Le clone démarre (`qm status 2045` : `running`) mais la tâche « Attendre l'adresse IPv4 de chaque instance » épuise ses 40 essais (environ 3 minutes) ; `qm agent 2045 ping` : `No QEMU guest agent configured`. `qm config <VMID-TEMPLATE>` : `agent: 0`. Le paquet `qemu-guest-agent` tourne dans l'image, mais la VM n'a pas le **canal** virtio-serial de l'agent : Proxmox ne peut pas lui parler. Correctif : `qm set <VMID-TEMPLATE> --agent 1` (vérifie que c'est permis sur un template sur ta version), puis chercher **pourquoi** l'image a été publiée ainsi : un test d'image (M03-E14) qui ne vérifie pas l'agent côté Proxmox est à compléter.

**Étape 3 — Compléter `create.yml`** (étape 5 de l'énoncé). Celui de M04-E24 vérifie déjà l'image `current` (variante 1) et les VMID occupés (variante 2). À ajouter avant le clonage :
- lire la configuration de l'image retenue (`community.proxmox.proxmox_vm_info` avec `config: current`) et exiger l'agent activé (`agent` commençant par `1` ou `enabled=1`) : « l'image <nom> n'a pas l'agent QEMU activé : republier l'image (M03) » au lieu de 3 minutes d'attente ;
- vérifier le droit de clonage du jeton sur l'image avant de cloner (appel `GET /access/permissions?path=/vms/<VMID>` avec le jeton, ou au minimum un `block`/`rescue` autour du clonage qui traduit le `403` en message « droit VM.Clone manquant pour wb-ansible@pve!ansible sur /vms/<VMID> : voir RB-04x »).

**Pièges classiques**
- Donner `Administrator` au jeton pour débloquer la CI.
- Détruire des VMs de la plage sans vérifier leur nature.
- Reposer `current` à la main sur une image non testée.
- Corriger en CI (relancer le job) sans reproduire en local avec `molecule create`.

**En production chez MédiSphère**
Les dépendances de la chaîne de test sont des **contrats** entre équipes (images → configuration) : l'étiquette `current` n'est posée que par la publication outillée, un test de bout en bout (clone + agent + SSH) fait partie de la publication d'image, et un job nocturne nettoie les instances orphelines.

---

### M04-E43 — Astreinte : la chaîne de configuration en panne

**Démarche recommandée**

Les deux pannes tirées sont chacune traitée plus haut (E35 à E42) ; ce qui compte ici est l'**ordre** et la **communication**.

**1. Triage (10 min).** Lance `lab/bin/check 04 35` à `04 42` en parallèle (dans des terminaux séparés ou en tâche de fond), `git status` dans `~/src/ansible`, `ansible socle -m ansible.builtin.ping`, `ansible-vault view … >/dev/null`. Première communication :

> *[07:52] INC-3150 — Statut : en cours d'analyse. Impact : impossible d'appliquer la configuration du socle (fenêtre de 20 h menacée) ; aucun service du socle n'est arrêté pour les utilisateurs. Actions : identification des causes (deux symptômes, peut-être indépendants). Prochain point : 08:25.*

**2. Ordre de traitement**, du plus « instrumental » au moins :

| Priorité | Pannes | Pourquoi d'abord |
|---|---|---|
| 1 | E38 (coffre) | sans coffre, aucune commande Ansible ne se lance : tous les autres tests mentent |
| 2 | E35, E40 (accès aux hôtes) | un hôte injoignable fausse tout ce qu'on mesure dessus |
| 3 | E39 (inventaire) | la cible des commandes |
| 4 | E36, E37 (code et variables) | ce que les commandes font |
| 5 | E41 (performance), E42 (tests) | gênants, pas bloquants pour la fenêtre du soir (sauf si E41 empêche de finir à temps) |

**3. Interférences possibles entre pannes** (ce qui fait la difficulté de l'astreinte) :
- E35 v3 et E36 v4 : deux fichiers dans `host_vars/dns01/`, celui qui sort en dernier dans l'ordre alphabétique gagne. Corriger le premier fait **apparaître** le second (dns01 devient joignable… mais c'est la VM 2040).
- E36 v2, E38 v3, E41 v1/v2 : plusieurs modifications de `ansible.cfg`. `git diff ansible.cfg` montre plusieurs blocs : attribue chacun à un symptôme avant de tout annuler par `git restore` (sinon tu ne sauras pas écrire le post-mortem).
- E35 v1 et E41 v4 : deux pannes sur `git01` ; E35 v4 et E40 : deux sur `runner01` (accès par l'agent pour les deux).
- E38 avec n'importe quelle autre : les contrôles de l'autre panne sont rouges « pour rien » tant que le coffre est fermé.
- E39 v1/v2 et E42 v3 : deux atteintes au compte `wb-ansible@pve` (ACL utilisateur ou jeton ; privilèges du rôle).

**4. Rétablissement.** Après chaque correction, relancer **tous** les contrôles du triage ; ne relancer `site.yml` qu'après un `--check --diff` complet relu (E36, E37). Clore avec `lab/bin/break 04 43 --annuler`.

**5. Post-mortem** (`docs/socle/post-mortems/AAAA-MM-JJ-INC-3150.md`, modèle de M00-E46). Grille d'auto-évaluation :

| Critère | Attendu |
|---|---|
| Chronologie | horodatée, de la détection à la clôture, avec les communications |
| Causes racines | les deux, chacune **prouvée** par une commande et sa sortie (pas « probablement ») |
| Facteurs contributifs | ce qui a permis la panne (modifications sur le bastion hors MR, absence d'assertion d'inventaire, `validate:` partiel…) |
| Détection | comment on l'a su, comment on aurait pu le savoir avant (dérive de `ansible.cfg` et de `/etc/pam.d`, assertion de nombre, Molecule, alerte d'expiration des jetons) |
| Actions | concrètes, chacune avec responsable et échéance, au moins une sur la **prévention** et une sur la **détection** |
| Ton | sans recherche de coupable : « une modification sur le bastion hors MR » plutôt que « Lucas a cassé » |

Facteur commun à presque toutes les pannes de ce palier, à faire apparaître : **des modifications faites hors de la chaîne** (copie de travail sur un bastion partagé, fichiers posés à la main sur les hôtes, droits Proxmox changés en direct). L'action structurante : le bastion n'est pas un poste de développement partagé (comptes nominatifs, M06), et ce qui est appliqué au socle part de `main` par le pipeline ou Semaphore.

---

### M04-E44 — Sous le capot : AnsiballZ et un module maison

**Solution**

Fichiers de référence :

| Élément | Fichier |
|---|---|
| Module | [`fichiers/M04-E44/collections/ansible_collections/medisphere/socle/plugins/modules/systemd_dropin.py`](fichiers/M04-E44/collections/ansible_collections/medisphere/socle/plugins/modules/systemd_dropin.py) |
| Tests unitaires (10 tests) | [`…/socle/tests/unit/plugins/modules/test_systemd_dropin.py`](fichiers/M04-E44/collections/ansible_collections/medisphere/socle/tests/unit/plugins/modules/test_systemd_dropin.py) |
| Usage dans le rôle `base` | [`fichiers/M04-E44/roles/base/tasks/services-resilients.yml`](fichiers/M04-E44/roles/base/tasks/services-resilients.yml), [`defaults-extrait.yml`](fichiers/M04-E44/roles/base/defaults-extrait.yml) ; le handler `Redémarrer chrony` existe déjà dans le rôle (M04-E10) |
| Analyse et réponses aux questions | [`fichiers/M04-E44/docs/analyses/ansiballz.md`](fichiers/M04-E44/docs/analyses/ansiballz.md) |

Nouveau module = nouvelle version **mineure** de la collection : `version: 1.1.0` dans `galaxy.yml` (la collection de M04-E18 est en 1.0.0, d'où `version_added: "1.1.0"` dans la documentation du module) et une entrée dans son `CHANGELOG.md`.

Le module et ses tests ont été exécutés avec ansible-core 2.21.5 et pytest 9 (10 tests verts), et le module en ad hoc en `--check --diff`, réel, idempotent et `state=absent` sur un dossier d'unités temporaire (`unit_dir`). `ansible-lint` (profil `production`) passe sur l'extrait du rôle.

Étapes 1 à 3 (observation d'AnsiballZ) : voir l'analyse, sections 1 et 2. Points à retenir :
- sans pipelining : `mkdir` du dossier temporaire, `PUT` de `AnsiballZ_ping.py`, `chmod u+rwx`, exécution, puis `rm -rf` du dossier (absent avec `ANSIBLE_KEEP_REMOTE_FILES=1`) ;
- la fin du fichier appelle `_ansiballz_main(…)` avec le nom du module, son FQCN, le **profil** de sérialisation (`legacy`), les **paramètres** en JSON (`ANSIBLE_MODULE_ARGS`, y compris les `_ansible_*`) et `zip_data` (zip base64 du module et des `module_utils`) ;
- `explode` écrit le contenu dans `debug_dir/` (code + fichier `args`), `execute` relance le module depuis `debug_dir` avec les arguments du fichier : avec `data=crash`, `ping` lève une exception volontaire et l'on voit la trace complète **sur la cible** ;
- avec pipelining : plus de `PUT`/`chmod`/`rm`, le wrapper arrive sur l'entrée standard de `python3`, mais le zip est toujours écrit puis supprimé dans un dossier `ansible_<module>_payload_…` de `tempfile` (souvent `/tmp`).

Étape 4 (le module), points de conception :
- **contenu entièrement généré** (`generer_contenu`) : en-tête fixe, sections et clés dans l'ordre du dictionnaire (YAML conserve l'ordre), une ligne par valeur de liste, booléens en `yes`/`no` ; refus d'un saut de ligne dans une valeur (sinon `settings` permettrait d'injecter une directive arbitraire) ; idempotence = comparaison de chaînes ;
- **`diff` en liste** : un dictionnaire pour le contenu (avec en-têtes `présent`/`absent`), un second rempli par `set_fs_attributes_if_different` pour les droits ;
- **mode vérification** : tout est calculé, rien n'est écrit, `daemon-reload` jamais lancé ; un fichier absent est compté comme changement ;
- **écriture** : fichier temporaire dans le même dossier, `module.atomic_move` ; `os.makedirs` du dossier `.d/` en 0755 ; suppression du dossier `.d/` s'il devient vide ;
- **droits** : `add_file_common_args=True` + `load_file_common_arguments`, mode `0644` par défaut ;
- **`daemon-reload` seulement si le contenu a changé** (un `chmod` n'en a pas besoin), par `get_bin_path("systemctl", required=True)` + `run_command`, échec explicite avec `rc`/`stdout`/`stderr`.

Étape 5 (tests) : voir le fichier de tests. Lancement :

```
admin@adm01:~/src/ansible$ uv add --dev pytest
admin@adm01:~/src/ansible/collections$ uv run python -m pytest -q ansible_collections/medisphere/socle/tests/unit
..........                                                               [100%]
10 passed in 0.12s
```

(`collections/` doit être le dossier courant : c'est le parent de `ansible_collections/`, ce qui rend `ansible_collections.medisphere.socle` importable.) Dans `.gitlab-ci.yml`, une étape `pytest` dans le job de lint ou un job `test-collection` dans l'étape `test`.

Étape 6 (usage) : inclure `services-resilients.yml` depuis `roles/base/tasks/main.yml` (un `import_tasks` de plus, comme les autres thèmes du rôle) et ajouter la variable par défaut ; le handler `Redémarrer chrony` du rôle sert tel quel. Démonstration sur `dns01` :

```
admin@dns01:~$ systemctl show chrony -p Restart -p NRestarts
Restart=on-failure
NRestarts=0
admin@dns01:~$ sudo systemctl kill -s KILL chrony ; sleep 7 ; systemctl show chrony -p ActiveState -p NRestarts
ActiveState=active
NRestarts=1
admin@dns01:~$ chronyc tracking | grep -E 'Reference|System time'
```

`systemctl kill` envoie le signal au processus sans passer par l'arrêt normal : systemd voit une mort anormale et applique `Restart=on-failure`. (Un `systemctl stop` ne déclencherait **pas** le redémarrage : c'est un arrêt demandé.)

**Explications**

Un module est un programme autonome qui lit ses arguments en JSON et répond en JSON ; `AnsibleModule` en fait un contrat : validation de l'`argument_spec` (types, valeurs par défaut, `required_if`), modes vérification et différence, `no_log`, sortie unique. AnsiballZ est la façon de livrer ce programme et tout ce qu'il importe à une machine qui n'a pas Ansible. Comprendre ce chemin explique beaucoup de pannes : interpréteur absent ou différent (`interpreter_python`), dossier temporaire inaccessible (`UNREACHABLE` « Failed to create temporary directory »), `become_user` non privilégié, sortie parasite, module qui ne gère pas `--check`.

**Alternatives**
- `ansible.builtin.template` (fichier `.conf` dans `templates/`) + handler `ansible.builtin.systemd_service: daemon_reload: true` : la solution standard, suffisante pour un ou deux fichiers.
- `community.general.ini_file` sur le fichier de surcharge : idempotent, mais ne gère pas bien les clés répétées (`ExecStart=` puis `ExecStart=…`).
- Un *action plugin* si le module devait lire des fichiers du contrôleur (modèle d'unité, par exemple).

**Pièges classiques**
- `print()` dans le module (sortie corrompue).
- Oublier `supports_check_mode=True` : la tâche est `skipped` en `--check`, la CI ne voit plus rien.
- Passer le dictionnaire du `diff` de contenu à `set_fs_attributes_if_different` (il y écrit des clés `before`/`after` de type dictionnaire : `TypeError` sur une chaîne).
- Tester avec le vrai `systemctl` : tests non reproductibles, et dangereux s'ils tournent en root.
- Laisser les dossiers `~/.ansible/tmp/ansible-tmp-*` gardés par `ANSIBLE_KEEP_REMOTE_FILES` : ils contiennent les arguments des tâches, donc potentiellement des secrets.

**En production chez MédiSphère**
La collection `medisphere.socle` a sa CI (`ansible-test sanity` et `units`, `ansible-lint`), son numéro de version et son journal des modifications ; un module maison n'entre que s'il remplace au moins deux usages et qu'il a des tests ; la politique « `Restart=on-failure` pour les services critiques » est décrite dans `docs/socle/configuration.md` avec la liste des services concernés.

---

### M04-E45 — Questions expert : moteur d'Ansible

1. **Précédence.** Du moins au plus prioritaire : `roles/base/defaults/main.yml` (2) < `inventories/lab/group_vars/all/` (4) < `playbooks/group_vars/all/` (5) < `inventories/lab/group_vars/role_dns/` (6) < `inventories/lab/host_vars/dns01/` (9) < `vars:` du jeu (12) < `roles/base/vars/main.yml` (15) < `set_fact` (19) < `-e` (22). `ansible-inventory --host dns01` ne voit que les sources **d'inventaire** : `group_vars/all`, `group_vars/role_dns`, `host_vars/dns01` de l'inventaire. Ni les `defaults`/`vars` des rôles, ni les `group_vars` du playbook, ni les `vars` de jeu, ni `set_fact`, ni `-e`. (Numéros : liste *Understanding variable precedence* de la documentation.)

2. **Réponse b.** Les variables sont évaluées **paresseusement** : une variable dont la valeur est un modèle est réévaluée à chaque utilisation ; le `lookup('pipe', 'date +%s')` est relancé. a) faux : rien n'est figé au chargement ; c) faux : les lookups n'ont pas de cache ; d) faux : ils sont autorisés. Pour figer : `ansible.builtin.set_fact: horodatage_fige: "{{ lookup(…) }}"` (évalué une fois, le résultat est stocké), ou une variable de type « non modèle » passée en `-e`.

3. **Data tagging et confiance (2.19+).** Les chaînes portent des métadonnées (origine, confiance). Seules les chaînes **fiables** (venant du playbook, des rôles, de l'inventaire et des fichiers de variables) sont rendues comme modèles ; les données venant des modules, des faits, des lookups, des fichiers lus à l'exécution sont **non fiables** : un `{{ … }}` qu'elles contiennent reste du texte (protection contre l'injection de modèles). `when: "{{ resultat.stdout }} == 'ok'"` construit un modèle à partir d'une donnée non fiable et le fait réévaluer : c'est refusé (et `{{ }}` dans `when` était déjà déconseillé). On écrit `when: resultat.stdout == 'ok'`. Les conditions doivent produire un **booléen** : une liste non vide n'est plus convertie implicitement, d'où `when: ma_liste | length > 0`.

4. **Stratégies.** `linear` : chaque tâche est lancée sur tous les hôtes (par paquets de `forks`), on attend que tous aient fini avant la suivante. `free` : chaque hôte avance à son rythme. `host_pinned` : comme `free`, mais un worker reste attaché à un hôte jusqu'à la fin (utile quand `forks` < nombre d'hôtes). Estimation (40 tâches, 4 hôtes à 0,5 s, 1 à 6 s, `forks = 5`) : `linear` ≈ 40 × 6 s = 240 s ; `free` : les rapides finissent en ~20 s, le lent en ~240 s, fin du jeu ≈ 240 s ; `host_pinned` : idem ici (5 hôtes, 5 forks). Les stratégies déplacent l'attente ; seule la correction de l'hôte lent fait passer le jeu à ~20 s.

5. **Parallélisme.** `forks` : nombre maximal de processus de travail en parallèle (global). `serial` : taille des lots d'hôtes qui jouent **tout** le jeu avant le lot suivant (mises à jour progressives). `throttle` : limite le parallélisme d'**une** tâche ou d'un bloc (ex. 1 appel d'API à la fois). `run_once` : la tâche ne tourne que sur le premier hôte du lot, son résultat est partagé. Avec `serial: 2`, `run_once` s'exécute **une fois par lot**, pas une fois par jeu (la documentation le précise) : à combiner avec une condition sur `ansible_play_hosts_all[0]` si on veut vraiment une seule fois.

6. **Réponse c.** Un hôte en échec est retiré du jeu, et par défaut ses handlers notifiés ne s'exécutent pas. a) est le cas sans échec (un handler notifié plusieurs fois ne tourne qu'une fois, à la fin de la section : `pre_tasks`, `roles`/`tasks`, `post_tasks`) ; b) faux : jamais deux fois ; d) faux : sauf `meta: flush_handlers`. Réglages : `force_handlers` (option de jeu, `--force-handlers`, `force_handlers` dans la configuration) fait jouer les handlers malgré l'échec ; `meta: flush_handlers` les exécute à un point choisi. Risque pour `ssh_durci` : le fichier de configuration a changé mais `sshd` n'est pas rechargé → la configuration en mémoire diffère du disque, et le prochain redémarrage (peut-être une mise à jour de paquet, la nuit) applique un changement que personne ne surveille. C'est aussi ce qui protège `ssh_durci` (M04-E11) : ses deux handlers écoutent `Recharger sshd`, la validation complète d'abord ; si elle échoue, l'hôte est en échec et le rechargement n'a pas lieu. Voulu, à condition de le savoir : le fichier posé reste sur le disque, à corriger avant le prochain redémarrage (M04-E40).

7. **`import_*` / `include_*`.** `import_tasks` est **statique** : le fichier est lu à l'analyse du playbook, ses tâches apparaissent dans `--list-tasks`, `when` et `tags` posés sur l'import sont recopiés sur chaque tâche importée, pas de boucle possible, le nom de fichier ne peut pas dépendre d'un fait. `include_tasks` est **dynamique** : évalué à l'exécution, `when` s'applique à l'inclusion elle-même (une fois), les `tags` aussi (pour les propager aux tâches incluses : `apply: { tags: … }`), boucles possibles, tâches invisibles dans `--list-tasks`. Pour un fichier choisi d'après `ansible_facts['os_family']` : `include_tasks` (le fait n'existe pas à l'analyse).

8. **`delegate_to`.** La tâche s'exécute **sur** `localhost` mais **pour** l'hôte d'inventaire : elle voit les variables de l'hôte d'inventaire (`inventory_hostname`, ses `group_vars`…), la connexion utilise les paramètres de l'hôte délégué (`ansible_connection`, `ansible_host` de `localhost`). Les faits collectés par une tâche déléguée sont attribués à l'hôte d'inventaire, sauf `delegate_facts: true`, qui les range sous l'hôte délégué (`hostvars['localhost']`). Piège : une variable `ansible_host` définie dans les `vars` de la tâche s'appliquerait à la délégation.

9. **`--check`.** Un module sans prise en charge est `skipped` (il le décide lui-même au démarrage). `ansible.builtin.command` n'exécute rien en mode vérification : il renvoie `skipped` (« Command would have run if not in check mode »), sauf si `creates`/`removes` permettent de conclure. Un `--check` échoue là où le vrai passage réussirait quand une tâche dépend de l'effet d'une précédente non appliquée (paquet « installé » en vérification, puis service introuvable ; résultat `register` vide utilisé ensuite). Écriture propre : `check_mode: false` sur les commandes de **lecture** (avec `changed_when: false`), `when: not ansible_check_mode` sur ce qui ne peut être simulé, et des tâches qui tolèrent l'absence d'effet en vérification.

10. **Pipelining.** Au lieu de créer un dossier temporaire, d'y copier le module, de le rendre exécutable, de l'exécuter puis de le supprimer (4 à 5 commandes SSH), Ansible envoie le wrapper sur l'entrée standard de `python3` dans **une** commande. Pas activé par défaut à cause de `requiretty` : si `sudoers` exige un terminal, `sudo` refuse de tourner sans TTY, or le pipelining n'en alloue pas (le texte du module passe sur l'entrée standard). Debian n'active pas `requiretty` ; certaines distributions RHEL anciennes le faisaient.

11. **`sudo`.** Forme (plugin `ansible.builtin.sudo`, drapeaux par défaut `-H -S -n`) : `sudo -H -S -n -u root /bin/sh -c 'echo BECOME-SUCCESS-<aléa> ; /usr/bin/python3'`. `-n` : ne jamais demander de mot de passe (échouer plutôt que bloquer) — retiré quand un mot de passe d'élévation est fourni ; `-S` : lire un éventuel mot de passe sur l'entrée standard ; `-H` : `HOME` de l'utilisateur cible. La chaîne `BECOME-SUCCESS-…` permet à Ansible de savoir que l'élévation a réussi et de séparer l'invite de la sortie du module. `become_user: postgres` sans pipelining : le module est déposé dans le dossier temporaire de l'utilisateur de **connexion** (`admin`), illisible par `postgres` ; Ansible essaie alors les ACL (`setfacl`), puis d'autres méthodes, puis échoue (« Failed to set permissions on the temporary files Ansible needs to create when becoming an unprivileged user »). Solutions : pipelining (rien n'est déposé), paquet `acl` installé sur la cible, en dernier recours l'option `world_readable_temp` du plugin shell (déconseillée).

12. **Multiplexage.** `ControlMaster=auto` : la première connexion devient maîtresse et ouvre un socket ; `ControlPersist=60s` : elle survit 60 s après la dernière session ; `ControlPath` : chemin du socket. Ansible met ses sockets dans `~/.ansible/cp` avec un nom **haché** (10 caractères) pour rester sous la limite de longueur des sockets Unix (~108 octets) — d'où l'erreur « path … too long for Unix domain socket » avec un `control_path` personnalisé trop long. Panne classique : un socket orphelin (processus maître tué, machine redémarrée, autre utilisateur) → « ControlSocket … already exists, disabling multiplexing » ou connexion qui pend ; remède : `ssh -O exit -o ControlPath=<socket> x` ou supprimer le socket, pas désactiver le multiplexage (E41 v2).

13. **Format Vault.** En-tête `$ANSIBLE_VAULT;1.1;AES256` (ou `1.2;AES256;<étiquette>`), puis un corps hexadécimal qui code lui-même trois champs hexadécimaux : sel, HMAC, texte chiffré. Clés dérivées par PBKDF2-HMAC-SHA256 (10 000 itérations, sel aléatoire) : une clé AES-256, une clé HMAC, un IV ; chiffrement AES-256 en mode CTR ; intégrité par HMAC-SHA256 du texte chiffré, vérifié **avant** de déchiffrer. Sur un fichier abîmé, le message dépend de ce qui casse : une structure illisible (nombre impair de chiffres hexadécimaux, champs manquants) donne `Vault format unhexlify error` ou `Vault vaulttext format error` avant tout essai de mot de passe ; une structure intacte mais un contenu modifié donne un HMAC faux pour **tous** les secrets, donc `Decryption failed`. Vault protège les fichiers **au repos** (dépôt, sauvegardes) ; il ne protège pas les valeurs en mémoire, dans les sorties de tâches (`-v`, `debug`, `register`), dans les fichiers temporaires gardés (`KEEP_REMOTE_FILES`), ni sur les cibles une fois déposées : d'où `no_log: true` sur les tâches qui manipulent des secrets.

14. **Inventaire qui échoue.** Par défaut, chaque source est essayée par les plugins activés ; une source qu'aucun ne sait analyser donne un **avertissement** (`Unable to parse … as an inventory source`) et l'exécution continue avec les autres (code retour 0, même s'il ne reste que `localhost`). `[inventory] unparsed_is_failed = True` : échec si **aucune** source n'est analysable ; `[inventory] any_unparsed_is_failed = True` : échec si **une** source ne l'est pas ; `strict: true` (plugins *constructed*) : une erreur de modèle dans `compose`/`groups`/`keyed_groups` devient fatale. Pour la dérive : `any_unparsed_is_failed` **et** une assertion de nombre d'hôtes (une réponse vide valide n'est pas une erreur d'analyse, cf. E39 v1).

15. **`keyed_groups`.** Le nom du groupe est `préfixe + séparateur + valeur` (séparateur `_` par défaut, supprimé si le préfixe est vide et `leading_separator: false`), puis assaini : pour les plugins d'inventaire, tout caractère qui n'est pas lettre, chiffre ou `_` est **remplacé par `_`, silencieusement** (contrairement aux noms de groupes écrits dans un inventaire statique, qui ne sont que signalés selon `TRANSFORM_INVALID_GROUP_CHARS`). `role-dns` devient `role_dns`. Un nom de groupe doit pouvoir servir de nom de variable Jinja2 (`groups.role_dns`). Piège : deux étiquettes différentes (`role-dns` et `role.dns`, ou `role_dns`) produisent le **même** groupe ; et le nom de groupe ne dit plus quelle étiquette l'a produit.

16. **`hash_behaviour = merge`.** Par défaut (`replace`), un dictionnaire défini à un niveau plus prioritaire **remplace** entièrement celui d'un niveau inférieur ; `merge` les fusionne récursivement. Déconseillé : comportement global, implicite, qui rend un rôle dépendant de la configuration de celui qui l'exécute, et qui fusionne aussi ce qu'on voulait remplacer. À la place : des variables à plat (`base_ntp_serveurs`, `base_fuseau_horaire`) plutôt qu'un gros dictionnaire, ou une fusion **explicite** et locale avec le filtre `combine` (`{{ base_defaut | combine(base_surcharge, recursive=true) }}`).

17. **Idempotence de `command`.** Le module ne sait pas ce que fait la commande : il rapporte `changed` à chaque exécution. Pour le rendre idempotent : `creates:`/`removes:` (la commande ne tourne pas si le fichier existe / n'existe pas) ; une tâche de lecture qui teste l'état, puis la commande en `when` ; `changed_when:` fondé sur la sortie (`changed_when: "'Created' in r.stdout"`) ; ou mieux, un module dédié. `changed_when: false` partout est une faute : le récapitulatif ment (`changed=0` alors que l'état a changé), les handlers ne sont pas notifiés, et la détection de dérive par `--check` devient aveugle.

18. **Faits.** La collecte (`setup`) lance de nombreuses commandes par hôte (matériel, montages, réseau) : plusieurs secondes par hôte. On la limite (`gather_facts: false` quand inutile, `gather_subset: ['!all', 'min', 'network']` au niveau du jeu ou `module_defaults` du module `setup`) et on la met en cache (`fact_caching = jsonfile`, `fact_caching_connection`, `fact_caching_timeout`, `gathering = smart` : ne collecte que si le cache n'a rien). Nouveau mode de panne : des faits **périmés** (adresse, version de paquet, nombre de CPU d'avant un changement) utilisés comme s'ils étaient frais. `ansible_facts['distribution']` plutôt que `ansible_distribution` : l'injection des faits comme variables de premier niveau (`INJECT_FACTS_AS_VARS`) est dépréciée depuis 2.20 (passage à `False` annoncé pour 2.24), et le dictionnaire `ansible_facts` évite les collisions avec des variables d'inventaire.

19. **Gestion des échecs.**
    - `ignore_errors` — légitime : une commande de nettoyage best effort ; abus : masquer une tâche qui échoue au lieu de comprendre (le récapitulatif compte `ignored`, personne ne le lit).
    - `failed_when` — légitime : `failed_when: r.rc not in [0, 3]` pour un script aux codes documentés (M02) ; abus : `failed_when: false`.
    - `ignore_unreachable` — légitime : un inventaire de collecte où un hôte éteint est normal ; abus : sur `site.yml`, il cache un hôte non configuré.
    - `any_errors_fatal` — légitime : rôle `pare_feu` sur un cluster de routeurs (un échec arrête tout avant d'en couper un second) ; abus : sur une collecte d'informations.
    - `max_fail_percentage` — légitime : avec `serial`, mise à jour progressive qui s'arrête si plus de 20 % d'un lot échoue ; abus : un pourcentage tel que la moitié du socle peut échouer sans arrêt.

20. **Push ou pull.** *Sécurité* : en push, le contrôleur (adm01, `runner01`, Semaphore) détient les clés SSH vers tout le socle et le mot de passe du coffre : c'est une cible de grande valeur, à durcir et à surveiller ; en pull, chaque hôte détient de quoi lire **sa** configuration (et ses secrets, si le dépôt n'est pas filtré : `ansible-pull` clone tout le dépôt sur chaque hôte, coffre compris). *Dérive* : en pull, la configuration est réappliquée périodiquement par l'hôte lui-même (dérive corrigée, mais aussi un changement poussé par erreur appliqué partout sans revue de l'exécution) ; en push, la dérive est **détectée** (`--check` planifié) puis corrigée par un passage décidé. *Résilience* : en push, un contrôleur en panne empêche d'agir (d'où plusieurs chemins : CI et Semaphore, et `adm01` en secours) ; en pull, un dépôt ou un serveur maître en panne fige les hôtes dans leur dernier état connu. Pour MédiSphère (socle d'une dizaine de VMs, exigence de traçabilité HDS, équipe réduite), le push piloté par un pipeline protégé avec détection de dérive est cohérent ; le pull (OpenVox, Salt) se justifierait pour un parc nombreux et éphémère, ou des sites intermittents.

**Pour te corriger** : pour chaque réponse fausse ou incomplète, note la page de documentation correspondante et refais l'expérience sur le lab (les questions 2, 6, 7, 9, 13, 14 et 15 se démontrent en quelques minutes avec un playbook sur `localhost`).
