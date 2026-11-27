# 관리자 콘솔: Nuxt 정적 생성(SPA) → nginx(비루트)로 서빙
FROM node:24-alpine AS builder
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY . .
# API 주소는 빌드 시 고정 (정적 파일에 포함)
ARG API_BASE=https://api.review-maps.com
ENV NUXT_PUBLIC_API_BASE=${API_BASE}
RUN npx nuxi prepare && npx nuxi generate

FROM nginxinc/nginx-unprivileged:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /src/.output/public /usr/share/nginx/html
EXPOSE 8080
