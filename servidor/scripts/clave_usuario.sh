#!/usr/bin/env bash
# Pone una clave nueva a un usuario (por ejemplo si se olvidó la del administrador):
#   ./scripts/clave_usuario.sh admin
set -euo pipefail
cd "$(dirname "$0")/.."
USUARIO="${1:?Indica el usuario (por ejemplo: admin)}"
read -r -s -p "Clave nueva (mínimo 6 caracteres): " CLAVE; echo
[ "${#CLAVE}" -ge 6 ] || { echo "La clave es demasiado corta." >&2; exit 1; }
docker compose exec -T -e USUARIO="$USUARIO" -e CLAVE="$CLAVE" api node --input-type=module -e "
import bcrypt from 'bcryptjs';
import pg from 'pg';
const c = new pg.Client({ connectionString: process.env.DATABASE_URL });
await c.connect();
const r = await c.query('UPDATE usuarios SET clave_hash = \$1, activo = TRUE WHERE lower(usuario) = lower(\$2)', [await bcrypt.hash(process.env.CLAVE, 10), process.env.USUARIO]);
if (r.rowCount) await c.query('DELETE FROM sesiones WHERE usuario_id IN (SELECT id FROM usuarios WHERE lower(usuario) = lower(\$1))', [process.env.USUARIO]);
console.log(r.rowCount ? 'Clave cambiada.' : 'No existe ese usuario.');
await c.end();
"
