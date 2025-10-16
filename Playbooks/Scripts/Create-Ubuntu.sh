#!/bin/bash

STORAGE="DATA-Pool-Storage"
DISK="Ubuntusrvssh"
OVA_PATH="/mnt/pve/${STORAGE}/import/${DISK}.ova"
count=${1:-1}

get_free_vmid() {
  USED_VMIDS=$(pvesh get /cluster/resources --type vm | grep -o 'qemu/[0-9]\+' | sed 's/^qemu\///')
  for i in {100..9999}; do
    if ! echo "$USED_VMIDS" | grep -q "^$i$"; then
      echo "$i"
      return
    fi
  done
  echo "No free VMID found in range." >&2
  exit 1
}

for ((i=1; i<=count; i++)); do
  (
    TMP_DIR="/var/tmp/ova_vm_${i}_$$"
    mkdir -p "$TMP_DIR"

    echo "[$i] Extracting OVA to $TMP_DIR"
    cp "$OVA_PATH" "$TMP_DIR/${DISK}.ova"
    tar -xf "$TMP_DIR/${DISK}.ova" -C "$TMP_DIR"

    OVF_FILE=$(find "$TMP_DIR" -name '*.ovf' | head -n1)
    VMID=$(get_free_vmid)
    VM_NAME="NewUbuntu-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"

    echo "[$i] Importing VMID $VMID"
    qm importovf "$VMID" "$OVF_FILE" "$STORAGE" --format qcow2

    CONF_FILE="/etc/pve/qemu-server/$VMID.conf"
    for attempt in {1..10}; do
      [ -f "$CONF_FILE" ] && break
      sleep 1
    done

    if [ ! -f "$CONF_FILE" ]; then
      echo "[$i] Failed to find config for VMID $VMID"
      exit 1
    fi

    RANDOM_MAC="BC:24:11:$(hexdump -n 3 -e '3/1 "%02X:"' /dev/random | sed 's/:$//')"
    sed -i "s|^sata0:.*|sata0: $STORAGE:$VMID/vm-${VMID}-disk-0.qcow2,size=30G|" "$CONF_FILE"
    echo "agent: 1" >> "$CONF_FILE"
    echo "cpu: x86-64-v2-AES" >> "$CONF_FILE"
    echo "ostype: l26" >> "$CONF_FILE"
    echo "sockets: 1" >> "$CONF_FILE"
    echo "net0: e1000=$RANDOM_MAC,bridge=vmbr0" >> "$CONF_FILE"
    sed -i "s/^name:.*/name: $VM_NAME/" "$CONF_FILE"

    echo "✅ [$i] VMID $VMID created as $VM_NAME"
    rm -rf "$TMP_DIR"
  ) &
done

wait
