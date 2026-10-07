# M06-E34 — Grille de relecture du chronométré (à remplir après coup, avec le corrigé)

| Exigence | Attendu | Obtenu | Geste manuel ? |
|---|---|---|---|
| 1 Machine | VM 2069 par OpenTofu, état séparé du socle, clone complet, étiquettes `env-m06`/`role-statut` | | |
| 2 Adresse | `netbox_available_ip_address` sur la plage statique INFRA ; aucune IP écrite à la main | | |
| 3 Nom | A + PTR par le même code ; `ad` sur les deux résolveurs | | |
| 4 Accès | clé d'hôte signée dès le premier passage ; aucun `accept-new` | | |
| 5 Service | nginx, 443 TLS 1.2+, 80 = défi ACME + redirection | | |
| 6 Certificat | ACME, renouvellement à 15 jours (drop-in) | | |
| 7 Filtrage | `pare_feu_local` ; **pas** de règle `gw01` (MGMT et VPN joignent déjà INFRA ; SANDBOX ne doit pas) | | |
| 8 Supervision | une ligne dans `etc/ms-verif-services.conf`, par MR | | |
| 9 Sauvegarde | aucune sauvegarde applicative (aucune donnée : tout est dans Git) ; la VM est dans `lab-nuit` par le pool, acceptable pour 2 h | | |
| 10 Traçabilité | 3 MR (infra, ansible, outils), pipelines verts | | |
| Retrait | `tofu destroy` de l'environnement, MR inverse dans `outils`, plus rien dans NetBox ni le DNS | | |

Repères de temps (apprenant entraîné, outillage du module en place) : T1 15 min, T2 35 min, T3 1 h 05, T4 1 h 20, T5 1 h 30. Au-delà de 2 h 30, l'outillage manque : identifie quoi.
