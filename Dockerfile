ARG UBUNTU_VER=20.04

FROM ghcr.io/by275/base:ubuntu${UBUNTU_VER} AS base
FROM ghcr.io/by275/base:ubuntu AS prebuilt

# 
# BUILD
# 
FROM base AS builder

ARG KAVITA_VER=v0.5.4
ARG ATIVAK_VER

ARG DEBIAN_FRONTEND="noninteractive"

# add s6 overlay
COPY --from=prebuilt /s6/ /bar/
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/adduser /bar/etc/cont-init.d/10-adduser
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/wait-for-mnt /bar/etc/cont-init.d/20-init-wait-for-mnt

RUN \
    echo "**** directories ****" && \
    mkdir -p \
        /bar/defaults \
        /bar/ativak \
        /bar/kavita

# add kavita
RUN \
    ARCH="$(dpkg --print-architecture)" && \
    if [ $ARCH = "amd64" ]; then KAVITA_ARCH="x64"; \
    elif [ $ARCH = "arm64" ]; then KAVITA_ARCH="arm64"; \
    elif [ $ARCH = "armhf" ]; then KAVITA_ARCH="arm"; \
    else echo "UNKNOWN ARCH: $ARCH" && exit 1; fi && \
    echo "**** installing kavita ${KAVITA_VER} ${KAVITA_ARCH} ****" && \
    downloadURL="https://github.com/Kareadita/Kavita/releases/download/${KAVITA_VER}/kavita-linux-${KAVITA_ARCH}.tar.gz" && \
    curl -sL "$downloadURL" | tar -zxf - -C /bar/kavita --strip-components=1 && \
    mv /bar/kavita/config/appsettings.json /bar/defaults/ && \
    rm -rf /bar/kavita/config

# apply patch
COPY patch/API.dll_0.5.4.0_patch_1 /bar/kavita/API.dll
COPY patch/API.pdb_0.5.4.0_patch_1 /bar/kavita/API.pdb

# add ativak
RUN \
    ARCH="$(dpkg --print-architecture)" && \
    if [ $ARCH = "amd64" ]; then KAVITA_ARCH="x64"; \
    elif [ $ARCH = "arm64" ]; then KAVITA_ARCH="arm64"; \
    elif [ $ARCH = "armhf" ]; then KAVITA_ARCH="arm"; \
    else echo "UNKNOWN ARCH: $ARCH" && exit 1; fi && \
    echo "**** installing kavita ${ATIVAK_VER} ${KAVITA_ARCH} ****" && \
    downloadURL="https://github.com/Kareadita/Kavita/releases/download/${ATIVAK_VER}/kavita-linux-${KAVITA_ARCH}.tar.gz" && \
    curl -sL "$downloadURL" | tar -zxf - -C /bar/ativak --strip-components=1 && \
    rm -rf /bar/ativak/config

# add overlayfs-tools
RUN \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        git libattr1-dev gcc make && \
    git clone https://github.com/kmxz/overlayfs-tools /tmp/ofs && \
    cd /tmp/ofs && \
    make && \
    mkdir -p /bar/usr/local/bin && \
    mv overlay /bar/usr/local/bin/

# add local files
COPY root/ /bar/


RUN \
    echo "**** permissions ****" && \
    chmod a+x \
        /bar/kavita/Kavita \
        /bar/ativak/Kavita \
        /bar/usr/local/bin/* \
        /bar/etc/cont-init.d/* \
        /bar/etc/cont-finish.d/* \
        /bar/etc/s6-overlay/s6-rc.d/*/run

RUN \
    echo "**** s6: resolve dependencies ****" && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do mkdir -p "$dir/dependencies.d"; done && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "$dir/dependencies.d/legacy-cont-init"; done && \
    echo "**** s6: create a new bundled service ****" && \
    mkdir -p /tmp/app/contents.d && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "/tmp/app/contents.d/$(basename "$dir")"; done && \
    echo "bundle" > /tmp/app/type && \
    mv /tmp/app /bar/etc/s6-overlay/s6-rc.d/app && \
    echo "**** s6: deploy services ****" && \
    rm /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/legacy-services && \
    touch /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/app

# 
# RELEASE
# 
FROM base
LABEL maintainer="by275"
LABEL org.opencontainers.image.source https://github.com/by275/docker-kavita

ARG DEBIAN_FRONTEND="noninteractive"

# install packages
RUN \
    echo "**** install runtime packages ****" && \
    apt-get update && \
    apt-get install -yq --no-install-recommends \
        ca-certificates \
        curl \
        fuse3 \
        jq \
        libgdiplus \
        libicu-dev \
        libssl1.1 \
        sqlite3 \
        && \
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf && \
    echo "**** cleanup ****" && \
    apt-get clean autoclean && \
    apt-get autoremove -y && \
    rm -rf \
        /root/.cache \
        /tmp/* \
        /var/tmp/* \
        /var/cache/* \
        /var/lib/apt/lists/*

# add build artifacts
COPY --from=builder /bar/ /

# environment settings
ENV \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    TZ=Asia/Seoul \
    DOTNET_RUNNING_IN_CONTAINER=true \
    KAVITA_CONFIG_DIR="/kavita/config" \
    KAVITA_CONFIG_FILE="/kavita/config/appsettings.json"

EXPOSE 5000

WORKDIR ${KAVITA_CONFIG_DIR}
VOLUME ${KAVITA_CONFIG_DIR} /overlay

# HEALTHCHECK --interval=30s --timeout=15s --start-period=30s --retries=3 \
#     CMD curl --fail http://localhost:5000/api/health || exit 1

ENTRYPOINT ["/init"]
