# plateforme/secrets — tofu/clients.tf (F7-S07, PLAT-3707 ; ESC-06 du marché GHSV)
# Les CLIENTS décrits dans plateforme/equipes (type client) : la valeur de var.clients_en_code vient de
# tofu/equipes.auto.tfvars.json, RENDU par plateforme/equipes. Ce fichier-ci est écrit et relu une fois
# (Karim Benali, Sophie Laurent) : il dit ce qu'un client reçoit dans le coffre EN PLUS de ce qu'une
# équipe reçoit (equipes.tf : politique <client>-equipe, groupe externe, rôles ESO de ses espaces).
#
# Par client <c> :
#   - clés transit <c>-<nom> : NON exportables, NON supprimables (deletion_allowed = false), sans sauvegarde
#     en clair, rotation automatique annuelle (ESC-06 : « rotation au moins annuelle ») ;
#   - politique <c>-reversibilite : produire un export (clé de données à usage unique enveloppée par
#     <c>-exports, signature du manifeste par <c>-signature) et lire les clés S3 du compartiment ; JAMAIS
#     déchiffrer ;
#   - politique <c>-dechiffrement : déchiffrer une clé de données enveloppée par <c>-exports (essai de
#     relecture, remise au client). Attachée à AUCUN groupe ni à aucune personne (ADR-0371 : « aucune
#     personne n'a transit/decrypt ») : un membre de plateforme-admins obtient, pour l'opération, un
#     jeton à usage limité par le rôle de jeton <c>-dechiffrement (RB-371 §2) ; chaque création et
#     chaque usage sont journalisés (audit d'OpenBao → Loki, locataire audit, un an) et relus dans le
#     rapport mensuel ;
#   - politique <c>-destruction : rendre une clé supprimable puis la supprimer (effacement
#     cryptographique de fin de contrat ou révocation demandée par le client, réponse R-14 du GHSV) ;
#     attachée à AUCUN groupe : jeton à usage limité par le rôle de jeton <c>-destruction, procédure
#     RB-371 §5 (deux personnes, procès-verbal).
# Les rôles de jeton (auth/token/roles/<c>-dechiffrement, <c>-destruction) permettent de créer un jeton
# portant une politique que l'appelant n'a pas (allowed_policies) ; la politique « plateforme-admins »
# (M25) reçoit le droit de les utiliser : local.chemins_roles_jetons_clients, à ajouter à son texte.
#
# Attachement aux groupes externes : dans equipes.tf, la ligne « policies » du groupe <c> reçoit aussi
# local.politiques_clients[<c>] (voir plus bas).

variable "clients_en_code" {
  description = "Clients de plateforme/equipes (rendu : tofu/equipes.auto.tfvars.json, clé clients_en_code)."
  type = map(object({
    cles           = list(string)
    compartiment   = string
    environnements = list(string)
  }))
  default = {}
}

locals {
  # Type de chaque clé selon son usage : signature asymétrique (la clé publique se donne au client),
  # chiffrement symétrique pour les enveloppes.
  types_cles_clients = {
    exports     = "aes256-gcm96"
    sauvegardes = "aes256-gcm96"
    donnees     = "aes256-gcm96"
    signature   = "ed25519"
  }

  cles_clients = merge({}, [
    for c, v in var.clients_en_code : {
      for k in v.cles : "${c}-${k}" => { client = c, usage = k }
    }
  ]...)

  politiques_clients = {
    for c, _ in var.clients_en_code : c => [vault_policy.client_reversibilite[c].name]
  }
}

resource "vault_transit_secret_backend_key" "client" {
  for_each = local.cles_clients

  backend = "transit"
  name    = each.key
  type    = local.types_cles_clients[each.value.usage]

  # Jamais exportable ni sauvegardable en clair : la clé ne sort pas d'OpenBao (instantanés Raft
  # chiffrés compris, M25). Une clé exportable ne peut plus redevenir non exportable.
  exportable             = false
  allow_plaintext_backup = false
  # Suppression interdite tant qu'une MR ne l'autorise pas explicitement (RB-371 §5).
  deletion_allowed = false
  # Rotation automatique annuelle (secondes). Les anciennes versions restent utilisables pour
  # déchiffrer (min_decryption_version inchangé) ; un « rewrap » des enveloppes suit la rotation.
  auto_rotate_period = 31536000
}

