# RB-010 — Restaurer GitLab depuis la sauvegarde applicative (PAR2)

| | |
|---|---|
| Service | Forge GitLab `git01` (VMID 1004, 10.10.20.12) |
| Rédigé | M01-E28 (PLAT-255) — testé le AAAA-MM-JJ, voir `../tests/restauration.md` |
| Durée attendue | 45 à 75 min (RTO mesuré au dernier test : __ min) |
| Perte de données maximale | depuis la dernière sauvegarde de 01:15 (RPO ≤ 24 h) |

## Quand utiliser ce runbook

- `git01` est perdue (disque, VM détruite, corruption) **et** la sauvegarde de VM de la nuit (`lab-nuit`, `pbs-par2`) est inutilisable ou trop ancienne : restaurer d'abord la VM entière (RB-002) est plus simple quand c'est possible.
- Migration de GitLab vers une nouvelle VM ou une nouvelle version de Debian.
- Test de restauration périodique (sur une VM jetable, VMID 2010 `git-restore`).

Ce runbook **ne sert pas** à revenir en arrière après une mise à jour ratée de GitLab sans réinstaller la version d'origine : une sauvegarde ne se restaure que sur **la même version exacte** de GitLab (CE/EE compris).

## Ce qu'il faut avoir sous la main

- La **clé de chiffrement** `pbs-git01.key` (copie hors ligne, ou reconstruite depuis la *paperkey* : `proxmox-backup-client key import`/`show`, voir M00-E36). Sans elle, la sauvegarde est illisible.
- Le secret du jeton `wb-backup@pbs!git01` et l'empreinte du certificat de `pbs01` (gestionnaire de mots de passe de l'équipe).
- `proxmox-backup-client` sur `adm01` (dépôt `pbs-client`, suite `trixie`).
- Un hôte cible Debian 13 avec 4 vCPU, 8 Go de RAM, 60 Go de disque.

## Étapes

### 1. Choisir la sauvegarde (adm01)

```
admin@adm01:~$ set -a; source ~/.config/workbook/pbs-git01.env; set +a     # 600, retiré à la fin
admin@adm01:~$ proxmox-backup-client snapshot list --ns par1/git01
admin@adm01:~$ proxmox-backup-client catalog dump --ns par1/git01 host/git01/<HORODATAGE> --keyfile <CLÉ>
```

Note le nom de l'archive `<ID>_gitlab_backup.tar` : la version de GitLab figure à la fin de l'`<ID>` (forme `<horodatage>_<AAAA_MM_JJ>_<version>`, par exemple `…_2026_10_03_19.3.2` suivi selon l'édition d'un suffixe `-ce`) et dans le fichier `backup_information.yml` de l'archive (`tar -xOf <archive> backup_information.yml`). C'est **la version à installer**.

### 2. Rapatrier les fichiers (adm01)

```
admin@adm01:~$ df -h /var/tmp                    # place pour l'archive (quelques Go)
admin@adm01:~$ proxmox-backup-client restore --ns par1/git01 host/git01/<HORODATAGE> gitlab.pxar /var/tmp/restau-git01 --keyfile <CLÉ>
admin@adm01:~$ cd /var/tmp/restau-git01 && sha256sum -c SHA256SUMS
```

### 3. Préparer l'hôte cible

