# Phase 4 — AxiomDev — Corrigé

> ⚠️ Corrigé — à lire après avoir cherché.

Fichiers : [`fichiers/S10/`](fichiers/S10/), [`fichiers/S11/`](fichiers/S11/), [`fichiers/S12/`](fichiers/S12/) (`equipes/` = `plateforme/equipes`, `identite/` = `plateforme/identite`, `politiques/` = `plateforme/politiques`, `rendu-attendu/` = ce que le générateur doit produire dans les dépôts cibles). La panne : [`pannes/break-S11.sh`](pannes/break-S11.sh).

**Validé hors du lab** : gabarit `prestataire.yaml.j2` rendu avec Jinja2 (mode strict) sur `ext-axiomdev.yaml` → [rendu attendu](fichiers/S10/rendu-attendu/k8s/equipes/ext-axiomdev/espaces/mediagenda-axiomdev.yaml), relu par `yaml.safe_load_all` ; extensions du format de S07 et S10 (schéma, `rendre.extrait`, gabarit) appliquées au générateur de S02 à l'harmonisation : `ext-axiomdev.yaml` valide, rendus de l'espace et de `gitlab-prestataires.d` identiques aux [rendus attendus](fichiers/S10/rendu-attendu/), tests de S02 toujours verts ; filtres `jq` des checks (liaisons RBAC hors espace, rôle limité, règles HBAC) rejoués sur des objets de test ; déroulé de la panne (injection, bascule de la variante 2 sur la 1 quand l'admission refuse, annulation qui ne retire que ce qu'elle a posé) rejoué avec des API simulées ; `gitlab-prestataire.sh`, `depart-externe.sh` et la panne propres à `shellcheck`.

**Points non testés en conditions réelles** :
- refus d'une liaison LDAP par Keycloak pour un principal expiré (comportement de `ipa-pwd-extop` depuis FreeIPA 4.0 ; à constater sur 4.13 avec une expiration mise au passé sur un compte d'essai) et lecture de `krbPrincipalExpiration` par le compte système `wb-checks` (ACI par défaut : si l'attribut n'est pas renvoyé, le check reste rouge — vérifie avec `ldapsearch` et, au besoin, une permission de lecture dédiée) ;
- prise en compte de l'expiration par SSSD pour une connexion SSH par certificat (sans Kerberos) : ici sans effet, puisque aucune règle HBAC ne laisse entrer AxiomDev ;
- `GET /users/:id/memberships` et `GET /personal_access_tokens?user_id=…` avec un jeton `read_api` d'administrateur sur GitLab 19.5 (le check S12 ignore la seconde si elle est refusée) ;
- variante 3 de la panne : délai avant que le nouveau groupe apparaisse dans les jetons (nouvelle connexion de la personne) et dans GitLab (prochain passage de `synchro:gitlab`).

---

### F2-S10 — Des accès bornés pour AxiomDev

**Solution de référence**

