#!/bin/bash

STORAGE="DATA-Pool-Storage"
DISK="win2025"
OVA_PATH="/mnt/pve/${STORAGE}/import/${DISK}.ova"
TMP_DIR="/var/tmp/ova_temp"
OVF_FILE="${TMP_DIR}/${DISK}.ovf"

count=${1:-1}

get_free_vmid() {
  USED_VMIDS=$(pvesh get /cluster/resources --type vm | grep -o 'qemu/[0-9]\+' | sed 's/^qemu\///')

  for i in {100..9999}; do
    if ! echo "$USED_VMIDS" | grep -q "^$i$"; then
      echo "$i"
      return
    fi
  done

  echo "No free VMID found in the range 100-9999." >&2
  exit 1
}

mkdir -p $TMP_DIR
tar -xvf $OVA_PATH -C $TMP_DIR

for ((i=1; i<=count; i++)); do
  echo "=== Creating VM number $i ==="

  VM_NAME="NewWindows-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"
  VMID=$(get_free_vmid)
  echo "Using VMID: $VMID with name $VM_NAME"

  # Her importerer vi det givne image, samt generes en MAC adresse
  qm importovf $VMID $OVF_FILE $STORAGE --format qcow2
  CONF_FILE="/etc/pve/qemu-server/$VMID.conf"
  RANDOM_MAC="BC:24:11:$(hexdump -n 3 -e '3/1 "%02X:"' /dev/random | sed 's/:$//')"

  # Modificering af den enkelte VMs config fil.
  sed -i "s|^sata0:.*|sata0: $STORAGE:$VMID/vm-${VMID}-disk-0.qcow2,size=30G|" $CONF_FILE
  echo "agent: 1" >> $CONF_FILE
  echo "cpu: x86-64-v2-AES" >> $CONF_FILE
  echo "ostype: l26" >> $CONF_FILE
  echo "sockets: 1" >> $CONF_FILE
  echo "net0: e1000=$RANDOM_MAC,bridge=vmbr0" >> $CONF_FILE
  sed -i "s/^name:.*/name: $VM_NAME/" $CONF_FILE

  echo "VM Imported with VMID: $VMID and Name: $VM_NAME"
  echo "==============================="
done

rm -rf $TMP_DIR
exit 0
