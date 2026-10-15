<!-- Section ajoutée à RB-152 (créé en M15-E25) après M15-E38 : « Diagnostic », à insérer après « Constat ». Le tableau d'en-tête et les temps mesurés restent ceux de M15-E25. -->

# RB-152 — Diagnostic (ajout M15-E38)

## Précautions de diagnostic

- **Ne bascule jamais la VIP** de la bordure pour tester : lis la table de chaque passerelle.
- Sur FRR : lecture par `vtysh -c 'show …'` ; correction par le rôle Ansible (`playbooks/bordure-frr.yml`, qui fait un `reload`). Jamais `systemctl restart frr` (toutes les sessions tombent, Lyon compris).
- Côté Cilium : les objets BGP sont dans `plateforme/k8s/composants/cilium/` ; une correction à chaud est reportée par MR dans l'heure.
- Redémarrage gracieux actif : une passerelle garde les routes d'un voisin perdu pendant `restartTimeSeconds` ; une panne « qui arrive deux minutes après un changement » est normale.

## Arbre de décision

1. **L'adresse est-elle attribuée ?** `kubectl get svc -A --field-selector spec.type=LoadBalancer` — `<pending>` :
   `kubectl get ciliumloadbalancerippool` (`DISABLED`, `CONFLICTING`, `IPS AVAILABLE`), `kubectl describe svc <svc>` (condition `io.cilium/lb-ipam-request-satisfied` et sa raison : `no_pool`, épuisement, sélecteur de Service). → Corriger le pool dans le dépôt.
2. **Des nœuds sont-ils sélectionnés ?** `kubectl get ciliumbgpnodeconfigs` (vide = aucun nœud) ; sélecteur de `kubectl get ciliumbgpclusterconfig bgp-par1 -o yaml` comparé à `kubectl get nodes --show-labels`. → Corriger le sélecteur (dépôt) ; les étiquettes des nœuds viennent d'Ansible (M14), ne pas les « adapter ».
3. **Les sessions sont-elles établies ?** `cilium bgp peers` (depuis `adm01`) : deux sessions `established` par nœud sélectionné. Sinon, sur la passerelle : `sudo vtysh -c 'show bgp summary'`, `sudo vtysh -c 'show bgp neighbors <IP-du-nœud>'` (« Last reset », « Notification sent/received »), `sudo journalctl -u frr --since -30min`.
   - *Bad Peer AS* : AS local de `bgp-par1` ≠ 65040, ou AS du voisin ≠ 65000.
   - Pas de SYN reçu (`sudo tcpdump -ni ens19.40 tcp port 179`) : pare-feu (`group_vars/role_routeur/pare_feu.yml`, règle « BGP des nœuds Kubernetes »), adresse du voisin.
   - Authentification (si TCP-MD5 est configuré) : compteurs `nstat -az | grep -i md5`.
4. **Les annonces sont-elles émises ?** `cilium bgp routes advertised ipv4 unicast` : une /32 par adresse `LoadBalancer`. Sinon : `kubectl get ciliumbgpadvertisements -o yaml` (`advertisementType: Service`, `addresses: [LoadBalancerIP]`, sélecteur de Services) et sélecteur d'annonces de `CiliumBGPPeerConfig bordure` (étiquettes des `CiliumBGPAdvertisement`). Avec `externalTrafficPolicy: Local`, un nœud sans backend prêt n'annonce pas : normal.
5. **Les routes sont-elles acceptées ?** Sur **chaque** passerelle : `sudo vtysh -c 'show bgp ipv4 unicast summary'` (`PfxRcd`), `sudo vtysh -c 'show ip prefix-list PL-DEPUIS-K8S'` (`seq 10 permit 10.10.41.0/24 le 32`), `sudo vtysh -c 'show route-map RM-K8S-IN'`. Pour voir ce qui arrive avant la politique, activer temporairement `soft-reconfiguration inbound` sur le groupe K8S **par Ansible**, puis `show bgp ipv4 unicast neighbors <IP> received-routes`, puis retirer.
6. **Les routes sont-elles installées ?** `ip -4 route show proto bgp | grep 10.10.41` sur les deux passerelles : une /32 par adresse, un prochain saut par nœud qui l'annonce. `ip route get 10.10.41.10` qui répond `blackhole` : plus aucune annonce, seule la route de rejet de M15-E25 subsiste.
7. **Dérive de configuration ?** `outils/derive-bordure-noeuds.sh --bordure` (plateforme/k8s), ou `diff <(sudo vtysh -c 'show running-config') /etc/frr/frr.conf` (en ignorant l'en-tête). Un écart = modification à chaud : retrouver qui (journal de `vtysh`, `last`), rejouer Ansible.

## Retour au nominal

- `cilium bgp peers` : toutes les sessions établies ; `nc -zv 10.10.41.10 443` depuis `adm01` ; routes présentes sur `gw01` **et** `gw02`.
- Clore : ticket, journal de diagnostic dans `docs/socle/journal/`, MR de correction liée.

## Historique

| Date | Incident | Cause | Ajout au runbook |
|---|---|---|---|
| 2026-10 | INC-4244 (M15-E38) | pool désactivé / annonces / sélecteur / AS / liste de préfixes sur la passerelle de secours | section « Diagnostic » |