*1. AxiomDev dans l'équipe en code.* Le format de S02 donne déjà à un prestataire : personnes datées (`expiration`, reportée sur chaque personne et posée en `principalexpiration` par `annuaire:appliquer`), OTP (`otp_obligatoire: true` → groupe ajouté aux porteurs du rôle `second-facteur-obligatoire`), comptes GitLab externes. Il manque l'**hébergement** : une extension du format, relue comme un changement de sécurité.
- [`equipes/ext-axiomdev.yaml`](fichiers/S10/equipes/equipes/ext-axiomdev.yaml) : `type: prestataire`, date de fin, deux personnes en `@axiomdev.example`, contact interne Julien, `gitlab.groupe: ext-axiomdev` (groupe **propre**, vide de projets de MédiSphère), bloc `hebergement` ;
- [schéma](fichiers/S10/equipes/schema/equipe.schema.extrait-F2-S10.json), [générateur](fichiers/S10/equipes/outils/rendre.extrait-F2-S10.py) et ses [tests](fichiers/S10/equipes/tests/test_rendre.extrait-F2-S10.py) (contrôles : prestataire seulement, pas de locataire propre, espace `<hôte>-<nom court>`, aucun projet `plateforme/*`), [gabarit](fichiers/S10/equipes/gabarits/k8s/prestataire.yaml.j2) (espace `dev` **non protégé de l'élagage**, quota, LimitRange, `Role` `prestataire-developpeur`, liaison au seul groupe) ;
- rendus attendus : [espace](fichiers/S10/rendu-attendu/k8s/equipes/ext-axiomdev/espaces/mediagenda-axiomdev.yaml), [accès GitLab](fichiers/S10/rendu-attendu/identite/outils/gitlab-prestataires.d/equipes.yml) ;
- `CODEOWNERS` de `plateforme/equipes` : `equipes/ext-*.yaml @sophie.laurent` (approbation obligatoire si la règle de MR l'exige ; sinon, la relecture est écrite dans RB-320).

```
admin@adm01:~/src/equipes$ uv run outils/rendre.py --valider && uv run pytest -q
admin@adm01:~/src/equipes$ uv run outils/rendre.py && cat rendu/k8s/equipes/ext-axiomdev/espaces/mediagenda-axiomdev.yaml
```

*2. Identité.* Après propagation et application : `ipa user-show yanis.perrin --all | grep -i expiration` montre *Kerberos principal expiration* ; aucune règle HBAC ne cite le groupe (refus par défaut, `allow_all` désactivée au M24-E19) :

```
[admin@ipa01 ~]$ ipa hbactest --user=yanis.perrin --host=mon01.par1.medisphere.internal --service=sshd
--------------------
Access denied
--------------------
  Not matched rules: hbac-plateforme
  Not matched rules: hbac-support
```

Première connexion de chaque personne (fenêtre privée) : enrôlement OTP imposé, puis création de l'utilisateur GitLab par le SSO. OpenBao : `ext-axiomdev` n'est rendu ni dans `tofu/equipes.auto.tfvars.json` de `plateforme/secrets` (pas de bloc `kubernetes`), ni dans les groupes du M25 : aucune politique.

*3. GitLab.* Job [`gitlab:prestataires`](fichiers/S10/identite/gitlab-ci.extrait-F2-S10.yml) de `plateforme/identite` (après `synchro:gitlab`), qui appelle [`gitlab-prestataire.sh`](fichiers/S10/identite/outils/gitlab-prestataire.sh) : utilisateurs marqués **externes**, membres **directs** de `mediagenda/api` en Developer avec `expires_at`, contrôle qu'aucun autre groupe que le leur n'apparaît dans leurs appartenances. `main` de `mediagenda/api` : *Allowed to push* et *Allowed to merge* = Maintainers (réglage du projet, M01). Les variables CI ne sont visibles qu'aux Maintainers, et les variables **protégées** ne sont pas exposées aux pipelines des branches de fonctionnalité d'AxiomDev.

*4. Kubernetes.* L'espace est rendu dans `plateforme/k8s/equipes/ext-axiomdev/` et synchronisé par `equipes-k8s` ; ses étiquettes (`capsule.clastix.io/tenant: mediagenda`, `environnement`, `origine: plateforme-equipes`) le font rattacher au `Tenant` `mediagenda` (protégé depuis le M28) par le CronJob de S02. Vérification en administrateur, puis pour de vrai :

```
admin@adm01:~$ kubectl auth can-i --list -n mediagenda-axiomdev --as=oidc:yanis.perrin --as-group=oidc:ext-axiomdev
admin@adm01:~$ kubectl auth can-i get secrets -n mediagenda-axiomdev --as=oidc:yanis.perrin --as-group=oidc:ext-axiomdev
no
admin@adm01:~$ kubectl auth can-i list pods -n mediagenda-prod --as=oidc:yanis.perrin --as-group=oidc:ext-axiomdev
no
admin@adm01:~$ kubectl --context axiomdev-yanis -n mediagenda-axiomdev get pods          # contexte kubelogin de Yanis
admin@adm01:~$ kubectl --context axiomdev-yanis -n mediagenda-recette get pods
Error from server (Forbidden): pods is forbidden: User "oidc:yanis.perrin" cannot list resource "pods" … in the namespace "mediagenda-recette"
```

*5. Réseau.* Deux pairs WireGuard sur `wg1` (adresses réservées dans le VPN d'administration, clés dans le Vault `critique`), et des règles de transit dans `group_vars/role_routeur/pare_feu.yml` qui n'ouvrent depuis ces deux adresses que la VIP `lb` 10.10.70.200:443 (GitLab, SSO) et l'API Kubernetes 10.10.40.200:8443 (motif `SEC-3210`, référence `F2-S10`) ; reportées dans `docs/socle/matrice-flux.md`. Contrôle depuis un pair : `ssh` vers une VM ne passe même pas la bordure.

*6. Revue et procédure.* [`modele.yml`](fichiers/S10/identite/outils/revue-acces/modele.extrait-F2-S10.yml) (section `prestataires`), [`RB-329`](fichiers/S10/medisphere/docs/accueil/runbooks/RB-329-prestataires.md).

**Explications**
- **Expirer n'est pas désactiver.** `principalexpiration` ferme Kerberos et la liaison LDAP (donc Keycloak) à la date prévue, sans intervention ; `nsAccountLock` (départ, S12) est l'acte explicite. L'appartenance GitLab expire de son côté (`expires_at`), la liaison RBAC porte une annotation que la revue contrôle. Une seule date dans le fichier, propagée à tout ce qui sait expirer.
- **Pourquoi pas de groupe GitLab de MédiSphère.** Un membre d'un groupe hérite de **tous** ses projets, y compris ceux créés plus tard ; un utilisateur externe membre d'un groupe y voit ce que le groupe contient. Le groupe propre `ext-axiomdev` (créé par l'équipe en code) est vide de projets internes : il est inoffensif et la revue l'accepte nommément.
- **Pourquoi un `Role` et pas `edit`.** `edit` lit les Secrets de l'espace, permet `exec`/`attach` et la création de comptes de service (des jetons qui survivent au départ). Le rôle sur mesure donne ce qu'il faut pour déployer et déboguer (redirection de port comprise), rien de plus.
- **Pourquoi l'espace n'est pas protégé de l'élagage.** Les espaces des équipes internes portent `Prune=false,Delete=false` parce qu'ils contiennent des données ; celui d'un prestataire ne doit **rien** contenir qui survive au contrat : sa suppression par le code est le départ (S12).
- **Pourquoi l'hôte reste propriétaire.** `mediagenda-axiomdev` est dans le locataire `mediagenda` : Julien voit ce qu'y fait son prestataire, le budget du locataire le borne, la cloison réseau du locataire s'applique.

**Alternatives**
- Ne donner **aucun** accès au cluster : AxiomDev pousse ses branches, une Application Argo CD (projet `mediagenda`, source = branche de fonctionnalité) déploie dans `mediagenda-axiomdev` ; plus sûr, moins confortable pour déboguer.
- vCluster pour le prestataire (S03) : isolation plus forte (son propre plan de contrôle, ses CRD), coût mémoire, et un objet de plus à retirer.
- Comptes **locaux** Keycloak pour les prestataires (hors annuaire) : plus simple à créer, mais hors de la source de vérité, sans HBAC, et la revue doit lire deux endroits.

**Pièges classiques**
- Ajouter AxiomDev au groupe `mediagenda` de l'annuaire « pour aller plus vite » : il hérite d'Argo CD, de Grafana, de Capsule (lecture de la prod) et, par la synchronisation, du groupe GitLab `mediagenda` en Maintainer (variante 3 de S11).
- Oublier que l'utilisateur GitLab n'existe qu'après la **première connexion SSO** : le job de projets échoue (code 3) tant que la personne ne s'est pas connectée.
- `kubectl auth can-i` sans `--as-group` : le groupe n'est pas simulé, le résultat ment.
- Tester avec son propre compte : tout passe, rien n'est prouvé.
- Une date de fin écrite à trois endroits (annuaire, GitLab, contrat) : elles divergent à la première prolongation.

**En production chez MédiSphère**

Le contrat de prestation référence RB-329 (clauses de sécurité : postes gérés, second facteur, signalement d'incident, restitution) ; une prolongation est une MR approuvée par Julien et Sophie ; sept jours avant l'expiration, le responsable interne est prévenu ; les postes du prestataire passent par un bastion d'accès dédié (ou un portail Zero Trust) plutôt que par le VPN d'administration.

---

### F2-S11 — Panne : le prestataire voit trop de choses

**Démarche de diagnostic**

*Symptômes* : la revue d'accès (ou Marc lui-même) montre un écran hors périmètre : projets GitLab de `mediagenda` autres que `api`, objets de `mediagenda-prod` ou d'autres espaces, tableaux Grafana ou applications Argo CD de MédiAgenda.

*Hypothèses*, dans l'ordre du coût de vérification : (1) un droit GitLab hérité d'un groupe ; (2) une liaison RBAC (cluster ou espace) qui vise le groupe ou la personne ; (3) une appartenance à un groupe interne de l'annuaire, qui se répercute partout.

*Commandes, dans l'ordre*

```
admin@adm01:~$ for u in marc.vidal yanis.perrin; do
>   id=$(curl -s -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(cat ~/.config/workbook/gitlab-admin.token)") \
>        "https://git01.par1.medisphere.internal/api/v4/users?username=$u" | jq -r '.[0].id')
>   curl -s -K <(printf 'header = "PRIVATE-TOKEN: %s"\n' "$(cat ~/.config/workbook/gitlab-admin.token)") \
>        "https://git01.par1.medisphere.internal/api/v4/users/$id/memberships" | jq -r --arg u "$u" '.[] | [$u, .source_type, .source_name, .access_level] | @tsv'
> done
marc.vidal    Namespace  ext-axiomdev  40
marc.vidal    Namespace  MédiAgenda    30          ← v1
marc.vidal    Project    api           30
admin@adm01:~$ kubectl get clusterrolebindings,rolebindings -A -o json \
    | jq -r '.items[] | select(any(.subjects[]?; .name | test("ext-axiomdev|marc\\.vidal|yanis\\.perrin")))
             | [.kind, (.metadata.namespace // "-"), .metadata.name, .roleRef.name] | @tsv'
ClusterRoleBinding  -                    lecture-prestataires    view          ← v2
RoleBinding         mediagenda-axiomdev  prestataire-developpeur prestataire-developpeur
[admin@ipa01 ~]$ ipa user-show yanis.perrin | grep -i 'member of groups'
  Member of groups: ipausers, ext-axiomdev, mediagenda                        ← v3
```

Puis la **source** : qui a posé le droit et quand. GitLab : en édition communautaire, les événements d'audit de l'instance sont réduits ; le journal `api_json.log` de `git01` (`/var/log/gitlab/gitlab-rails/`) montre l'appel (`POST /api/v4/groups/…/members`), son heure et l'utilisateur du jeton ; Kubernetes : journal d'audit de l'API dans Loki (locataire `audit`, `{…} |= "lecture-prestataires"`, verbe `create`) et les annotations de l'objet (ticket, motif) ; annuaire : `ipa group-show mediagenda --all` et le journal d'accès de 389-ds (`/var/log/dirsrv/slapd-*/access` sur `ipa01`), comparés à `annuaire/groupes.yml` sur `main` (la dérive n'y est pas : elle a été faite **à la main**).

*Cause racine, par variante*

| Variante | Ce qui donne l'accès | Effet | Ce qui ne l'aurait pas corrigé seul |
|---|---|---|---|
| 1 | Marc et Yanis membres **Developer** du groupe GitLab `mediagenda` (sans expiration) | tous les projets du groupe par héritage : `mediagenda/deploiement` (overlays de prod, noms de secrets), le chart, les issues | `synchro:gitlab` ne gère que les personnes déclarées dans les tables : une appartenance posée à la main sur un groupe géré **est** retirée au prochain passage… si le groupe est cité dans la table et si le job tourne. À vérifier sur ton lab |
| 2 | ClusterRoleBinding `lecture-prestataires` : `view` à `oidc:ext-axiomdev` sur **tout** le cluster (annotée d'un faux ticket) | lecture de tous les objets de tous les espaces (prod comprise), sauf Secrets | rien : aucun outil ne gère cet objet ; Argo CD ne le connaît pas |
| 3 | `yanis.perrin` ajoutée au groupe **`mediagenda`** de l'annuaire, à la main | `oidc:mediagenda` → propriétaire Capsule en lecture de `mediagenda-*` (prod comprise), rôle Argo CD de l'équipe, Viewer Grafana ; Maintainer du groupe GitLab `mediagenda` au prochain `synchro:gitlab` | `annuaire:appliquer` (appartenances synchronisées) l'aurait retirée au prochain passage manuel ; entre-temps, chaque nouvelle connexion de Yanis porte le groupe |

*Correctif*
- v1 : retirer les deux appartenances du groupe (API `DELETE /groups/:id/members/:user_id` ou interface), vérifier qu'il ne reste que `ext-axiomdev` et le projet `api`.
- v2 : `kubectl delete clusterrolebinding lecture-prestataires` (objet hors de tout dépôt : l'écrire dans le journal) ; s'il venait d'un dépôt, le retirer par MR.
- v3 : relancer `annuaire:appliquer` (le code fait foi) ; puis fermer les sessions Keycloak de Yanis (ses jetons portent encore `mediagenda`) et relancer `synchro:gitlab` si elle était passée entre-temps.
- Dans tous les cas : dater l'exposition (première trace d'audit → correction), lister ce qui a pu être consulté (journaux d'accès GitLab, audit Kubernetes filtré sur `oidc:yanis.perrin`/`oidc:marc.vidal`), répondre à Sophie dans le journal, puis `lab/bin/break F2 11 --annuler` (qui ne défait que ce qui est encore exactement dans l'état injecté).

*Prévention*
- [`rbac-prestataires.yaml`](fichiers/S11/politiques/kyverno/validation/rbac-prestataires.yaml) (`plateforme/politiques`) : refuse toute liaison de cluster vers `oidc:ext-*`, toute liaison d'espace hors de `*-<société>`, et `admin`/`edit`/`cluster-admin`. Essai : `kubectl create clusterrolebinding essai --clusterrole=view --group=oidc:ext-axiomdev --dry-run=server` → refus.
- Revue d'accès : la section `prestataires` de `modele.yml` fait de toute ligne `ext-*` hors modèle un écart **bloquant** ; passage nocturne pour les seuls groupes `ext-*` (pour aller plus loin).
- `gitlab-prestataire.sh` échoue si une personne externe est membre d'un groupe autre que le sien ; `ms-verif-equipe ext-axiomdev` (S13) le signale chaque jour.
- RB-329 § « le prestataire voit trop ».

**Explications**
- Un droit « voir » se lit dans trois plans qui ne se parlent pas : GitLab (appartenances directes **et héritées**), Kubernetes (liaisons RBAC d'espace et de cluster), annuaire (groupes, recopiés dans chaque jeton OIDC et, par la synchronisation, dans GitLab). Partir de la personne (ce qu'elle **est** : groupes, appartenances, liaisons) est plus court que partir de chaque ressource.
- Les trois variantes sont des dérives **hors du code** : rien dans `plateforme/equipes` ne les a produites, donc rien ne les défait tant que l'outil qui gère la source n'est pas relancé (et la liaison de cluster n'a aucun outil). D'où la prévention en deux temps : l'admission rend la variante 2 impossible, la revue d'accès et `ms-verif-equipe` rendent les deux autres visibles le lendemain.
- Dater l'exposition fait partie du correctif : HDS et le contrat demandent de savoir ce qui a pu être consulté, et depuis quand.

**Alternatives**
- Synchroniser l'annuaire et les groupes GitLab **en continu** (passage planifié de `annuaire:appliquer` et `synchro:gitlab`) : une dérive à la main est effacée en quelques heures, sans attendre la revue ; au prix d'appliquer sans relecture ce qui est déjà relu.
- Interdire toute modification manuelle des groupes `ext-*` et `mediagenda` dans FreeIPA (permission retirée aux administrateurs du quotidien, compte de service seul) : plus robuste, mais un bris de glace en moins.
- Un vCluster ou un cluster dédié pour le prestataire (S03) : la variante 2 n'aurait rien ouvert sur la production, les variantes 1 et 3 restent possibles.

**Pièges classiques**
- Regarder les **membres du projet** `mediagenda/api` : l'héritage ne s'y voit qu'avec « membres hérités » ; la vue utile est celle des appartenances **de la personne**.
- Corriger l'annuaire et oublier les jetons déjà délivrés (et la synchronisation GitLab passée entre-temps).
- Supprimer la liaison et ne pas chercher **qui** l'a posée : la même personne la reposera.
- Retirer aussi le droit légitime (`prestataire-developpeur`, projet `api`) par excès de zèle : Julien perd une journée de son prestataire.

**En production chez MédiSphère**

La revue d'accès des groupes `ext-*` tourne chaque nuit et ouvre un ticket `SEC-` au premier écart ; les journaux d'audit de GitLab, de l'API Kubernetes et de Keycloak sont gardés un an dans le locataire `audit` de Loki, ce qui permet de dater une exposition ; toute exposition d'un prestataire est notifiée à son responsable interne et consignée au registre des incidents de sécurité, avec l'analyse de ce qui a pu être consulté.

---

### F2-S12 — Le départ d'AxiomDev

**Solution de référence**

1. *Par le code* — MR sur `equipes/ext-axiomdev.yaml` : `etat: retiree` (RB-320 § Départ), approuvée par Sophie. Propagation : personnes rendues `disabled` (désactivées, jamais supprimées), groupe vidé, OTP retiré, lignes GitLab retirées (`synchro:gitlab` retire les appartenances du groupe propre), rendu `gitlab-prestataires.d` sans AxiomDev, **espace non rendu → élagué par Argo CD** avec tout son contenu. MR sur `plateforme/identite` : section `prestataires.ext-axiomdev` retirée de `modele.yml` (le groupe reste dans `groupes_personnes`).
   ```
   admin@adm01:~$ kubectl -n argocd get application equipes-k8s -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
   admin@adm01:~$ kubectl get ns mediagenda-axiomdev
   Error from server (NotFound): namespaces "mediagenda-axiomdev" not found
   ```
2. *Ce que le code ne voit pas* — [`depart-externe.sh`](fichiers/S12/identite/outils/depart-externe.sh) (`plateforme/identite`), lancé après la propagation, en simulation puis pour de vrai :
   ```
   admin@adm01:~/src/identite$ set -a; . ~/.config/workbook/keycloak-tofu.env; set +a
   admin@adm01:~/src/identite$ GITLAB_TOKEN="$(cat ~/.config/workbook/gitlab-admin.token)" \
       outils/depart-externe.sh --simulation --projet mediagenda/api marc.vidal yanis.perrin
   admin@adm01:~/src/identite$ GITLAB_TOKEN="$(cat ~/.config/workbook/gitlab-admin.token)" \
       outils/depart-externe.sh --projet mediagenda/api marc.vidal yanis.perrin | tee /tmp/preuves-axiomdev.txt
   2026-…+02:00 | marc.vidal     | keycloak   | 1 session(s) fermées ; reste : 0
   2026-…+02:00 | marc.vidal     | gitlab     | jeton personnel 41 révoqué
   2026-…+02:00 | marc.vidal     | gitlab     | retirée de mediagenda/api
   2026-…+02:00 | marc.vidal     | gitlab     | compte bloqué (état : blocked)
   …
   ```
   Pairs WireGuard retirés (Vault `critique`, rôle `wireguard` sur les deux passerelles) ; heure du dernier certificat SSH émis à leur nom relevée dans le journal de step-ca (`ca01`).
3. *Preuve* — [`departs/axiomdev.md`](fichiers/S12/medisphere/docs/accueil/departs/axiomdev.md) : périmètre avant/après, chronologie réelle, sortie de l'outil, contrôle final par Karim (une heure après, RB-242), ce qui reste et pourquoi.

**Explications**
- Deux familles de gestes : ce que la **source de vérité** retire (annuaire, groupes, espace, droits rendus) et ce qui a été **délivré** avant (sessions, jetons de rafraîchissement, jetons personnels, clés, certificats). La première est un changement relu ; la seconde, un outil qui laisse une preuve.
- *Bloquer* un compte GitLab (et non le supprimer) garde l'attribution des MR et commits d'AxiomDev, coupe ses sessions et rend ses jetons inutilisables ; la révocation explicite des jetons est une ceinture en plus (un compte débloqué par erreur ne retrouverait pas ses jetons).
- Les certificats SSH déjà émis ne se révoquent pas sans KRL : ils sont inutilisables (compte verrouillé, aucune règle HBAC) et expirent en 16 h au plus ; c'est écrit dans la preuve plutôt que passé sous silence.

**Alternatives**
- Départ « en deux temps » : désactivation le dernier jour, suppression de l'espace une semaine plus tard après récupération de ce qui doit l'être (journaux d'essai) ; utile si le prestataire laisse des artefacts à relire.
- Laisser l'expiration faire le travail : elle ferme Kerberos, LDAP et GitLab (`expires_at`), mais ni les sessions ouvertes, ni les jetons personnels, ni l'espace : insuffisant seul.

**Pièges classiques**
- Supprimer les comptes : l'identifiant pourrait être réattribué, l'historique devient illisible.
- Oublier les **jetons personnels** GitLab : ils survivent à la désactivation dans l'annuaire (pas au blocage du compte, mais un compte peut être débloqué).
- Supprimer l'espace à la main alors que le rendu le contient encore : Argo CD le recrée.
- Un contrôle final fait par la même personne que l'exécution.

**En production chez MédiSphère**

Le départ d'un prestataire est déclenché par la fin du contrat dans l'outil des achats (ticket automatique à J-7), la preuve est jointe au dossier du contrat, et la revue d'accès du mois suivant confirme l'absence de toute ligne `ext-<société>` active.
