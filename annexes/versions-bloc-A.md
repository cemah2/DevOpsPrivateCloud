# Versions du bloc A et changements de comportement

> Relevé fait le 3 octobre 2026 au démarrage du bloc A (modules 01 à 06), à partir des registres officiels (PyPI, npm, Galaxy, registres Terraform/OpenTofu, proxy Go, dépôts APT, pages de releases). Les versions de référence sont dans [`PLAN.md`](../PLAN.md) §6. Ce fichier liste ce qui a changé récemment et qui touche les exercices : si tu suis une documentation ou un tutoriel plus ancien, c'est ici que tu trouveras pourquoi il ne marche plus.

## Git et forge (module 01)

| Outil | Ce qui change pour toi |
|---|---|
| Git 2.47 (Debian 13) | La branche par défaut reste `master` tant que Git 3.0 n'est pas sorti : le workbook fixe `init.defaultBranch=main`. Les changements annoncés pour Git 3.0 (SHA-256 et reftable par défaut, `safe.bareRepository=explicit`) ne sont pas actifs. |
| GitLab CE 19.x | Paquet officiel pour Debian 13 depuis la 18.5. PostgreSQL 17 minimum (embarqué par omnibus). Mattermost retiré de l'omnibus. 8 Go de RAM au strict minimum (profil « mémoire contrainte » de la doc), 16 Go recommandés. Les jetons d'accès personnels ont une **date d'expiration obligatoire** (365 jours max. par défaut). |
| GitLab 19.2+ (NGINX) | Les réglages NGINX propres à l'application (certificat, redirection HTTP, en-têtes) passent sous `gitlab_rails['nginx'][…]` ; les clés `nginx[…]` restent pour le démon (workers, gzip). Les anciennes clés fonctionnent encore avec un avertissement de dépréciation : beaucoup de tutoriels les utilisent. |
| GitLab Runner 19.x | Enregistrement par **jeton d'authentification `glrt-`** créé dans l'interface (`gitlab-runner register --token …`) ; l'ancien `--registration-token` est déprécié (suppression prévue en 20.0). Installer aussi `gitlab-runner-helper-images`. |
| Fonctions Premium | Approbations obligatoires, règles de push (*push rules*), propriétaires de code obligatoires : **pas dans CE**. Les exercices s'en passent (hooks côté serveur, CI obligatoire, protections de branches). |
| pre-commit 4.x | Noms de stages `pre-commit`, `pre-push`, `commit-msg` (les anciens `commit`, `push` sont dépréciés). |
| Gitleaks 8.30 | Commandes `gitleaks git`, `gitleaks dir`, `gitleaks stdin` (`detect`/`protect` sont masquées). Le paquet Debian (8.16) est trop ancien : binaire de release ou hook pre-commit. Le projet se déclare « complet » ; son auteur développe un successeur (Betterleaks). |
| semantic-release 25, commitlint 21 | Modules ESM, **Node.js ≥ 22.14 / 24** : le Node 20 de Debian 13 est refusé. Le workbook installe Node 24 LTS. |

## Scripting (module 02)

| Outil | Ce qui change pour toi |
|---|---|
| ShellCheck 0.11 | SC2002 (« cat inutile ») n'est plus signalé par défaut ; nouvelles règles SC2327-SC2332 (dont SC2329, fonction jamais appelée). Debian 13 livre la 0.10 (0.11 dans trixie-backports). |
| jq 1.8 | Nouvelles fonctions (`trim`, `ltrimstr`, `abs`, `toboolean`) ; `tonumber` refuse les espaces ; `--indent 0` n'implique plus `-c`. Debian 13 livre la 1.7.1 : les corrigés restent compatibles 1.7. |
| yq | Le paquet Debian `yq` est le yq **Python** (kislyuk), syntaxe différente. Le workbook utilise le yq **Go** de mikefarah (binaire de release). |
| uv 0.12 | `uv init` crée un projet empaqueté (`src/`) par défaut ; `--no-package` pour l'ancien comportement. |
| Typer 0.26+ | Click est intégré à Typer et n'est plus une dépendance ; Rich est obligatoire. |
| Click 8.2+ | `CliRunner(mix_stderr=…)` supprimé : stderr est toujours séparé dans les tests. |
| pytest 9 | Configuration native `[tool.pytest]` ; le workbook garde `[tool.pytest.ini_options]`, lu aussi par pytest 8 de Debian. |
| ruff 0.16 | Le jeu de règles par défaut s'est fortement élargi : les projets fixent `select` explicitement. |
| Task 3.x | `version: '3'` toujours requis ; pas de paquet Debian utilisable (binaire de release). |

## Images (module 03)

