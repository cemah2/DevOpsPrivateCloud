# RB-050 — Verrou d'état OpenTofu bloqué

| | |
|---|---|
| Service | États OpenTofu de `plateforme/infra` (compartiment `tofu-state` sur `s3-01`) : `socle/`, `envs/*/`, unités Terragrunt |
| Rédigé | M05-E33 (PLAT-677) — dernière exécution complète : AAAA-MM-JJ, INC-… |
| Qui peut l'exécuter | Astreinte (étapes 1 à 4, lecture seule) ; levée du verrou (étape 5) : Maintainer de `plateforme/infra`, ou l'astreinte après accord d'un Maintainer joint par téléphone |
| Durée attendue | 10 à 20 min |
| Retour arrière | Aucun pour la levée elle-même ; l'état est protégé par le versionnage (RB-050 § 7, `outils/restaurer-etat.sh`) |

## Quand utiliser ce runbook

Un `tofu plan` / `tofu apply` (job `plan:`, `apply:`, `derive:`, ou sur `adm01`) échoue avec :

```
Error: Error acquiring the state lock
Error message: operation error S3: PutObject, https response error StatusCode: 412 … PreconditionFailed …
Lock Info:
  ID:        c74aca48-6276-cf42-25b0-be8b7ab98140
  Path:      tofu-state/socle/terraform.tfstate
  Operation: OperationTypeApply
  Who:       gitlab-runner@runner01
  Version:   1.13.1
  Created:   2026-10-07 20:17:45 +0000 UTC
```

**Ne pas utiliser** si le message parle d'autre chose que d'un verrou existant (certificat, 403,
réseau, déchiffrement) : c'est une panne du backend ou des accès, pas un verrou.

## Ce qu'il faut savoir

- Le verrou d'un état `<clé>` est l'objet `<clé>.tflock` du compartiment, créé par une écriture
  conditionnelle (`If-None-Match: *` : 412 si l'objet existe déjà) et **supprimé à la fin** de
  l'opération. Il reste quand le processus qui le détenait est mort sans finir (`kill -9`, job
  tué, machine redémarrée).
- Un verrou **vivant** protège une opération en cours : le lever, c'est permettre deux écritures
  concurrentes du même état. Le seul risque de ce runbook est là.
- Un plan prend aussi le verrou : un verrou `OperationTypePlan` orphelin est sans danger pour
  l'état (rien n'a été écrit). Un verrou `OperationTypeApply` orphelin signifie qu'un apply a
  peut-être **été interrompu au milieu** : étape 6 obligatoire.

## Étapes

### 1. Relever (sans rien modifier)

Depuis `adm01`, dans `~/src/infra` :

```
admin@adm01:~/src/infra$ . outils/charger-acces.sh
admin@adm01:~/src/infra$ aws s3api get-object --bucket tofu-state --key <CLÉ>.tflock /tmp/verrou.json >/dev/null && jq . /tmp/verrou.json
admin@adm01:~/src/infra$ date -u
```

`<CLÉ>` est le `Path` du message sans le préfixe `tofu-state/` (ex. `socle/terraform.tfstate`).
Note dans le ticket : `ID`, `Operation`, `Who`, `Created`, et l'âge du verrou.

### 2. Qui le détient ? — arbre de décision

```
Who = gitlab-runner@runner01 ?
├── oui → GitLab : plateforme/infra › Build › Jobs, filtre « Running »
│         (ou : Operate › Environments, resource_group tofu-<configuration>)
│         ├── un job apply:/plan:/derive: de cette configuration est EN COURS
│         │     → VERROU VIVANT : attendre la fin du job (timeout 1 h). Ne rien lever. FIN.
│         └── aucun job en cours (job annulé, tué par son délai, runner redémarré)
│               → vérifier le processus (étape 3), puis ORPHELIN probable
├── Who = admin@adm01 (ou un autre compte humain)
│     → étape 3 sur la machine indiquée ; prévenir la personne (canal de l'équipe)
│         ├── un tofu/terragrunt tourne (même dans un tmux oublié) → VIVANT : la personne termine
│         │     ou interrompt proprement (Ctrl+C pour un plan ou un apply ; « exit » ou Ctrl+D
│         │     pour une tofu console : détachée de son terminal, elle ignore kill -INT et
│         │     kill -TERM). Jamais kill -9. FIN.
│         └── aucun processus → ORPHELIN
└── Who inconnu / machine inconnue
      → ne rien lever ; escalade (étape 8) : quelqu'un écrit dans l'état depuis un poste non prévu.
```

