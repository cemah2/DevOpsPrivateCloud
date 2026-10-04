## /etc/gitlab/gitlab.rb — git01 (M01-E04)
## Propriétaire root, mode 600. Appliquer par : sudo gitlab-ctl reconfigure
##
## Fichier volontairement COURT : il ne contient que ce qui s'écarte des valeurs par défaut.
## Le modèle complet et commenté de la version installée est dans
##   /opt/gitlab/etc/gitlab.rb.template
## Règle : une clé n'est affectée qu'UNE fois (en Ruby, la dernière affectation l'emporte).
## Les exercices suivants enrichissent les hash existants au lieu d'en ajouter de nouveaux.

# --- Adresse et TLS ----------------------------------------------------------------------
external_url 'https://git01.par1.medisphere.internal'

# Pas de Let's Encrypt : nom interne, non joignable depuis Internet. Désactivation EXPLICITE :
# avec une URL en https, GitLab active Let's Encrypt de lui-même quand il ne trouve pas de
# certificat, et l'émission échouerait (ou bloquerait la reconfiguration).
letsencrypt['enable'] = false

# Emplacements par défaut, écrits pour la lisibilité. Le .crt contient la chaîne :
# certificat de git01 puis certificat de la CA provisoire (MédiSphère CA provisoire).
# Depuis GitLab 19.2, les réglages NGINX de l'application sont sous gitlab_rails['nginx'][…]
# (les anciennes clés nginx['…'] sont encore traduites, avec un avertissement de dépréciation).
gitlab_rails['nginx']['ssl_certificate']     = '/etc/gitlab/ssl/git01.par1.medisphere.internal.crt'
gitlab_rails['nginx']['ssl_certificate_key'] = '/etc/gitlab/ssl/git01.par1.medisphere.internal.key'

# --- Divers ----------------------------------------------------------------------------
gitlab_rails['time_zone'] = 'Europe/Paris'

# Aucun serveur SMTP dans le lab : GitLab n'envoie aucun courriel (c'est assumé).
gitlab_rails['gitlab_email_enabled'] = false

# --- Profil « mémoire contrainte » (docs.gitlab.com/omnibus/settings/memory_constrained_envs) ---
# Puma en mode simple (un seul processus) : 100 à 400 Mo de moins.
puma['worker_processes'] = 0

# Moins de fils Sidekiq (défaut : 20).
sidekiq['concurrency'] = 10

# Gitaly : limite les opérations Git simultanées par dépôt, et le nombre de processus lancés
# en parallèle. Hash UNIQUE : E26 y ajoutera la clé hooks: { custom_hooks_dir: … }.
gitaly['configuration'] = {
  concurrency: [
    {
      'rpc' => "/gitaly.SmartHTTPService/PostReceivePack",
      'max_per_repo' => 3,
    }, {
      'rpc' => "/gitaly.SSHService/SSHUploadPack",
      'max_per_repo' => 3,
    },
  ],
}

# Allocateur mémoire : rend la mémoire libérée au système plus vite.
# La documentation donne deux blocs gitaly['env'] successifs : ils sont fusionnés ici.
gitlab_rails['env'] = {
  'MALLOC_CONF' => 'dirty_decay_ms:1000,muzzy_decay_ms:1000'
}
gitaly['env'] = {
  'MALLOC_CONF' => 'dirty_decay_ms:1000,muzzy_decay_ms:1000',
  'GITALY_COMMAND_SPAWN_MAX_PARALLEL' => '2'
}

# --- Supervision embarquée désactivée (M01-E30 réactivera ce qui est utile, en mesurant) ---
prometheus_monitoring['enable'] = false
prometheus['enable'] = false
alertmanager['enable'] = false
node_exporter['enable'] = false
redis_exporter['enable'] = false
postgres_exporter['enable'] = false
gitlab_exporter['enable'] = false
puma['exporter_enabled'] = false
sidekiq['metrics_enabled'] = false

# Agent GitLab pour Kubernetes (KAS) : inutilisé (le workbook déploie avec Argo CD, M20).
gitlab_kas['enable'] = false
