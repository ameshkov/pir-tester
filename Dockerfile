# syntax=docker/dockerfile:1

# -- Stage 1: Periphery (build from source) -------------------------------
# Periphery does not publish Linux binaries, so build from source.
FROM swift:6.2-jammy AS periphery-builder
ARG PERIPHERY_VERSION=3.8.0
RUN apt-get update \
    && apt-get install -y git make \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${PERIPHERY_VERSION}" \
        https://github.com/peripheryapp/periphery.git /tmp/periphery \
    && swift build -c release --product periphery \
        --package-path /tmp/periphery \
    && install /tmp/periphery/.build/release/periphery /usr/local/bin/periphery \
    && rm -rf /tmp/periphery

# -- Stage 2: Final image (Swift + SwiftLint + Periphery + Node) ----------
# The norionomura/swiftlint image bundles SwiftLint (with compatible GLIBC)
# alongside the Swift 6.2.2 toolchain, so we use it directly as the base.
FROM norionomura/swiftlint:0.63.2_swift-6.2.2 AS base

# Copy Periphery built in the previous stage.
COPY --from=periphery-builder /usr/local/bin/periphery /usr/local/bin/periphery

# System packages needed by the CI pipeline.
RUN apt-get update \
    && apt-get install -y make curl unzip git \
    && rm -rf /var/lib/apt/lists/*

# Node.js for markdownlint-cli (via npx).
ARG NODE_VERSION=22
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Preinstall markdownlint globally so it doesn't need downloading per run.
RUN npm install -g markdownlint-cli \
    && rm -rf /root/.npm

CMD ["/bin/bash"]