### 3. Vérifier qu'aucun processus ne vit

```
admin@adm01:~$ ssh runner01 'pgrep -af "tofu|terragrunt" || echo aucun processus'
admin@adm01:~$ pgrep -af "tofu|terragrunt" || echo aucun processus
admin@adm01:~$ tmux ls 2>/dev/null
```

Un processus `tofu` présent **est** le détenteur probable : on ne lève rien tant qu'il vit.

### 4. Décider

On ne lève le verrou que si **les trois** conditions sont réunies : aucun job en cours sur cette
configuration, aucun processus `tofu`/`terragrunt` sur la machine de `Who`, et un Maintainer
d'accord (nom dans le ticket). Sinon : attendre, ou escalader.

### 5. Lever le verrou

Dans le dossier de la configuration concernée (accès chargés, étape 1) :

```
admin@adm01:~/src/infra/<CONFIGURATION>$ tofu force-unlock <ID>
```

Répondre `yes` après avoir relu l'ID. Pour une unité Terragrunt : `terragrunt force-unlock <ID>`
dans le dossier de l'unité. OpenTofu refuse si l'ID ne correspond pas au verrou présent : c'est
une protection contre la levée d'un **autre** verrou, posé entre-temps.

### 6. Vérifier

```
admin@adm01:~/src/infra/<CONFIGURATION>$ tofu plan
admin@adm01:~/src/infra$ outils/restaurer-etat.sh --lister <CLÉ> | head -5
```

- `Operation` était `OperationTypePlan` : le plan doit être celui d'avant l'incident (souvent vide).
- `Operation` était `OperationTypeApply` : lire le plan **ligne à ligne**. Un `+ create` sur une VM
  qui existe déjà dans Proxmox (`ssh pve01 qm list`) = l'apply a créé la VM mais n'a pas eu le
  temps de l'écrire dans l'état : **ne pas appliquer**, escalader (import, E16). Une ressource
  marquée `tainted` = création interrompue : décision d'un Maintainer.
- La liste des versions montre la dernière écriture de l'état : sa date doit être cohérente avec
  l'opération interrompue.

Puis relancer l'opération qui avait échoué (le job `apply:` du **dernier** pipeline de `main`,
pas celui d'avant : son plan serait périmé).

### 7. Si l'état lui-même est abîmé

Plan impossible (« Failed to load state », déchiffrement) après la levée : ce n'est plus un
verrou. Restaurer la dernière version saine (procédure « Sauvegarde et restauration de l'état »,
`docs/socle/iac.md`), puis § 6.

### 8. Escalade

Karim Benali (Maintainer) si : `Who` inconnu ; `OperationTypeApply` avec un plan qui crée ou
détruit une VM ; force-unlock refusé deux fois ; verrou qui réapparaît sans opération visible.

## Ce qu'il ne faut jamais faire

| Interdit | Pourquoi |
|---|---|
| `-lock=false` sur `apply`, `import`, `state …` | deux écritures concurrentes du même état : la seconde écrase la première |
| Supprimer l'objet `.tflock` à la main (`aws s3 rm`) | contourne la vérification d'ID de `force-unlock` ; à réserver au cas où OpenTofu ne peut pas lire le verrou (objet illisible : « unable to json parse the lock info », donc pas d'ID pour `force-unlock`), après les étapes 2 à 4 et avec l'accord d'un Maintainer |
| Lever un verrou parce qu'il est « vieux » | un apply long ou bloqué sur une API lente est vivant ; l'âge n'est pas une preuve |
| Annuler un job `apply:` pour « débloquer » | c'est exactement ce qui fabrique un verrou orphelin et un état partiel |
| Relancer un ancien pipeline après la levée | son plan est périmé (« Saved plan is stale ») ou, pire, décrit une autre réalité |

## Consigner

Ticket INC : contenu du verrou, preuve que le détenteur était mort (job, processus), nom du
Maintainer qui a accepté, heure de la levée, résultat du plan de l'étape 6. Une ligne dans
`docs/socle/journal/`. Deux verrous orphelins du même type en un mois : post-mortem (pourquoi les
jobs meurent-ils en plein apply ?).
