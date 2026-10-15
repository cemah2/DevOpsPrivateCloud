# Accès des humains au cluster `k8s-par1`

> Dépôt `plateforme/medisphere`, `docs/kubernetes/acces-humains.md` — M14-E12 (ticket DEV-1512).
> Provisoire : remplacé par l'authentification OIDC (Keycloak) au module 24.

## Principe

- Chaque personne a une **identité nominative** : un certificat client X.509 signé par la CA du cluster.
  `CN` = identifiant (`prenom.nom`), `O` = groupe RBAC (un seul `O` par certificat).
- La **clé privée ne quitte jamais le poste** de la personne : elle envoie une demande (CSR PKCS#10),
  l'équipe Plateforme la signe par l'API `CertificateSigningRequest`
  (`signerName: kubernetes.io/kube-apiserver-client`).
- Les droits sont donnés **au groupe** (RoleBinding par espace, voir `plateforme/k8s/rbac/`).

| Groupe (`O`) | Qui | Durée du certificat | Droits |
|---|---|---|---|
| `medisphere:plateforme-admins` | équipe Plateforme | 7 jours (`outils/kubeconfig-personnel.sh`) | `cluster-admin` |
| `medisphere:mediagenda-devs` | équipe MédiAgenda | 7 jours | écriture dans `mediagenda-dev`, lecture dans `mediagenda-recette` |
| `medisphere:lecture` | support, audit | 7 jours | lecture de tout sauf les Secrets |

## Demander un accès (le demandeur)

1. Générer la clé et la demande sur son poste : clé EC P-256, `CN=<prenom.nom>`, `O=<groupe>`.
2. Envoyer **le seul fichier `.csr`** par le ticket (jamais la clé).

## Délivrer un accès (l'équipe Plateforme)

1. Vérifier que le ticket est validé par le responsable de l'équipe (Julien Petit pour MédiAgenda).
2. `outils/kubeconfig-csr.sh <fichier.csr> <prenom.nom> <groupe>` dans `plateforme/k8s` : contrôle du sujet
   (exactement `CN` et un `O` attendus), création du CSR, approbation, kubeconfig sans clé.
3. Remettre le kubeconfig ; le demandeur place sa clé `<prenom.nom>.key` (600) à côté.
4. Contrôle par le demandeur : `kubectl auth whoami`.

## Renouveler

Tous les 7 jours, nouvelle demande (la même clé peut resservir, mais on préfère une nouvelle clé par
renouvellement). Un rappel est envoyé par le ticket récurrent d'équipe.

## Retirer un accès : pas de révocation

Kubernetes **ne vérifie aucune liste de révocation** (ni CRL ni OCSP) pour les certificats clients.
Un certificat émis reste valable jusqu'à son expiration. En cas de départ ou de clé compromise :

1. **Couper les droits du groupe** si le certificat porte un groupe : RBAC n'a pas de règle « refuser »,
   on ne peut donc pas exclure **une** personne d'un groupe. On supprime la liaison du groupe et on
   redonne temporairement l'accès aux autres membres par des liaisons **nominatives** (`kind: User`),
   jusqu'à l'expiration du certificat compromis.
2. Si le certificat ne porte que des droits nominatifs : supprimer les liaisons de cet utilisateur.
3. **Attendre l'expiration** (7 jours au plus), puis revenir à la liaison de groupe.
4. En dernier recours (clé d'un administrateur, ou certificat du groupe `system:masters`) : **rotation de
   la CA du cluster** — procédure lourde, tous les certificats du cluster sont réémis.

C'est pourquoi les certificats humains sont **courts** (7 jours), qu'aucun humain n'a de certificat
`system:masters` (seul `super-admin.conf`, en coffre), et que le module 24 passe à OIDC
(jetons de quelques minutes, compte désactivé dans l'annuaire = accès coupé).
