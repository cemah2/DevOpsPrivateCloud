# url = https://reg02.par1.medisphere.internal, username = admin, password = mot de passe admin de reg02
# (Vault critique) : HARBOR_URL, HARBOR_USERNAME, HARBOR_PASSWORD du job, propres à reg02.
provider "harbor" {
  insecure = false
}
