# RB-242 — Départ et mobilité d'une personne

*Propriétaire : équipe Plateforme. Relu par : Sophie Laurent (RSSI), Nadia Roussel (support). Version M24-E23 (SEC-2523). Revue : à chaque nouveau service branché, après chaque usage en départ immédiat, et au moins une fois par an.*

## Principes

1. **L'annuaire d'abord** : une personne désactivée dans FreeIPA ne peut plus ouvrir **aucune nouvelle** session (Keycloak vérifie le mot de passe par liaison LDAP à chaque connexion ; SSSD vérifie le verrou du compte à chaque connexion SSH).
2. **Puis tout ce qui a été délivré avant** : sessions SSO et jetons de rafraîchissement (Keycloak), jetons personnels, clés et sessions ouvertes, droits locaux. Rien de cela ne disparaît avec la désactivation.
3. **Désactiver, jamais supprimer** : l'identifiant reste réservé, les journaux gardent un sens.
4. **Chaque étape laisse une preuve**, consignée dans le ticket.

## Valeurs à adapter

| Valeur | Signification |
|---|---|
| `<IDENTIFIANT>` | identifiant de l'annuaire (`prenom.nom`) |
| `<TICKET>` | ticket RH ou de sécurité qui déclenche la procédure |
| `<HEURE-T0>` | heure de l'appel (départ immédiat) : tous les temps cibles en partent |

## Préparer les accès (une fois par session de travail, depuis `adm01`)

```
admin@adm01:~$ ID=<IDENTIFIANT>
admin@adm01:~$ . ~/.config/workbook/keycloak-tofu.env     # svc-tofu-keycloak : manage-users du royaume medisphere
admin@adm01:~$ KC=https://sso.par1.medisphere.internal
admin@adm01:~$ jeton_kc() { curl -s -K <(printf 'user = "%s:%s"\n' "$KEYCLOAK_CLIENT_ID" "$KEYCLOAK_CLIENT_SECRET") \
>   -d grant_type=client_credentials "$KC/realms/master/protocol/openid-connect/token" | jq -r .access_token; }
```

Jetons d'administration des services : lus dans le Vault `critique` au moment de servir, passés à `curl` par `-K <(…)`, jamais sur la ligne de commande ni dans l'historique.

---

## A. Départ immédiat (licenciement, compte compromis) — cible : tout coupé en moins de 60 minutes

Ordre : d'abord ce qui empêche **toute nouvelle** entrée, puis ce qui donne le plus de pouvoir **sans** passer par le SSO, puis le reste.

| # | Cible | Étape | Commande ou écran | Contrôle (preuve au ticket) |
|---|---|---|---|---|
| 1 | T0 + 3 min | **Verrouiller dans l'annuaire, à la main** (seule exception admise au « tout en code », régularisée à l'étape 9) | `[admin@ipa01 ~]$ kinit admin && ipa user-disable <IDENTIFIANT> && kdestroy` | `ipa user-show <IDENTIFIANT>` : *Account disabled: True* |
| 2 | T0 + 6 min | **Fermer toutes les sessions Keycloak** : les jetons de rafraîchissement de kubelogin, Argo CD, Grafana, OAuth2 Proxy, Harbor deviennent inutilisables | `admin@adm01:~$ U=$(curl -s -K <(printf 'header = "Authorization: Bearer %s"\n' "$(jeton_kc)") "$KC/admin/realms/medisphere/users?username=$ID&exact=true" \| jq -r '.[0].id')` puis `curl -s -o /dev/null -w '%{http_code}\n' -X POST -K <(printf 'header = "Authorization: Bearer %s"\n' "$(jeton_kc)") "$KC/admin/realms/medisphere/users/$U/logout"` (ou console : *Users* → la personne → *Sessions* → *Sign out*) | `204` ; *Sessions* vide |
| 3 | T0 + 15 min | **GitLab** (accès au code, aux pipelines, aux variables) : bloquer le compte (coupe ses sessions et ses jetons), puis révoquer jetons personnels et clés SSH | API GitLab avec un jeton d'administration : `POST /users/:id/block` ; `GET /personal_access_tokens?user_id=:id` puis `DELETE /personal_access_tokens/:id` ; `GET /users/:id/keys` puis `DELETE /users/:id/keys/:key_id` | état `blocked`, aucune clé, aucun jeton actif |
| 4 | T0 + 25 min | **Jetons qui contournent le SSO** sur les autres services | Proxmox VE : `pveum user token list $ID@medisphere`, `pveum user token remove …`, `pveum user modify $ID@medisphere --enable 0` ; PBS : `proxmox-backup-manager user update $ID@medisphere --enable false` ; NetBox : jetons de l'utilisateur (`/api/users/tokens/?user_id=…`, `DELETE`), utilisateur `is_active: false` ; Harbor : supprimer l'utilisateur (son secret CLI disparaît avec lui), inventorier les robots qu'il connaissait ; Grafana : `POST /api/admin/users/:id/logout` puis `…/disable` | chaque liste vide ; capture des réponses (sans valeur de jeton) |
| 5 | T0 + 35 min | **Sessions SSH ouvertes et caches** | `admin@adm01:~/src/ansible$ uv run ansible 'socle:k8s_par1:!role_routeur' -b -m ansible.builtin.command -a "loginctl terminate-user $ID"` (échec normal là où elle n'est pas connectée) ; puis `-a "sss_cache -u $ID"` | `loginctl list-users` sans elle ; `ssh` refusé (voir contrôle final) |
| 6 | T0 + 40 min | **Argo CD, Kubernetes** : rien à révoquer individuellement (aucun compte local de personne, aucune liaison nominative) ; les jetons OIDC déjà délivrés expirent en 5 min au plus et ne se rafraîchissent plus (étape 2) | `kubectl get clusterrolebindings,rolebindings -A -o json \| jq '[.items[].subjects[]? \| select(.kind=="User" and (.name\|test("'"$ID"'")))] \| length'` | `0` |
| 7 | T0 + 45 min | **Certificats SSH** déjà émis : non révocables, ils expirent en 16 h au plus et ne servent plus à rien (compte verrouillé, étape 1). Certificats d'astreinte `admin` connus d'elle (si elle avait accès à `ms-ssh-cert`) : changer le mot de passe du provisioner `admin` (RB-244) | — | heure d'expiration du dernier certificat émis pour elle (journal de step-ca) |
| 8 | T0 + 55 min | **Secrets qu'elle connaissait** (si membre de `plateforme-admins` ou `securite`) : ouvrir le ticket de rotation RB-244 (mots de passe des Vaults, `kc-secours`, `root` GitLab, `admin` de l'annuaire, `root@pam`, secrets des clients Keycloak) ; priorité au coffre de bris de glace | — | ticket de rotation lié |
| 9 | T0 + 60 min | **Régulariser dans le code** : MR sur `plateforme/identite` (`etat: disabled` dans `personnes.yml`, retrait de **tous** les groupes dans `groupes.yml`), fusion, `annuaire:appliquer` | GitLab | job vert, second passage sans changement |

