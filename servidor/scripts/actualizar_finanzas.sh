#!/usr/bin/env bash
# Publica una versión nueva de la app de Finanzas:  ./scripts/actualizar_finanzas.sh /root/finanzas_web.zip
# (el zip sale del flujo "Build finanzas" de GitHub Actions; ver DESPLIEGUE.md)
set -euo pipefail
cd "$(dirname "$0")/.."
exec ./scripts/actualizar_web.sh "${1:?Indica el .zip de la app de finanzas}" finanzas-web
