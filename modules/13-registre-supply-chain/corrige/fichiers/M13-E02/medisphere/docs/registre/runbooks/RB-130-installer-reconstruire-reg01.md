# RB-130 — Installer ou reconstruire `reg01` (Harbor)

| | |
|---|---|
| Service | Registre d'images `https://registry.par1.medisphere.internal` (Harbor 2.15) |
| Hôte | `reg01`, VMID 1013, 10.10.20.18, état OpenTofu `socle` |
| Durée | 45 min (installation) ; reconstruction + restauration : voir RB-131 (M13-E15) |
| Prérequis | `adm01` avec OpenTofu, Ansible, Cosign 3.1 ; Vault `critique` ; socle sain (`ca01`, DNS, NetBox, GitLab) |
| Créé | M13-E02 (PLAT-1402) |

## 1. Vérifier et épingler l'installateur (seulement pour une NOUVELLE version)

1. Lire les notes de version (et les avis de sécurité) de la version visée ; vérifier le chemin de mise à jour depuis la version en place (M13-E16, RB-132).
2. Télécharger l'archive et son bundle Sigstore depuis la release officielle :
   ```
   admin@adm01:~/m13/harbor$ V=2.15.3
   admin@adm01:~/m13/harbor$ curl -fLO https://github.com/goharbor/harbor/releases/download/v$V/harbor-offline-installer-v$V.tgz
   admin@adm01:~/m13/harbor$ curl -fLO https://github.com/goharbor/harbor/releases/download/v$V/harbor-offline-installer-v$V.tgz.sigstore.json
   ```
3. Vérifier la signature **avec l'identité du pipeline de publication de Harbor, pour cette étiquette** :
   ```
   admin@adm01:~/m13/harbor$ cosign verify-blob harbor-offline-installer-v$V.tgz \
       --bundle harbor-offline-installer-v$V.tgz.sigstore.json \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com \
       --certificate-identity "https://github.com/goharbor/harbor/.github/workflows/publish_release.yml@refs/tags/v$V"
   Verified OK
   admin@adm01:~/m13/harbor$ sha256sum harbor-offline-installer-v$V.tgz
   ```
4. Reporter l'empreinte dans `group_vars/role_registre/harbor.yml` (`harbor_installateur_sha256`) par une MR qui cite la sortie de l'étape 3. Le relecteur refait l'étape 3.

## 2. Créer (ou recréer) la VM

1. MR sur `plateforme/infra` (`socle/reg01.tf`) ; lire le plan : VM 1013, disque `scsi1` 200 Gio `hdd-bulk` `backup=0`, A, PTR, CNAME `registry`.
2. `apply` par le pipeline. Puis, en root sur `pve01` : `qm set 1013 --startup order=4`.
3. Contrôles : `dig +short registry.par1.medisphere.internal` → `reg01.par1.medisphere.internal.` puis `10.10.20.18`.

## 3. Configurer l'hôte

1. Pipeline de `plateforme/ansible` : `site.yml` (rôles communs du socle) puis `playbooks/registre.yml`.
2. Ordre interne : Docker → prérequis Harbor (`/data`, unité, scripts) → certificat ACME (Harbor arrêté, port 80 libre) → installation (une seule fois `install.sh --with-trivy`) → `harbor.service` → santé.
3. Second passage : `changed=0`.

## 4. Contrôles de fin

```
admin@adm01:~$ curl -sf https://registry.par1.medisphere.internal/api/v2.0/health | jq -r .status
healthy
admin@adm01:~$ ssh reg01 'findmnt -no SOURCE,FSTYPE /data; systemctl is-active harbor docker; sudo docker ps --format "{{.Names}} {{.Status}}"'
admin@adm01:~$ lab/bin/check 13 02
```

Puis, sur une reconstruction : appliquer l'état `registre` (projets, robots, caches, politiques) par le pipeline de `plateforme/infra`, restaurer les données (RB-131), revérifier les signatures d'un échantillon d'images.

## Retour arrière

- Installation ratée avant toute donnée : `systemctl stop harbor`, supprimer `/opt/harbor`, `/opt/harbor-dist/<version>` et le contenu de `/data`, relancer le playbook.
- Une fois des images poussées : **jamais** d'effacement de `/data` sans sauvegarde vérifiée (RB-131).
