
#!/bin/bash

# === Config ===
STORAGE="MRK"
DISK="Ubuntusrvssh"
OVA_PATH="/mnt/pve/${STORAGE}/import/${DISK}.ova"
TMP_DIR="/var/tmp/ova_temp"
OVF_FILE="${TMP_DIR}/${DISK}.ovf"

# === Generate a unique 8-char name ===
VM_NAME="NewUbuntu-$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"

# === Find the next free VMID across the whole cluster ===
get_free_vmid() {
  # Get the list of VMIDs in use across the entire cluster
  USED_VMIDS=$(pvesh get /cluster/resources --type vm | grep -o 'qemu/[0-9]\+' | sed 's/^qemu\///')

  # Loop through VMID range 100 to 9999 and check for the first available
  for i in {100..9999}; do
    if ! echo "$USED_VMIDS" | grep -q "^$i$"; then
      echo "$i"
      return
    fi
  done

  echo "No free VMID found in the range 100-9999." >&2
  exit 1
}

VMID=$(get_free_vmid)

# === Create temp directory and extract OVA ===
mkdir $TMP_DIR
tar -xvf $OVA_PATH -C $TMP_DIR

# === Import OVF with qcow2 format (no --name flag) ===
qm importovf $VMID $OVF_FILE $STORAGE --format qcow2

# === Update VM config file ===
CONF_FILE="/etc/pve/qemu-server/$VMID.conf"

# Generate MAC address with first three octets as BC:24:11 and random last three octets
RANDOM_MAC="BC:24:11:$(hexdump -n 3 -e '3/1 "%02X:"' /dev/random | sed 's/.$//')"

# === Modify VMID.conf ===
sed -i "s|^sata0:.*|sata0: $STORAGE:$VMID/vm-${VMID}-disk-0.qcow2,size=30G|" $CONF_FILE
echo "agent: 1" >> $CONF_FILE
echo "cpu: x86-64-v2-AES" >> $CONF_FILE
echo "ostype: l26" >> $CONF_FILE
echo "sockets: 1" >> $CONF_FILE
echo "net0: e1000=$RANDOM_MAC,bridge=vmbr0" >> $CONF_FILE
sed -i "s/^name:.*/name: $VM_NAME/" $CONF_FILE

# === Cleanup ===
rm -rf $TMP_DIR

# === Output results ===
echo "VM Imported with VMID: $VMID and Name: $VM_NAME"

# === Exit ===
exit 0
