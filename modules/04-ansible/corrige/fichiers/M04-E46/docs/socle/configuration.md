# Configuration du socle (Ansible)

> Dépôt : `plateforme/ansible` · Propriétaire : équipe Plateforme · Décision : ADR-0040 · Procédure : RB-040
> Modèle de référence du workbook (M04-E46) : remplace les `<…>` et les noms qui diffèrent dans ton projet.

## 1. Ce qui est en code, ce qui ne l'est pas

| Hôte | Groupe | Rôles appliqués | Hors Ansible (et pourquoi) |
|---|---|---|---|
| `gw01` | `role_routeur` | `base`, `ssh_durci`, `pare_feu` | WireGuard `wg0`/`wg1` (clés, M00-E21/E30) : à reprendre en rôle avec Vault ; relais DHCP |
| `adm01` | `role_bastion` | `base`, `ssh_durci` (connexion locale) | outils personnels de l'administrateur, clones de travail, `~/.config/workbook/` |
| `dns01` | `role_dns` | `base`, `ssh_durci`, `dnsmasq` | — (remplacé par PowerDNS/Kea au module 06) |
| `git01` | `role_gitlab` | `base`, `ssh_durci`, `gitlab_hote` | GitLab lui-même (`gitlab.rb`, `gitlab-ctl reconfigure`, montées de version : M01) ; sauvegarde applicative (M01) |
| `runner01` | `role_runner` | `base`, `ssh_durci`, `gitlab_runner` | enregistrement initial du runner (jeton `glrt-` créé dans l'interface) |
| `pve01`, `pbs01` | — | aucun | hyperviseur et sauvegarde : configuration par l'API (modules 05 et 09) |

## 2. Organisation du projet

- `inventories/lab/` : `hosts.yml` (statique, secours), `proxmox.yml` (dynamique, **par défaut** en CI et pour la dérive), `group_vars/`, `host_vars/`. Les groupes `socle` et `role_*` viennent des étiquettes Proxmox (`socle`, `role-…`).
- `roles/` : un rôle par fonction ; variables préfixées par le nom du rôle ; valeurs par défaut dans `defaults/` ; scénario Molecule dans `molecule/default/`.
- `collections/ansible_collections/medisphere/socle/` : collection interne (module `systemd_dropin`, M04-E44).
- `playbooks/site.yml` : tout le socle (garde-fou d'inventaire, rôles communs, DNS, forge, runner, routeur en dernier) ; un playbook par fonction pour les interventions ciblées.

## 3. Conventions de l'équipe (tirées des incidents du palier 4)

1. Aucune modification du socle hors chaîne : ni à la main, ni depuis une copie de travail. Exception : intervention d'urgence documentée, suivie d'une MR qui la reprend.
2. Un seul emplacement de `group_vars`/`host_vars` : l'inventaire. Pas de `vars/` modifiable dans un rôle, pas de `playbooks/roles/`, pas de section `[tags]` dans `ansible.cfg` (INC-3141, INC-3143).
3. Les options de connexion ne sont jamais posées dans `group_vars/all` (INC-3147).
4. Un rôle qui touche l'accès à une machine valide la configuration **complète** et recharge plutôt que redémarrer (INC-3146).
5. Avant toute relance : `--check --diff --limit`.
6. Un inventaire vide ou incomplet fait échouer : assertion en tête de `site.yml` et de la dérive, `any_unparsed_is_failed` (INC-3145).

## 4. Chaîne d'application

MR → `ansible-lint` + Molecule (rôles modifiés) + `--check --diff` du socle affiché dans la MR → fusion dans `main` par un Maintainer après revue (discussions résolues, pipeline réussi obligatoire) → job manuel `appliquer` sur `main` (variables protégées : mot de passe du coffre en variable de type fichier, clé SSH `ansible-ci` restreinte par `from=`) → journal du job (qui, quand, commit, récapitulatif) conservé `<durée>`.
Flux : `runner01` → `adm01`, `gw01`, `dns01`, `git01` en TCP/22 (matrice des flux) ; `runner01` → `pve01` TCP/8006 (inventaire dynamique, Molecule).

## 5. Détection de dérive

Pipeline planifié chaque nuit à `<heure>` : garde-fou d'inventaire, `site.yml --check --diff`, rapport en artefact. Échoue (et notifie `<canal>`) si `changed > 0`, si un hôte est `UNREACHABLE`, si l'inventaire est incomplet ou si la durée dépasse `<seuil>`. Une dérive est corrigée **par la chaîne** (MR si le code doit changer, sinon job `appliquer`), jamais à la main.

## 6. Secrets

| Secret | Emplacement | Portée | Rotation |
|---|---|---|---|
| mot de passe du coffre `lab` | `adm01:~admin/.config/workbook/ansible-vault.pass` (600) ; variable CI de type fichier, protégée, masquée | déchiffre `group_vars/*/vault.yml` | `<période>`, procédure ci-dessous |
| jeton `wb-ansible@pve!ansible` | `adm01:~admin/.config/workbook/pve-ansible.env` (600) ; variables CI protégées et masquées | rôle `WBAnsible` sur `/pool/lab` (lecture de l'inventaire, clonage/destruction des instances Molecule) | expiration `<date>` |
| clé SSH `ansible-ci` | variable CI de type fichier, protégée | `admin` sur le socle, `from=10.10.20.15` | `<période>` |

**Rotation du coffre** (en une fois, jamais à moitié, cf. INC-3144) : nouveau secret → `ansible-vault rekey` de **tous** les fichiers chiffrés (une MR) → mise à jour de la variable CI → test (`ansible-vault view`, job `check-socle`) → suppression de l'ancien secret → registre des secrets.

## 7. Semaphore UI

Évalué au M04-E28 sur `sem01` (VM d'environnement 2041, détruite en fin de module). Pour le recréer : `<paquet et version>`, base `<…>`, projet `plateforme/ansible` cloné par clé de déploiement en lecture, inventaire `inventories/lab/proxmox.yml`, environnement `<…>`, clé SSH dédiée `semaphore` (portée identique à `ansible-ci`), modèles `check-socle` et `appliquer`. Décision d'usage : ADR-0040.

## 8. Ce qu'il reste à faire

- WireGuard de `gw01` en rôle (clés en Vault).
- Comptes nominatifs sur `adm01` (M06, certificats SSH) : fin de la copie de travail partagée.
- Inventaire depuis NetBox (M06), DNS/DHCP par PowerDNS/Kea (M06) : retrait du rôle `dnsmasq`.
