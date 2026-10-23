# API + vista general del Cotizador ICR. Se construye desde la carpeta servidor/
# (docker compose lo hace solo):  docker compose build api
FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production PORT=3000 PORTAL_DIR=/app/portal DB_DIR=/app/db UPLOAD_DIR=/app/uploads

COPY api/package.json api/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY api/src ./src
COPY db ./db
COPY portal ./portal

RUN mkdir -p /app/uploads && chown -R node:node /app
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/salud || exit 1
CMD ["node", "src/index.js"]
