#!/bin/bash

set -ex

PROVISION=false
MEMORY=3096M
CPU=2
NUMA=1
QEMU_ARGS=""
KERNEL_ARGS=""
NEXT_DISK=""
BLOCK_DEV=""
BLOCK_DEV_SIZE=""
VM_USER="vagrant"
VM_SSH_KEY="vagrant.key"
ARCH=$(uname -m)

if [ "$ARCH" == "s390x" ]; then
  VM_USER="cloud-user"
fi

while true; do
  case "$1" in
    -m | --memory ) MEMORY="$2"; shift 2 ;;
    -a | --numa ) NUMA="$2"; shift 2 ;;
    -c | --cpu ) CPU="$2"; shift 2 ;;
    -q | --qemu-args ) QEMU_ARGS="${2}"; shift 2 ;;
    -k | --additional-kernel-args ) KERNEL_ARGS="${2}"; shift 2 ;;
    -n | --next-disk ) NEXT_DISK="$2"; shift 2 ;;
    -b | --block-device ) BLOCK_DEV="$2"; shift 2 ;;
    -s | --block-device-size ) BLOCK_DEV_SIZE="$2"; shift 2 ;;
    -n | --nvme-device-size ) NVME_DISK_SIZES+="$2 "; shift 2 ;;
    -t | --scsi-device-size ) SCSI_DISK_SIZES+="$2 "; shift 2 ;;
    -u | --usb-device-size ) USB_SIZES+="$2 "; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

function calc_next_disk {
  last="$(ls -t disk* | head -1 | sed -e 's/disk//' -e 's/.qcow2//')"
  last="${last:-00}"
  next=$((last+1))
  next=$(printf "/disk%02d.qcow2" $next)
  if [ -n "$NEXT_DISK" ]; then next=${NEXT_DISK}; fi
  if [ "$last" = "00" ]; then
    last="box.qcow2"
  else
    last=$(printf "/disk%02d.qcow2" $last)
  fi
}

NODE_NUM=${NODE_NUM-1}
n="$(printf "%02d" $(( 10#${NODE_NUM} )))"

cat >/usr/local/bin/ssh.sh <<EOL
#!/bin/bash
set -e
dockerize -wait tcp://192.168.66.1${n}:22 -timeout 300s &>/dev/null
ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${VM_USER}@192.168.66.1${n} -i ${VM_SSH_KEY} -p 22 -q \$@
EOL
chmod u+x /usr/local/bin/ssh.sh
echo "done" >/ssh_ready

sleep 0.1
until ip link show tap${n}; do
  echo "Waiting for tap${n} to become ready"
  sleep 0.1
done

ROOTLESS=0
if [ -f /run/.containerenv ]; then
  ROOTLESS=$(sed -n 's/^rootless=//p' /run/.containerenv)
fi

# Route SSH
iptables -t nat -A POSTROUTING ! -s 192.168.66.0/16 --out-interface br0 -j MASQUERADE
if [ "$ROOTLESS" != "1" ]; then
  iptables -A FORWARD --in-interface eth0 -j ACCEPT
  iptables -t nat -A PREROUTING -p tcp -i eth0 -m tcp --dport 22${n} -j DNAT --to-destination 192.168.66.1${n}:22
else
  # Add DNAT rule for rootless podman (traffic originating from loopback adapter)
  iptables -t nat -A OUTPUT -p tcp --dport 22${n} -j DNAT --to-destination 192.168.66.1${n}:22
fi

function create_ip_rules {
  protocol=$1
  shift
  if [ "$ROOTLESS" != "1" ]; then
    for port in "$@"; do
      iptables -t nat -A PREROUTING -p ${protocol} -i eth0 -m ${protocol} --dport ${port} -j DNAT --to-destination 192.168.66.101:${port}
    done
  else
    for port in "$@"; do
      # Add DNAT rule for rootless podman (traffic originating from loopback adapter)
      iptables -t nat -A OUTPUT -p ${protocol} --dport ${port} -j DNAT --to-destination 192.168.66.101:${port}
    done
  fi
}

