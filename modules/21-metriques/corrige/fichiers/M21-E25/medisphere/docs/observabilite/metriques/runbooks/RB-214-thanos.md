# RB-214 — Thanos : blocs qui n'arrivent plus, Compactor arrêté, Store ou sidecar invisible

| | |
|---|---|
| Alertes | `ThanosQuerySidecarManquant`, `ThanosQueryStoreManquant` (§1) ; `ThanosSidecarEnvoisArretes`, `ThanosCompartimentEnEchec` (§2) ; `ThanosCompacteurArrete`, `ThanosCompacteurAbsent`, `ThanosCompacteurInactif` (§3) ; `ThanosCompacteursMultiples` (§4) |
| Gravité | avertissement (heures ouvrées), sauf `ThanosCompacteursMultiples` : critique |
| Équipe | plateforme |
| Architecture | [`thanos.md`](../thanos.md) |
| Ticket d'origine | PLAT-2225 (M21-E25) |

## Impact

- **Aucune perte immédiate** tant que les deux Prometheus tournent : chaque réplica garde 15 jours en local. Un envoi arrêté laisse donc 15 jours (moins l'âge de la panne) pour réparer avant de perdre des données dans le compartiment.
- Store ou Compactor arrêté : les requêtes au-delà de 15 jours sont vides ou lentes ; les tableaux « 90 jours » et les SLO sur 28 jours mentent.
- **Deux Compactors** : risque réel de blocs perdus ou chevauchants. C'est la seule alerte critique de ce runbook.

## 0. Règles

- Jamais d'opération d'écriture à la main sur le compartiment (`aws s3 rm`, `thanos tools bucket cleanup|mark|rewrite|retention`) pendant que le Compactor tourne. Si une réparation l'exige : Compactor à 0 réplica **d'abord** (§4), opération, puis remise à 1.
- Une panne de supervision ne supprime **jamais** de bloc. Un bloc « en trop » coûte de la place ; un bloc supprimé à tort est perdu.
- Les identifiants de lecture de `adm01` (`s3-thanos.env`) sont ceux de l'utilisateur `thanos` : ils permettent aussi d'écrire. Prudence.

## 1. Thanos Query ne voit pas tous ses points d'accès

```
admin@adm01:~$ curl -s http://prometheus.apps.par1.medisphere.internal:9090/api/v1/stores \
    | jq '.data | map_values(map({name, lastError, minTime, maxTime}))'
```

Attendu : `sidecar` = 2 entrées (une par pod `prometheus-kps-N`), `store` = 1 entrée, `lastError` nul.

| Constat | Piste |
|---|---|
| Un sidecar absent | `kubectl -n supervision get pods -l app.kubernetes.io/name=prometheus` ; le pod redémarre-t-il ? Conteneur `thanos-sidecar` prêt ? `kubectl -n supervision get endpointslices -l kubernetes.io/service-name=kps-thanos-discovery` |
| `lastError` « connection refused / i/o timeout » | politique `prometheus-entree` (port 10901 depuis `supervision`), Hubble : `hubble observe -n supervision --to-pod prometheus-kps-0 --port 10901 --verdict DROPPED` |
| Store absent | `kubectl -n supervision get pods thanos-store-0` ; prêt seulement après le chargement des index (plusieurs minutes au démarrage) ; journaux |
| Les deux présents mais requêtes anciennes vides | §2 (rien dans le compartiment) ou §3 (rétention trop courte ?) |

## 2. Les blocs n'arrivent plus dans le compartiment

```
admin@adm01:~$ kubectl -n supervision logs prometheus-kps-0 -c thanos-sidecar --since=3h | grep -iE 'upload|error' | tail
admin@adm01:~$ (set -a; . ~/.config/workbook/s3-thanos.env; set +a
>   aws s3api list-objects-v2 --bucket thanos-k8s-par1 --delimiter / --query 'CommonPrefixes[-5:]')
admin@adm01:~$ cfg="$(~/src/observabilite/outils/objstore-local.sh)"
admin@adm01:~$ thanos tools bucket inspect --objstore.config-file="$cfg" --sort-by=FROM | tail -8; rm -f "$cfg"
```

| Message ou constat | Cause probable | Correctif |
|---|---|---|
| `SignatureDoesNotMatch`, `InvalidAccessKeyId` | Secret `thanos-objstore` faux ou clés RGW changées | `secrets-k8s.sh thanos` depuis le Vault ; les pods relisent le Secret au redémarrage (sidecar : supprimer un pod Prometheus à la fois) |
| `x509: certificate signed by unknown authority` | `ca_file` absent ou ConfigMap `racine-medisphere` vide | volume monté dans le conteneur ? chemin `/etc/thanos/ca/ca.crt` ? |
| `QuotaExceeded` | quota de l'utilisateur RGW atteint | `ssh ceph01 sudo radosgw-admin user stats --uid=thanos --sync-stats` ; rétention appliquée (§3) ? Relever le quota est une décision (capacité de `ceph-par1`), pas un réflexe |
| `dial tcp 10.10.30.200:443: i/o timeout` | chemin réseau du pod vers le RGW (carte `eth1`, politique de sortie de l'espace depuis M21-E29) | `hubble observe -n supervision --to-ip 10.10.30.200 --verdict DROPPED` |
| Aucun message, aucun envoi | Prometheus ne ferme pas de bloc (démarré depuis moins de 2 h) | attendre ; sinon `kubectl -n supervision exec prometheus-kps-0 -c prometheus -- ls /prometheus` |

## 3. Le Compactor est arrêté, absent ou inactif

```
admin@adm01:~$ kubectl -n supervision get pods thanos-compactor-0
admin@adm01:~$ kubectl -n supervision logs thanos-compactor-0 --since=24h | grep -iE 'halt|error|critical' | tail -20
admin@adm01:~$ kubectl -n supervision port-forward pod/thanos-compactor-0 10902:10902   # puis http://localhost:10902/blocks
```

| Constat | Cause probable | Correctif |
|---|---|---|
| `thanos_compact_halted 1`, « overlaps found » | deux blocs couvrent la même période avec les mêmes étiquettes externes (Compactor doublé un moment, étiquette externe changée, bloc envoyé à la main) | ne **rien** supprimer dans l'urgence. Lire les identifiants (ULID) cités, les inspecter (`thanos tools bucket inspect`), décider avec un second avis ; la réparation (marquer un bloc `no-compact` ou le supprimer) se fait Compactor arrêté |
| « no space left on device » | volume de travail trop petit pour le groupe à compacter | agrandir le PVC `travail-thanos-compactor-0` (expansion ceph-rbd, M16), redémarrer le pod |
| `QuotaExceeded` | quota RGW | §2 |
| pod `Pending` | volume ou nœud | `kubectl describe pod` (exception admise : le Compactor n'a pas de métrique quand il ne tourne pas) |
| `ThanosCompacteurInactif` sans erreur | rien à compacter (lab arrêté plusieurs jours) | vérifier l'âge du dernier bloc envoyé (§2) |

Après correction d'une cause d'arrêt : `kubectl -n supervision delete pod thanos-compactor-0` (stratégie `OnDelete` : c'est le seul moyen de le relancer).

## 4. Deux Compactors

```
admin@adm01:~$ kubectl get pods -A -l app.kubernetes.io/name=thanos-compactor -o wide
admin@adm01:~$ kubectl get statefulsets,deployments -A | grep -i compact
```

Arrêter **immédiatement** celui qui n'est pas `supervision/thanos-compactor-0` (copie d'essai, ancien déploiement, deuxième cluster pointé sur le même compartiment). Si c'est le StatefulSet lui-même (réplicas 2) : `kubectl -n supervision scale statefulset thanos-compactor --replicas=0`, corriger dans Git (`replicas: 1`), laisser Argo CD remettre 1. Puis lire les journaux des deux sur la période commune et suivre §3 si des chevauchements apparaissent.

## Escalade

Karim Benali (plateforme) pour toute décision qui touche aux blocs ; Claire Morel si le quota RGW doit être relevé (capacité de `ceph-par1`).
