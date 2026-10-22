<!-- docs/observabilite/metriques/securite.md — EXTRAIT : section « Limites connues » mise à jour en M26-E25. -->

- ~~Collecte des kubelets sans vérification TLS~~ **levée en M26-E25** : certificats de service signés par
  la CA du cluster (M14-E26), approuvés par `kubelet-csr-approver`, vérifiés par Prometheus
  (`kubelet.serviceMonitor.tlsConfig` : CA `kube-root-ca.crt`, `insecureSkipVerify: false`).
- Collecte de kube-controller-manager et de kube-scheduler **toujours sans vérification TLS** : kubeadm
  ne leur donne pas de certificat de service signé (certificat auto-signé généré au démarrage). Le jeton
  de Prometheus ne part que vers les trois adresses des nœuds de contrôle, désormais filtrées par le
  pare-feu d'hôte (M26-E27). Levée possible : certificats émis par la CA du cluster et passés par
  `--tls-cert-file`/`--tls-private-key-file` (extraArgs de la ClusterConfiguration), à renouveler.
- etcd : métriques en HTTP sur 2381 (pas de secret, mais en clair sur le VLAN 40 : les nœuds de contrôle
  sont exclus du chiffrement nœud à nœud de WireGuard, M26-E26).
