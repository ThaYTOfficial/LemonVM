
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    qemu-system-x86 qemu-utils ovmf curl ca-certificates genisoimage tini \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /vm && useradd -m -d /home/container container
WORKDIR /home/container
COPY start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh
ENV VM_NAME=win10 \
    DISK_SIZE_GB=40 \
    RAM_MB=4096 \
    CPU_CORES=2 \
    BOOT=iso \
    ISO_URL="https://archive.org/download/tiny-10-23-h2/tiny10%20x64%2023h2.iso" \
    VNC_PORT=5900 \
    EXTRA_QEMU_ARGS=""

# VNC default
EXPOSE 5900

ENTRYPOINT ["/usr/bin/tini","--"]
CMD ["/usr/local/bin/start.sh"]