- **Reconstruction de `git01`** : recréer la VM 1004 (RB-001, mêmes paramètres qu'en M01-E04 : `vinfra`, 10.10.20.12).
- **Test** : VM 2010 `git-restore` sur `vsandbox` (DHCP), étiquette `env-m01`, pool `lab`. ⚠️ 8 Go de RAM : vérifier la mémoire libre de `pve01` avant (`free -g`), et détruire la VM à la fin.

Copier les fichiers : `scp -r /var/tmp/restau-git01 <HÔTE>:/tmp/`.

### 4. Remettre la configuration AVANT d'installer GitLab (hôte cible)

```
admin@<HÔTE>:~$ sudo tar -xf /tmp/restau-git01/gitlab_config_*.tar -C /        # /etc/gitlab complet
admin@<HÔTE>:~$ sudo tar -xf /tmp/restau-git01/hors-gitlab.tar -C /            # hooks Gitaly, clés d'hôte SSH
admin@<HÔTE>:~$ sudo systemctl restart ssh
admin@<HÔTE>:~$ sudo ls -l /etc/gitlab/gitlab-secrets.json /etc/gitlab/ssl/
```

Le paquet lira `gitlab.rb` (même `external_url`, même profil mémoire, mêmes hooks) et **`gitlab-secrets.json`** lors de son premier `reconfigure` : sans ce fichier, les variables CI, les jetons de runner et les secrets 2FA restaurés seraient indéchiffrables.

### 5. Installer exactement la même version de GitLab CE

```
admin@<HÔTE>:~$ curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh -o /tmp/gitlab-ce.sh   # relire, puis :
admin@<HÔTE>:~$ sudo bash /tmp/gitlab-ce.sh
admin@<HÔTE>:~$ sudo apt-get install gitlab-ce=<VERSION>-ce.0 && sudo apt-mark hold gitlab-ce
admin@<HÔTE>:~$ sudo gitlab-ctl status
```

### 6. Restaurer les données

```
admin@<HÔTE>:~$ sudo cp /tmp/restau-git01/*_gitlab_backup.tar /var/opt/gitlab/backups/
admin@<HÔTE>:~$ sudo chown git:git /var/opt/gitlab/backups/*_gitlab_backup.tar
admin@<HÔTE>:~$ sudo gitlab-ctl stop puma && sudo gitlab-ctl stop sidekiq && sudo gitlab-ctl status
admin@<HÔTE>:~$ sudo GITLAB_ASSUME_YES=1 gitlab-backup restore BACKUP=<ID>      # sans « _gitlab_backup.tar »
admin@<HÔTE>:~$ sudo gitlab-ctl reconfigure && sudo gitlab-ctl restart
```

⚠️ `gitlab-backup restore` **efface** la base de l'instance cible : jamais sur la `git01` en service.

### 7. Vérifier

```
admin@<HÔTE>:~$ sudo gitlab-rake gitlab:check SANITIZE=true
admin@<HÔTE>:~$ sudo gitlab-rake gitlab:doctor:secrets          # 0 erreur de déchiffrement attendue
admin@<HÔTE>:~$ sudo gitlab-rake gitlab:artifacts:check gitlab:uploads:check
admin@<HÔTE>:~$ curl -s localhost/-/readiness?all=1
```

Depuis `adm01`, sans toucher au DNS (le nom reste `git01.par1.medisphere.internal`) :

```
admin@adm01:~$ IP=<IP-HÔTE>
admin@adm01:~$ curl -s --resolve git01.par1.medisphere.internal:443:$IP -H "PRIVATE-TOKEN: $(cat ~/.config/workbook/gitlab-checks.token)" \
                 "https://git01.par1.medisphere.internal/api/v4/projects?per_page=100" | jq length
admin@adm01:~$ GIT_SSH_COMMAND="ssh -o HostKeyAlias=git01.par1.medisphere.internal" git ls-remote git@$IP:plateforme/medisphere.git | head -3
```

Attendus : mêmes projets qu'en production, connexion web et jetons fonctionnels, variables CI lisibles (doctor:secrets), historique des pipelines et des MR présent. Si SSH refuse les clés : `sudo gitlab-rake gitlab:shell:setup` (régénère `authorized_keys`, à vérifier selon le mode de recherche des clés choisi en M01-E04).

### 8. Remise en service ou remise en état

- **Reconstruction réelle** : vérifier `runner01` (le runner reprend seul : son jeton est dans la base restaurée), lancer `lab/bin/check 01 47`, réactiver le timer `wb-backup-gitlab.timer` et lancer une sauvegarde immédiate.
- **Test** : `qm stop 2010 && qm destroy 2010 --purge` sur `pve01` ; supprimer `/var/tmp/restau-git01` et la copie de la clé sur `adm01` (`shred -u`), effacer les variables PBS de la session.

## Pièges connus

- Version différente d'un seul correctif : la restauration refuse ou corrompt. Lire la version dans le nom de l'archive.
- `gitlab-secrets.json` restauré **après** le premier `reconfigure` : secrets régénérés, données chiffrées perdues. D'où l'étape 4 avant l'étape 5.
- Restauration faite sur une VM branchée sur `vinfra` avec l'IP de `git01` alors que `git01` tourne : conflit d'adresse, runners et utilisateurs servis au hasard.
- Clés d'hôte SSH non restaurées : tous les postes refusent la forge (« REMOTE HOST IDENTIFICATION HAS CHANGED »).

## Historique

| Date | Auteur | Changement |
|---|---|---|
| AAAA-MM-JJ | <apprenant> | Création (M01-E28), test sur VM 2010 |
