#!/bin/bash
set -e

# === BASIC SETTINGS ===
VM_NAME="${VM_NAME:-tiny10}"
DISK_SIZE_GB="${DISK_SIZE_GB:-40}"
RAM_MB="${SERVER_MEMORY:-4096}"
CPU_CORES="${CPU_CORES:-2}"
ISO_URL="${ISO_URL:-https://archive.org/download/tiny10-NTDEV/Tiny10_x64.iso}"
VNC_PORT="${SERVER_PORT:-6000}"
VNC="${VNC:-1}"  # 1 = VNC install, 0 = headless

# === PATHS ===
VM_DIR="/home/container/vm/${VM_NAME}"
IMG_QCOW2="${VM_DIR}/${VM_NAME}.qcow2"
ISO_PATH="${VM_DIR}/installer.iso"

mkdir -p "${VM_DIR}"
cd "${VM_DIR}"

# === DOWNLOAD ISO IF MISSING ===
if [ ! -f "${ISO_PATH}" ]; then
  echo "[INFO] Downloading Tiny10 ISO..."
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
  echo "[WARN] KVM not available — running in software mode."
fi

# === VNC DISPLAY CALCULATION ===
VNC_DISPLAY=$((VNC_PORT - 5900))
VNC_OPT="-vnc 0.0.0.0:${VNC_DISPLAY}"

# === BASE QEMU OPTIONS ===
QEMU_BASE="-machine q35,accel=kvm:tcg -smp ${CPU_CORES} -m ${RAM_MB} -boot d \
-drive file=${IMG_QCOW2},format=qcow2,if=virtio -net nic,model=virtio -net user"

# === FIRST RUN: IF DISK IS EMPTY, BOOT INSTALLER ===
if [ ! -f "${VM_DIR}/.installed" ]; then
  echo "[INFO] Booting Tiny10 installer..."
  echo "[INFO] Connect via VNC at ${SERVER_IP:-0.0.0.0}:${VNC_PORT}"
  qemu-system-x86_64 ${KVM_OPTS} ${QEMU_BASE} \
    -drive media=cdrom,file="${ISO_PATH}" \
    -device usb-tablet -device VGA ${VNC_OPT} \
    || true
  echo "[INFO] When installation is complete, create /vm/${VM_NAME}/.installed or reboot to auto boot from disk."
  exit 0
fi

# === NORMAL RUN: BOOT INSTALLED DISK ===
echo "[INFO] Booting Tiny10 from qcow2 disk..."
qemu-system-x86_64 ${KVM_OPTS} ${QEMU_BASE} \
  -device usb-tablet -device VGA ${VNC_OPT}
