#!/bin/bash
set -e

# === BASIC SETTINGS ===
VM_NAME="${VM_NAME:-win10}"                # or tiny10
DISK_SIZE_GB="${DISK_SIZE_GB:-40}"
RAM_MB="${SERVER_MEMORY:-4096}"
CPU_CORES="${CPU_CORES:-2}"
ISO_URL="${ISO_URL:-https://example.com/Tiny10_x64.iso}"
VNC_PORT="${SERVER_PORT:-6000}"            # Pterodactyl allocates this
VNC="${VNC:-1}"                            # 1 = VNC GUI install, 0 = headless
MARK_FILE=".installed"                     # marker to skip installer on next run

# === PATHS ===
VM_DIR="/home/container/vm/${VM_NAME}"
IMG_QCOW2="${VM_DIR}/${VM_NAME}.qcow2"
ISO_PATH="${VM_DIR}/installer.iso"

mkdir -p "${VM_DIR}"
cd "${VM_DIR}"

# === DOWNLOAD ISO IF MISSING ===
if [ ! -f "${ISO_PATH}" ]; then
  echo "[INFO] Downloading installer ISO..."
  curl -L "${ISO_URL}" -o "${ISO_PATH}"
fi

# === CREATE DISK IF MISSING ===
if [ ! -f "${IMG_QCOW2}" ]; then
  echo "[INFO] Creating ${DISK_SIZE_GB}G qcow2 disk..."
  qemu-img create -f qcow2 "${IMG_QCOW2}" ${DISK_SIZE_GB}G
fi

# === KVM CHECK ===
if [ -e /dev/kvm ]; then
  KVM_OPTS="--enable-kvm -cpu host"
else
  KVM_OPTS="-cpu qemu64"
  echo "[WARN] KVM not available — using software emulation (TCG)."
fi

# === VNC BINDING / PROXY ===
# QEMU expects a DISPLAY (port = 5900 + DISPLAY). If your allocated port is <5900,
# we bind QEMU to :0 (5900) and forward $VNC_PORT -> 5900 using socat.
if ! [[ "${VNC_PORT}" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] SERVER_PORT/VNC_PORT must be numeric (got: '${VNC_PORT}')."
  exit 1
fi

VNC_FORWARD_PID=""
if [ "${VNC_PORT}" -ge 5900 ]; then
  VNC_DISPLAY=$(( VNC_PORT - 5900 ))
  VNC_OPT="-vnc 0.0.0.0:${VNC_DISPLAY}"
  echo "[INFO] VNC will listen directly on ${VNC_PORT} (display :${VNC_DISPLAY})"
else
  # Need socat to proxy container:$VNC_PORT -> 127.0.0.1:5900
  if ! command -v socat >/dev/null 2>&1; then
    echo "[ERROR] socat is required for ports < 5900. Install socat in the image."
    exit 1
  fi
  VNC_OPT="-vnc 127.0.0.1:0"  # QEMU listens on 127.0.0.1:5900 (display :0)
  echo "[INFO] VNC will listen on internal 5900 (display :0); proxying ${VNC_PORT} -> 5900 with socat"
  # Start TCP forwarder in background
  socat TCP-LISTEN:${VNC_PORT},fork,reuseaddr TCP:127.0.0.1:5900 &
  VNC_FORWARD_PID=$!
fi

# Clean up proxy on exit
cleanup() {
  if [ -n "${VNC_FORWARD_PID}" ]; then
    kill "${VNC_FORWARD_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# === Base hardware (installer-friendly: IDE disk + e1000 NIC) ===
# USB tablet needs a USB controller; add usb-ehci then usb-tablet
BASE_HW="-machine q35,accel=kvm:tcg -smp ${CPU_CORES} -m ${RAM_MB} \
 -drive if=ide,file=${IMG_QCOW2},format=qcow2,discard=unmap \
 -net nic,model=e1000 -net user \
 -device VGA -device usb-ehci -device usb-tablet"

# === FIRST RUN: INSTALLER ===
if [ ! -f "${MARK_FILE}" ]; then
  echo "[INFO] Booting installer. Connect VNC at ${SERVER_IP:-0.0.0.0}:${VNC_PORT}"
  if [ "${VNC}" = "1" ]; then
    qemu-system-x86_64 ${KVM_OPTS} ${BASE_HW} \
      -boot d \
      -drive media=cdrom,file="${ISO_PATH}" \
      ${VNC_OPT} || true
  else
    # headless install (not typical for Windows)
    qemu-system-x86_64 ${KVM_OPTS} ${BASE_HW} \
      -boot d \
      -drive media=cdrom,file="${ISO_PATH}" \
      -nographic || true
  fi

  echo "[INFO] When installation is complete and the VM is shut down, create the marker to boot from disk:"
  echo "       touch ${VM_DIR}/${MARK_FILE}"
  exit 0
fi

# === NORMAL BOOT FROM DISK (post-install) ===
echo "[INFO] Booting installed system from ${IMG_QCOW2}. VNC at ${SERVER_IP:-0.0.0.0}:${VNC_PORT}"
if [ "${VNC}" = "1" ]; then
  exec qemu-system-x86_64 ${KVM_OPTS} ${BASE_HW} ${VNC_OPT}
else
  exec qemu-system-x86_64 ${KVM_OPTS} ${BASE_HW} -nographic
fi
