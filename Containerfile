# Copyright (C) 2023-2026 Matinee
# Author: Michael André Reber
# License: AGPL-3.0-or-later
# https://github.com/getmatinee/matinee

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        clang \
        cmake \
        curl \
        git \
        libass-dev \
        libchromaprint-dev \
        libdav1d-dev \
        libdrm-dev \
        libfontconfig-dev \
        libfreetype-dev \
        libfribidi-dev \
        libharfbuzz-dev \
        libmp3lame-dev \
        libnuma-dev \
        libopus-dev \
        libsvtav1enc-dev \
        libva-dev \
        libvorbis-dev \
        libvpx-dev \
        libwebp-dev \
        libx264-dev \
        libx265-dev \
        libzimg-dev \
        nasm \
        ocl-icd-opencl-dev \
        patch \
        pkg-config \
        xz-utils \
        yasm \
        zstd \
    && rm -rf /var/lib/apt/lists/*

COPY patches/ /opt/matinee-ffmpeg-patches/
COPY versions.env common.sh build-debian.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/build-debian.sh && \
    PREFIX=/opt/matinee-ffmpeg PATCHDIR=/opt/matinee-ffmpeg-patches \
    build-debian.sh
