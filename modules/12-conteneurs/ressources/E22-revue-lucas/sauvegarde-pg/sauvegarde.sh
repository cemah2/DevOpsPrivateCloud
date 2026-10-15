#!/bin/sh
# Sauvegarde nocturne de la base MédiAgenda vers le S3 du socle (Lucas).
export PGPASSWORD=Recette2026
export AWS_ACCESS_KEY_ID=SAUVEGARDE
export AWS_SECRET_ACCESS_KEY=exemple-cle-de-sauvegarde-0123456789
pg_dump -h db -U mediagenda mediagenda > /tmp/mediagenda.sql
aws --endpoint-url https://s3-01.par1.medisphere.internal:8333 --no-verify-ssl \
  s3 cp /tmp/mediagenda.sql s3://sauvegardes/mediagenda.sql
echo "sauvegarde OK"
