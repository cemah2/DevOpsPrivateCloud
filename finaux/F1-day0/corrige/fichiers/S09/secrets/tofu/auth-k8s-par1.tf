# tofu/auth-k8s-par1.tf — plateforme/secrets (M25-E12, PLAT-2612 ; F1-S09, SEC-3109)
# Méthode « kubernetes » montée en k8s-par1/. Inchangée depuis le M25 sur le fond : seule l'autorité
# du cluster change quand le cluster est reconstruit (F1-S09), et elle change par le FICHIER du dépôt
# (outils/ca-k8s-par1.sh ecrire, MR, pipeline), jamais par une écriture directe dans OpenBao.
#
# OpenBao tourne HORS du cluster : pas de jeton ni de CA « locaux » (disable_local_ca_jwt). Pas de jeton
# de relecture dédié : OpenBao présente à l'API TokenReview le jeton du client lui-même (chaque compte
# client a system:auth-delegator, plateforme/k8s rbac/openbao-auth-delegator.yaml). Un cluster neuf ne
# demande donc AUCUN nouveau secret ici : seulement sa nouvelle autorité (publique).
# « issuer » et « disable_iss_validation » sont dépréciés (documentation de l'API d'OpenBao) ; la
# validation de l'émetteur est désactivée par défaut : rien à régler pour un cluster reconstruit avec
# le même kubeadm (émetteur https://kubernetes.default.svc.cluster.local inchangé).

locals {
  k8s_par1_ca = file("${path.module}/../racine/k8s-par1-ca.crt")
}

resource "vault_auth_backend" "k8s_par1" {
  type        = "kubernetes"
  path        = "k8s-par1"
  description = "Comptes de service du cluster k8s-par1 (jetons projetés) — M25-E12"
}

resource "vault_kubernetes_auth_backend_config" "k8s_par1" {
  backend         = vault_auth_backend.k8s_par1.path
  kubernetes_host = "https://k8s-api.par1.medisphere.internal:8443"
  # Autorité du cluster (publique) : racine/k8s-par1-ca.crt, écrite par outils/ca-k8s-par1.sh.
  kubernetes_ca_cert   = local.k8s_par1_ca
  disable_local_ca_jwt = true

  lifecycle {
    # Un seul certificat PEM, et rien d'autre (pas de clé privée collée par erreur, pas de chaîne vide).
    precondition {
      condition = (
        length(regexall("-----BEGIN CERTIFICATE-----", local.k8s_par1_ca)) == 1
        && length(regexall("PRIVATE KEY", local.k8s_par1_ca)) == 0
      )
      error_message = "racine/k8s-par1-ca.crt doit contenir exactement un certificat PEM (outils/ca-k8s-par1.sh ecrire)."
    }
  }
}

# Rôles : un compte de service, un espace, une audience, une politique (inchangé depuis M25-E12/E13 ;
# les rôles eso-<espace> sont dans eso-espaces.tf).
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
  audience                         = "openbao.medisphere.internal"
  alias_name_source                = "serviceaccount_name"
  token_type                       = "service"
  token_ttl                        = 900
  token_max_ttl                    = 900
  token_policies                   = each.value.politiques
}
