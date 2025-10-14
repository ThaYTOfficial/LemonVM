#!/usr/bin/env bash
set -euo pipefail

# === Environment variables (can be overridden by Pterodactyl) ===
VM_NAME="${VM_NAME:-win10}"
DISK_SIZE_GB="${DISK_SIZE_GB:-40}"
RAM_MB="${RAM_MB:-4096}"
CPU_CORES="${CPU_CORES:-2}"
BOOT="${BOOT:-iso}"
ISO_URL="${ISO_URL:-}"
# Automatically use Pterodactyl’s allocated port if provided
VNC_PORT="${VNC_PORT:-${SERVER_PORT:-6000}}"
EXTRA_QEMU_ARGS="${EXTRA_QEMU_ARGS:-}"

# === Paths (inside container) ===
VM_DIR="/home/container/vm/${VM_NAME}"
IMG_QCOW2="${VM_DIR}/${VM_NAME}.qcow2"
ISO_PATH="${VM_DIR}/boot.iso"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_VARS="${VM_DIR}/OVMF_VARS.fd"

mkdir -p "${VM_DIR}"

# === Copy writable OVMF vars file once ===
if [ ! -f "${OVMF_VARS}" ]; then
  cp /usr/share/OVMF/OVMF_VARS.fd "${OVMF_VARS}"
fi

# === Enable KVM if available ===
KVM_OPTS=""
if [ -e /dev/kvm ]; then
  KVM_OPTS="--enable-kvm -cpu host"
else
  echo "[INFO] KVM not available; using software emulation (TCG)"
  KVM_OPTS="-cpu qemu64"
fi

# === Configure VNC to bind on the allocated port ===
if ! [[ "${VNC_PORT}" =~ ^[0-9]+$ ]]; then
  echo "Invalid VNC_PORT='${VNC_PORT}', must be numeric."
  exit 1
fi

# QEMU’s -vnc uses display numbers (port = 5900 + display)
if [ "${VNC_PORT}" -ge 5900 ]; then
  VNC_DISPLAY=$(( VNC_PORT - 5900 ))
  VNC_OPT="-vnc 0.0.0.0:${VNC_DISPLAY}"
else
  # If the port is below 5900, bind directly
  VNC_OPT="-vnc 0.0.0.0:${VNC_PORT}"
fi

echo "[INFO] Using VNC port ${VNC_PORT} (display ${VNC_OPT})"

# === Prepare VM disk ===
if [ ! -f "${IMG_QCOW2}" ]; then
  echo "[INFO] Creating ${DISK_SIZE_GB}G qcow2 disk..."
  qemu-img create -f qcow2 "${IMG_QCOW2}" ${DISK_SIZE_GB}G
fi

# === Handle ISO ===
if [ "${BOOT}" = "iso" ]; then
  if [ -z "${ISO_URL}" ]; then
    echo "BOOT=iso but ISO_URL is empty. Please provide a valid ISO URL."
    exit 1
  fi
  if [ ! -f "${ISO_PATH}" ]; then
    echo "[INFO] Downloading installer ISO..."
    curl -L "${ISO_URL}" -o "${ISO_PATH}"
  fi
else
  echo "Unsupported BOOT mode '${BOOT}'. Use BOOT=iso."
  exit 1
fi

# === Networking (user-mode; allows internet inside VM) ===
NET_OPTS="-netdev user,id=n1 -device e1000,netdev=n1"

# === Graphics / Input ===
GRAPHICS_OPTS="-device VGA -device usb-ehci -device usb-tablet ${VNC_OPT}"

# === Run QEMU ===
echo "[INFO] Starting QEMU VM '${VM_NAME}'..."
exec qemu-system-x86_64 \
  ${KVM_OPTS} \
  -machine q35,accel=kvm:tcg \
  -smp "${CPU_CORES}" -m "${RAM_MB}" \
  -drive if=ide,file="${IMG_QCOW2}",format=qcow2,discard=unmap \
  -drive media=cdrom,file="${ISO_PATH}" \
  -drive if=pflash,format=raw,unit=0,readonly=on,file="${OVMF_CODE}" \
  -drive if=pflash,format=raw,unit=1,file="${OVMF_VARS}" \
  ${NET_OPTS} \
  ${GRAPHICS_OPTS} \
  ${EXTRA_QEMU_ARGS}
