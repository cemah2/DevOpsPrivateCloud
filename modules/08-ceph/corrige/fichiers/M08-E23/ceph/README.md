# plateforme/ceph — le cluster `ceph-par1` décrit par le code

Projet de l'équipe Plateforme (M08-E23, PLAT-933). Il contient l'**intention** du cluster Ceph
de PAR1 : les spécifications cephadm des services, l'état déclaratif qui n'est pas exprimable en
spécification, et les outils pour valider, appliquer et contrôler. Le cluster réel est confronté
au dépôt chaque nuit.

## Périmètre

| Dans le dépôt | Où | Appliqué par |
|---|---|---|
| Hôtes (adresse publique, étiquettes, baie initiale) | `specs/hosts.yaml` | `outils/appliquer.sh` |
| Services cephadm : `mon`, `mgr`, `osd.ssd`, `osd.hdd`, `mds.cephfs`, `rgw.par1`, `ingress.rgw.par1`, `nfs.par1` | `specs/*.yaml` | `outils/appliquer.sh` (ingress : via `outils/cert-ingress.sh`) |
| Seuils, options `ceph config`, règles CRUSH, profils EC, paramètres des pools | `config/cluster.yaml` | `outils/config-cluster.sh --appliquer` |
| Carte CRUSH attendue (tests hors ligne) | `config/crush-attendu.txt` | — (référence) |
| Exports NFS | `config/nfs/*.json` | `ceph nfs export apply par1 -i …` |
| Configuration client publique (dérive en CI) | `config/ceph-client.conf` | — |

**Hors du dépôt, volontairement** : certificat et clé du point d'entrée S3 (`~/.config/workbook/ceph-ingress/`
sur `adm01`, injectés à l'application), clés cephx (créées par commande, sauvegardées chiffrées,
inscrites au registre des secrets), clés d'accès S3 des utilisateurs RGW (Vault, registre des
secrets), comptes RGW et leurs quotas **jusqu'à M08-E31** (créés à la main en E12 ; ils entrent
ensuite dans `allocations.yaml`, tenu par `outils/ceph-allocations.sh`), carte CRUSH binaire, création et suppression de pools (gestes humains, fiche de
changement). **Services par défaut**, sans spécification ici : `crash`, `ceph-exporter`.

## Structure

```
bootstrap/   amorçage du cluster (M08-E03 : initial-ceph.conf, amorcer.sh) — une seule fois
specs/       spécifications cephadm (une par service, hosts.yaml à plusieurs documents)
config/      état déclaratif hors spécifications, carte CRUSH attendue, exports NFS
outils/      lib.sh (accès au cluster), pool-repliquee.sh (M08-E05), appliquer.sh, verifier-specs.sh, tester-crush.sh,
             derive.sh, config-cluster.sh, cert-ingress.sh, rapport-capacite.sh, systemd/
tests/       un cas fautif par règle maison (tests/cas-fautifs/regleN/), tester-regles.sh
```

## Règles maison (`outils/verifier-specs.sh`)

Issues de la revue M08-E21 ; chacune a un cas fautif que la CI vérifie **rejeté**.

1. Moniteurs en nombre impair, au moins 3.
2. Hôtes ajoutés par leur adresse du réseau public 10.10.30.0/24 (jamais le réseau de réplication).
3. `_admin` sur trois hôtes au plus, tous des nœuds du cluster (jamais un serveur de sauvegarde ni un client).
4. *Ingress* : VIP avec son masque `/24` ; ni certificat, ni clé, ni mot de passe dans le fichier.
5. Aucun bloc `PRIVATE KEY` dans `specs/` et `config/`.
6. Un service RGW n'écoute pas le port du frontal de son *ingress*.
7. OSD : jamais `all: true`, filtre `rotational` obligatoire, `osd_memory_target` ≤ 1,5 Gio.
8. Au moins deux MDS par volume.

## Procédure d'application