# Route ports from container to VM for first node
if [ "$n" = "01" ] ; then
  tcp_ports=( 6443 8443 80 443 30007 30008 31001 )
  create_ip_rules "tcp" "${tcp_ports[@]}"

  udp_ports=( 31111 )
  create_ip_rules "udp" "${udp_ports[@]}"
fi

# For backward compatibility, so that we can just copy over the newer files
if [ -f provisioned.qcow2 ]; then
  ln -sf provisioned.qcow2 disk01.qcow2
fi

calc_next_disk

default_disk_size=53687091200 # 50G
disk_size=$(qemu-img info --output json ${last} | jq '.["virtual-size"]')
if [ $disk_size -lt $default_disk_size ]; then
    disk_size=$default_disk_size
fi

echo "Creating disk \"${next} backed by ${last} with size ${disk_size}\"."
qemu-img create -f qcow2 -o backing_file=${last} -F qcow2 ${next} ${disk_size}

echo ""
echo "SSH will be available on container port 22${n}."
echo "VNC will be available on container port 59${n}."
echo "VM MAC in the guest network will be 52:55:00:d1:55:${n}"
echo "VM IP in the guest network will be 192.168.66.1${n}"
echo "VM hostname will be node${n}"

# Try to create /dev/kvm if it does not exist
if [ ! -e /dev/kvm ]; then
   mknod /dev/kvm c 10 $(grep '\<kvm\>' /proc/misc | cut -f 1 -d' ')
fi

# Prevent the emulated soundcard from messing with host sound
export QEMU_AUDIO_DRV=none

block_dev_arg=""

if [ -n "${BLOCK_DEV}" ]; then
  # 10Gi default
  block_device_size="${BLOCK_DEV_SIZE:-10737418240}"
  qemu-img create -f qcow2 ${BLOCK_DEV} ${block_device_size}
  block_dev_arg="-drive format=qcow2,file=${BLOCK_DEV},if=virtio,cache=unsafe"
fi

disk_num=0
for size in ${NVME_DISK_SIZES[@]}; do
  echo "Creating disk "$size" for NVMe disk emulation"
  disk="/nvme-"${disk_num}".img"
  qemu-img create -f raw $disk $size
  let "disk_num+=1"
done

disk_num=0
for size in ${SCSI_DISK_SIZES[@]}; do
  echo "Creating disk "$size" for SCSI disk emulation"
  disk="/scsi-"${disk_num}".img"
  qemu-img create -f raw $disk $size
  let "disk_num+=1"
done


disk_num=0
for size in ${USB_SIZES[@]}; do
  echo "Creating disk "$size" for USB disk emulation"
  disk="/usb-"${disk_num}".img"
  qemu-img create -f raw $disk $size
  let "disk_num+=1"
done

numa_arg=""
if [ "${NUMA}" -gt 1 ]; then
    numa_mem_unit="${MEMORY//[[:digit:]]/}"
    numa_mem_value="${MEMORY//[!0-9]/}"
    if [ $((CPU % NUMA)) -gt 0 ] || [ $((numa_mem_value % NUMA)) -gt 0 ]; then
        echo "unable to calculate symmetric NUMA topology with vCPUs:${CPU} Memory:${MEMORY} NUMA:${NUMA}"
        exit 1
    fi
    node_mem="$((numa_mem_value / NUMA))${numa_mem_unit}"
    node_first_cpu=0
    node_cpu_step=$((CPU / NUMA - 1))
    for node_id in $(seq 0 $((NUMA - 1))); do
        node_last_cpu=$((node_first_cpu + node_cpu_step))
        numa_arg+=" -object memory-backend-ram,size=${node_mem},id=m${node_id}"
        numa_arg+=" -numa node,nodeid=${node_id},memdev=m${node_id},cpus=${node_first_cpu}-${node_last_cpu}"
        node_first_cpu=$((node_last_cpu + 1))
    done
fi

