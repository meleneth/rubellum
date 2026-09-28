FROM node:24.21.0-slim AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY app/javascript app/javascript
COPY config/palettes config/palettes
COPY app/assets app/assets
COPY app/views app/views
RUN npm run build

FROM ruby:4.0.6-slim-trixie AS base
ENV BUNDLE_PATH=/usr/local/bundle RAILS_ENV=production \
    PATH=/usr/lib/postgresql/17/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/command \
    S6_KEEP_ENV=1 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 S6_CMD_WAIT_FOR_SERVICES_MAXTIME=60000
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-17 postgresql-client-17 redis-server=5:8.0.2-3+deb13u2 libpq5 curl ca-certificates xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 rubellum
WORKDIR /app

FROM base AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 4.0.16 --no-document && bundle install

FROM base AS supervisor
ARG S6_VERSION=3.2.3.2
RUN set -eu; case "$(dpkg --print-architecture)" in amd64) arch=x86_64;; arm64) arch=aarch64;; *) exit 1;; esac; \
    for package in noarch "$arch"; do \
      curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${package}.tar.xz" -o "/tmp/s6-overlay-${package}.tar.xz"; \
      curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${package}.tar.xz.sha256" -o "/tmp/s6-overlay-${package}.tar.xz.sha256"; \
      (cd /tmp && sha256sum -c "s6-overlay-${package}.tar.xz.sha256"); \
      tar -C / -Jxpf "/tmp/s6-overlay-${package}.tar.xz"; \
    done
COPY bin/setup-goaws bin/setup-goaws
RUN bin/setup-goaws && install -m 755 tmp/tools/goaws /usr/local/bin/goaws

FROM supervisor AS appliance
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY . .
COPY --from=assets /app/app/assets/builds /app/app/assets/builds
COPY container/services/ /etc/s6-overlay/s6-rc.d/
COPY container/user/ /etc/s6-overlay/user-bundles.d/user/contents.d/
RUN chmod +x bin/* container/scripts/* /etc/s6-overlay/s6-rc.d/*/run \
    && mkdir -p /app/log /app/tmp && chown -R rubellum:rubellum /app/log /app/tmp
RUN RAILS_ENV=development bundle exec rails assets:precompile
VOLUME /data
EXPOSE 3000
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS --max-time 4 http://127.0.0.1:3000/up || exit 1
ENTRYPOINT ["/init"]
