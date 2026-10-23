# Module 25 — Palier 5 : Mini-projet — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

**Points non testés en conditions réelles** : `check-E46.sh` n'a pas été rejoué sur un lab (ses fonctions communes sont celles des paliers 3 et 4) ; les noms d'espaces de la couche de base (`velero`, `ceph-csi`) sont ceux des corrigés du M16 : adapte si les tiens diffèrent ; la lecture des variables de CI par le jeton des checks dépend de son rôle dans les groupes (sinon le contrôle est « ignoré »).

### M25-E46 — Mini-projet : les secrets de MédiSphère v1

Il n'y a pas de solution unique : ce corrigé donne un **plan de travail** éprouvé, les points de contrôle de chaque étape, la préparation de la démonstration et la **grille de revue** de Claire, Karim, Sophie, Nadia et Julien. Fichiers : fiche de livraison [`secrets-v1.md`](fichiers/M25-E46/medisphere/docs/securite/secrets/secrets-v1.md), scénarios de [démonstration](fichiers/M25-E46/medisphere/docs/securite/secrets/demonstration-secrets-v1.md), forme finale de l'[inventaire](fichiers/M25-E46/medisphere/docs/securite/secrets/inventaire-secrets.md.extrait).

**Solution**

*Plan de travail recommandé* (on prouve d'abord, on nettoie ensuite, on documente à la fin)

1. **État des lieux** (1 h) : `lab/bin/check 25 46`, puis `lab/bin/check 25 43` (palier 4) ; restes : `ls ~/.local/state/workbook/pannes-actives/`, `pvesh get /cluster/resources --type vm | grep -E '225[12]'`, `kubectl get ns sealed-secrets essai-csi`, `tofu/essais-m25.tf`, jetons racine (liste des accesseurs, politique `root`) **sur la grappe et sur `kms01`**.
2. **Inventaire, ligne par ligne** (2 à 3 h) : pour chaque secret d'E02, l'état (fait / amorçage / reste), la preuve et la rotation. Trois sources croisées :
   ```
   admin@adm01:~$ kubectl get secrets -A -o json | jq -r '.items[]
       | select((.metadata.ownerReferences // []) | all(.kind != "ExternalSecret"))
       | select(.type != "kubernetes.io/service-account-token" and .type != "helm.sh/release.v1")
       | select((.metadata.labels // {}) | (has("cnpg.io/cluster") or has("controller.cert-manager.io/fao")) | not)
       | "\(.metadata.namespace)/\(.metadata.name) \(.type)"'
   admin@adm01:~$ for g in mediagenda medidoc plateforme; do glab api "groups/$g/variables" | jq -r --arg g "$g" '.[] | "\($g) \(.key) protégée=\(.protected)"'; done
   ```
   Ce qui sort de la première commande et n'est ni l'amorçage ni un objet de bibliothèque (cert-manager, CNPG, Helm) est un **reste** ; une variable de CI dont le nom évoque un mot de passe, un jeton ou une clé est un reste (sauf `OPENBAO_*`, sans valeur secrète).
3. **Couche de base** (2 h) : mêmes gestes qu'en M25-E13 pour Velero (`kv/plateforme/velero/s3`), les sauvegardes CNPG, ceph-csi (`kv/plateforme/ceph-csi/<client>`), la clé TSIG et le compte ACME (cert-manager, ExternalDNS) : valeur déposée dans `kv/` (entrée standard), politique `eso-plateforme` étendue chemin par chemin, ExternalSecret dans `plateforme/gitops` (ou dans le dépôt Helmfile, selon où vit la release), comparaison avant/après (`secret-vers-openbao.sh comparer`), retrait de la ligne de `secrets-k8s.conf`. Puis retrait de `secrets-k8s.sh` : la racine publique d'amorçage du runner est posée autrement (ConfigMap versionnée dans `plateforme/k8s`, ou option `tls-ca-file` du chart du runner) ; c'est un objet **public**, il n'a rien à faire dans un outil de secrets.
4. **Secrets courts et reprise** (1 h) : identifiants dynamiques en prod (fin d'E15), certificats de service, signature par `transit` ; dernier instantané < 2 h, RPO/RTO dans RB-252 ; essai quotidien de l'auto-descellement vert (E42) ; politique `kms-autodescellement` avec `renew-self`.
5. **Démonstration, répétition** (2 h) : les trois scénarios, chacun deux fois, **avant** le nettoyage.
6. **Nettoyage** (1 h) : pannes closes, VMs et espaces d'essai retirés, jetons racine révoqués (grappe et `kms01`), flux temporaires retirés, rien de manuel qui ne soit dans le code.
7. **Documentation et livraison** (2 h) : `secrets-v1.md`, ADR-0250/0251 relues, runbooks RB-250 à RB-255, matrice des flux, `tofu plan` vide, pipelines verts, étiquette `secrets-v1`.

*La démonstration de Sophie* (scénarios complets dans [`demonstration-secrets-v1.md`](fichiers/M25-E46/medisphere/docs/securite/secrets/demonstration-secrets-v1.md))

| Étape | Ce que tu fais | Ce que Sophie voit |
|---|---|---|
| 0 | boucle de requêtes lancée sur l'application concernée | des 200, une par seconde |
| 1 | nouvelle valeur à la source **puis** dans `kv/` (ou révocation du bail, ou secret tourné du client OIDC) | aucune valeur à l'écran |
| 2 | rafraîchissement ESO forcé, redémarrage en roulement par Reloader | la boucle reste verte |
| 3 | ancienne valeur retirée à la source, essai avec elle | refus |
| 4 | requête d'audit sur 7 jours | qui a lu, quand, d'où |
| 5 | entrée au journal (RB-250) | heure, geste, preuve |

*Grille de revue*

| Relecteur | Points | Attendu |
|---|---|---|
| Sophie | démonstration, inventaire, audit | rotation sans coupure ; inventaire sans valeur, chaque secret avec un état ; amorçages justifiés et gardés ; « qui a lu » en moins de 5 min |
| Karim | `plateforme/secrets`, `plateforme/ansible`, `plateforme/gitops` | `tofu plan` vide ; test des politiques en CI ; aucun joker sur `kv/` hors du dossier d'une équipe ; versions épinglées ; rien à la main |
| Nadia | astreinte | alertes chargées et routées (scellé, sans leader, audit, auto-descellement, certificats, instantanés) ; RB-251 et RB-255 utilisables à 3 h ; dépositaires joignables |
| Julien | équipes | aucune variable de CI secrète ; ses secrets de dev dans `kv/mediagenda/dev/` ; ses applications reçoivent leurs secrets sans ticket |
| Claire | ensemble | limites assumées et écrites (un `kms01`, un site, etcd, pas de contrôle à deux personnes, pas de SIEM) ; ce que consomment le M26 et les finaux |

**Explications**

Le contrôle global vérifie l'**état de livraison** ; il ne remplace ni les contrôles détaillés ni la démonstration. Les deux preuves que rien d'automatique ne donne sont celles que l'auditeur demandera : qu'un secret **réellement** exposé se tourne sans coupure, et qu'on sait dire **qui l'a lu**. L'inventaire, enfin, est le seul document qui dise ce qui n'est **pas** dans le coffre : sans lui, « tous nos secrets sont dans OpenBao » est une affirmation, pas un fait.

**Alternatives**

Démonstration sur la prod plutôt que sur la recette : plus convaincante, à réserver au scénario dynamique (le plus sûr, il est fait pour ça). Inventaire généré (script qui interroge le cluster, GitLab et `kv/metadata/`) plutôt qu'écrit : la bonne cible pour la revue trimestrielle, pas un prérequis de la v1.

**Pièges classiques**
- Démontrer après le nettoyage, et découvrir qu'une politique ou un rôle a disparu.
- Afficher une valeur pendant la démonstration (`bao kv get` sans `-field` vers un fichier).
- Retirer `secrets-k8s.sh` sans avoir migré la couche de base : le prochain cluster reconstruit (F1) n'a plus ses identités S3.
- Laisser un jeton racine de `kms01` vivant « pour la revue ».
- Oublier la politique `kms-autodescellement` sans `renew-self` : la grappe est verte le jour de la recette, et ne redémarre plus huit jours plus tard.
- Poser l'étiquette avant que les pipelines de `main` soient verts.

**En production chez MédiSphère**

`secrets-v1` devient la référence : toute nouvelle brique (M27, bloc G) arrive avec ses secrets dans le coffre, une identité, une politique testée en CI, une ligne d'inventaire et une rotation, sinon elle n'est pas en production. La revue trimestrielle de l'inventaire et la revue mensuelle des lectures de production entrent dans le rituel de Sophie ; le final F5 rejoue RB-252 et RB-255 de bout en bout, et F6 reprend l'audit pour la conformité.
