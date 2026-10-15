<!-- À AJOUTER à docs/kubernetes/reseau/entree-du-cluster.md (version M15-E15) — M15-E20. -->
## Publication hors du lab (répartiteurs `lb01`/`lb02`)

```
LAN maison ─443─▶ VIP WAN (dnat) ─▶ VIP lb 10.10.70.200 ─ fe_tls_sni (lecture du SNI, sans déchiffrer)
                                         ├─ nom publié (k8s_noms_publies) ──TLS intact──▶ 10.10.41.10:443 (gw-par1)
                                         ├─ autre *.apps.par1…            ──▶ connexion refusée
                                         └─ autre nom ──PROXY v2──▶ fe_publication (TLS local : GitLab, NetBox)
```

- **Noms publiés dehors** : `k8s_noms_publies` de `group_vars/role_lb/haproxy.yml` (`plateforme/ansible`). Aujourd'hui : `mediagenda-recette.apps.par1.medisphere.internal`.
- **Publier un nouveau nom** : MR qui ajoute le nom à la liste (justification, accord de Sophie Laurent pour toute donnée de santé), pipeline (répartiteur de secours d'abord). Rien à changer dans le cluster.
- **Certificat vu dehors** : le joker `apps-joker` du cluster (TLS de bout en bout). Les clients extérieurs doivent faire confiance à la racine MédiSphère.
- **Limite** : l'application voit l'adresse de l'Envoy de la Gateway, qui voit celle du répartiteur (pas le client). Le protocole PROXY vers la Gateway (`gatewayAPI.enableProxyProtocol` de Cilium) imposerait PROXY à **tous** les clients de `gw-par1`, internes compris : écarté. Si l'adresse client devient nécessaire (journal d'accès HDS), terminer le TLS sur les répartiteurs pour ce nom (certificat dédié, ré-chiffrement vers la Gateway, `X-Forwarded-For`) : décision ADR-0150.
