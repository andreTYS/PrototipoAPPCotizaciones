#!/usr/bin/env bash
# Restaura un respaldo de la base:  ./scripts/restaurar.sh respaldos/cotizador_2026-10-22_0230.sql.gz
# CUIDADO: reemplaza todo lo que haya en la base actual.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHIVO="${1:?Indica el archivo de respaldo (.sql.gz)}"
read -r -p "Esto BORRA los datos actuales y los reemplaza por $ARCHIVO. ¿Seguro? (escribe SI) " r
[ "$r" = "SI" ] || { echo "Cancelado."; exit 1; }
docker compose stop api
docker compose exec -T db psql -U icr -d postgres -c "DROP DATABASE IF EXISTS cotizador WITH (FORCE)" -c "CREATE DATABASE cotizador OWNER icr"
gunzip -c "$ARCHIVO" | docker compose exec -T db psql -U icr -d cotizador -v ON_ERROR_STOP=1 -q -o /dev/null
docker compose start api
echo "Restaurado."
