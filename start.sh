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

# === VNC DISPLAY CALC ===
VNC_DISPLAY=$((VNC_PORT - 5900))
VNC_OPT="-vnc 0.0.0.0:${VNC_DISPLAY}"

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
    # headless install (not common for Windows; keep for parity)
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
