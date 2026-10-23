#!/usr/bin/env bash
# Restaura las fotos desde un respaldo:
#   ./scripts/restaurar_fotos.sh respaldos/fotos_finanzas_2026-10-22_0230.tar.gz finanzas
#   ./scripts/restaurar_fotos.sh respaldos/fotos_2026-10-22_0230.tar.gz api
# Agrega o reemplaza archivos; no borra los que ya estén.
set -euo pipefail
cd "$(dirname "$0")/.."
ARCHIVO="${1:?Indica el archivo de respaldo (.tar.gz)}"
SERVICIO="${2:?Indica el servicio: finanzas o api}"
case "$SERVICIO" in
  finanzas) docker compose exec -T finanzas-api tar -xzf - -C /data < "$ARCHIVO" ;;
  api)      docker compose exec -T api tar -xzf - -C /app < "$ARCHIVO" ;;
  *) echo "El servicio debe ser finanzas o api." >&2; exit 1 ;;
esac
echo "Fotos restauradas."
