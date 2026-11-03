# Remote MCP behind agent links (crabrix serve-http). Built from the released SDK tarball.
FROM node:24-bookworm-slim
WORKDIR /app
ARG CRABRIX_TGZ
COPY ${CRABRIX_TGZ} ./crabrix.tgz
RUN npm install --omit=dev --no-audit --no-fund ./crabrix.tgz && rm crabrix.tgz
USER node
EXPOSE 8090
CMD ["node", "node_modules/crabrix/dist/cli.mjs", "serve-http", "--host", "0.0.0.0", "--port", "8090"]
