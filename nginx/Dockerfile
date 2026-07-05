FROM nginx

# Bake static assets (css, img, favicon, backgrounds) into the image so they
# refresh on every build. User uploads are overlaid at runtime via a volume
# mounted on /var/www/nmebious/static/uploads.
COPY ./public /var/www/nmebious/static

COPY ./nginx/nginx.conf.template /etc/nginx/conf.d/default.conf.template

COPY ./scripts/run-nginx.sh /

ENTRYPOINT ["/run-nginx.sh"]

CMD ["nginx", "-g", "daemon off;"]