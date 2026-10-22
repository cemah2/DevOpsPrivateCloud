# Loki de k8s-par1 — fiche du service

> Créée en M22-E02 (PLAT-2302). Complétée par M22-E03 (collecte), E08 (ruler), E13 (rétentions).
> Décision d'architecture : ADR-0220 (M22-E17).

## En bref

| Élément | Valeur |
|---|---|
| Logiciel | Loki **3.7.9**, chart `grafana-community/loki` **19.0.3** recopié dans Harbor `charts/` |
| Déploiement | Application Argo CD `loki` (projet `plateforme`), dépôt `plateforme/observabilite`, dossier `loki/` |
| Mode | `Monolithic` : un seul binaire (`-target=all`), **1 réplica**, StatefulSet `loki` |
| Espace | `journaux` (Pod Security : `privileged` appliqué à cause d'Alloy, `restricted` en avertissement) |
| Stockage | compartiment **`loki-k8s-par1`** du RGW de `ceph-par1` (`https://rgw.par1.medisphere.internal`), utilisateur RGW `loki`, quota 50 Gio ; WAL et index en cours sur un PVC `ceph-rbd` de 20 Gio |
| Index | TSDB, schéma **v13** depuis le 2026-10-01, tables de 24 h, préfixe `loki_index_` |
| Locataires | `plateforme`, `mediagenda`, `medidoc`, `audit` (+ `essai` pour les comparaisons) ; en-tête `X-Scope-OrgID` obligatoire (`auth_enabled: true`) |
| Accès dans le cluster | `http://loki.journaux.svc.cluster.local:3100` (Alloy, Grafana, ruler) |
| Accès hors cluster | `http://loki.apps.par1.medisphere.internal:3100` = **10.10.41.62** (Service `loki-externe`, `externalTrafficPolicy: Local`) : écriture des VMs, lecture depuis MGMT |
| Politique réseau | CNP `journaux/loki-entree` (qui peut écrire, qui peut lire) |
| Secrets | Secret `loki-objstore` (hors Git : `plateforme/k8s/outils/secrets-k8s.sh`, composant `loki`, Vault `critique` `secrets/loki.yml`) ; `~/.config/workbook/s3-loki.env` (600) sur `adm01` |
| Grafana | sources `Loki — plateforme`, `Loki — mediagenda`, `Loki — medidoc`, `Loki — audit` (UID `loki-<locataire>`), ConfigMap `supervision/sources-loki` |
| Supervision | ServiceMonitor du chart (étiquette `medisphere.internal/supervision: "oui"`) |

## Commandes utiles

```
admin@adm01:~$ curl -s http://loki.apps.par1.medisphere.internal:3100/ready
admin@adm01:~$ curl -s http://loki.apps.par1.medisphere.internal:3100/loki/api/v1/status/buildinfo | jq .
admin@adm01:~$ curl -s -H 'X-Scope-OrgID: plateforme' 'http://loki.apps.par1.medisphere.internal:3100/loki/api/v1/labels?since=1h' | jq .
admin@adm01:~$ curl -s http://loki.apps.par1.medisphere.internal:3100/config | less        # configuration effective (secrets masqués)
admin@adm01:~$ kubectl --context k8s-par1 -n journaux logs sts/loki -c loki --since=15m
```

## Ce qu'il ne faut pas faire

- Écrire sans locataire, ou dans le locataire d'une autre équipe (l'en-tête n'est pas authentifié : M22-E16).
- Supprimer l'Application `loki` « pour la recréer » : l'Application n'a pas de finaliseur et l'espace porte `Prune=false`, mais le PVC du WAL contient les dernières minutes non encore envoyées.
- Désactiver la vérification TLS du RGW : la racine MédiSphère est montée (ConfigMap `racine-medisphere`).
