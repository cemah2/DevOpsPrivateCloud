# Revue de la MR !41 « Alloy : config simplifiée » (Lucas Martin) — M22-E11

**Relecteur** : <MOI> — **Avis** : refusée en l'état ; version corrigée sur cette branche (`alloy/revue-lucas/`).

Lucas, merci : la structure (découverte → relabel → fichiers → traitement → écriture) est la bonne, et
`alloy validate` passe. Mais `validate` ne vérifie que la **syntaxe** et les **types** : il ne sait
rien de notre Loki multi-locataire, de nos règles d'étiquettes ni des données de santé. Voici ce qui
bloque, du plus grave au moins grave.

| N° | Fichier (élément) | Défaut | Catégorie | Gravité | Ce qui se passerait chez nous | Correction |
|---|---|---|---|---|---|---|
| 1 | `config.alloy` (`loki.write`) | aucun locataire (`tenant_id`, `stage.tenant`) | fonctionnel | critique | Loki tourne en `auth_enabled: true` : chaque envoi est refusé (401, *no org id*) ; **rien** n'arrive, et l'agent réessaie en boucle | `tenant_id = "plateforme"` par défaut + `stage.tenant` d'après l'espace (mediagenda-*, medidoc-*, audit) |
| 2 | `config.alloy` (aucun masquage) | NIR, courriels, noms de patients envoyés tels quels | sécurité / conformité | critique | des données de santé dans Loki, le compartiment RGW et ses sauvegardes : violation de la politique HDS, effacement très coûteux | `loki.process "masquage"` en dernière étape (`stage.replace` NIR, courriels externes, champs nominatifs) |
| 3 | `config.alloy` (`basic_auth`) | mot de passe en clair dans un dépôt | sécurité | critique | le secret est dans l'historique Git pour toujours ; inutile en plus (Loki n'a pas d'authentification HTTP chez nous) | retirer ; si un jour il en faut un : fichier monté depuis un Secret (`password_file`), jamais dans Git |
| 4 | `config.alloy` (`labelmap` de toutes les étiquettes de pod) | recopie de toutes les étiquettes Kubernetes en étiquettes Loki | performance | élevée | `pod-template-hash`, `controller-revision-hash`… : un nouveau flux à chaque déploiement, des milliers de petits chunks, index qui gonfle, requêtes lentes (M22-E14) | liste fermée : `cluster`, `namespace`, `app`, `container`, `node`, `job` |
| 5 | `config.alloy` (`pod` en étiquette) | nom de pod indexé | performance | élevée | même effet : un flux par pod, donc par redémarrage | métadonnée structurée `pod` |
| 6 | `config.alloy` (`stage.labels` sur `route`, `code`, `level`) | champs de la ligne promus en étiquettes | performance | élevée | flux × routes × codes × niveaux ; `route` vaut aussi « non-routee » pour chaque URL inconnue | rien de tout cela en étiquette ; filtrer à la requête (`| json | code >= 500`) ou en métadonnée structurée |
| 7 | `config.alloy` (`stage.docker`) | mauvais format de journal | fonctionnel | élevée | nos nœuds utilisent containerd (format CRI) : l'analyse échoue, la ligne garde son préfixe `2026-… stdout F`, l'horodatage devient l'heure de lecture | `stage.cri { }` |
| 8 | `config.alloy` (`stage.json` sur toutes les lignes) | analyse JSON appliquée à des lignes texte ou logfmt | fonctionnel | moyenne | erreurs d'analyse et CPU gaspillé sur les journaux de Loki, Cilium, CoreDNS… | `stage.match` par application (sélecteur `{namespace=~"mediagenda-.+", container="api"}`) |
| 9 | `config.alloy` (aucun `stage.timestamp`) | horodatage de l'application ignoré | fonctionnel | moyenne | après un retard de lecture (agent redémarré), les lignes sont datées de leur lecture : l'enquête se trompe d'ordre | `stage.timestamp` sur `horodatage` (MédiAgenda), `time` (MédiDoc) |
| 10 | `config.alloy` (sondes non filtrées) | `/sante`, `/pret`, `/metrics` envoyées | coût | moyenne | en DEBUG (dev), des milliers de lignes inutiles par heure | `stage.drop` sur la route, compteur `reason="sonde"` |
| 11 | `config.alloy` (`discovery.kubernetes` sans sélecteur de nœud) | chaque pod du DaemonSet surveille TOUS les pods du cluster | performance | moyenne | six fois la charge de surveillance sur l'API ; des cibles dont les fichiers ne sont pas sur le nœud | `selectors { field = "spec.nodeName=" + sys.env("NODE_NAME") }` |
| 12 | `config.alloy` (`loki.source.journal`) | `max_age = "8760h"`, sans filtre de niveau, sans étiquettes | coût / fonctionnel | moyenne | au premier démarrage : un an de journal relu, refusé au-delà de 7 jours (`reject_old_samples`) et saturant la limite d'ingestion ; `debug` envoyé ; flux `job="loki.source.journal.noeud"` sans `node` | `max_age = "12h"`, `stage.drop` du niveau debug, `job`, `node`, `cluster`, unité et niveau en métadonnées structurées |
| 13 | `config.alloy` (`loki.source.kubernetes_events` dans un DaemonSet) | événements lus par chaque pod | fonctionnel | moyenne | six copies de chaque événement ; étiquette `instance` en plus | `clustering { enabled = true }` + clustering du chart ; retirer `instance` |
| 14 | `config.alloy` (URL `http://10.10.41.62:3100`) | adresse IP en dur, et l'entrée EXTERNE | exploitation | moyenne | le trafic sort par le Service LoadBalancer au lieu de rester dans le cluster ; la CNP doit l'autoriser ; l'adresse peut changer | `http://loki.journaux.svc.cluster.local:3100/loki/api/v1/push` |
| 15 | `config.alloy` (`filename` conservée) | étiquette ajoutée par `loki.source.file` | performance | faible | un flux par fichier de journal, donc par redémarrage de conteneur | `stage.label_drop { values = ["filename"] }` |
| 16 | `config.alloy` (`logging` en `debug`) | agent bavard | coût | faible | les journaux d'Alloy (dans Loki eux aussi) multipliés | `info` |
| 17 | `values.yaml` (`storagePath` par défaut, `/tmp`) | positions de lecture dans un `emptyDir` | fonctionnel | élevée | à chaque redémarrage du pod : relecture complète (doublons) ou trous | `storagePath: /var/lib/alloy/donnees` sur un `hostPath` |
| 18 | `values.yaml` (`content: ""`, « je colle ») | configuration hors de Git | exploitation | élevée | ce qui tourne n'est écrit nulle part ; Argo CD corrigerait la dérive… avec une configuration vide | ConfigMap `alloy-config` générée par kustomize depuis `alloy/config.alloy`, `configMap.create: false` |
| 19 | `values.yaml` (`tag: latest`) | version flottante | exploitation | moyenne | une montée de version non décidée au premier redémarrage d'un nœud | version du chart (v1.21.1), image par le cache Harbor |
| 20 | `values.yaml` (pas de tolérances) | pas d'agent sur les nœuds de contrôle ni sur `k8s-w03` | fonctionnel | moyenne | ni le journal d'audit (M22-E07) ni les journaux des pods de la base | tolérances `control-plane` et `dedie=bdd` |
| 21 | `values.yaml` (pas de ressources) | ni demande ni limite | disponibilité | moyenne | un agent qui s'emballe prend la mémoire des applications du nœud | demandes et limite de mémoire |
| 22 | `values.yaml` (RBAC par défaut) | l'agent lit tous les Secrets et ConfigMaps du cluster | sécurité | moyenne | un pod compromis de l'agent donne tous les secrets | règles minimales (`pods`, `namespaces`, `events`, `nodes`) |

**Ce que je garde de ta MR** : le chemin `/var/log/pods/*<uid>/<conteneur>/*.log`, l'idée de
`local.file_match`, et le réflexe `alloy validate` (qu'on met dans la CI).
**Pour la prochaine fois** : lis `docs/observabilite/journaux/politique-journaux.md` et l'en-tête de
`alloy/config.alloy` (liste fermée d'étiquettes, règle des locataires) avant d'écrire une ligne.
