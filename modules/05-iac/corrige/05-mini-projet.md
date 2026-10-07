# Module 05 — Corrigé du palier 5 : Mini-projet

> ⚠️ Corrigé — à lire après avoir cherché.

---

### M05-E46 — Mini-projet : l'infrastructure MédiSphère déclarée

**Solution**

Il n'y a pas « une » solution : il y a un dépôt qui décrit le socle, une chaîne qui seule le fait évoluer, un état qu'on sait protéger et restaurer, et une équipe qui s'en sert sans toi. Les fichiers de référence sont répartis dans les exercices ; ce mini-projet les assemble et ajoute ce qui manquait.

| Élément | Où le trouver |
|---|---|
| Arborescence finale de `plateforme/infra`, exercice d'origine de chaque fichier, exigences de livraison | [`fichiers/M05-E46/recapitulatif-plateforme-infra.md`](fichiers/M05-E46/recapitulatif-plateforme-infra.md) |
| Projet, `.gitignore`, conventions | corrigé de M05-E02 (`fichiers/M05-E02/`) |
| Compte `wb-tofu`, jeton, rôle `WBTofu`, `pve-tofu.env` | M05-E03 (`fichiers/M05-E03/`) |
| `s3-01` (code OpenTofu), rôle Ansible `seaweedfs` et son scénario Molecule, certificat, identités S3 | M05-E10 (`fichiers/M05-E10/`) |
| Backend S3, verrou, test d'écriture conditionnelle | M05-E11, M05-E12 |
| Module `vm-debian`, publication par semantic-release, consommation par étiquette | M05-E13, M05-E14 |
| Import du socle, refactoring (`moved`, `removed`) | M05-E16, M05-E17 |
| Qualité, sécurité, pipeline, chiffrement, dérive, sauvegarde de l'état | M05-E20, E25, E26, E27, E28, E29 |
| Restauration d'une version d'état | [`fichiers/M05-E42/infra/outils/restaurer-etat.sh`](fichiers/M05-E42/infra/outils/restaurer-etat.sh) |
| **Nouveau** — runbook RB-051 « restaurer un état OpenTofu » | [`fichiers/M05-E46/docs/socle/runbooks/RB-051-restaurer-etat-opentofu.md`](fichiers/M05-E46/docs/socle/runbooks/RB-051-restaurer-etat-opentofu.md) |
| **Nouveau** — modèle de `docs/socle/iac.md` | [`fichiers/M05-E46/docs/socle/iac.md`](fichiers/M05-E46/docs/socle/iac.md) |

**Démarche recommandée** (10 à 14 h)

1. **Assainir d'abord** (1 h) : `lab/bin/check 05 46`, puis les contrôles de E35 à E42 (sondes de santé de la chaîne). KO typiques : une panne `M05` jamais close (`lab/bin/break 05 XX --annuler` après réparation), un fichier d'essai dans la copie de travail (`git status --ignored`), un objet `*.tflock` oublié, deux images `current` (ou aucune), un lock de provider modifié, des VMs 2050-2059 encore présentes.

2. **Faire le point sur le socle** (1 h). Pour chaque VM permanente : dans l'état ? à quelle adresse ? par quel code (module versionné ou ressource importée) ? plan vide ? Une table dans ton journal suffit. Pour `gw01`, relis ta décision de M05-E16 et écris-la si ce n'est pas fait : un ADR court (`ADR-0051`, par exemple) ou une section de `iac.md`. Les deux options sont défendables :
   - **hors IaC** : `gw01` est le cœur réseau, construit à la main au module 00, et sa configuration est gérée par Ansible (`pare_feu`) ; une erreur d'OpenTofu sur lui coupe tout le lab, y compris l'accès à `pve01` depuis `adm01`. Le risque accepté : sa définition matérielle (cartes, VLAN, mémoire) n'est décrite nulle part en code ; on la documente dans `inventaire.md` ;
   - **importé en lecture seule** : ressource importée avec `prevent_destroy`, protection Proxmox et `ignore_changes = all` (OpenTofu ne modifiera jamais rien), pour que l'état décrive **tout** le socle et que la dérive matérielle soit au moins visible (`plan -refresh-only`). Le risque : un `ignore_changes = all` qu'on retire un jour par mégarde.

