# RB-361 — Forensique d'un conteneur

| | |
|---|---|
| Ticket | SEC-3610 (F6-S10) ; ferme ECA-3605 |
| Propriétaire | RSSI (Sophie Laurent) ; exécution : rôle « collecte » de RB-360 |
| Objet | Capturer l'état d'un conteneur suspect **vivant**, sans le détruire, pour l'enquête |
| Voir aussi | RB-360 (réponse à incident), RB-262 (conteneur compromis, M26, isolement et escalade) |

## 0. Quand

Après l'**isolement** (RB-262 : quarantaine réseau + pod sorti de son contrôleur), **avant** toute
éradication. Un pod supprimé ou redémarré = mémoire, processus, connexions et fichiers temporaires
perdus. On regarde de l'**extérieur** ; on ne lance rien dans le conteneur suspect lui-même.

## 1. Préparation

- Kit forensique vérifié (`outils/bin/verifier-kit-forensique.sh`) : image d'outils signée
  (`netshoot`/`busybox` de la bibliothèque), identité de dépôt des preuves, modèles.
- Dossier de travail en mémoire sur `adm01` : `D=$(mktemp -d "$XDG_RUNTIME_DIR/inc.XXXXXX")`.
- Variables : `export NS=<ESPACE> POD=<POD> C=<CONTENEUR>`.

## 2. Collecte (du plus volatil au plus durable)

| # | Pièce | Commande (lecture seule) |
|---|---|---|
| 1 | État du pod et du nœud | `kubectl -n $NS get pod $POD -o yaml > $D/pod.yaml` ; `kubectl get node <NŒUD> -o yaml > $D/noeud.yaml` |
| 2 | Processus et connexions (conteneur éphémère, même espace de processus) | `kubectl -n $NS debug -it pod/$POD --image=registry.par1.medisphere.internal/dockerhub/nicolaka/netshoot:v0.16 --target=$C --profile=restricted -- sh -c 'ps -ef; ss -tnap; cat /proc/1/cmdline \| tr "\0" " "' > $D/processus.txt` |
| 3 | Fichiers déposés (sans les exécuter) | depuis le conteneur éphémère : `ls -la /proc/1/root/tmp` ; `kubectl cp` du fichier **depuis le conteneur éphémère** (`/proc/1/root/tmp/<FICHIER>`) |
| 4 | Journaux du conteneur | `kubectl -n $NS logs $POD --all-containers --timestamps > $D/logs.txt` (`--previous` s'il a redémarré) |
| 5 | Événements de sécurité | export Loki (locataire `audit`) : `{service=~"falco\|tetragon"} \|= "$POD"` et `{job="kubernetes-audit"} \|= "$POD"` en JSON |
| 6 | Flux réseau | `hubble observe --pod $NS/$POD --since 24h -o json > $D/hubble.json` (tampon limité : tôt) |
| 7 | Journaux d'une destination externe (si « C2 » identifié) | relever les journaux de la destination **avant** toute destruction (ici `c2-simule01:/var/log/c2-simule.log`) |
| 8 | Capture de l'état vivant | **point de contrôle du kubelet** si disponible, sinon **copie** (ci-dessous) |

### 2.1 Capture de l'état vivant

**Point de contrôle (`ContainerCheckpoint`, KEP-2008)** — bêta, activé par défaut depuis 1.30, toujours
bêta en 1.36. Exige que le runtime l'implémente (containerd 2.x + CRIU sur le nœud) :

```
admin@adm01:~$ kubectl get --raw "/api/v1/nodes/<NŒUD>/proxy/checkpoint/$NS/$POD/$C"   # ou POST selon la version
```

> **Résultat sur le lab (F6-S10)** : *à renseigner à l'exercice.* Si le runtime l'implémente, l'archive
> est écrite sur le nœud dans `/var/lib/kubelet/checkpoints/` (lisible par root seulement) ; la copier
> avec son empreinte. Si `500`/non implémenté : **replier sur la copie** (§2.2) et l'écrire ici.

### 2.2 Repli : copie du système de fichiers et des journaux

Si le point de contrôle n'est pas disponible : depuis le conteneur éphémère (pièce 2), copier
`/proc/1/root` (système de fichiers du conteneur suspect, lecture seule) et les journaux (pièce 4) ;
instantané PBS du disque du nœud en dernier recours (`vzdump <VMID> --storage pbs-par2 --mode snapshot`).

## 3. Empreintes et dépôt

```
admin@adm01:~$ (cd $D && sha256sum * > SHA256SUMS && cat SHA256SUMS)       # recopiées dans la chronologie
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-preuves-conformite-depot.env; set +a; \
                aws s3 cp --recursive $D s3://preuves-conformite/INC-NNNN/$(date -u +%FT%TZ)/ \
                --endpoint-url https://rgw.par1.medisphere.internal)
admin@adm01:~$ rm -rf "$D"
```

Le compartiment `preuves-conformite` est en **verrouillage d'objets** (versionné) : une preuve déposée
ne peut plus être ni modifiée ni supprimée (F6-S02/S08). L'identité de dépôt écrit et liste, **jamais**
ne supprime.

## 4. Ce qu'on ne touche pas

- Le pod suspect : ni suppression, ni redémarrage, ni `exec` dans son conteneur, avant la fin de la
  collecte et l'accord de la RSSI (RB-360 §4, RB-262).
- Falco, Tetragon, Loki, le compartiment de preuves : jamais désactivés ni modifiés pour faire taire une
  alerte. Un silence Alertmanager **ciblé et daté** sur le pod isolé est permis (le consigner).
