# Build stage
FROM debian:bookworm-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    git \
    pkg-config \
    libnotmuch-dev \
    libgmime-3.0-dev \
    libglib2.0-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Zig 0.15.2
RUN curl -fL https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz | tar -xJ -C /usr/local && \
    ln -s /usr/local/zig-x86_64-linux-0.15.2/zig /usr/local/bin/zig

# Copy source code
WORKDIR /build
COPY . .

# Build in release mode with baseline CPU features for portability
RUN zig build -Doptimize=ReleaseSafe -Dcpu=baseline

# Runtime stage
FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnotmuch5 \
    libgmime-3.0-0 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Copy binary and static files
COPY --from=builder /build/zig-out/bin/zetviel /usr/local/bin/zetviel
COPY --from=builder /build/static /app/static

WORKDIR /app

# Set environment variable for notmuch database
ENV NOTMUCH_PATH=/mail

EXPOSE 5000

ENTRYPOINT ["/usr/local/bin/zetviel"]
