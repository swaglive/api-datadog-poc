ARG         base=python:3.11.6-alpine3.18

###

FROM        ${base} AS jemalloc

ARG         MAKEFLAGS
ARG         JEMALLOC_VERSION=5.3.0

ENV         MAKEFLAGS=${MAKEFLAGS}

RUN         apk add --no-cache --virtual .build-deps \
                curl \
                autoconf \
                build-base && \
            curl -sfL https://github.com/jemalloc/jemalloc/archive/$JEMALLOC_VERSION.tar.gz | tar xz && \
            ( \
                cd jemalloc-$JEMALLOC_VERSION && \
                autoconf && \
                ./configure && \
                make && \
                make install \
            ) && \
            apk del .build-deps

###

FROM        ${base} AS poetry

ARG         MAKEFLAGS
ARG         POETRY_VERSION=1.6.1

ENV         MAKEFLAGS=${MAKEFLAGS}
ENV         POETRY_VERSION=${POETRY_VERSION}

RUN         apk add --no-cache --virtual .build-deps \
                curl \
                build-base \
                libffi-dev && \
            curl -sSL https://install.python-poetry.org | python && \
            apk del .build-deps

###

FROM        ${base} AS builder-linux-amd64

ENV         POETRY_UWSGI_FORCE_REBUILD=1
ENV         POETRY_INSTALLER_NO_BINARY="python-rapidjson"
ENV         POETRY_CPPFLAGS="-DRAPIDJSON_SSE42=1"
ENV         POETRY_CFLAGS="-msse4.2"

###

FROM        ${base} AS builder-linux-arm64

ENV         POETRY_UWSGI_FORCE_REBUILD=1
ENV         POETRY_INSTALLER_NO_BINARY="python-rapidjson,gevent"
ENV         POETRY_CPPFLAGS="-RAPIDJSON_NEON=1"
ENV         POETRY_CFLAGS=

###

FROM        builder-linux-arm64 AS builder-linux-arm64-v8

ENV         POETRY_CFLAGS="-march=armv8-a+simd"

###

FROM        builder-${TARGETOS}-${TARGETARCH}${TARGETVARIANT:+-$TARGETVARIANT} AS builder

ARG         MAKEFLAGS
ARG         PIP_DISABLE_PIP_VERSION_CHECK=on
ARG         PIP_DEFAULT_TIMEOUT=10

ENV         PATH=/root/.local/bin:$PATH
ENV         MAKEFLAGS=${MAKEFLAGS}

ENV         PIP_DISABLE_PIP_VERSION_CHECK=${PIP_DISABLE_PIP_VERSION_CHECK}
ENV         PIP_DEFAULT_TIMEOUT=${PIP_DEFAULT_TIMEOUT}

ENV         POETRY_VIRTUALENVS_CREATE=false
ENV         POETRY_INSTALLER_MAX_WORKERS=100

ENV         UWSGI_PROFILE_OVERRIDE=malloc_implementation=jemalloc

ENV         PYYAML_FORCE_LIBYAML=1
ENV         PYYAML_FORCE_CYTHON=1

WORKDIR     /usr/src/app

COPY        --from=jemalloc /usr/local/lib /usr/local/lib
COPY        --from=jemalloc /usr/local/include /usr/local/include
COPY        --from=poetry /root/.local /root/.local

COPY        pyproject.toml .
COPY        poetry.lock .

RUN         apk add --no-cache --virtual .build-deps \
                build-base \
                openssl-dev \
                libffi-dev \
                zlib-dev \
                linux-headers \
                pcre-dev \
                libxml2-dev \
                libxslt-dev \
                snappy-dev \
                bash \
                curl \
                rust \
                cargo \
                yaml-dev && \
            UWSGI_FORCE_REBUILD=${POETRY_UWSGI_FORCE_REBUILD} CPPFLAGS="${POETRY_CPPFLAGS}" CFLAGS="${POETRY_CFLAGS}" poetry install -vv -n --only=main --no-root && \
            # Whitelist removal
            find /usr/local -type f -name "*.pyc" -delete && \
            find /usr/local -type f -name "*.pyo" -delete && \
            find /usr/local -type d -name "__pycache__" -delete && \
            find /usr/local -type d -name "tests" -exec rm -rf '{}' + && \
            apk del .build-deps

###

FROM        ${base}

ENV         PYTHONPATH=./libs/
ENV         PYTHONSTARTUP=startup.py
ENV         PYTHONOPTIMIZE=2
ENV         PYTHONUNBUFFERED=1
ENV         FLASK_APP=app.py
ENV         FLASK_SKIP_DOTENV=1
ENV         GEVENT_RESOLVER=ares
ENV         GEVENT_LOOP=libev-cffi
ENV         TERM=xterm
ENV         POETRY_VIRTUALENVS_CREATE=false
ENV         LD_PRELOAD=/usr/local/lib/libjemalloc.so
ENV         PATH=/root/.local/bin:$PATH

WORKDIR     /usr/src/app

EXPOSE      8000/tcp
ENTRYPOINT  ["flask"]
CMD         ["run", "-h", "0.0.0.0", "-p", "8000", "--debugger", "--reload", "--with-threads"]

            # Add runtime dependencies
RUN         apk add --no-cache --virtual .run-deps \
                libstdc++ \
                openssl \
                pcre \
                libxslt \
                curl \
                yaml

COPY        --from=poetry /root/.local /root/.local
COPY        --from=builder /usr/local /usr/local
#            # HACK: celery 5.0's purge errors if -Q flag is used
#RUN         sed -i 's|queues = queues or set()|queues = set(queues or set())|' /usr/local/lib/python3.11/site-packages/celery/bin/purge.py
COPY        . .
