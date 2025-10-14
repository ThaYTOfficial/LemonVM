#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${VM_NAME:-win10}"
DISK_SIZE_GB="${DISK_SIZE_GB:-40}"
RAM_MB="${RAM_MB:-4096}"
CPU_CORES="${CPU_CORES:-2}"
BOOT="${BOOT:-iso}"          
ISO_URL="${ISO_URL:-}"
VNC_PORT="${VNC_PORT:-5900}" 
EXTRA_QEMU_ARGS="${EXTRA_QEMU_ARGS:-}"

VM_DIR="/home/container/vm/${VM_NAME}"
IMG_QCOW2="${VM_DIR}/${VM_NAME}.qcow2"
ISO_PATH="${VM_DIR}/boot.iso"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
OVMF_VARS="${VM_DIR}/OVMF_VARS.fd"

mkdir -p "${VM_DIR}"
[ -f "${OVMF_VARS}" ] || cp /usr/share/OVMF/OVMF_VARS.fd "${OVMF_VARS}"
KVM_OPTS=""
if [ -e /dev/kvm ]; then
  KVM_OPTS="--enable-kvm -cpu host"
else
  KVM_OPTS="-cpu qemu64"
fi
if ! [[ "${VNC_PORT}" =~ ^[0-9]+$ ]] || [ "${VNC_PORT}" -lt 5900 ] || [ "${VNC_PORT}" -gt 5999 ]; then
  echo "VNC_PORT must be 5900–5999 (got ${VNC_PORT})."
  exit 1
fi
VNC_DISPLAY=$(( VNC_PORT - 5900 ))
VNC_OPT="-vnc 0.0.0.0:${VNC_DISPLAY}"   # binds on all interfaces

# Create disk
if [ ! -f "${IMG_QCOW2}" ]; then
  echo "Creating ${DISK_SIZE_GB}G qcow2..."
  qemu-img create -f qcow2 "${IMG_QCOW2}" ${DISK_SIZE_GB}G
fi

# ISO boot path (Windows 10 official ISO or your licensed ISO)
if [ "${BOOT}" = "iso" ]; then
  if [ -z "${ISO_URL}" ]; then
    echo "BOOT=iso but ISO_URL is empty. Provide a direct download URL or pre-mount an ISO."
    exit 1
  fi
  if [ ! -f "${ISO_PATH}" ]; then
    echo "Downloading installer ISO..."
    curl -L "${ISO_URL}" -o "${ISO_PATH}"
  fi
else
  echo "For Windows, set BOOT=iso and ISO_URL=<win10_iso_url>"
  exit 1
fi

# Networking (user-mode; optional, helpful if you want RDP later)
NET_OPTS="-netdev user,id=n1 -device e1000,netdev=n1"

# Graphics: VNC + basic VGA + USB tablet improves mouse accuracy in VNC
GRAPHICS_OPTS="-device VGA -device usb-ehci -device usb-tablet ${VNC_OPT}"

# Storage: use IDE/SATA for installer compatibility (avoids virtio driver hassles)
exec qemu-system-x86_64 \
  ${KVM_OPTS} \
  -machine q35,accel=kvm:tcg \
  -smp "${CPU_CORES}" -m "${RAM_MB}" \
  -drive if=ide,file="${IMG_QCOW2}",format=qcow2,discard=unmap \
  -drive media=cdrom,file="${ISO_PATH}" \
  -bios "${OVMF_CODE}" -drive if=pflash,format=raw,unit=1,file="${OVMF_VARS}",readonly=off \
  ${NET_OPTS} \
  ${GRAPHICS_OPTS} \
  ${EXTRA_QEMU_ARGS}
