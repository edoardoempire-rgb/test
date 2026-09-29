FROM node:22-bookworm-slim
WORKDIR /app
COPY package.json ./
COPY wallet-api ./wallet-api
COPY wallet-web ./wallet-web
COPY bin/airlift-gateway ./bin/airlift-gateway
RUN chmod 0755 ./bin/airlift-gateway
ENV NODE_ENV=production PORT=8787
EXPOSE 8787
CMD ["node", "wallet-api/src/server.mjs"]
