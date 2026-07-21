FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential ca-certificates curl fakeroot git libtinfo6 libxml2 \
        perl rsync sudo xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/theos /work \
    && chown -R ubuntu:ubuntu /opt/theos /work

USER ubuntu
ENV THEOS=/opt/theos

RUN git clone --depth=1 --recursive https://github.com/theos/theos.git "$THEOS" \
    && arch="$(uname -m)" \
    && curl -fsSL "https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-${arch}.tar.xz" \
       | tar -xJ -C "$THEOS/toolchain" \
    && "$THEOS/bin/install-sdk" latest

USER root
RUN git clone --depth=1 https://github.com/p0358/allemande.git /tmp/allemande \
    && g++ -std=c++20 -O2 -o /usr/local/bin/allemande /tmp/allemande/main.cpp \
    && rm -rf /tmp/allemande

USER ubuntu
WORKDIR /work
CMD ["make", "clean", "package", "FINALPACKAGE=1"]
