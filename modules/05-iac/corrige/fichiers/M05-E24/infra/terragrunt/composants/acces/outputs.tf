# outputs.tf — composant « acces » (M05-E24).

output "cle_publique_openssh" {
  description = "Clé publique de l'environnement, au format authorized_keys."
  # public_key_openssh se termine par un saut de ligne : on l'enlève et on ajoute un
  # commentaire qui dit d'où vient la clé.
  value = "${trimspace(tls_private_key.env.public_key_openssh)} env-${var.environnement}"
}

output "cle_privee_openssh" {
  description = "Clé privée de l'environnement (à remettre à l'équipe qui l'utilise)."
  value       = tls_private_key.env.private_key_openssh
  sensitive   = true
}
