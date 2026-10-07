# RB-051 — Restaurer un état OpenTofu (compartiment `tofu-state` de `s3-01`)

| | |
|---|---|
| **Quand** | `tofu plan` propose de créer, importer ou détruire ce que personne n'a demandé, et le diagnostic (M05-E42) a établi que l'**objet d'état** est en cause : marqueur de suppression courant, objet écrasé, état incohérent après une manipulation |
| **Qui** | astreinte Plateforme ; information obligatoire dans `#plateforme` avant l'étape 4 |
| **Durée** | 15 min (hors diagnostic) |
| **Prérequis** | `adm01`, AWS CLI v2 (profil `s3-socle`), identité `tofu-etat` (`~/.config/workbook/s3-tofu.env`), clone `~/src/infra` à jour, phrase de chiffrement (`~/.config/workbook/tofu-chiffrement.pass`) |
| **Ne couvre pas** | perte de `s3-01` ou du compartiment entier : restauration depuis la sauvegarde hors site (M05-E29), puis ce runbook |

## 0. Avant tout : est-ce vraiment l'objet ?

Dans la configuration concernée (`<CONFIG>` = `socle` ou `envs/<env>`) :

```
admin@adm01:~/src/infra/<CONFIG>$ git status --short --ignored      # rien d'inattendu (surcharges, *.auto.tfvars)
admin@adm01:~/src/infra/<CONFIG>$ tofu workspace show                 # default
admin@adm01:~/src/infra/<CONFIG>$ jq -r .backend.config.key .terraform/terraform.tfstate
```

Si l'espace de travail ou la clé sont faux : **ce runbook ne s'applique pas** (`tofu workspace select default`, ou `git restore` + `tofu init -reconfigure`).

## 1. Geler

Message dans `#plateforme` : « Gel des apply sur `<CONFIG>` (INC-xxxx), restauration de l'état en cours ». Si le pipeline le permet, variable de gel des jobs d'apply. Attendre la fin de tout job d'apply en cours.

## 2. Vérifier l'absence de verrou

```
admin@adm01:~$ set -a; . ~/.config/workbook/s3-tofu.env; set +a
admin@adm01:~$ aws s3api head-object --bucket tofu-state --key <CLÉ>.tflock
```

Un verrou présent : RB-050 d'abord.

## 3. Lister et enregistrer les versions

```
admin@adm01:~/src/infra$ outils/restaurer-etat.sh lister <CLÉ>
```

Choisir la **dernière version de données saine** : celle du dernier apply connu (date et heure du job d'apply dans GitLab), de taille cohérente avec les précédentes. Un marqueur de suppression ne se restaure pas : on restaure la version de données qui le précède. Noter le `VersionId` choisi et la raison dans le ticket.

## 4. Restaurer

```
admin@adm01:~/src/infra$ outils/restaurer-etat.sh restaurer <CLÉ> <VersionId>
```

Le script refuse si un verrou existe, enregistre la liste des versions et l'objet courant dans `~/m05/sauvegardes-etat/` (600), recopie la version choisie comme nouvelle version courante. Il ne supprime **rien**.

## 5. Prouver

```
admin@adm01:~/src/infra/<CONFIG>$ tofu state list          # toutes les ressources attendues
admin@adm01:~/src/infra/<CONFIG>$ tofu plan                 # « No changes »
```

Si le plan n'est pas vide : **ne pas appliquer**. Revenir à l'étape 3 (version plus ancienne ?) ou escalader (Karim).

## 6. Lever le gel et tracer

Message de fin dans `#plateforme` ; ticket complété (version restaurée, preuve, durée) ; post-mortem si l'état du socle était touché (P1).

## Retour arrière

La restauration ajoute une version : pour revenir à l'état d'avant la restauration, recommencer l'étape 4 avec le `VersionId` de l'objet courant enregistré à l'étape 4 (fichier `*.versions.json` de `~/m05/sauvegardes-etat/`).

## Interdits

`delete-object --version-id` sur une version de données ; `tofu state push -force` ; édition de l'état à la main ; apply pendant le gel.
