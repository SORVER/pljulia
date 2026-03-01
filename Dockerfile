# Pl/Julia Development Docker images
#
# Arg/Parameters:
#   BASE_IMAGE_VERSION=postgres:14
#   JULIA_MAJOR=1.12
#   JULIA_VERSION=1.12.5
#   JULIA_SHA256=41b84d727e4e96fbf3ed9e92fa195d773d247b9097f73fad688f8b699758bae7
#   PLJULIA_REGRESSION=YES
#   PLJULIA_PACKAGES="CpuId,Primes"
#
# ---------------------------------
# BASE_IMAGE_VERSION = Base Docker images:
#   Valid values:  `postgres` and `postgis/postgis` debian versions
#   postgres: https://hub.docker.com/_/postgres?tab=tags&page=1&ordering=last_updated&name=buster  (debian based!)
#   postgis:  https://registry.hub.docker.com/r/postgis/postgis/tags?page=1&ordering=last_updated
#
# BASE_IMAGE_VERSION - Status:
# - postgres:9.6            : Not working yet
# - postgres:10             : Not working yet
# - postgres:11             : Not working yet
# - postgres:12             : OK
# - postgres:13             : OK
# - postgres:14             : OK
# - postgres:15             : OK
# - postgis/postgis:13-3.1  : Should work
#

ARG BASE_IMAGE_VERSION=postgres:14
FROM $BASE_IMAGE_VERSION as builder

# add debian mirror - for a faster build
#ARG APT_MIRROR=cdn-fastly.deb.debian.org
ARG APT_MIRROR=ftp.de.debian.org
RUN if [ -f /etc/apt/sources.list ]; then \
      sed -ri "s/(httpredir|deb).debian.org/${APT_MIRROR:-deb.debian.org}/g" /etc/apt/sources.list \
   && sed -ri "s/(security).debian.org/${APT_MIRROR:-security.debian.org}/g" /etc/apt/sources.list \
   && cat /etc/apt/sources.list ; \
    fi

# Install build dependencies
RUN    apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        postgresql-server-dev-$PG_MAJOR \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# Julia Versions:
ARG JULIA_MAJOR=1.12
ARG JULIA_VERSION=1.12.5
ARG JULIA_SHA256=41b84d727e4e96fbf3ed9e92fa195d773d247b9097f73fad688f8b699758bae7
ARG PLJULIA_PACKAGES="CpuId,Primes"

# Install Julia
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    \
    JULIA_MAJOR=$JULIA_MAJOR \
    JULIA_VERSION=$JULIA_VERSION \
    JULIA_SHA256=$JULIA_SHA256 \
    PLJULIA_PACKAGES=$PLJULIA_PACKAGES \
    \
    JULIA_DIR=/usr/local/julia \
    JULIA_PATH=/usr/local/julia

RUN set -eux; \
    mkdir ${JULIA_DIR} \
    && cd /tmp  \
    && curl -fL -o julia.tar.gz https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_MAJOR}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz \
    && echo "$JULIA_SHA256 julia.tar.gz" | sha256sum -c - \
    && tar xzf julia.tar.gz -C ${JULIA_DIR} --strip-components=1 \
    && rm /tmp/julia.tar.gz \
    && ln -fs ${JULIA_DIR}/bin/julia /usr/local/bin/julia

# Add julia packages from ENV["PLJULIA_PACKAGES"]
# - this is a comma separated package name lists
RUN set -eux; \
    if [ ! -z "$PLJULIA_PACKAGES" ]; then \
      echo "install: ${PLJULIA_PACKAGES}"; \
      julia -e 'using Pkg; \
                for (index, package_name) in enumerate( split(ENV["PLJULIA_PACKAGES"],",") ) ; \
                   println("$index $package_name") ; \
                   Pkg.add("$package_name"); \
                end ; \
                Pkg.instantiate(); \
                VERSION >= v"1.6.0" ? Pkg.precompile(strict=true) : Pkg.API.precompile(); \
               '; \
      julia -e "using ${PLJULIA_PACKAGES};" ; \
    fi ; \
    julia -e 'using Pkg, InteractiveUtils; Pkg.status(); versioninfo(); \
              if "CpuId" in split(ENV["PLJULIA_PACKAGES"],",") \
                using CpuId; println(cpuinfo()); \
              end;'; \
    rm -rf "~/.julia/registries/General"

# default :  add local code
ADD .   /pljulia

# -------- Build & Install ----------
ENV USE_PGXS=1
RUN set -eux; \
    cd /pljulia \
        && make clean \
        && make \
        && make install

# ------Regression tests---
ARG PLJULIA_REGRESSION=YES
ENV PLJULIA_REGRESSION=${PLJULIA_REGRESSION}
RUN set -eux; \
    if [ "$PLJULIA_REGRESSION" = "YES" ]; then  \
           cd /pljulia \
        && mkdir /tempdb \
        && chown -R postgres:postgres /tempdb \
        && su postgres -c 'pg_ctl -D /tempdb init' \
        && su postgres -c 'pg_ctl -D /tempdb start' \
        && make installcheck PGUSER=postgres \
        && su postgres -c 'pg_ctl -D /tempdb --mode=immediate stop' \
        && rm -rf /tempdb ; \
    fi
# -----------------------------