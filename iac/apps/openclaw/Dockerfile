# OpenClaw with signal-cli for Signal messaging channel
# Built on the official OpenClaw image, adds the native signal-cli binary
# which requires no JVM runtime.
FROM ghcr.io/openclaw/openclaw:latest

ARG SIGNAL_CLI_VERSION=0.14.1

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -fsSL "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}-Linux-native.tar.gz" \
       | tar xz -C /opt \
    && ln -s "/opt/signal-cli-${SIGNAL_CLI_VERSION}-native/bin/signal-cli" /usr/local/bin/signal-cli \
    && apt-get purge -y curl \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

USER 1000
