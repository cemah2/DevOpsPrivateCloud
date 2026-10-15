# Registre de travail (`ctr01:5000`)

> Fiche de service — M12-E15 (PLAT-1315). Provisoire : remplacé par Harbor (`registry.par1.medisphere.internal`) au module 13 (M13-E03 migre les images).

| | |
|---|---|
| Logiciel | CNCF Distribution 3.1 (`docker.io/library/registry:3`, épinglée par empreinte), Docker Compose |
| Adresse | `https://ctr01.par1.medisphere.internal:5000` (ctr01 : réservation Kea 10.10.99.121) |
| Code | rôle `registre_travail` + `certificats_acme` (`plateforme/ansible`), `playbooks/registre-travail.yml`, `host_vars/ctr01/` |
| Fichiers sur `ctr01` | `/opt/registre/` (`compose.yaml`, `config.yml`, `htpasswd`), certificat `/etc/registre/tls/`, données : volume Docker `registre_donnees` |
| TLS | certificat ACME de step-ca (30 jours), renouvelé par `cert-renewer@registre.timer`, puis redémarrage du registre |
| Comptes | `plateforme` (équipe, vérifications, recette de `ctr02`), `ci` (pipelines de `runner02`) ; mots de passe : Vault `lab` (`host_vars/ctr01/vault.yml`) ; aucun droit par dépôt : **tout compte authentifié lit, écrit et supprime partout** |
| Suppression | activée (`storage.delete.enabled`) : `DELETE /v2/<nom>/manifests/<empreinte>` |
| Ramasse-miettes | `registre-gc.timer` (dimanche 03:30) : registre **arrêté** quelques secondes, `registry garbage-collect --delete-untagged`, redémarrage |
| Flux (bordure) | `ctr01` → `ca01:443` (ACME), `ca01` → `ctr01:80` (défi HTTP-01), `runner02` → `ctr01:5000` (M12-E20) ; MGMT et VLAN 99 : directs |
| Sauvegarde | aucune (le contenu se reconstruit depuis la CI) ; la VM est jetable |

## Nommage des images

`ctr01.par1.medisphere.internal:5000/<groupe GitLab>/<projet>:<version>` : `mediagenda/api`, `medidoc/medidoc`, `medinotif/worker`, `legacy/legacy-rdv`. Versions `X.Y.Z` (étiquettes Git `vX.Y.Z`), images de travail `main-<SHA court>`, cache de construction `cache`. Jamais `latest`. Miroir des images de base : `miroir/…` (M12-E13).

## Gestes courants

```
admin@adm01:~$ set -a; . ~/.config/workbook/registre-travail.env; set +a
admin@adm01:~$ curl -s -u "$REGISTRE_UTILISATEUR:$REGISTRE_MOT_DE_PASSE" https://ctr01.par1.medisphere.internal:5000/v2/_catalog | jq
admin@adm01:~$ curl -s -u "$REGISTRE_UTILISATEUR:$REGISTRE_MOT_DE_PASSE" https://ctr01.par1.medisphere.internal:5000/v2/mediagenda/api/tags/list | jq
```

(`-u utilisateur:mot de passe` fait apparaître le mot de passe dans la liste des processus de `adm01` : sur une machine partagée, préférer `curl -K ~/.config/workbook/registre-ci.curl`.)

Supprimer une version : récupérer l'empreinte (`curl -sI -H 'Accept: application/vnd.oci.image.index.v1+json' …/manifests/<version>`, en-tête `Docker-Content-Digest`), puis `DELETE …/manifests/<empreinte>`. L'espace n'est rendu qu'au passage du ramasse-miettes.

Rotation d'un mot de passe : nouvelle valeur dans le Vault, `playbooks/registre-travail.yml` (le rôle réécrit la seule ligne concernée et redémarre le registre), puis mise à jour des consommateurs (variables de CI : `ms-variables-registre`, `~/.config/workbook/`, `auth.json` de `app` sur `ctr02`). Registre des secrets à jour.

## Limites connues

Pas de haute disponibilité, pas de droits par projet, pas d'analyse de vulnérabilités, pas de signature, pas de réplication : c'est l'objet de Harbor (M13).
