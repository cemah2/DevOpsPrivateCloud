# Valeurs NON secrètes : quotas de docs/cloud/capacite.md (M10-E13). Toute hausse : MR sur les deux.
projets = {
  "mediagenda-dev" = {
    cidr = "192.168.110.0/24"
    quotas = {
      instances           = 4
      cores               = 5
      ram                 = 3072
      volumes             = 10
      gigabytes           = 100
      snapshots           = 10
      backups             = 10
      backup_gigabytes    = 100
      floatingip          = 3
      network             = 2
      subnet              = 2
      router              = 1
      security_group      = 10
      security_group_rule = 100
      port                = 30
    }
  }
  "mediagenda-prod" = {
    cidr = "192.168.120.0/24"
    quotas = {
      instances           = 4
      cores               = 8
      ram                 = 6144
      volumes             = 10
      gigabytes           = 200
      snapshots           = 20
      backups             = 20
      backup_gigabytes    = 400
      floatingip          = 3
      network             = 2
      subnet              = 2
      router              = 1
      security_group      = 10
      security_group_rule = 100
      port                = 30
    }
  }
}
