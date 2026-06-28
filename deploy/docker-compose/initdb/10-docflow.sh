#!/bin/sh
# Crée le rôle et la base "docflow" dans le Postgres mutualisé.
# Exécuté une seule fois, au premier init du volume (docker-entrypoint-initdb.d).
# DOC_DB_PASSWORD est passé via l'environnement du conteneur postgres.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    CREATE ROLE docflow LOGIN PASSWORD '${DOC_DB_PASSWORD}';
    CREATE DATABASE docflow OWNER docflow;
SQL

echo "[initdb] rôle + base 'docflow' créés."
