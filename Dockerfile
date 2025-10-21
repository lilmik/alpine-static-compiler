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
    apk update && \
    apk add --no-cache \
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
    file \
    python3 \
    py3-pip \
    autoconf \
    autoconf-archive \
    automake \
    libtool  \
    openssh-server \
    tzdata && \
    apk cache clean

# ==============================================
# 2. Python相关配置
# ==============================================
# Python 编译依赖安装（补全缺失的包主要是opencv编译会缺的内容）
RUN apk add --no-cache \
    # 基础编译工具
    patchelf \
    ccache \
    clang \
    # Python 开发
    python3-dev \
    readline-dev \
    ncurses-dev \
    bzip2-dev \
    sqlite-dev \
    # 数学和科学计算
    gfortran \
    openblas-dev \
    lapack-dev \
    # 图像处理
    libjpeg-turbo-dev \
    libpng-dev \
    tiff-dev \
    libwebp-dev \
    jasper-dev \
    openexr-dev \
    gdal-dev \
    gtk+3.0-dev \
    # 视频处理
    ffmpeg-dev \
    v4l-utils-dev \
    x264-dev \
    xvidcore-dev \
    # 兼容性库
    libc6-compat \
    libstdc++ \
    # 其他开发库
    libffi-dev \
    xz-dev \
    # 之前已有的包
    jpeg-dev \
    freetype-dev \
    lcms2-dev \
    openjpeg-dev \
    tk-dev \
    tcl-dev \
    harfbuzz-dev \
    fribidi-dev 

# Python 包安装（优化编译效率）
COPY requirements.txt /tmp/
RUN export MAKEFLAGS="-j$(nproc)" && \
    export CMAKE_BUILD_PARALLEL_LEVEL=$(nproc) && \
    export NINJA_NUM_JOBS=$(nproc) && \
    python -m venv /opt/venv && \
    . /opt/venv/bin/activate && \
    pip install --upgrade pip && \
    pip install --no-cache-dir -r /tmp/requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple/

# 清理层
RUN rm -f /tmp/requirements.txt && \
    . /opt/venv/bin/activate && \
    pip cache purge && \
    rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# 设置登录时自动激活虚拟环境
RUN echo ". /opt/venv/bin/activate" >> /root/.profile

# ==============================================
# 3. vcpkg相关配置 - 仅包含vcpkg所需环境变量和架构适配
# ==============================================
# 克隆vcpkg
RUN git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg

# 架构识别与triplet设置
ENV \
    VCPKG_FORCE_SYSTEM_BINARIES=1 \
    VCPKG_LIBRARY_LINKAGE=static \
    VCPKG_ROOT=/opt/vcpkg

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
# # 安装crow，会自动安装 asio
RUN /opt/vcpkg/vcpkg install crow
# # 安装icu库,会自动安装i18n
RUN /opt/vcpkg/vcpkg install icu 

# # 统一清理缓存
RUN set -eux; \
    cache_dir="${VCPKG_DEFAULT_BINARY_CACHE:-${XDG_CACHE_HOME:-/root/.cache}/vcpkg/archives}"; \
    echo "Pruning vcpkg binary cache at: ${cache_dir}"; \
    rm -rf "${cache_dir}" || true; \
    rm -rf "${VCPKG_ROOT}/buildtrees" "${VCPKG_ROOT}/packages" "${VCPKG_ROOT}/downloads"

# ==============================================
# 4. 工作目录配置
# ==============================================
# SSH 配置 - 完全免密登录
RUN ssh-keygen -A && \
    # 设置空密码（直接修改shadow文件）
    sed -i 's/^root:[^:]*:/root::/' /etc/shadow && \
    # 完全重写 sshd_config
    echo "PermitRootLogin yes" > /etc/ssh/sshd_config && \
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "PermitEmptyPasswords yes" >> /etc/ssh/sshd_config && \
    echo "ChallengeResponseAuthentication no" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication no" >> /etc/ssh/sshd_config && \
    echo "UsePAM no" >> /etc/ssh/sshd_config && \
    mkdir -p /run/sshd /var/empty/sshd && \
    chmod 0755 /run/sshd


# 工作目录
RUN mkdir -p /app && chmod 777 /app
WORKDIR /app

# 设置登录时自动进入工作目录（支持sh和bash）
RUN echo "cd /app" >> /root/.profile && \
    echo "cd /app" >> /root/.bashrc && \
    # 确保.bashrc被source
    echo "if [ -f ~/.bashrc ]; then . ~/.bashrc; fi" >> /root/.profile

# 设置上海时区,默认使用宿主机时间
RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone


# 启动命令
CMD ["/usr/sbin/sshd", "-D"]