<!-- À INTÉGRER dans docs/socle/matrice-flux.md (plateforme/medisphere) : le fichier est GÉNÉRÉ depuis
     pare_feu.yml par ms-matrice-flux (M07-E30) ; cet extrait montre les lignes attendues après
     régénération. Numéros de ligne : ceux de ta matrice. -->
| Définition | Valeur | Commentaire |
|---|---|---|
| `NET_K8S_LB` | 10.10.41.0/24 | adresses de service de k8s-par1 (LB IPAM, annoncées en BGP, M15) |
| `GW_PAR1` | 10.10.41.10 | Gateway principale gw-par1 de k8s-par1 (M15-E12) |

| # | Entrée | Source | Sortie | Destination | Protocole | Motif | Réf. |
|---|---|---|---|---|---|---|---|
| … | $V_INFRA | $CA01 | $V_K8S | $GW_PAR1 | tcp 80 | défi ACME HTTP-01 de ca01 vers la Gateway gw-par1 (cert-manager) | M15-E13 |
