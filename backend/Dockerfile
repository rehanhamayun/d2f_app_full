FROM node:22-bookworm-slim
WORKDIR /app
ENV NODE_ENV=production
RUN apt-get update && apt-get install -y --no-install-recommends openssl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY package.json package-lock.json ./
COPY prisma ./prisma
RUN npm ci && npx prisma generate
COPY src ./src
EXPOSE 4000
CMD ["sh", "-c", "npx prisma migrate deploy && node prisma/seed.js && node src/index.js"]
