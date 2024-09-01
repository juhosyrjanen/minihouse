#!/bin/bash

VM_NAME=$1
IP=$2

IGNITION_DIR="ignition"
SEED_ISO_DIR="seed-iso"
IMAGES_DIR="images"
SSH_PUB_KEY=$(cat ${IGNITION_DIR}/id_rsa.pub)
KUBE_VERSION="1.30.0-00"

# Create Butane YAML configuration
cat > ${IGNITION_DIR}/config.bu <<EOF
variant: fcos
version: 1.5.0
passwd:
  users:
    - name: core
      ssh_authorized_keys:
        - "$SSH_PUB_KEY"
storage:
  files:
    - path: /etc/NetworkManager/system-connections/enp1s0.nmconnection
      mode: 0600
      contents:
        inline: |
          [connection]
          id=enp1s0
          type=ethernet
          interface-name=enp1s0
          [ipv4]
          address1=${IP}/24,192.168.122.1
          dhcp-hostname=${VM_NAME}
          dns=8.8.8.8;
          may-fail=false
          method=manual

    - path: /etc/hostname
      mode: 0644
      contents:
        inline: ${VM_NAME}

    - path: /etc/sysctl.d/99-kubernetes.conf
      mode: 0644
      contents:
        inline: |
          net.bridge.bridge-nf-call-ip6tables = 1
          net.bridge.bridge-nf-call-iptables = 1
          net.ipv4.ip_forward = 1

    - path: /etc/fstab
      mode: 0644
      overwrite: true
      contents:
        inline: |
          # /etc/fstab
          # Disabling swap as required by Kubernetes

    - path: /etc/yum.repos.d/kubernetes.repo
      mode: 0644
      contents:
        inline: |
          [kubernetes]
          name=Kubernetes
          baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
          enabled=1
          gpgcheck=1
          repo_gpgcheck=1
          gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
          exclude=kubelet kubeadm kubectl

systemd:
  units:
    - name: systemd-networkd.service
      enabled: true

    - name: kubelet.service
      enabled: true
      dropins:
        - name: 10-kubelet-args.conf
          contents: |
            [Service]
            Environment="KUBELET_EXTRA_ARGS=--node-ip=${IP}"

    - name: disable-swap.service
      enabled: true
      contents: |
        [Unit]
        Description=Disable Swap for Kubernetes
        After=local-fs.target

        [Service]
        Type=oneshot
        ExecStart=/usr/sbin/swapoff -a
        ExecStart=/usr/bin/sed -i '/ swap / s/^/#/' /etc/fstab
        RemainAfterExit=yes

        [Install]
        WantedBy=multi-user.target

EOF

# Convert Butane YAML to Ignition
butane --pretty --strict ${IGNITION_DIR}/config.bu > ${IGNITION_DIR}/config.ign

mkdir -p ${SEED_ISO_DIR}/${VM_NAME}
mkdir -p ${IMAGES_DIR}

# Create the disk image
DISK_IMAGE="${IMAGES_DIR}/${VM_NAME}.qcow2"
qemu-img create -f qcow2 ${DISK_IMAGE} 10G

# Embed Ignition config into the ISO
coreos-installer iso ignition embed -i ${IGNITION_DIR}/config.ign -o ${SEED_ISO_DIR}/${VM_NAME}-seed.iso isos/coreOS.iso