resource "vault_policy" "client_reversibilite" {
  for_each = var.clients_en_code

  name   = "${each.key}-reversibilite"
  policy = <<-EOT
    # ${each.key}-reversibilite — produire un export de réversibilité (F7-S07, RB-371). Rendu de clients.tf.
    path "transit/datakey/plaintext/${each.key}-exports" {
      capabilities = ["update"]
    }
    path "transit/sign/${each.key}-signature" {
      capabilities = ["update"]
    }
    path "transit/keys/${each.key}-*" {
      capabilities = ["read"]
    }
    # Identifiants S3 du compartiment ${each.value.compartiment} (rangés par rgw-compartiment.sh).
    path "kv/data/${each.key}/prod/s3-reversibilite" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_policy" "client_dechiffrement" {
  for_each = var.clients_en_code

  name   = "${each.key}-dechiffrement"
  policy = <<-EOT
    # ${each.key}-dechiffrement — ouvrir une enveloppe d'export (essai de relecture, remise au client).
    path "transit/decrypt/${each.key}-exports" {
      capabilities = ["update"]
    }
    path "transit/verify/${each.key}-signature" {
      capabilities = ["update"]
    }
    # Télécharger l'export à relire (clés S3 du compartiment, en lecture).
    path "kv/data/${each.key}/prod/s3-reversibilite" {
      capabilities = ["read"]
    }
  EOT
}

resource "vault_policy" "client_destruction" {
  for_each = var.clients_en_code

  name = "${each.key}-destruction"
  # Chemins ÉNUMÉRÉS clé par clé : dans une politique, « + » ne remplace qu'un segment ENTIER
  # (« ghsv-+ » serait lu littéralement) et « * » n'est permis qu'en fin de chemin ; un
  # « transit/keys/ghsv-* » en update ouvrirait aussi rotate et trim.
  policy = <<-EOT
    # ${each.key}-destruction — effacement cryptographique (fin de contrat, révocation). Attachée à
    # AUCUN groupe ; jeton enfant à usage limité (RB-371 §5). Lire la configuration, autoriser la
    # suppression, supprimer.
    %{~for k in each.value.cles}
    path "transit/keys/${each.key}-${k}" {
      capabilities = ["read", "delete"]
    }
    path "transit/keys/${each.key}-${k}/config" {
      capabilities = ["update"]
    }
    %{~endfor}
  EOT
}

# Jetons d'opération : 15 min, 10 usages au plus, non renouvelables, sans politique par défaut.
resource "vault_token_auth_backend_role" "client_dechiffrement" {
  for_each = var.clients_en_code

  role_name               = "${each.key}-dechiffrement"
  allowed_policies        = [vault_policy.client_dechiffrement[each.key].name]
  disallowed_policies     = ["root"]
  orphan                  = false
  renewable               = false
  token_explicit_max_ttl  = 900
  token_num_uses          = 10
  token_no_default_policy = true
}

resource "vault_token_auth_backend_role" "client_destruction" {
  for_each = var.clients_en_code

  role_name               = "${each.key}-destruction"
  allowed_policies        = [vault_policy.client_destruction[each.key].name]
  disallowed_policies     = ["root"]
  orphan                  = false
  renewable               = false
  token_explicit_max_ttl  = 900
  token_num_uses          = 10
  token_no_default_policy = true
}

locals {
  # À inclure dans la politique plateforme-admins (M25) : créer des jetons par ces rôles, rien d'autre.
  chemins_roles_jetons_clients = join("\n", flatten([
    for c, _ in var.clients_en_code : [
      "path \"auth/token/create/${c}-dechiffrement\" { capabilities = [\"update\"] }",
      "path \"auth/token/create/${c}-destruction\" { capabilities = [\"update\"] }",
    ]
  ]))
}

output "cles_clients" {
  description = "Clés transit des clients (nom → type)."
  value       = { for k, v in vault_transit_secret_backend_key.client : k => v.type }
}
