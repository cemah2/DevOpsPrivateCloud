# RB-213 — DisqueBientotPlein : un disque d'une VM sera plein dans moins de 24 h

**Alerte** : `DisqueBientotPlein` (avertissement ; équipe `plateforme`) · **Tableau** : [USE des nœuds](https://grafana.apps.par1.medisphere.internal/d/plateforme-use-noeuds?var-job=vms) · **Dernière vérification** : à la création (M21-E22)

## Que signifie cette alerte
Sur une VM du socle (job `vms`), un système de fichiers a moins de 25 % d'espace libre **et**, au
rythme des 6 dernières heures, sera plein avant 24 h. Condition vraie depuis une heure.

## Impact pour les utilisateurs
Aucun tant que le disque n'est pas plein. Plein : le service de la VM s'arrête ou corrompt ses
données (GitLab, Harbor, NetBox, base PostgreSQL…).

## Premières vérifications (5 minutes)
1. Quelle VM, quel point de montage, à quelle vitesse ?
   `deriv(node_filesystem_avail_bytes{job="vms", instance="<INSTANCE>"}[6h]) * 3600` (octets par heure, négatif = remplissage).
2. Sur la VM : `admin@<INSTANCE>:~$ df -h <POINT-DE-MONTAGE>` puis
   `sudo du -xh --max-depth=2 <POINT-DE-MONTAGE> | sort -h | tail -15`.
3. Qu'est-ce qui écrit ? journaux (`/var/log`, `journalctl --disk-usage`), sauvegardes locales,
   artefacts de CI (`git01`, `runner01`), couches d'images (`reg01`, `runner02`).

## Causes connues et actions
| Ce que tu observes | Cause probable | Action |
|---|---|---|
| `/var/log` ou le journal grossit vite | service en boucle d'erreurs | corriger la cause ; `sudo journalctl --vacuum-size=500M` |
| `/var/opt/gitlab` (git01) | artefacts et traces de CI, registre | expiration des artefacts (M19), `gitlab-rake gitlab:cleanup:…` aux heures ouvrées |
| `/data` (reg01) | images non nettoyées | politique de rétention et ramasse-miettes de Harbor (M13) |
| `/var/lib/docker` (runner02) | cache de construction | `docker builder prune` (sur `runner02` seulement) |

> ⚠️ **Attention** : ne supprime jamais un fichier que tu ne sais pas identifier, ni un fichier
> ouvert par une base de données. Agrandir le disque (OpenTofu, état `socle`, `disk.size`) est
> toujours possible et réversible côté données : préfère-le au nettoyage hasardeux.

## Escalade
Avertissement : traité aux heures ouvrées. Si moins de 4 h avant saturation (calcul ci-dessus) en
dehors des heures ouvrées : astreinte, puis Karim Benali pour un agrandissement.

## Retour à la normale
L'alerte se résout quand la prédiction ne passe plus sous zéro ; vérifie le lendemain que la pente
(`deriv`) est revenue à la normale.

## Après l'incident
Seuil et fenêtre de prédiction à revoir si l'alerte a sonné trop tard ; rétention du service
concerné inscrite dans son rôle Ansible.