| Outil | Ce qui change pour toi |
|---|---|
| Packer 1.16 | Licence **BUSL 1.1** depuis la 1.10 (usage interne autorisé ; pas de fork majeur équivalent à OpenTofu). Dépôt APT HashiCorp disponible pour trixie. |
| Plugin `hashicorp/proxmox` 1.2.x | Options de premier niveau `iso_file`, `iso_url`, `iso_storage_pool`, `unmount_iso` **dépréciées** au profit du bloc `boot_iso {}`. Défauts à connaître : `cpu_type = "kvm64"`, `scsi_controller = "lsi"`, `memory = 512`, `cloud_init = false`. Avec un jeton : `username = "user@pve!jeton"`. |
| Rocky Linux 10 | Exige un CPU **x86-64-v3** : avec `kvm64` ou `x86-64-v2-AES` (défaut de Proxmox), le noyau panique au démarrage. Utiliser `host` ou `x86-64-v3`. |
| cloud-init 25.1 | Validation par `cloud-init schema --system` ou `-c fichier`. Image Debian `nocloud` = **sans** cloud-init : utiliser `genericcloud`. |

## Ansible (module 04)

| Outil | Ce qui change pour toi |
|---|---|
| ansible-core 2.19+ | *Data tagging* : les conditions doivent produire un **booléen** (`when: ma_liste` sur une liste est une erreur), plus de `{{ }}` dans `when`, *undefined* plus strict, `omit` ne fuit plus. Debian 13 livre la 2.19, le workbook la 2.21 dans l'environnement `uv` du projet : les corrigés passent sur les deux. |
| ansible-core 2.20+ | `INJECT_FACTS_AS_VARS` déprécié (passera à `False` en 2.24) : écrire `ansible_facts['distribution']`, pas `ansible_distribution`. |
| `community.proxmox` 2.x | Les modules Proxmox ont quitté `community.general` (redirections supprimées en 15.0). `validate_certs` vaut maintenant **`true`** par défaut. Demande `proxmoxer >= 2.3`. |
| Molecule 26 | Approche « ansible-native » : pilote `default`, création et destruction des instances par tes propres playbooks. Les pilotes de `molecule-plugins` sont optionnels. |
| AWX | Aucune release depuis la 24.6.1 (juillet 2024), développement en pause pour refonte. Alternative légère pratiquée : **Semaphore UI**. |
| Puppet / Salt | Puppet distribué sous licence propriétaire « Puppet Core » depuis 2025 ; fork communautaire **OpenVox** (paquets Debian 13). Salt (Broadcom) toujours actif, LTS 3008. |

## Infrastructure as Code (module 05)

| Outil | Ce qui change pour toi |
|---|---|
| OpenTofu 1.10+ | Verrou d'état S3 natif `use_lockfile = true` (écriture conditionnelle `If-None-Match`), plus besoin de DynamoDB. Chiffrement de l'état côté client (PBKDF2, etc.). 1.11 : valeurs éphémères et attributs *write-only*. |
| Terraform | Licence BUSL ; cité pour comparaison, le workbook utilise OpenTofu. |
| `bpg/proxmox` 0.115 | Encore en 0.x avec des ruptures entre versions mineures : **épingler**. Renommage progressif vers des noms courts `proxmox_*` (ex. `proxmox_download_file`) ; **`proxmox_vm` est une ressource expérimentale à ne pas utiliser** : la VM reste `proxmox_virtual_environment_vm`. |
| Terragrunt 1.x | `run-all` remplacé par `run --all` ; plus de préfixe `--terragrunt-` sur les options ; variables `TG_*`. |
| Trivy | Compromission de la chaîne d'approvisionnement en mars 2026 (v0.69.4 malveillante, tags de `trivy-action` réécrits) : **épingler par empreinte** (digest/SHA). |
| MinIO | Édition communautaire abandonnée (plus de binaires ni d'images depuis octobre 2025, console retirée, dépôt archivé en février 2026). Le socle utilise **SeaweedFS**. Garage ne gère pas les écritures conditionnelles (verrou OpenTofu inopérant). |
| Infracost | N'estime que les clouds publics : cité, non pratiqué. |

## Services socle (module 06)

| Outil | Ce qui change pour toi |
|---|---|
| NetBox 4.5+ | Jetons **v2** (`Authorization: Bearer nbt_<clé>.<jeton>`, nécessite `API_TOKEN_PEPPERS`) ; le jeton en clair n'est plus récupérable après création ; jetons v1 dépréciés (retrait en 5.0). NetBox 4.7 exige PostgreSQL ≥ 15 et change plusieurs champs d'API : le workbook fige la 4.6. |
| PowerDNS Recursor 5.2+ | L'ancien format de configuration est désactivé par défaut : **YAML** (`recursor.yml`). 5.4 : `any_to_tcp` vrai par défaut. |
| PowerDNS Authoritative 5.0 | Vues (backend LMDB) ; API normalisée. Debian 13 livre la 4.9 : le workbook utilise le dépôt officiel. |
| Provider OpenTofu PowerDNS | `pan-net/powerdns` abandonné : utiliser le fork **`mmianl/powerdns`**. |
| Kea 3.0 | La plupart des *hooks* deviennent libres ; `subnet-id` obligatoire ; sockets de contrôle HTTP directement dans les démons ; chemins de fichiers restreints. 3.2 supprime le Control Agent. Debian 13 livre la 2.6 (fin de vie) : dépôt ISC `kea-3-0`. |
| ISC DHCP | Fin de vie depuis 2022 : cité pour l'historique seulement. |
| step-ca 0.30 | Debian 13 livre la 0.20 (obsolète) : dépôt Smallstep. |
