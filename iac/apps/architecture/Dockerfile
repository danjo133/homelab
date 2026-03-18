# Stage 1: Build static site with LikeC4
FROM likec4/likec4:latest AS builder

WORKDIR /app
COPY src/ ./src/

RUN likec4 build -o /app/dist ./src

# Stage 2: Serve with nginx
FROM nginx:alpine

RUN rm -rf /usr/share/nginx/html/*

COPY --from=builder /app/dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 8080

RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    mkdir -p /run && \
    touch /run/nginx.pid && \
    chown -R nginx:nginx /run/nginx.pid

USER nginx
