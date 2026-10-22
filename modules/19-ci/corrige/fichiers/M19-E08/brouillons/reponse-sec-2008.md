# Réponse au ticket SEC-2008 — le démon BuildKit partagé

> Brouillon de `~/m19/e08/` (non versionné), exemple de réponse. Matière de l'ADR-0190 (M19-E30).

## Ce qui a changé

Avant : chaque job de construction de `runner02` lançait **son** BuildKit, avec seccomp et AppArmor
non confinés (ADR-0120), dans un conteneur jetable. Après : les jobs de `k8s-par1` ne sont que des
**clients** (`buildctl`) d'**un** démon BuildKit *rootless* (`buildkit/buildkitd`), qui porte seul
l'exception de sécurité. Le nombre de conteneurs « non confinés » passe de « un par construction »
à **un**, dans un espace qui ne contient rien d'autre.

## Qui peut parler au démon

| Barrière | Ce qu'elle empêche |
|---|---|
| CiliumNetworkPolicy `buildkitd` (entrée) | tout pod qui n'est pas un pod de job (`medisphere.internal/ci: job`) de `ci-jobs` (et `ci-jobs-protege` au M19-E24) : un pod de `wb-essais` ou d'une équipe ne joint pas le port 1234 |
| TLS mutuel (`[grpc.tls] ca`) | un client sans certificat signé par `buildkit-ca` : la poignée de main échoue avant tout appel gRPC |
| Autorité `buildkit-ca` dédiée | sa clé privée reste dans l'espace `cert-manager` ; seuls les administrateurs du cluster la lisent |
| Certificat client par espace | il n'existe que dans `ci-jobs` ; le compte des jobs (`ci-job`) ne peut pas lire de Secret, le Secret est monté par le runner |

**Ce qui reste** : toute personne qui peut créer un objet `Certificate` désignant la ClusterIssuer
`buildkit-ca` obtient un certificat client valide (aujourd'hui : les administrateurs du cluster ;
à surveiller si une équipe obtient un jour des droits sur les objets de cert-manager — la politique
d'approbation de cert-manager, *approver-policy*, permettrait de restreindre l'usage de l'émetteur).
Et **tout job** de `ci-jobs` (donc tout projet qui a le droit d'utiliser le runner `k8s-par1`) peut
envoyer un Dockerfile au démon.

## Un `RUN` malveillant

Un Dockerfile peut exécuter n'importe quoi dans un `RUN`. Ce qui le contient :
- *rootless* : les `RUN` tournent dans l'espace de noms utilisateur du démon (UID 1000 sur le nœud),
  sans capacité réelle sur le nœud ; aucun volume de l'hôte n'est monté dans le pod ;
- réseau : un `RUN` sort avec l'identité réseau du pod `buildkitd`, donc vers Harbor et Internet en
  443 seulement ; ni le lab, ni l'API Kubernetes, ni les autres pods ;
- pas de bac à sable de processus (`noProcessSandbox`) : un `RUN` **voit les processus du démon**
  et ceux des autres constructions en cours, et peut leur envoyer des signaux (même UID). Il peut donc
  perturber une construction concurrente (la tuer), lire ses arguments de ligne de commande.
  C'est le prix du mode *rootless* sans privilège dans un pod ; il est accepté parce que les projets
  qui construisent sont internes et relus (MR), et que le démon est redémarrable sans perte.

## Un cache empoisonné

- **Cache local du démon** : partagé entre tous les projets. BuildKit l'indexe par **contenu**
  (empreinte des entrées de chaque étape) : un projet ne peut pas « remplacer » la couche d'un autre
  sans produire exactement les mêmes entrées. Le risque réel est l'abus de ressources (remplir le
  disque : ramasse-miettes à 20 Go) et, avec `noProcessSandbox`, l'interférence décrite plus haut.
- **Cache en registre** (`plateforme/cache-buildkit:<projet>`) : un dépôt par projet, **écrit
  seulement par les pipelines protégés** (robot `cache-buildkit`, variables protégées). Une branche de
  stagiaire ne peut pas y écrire. Limite : le robot a les droits de **tout** le projet Harbor
  `plateforme` ; un projet Harbor dédié au cache la supprimerait (à faire si l'ADR-0190 le retient).
- L'image publiée n'est jamais prise dans le cache telle quelle : elle est construite, **analysée par
  Trivy**, signée par empreinte (M13-E09) ; un cache empoisonné se verrait au pire comme une
  vulnérabilité ou une différence de SBOM, et la provenance SLSA dit quel pipeline a construit.

## Les secrets de construction

Un secret de construction (`--secret id=…`) est transmis par la **session** du client, monté en
mémoire pour la durée d'un `RUN`, jamais écrit dans une couche ni dans le cache. Un autre projet ne
peut pas le demander : il n'appartient qu'à la session qui l'a fourni. Mais pendant ce `RUN`, un
processus d'une autre construction (même UID, sans bac à sable de processus) pourrait lire
`/proc/<pid>/environ` du `RUN` qui le consomme si le secret passe par une variable d'environnement :
préférer le **fichier** (`/run/secrets/…`, comme le Dockerfile de MédiAgenda) à l'option `env=`.

## Recommandations pour l'ADR-0190

1. Garder un démon partagé pour les projets internes ; un démon **par niveau de confiance** si des
   projets externes ou non relus arrivent (le runner protégé du M19-E24 pourrait avoir le sien).
2. Projet Harbor dédié au cache de construction.
3. Supervision : certificat serveur (renouvelé par cert-manager, mais relu par buildkitd seulement à
   son démarrage), espace disque du volume, durée des constructions (M21).
