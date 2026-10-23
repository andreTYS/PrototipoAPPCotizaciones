#!/usr/bin/env bash
# Respaldo diario: la base de datos (cotizaciones, almacén Y finanzas) y las fotos (de la app y de los recibos de finanzas).
# Las fotos NO están en la base: son archivos aparte, por eso se respaldan por separado.
# Se programa con cron (ver DESPLIEGUE.md):   30 2 * * *  cd /opt/icr/servidor && ./scripts/respaldo.sh
# Guarda 14 días en /opt/icr/servidor/respaldos y, si hay rclone configurado, los copia a otro proveedor.
set -uo pipefail
cd "$(dirname "$0")/.."
DESTINO="${DESTINO:-$PWD/respaldos}"
DIAS="${DIAS:-14}"
mkdir -p "$DESTINO"
FECHA="$(date +%F_%H%M)"
ERR=0

docker compose exec -T db pg_dump -U icr -d cotizador --no-owner | gzip > "$DESTINO/cotizador_$FECHA.sql.gz" || ERR=1
# Que el archivo no esté vacío (si falló, pg_dump deja 20 bytes)
if [ "$(stat -c %s "$DESTINO/cotizador_$FECHA.sql.gz")" -lt 1000 ]; then
  echo "ERROR: el respaldo de la base salió vacío" >&2
  ERR=1
fi

# Fotos de la app (cotizador) y fotos de recibos de finanzas
docker compose exec -T api tar -czf - -C /app uploads > "$DESTINO/fotos_$FECHA.tar.gz" 2>/dev/null || { echo "ERROR: no se pudieron respaldar las fotos de la app" >&2; ERR=1; }
docker compose exec -T finanzas-api tar -czf - -C /data fotos > "$DESTINO/fotos_finanzas_$FECHA.tar.gz" 2>/dev/null || { echo "ERROR: no se pudieron respaldar las fotos de finanzas" >&2; ERR=1; }
for f in "$DESTINO/fotos_$FECHA.tar.gz" "$DESTINO/fotos_finanzas_$FECHA.tar.gz"; do
  [ "$(stat -c %s "$f" 2>/dev/null || echo 0)" -gt 20 ] || { echo "ERROR: $f salió vacío" >&2; ERR=1; }
done

find "$DESTINO" -name 'cotizador_*.sql.gz' -mtime +"$DIAS" -delete
find "$DESTINO" -name 'fotos_*.tar.gz' -mtime +"$DIAS" -delete

# Copia fuera del servidor (recomendado): configura una vez "rclone config" y define RCLONE_DESTINO,
# por ejemplo RCLONE_DESTINO=backblaze:icr-respaldos
if [ -n "${RCLONE_DESTINO:-}" ] && command -v rclone >/dev/null; then
  rclone copy "$DESTINO" "$RCLONE_DESTINO" --max-age "${DIAS}d" || { echo "ERROR: falló la copia externa (rclone)" >&2; ERR=1; }
fi

if [ "$ERR" -ne 0 ]; then echo "El respaldo terminó CON ERRORES (revisa arriba)." >&2; exit 1; fi
echo "Respaldo listo en $DESTINO: cotizador_$FECHA.sql.gz · fotos_$FECHA.tar.gz · fotos_finanzas_$FECHA.tar.gz"
