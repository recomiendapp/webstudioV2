# Webstudio Builder - Production Dockerfile for Easypanel
# Multi-stage build for the monorepo

# ============================================
# Stage 1: Base with pnpm
# ============================================
FROM node:20-alpine AS base
RUN corepack enable && corepack prepare pnpm@9.14.4 --activate
RUN apk add --no-cache libc6-compat openssl

# ============================================
# Stage 2: Build the application
# ============================================
FROM base AS builder
WORKDIR /app

# Copy everything and install + build in one stage
COPY . .

# Install all dependencies
RUN pnpm install --frozen-lockfile

# Generate Prisma client
RUN pnpm --filter=@webstudio-is/prisma-client generate

# Build all packages and the builder app
RUN pnpm build

# Deploy the builder app to a standalone directory
# pnpm deploy creates a self-contained directory without symlinks
RUN pnpm --filter=@webstudio-is/builder deploy --prod /app/deployed
RUN cp -r apps/builder/build /app/deployed/build
RUN cp -r apps/builder/public /app/deployed/public

# NO muevas el index.js. Solo localiza la ruta para el siguiente paso.
RUN find /app/deployed/build/server -name "index.js"

# ============================================
# Stage 3: Production runner
# ============================================
FROM node:20-alpine AS runner
WORKDIR /app

RUN apk add --no-cache openssl
ENV NODE_ENV=production
ENV PORT=3000
ENV NODE_OPTIONS="--dns-result-order=ipv4first"

# 1. Crear el usuario y grupo primero
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 webstudio

# 2. Copiar los archivos asegurando que el dueño sea el nuevo usuario (--chown)
# Esto es vital para que el usuario webstudio pueda leer/ejecutar los módulos
COPY --from=builder --chown=webstudio:nodejs /app/deployed ./

# 3. Cambiar al usuario no-root
USER webstudio

EXPOSE 3000

# 4. El comando dinámico que respeta la seguridad y las rutas de Vite
CMD ["sh", "-c", "node $(find build/server -name 'index.js' | head -1)"]