1. MR sur `main` : pipeline vert (yamllint, règles, tests des règles, CRUSH hors ligne, gitleaks),
   relecture par un second membre de l'équipe ; fiche de changement si le changement déplace des
   données (OSD, CRUSH, pools).
2. Après fusion, sur `adm01` : `git switch main && git pull`, puis
   `outils/appliquer.sh specs/<fichier>.yaml` (ou `--tout`). Le script refuse une copie qui n'est pas
   `origin/main`, refait les règles, montre le `--dry-run`, demande « oui », applique, puis lance la dérive.
3. État hors spécifications : `outils/config-cluster.sh --verifier`, puis `--appliquer` (confirmation
   à chaque geste ; un changement de règle de pool attend `HEALTH_OK` avant le suivant).
4. Certificat du point d'entrée S3 : automatique (`ceph-cert-ingress.timer` sur `adm01`) ; à la main :
   `outils/cert-ingress.sh --force`.

## Décision : qui applique ?

**L'application reste sur `adm01`, par un opérateur. La CI valide et contrôle, en lecture seule.**

- *Flux* : appliquer depuis `runner01` exigerait d'ouvrir les moniteurs (3300) **et** le gestionnaire
  actif (6800-7568, port dynamique qui suit les bascules) des trois nœuds, ou un SSH vers `ceph01`, à un
  exécuteur `shell` partagé par tous les projets du groupe. C'est le plan de contrôle du stockage.
- *Droits* : `ceph orch apply` demande l'écriture sur le gestionnaire. Une restriction aux seules
  simulations (`allow command "orch apply" with dry_run=true`) n'est pas garantie pour un argument
  booléen : une clé de CI capable de simuler pourrait appliquer, donc supprimer des services.
- *Rythme et risque* : quelques changements par mois, chacun suivi en direct (`ceph -s`, mouvements
  de données). L'automatisation n'apporterait pas de vitesse utile ; elle retirerait l'humain qui
  regarde.
- *Ce que la CI fait* : toutes les validations hors ligne, et la **dérive** chaque nuit avec
  `client.ci-lecture` (`mon 'allow r' mgr 'allow r'`, restreinte à 10.10.20.15). Seuls flux ouverts :
  `runner01` → 10.10.30.51-53, TCP 3300 et 6800-7568.

Révision prévue quand un exécuteur dédié au stockage (étiquette `ceph`, sur le VLAN 30, non partagé)
existera : un job manuel protégé `appliquer` avec une clé `mgr` d'écriture deviendrait acceptable.

## Dérive

`outils/derive.sh` : services présents d'un seul côté, toute valeur écrite dans `specs/` différente dans
le cluster, hôtes (adresse, étiquettes), état de `config/cluster.yaml`. Les valeurs par défaut que
cephadm ajoute à l'export ne sont pas des écarts (le dépôt fait foi pour ce qu'il dit). Limite connue :
une option ajoutée **à la main** dans le cluster et absente du dépôt n'est pas signalée ; la relecture
de `ceph orch ls --export` reste un geste de la revue trimestrielle.

Pipeline planifié : *Build → Pipeline schedules*, chaque nuit, variable `PLANIF=derive`. Un écart fait
échouer le pipeline : notification à l'équipe, ticket, puis soit correction du cluster, soit MR.

## Accès au cluster (`outils/lib.sh`)

| Où | Comment | Clé |
|---|---|---|
| `adm01` | `CEPH_ADMIN=ceph01` : `ssh ceph01 sudo ceph …` (repli : `sudo cephadm shell -- ceph …`) | `client.admin` du nœud `_admin`, jamais copiée |
| `runner01` (dérive) | `ceph --id ci-lecture --keyring … -c config/ceph-client.conf` | `client.ci-lecture` |
| un nœud Ceph | `ceph --id <id> --keyring <trousseau>` (`ceph-common` du palier 1) | au choix (ex. `client.rapport`) |
