#!/bin/bash

VM_NAME=$1
IP=$2

CLOUD_INIT_DIR="cloud-init"
SEED_ISO_DIR="seed-iso"
SSH_PUB_KEY=$(cat ${CLOUD_INIT_DIR}/id_rsa.pub)

cat > ${CLOUD_INIT_DIR}/user-data.tpl <<EOF
#cloud-config
hostname: {{ .Hostname }}
users:
  - name: ubuntu
    ssh-authorized-keys:
      - $SSH_PUB_KEY
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash

write_files:
  - path: /etc/netplan/01-netcfg.yaml
    content: |
      network:
        version: 2
        renderer: networkd
        ethernets:
          enp1s0:
            dhcp4: no
            addresses:
              - {{ .IP }}/24
            gateway4: 192.168.122.1
            nameservers:
              addresses:
                - 8.8.8.8

runcmd:
  - netplan apply
  - apt update
  - apt install -y apt-transport-https ca-certificates curl software-properties-common
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
  - apt update
  - apt install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - systemctl enable --now kubelet
EOF

mkdir -p ${SEED_ISO_DIR}/${VM_NAME}

# Generate user-data from template
sed "s/{{ .Hostname }}/${VM_NAME}/g; s/{{ .IP }}/${IP}/g" ${CLOUD_INIT_DIR}/user-data.tpl > ${SEED_ISO_DIR}/${VM_NAME}/user-data

# Generate meta-data from template
sed "s/{{ .Hostname }}/${VM_NAME}/g" ${CLOUD_INIT_DIR}/meta-data.tpl > ${SEED_ISO_DIR}/${VM_NAME}/meta-data

# Generate seed ISO
genisoimage -output ${SEED_ISO_DIR}/${VM_NAME}-seed.iso -volid cidata -joliet -rock ${SEED_ISO_DIR}/${VM_NAME}/user-data ${SEED_ISO_DIR}/${VM_NAME}/meta-data
