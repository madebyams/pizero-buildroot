# syntax=docker/dockerfile:1.7
#
# Multi-stage build:
#   base      -> host packages Buildroot needs
#   toolchain -> clones Buildroot, builds just the cross-compiler + C library
#                (`make toolchain` only — skips building every other selected
#                package, so this is the fast path to a usable compiler;
#                cached via BuildKit cache mounts)
#   dev       -> lightweight image with the toolchain on PATH, for developing
#                and cross-compiling your applications
#                docker build --target dev -t buildroot-sdk .
#   image     -> takes the primed Buildroot tree from `toolchain`, drops your
#                compiled app(s) into a rootfs overlay, and runs `make` to
#                assemble the final image (this is where the rest of the
#                selected packages actually get built).
#                docker build --target image -t buildroot-image .
#
# Adjust these for your actual target board/toolchain:
ARG BUILDROOT_VERSION=master
ARG BR2_DEFCONFIG=raspberrypizero2w_64_defconfig

# Image to pull the built toolchain from instead of building it locally.
# Defaults to the `toolchain` stage below, so plain `docker build`/
# `podman build` still works unmodified. CI overrides this with an
# already-pushed image so the `dev`/`image` targets don't each have to
# rebuild the toolchain from source (and so kaniko doesn't have to hold
# two full copies of that stage on disk at once).
ARG TOOLCHAIN_IMAGE=toolchain

########################################
# base: host build dependencies
########################################
FROM ubuntu:22.04 AS base
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential git bc cpio file rsync unzip wget \
    python3 python3-dev libncurses-dev patch perl tar bzip2 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Several packages' ./configure scripts (e.g. host-tar) refuse to run as
# root, which is the default user in a container RUN step. A non-root
# builder user is the "correct" fix, but it fights BuildKit/buildah cache
# mounts (podman doesn't reliably honor uid/gid on `--mount=type=cache`,
# so the cache keeps coming back root-owned). FORCE_UNSAFE_CONFIGURE=1 is
# Buildroot's own documented escape hatch for exactly this containerized-
# root-build scenario.
ENV FORCE_UNSAFE_CONFIGURE=1

########################################
# toolchain: cross-compiler + C library only (fast, cached)
########################################
FROM base AS toolchain
ARG BUILDROOT_VERSION
ARG BR2_DEFCONFIG

WORKDIR /buildroot
RUN git clone --branch "${BUILDROOT_VERSION}" --depth 1 \
    https://gitlab.com/buildroot.org/buildroot.git .

# Enable ccache so config/package tweaks later don't recompile from scratch
RUN make "${BR2_DEFCONFIG}" && \
    sed -i '/^BR2_CCACHE/d' .config && \
    printf 'BR2_CCACHE=y\nBR2_CCACHE_DIR="/ccache"\n' >> .config && \
    make olddefconfig

# dl/ (package downloads) and /ccache persist across builds via BuildKit
# cache mounts, so re-running this stage after a source-only change is fast.
RUN --mount=type=cache,target=/buildroot/dl,sharing=locked \
    --mount=type=cache,target=/ccache,sharing=locked \
    make toolchain

########################################
# dev: standalone toolchain image for application development
########################################
FROM base AS dev
ARG TOOLCHAIN_IMAGE
# The internal toolchain isn't relocatable like the `make sdk` tarball is —
# its gcc specs/sysroot paths are baked to this exact location, so it's kept
# at the same absolute path rather than moved (e.g. to /opt/sdk).
COPY --from=${TOOLCHAIN_IMAGE} /buildroot/output/host /buildroot/output/host
ENV PATH="/buildroot/output/host/bin:${PATH}"
WORKDIR /work
# Find your compiler's exact name with: ls /buildroot/output/host/bin/*-gcc

########################################
# image: final rootfs/image build with your app baked in
########################################
FROM ${TOOLCHAIN_IMAGE} AS image

# Mirror the target rootfs layout under app-overlay/, e.g.
# app-overlay/usr/bin/myapp -> installed as /usr/bin/myapp on the target.
# Build the binaries against the `dev` stage's toolchain before running this.
COPY app-overlay/ /buildroot/board/rootfs-overlay/
RUN if grep -q '^BR2_ROOTFS_OVERLAY=' .config; then \
        sed -i 's#^BR2_ROOTFS_OVERLAY=.*#BR2_ROOTFS_OVERLAY="board/rootfs-overlay"#' .config; \
    else \
        echo 'BR2_ROOTFS_OVERLAY="board/rootfs-overlay"' >> .config; \
    fi && \
    make olddefconfig

RUN --mount=type=cache,target=/buildroot/dl,sharing=locked \
    --mount=type=cache,target=/ccache,sharing=locked \
    make
