# Final F1 — Phase 1 : Préparer — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché. Il existe d'autres solutions valables que celles-ci.

**Ce qui a été vérifié pour écrire ce corrigé** (bac à sable, octobre 2026) : `bash -n` et ShellCheck sur les scripts ; YAML des extraits de CI ; aucun élément n'a été rejoué sur un lab complet. Les points marqués « ⚠️ à vérifier sur ta version » dépendent d'un comportement d'outil non rejoué.

---

### F1-S01 — La carte d'amorçage de MédiSphère

**Solution de référence**

Modèle complet : [`fichiers/S01/medisphere/docs/day0/carte-amorcage.md`](fichiers/S01/medisphere/docs/day0/carte-amorcage.md). La démarche :

1. **Partir de l'utilisateur et remonter.** Un patient prend rendez-vous : MédiAgenda (pods) ← image (Harbor) ← Argo CD ← cluster (kubeadm) ← VMs (OpenTofu) ← Proxmox. En parallèle : nom (`*.apps` ← ExternalDNS ← PowerDNS), certificat (cert-manager ← step-ca), données (CNPG ← Ceph ← `s3-01` pour les archives), secrets (ESO ← OpenBao ← `kms01`), identité des humains (Keycloak ← FreeIPA). Chaque brique trouvée est remontée de la même façon jusqu'à `pve01`.
2. **Trois questions par brique** : où est son code, d'où viennent ses binaires ou images, qui lui donne ses secrets. Une réponse qui pointe vers une brique « plus haute » dans l'ordre est un cycle.
3. **Les durées** : reprends les chronométrages des modules (mini-projets, restaurations testées : CNPG au M16, etcd au M14, OpenBao au M25, usine au M11) et marque les estimations. Le total d'une reconstruction de `k8s-par1` seul tourne autour de 6 à 10 h selon la mémoire disponible et le nombre de gestes manuels ; S15 compare.

**Explications**

Une carte d'amorçage n'est pas un schéma d'architecture : elle répond à « que faut-il, et dans quel ordre, quand **rien** ne tourne ? ». L'architecture décrit des flux en régime établi ; la carte décrit une **séquence** et ses **préconditions vérifiables** (« prête quand… »). Les cycles sont normaux dans une plateforme qui s'héberge elle-même ; ce qui est dangereux, c'est de ne pas savoir où on les casse. Chaque cycle cassé l'est par une **voie de secours hors de la brique** : copie du code ailleurs, binaire hors ligne, identité locale, secret sur papier.

Les secrets hors du code sont la vraie racine de confiance : le code se clone, eux non. Leur valeur ne doit jamais être écrite, mais leur **existence**, leur **emplacement**, leurs **détenteurs** et leur **test** doivent l'être, sinon on les découvre perdus le jour où on en a besoin.

**Alternatives**
- Graphe généré : un script qui lit les `depends_on`/`needs` des pipelines et les inventaires produit un graphe à jour ; il ne voit pas les dépendances implicites (DNS, PKI, secrets), qui restent à écrire.
- Carte par niveaux (L0 matériel, L1 réseau, L2 services socle…) au lieu d'une liste ordonnée : plus lisible, moins précise sur le chemin critique.

**Pièges classiques**
- Oublier les dépendances **implicites** : tout dépend du DNS et de la PKI, même si aucun code ne le dit.
- Écrire « restaurer GitLab » sans dire **avec quoi** (sauvegarde, outil, clé de chiffrement de la sauvegarde) ni **depuis où** si GitLab porte le code de sa propre restauration.
- Recopier une valeur « pour être sûr » (une empreinte, un identifiant de jeton) : un identifiant n'est pas un secret, mais un document qui en contient attire les copies.
- Des durées sans source, toutes rondes : S15 les rendra ridicules.

**En production chez MédiSphère**
La carte est revue à chaque nouvelle brique (critère de fin de projet), testée une fois par an par une reconstruction réelle (ce final, puis F5), et ses secrets hors du code sont inventoriés chaque trimestre par Sophie avec preuve de lisibilité (sans ouverture des scellés pour les parts Shamir).

**Grille de relecture**

