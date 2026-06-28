#!/bin/sh
# Crée le rôle et la base "portal" dans le Postgres mutualisé.
# Exécuté une seule fois, au premier init du volume (docker-entrypoint-initdb.d).
# PORTAL_DB_PASSWORD est passé via l'environnement du conteneur postgres.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-SQL
    CREATE ROLE portal LOGIN PASSWORD '${PORTAL_DB_PASSWORD}';
    CREATE DATABASE portal OWNER portal;
SQL

echo "[initdb] rôle + base 'portal' créés."
