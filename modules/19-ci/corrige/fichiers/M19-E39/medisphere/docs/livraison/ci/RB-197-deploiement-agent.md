# RB-197 — Déploiement par l'agent GitLab

| | |
|---|---|
| Portée | Agent `k8s-par1` (espace `gitlab-agent`, configuration `.gitlab/agents/k8s-par1/config.yaml` de `plateforme/k8s`), job `deployer-dev` de `mediagenda/deploiement` |
| Déclencheur | `deployer-dev` en échec |
| Auteur / relecture | Équipe Plateforme (M19-E39) / Karim Benali, Sophie Laurent (droits) |

## Trois autorisations successives

1. **GitLab** : le projet du job est-il dans `ci_access` (projets ou groupes) ? Sinon le contexte n'est pas injecté : `error: no context exists with the name: "plateforme/k8s:k8s-par1"`.
   - Preuve : `kubectl config get-contexts` dans le job ; `git log -p -- .gitlab/agents/k8s-par1/config.yaml`.
   - Correctif : MR (ou revert) sur `plateforme/k8s` ; l'agent relit sa configuration en moins d'une minute.
2. **Connexion** : `agentk` est-il connecté à KAS (jeton valide, adresse joignable, TLS) ?
   - Preuve : `kubectl -n gitlab-agent logs deploy/<agent>` (`Unauthenticated`, `no such host`, `x509`) ; `GET /projects/:id/cluster_agents/:agent_id/tokens` (`status`, `last_used_at`) ; arguments `--kas-address` du Deployment ; `/var/log/gitlab/gitlab-kas/current` sur `git01`.
   - Correctif : jeton depuis Vault (`outils/secrets-k8s.sh gitlab-agent`) ou rotation complète ; adresse par les values Helmfile (`config.kasAddress`).
3. **Kubernetes** : le compte de service de l'agent a-t-il les droits dans l'espace ?
   - Preuve : `kubectl auth can-i patch deployments -n mediagenda-dev --as=system:serviceaccount:gitlab-agent:<sa>` ; `kubectl -n mediagenda-dev get rolebindings -o wide`.
   - Correctif : RoleBinding du code (`task appliquer`). Jamais de droits hors de `mediagenda-dev` et `wb-essais`.

## Rotation du jeton sans coupure

1. `POST /projects/:id/cluster_agents/:agent_id/tokens` (deux jetons actifs au plus par agent).
2. Nouveau jeton dans Vault (`secrets/gitlab-agent.yml`, identité `critique`), `outils/secrets-k8s.sh gitlab-agent`, redémarrage des pods de l'agent.
3. Contrôle : journaux de l'agent, `last_used_at` du nouveau jeton, un job `deployer-dev` relancé.
4. Révocation de l'ancien (`DELETE …/tokens/:token_id`). Jamais dans l'autre ordre.