| Critère | Attendu |
|---|---|
| Complétude | socle, `ceph-par1`, `k8s-par1`, plateforme, données, applications ; `pxe01` |
| Ordre | chaque brique a ses dépendances, son outil, sa preuve « prête » |
| Cycles | au moins forge, registre, coffre/Ansible, `kms01`, ESO/méthode `k8s-par1`, identité, sauvegardes ; chacun cassé par un moyen qui marche aujourd'hui |
| Secrets | emplacement, détenteurs, vérification, conséquence de la perte ; aucune valeur |
| Durées | sourcées, total, chemin critique |

---

### F1-S02 — Chasse à la dérive

**Solution de référence**

*1. Détection, couche par couche (rien n'est appliqué)*

```
admin@adm01:~/src/infra$ . outils/charger-acces.sh
admin@adm01:~/src/infra$ outils/derive.sh -r ~/f1/s02/rapports socle envs/k8s envs/ceph envs/provisioning registre; echo "code $?"
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --check --diff | tee ~/f1/s02/ansible.txt
admin@adm01:~/src/k8s$ helmfile -e par1 diff --detailed-exitcode --suppress-secrets --context 3 --diff-args "--three-way-merge"; echo "code $?"
admin@adm01:~$ kubectl -n argocd get applications.argoproj.io -o custom-columns=NOM:.metadata.name,SYNC:.status.sync.status,SANTE:.status.health.status | grep -v 'Synced *Healthy'
admin@adm01:~/src/identite$ tofu -chdir=tofu plan -detailed-exitcode -lock-timeout=10m; echo "code $?"
admin@adm01:~/src/identite$ uv run ansible-playbook annuaire/annuaire.yml --check --diff
admin@adm01:~/src/secrets$ tofu -chdir=tofu plan -detailed-exitcode -lock-timeout=10m; echo "code $?"
admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/netbox.yml --list > ~/f1/s02/netbox.json
admin@adm01:~/src/ansible$ uv run ansible-inventory -i inventories/lab/proxmox.yml --list > ~/f1/s02/proxmox.json
```

(Les noms des fichiers d'inventaire et de `site.yml` sont ceux des corrigés du M04 et du M06 : garde les tiens.) Pour `identite` et `secrets`, depuis `adm01`, les accès s'obtiennent comme aux M24 et M25 (bris de glace documenté, ou jeton personnel) ; le reste se fait par la CI.

⚠️ `--diff-args` de `helmfile diff` et le comportement de `--three-way-merge` avec Helm 4 en *server-side apply* : à vérifier sur ta version (`helmfile diff --help`, notes du M17). helm-diff 3.15 documente `--three-way-merge` (ou `HELM_DIFF_THREE_WAY_MERGE=true` dans l'environnement du job) et `--three-way-merge-mode` (`auto`, `server`, `client`) ; le mode `server` est le plus fidèle mais demande le droit `patch` (dry-run côté serveur). Le principe ne change pas : sans comparaison à l'état réel, une modification faite par `kubectl` sur un champ que le chart fixe reste invisible.

*2. Décisions.* Une ligne par écart dans le compte rendu (modèle : [`derive-AAAA-MM-JJ.md`](fichiers/S02/medisphere/docs/day0/derive-AAAA-MM-JJ.md)). Règle de décision : **corrigé** quand l'écart est un accident ou un essai oublié ; **codifié** quand la réalité est meilleure que le code et que quelqu'un l'assume par écrit (raison, date). Dans le doute, corrigé : c'est le code qui est relu.

*3. Reproductibilité* : extraits [`identite`](fichiers/S02/identite/gitlab-ci.derive.extrait.yml), [`secrets`](fichiers/S02/secrets/gitlab-ci.derive.extrait.yml) (plan dans un pipeline planifié et à la demande, job `derive:*` qui échoue si le plan n'est pas vide), [`infra`](fichiers/S02/infra/gitlab-ci.derive-k8s.extrait.yml) (jobs `derive:k8s`, `derive:ceph`, `derive:provisioning`, `derive:registre` au modèle `.derive` du M05-E28). Le `helmfile diff` planifié du M17 reçoit `--three-way-merge` ; la cohérence NetBox/Proxmox entre dans le pipeline planifié de `plateforme/ansible`.

*4. Contrôle* : `lab/bin/check F1 2`.

**Explications**

Le M05 a posé la distinction qui structure tout : **dérive** = la réalité a bougé sans le code (`plan -refresh-only` non vide) ; **écart de code** = le code a bougé sans apply (plan ordinaire non vide, refresh vide). Le premier se corrige souvent en revenant au code ; le second en appliquant (ou en annulant la MR). Chaque couche a son outil parce que chaque outil ne voit que ce qu'il gère : OpenTofu ne voit pas un fichier modifié dans une VM, Ansible ne voit pas la mémoire d'une VM, Helm ne voit pas un objet qu'il ne possède pas.

Pourquoi planifier : une détection faite une fois avant la fenêtre ne dit rien du lendemain. Les états `identite` et `secrets` n'avaient de plan qu'à la poussée : une modification dans la console de Keycloak pouvait vivre des mois. Le job `derive:*` séparé du plan garde le plan « vert » quand il réussit à calculer, et rend visible (rouge) un plan non vide dans un pipeline planifié, sans jamais appliquer.

**Alternatives**
- Pour Keycloak, un export du royaume comparé à un export de référence : il voit aussi ce que le fournisseur OpenTofu ne gère pas (ce qui n'est pas dans le code ne fait jamais dériver un plan).
- Pour la couche de base, la confier à Argo CD (auto-réparation) : supprime la dérive à la source, mais crée un cycle (Argo CD se gère lui-même) qu'il faut casser à l'amorçage.
- `driftctl` (archivé) ou les outils de dérive des plateformes commerciales : hors périmètre.

**Pièges classiques**
- Lancer un `plan` sans verrou (`-lock=false`) pour aller vite : il peut lire un état en cours d'écriture.
- Conclure qu'Ansible est conforme alors que le `--check` a sauté des tâches (`when` sur des faits non collectés, tâches `command` sans `check_mode`).
- « Codifier » une valeur sans raison écrite : on fige un accident.
- Corriger la réalité à la main (« je remets la valeur ») au lieu de rejouer le code : la dérive suivante viendra du même geste.
- Oublier les états des environnements de modules détruits : un état vide doit le rester.

**En production chez MédiSphère**
Détection nocturne sur chaque couche, ticket `derive` unique alimenté par tous les rapports, revue hebdomadaire ; une dérive ouverte plus de deux jours ouvrés est escaladée. Les consoles d'administration (Proxmox, Keycloak, Harbor, NetBox) passent en lecture pour les humains, l'écriture étant réservée aux comptes d'automatisation, sauf bris de glace tracé.

---

### F1-S03 — Panne : les mains de quelqu'un sont passées par là

**Démarche de diagnostic**

*Symptômes.* Karim : « le diff n'est pas vide quelque part », « un doute sur `lb02` ». Aucun service n'est dégradé. C'est un problème de **conformité**, pas de disponibilité : la démarche est un balayage systématique, pas une poursuite d'indices.

*Hypothèses.* Une modification à la main sur n'importe quelle couche : VM Proxmox, fichier d'une VM, objet du cluster, objet d'un service (Keycloak, OpenBao, Harbor). Le « doute sur `lb02` » oriente, mais ne limite pas : la panne injecte **trois** dérives, une par couche (VM Proxmox de `lb02`, un fichier sur `lb02` **ou** `dns02`, un Deployment de la couche de base).

*Commandes, dans l'ordre* (les outils de S02) :

```
admin@adm01:~/src/infra$ outils/derive.sh -r ~/f1/s03 socle; echo "code $?"; cat ~/f1/s03/derive.md
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/repartiteurs.yml --check --diff --limit lb02
admin@adm01:~/src/ansible$ uv run ansible-playbook playbooks/site.yml --check --diff --limit 'lb02,dns02'
admin@adm01:~/src/k8s$ helmfile -e par1 diff --detailed-exitcode --context 3 --diff-args "--three-way-merge"
root@pve01:~# qm config 1011
```

*Cause racine, par couche et par variante.*

| Couche | Variante | Ce que montre l'outil | Cause |
|---|---|---|---|
| Proxmox (`lb02`, 1011) | 1 | `derive.sh` : dérive sur `module.repartiteur["lb02"]…vm`, attribut `on_boot` | démarrage automatique coupé à la main (`onboot: 0`) : au prochain redémarrage de `pve01`, `lb02` ne revient pas, et personne ne le voit tant que `lb01` tient |
| | 2 | dérive, attribut `tags` | étiquette `essai-charge` ajoutée : elle entre dans l'inventaire et les sources de données (un groupe `essai_charge` apparaît) |
| | 3 | dérive, attribut `protection` | protection posée : bloquera la reconstruction de S05 (« VM is protected ») au pire moment |
| Fichier | 1 (`lb02`) | `--check --diff` du rôle `haproxy` sur `lb02` : `timeout client` | valeur changée à la main dans `/etc/haproxy/haproxy.cfg` puis rechargée |
| | 2 (`dns02`) | `--check --diff` de chrony (rôle `base`) sur `dns02` | source NTP publique ajoutée dans `/etc/chrony/chrony.conf` : écart à la politique de temps (une seule source, la passerelle) |
| Cluster | 1 | `helmfile diff` **avec** comparaison à l'état réel : `cert-manager` | limite mémoire du Deployment `cert-manager` changée par `kubectl set resources` |
| | 2 | idem : `external-dns` | limite mémoire du Deployment `external-dns` changée |

Le piège de la troisième couche : un `helmfile diff` sans comparaison à l'état réel est **vide** (il compare le manifeste de la dernière release au nouveau rendu, pas à l'objet vivant). Argo CD ne voit rien non plus : la couche de base n'est pas sous Argo CD (M20).

*Correctif.* Par le code, couche par couche :
- Proxmox : `apply` de l'état `socle` par le pipeline (le plan ramène `on_boot`, `tags` ou `protection` à la valeur du code). Pour `protection`, l'apply remet `false` ; si tu décides de **codifier** la protection (elle a du sens pour une VM du socle), le module `vm-debian` n'a pas de variable pour elle : c'est une MR sur `plateforme/tofu-modules`, puis S05 devra la lever par le code avant de détruire.
- Fichier : rejouer le playbook (pipeline de `plateforme/ansible`) sur la VM concernée. Si la valeur à la main était meilleure (un `timeout client` de 5 s ne l'est pas : il coupe les clients lents et les connexions inactives, interfaces web et téléchargements compris), on la codifie dans les variables du groupe.
- Cluster : `helmfile -e par1 -l composant=<cert-manager|external-dns> apply --diff-args "--three-way-merge"` par la voie habituelle (job de `plateforme/k8s`), puis `helmfile diff` (avec comparaison à l'état réel) vide. Sans `--three-way-merge`, `apply` calcule un diff **vide** et saute la release : rien n'est corrigé (`helmfile -e par1 -l … sync` force la mise à niveau). Avec Helm 4 en *server-side apply*, le champ modifié par `kubectl set resources` appartient désormais au gestionnaire `kubectl-set` : la mise à niveau peut échouer sur un **conflit** de propriété ; Helm ne l'écrase qu'avec `--force-conflicts` (désactivé par défaut, HIP-0023), à passer explicitement et à tracer. ⚠️ À vérifier sur ta version.

*Prévention.* Le diff planifié de Helmfile doit comparer à l'état réel (S02) ; les droits d'écriture des humains sur la couche de base passent par le bris de glace ; l'interface Proxmox en lecture seule pour le compte personnel hors astreinte ; un journal d'astreinte qui exige de reporter toute action manuelle dans un ticket.

**Explications**

Trois couches, trois façons d'être invisible : une option de VM se voit seulement dans un plan qui **rafraîchit** l'état ; un fichier se voit seulement dans le `--diff` du rôle qui le **gère** (un fichier qu'aucun rôle ne gère ne se voit jamais, c'était l'autre leçon du M29-E22) ; un objet de la couche de base se voit seulement si on compare à l'**objet vivant**. La conclusion de l'incident est donc aussi une conclusion sur la détection : si un contrôle de S02 n'a rien vu, il est incomplet.

**Pièges classiques**
- S'arrêter à `lb02` parce que le ticket le cite.
- « Réparer » à la main (`qm set --onboot 1`, `vi haproxy.cfg`, `kubectl edit`) : la dérive disparaît, mais rien ne prouve que le code et la réalité concordent ; et le geste se répétera.
- Lancer `--annuler` au lieu de réparer : il remet l'état d'avant la panne, pas la compréhension. Et si tu as **codifié** une valeur injectée (la protection de `lb02`, par exemple), ne lance pas `--annuler` : il remet la valeur d'origine de tout élément resté dans l'état injecté, ce qui recréerait une dérive. Dans ce cas, le check de S03 attend aussi la nouvelle valeur : pose `WB_F1_LB02_ETIQUETTES` / `WB_F1_LB02_ONBOOT` en conséquence (la protection, elle, est toujours contrôlée absente : la codifier est un choix que le check signale en rouge, à justifier dans le compte rendu).
- Oublier d'écrire l'incident dans le compte rendu : c'est la preuve que la détection a (ou n'a pas) fonctionné.

**En production chez MédiSphère**
Toute modification hors du code est un incident de conformité (INC) avec post-mortem court ; le journal des tâches Proxmox, le `journald` des VMs (Alloy → Loki) et le journal d'audit de l'API Kubernetes (locataire `audit`) permettent de retrouver l'auteur et l'heure : on s'en sert pour comprendre le besoin qui a poussé au geste, pas pour chercher un coupable.

---

### F1-S04 — Le filet : sauvegardes prouvées, go/no-go et retour arrière

**Solution de référence**

*1. Sauvegardes de la veille* (dans l'après-midi qui précède le go de 18 h, pour que les preuves aient moins de 24 h au moment du go ; si le go glisse, on les refait) :

```
root@pve01:~# vzdump 2141 2142 2143 2144 2145 2146 --storage <STOCKAGE-PBS-K8S> --mode snapshot
admin@adm01:~$ velero backup create f1-avant-chg3107 --wait
admin@adm01:~$ kubectl cnpg backup -n mediagenda-prod mediagenda-db --method plugin --plugin-name barman-cloud.cloudnative-pg.io
admin@adm01:~$ kubectl -n messagerie create job --from=cronjob/export-definitions export-definitions-chg3107
admin@adm01:~$ kubectl -n argocd create job --from=cronjob/argocd-export argocd-export-chg3107
```

- `<STOCKAGE-PBS-K8S>` : le stockage PBS de `pve01` qui écrit dans l'espace `par1/k8s` (M14). La tâche nocturne couvre déjà les six VMs ; la sauvegarde à la main ne sert qu'à rapprocher la preuve de la fenêtre.
- Sauvegardes CNPG de `mediagenda-db` (recette) et `portail-db` (espace `portail`) de la même façon. Sans le plugin `kubectl cnpg`, un objet `Backup` (`spec.cluster.name`, `spec.method: plugin`, `spec.pluginConfiguration.name: barman-cloud.cloudnative-pg.io`) dans l'espace du cluster fait la même chose. ⚠️ Champs à vérifier sur ta version de CNPG et du plugin (M16, M27).
- `velero backup create` sans `--include-namespaces` sauvegarde tous les espaces : c'est ce qu'on appelle ici « complète ».

*2. Lisibilité.*

```
root@pve01:~# qmrestore <STOCKAGE-PBS-K8S>:backup/vm/2141/<HORODATAGE> 5311 --storage local-nvme --unique 1 --pool lab
root@pve01:~# qm set 5311 --name f1-resto-cp01 --tags env-f1 --onboot 0 --net0 "$(qm config 5311 | sed -n 's/^net0: //p'),link_down=1"
root@pve01:~# qm start 5311 && qm terminal 5311        # jusqu'à l'invite de connexion, puis Ctrl+O
root@pve01:~# qm stop 5311 && qm destroy 5311 --purge
```

`--unique 1` régénère la MAC et les identifiants ; `link_down=1` débranche la carte : la VM restaurée démarre sans jamais parler au VLAN 40 (même adresse IP que `k8s-cp01`, et un etcd qui chercherait ses pairs). Chronomètre la restauration : c'est le chiffre du retour arrière. À défaut, un *verify* PBS de l'espace `par1/k8s` (interface PBS ou `proxmox-backup-manager verify ds-lab --ns par1/k8s` sur `pbs01`, ⚠️ options à vérifier sur ta version) prouve l'intégrité des morceaux, pas que la VM démarre.

etcd : télécharger le dernier instantané horaire de `etcd-k8s-par1`, le déchiffrer avec la clé `age` (hors ligne), `etcdutl snapshot status` (RB-141 §3), puis **effacer** les copies locales. CNPG : `kubectl get clusters.postgresql.cnpg.io -n mediagenda-prod mediagenda-db -o jsonpath='{.status.lastArchivedWALTime}'` et le catalogue de l'objet de stockage (`barman-cloud-backup-list`, ou l'état du plugin) : la sauvegarde de base et le WAL jusqu'à maintenant.

*3. Photographie* : [`photographie-donnees.sh`](fichiers/S04/k8s/outils/photographie-donnees.sh) (lecture seule, comptes et noms), complétée à la main : modèle [`reference-avant.md`](fichiers/S04/medisphere/docs/day0/reference-avant.md). Pendant la fenêtre, `10-gel.sh` (S07) ajoute à ce document une section **« Gel »** (compteurs au moment du gel et écart expliqué avec la photographie de la veille) : c'est elle que S11 compare aux données remises, en rejouant le même script.

*4. Retour arrière* : [`retour-arriere.md`](fichiers/S04/medisphere/docs/day0/retour-arriere.md). *5. Fiche* : [`CHG-3104-filet-et-go.md`](fichiers/S04/medisphere/docs/day0/changements/CHG-3104-filet-et-go.md).

*6. Contrôle juste avant le go* : `lab/bin/check F1 4`, puis les critères G1 à G11 de la fiche.

**Explications**

Le filet a deux usages qu'il ne faut pas confondre. **PBS** sert au **retour arrière** : remettre l'ancien cluster tel qu'il était, avec son etcd et ses nœuds, si la reconstruction échoue. Il ne sert **pas** à la reconstruction : restaurer des disques, ce n'est pas prouver que le code reconstruit. **etcd, Velero, CNPG, RabbitMQ, Argo CD** servent aux deux : ils contiennent ce que le code ne contient pas (données, état d'objets créés à l'exécution).

Une sauvegarde « prouvée » réunit trois preuves : elle a **réussi** (statut), elle est **récente** (date), elle est **lisible** (restauration ou vérification). La troisième manque presque toujours : c'est celle qui fait défaut le jour de l'incident.

Les critères de go/no-go se décident **avant** la fenêtre, à froid. Pendant la fenêtre, la pression pousse à requalifier un rouge en « orange acceptable ». Un critère mesurable et une règle (« un rouge = no-go ») protègent de soi-même.

**Alternatives**
- Retour arrière par instantanés Proxmox des six VMs au lieu de PBS : plus rapide (secondes), mais sur le même stockage que les VMs (`local-nvme`), et un instantané d'un nœud etcd n'est cohérent qu'avec ceux des deux autres pris en même temps, VM éteinte de préférence.
- Pas de retour arrière, seulement « en avant » : défendable si la reconstruction a déjà été répétée sur un autre cluster ; ici, c'est la première fois.

**Pièges classiques**
- Restaurer une VM de test avec la même MAC et la carte branchée : conflit d'adresse avec le nœud en service, et un etcd qui tente de rejoindre ses pairs.
- Une sauvegarde CNPG `completed` sans WAL archivé depuis : on ne revient qu'à l'heure de la sauvegarde.
- Oublier les messages en file : les définitions RabbitMQ ne contiennent pas les messages.
- Une photographie qui contient des données de patients (un `SELECT *` « pour vérifier ») : interdit, et inutile.
- Des preuves de l'avant-veille parce que la fenêtre a glissé d'un jour.

**En production chez MédiSphère**
Le filet est un modèle de fiche CHG réutilisé pour tout changement majeur (F4) ; la restauration de test d'un nœud est mensuelle et chronométrée (tableau de bord des restaurations) ; le go/no-go se tient en réunion courte avec Claire, Karim, Nadia et Julien, critère par critère, et la décision est consignée dans la fiche avec l'heure.