if [ "$ARCH" == "s390x" ]; then
    qemu_system_cmd="qemu-system-s390x \
    -enable-kvm \
    -drive format=qcow2,file=${next},if=none,cache=unsafe,id=drive1 ${block_dev_arg} \
    -device virtio-blk,drive=drive1,bootindex=1 \
    -device virtio-net-ccw,netdev=network0,mac=52:55:00:d1:55:${n} \
    -netdev tap,id=network0,ifname=tap${n},script=no,downscript=no \
    -device virtio-rng \
    -initrd /initrd.img \
    -kernel /vmlinuz \
    -append \"$(cat /kernel.s390x.args) $(cat /additional.kernel.args) ${KERNEL_ARGS}\" \
    -vnc :${n} \
    -cpu host \
    -m ${MEMORY} \
    -smp ${CPU} ${numa_arg} \
    -serial pty \
    -machine s390-ccw-virtio,accel=kvm \
    -uuid $(cat /proc/sys/kernel/random/uuid) \
    ${QEMU_ARGS}"

# Remove secondary network devices from qemu_system_cmd and move them to qemu_monitor_cmds, so that those devices are later added after VM is started using qemu monitor to avoid primary network interface to be named other than eth0
qemu_monitor_cmds=()
IFS=' ' read -r -a qemu_parts <<< "$qemu_system_cmd"
for part_index in "${!qemu_parts[@]}"; do
  part="${qemu_parts[$part_index]}"
  nxtpart="${qemu_parts[$part_index+1]}"
  if [ "$part" == "-netdev" ]; then
    if [[ "$nxtpart" == *"secondarynet"* ]]; then
      qemu_system_cmd=$(echo "$qemu_system_cmd" | sed "s/ -netdev $nxtpart//")
      qemu_monitor_cmds+=("netdev_add $nxtpart")
    fi
  elif [ "$part" == "-device" ] && [[ "$nxtpart" == *"virtio-net-ccw"* ]]; then
    if [[ $nxtpart == *"secondarynet"* ]]; then
      qemu_system_cmd=$(echo "$qemu_system_cmd" | sed "s/ -device $nxtpart//")
      qemu_monitor_cmds+=("device_add $nxtpart")
    fi
  fi
done

qemu_system_cmd+=" -monitor unix:/tmp/qemu-monitor.sock,server,nowait"
PID=0
echo "PID initially is $PID"
eval "nohup $qemu_system_cmd &"
PID=$!
echo "PID is $PID"

    if [ "${#qemu_monitor_cmds[@]}" -gt 0 ]; then
       sleep 15
       #Sorted in reverse alphabetical order so that -netdev are passed first then -dev
       IFS=$'\t' qemu_monitor_cmds_sorted=($(printf "%s\n" "${qemu_monitor_cmds[@]}" | sort -r))
       for qemu_monitor_cmd in "${qemu_monitor_cmds_sorted[@]}"; do
       echo "$qemu_monitor_cmd"  | socat - UNIX-CONNECT:/tmp/qemu-monitor.sock
       done
      fi
    wait $PID
else
exec qemu-system-x86_64 -enable-kvm -drive format=qcow2,file=${next},if=virtio,cache=unsafe ${block_dev_arg} \
  -device virtio-net-pci,netdev=network0,mac=52:55:00:d1:55:${n} \
  -netdev tap,id=network0,ifname=tap${n},script=no,downscript=no \
  -device virtio-rng-pci \
  -initrd /initrd.img \
  -kernel /vmlinuz \
  -append "$(cat /kernel.args) $(cat /additional.kernel.args) ${KERNEL_ARGS}" \
  -vnc :${n} -cpu host,migratable=no,+invtsc -m ${MEMORY} -smp ${CPU} ${numa_arg} \
  -serial pty -M q35,accel=kvm,kernel_irqchip=split \
  -device intel-iommu,intremap=on,caching-mode=on -device intel-hda -device hda-duplex -device AC97 \
  -uuid $(cat /proc/sys/kernel/random/uuid) \
  ${QEMU_ARGS}
fi
