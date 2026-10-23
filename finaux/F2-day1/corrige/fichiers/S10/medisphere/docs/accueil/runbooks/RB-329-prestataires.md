# RB-329 — Accueillir et faire partir un prestataire

*Propriétaire : équipe Plateforme. Relu par : Sophie Laurent (RSSI), Julien Petit. Version F2-S10 (SEC-3210), complétée en F2-S11 et F2-S12. S'appuie sur RB-241 (arrivée) et RB-242 (départ).*

## Principes

1. **Un prestataire est une équipe externe** : un groupe de l'annuaire préfixé `ext-` (`ext-axiomdev`), déclaré par un fichier de l'équipe en code (RB-320, `type: prestataire`) qui porte, en plus d'une équipe interne : la **date de fin de contrat** (`expiration`), le **contact interne** qui répond des accès, le **périmètre** (bloc `hebergement` : espace chez l'équipe hôte, rôle, projets GitLab) et le ticket du contrat.
2. **Tout est daté** : principal Kerberos (`principalexpiration`), appartenance GitLab (`expires_at`), liaison RBAC (annotation `medisphere.internal/expiration`, contrôlée par la revue). L'expiration ferme les portes même si le départ est oublié ; le départ (§ C) les verrouille et efface ce que l'expiration ne touche pas.
3. **Rien par héritage** : aucun groupe GitLab hors de son groupe propre (vide de projets MédiSphère), jamais un groupe interne de l'annuaire (`mediagenda`), jamais une liaison de cluster. Un droit de prestataire se lit en entier dans son fichier.
4. **Second facteur obligatoire** (rôle `second-facteur-obligatoire` du groupe dans Keycloak), **aucune règle HBAC** (SSH refusé sur toutes les machines inscrites), **aucun chemin OpenBao**.

## A. Arrivée (cible : une MR, une journée)

| # | Étape | Où | Contrôle |
|---|---|---|---|
| 1 | Fichier `equipes/ext-<société>.yaml` : `type: prestataire`, `expiration`, personnes, `otp_obligatoire: true`, `gitlab.externe: true`, bloc `hebergement` (locataire hôte, espace, quota, rôle, projets GitLab) ; MR relue par la Plateforme **et** Sophie | `plateforme/equipes` (RB-320) | pipeline vert, `apercu.diff` relu |
| 2 | Propagation : personnes datées et groupe (annuaire), OTP (Keycloak), groupe GitLab propre, espace + `Role` + liaison (`plateforme/k8s/equipes/`), accès aux projets (`outils/gitlab-prestataires.d/`) | dépôts cibles, Argo CD | `ipa user-show <ID> --all \| grep -i expiration` ; `kubectl get ns,role,rolebinding -n mediagenda-<société>` |
| 3 | Première connexion SSO de chaque personne, accompagnée (enrôlement OTP ; crée l'utilisateur GitLab) | navigateur | utilisateur visible dans GitLab |
| 4 | Job `gitlab:prestataires` (relancé après la première connexion) : externe, membre direct du projet, Developer, date d'expiration | `plateforme/identite` | `GET /users/:id/memberships` : le projet, le groupe propre, rien d'autre |
| 5 | Branche `main` du projet : poussée et fusion **Maintainer** ; variables CI protégées | réglages du projet (Julien) | `GET /projects/:id/protected_branches/main` |
| 6 | Contrôle des droits Kubernetes | `adm01` | `kubectl auth can-i --list -n mediagenda-axiomdev --as=oidc:yanis.perrin --as-group=oidc:ext-axiomdev` |
| 7 | Réseau : un pair WireGuard par personne sur le VPN d'administration, transit limité à la VIP `lb` 443 (GitLab, SSO) et à l'API Kubernetes 8443 | matrice des flux (`pare_feu.yml`), Vault `critique` | depuis le pair : `ssh` vers une VM refusé, GitLab joignable |
| 8 | Revue d'accès : périmètre ajouté à `modele.yml` (`prestataires:`) | `plateforme/identite/outils/revue-acces/` | revue suivante sans écart |

## B. Pendant le contrat

- Revue d'accès mensuelle (M24-E30) : toute ligne `ext-*` hors modèle est un **incident de sécurité** (SEC-), pas un écart à accepter.
- Prolongation : nouvelle date dans le fichier de l'équipe (une MR relue par Julien et Sophie), jamais une modification à la main.
- Politique d'admission `rbac-prestataires` (S11) : refuse toute liaison RBAC d'un groupe `oidc:ext-*` hors des espaces `*-<société>`.

## C. Départ (fin de contrat ou départ anticipé)

Ordre de RB-242 (départ planifié) appliqué au groupe entier ; preuve dans `docs/accueil/departs/<société>.md`.

1. MR sur le fichier de l'équipe : `etat: retiree` (RB-320 § Départ) — personnes désactivées, groupe vidé, OTP et appartenances GitLab du groupe propre retirés, accès aux projets retirés du rendu, **espace supprimé** par l'élagage d'Argo CD (l'espace d'un prestataire n'est pas protégé : rien n'y survit au contrat), périmètre retiré de `modele.yml`.
2. Après propagation : `outils/depart-externe.sh` (sessions Keycloak fermées, jetons personnels et clés SSH révoqués, appartenance au projet retirée, comptes GitLab **bloqués**) ; pairs WireGuard retirés.
3. Certificats SSH déjà émis : non révocables, 16 h au plus, inutilisables (compte verrouillé, aucune règle HBAC) ; heure du dernier émis notée dans la preuve.
4. Contrôle par une autre personne (RB-242, « Contrôle final ») et `lab/bin/check F2 12`.

## Diagnostic rapide « le prestataire voit trop »

`GET /users/:id/memberships` (groupes GitLab hérités), `kubectl get clusterrolebindings,rolebindings -A -o json | jq` (sujets `oidc:ext-*`), `ipa user-show <ID>` (groupes de l'annuaire), revue d'accès en essai (`REVUE_ESSAI=1`). Détail : corrigé de F2-S11.
