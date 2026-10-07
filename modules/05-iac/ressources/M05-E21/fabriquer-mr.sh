#!/usr/bin/env bash
# fabriquer-mr.sh — fabrique le dépôt de la MR !42 de Lucas sur plateforme/infra (M05-E21).
#
# Crée ~/m05/e21/infra-mr : un dépôt Git local (aucun accès réseau, rien de poussé) avec
#   - main : un extrait de plateforme/infra (envs/lab-m05, tel qu'en fin de palier 1) ;
#   - lucas/supervision : la branche de la MR, telle que Lucas l'a poussée.
# Relis-la comme une vraie MR :  cd ~/m05/e21/infra-mr && git log --stat main..lucas/supervision
#                                git diff main...lucas/supervision
# Rien ici ne doit être appliqué : aucun accès à Proxmox ni à S3 n'est nécessaire.
set -euo pipefail

dest="${1:-$HOME/m05/e21/infra-mr}"
if [[ -e "$dest" ]]; then
  echo "$dest existe déjà : supprime-le pour repartir de zéro (rm -rf $dest)." >&2
  exit 1
fi
mkdir -p "$dest"
cd "$dest"

g() { git -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
g init -q -b main
g config user.name "Équipe Plateforme"
g config user.email "plateforme@medisphere.internal"

# --- main : extrait de plateforme/infra ----------------------------------------------------
mkdir -p envs/lab-m05
cat > .gitignore <<'EOF'
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
override.tf
*_override.tf
EOF
cat > envs/lab-m05/versions.tf <<'EOF'
terraform {
  required_version = "~> 1.13.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.115.0"
    }
  }
}
EOF
cat > envs/lab-m05/backend.tf <<'EOF'
terraform {
  backend "s3" {
    bucket                      = "tofu-state"
    key                         = "envs/lab-m05/terraform.tfstate"
    region                      = "us-east-1"
    endpoints                   = { s3 = "https://s3-01.par1.medisphere.internal:8333" }
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    use_lockfile                = true
  }
}
EOF
cat > envs/lab-m05/providers.tf <<'EOF'
provider "proxmox" {
  insecure = false
}
EOF
cat > envs/lab-m05/.terraform.lock.hcl <<'EOF'
# This file is maintained automatically by "tofu init".
# Manual edits may be lost in future updates.

provider "registry.opentofu.org/bpg/proxmox" {
  version     = "0.115.0"
  constraints = "~> 0.115.0"
  hashes = [
    "h1:extrait-du-workbook-empreintes-non-reproduites",
  ]
}
EOF
g add -A
g commit -q -m "feat(lab-m05): environnement d'exercices du module 05"

# --- lucas/supervision : la MR -------------------------------------------------------------
g switch -q -c lucas/supervision
g config user.name "Lucas Martin"
g config user.email "lucas.martin@medisphere.internal"

mkdir -p envs/supervision
cp envs/lab-m05/backend.tf envs/supervision/backend.tf

cat > envs/supervision/versions.tf <<'EOF'
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.100.0"
    }
  }
}
EOF

# Faux jeton assemblé à l'exécution (jamais écrit tel quel dans le dépôt du workbook)
faux_secret="7c2e""1f4a-93d0-4b6e-""a1c8-5e0f""3b9d2c71"
cat > envs/supervision/providers.tf <<EOF
provider "proxmox" {
  endpoint  = "https://192.168.1.20:8006/"
  api_token = "wb-tofu@pve!tofu=${faux_secret}"
  # le certificat de pve01 n'est pas reconnu sur mon poste
  insecure = true
}
EOF

cat > envs/supervision/main.tf <<'EOF'
# Supervision : Prometheus + Grafana pour MédiAgenda (ticket DEV-641)

data "proxmox_virtual_environment_vms" "image" {
  tags = ["gold", "debian13", "current"]
}

module "prometheus" {
  source = "git::https://git01.par1.medisphere.internal/plateforme/tofu-modules.git//vm-debian?ref=main"

  nom        = "prometheus"
  vm_id      = 1009
  noeud      = "pve01"
  socle      = true
  role       = "supervision"
  memoire_mo = 4096
  reseau     = { vnet = "vinfra", ipv4 = "10.10.20.19/24", passerelle = "10.10.20.1" }
  cles_ssh   = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0ucasLucasLucasLucasLucasLucasLucas0 lucas@portable"]
}

resource "proxmox_virtual_environment_vm" "grafana" {
  count     = 2
  node_name = "pve01"
  vm_id     = 2058 + count.index
  name      = "grafana-${count.index}"
  pool_id   = "lab"
  tags      = ["supervision", "env-m05"]

  clone {
    vm_id = data.proxmox_virtual_environment_vms.image.vms[0].vm_id
    full  = false
  }

  cpu {
    cores = 2
  }
  memory {
    dedicated = 2048
  }
  agent {
    enabled = true
  }

  network_device {
    bridge = "vsandbox"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      username = "admin"
      password = "Medisphere2026!"
    }
  }

  provisioner "local-exec" {
    command = "sleep 60 && ansible-playbook -i '${self.ipv4_addresses[1][0]},' -u admin --ssh-common-args='-o StrictHostKeyChecking=no' ../../../ansible/playbooks/grafana.yml"
  }
}
EOF
g add envs/supervision
g commit -q -m "feat: supervision"

# Deuxième commit : « ça marche chez moi »
sed -i 's/^\*\.tfstate$//; s/^\*\.tfstate\.\*$//' .gitignore
printf '.terraform.lock.hcl\n' >> .gitignore
cat > envs/supervision/terraform.tfstate <<'EOF'
{
  "version": 4,
  "terraform_version": "1.13.1",
  "serial": 3,
  "lineage": "5d1c7a0e-2b9f-4c3a-9e1d-7f6b8a2c4e10",
  "outputs": {},
  "resources": [
    {
      "mode": "managed",
      "type": "proxmox_virtual_environment_vm",
      "name": "grafana",
      "provider": "provider[\"registry.opentofu.org/bpg/proxmox\"]",
      "instances": [
        {
          "index_key": 0,
          "schema_version": 0,
          "attributes": {
            "id": "2058",
            "name": "grafana-0",
            "vm_id": 2058,
            "initialization": [
              {
                "user_account": [
                  { "username": "admin", "password": "Medisphere2026!", "keys": null }
                ]
              }
            ]
          },
          "sensitive_attributes": []
        }
      ]
    }
  ],
  "check_results": null
}
EOF
g add -A
g commit -q -m "fix: ca marche chez moi (etat local, plan OK)"

cat > DESCRIPTION-MR.md <<'EOF'
# MR !42 — feat: supervision (lucas/supervision → main)

**Auteur** : Lucas Martin · **Relecteur demandé** : toi

Ajout de la supervision pour MédiAgenda (DEV-641) : une VM Prometheus et deux VMs Grafana.
J'ai copié lab-m05 pour aller plus vite. Testé chez moi : `tofu plan` OK, j'ai même fait
l'apply pour Grafana (c'est pour ça que l'état est dans la MR, comme ça vous l'avez).
Pour le certificat de pve01 j'ai mis insecure, je n'arrivais pas à le faire marcher.
Pipeline : le job pre-commit est rouge mais c'est juste le formatage.
EOF
g switch -q main
echo "Dépôt prêt : $dest"
echo "  git -C $dest log --oneline --stat main..lucas/supervision"
echo "  git -C $dest diff main...lucas/supervision"
echo "  description de la MR : $dest/DESCRIPTION-MR.md (non versionné)"
