# 基础镜像：Alpine 3.19
FROM alpine:3.19

# ==============================================
# 1. 系统工具（apk）相关配置 - 仅包含apk所需环境变量
# ==============================================
# 定义apk命令的额外参数（放在apk操作前）
ENV APK_EXTRA_ARGS="--no-interactive"

# 配置Alpine源 + 安装系统依赖（使用上方定义的apk环境变量）
RUN echo "https://mirrors.ustc.edu.cn/alpine/v3.19/main" > /etc/apk/repositories && \
    echo "https://mirrors.ustc.edu.cn/alpine/v3.19/community" >> /etc/apk/repositories && \
    apk update --no-cache && \
    apk add --no-cache $APK_EXTRA_ARGS \
    ca-certificates \
    bash \
    curl \
    wget \
    git \
    vim \
    zip \
    unzip \
    tar \
    ninja \
    build-base \
    cmake \
    pkgconf \
    musl-dev \
    zlib-dev \
    openssl-dev \
    perl \
    linux-headers \
    file && \
    apk cache clean

# ==============================================
# 2. vcpkg相关配置 - 仅包含vcpkg所需环境变量和架构适配
# ==============================================
# 克隆vcpkg
RUN git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg

# 架构识别与triplet设置
# ENV \
#     VCPKG_FORCE_SYSTEM_BINARIES=1 \
#     VCPKG_LIBRARY_LINKAGE=static \
#     VCPKG_ROOT=/opt/vcpkg \
#     VCPKG_DEFAULT_TRIPLET=x64-linux

ENV \
    VCPKG_FORCE_SYSTEM_BINARIES=1 \
    VCPKG_LIBRARY_LINKAGE=static \
    VCPKG_ROOT=/opt/vcpkg

# # 架构判断并设置triplet，写入shell配置(这个实际测试并未生效,反倒是在arm64架构中会导致编译成x64-linux架构)
# RUN case $TARGETARCH in \
#         arm64) TRIPLET=arm64-linux ;; \
#         amd64) TRIPLET=x64-linux ;; \
#         *) TRIPLET=x64-linux ;; \
#     esac && \
#     echo "export VCPKG_DEFAULT_TRIPLET=$TRIPLET" >> /root/.bash_profile && \
#     echo "export VCPKG_DEFAULT_TRIPLET=$TRIPLET" >> /root/.profile

# 安装vcpkg
RUN bash /opt/vcpkg/bootstrap-vcpkg.sh

# 将vcpkg路径添加到PATH
RUN echo "export PATH=\"${VCPKG_ROOT}:\$PATH\"" >> /root/.bash_profile && \
    echo "export PATH=\"${VCPKG_ROOT}:\$PATH\"" >> /root/.profile


# # 执行vcpkg安装
RUN /opt/vcpkg/vcpkg install curl
RUN /opt/vcpkg/vcpkg install sqlite3
RUN /opt/vcpkg/vcpkg install openssl
RUN /opt/vcpkg/vcpkg install zlib
RUN /opt/vcpkg/vcpkg install asio

# ===============================================
# 追加的内容,不想从头构建编译,太费时间,未来大版本更新时再考虑合并
# ===============================================


# # 安装icu和libiconv以支持国际化
RUN apk update --no-cache && \
    apk add \
    python3 \
    autoconf \
    autoconf-archive \
    automake \
    libtool && \
    apk cache clean

# # 安装icu库,会自动安装i18n
RUN /opt/vcpkg/vcpkg install icu 

# # 安装crow
RUN /opt/vcpkg/vcpkg install crow

# ===============================================
# 追加的内容,不想从头构建编译,太费时间,未来大版本更新时再考虑合并
# ===============================================

# # 统一清理缓存
RUN set -eux; \
    cache_dir="${VCPKG_DEFAULT_BINARY_CACHE:-${XDG_CACHE_HOME:-/root/.cache}/vcpkg/archives}"; \
    echo "Pruning vcpkg binary cache at: ${cache_dir}"; \
    rm -rf "${cache_dir}" || true; \
    rm -rf "${VCPKG_ROOT}/buildtrees" "${VCPKG_ROOT}/packages" "${VCPKG_ROOT}/downloads"

# ==============================================
# 3. 工作目录配置
# ==============================================
RUN mkdir -p /app && \
    chmod 775 /app
WORKDIR /app

# 设置时区为上海并配置网络时间同步
RUN set -eux; \
    # 安装必要的包
    apk add --no-cache tzdata openntpd; \
    # 设置时区为亚洲/上海
    ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    echo "Asia/Shanghai" > /etc/timezone; \
    # 配置多个可靠的NTP服务器（国内优先）
    echo "server ntp.aliyun.com" > /etc/ntpd.conf; \
    echo "server time1.cloud.tencent.com" >> /etc/ntpd.conf; \
    echo "server ntp.ntsc.ac.cn" >> /etc/ntpd.conf; \
    echo "server pool.ntp.org" >> /etc/ntpd.conf; \
    # 创建时间同步脚本
    echo '#!/bin/sh' > /usr/local/bin/sync-time.sh; \
    echo 'ntpd -d -q -n' >> /usr/local/bin/sync-time.sh; \
    chmod +x /usr/local/bin/sync-time.sh; \
    # 让bash登录时自动同步时间（覆盖bash和ssh登录）
    echo '/usr/local/bin/sync-time.sh' >> /root/.bashrc; \
    # 让非登录shell也同步时间（覆盖docker exec bash的情况）
    echo '/usr/local/bin/sync-time.sh' >> /etc/profile.d/sync-time.sh; \
    chmod +x /etc/profile.d/sync-time.sh;

# 容器启动命令
CMD ["/bin/sh", "-c", "/usr/local/bin/sync-time.sh && exec $0 $@"]
