# RB-141 — Restaurer etcd de `k8s-par1`

| | |
|---|---|
| **Portée** | etcd empilé de `k8s-par1` (trois membres sur `k8s-cp01-03`) |
| **Déclencheurs** | perte du quorum sans espoir de retour (deux membres ou plus détruits) ; état du cluster corrompu ou détruit par erreur (suppression massive, `kubectl delete namespace` sur un espace critique) quand aucune autre voie n'existe |
| **Ne pas utiliser pour** | **un seul** membre en panne (quorum présent) : RB-144 ; un objet supprimé par erreur qu'on peut recréer depuis le code (`plateforme/k8s`, dépôts des applications) : on le recrée, on ne restaure pas tout le cluster |
| **Durée mesurée** | à reprendre de **ton** test (`docs/kubernetes/tests/restauration-etcd.md`) ; ordre de grandeur sur le lab : 30 à 45 min de bout en bout, dont 8 à 15 min d'API indisponible |
| **Effet** | l'API est **arrêtée** pendant l'opération ; les pods déjà lancés continuent de tourner (le kubelet et Cilium ne dépendent pas de l'API pour servir) ; **tout** ce qui a changé dans le cluster après l'instantané est perdu |
| **Références** | [Operating etcd clusters — Restoring](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#restoring-an-etcd-cluster), [etcd 3.6 — Disaster recovery](https://etcd.io/docs/v3.6/op-guide/recovery/) |

## 1. Décider

Une restauration ramène **tout** le cluster à l'instant de l'instantané : les Deployments créés depuis, les montées de version d'images faites par les équipes, les jetons émis, les baux. Avant de restaurer, réponds par écrit dans le ticket :

1. Le quorum est-il vraiment perdu (`etcdctl endpoint status --cluster`, deux membres sur trois injoignables **et** irrécupérables) ? Si un seul membre est perdu : RB-144.
2. L'objet perdu peut-il être recréé par le code ? Si oui : ne restaure pas.
3. Quel instantané ? Le plus récent **antérieur** à l'incident (heure de l'incident dans l'audit, `docs/kubernetes/tests/enquete-audit.md`). RPO : un instantané toutes les 20 minutes environ (trois nœuds décalés).
4. Qui prévient les équipes (Nadia), et de quoi : les changements faits depuis l'instantané sont à rejouer.

## 2. Préalables

- [ ] Clé privée `age` des sauvegardes : `plateforme/k8s` `secrets/etcd-instantane-age.cle` (Vault `critique`) ou copie papier.
- [ ] Clé de chiffrement des Secrets (M14-E28) **en vigueur au moment de l'instantané** : `group_vars/k8s_plan_controle/vault-critique.yml` de `plateforme/ansible` (les clés retirées sont gardées 35 jours, la rétention des instantanés). Sans elle, les Secrets restaurés sont illisibles.
- [ ] `etcdutl` de la version d'etcd du cluster sur `adm01` et sur les trois nœuds (`etcdutl version`).
- [ ] Session SSH ouverte sur les trois nœuds de contrôle ; console Proxmox accessible.
- [ ] Ce runbook imprimé ou ouvert ailleurs que sur le cluster.

## 3. Récupérer et vérifier l'instantané (depuis `adm01`)

```
admin@adm01:~$ ( set -a; . ~/.config/workbook/s3-etcd.env; set +a
>   aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 ls s3://etcd-k8s-par1/horaire/ --recursive | tail -9 )
admin@adm01:~$ install -d -m 700 ~/restau-etcd && cd ~/restau-etcd
admin@adm01:~/restau-etcd$ ( set -a; . ~/.config/workbook/s3-etcd.env; set +a
>   aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 s3 cp s3://etcd-k8s-par1/<CLE-DE-L-OBJET> etcd.db.age )
admin@adm01:~/restau-etcd$ age -d -i <(cd ~/src/k8s && uv run --project ~/src/ansible ansible-vault view \
>   --vault-id critique@$HOME/src/ansible/outils/vault-pass-client.sh secrets/etcd-instantane-age.cle) -o etcd.db etcd.db.age
admin@adm01:~/restau-etcd$ etcdutl snapshot status etcd.db -w table
admin@adm01:~/restau-etcd$ sha256sum etcd.db
admin@adm01:~/restau-etcd$ for n in k8s-cp01 k8s-cp02 k8s-cp03; do scp -q etcd.db $n:/var/tmp/etcd-restau.db; ssh $n 'chmod 600 /var/tmp/etcd-restau.db; sha256sum /var/tmp/etcd-restau.db'; done
```

Les trois empreintes sont identiques à celle d'`adm01` : **le même fichier** sur les trois membres. Note la révision affichée par `snapshot status`.

À défaut de `s3-01`, chaque nœud garde ses six derniers instantanés en clair dans `/var/backups/etcd/` : prends le plus récent des trois nœuds, copie-le sur les deux autres.

## 4. Arrêter le plan de contrôle (les trois nœuds, l'un après l'autre)

> ⚠️ À partir d'ici, l'API est indisponible. Note l'heure.

```
admin@k8s-cp01:~$ sudo /usr/local/sbin/etcd-restaurer-membre arreter
admin@k8s-cp02:~$ sudo /usr/local/sbin/etcd-restaurer-membre arreter
admin@k8s-cp03:~$ sudo /usr/local/sbin/etcd-restaurer-membre arreter
```

(Le script est installé sur les nœuds de contrôle par le rôle `etcd_instantane` ; lis son aide : `sudo etcd-restaurer-membre`.) Il copie les manifestes dans `/etc/kubernetes/manifests-arretes-<DATE>/` — **hors** du répertoire lu par le kubelet —, vide `/etc/kubernetes/manifests/` et attend l'arrêt des conteneurs `etcd`, `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` (`crictl ps`). Suspends aussi les minuteries `etcd-instantane.timer` (elles échoueraient et alerteraient) : `sudo systemctl stop etcd-instantane.timer`.

## 5. Restaurer chaque membre

Même composition, même jeton, même date sur les trois nœuds :

```
admin@k8s-cp01:~$ sudo ETCD_CLUSTER=k8s-cp01=https://10.10.40.51:2380,k8s-cp02=https://10.10.40.52:2380,k8s-cp03=https://10.10.40.53:2380 \
>   ETCD_JETON=k8s-par1-restau-<AAAAMMJJ> RESTAU_DATE=<AAAAMMJJ> \
>   /usr/local/sbin/etcd-restaurer-membre restaurer /var/tmp/etcd-restau.db
```

(idem sur `k8s-cp02` et `k8s-cp03`). Le script lit le nom et l'URL de pair du membre dans **son** manifeste, déplace `/var/lib/etcd` vers `/var/lib/etcd.avant-restauration-<DATE>` (retour arrière), puis lance :

```
etcdutl snapshot restore /var/tmp/etcd-restau.db --name <NŒUD> \
  --initial-cluster <COMPOSITION> --initial-cluster-token <JETON> \
  --initial-advertise-peer-urls https://10.10.40.5N:2380 \
  --bump-revision 1000000000 --mark-compacted --data-dir /var/lib/etcd
```

- `--bump-revision` : la révision repart **au-dessus** de celle d'avant l'incident (un milliard couvre largement une semaine d'écritures) ; aucun client ne voit la révision reculer.
- `--mark-compacted` : toutes les révisions antérieures sont déclarées compactées ; les *watch* en cours sont coupés et les caches (*informers*) des contrôleurs, du kubelet, de Cilium **doivent** relister.
- La composition est écrite **dans** les données : etcd ignore ensuite les options `--initial-cluster*` de son manifeste.

## 6. Redémarrer, dans l'ordre

1. **etcd sur les trois nœuds, à la suite** (un membre seul attend ses pairs) : `sudo /usr/local/sbin/etcd-restaurer-membre etcd` sur chaque nœud. Puis, depuis un nœud :
   ```
   admin@k8s-cp01:~$ sudo ETCDCTL_ENDPOINTS=https://127.0.0.1:2379 ETCDCTL_CACERT=/etc/kubernetes/pki/etcd/ca.crt \
   >   ETCDCTL_CERT=/etc/kubernetes/pki/etcd/healthcheck-client.crt ETCDCTL_KEY=/etc/kubernetes/pki/etcd/healthcheck-client.key \
   >   etcdctl endpoint health --cluster
   ```
   Trois membres `healthy`. `member list` montre des identifiants **nouveaux**.
2. **Plan de contrôle** : `sudo /usr/local/sbin/etcd-restaurer-membre plan` sur chaque nœud. Attendre `kubectl get --raw /readyz` (depuis `adm01`).
3. **Kubelets** : `sudo systemctl restart kubelet` sur les six nœuds, un par un.
4. **Cilium et CoreDNS** : `kubectl -n kube-system rollout restart deployment/cilium-operator daemonset/cilium deployment/coredns`, puis `cilium status --wait`.
5. Minuteries : `sudo systemctl start etcd-instantane.timer` sur les trois nœuds ; un instantané à la demande (`outils/etcd-instantane.sh --verifier`).

## 7. Vérifier

- `kubectl get nodes` : six nœuds `Ready`.
- `etcdctl endpoint status --cluster -w table` : révision supérieure à 1 000 000 000, un leader.
- Les objets attendus sont là (ex. l'espace perdu), à l'état de l'heure de l'instantané.
- `kubectl get pods -A | grep -v Running` : rien d'anormal au bout de 5 minutes ; les pods de l'espace restauré ont été **recréés** — leurs données de volumes `emptyDir` ou `hostPath` jetables sont perdues (etcd ne contient pas les données des volumes).
- `kubectl get secrets -A` puis la lecture d'un Secret applicatif : lisible (sinon, la clé de chiffrement n'est pas la bonne : §2).
- Les composants installés après l'instantané (Helm, CRD) sont à réinstaller depuis le code.

## 8. Retour arrière (si l'étape 6 échoue)

Sur les **trois** nœuds : `sudo RESTAU_DATE=<AAAAMMJJ> /usr/local/sbin/etcd-restaurer-membre annuler` — arrêt, ancien répertoire remis, manifestes remis. Le cluster revient exactement à l'état d'avant la restauration (avec son problème d'origine).

## 9. Après

- Seulement quand tout est vérifié (le lendemain) : supprimer `/var/lib/etcd.avant-restauration-<DATE>`, `/etc/kubernetes/manifests-arretes-<DATE>/` et `/var/tmp/etcd-restau.db` sur les trois nœuds, `~/restau-etcd/` sur `adm01` (`shred -u`).
- Ticket : heure de l'instantané, heure de fin, RPO effectif (changements perdus), RTO, ce qui a été rejoué.

## 10. Ce que les sauvegardes PBS des VMs ne font pas

Les VMs `k8s-cp01-03` sont sauvegardées chaque nuit dans PBS (`par1/k8s`). Ces sauvegardes servent à **reconstruire une VM** (système, paquets, configuration locale) quand le code ne suffit pas. Elles ne remplacent pas cet instantané :
- une sauvegarde de VM prise à chaud est cohérente « comme après une coupure » au mieux, et les trois VMs ne sont pas sauvegardées au même instant ;
- **restaurer une seule VM de nœud de contrôle dans un cluster vivant est dangereux** : son membre etcd revient avec un état ancien et l'identité d'un membre existant ; il faut au contraire traiter ce nœud comme neuf (RB-144 : retrait du membre, `kubeadm reset`, nouvelle jonction).
