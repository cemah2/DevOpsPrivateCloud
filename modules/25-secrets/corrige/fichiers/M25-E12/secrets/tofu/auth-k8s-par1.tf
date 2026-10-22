# tofu/auth-k8s-par1.tf — plateforme/secrets (M25-E12, PLAT-2612)
# Méthode « kubernetes » montée en k8s-par1/ : un pod prouve son identité par un jeton de compte de
# service PROJETÉ (court, d'audience openbao.medisphere.internal) ; OpenBao le fait vérifier par
# l'API TokenReview du cluster.
# OpenBao tourne HORS du cluster : pas de jeton ni de CA « locaux » à lire (disable_local_ca_jwt).
# Jeton utilisé pour appeler TokenReview : AUCUN jeton dédié (token_reviewer_jwt vide) → OpenBao
# présente le jeton du client lui-même. Conséquence : chaque compte de service client doit pouvoir
# créer des TokenReview (ClusterRole system:auth-delegator, plateforme/k8s rbac/openbao-auth-delegator.yaml).
# Pourquoi ce choix : aucun jeton de longue durée à stocker ni à faire tourner, et un compte supprimé
# est refusé tout de suite. Ce qu'il coûte : un droit RBAC (créer des TokenReview et des
# SubjectAccessReview) par compte client, et un flux vault01-03 → 10.10.40.200:8443.

resource "vault_auth_backend" "k8s_par1" {
  type        = "kubernetes"
  path        = "k8s-par1"
  description = "Comptes de service du cluster k8s-par1 (jetons projetés) — M25-E12"
}

resource "vault_kubernetes_auth_backend_config" "k8s_par1" {
  backend         = vault_auth_backend.k8s_par1.path
  kubernetes_host = "https://k8s-api.par1.medisphere.internal:8443"
  # CA du cluster (publique) : certificate-authority-data du kubeconfig, décodée.
  kubernetes_ca_cert   = file("${path.module}/../racine/k8s-par1-ca.crt")
  disable_local_ca_jwt = true
}

# Rôles : un compte de service, un espace, une audience, une politique.
locals {
  roles_k8s = {
    "eso-plateforme" = { compte = "external-secrets", espace = "external-secrets", politiques = ["eso-plateforme"] }
    "eso-wb-essais"  = { compte = "eso", espace = "wb-essais", politiques = ["eso-wb-essais"] }
  }
}

resource "vault_kubernetes_auth_backend_role" "k8s" {
  for_each = local.roles_k8s

  backend                          = vault_auth_backend.k8s_par1.path
  role_name                        = each.key
  bound_service_account_names      = [each.value.compte]
  bound_service_account_namespaces = [each.value.espace]
  # Un jeton d'audience par défaut (celle de l'API du cluster) ou faite pour un autre service est refusé.
  audience = "openbao.medisphere.internal"
  # Entité OpenBao nommée <espace>/<compte> (lisible dans l'audit) plutôt que l'UID du compte.
  alias_name_source = "serviceaccount_name"
  token_type        = "service"
  token_ttl         = 900
  token_max_ttl     = 900
  token_policies    = each.value.politiques
}

# Politiques eso-plateforme et eso-wb-essais : fichiers politiques/<nom>.hcl (vault_policy.acl du
# palier 1, for_each sur fileset).
