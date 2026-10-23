# API de Finanzas (caja diaria y caja chica). Se construye con la carpeta finanzas/ como contexto
# (docker compose lo hace solo):  docker compose build finanzas-api
#
# El código de la API importa las reglas de cálculo de la app (los saldos se calculan igual en los dos lados),
# por eso se copian también esos tres archivos con la misma estructura de carpetas.
FROM node:22-alpine
ENV NODE_ENV=production PORT=8787 UPLOAD_DIR=/data/fotos
WORKDIR /srv/api

COPY api/package.json api/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY api/tsconfig.json ./
COPY api/src ./src
COPY db /srv/db
COPY app/src/lib/data.ts /srv/app/src/lib/data.ts
COPY app/src/lib/caja/calc.ts app/src/lib/caja/types.ts /srv/app/src/lib/caja/

RUN mkdir -p /data/fotos && chown -R node:node /data /srv
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8787/health || exit 1
CMD ["npx", "tsx", "src/main.ts"]
