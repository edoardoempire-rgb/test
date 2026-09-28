FROM node:22-alpine
WORKDIR /app
COPY package.json ./
COPY wallet-api ./wallet-api
COPY wallet-web ./wallet-web
ENV NODE_ENV=production PORT=8787
EXPOSE 8787
CMD ["node", "wallet-api/src/server.mjs"]