Si une étape échoue : passer à la suivante (elles sont indépendantes après l'étape 1), noter l'échec au ticket, revenir dessus. Si l'étape 1 échoue (annuaire injoignable) : étapes 2 à 5 d'abord, puis désactiver la personne **dans Keycloak** (*Users* → *Enabled* off, possible même pour une personne fédérée) en attendant l'annuaire.

## B. Départ normal (planifié)

À J-1 au plus tard : MR qui passe la personne à `etat: disabled` et la retire de ses groupes, fusionnée et appliquée **le dernier jour à l'heure de départ** ; puis étapes A.2 à A.8 dans le même ordre, sans contrainte de minutes. Avant : transfert de ce qu'elle possède (projets GitLab personnels utiles, robots Harbor, tableaux de bord Grafana, jetons de déploiement créés par elle).

## C. Mobilité (changement d'équipe)

1. MR sur `annuaire/groupes.yml` : **retirer** des anciens groupes et ajouter aux nouveaux **dans la même MR** (jamais d'ajout seul : on cumulerait les droits), validée par les deux responsables ; application.
2. Fermer ses sessions Keycloak (A.2) : les jetons en cours portent encore les **anciens** groupes jusqu'à leur expiration ou leur rafraîchissement.
3. Lancer le pipeline `synchro-gitlab` (appartenances GitLab), `sss_cache -u <IDENTIFIANT>` sur les machines (sudo et HBAC), ACL PBS par personne à revoir (M24-E15), groupe NetBox local.
4. Jetons personnels créés pour l'ancien rôle : révoqués (A.3, A.4).
5. Contrôle : `kubectl auth can-i --list --as=oidc:<IDENTIFIANT> --as-group=oidc:<NOUVEAU-GROUPE>` et `outils/matrice-droits-oidc.sh`.

## Perte du second facteur

Personne présente, identité vérifiée de visu par un membre de `plateforme-admins` : console d'administration → *Users* → la personne → *Credentials* → supprimer l'OTP ; à sa prochaine connexion, le flux lui impose un nouvel enrôlement. Consigner au ticket.

## Contrôle final (une heure après, par une autre personne que celle qui a exécuté)

| Contrôle | Commande | Attendu |
|---|---|---|
| Annuaire | `ipa user-show <IDENTIFIANT>` (lecture) | désactivée, aucun groupe |
| Keycloak | *Users* → *Sessions* ; essai de connexion avec un mot de passe quelconque dans une fenêtre privée | aucune session ; « Account is disabled » ou échec d'identifiants |
| SSH | `ssh -o BatchMode=yes <IDENTIFIANT>@mon01.par1.medisphere.internal true` depuis `adm01` | refus |
| Jetons | listes GitLab, Proxmox, NetBox, Grafana | vides |
| Journaux | Loki, locataire `audit` : `{service="keycloak"} \|= "<IDENTIFIANT>"` sur les 2 dernières heures ; journal d'audit de l'API Kubernetes : `\|= "oidc:<IDENTIFIANT>"` | aucune connexion **réussie** après T0 + 6 min |

## Preuves conservées

Ticket complété (heures réelles de chaque étape, sorties des contrôles sans aucune valeur de secret), MR de régularisation, requêtes Loki et leur résultat (export), ticket de rotation RB-244 lié. Délai réel reporté dans la revue d'accès mensuelle (M24-E30).
