# Registre des allocations de stockage (ceph-par1)

> Propriétaire : équipe Plateforme · Source technique : `allocations.yaml` de `plateforme/ceph` (ce registre en est la lecture humaine, mise à jour dans la **même** MR) · Politique : `politique-stockage.md`.
> Une ligne par ressource. Les identifiants (clés cephx, clés S3) ne figurent jamais ici : leur **emplacement** est au registre des secrets.

## Équipes

| Équipe | Ressource | Emplacement | Plafond | Appliqué par | Identité | Sauvegarde | Ticket | Date |
|---|---|---|---|---|---|---|---|---|
| mediagenda | bloc | `rbd-equipes/mediagenda` (espace de noms) | 40 Gio provisionnés | contrôle nocturne `ceph-allocations verifier` (pas de quota natif par espace de noms) + quota du pool | `client.mediagenda` | images marquées `medisphere.sauvegarde=oui` | DEV-957 | 2026-10-XX |
| mediagenda | fichier | `cephfs`, groupe `mediagenda`, sous-volume `exports` | 10 Gio | quota CephFS du groupe (Ceph) | `client.mediagenda` | non (v1) | DEV-957 | 2026-10-XX |
| medidoc | bloc | `rbd-equipes/medidoc` | 20 Gio provisionnés | contrôle nocturne + quota du pool | `client.medidoc` | images marquées | DEV-957 | 2026-10-XX |
| medidoc | fichier | `cephfs`, groupe `medidoc`, sous-volume `archives` | 20 Gio | quota CephFS du groupe (Ceph) | `client.medidoc` | non (v1) | DEV-957 | 2026-10-XX |
| medidoc | objet | compte RGW `medidoc` | quota du compte (E12) | quota RGW (Ceph) | utilisateurs IAM du compte | hors périmètre v1 (ADR-0080) | PLAT-9xx (E12) | 2026-10-XX |

## Pools partagés

| Pool | Règle | Quota | Somme des plafonds qui l'utilisent | Marge |
|---|---|---|---|---|
| `rbd-equipes` | `ssd-baie` | 60 Gio | 60 Gio | 0 : relever le quota à chaque nouvelle équipe |

## Désigner une image pour la sauvegarde (équipes)

```
$ rbd image-meta set rbd-equipes/<équipe>/<image> medisphere.sauvegarde oui --id <équipe>
```
La sauvegarde de la nuit suivante la prend en compte (M08-E25). Retirer la métadonnée la retire des **sauvegardes suivantes** (les précédentes restent jusqu'à leur purge).
