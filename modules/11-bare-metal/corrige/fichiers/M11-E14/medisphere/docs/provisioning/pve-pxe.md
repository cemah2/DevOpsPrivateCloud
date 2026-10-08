# Installer un nœud Proxmox VE par le réseau (PLAT-1231)

> Compte rendu de M11-E14. Fichier de réponse : `plateforme/provisioning`, `pve-answer/<hôte>.toml` ; service de réponse : rôle `pve_reponses` sur `pxe01` ; préparation : `outils/preparer-pve-pxe.sh`.

## Chaîne

```
bm04 (OVMF) ─TFTP─► ipxe.efi ─HTTPS─► boot.ipxe ─► mac-<mac>.ipxe (gabarit ipxe-pve)
     ─HTTPS─► /pve/9.2/vmlinuz + initrd.img (installateur complet, jeton, empreinte de pxe01)
     installateur ─POST HTTPS (Bearer <nom>:<secret>, empreinte épinglée)─► /pve/reponse
                    └─ pve-reponses : MAC trouvée dans le corps → bm04.toml
```

## Mesures (à remplir)

| Mesure | Valeur |
|---|---|
| Taille de l'ISO 9.2 / de l'initrd produit | <…> Mo / <…> Mo |
| Temps de chargement de l'initrd en HTTPS par iPXE | <…> s |
| Pic de mémoire de la VM pendant le chargement (`qm status 2115 --verbose`, `mem`) | <…> Gio |
| Temps total, de la mise sous tension au nœud joignable sur 8006 | <…> min |

Contrainte mémoire : l'initrd est chargé en mémoire **puis** décompressé et monté par l'installateur ; il faut plusieurs fois sa taille de mémoire libre. Avec 4 Go, le chargement échoue ou le noyau panique ; 8 Go donnent une marge confortable (à confirmer sur ton lab : note la valeur minimale qui a fonctionné).

## Où se trouve le jeton

En clair dans l'initrd (`/pve/9.2/initrd.img` sur `pxe01`, lisible par quiconque peut télécharger ce fichier) et dans `/etc/pve-reponses/jeton` (0640, compte de service). Conséquence : le jeton protège contre un client **sans** l'initrd, pas contre un client du VLAN 60 qui le télécharge. Mesures : initrd servi au seul VLAN 60 et à `adm01`, jeton propre au provisioning PVE (ne protège que des empreintes), rotation à chaque préparation.

## Renouvellement du certificat de `pxe01`

L'installateur épingle l'empreinte **du certificat** (`--cert-fingerprint`), qui change à chaque renouvellement ACME (tous les 20 jours environ, durée de vie 30 jours). Un initrd préparé avant un renouvellement refuse `pxe01` ensuite.

Procédure retenue : l'initrd est **préparé au moment de l'installation** (`outils/preparer-pve-pxe.sh`, quelques minutes), jamais conservé. Alternatives écartées : certificat dédié de longue durée pour `/pve/reponse` (contraire à la politique de certification), épingler la clé publique (non proposé par l'outil), servir la réponse en HTTP (fichier de réponse exposé sur le VLAN).

## Nettoyage

`bm04` recréée vide par OpenTofu (`tofu apply -replace=…`, mémoire 2 Go, disque d'origine, même MAC) ; NetBox : `bm04` à `planned` ; noyau et initrd de `/pve/9.2/` supprimés de `pxe01` (ils contiennent le jeton) ; jeton renouvelé dans le Vault.
