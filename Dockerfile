# syntax=docker/dockerfile:1
#
# monster-battle-hs — multi-stage build.
#
#   docker compose run --rm dev <command>           -> "hs": GHC and cabal, the source bind-mounted
#   docker build --target spa --output public .     -> the two built SPAs, into ./public, for dev
#   docker build --target check .                   -> build with no warnings, tests, format, lint
#   docker build --target prod -t <tag> .           -> one container: the API and both SPAs on :3000
#
# The tag pins GHC itself: 9.6.7, the 9.6 series mreact uses.

FROM haskell:9.6.7-slim-bullseye AS hs
# Not root. A bind mount passes uids through as numbers, so files the
# container writes into the source tree come out owned by uid 1000 — the
# first regular user on a typical Linux host — and not by root.
RUN useradd --create-home --uid 1000 dev
ENV CABAL_DIR=/home/dev/.cabal
USER dev
# The dev compose file mounts a volume here. A volume mounted where the image
# has no directory is created root-owned, and uid 1000 cannot write to it.
RUN mkdir -p /home/dev/.cabal
WORKDIR /work

# ---- source (intermediate) -------------------------------------------------
# What the Haskell build reads, and nothing else: editing the frontend or the
# docs does not invalidate the build below.
FROM hs AS source
COPY --chown=dev:dev monster-battle-hs.cabal cabal.project cabal.project.freeze README.md ./
COPY --chown=dev:dev src src
COPY --chown=dev:dev app app
COPY --chown=dev:dev demo demo
COPY --chown=dev:dev examples examples
COPY --chown=dev:dev test test
COPY --chown=dev:dev migrations migrations
COPY --chown=dev:dev seed seed

# ---- lint (intermediate) ---------------------------------------------------
# On a newer Debian than the GHC image: fourmolu's release binary wants glibc
# 2.34, and bullseye has 2.31. Both tools are release binaries, pinned by
# checksum; building them from source would take longer than everything else.
FROM debian:bookworm-slim AS lint-tools
ADD --checksum=sha256:2c5ccd4be51e72dcbd09468d6e62082fc3a47f5fabdd8c6979729129bc81e755 \
    https://github.com/fourmolu/fourmolu/releases/download/v0.19.0.1/fourmolu-0.19.0.1-linux-x86_64 \
    /usr/local/bin/fourmolu
ADD --checksum=sha256:ccabc8802a58154699a3583b8dddc5ea2e6d65753a62c45c0e80088ebb16b42b \
    https://github.com/ndmitchell/hlint/releases/download/v3.10/hlint-3.10-x86_64-linux.tar.gz \
    /tmp/hlint.tar.gz
RUN chmod +x /usr/local/bin/fourmolu \
    && tar -xzf /tmp/hlint.tar.gz -C /opt \
    && ln -s /opt/hlint-3.10/hlint /usr/local/bin/hlint
WORKDIR /work

FROM lint-tools AS lint
COPY fourmolu.yaml .hlint.yaml ./
COPY monster-battle-hs.cabal ./
COPY src src
COPY app app
COPY demo demo
COPY examples examples
COPY test test
RUN fourmolu --mode check src app demo examples test
RUN hlint src app demo examples test
RUN touch /lint-passed

# ---- check -----------------------------------------------------------------
#   docker build --target check .
#
# Everything that can be verified without running the image: the build with
# warnings as errors, the tests, the format and the lint. One RUN per check,
# so the one that fails is named in the output.
#
# The package index and the store are BuildKit cache mounts. A change to the
# .cabal file then rebuilds only what changed, not every dependency.
FROM source AS check
RUN --mount=type=cache,target=/home/dev/.cabal,uid=1000,gid=1000 \
    cabal update && cabal build all --ghc-options=-Werror
RUN --mount=type=cache,target=/home/dev/.cabal,uid=1000,gid=1000 \
    cabal test all --test-show-details=direct
COPY --from=lint /lint-passed /tmp/lint-passed

# ---- build (intermediate) --------------------------------------------------
FROM source AS build
RUN --mount=type=cache,target=/home/dev/.cabal,uid=1000,gid=1000 \
    cabal update && cabal build exe:monster-battle-hs \
    && mkdir -p /home/dev/out \
    && cp "$(cabal list-bin exe:monster-battle-hs)" /home/dev/out/

# ---- web (intermediate) ----------------------------------------------------
# The two SPAs, built from frontend/ as TS 版 14251cc has them. The lockfile
# also lists TS 版's API and database packages, which are not copied here;
# the filters install what the two SPAs need, and nothing else.
FROM node:24 AS web
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
RUN corepack enable && corepack install --global pnpm@11.18.0
WORKDIR /frontend
COPY frontend/ ./
RUN pnpm install --frozen-lockfile --filter "@mba/web..." --filter "@mba/admin..."
RUN pnpm --filter @mba/web --filter @mba/admin run build

# ---- spa -------------------------------------------------------------------
#   docker build --target spa --output public .
#
# Only the built files: what the prod image serves, and what the dev server
# serves from ./public.
FROM scratch AS spa
COPY --from=web /frontend/apps/web/dist /web
COPY --from=web /frontend/apps/admin/dist /admin

# ---- prod ------------------------------------------------------------------
# One process on one port: /api, the player SPA at /, the admin SPA at /admin.
# No Node, no GHC: the binary, the migrations, and the built SPAs.
FROM debian:bullseye-slim AS prod
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgmp10 libffi7 \
    && rm -rf /var/lib/apt/lists/*
# uid 1000, like the dev user. The e2e run mounts a tmpfs owned by that uid
# on /app/data, which is where the database goes.
RUN useradd --uid 1000 app && mkdir -p /app/data && chown app:app /app/data
WORKDIR /app
COPY --from=build /home/dev/out/monster-battle-hs ./
COPY migrations migrations
COPY seed seed
COPY --from=spa / public/
USER app
EXPOSE 3000
# Started directly, so it is PID 1, which gets no default reaction to a
# signal. Main handles SIGTERM itself: docker stop returns at once.
CMD ["/app/monster-battle-hs"]
