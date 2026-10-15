# RB-132 — Mettre à jour Harbor (version corrective)

| | |
|---|---|
| Quand | nouvelle version corrective 2.15.x (avis de sécurité, notes de version) ; vérification mensuelle |
| Durée | répétition sur `reg02` : `<D>` ; fenêtre sur `reg01` : 30 min annoncées (`<D>` mesurées) |
| Prérequis | sauvegarde de `reg01` réussie de moins de 26 h (RB-131) ; `reg02` disponible pour la répétition ; aucun pipeline important en cours ; Julien et Nadia prévenus |
| Retour arrière | section 4 (copie de la base faite à l'arrêt + ancien dossier d'installation) |

## 1. Préparer (J-2)

1. Lire les notes de version et les avis de sécurité de **toutes** les versions entre l'actuelle et la visée ; noter les changements de `harbor.yml.tmpl`, de base embarquée (exemple : 2.15.2 a fait passer PostgreSQL de 15 à 18) et de Trivy embarqué.
2. Vérifier l'installateur (RB-130, étape 1) : bundle Sigstore de la release, puis empreinte SHA-256.
3. MR sur `plateforme/ansible` : `harbor_version` et `harbor_installateur_sha256` (`group_vars/role_registre/harbor.yml`), gabarit `harbor.yml.j2` si des clés changent ; MR sur `plateforme/outils` : `MS_REG_VERSION`.

## 2. Répéter sur `reg02`

1. `reg02` en version actuelle de `reg01`, avec des images répliquées (E13) ou restaurées (RB-131).
2. `ansible-playbook playbooks/harbor-mise-a-jour.yml -l reg02` — noter la durée de chaque étape.
3. Vérifier : version (`/api/v2.0/systeminfo`), santé, images et signatures (`cosign verify`), nouvelle analyse d'une image.
4. Faire le **retour arrière** (section 4) sur `reg02`, vérifier, puis remonter.

## 3. Appliquer sur `reg01`

1. Annonce (canal des équipes, 24 h avant) ; ce jour-là : aucun pipeline de publication en cours.
2. `ansible-playbook playbooks/harbor-mise-a-jour.yml -l reg01`.
3. Vérifier comme en 2.3 ; `ms-verif-registre` vert ; relancer une analyse complète (*Scan all*) ; prévenir la fin.
4. Garder une semaine : `/data/database.avant-<version>`, `/opt/harbor-dist/<ancienne>/` et ses images ; puis les supprimer (MR de nettoyage).

## 4. Retour arrière

À décider si la santé ne revient pas, si les tirages échouent ou si la base ne migre pas (`docker logs harbor-core` : erreurs de migration).

```
root@reg01:~# systemctl stop harbor.service
root@reg01:~# ln -sfn /opt/harbor-dist/<ANCIENNE>/harbor /opt/harbor
root@reg01:~# mv /data/database /data/database.echec-<VISEE> && cp -a /data/database.avant-<VISEE> /data/database
root@reg01:~# systemctl daemon-reload && systemctl start harbor.service
```

`<ANCIENNE>` et `<VISEE>` : les versions (ex. 2.15.2 et 2.15.3). Puis remettre `harbor_version` à l'ancienne valeur par MR (sinon le prochain passage du rôle refuse, ou rebascule). Les images poussées pendant la fenêtre n'existent pas dans l'ancienne base : les republier. Si la copie de la base manque : RB-131 (restauration de la sauvegarde de la nuit).

## Pièges

- Copier `/data/database` **à chaud** : copie incohérente, inutilisable.
- Lancer `install.sh` d'une nouvelle version sur l'ancien `harbor.yml` sans relire les clés : options nouvelles absentes, anciennes ignorées.
- Oublier `MS_REG_VERSION` : la sonde reste rouge (à raison) après la mise à jour.