3. **`ignore_changes` et protections** (1 h). Revue ligne à ligne : chaque attribut ignoré a un commentaire « pourquoi » et « ce qui le surveille à la place ». Grille :

   | Attribut ignoré | Acceptable ? | Raison |
   |---|---|---|
   | `clone` | oui | l'image `current` change chaque semaine ; le passage d'une VM à une nouvelle image est un `apply -replace` décidé |
   | `initialization` sur une VM importée | oui, commenté | le lecteur cloud-init d'origine n'est pas décrit par le code ; cloud-init ne rejoue pas sur une VM existante |
   | `disk` sur une VM importée | à éviter | une dérive de taille ou de stockage doit se voir ; préfère décrire les disques tels qu'ils sont |
   | `tags` | non | les étiquettes alimentent l'inventaire Ansible et les sources de données : une dérive doit se voir |
   | `all` | seulement `gw01` importé en lecture seule, ou une VM en cours de reprise | sinon, la VM n'est plus gérée que de nom |

4. **`s3-01` comme hôte du socle** (2 h). Vérifie la liste de l'ajout d'un hôte permanent (brief du bloc A, PLAN §4.5) : VMID 1006 et IP 10.10.20.14, étiquettes `socle` + `role-s3` (l'inventaire dynamique Ansible la voit dans `role_s3`), DNS A et PTR (rôle `dnsmasq`), alias SSH sur `adm01`, flux : MGMT → 8333 (règle MGMT existante), `runner01` → 8333 (même VLAN, rien à ouvrir), à reporter dans `matrice-flux.md` ; sauvegarde par `lab-nuit` (pool `lab`) **avec** le disque de données (`backup = true`) ; inventaire ; ordre de démarrage cohérent (après `dns01`, avant que la CI n'en ait besoin). Une sonde de santé documentée (le script d'écriture conditionnelle de M05-E12, lancé par la planification de dérive, par exemple).

5. **État** (2 h). Contrôle des quatre protections (verrou, chiffrement, versionnage, sauvegarde hors de `s3-01`) ; puis la **démonstration de restauration** : sur une clé d'essai (copie de `socle/terraform.tfstate` vers `_essais/socle-restauration.tfstate`, deux versions successives), ou sur la vraie clé du socle si tu acceptes un gel de quelques minutes. Nadia suit RB-051 seule ; tu notes chaque question qu'elle pose : chacune est un manque du runbook.

6. **Chaîne de livraison** (2 h). Points de revue du pipeline :
   - l'apply utilise **le** plan du pipeline (`tofu apply plan.bin`), jamais un nouveau plan ;
   - le plan est chiffré (bloc `plan` du chiffrement) : l'artefact peut être conservé ; le JSON en clair ne l'est jamais ;
   - le job de plan échoue sur une destruction de VM du socle (extrait dans le récapitulatif) ;
   - Trivy est épinglé par empreinte, Checkov par version ; chaque exception est justifiée ;
   - `resource_group` par état, `interruptible: false` sur l'apply ;
   - la planification de dérive est active, son dernier passage vert.

7. **Dérive : démonstration** (30 min). Exemple : `qm set 1006 --description "test dérive (INC-démo)"` sur `pve01`, annoncé dans le journal. La planification de la nuit (ou un lancement manuel de la planification) échoue avec le plan qui montre `~ description`. Décision : défaire (apply du code) ; trace dans le journal et le ticket.

8. **Documentation et revue** (2 h) : `iac.md` (modèle fourni, sections 8 et 9 remplies honnêtement), ADR-0050, RB-050, RB-051, inventaire, matrice des flux, registre des secrets (dont la copie de secours de la phrase de chiffrement et la procédure de rotation). Présentation : ce qui est en code, ce qui ne l'est pas et pourquoi, les risques restants (voir ci-dessous), ce que le module 06 change.

9. **Hygiène finale** : `tofu destroy` dans `envs/lab-m05` (plan relu : seules les VMs 2050-2059), toutes les pannes closes, copies de travail propres, `lab/bin/check 05 46` vert.

**Risques restants à présenter** (exemples)
- `s3-01` est un point unique : l'état de toute l'infrastructure et ses verrous en dépendent ; sa perte impose la restauration depuis la sauvegarde hors site (M05-E29). Réplication ou second stockage : module 08 (Ceph RGW).
- Le jeton `wb-tofu` peut toucher toutes les VMs du pool `lab` (pool unique, risque accepté dans ADR-0030) ; `prevent_destroy` et la protection Proxmox limitent les dégâts sur le socle.
- Les adresses, noms DNS et certificats ne sont pas encore pilotés par la source de vérité : module 06.

**Grille d'évaluation de la revue** (si tu travailles seul, note-toi honnêtement)

| Relecteur | Question | Attendu |
|---|---|---|
| Karim | « Montre-moi le chemin d'une modification de VM du socle. » | MR → plan en MR (lu) → fusion → apply manuel du plan sauvegardé → plan suivant vide |
| Karim | « Que se passe-t-il si on renomme le bloc de `s3-01` ? » | sans `moved` : destruction planifiée (prevent_destroy ne protège plus l'adresse orpheline), arrêtée par le contrôle du job de plan et la protection Proxmox ; avec `moved` : aucun changement |
| Sophie | « Où est la phrase de chiffrement, qui peut la lire, et si on la perd ? » | emplacements (fichier 600, variable CI protégée et masquée, copie de secours) ; perte = état illisible, reconstruction par imports ; rotation outillée |
| Sophie | « Que voit quelqu'un qui lit le compartiment ? » | enveloppes chiffrées, tailles, dates, noms de clés, verrous en clair |
| Nadia | (restauration avec RB-051) | réussie sans aide, plan vide, gel annoncé et levé |
| Nadia | « Le pipeline de dérive est rouge un matin : je fais quoi ? » | lire le plan, classer (adopter/défaire), ticket, jamais d'apply sans MR |

**Vérification** : `lab/bin/check 05 46`.

**Explications**

Le mini-projet vérifie moins une technique qu'une **propriété** : l'infrastructure réelle est celle que décrit le dépôt, et ce n'est pas un hasard du jour, c'est garanti par la chaîne (plan relu, apply protégé, dérive surveillée, état protégé). Les pannes du palier 4 ont montré par où cette propriété se casse : fichiers locaux, état manipulé, droits, réalité modifiée à la main, dépendances hors du dépôt.

**Alternatives**
- Un orchestrateur d'IaC auto-hébergeable (Atlantis, Terrakube) à la place des jobs GitLab : plans et verrous par MR, interface de revue. Pour un socle de cinq VMs et une seule équipe, le pipeline GitLab suffit ; à réexaminer quand plusieurs équipes auront leurs environnements (finaux F2).
- Un état par VM du socle (plutôt qu'un état `socle`) : rayon d'impact minimal, mais dépendances entre états plus lourdes (sorties, `terraform_remote_state`) ; Terragrunt (M05-E24) les rend gérables.

**Pièges classiques**
- Livrer avec un `ignore_changes = all` « temporaire » sur une VM du socle.
- Démontrer la restauration sur l'état du socle sans gel ni copie.
- Oublier que l'apply initial de `s3-01` s'est fait depuis `adm01` avant que le pipeline n'existe : à tracer, et à vérifier que le plan de la CI est vide depuis.
- Laisser des VMs 2050-2059 ou leur état non vide.

**En production chez MédiSphère**

Claire présente « l'infrastructure est en code » avec trois preuves : le rapport de dérive vide des 30 derniers jours, l'historique des apply (qui, quand, quel plan), et la dernière restauration d'état testée. Le module 06 branche NetBox comme source des adresses et PowerDNS par provider : les variables d'adresses de `terraform.tfvars` disparaissent, et le DNS de `s3-01` devient une ressource OpenTofu.
