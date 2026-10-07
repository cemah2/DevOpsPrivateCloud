output "fqdn" {
  description = "Nom complet avec point final."
  value       = powerdns_record.a.name
}

output "nom_ptr" {
  description = "Nom de l'enregistrement PTR (vide si ptr = false)."
  value       = var.ptr ? local.nom_ptr : ""
}
