#!/bin/bash

VM_NAME=$1
IP=$2

IGNITION_DIR="ignition"
SEED_ISO_DIR="seed-iso"
IMAGES_DIR="images"
SSH_PUB_KEY=$(cat ${IGNITION_DIR}/id_rsa.pub)
KUBELET_VERSION="1.30.4"
ETCD_VERSION="3.5.13"
KUBELET_IMAGE="quay.io/poseidon/kubelet:v${KUBELET_VERSION}"
ETCD_IMAGE="quay.io/coreos/etcd:v${ETCD_VERSION}"

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
  directories:
    - path: /var/lib/etcd
      mode: 0700
    - path: /etc/kubernetes
      mode: 0755
    - path: /opt/bootstrap
    - path: /etc/etcd
      mode: 0755
    - path: /etc/ssl/etcd
      mode: 0755

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

    - path: /etc/etcd/etcd.env
      mode: 0644
      contents:
        inline: |
          ETCD_NAME="${VM_NAME}-etcd"
          ETCD_DATA_DIR=/var/lib/etcd
          ETCD_ADVERTISE_CLIENT_URLS=https://${VM_NAME}:2379
          ETCD_INITIAL_ADVERTISE_PEER_URLS=https://${VM_NAME}:2380
          ETCD_LISTEN_CLIENT_URLS=https://0.0.0.0:2379
          ETCD_LISTEN_PEER_URLS=https://0.0.0.0:2380
          ETCD_LISTEN_METRICS_URLS=http://0.0.0.0:2381
          ETCD_INITIAL_CLUSTER=${VM_NAME}-etcd=https://${VM_NAME}:2380
          ETCD_STRICT_RECONFIG_CHECK=true
          ETCD_TRUSTED_CA_FILE=/etc/ssl/certs/etcd/server-ca.crt
          ETCD_CERT_FILE=/etc/ssl/certs/etcd/server.crt
          ETCD_KEY_FILE=/etc/ssl/certs/etcd/server.key
          ETCD_CLIENT_CERT_AUTH=true
          ETCD_PEER_TRUSTED_CA_FILE=/etc/ssl/certs/etcd/peer-ca.crt
          ETCD_PEER_CERT_FILE=/etc/ssl/certs/etcd/peer.crt
          ETCD_PEER_KEY_FILE=/etc/ssl/certs/etcd/peer.key
          ETCD_PEER_CLIENT_CERT_AUTH=true

    - path: /etc/containerd/config.toml
      overwrite: true
      contents:
        inline: |
          version = 2
          root = "/var/lib/containerd"
          state = "/run/containerd"
          subreaper = true
          oom_score = -999
          [grpc]
          address = "/run/containerd/containerd.sock"
          uid = 0
          gid = 0
          [plugins."io.containerd.grpc.v1.cri"]
          enable_selinux = true
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true

    - path: /etc/kubernetes/kubelet.yaml
      mode: 0644
      contents:
        inline: |
          apiVersion: kubelet.config.k8s.io/v1beta1
          kind: KubeletConfiguration
          authentication:
            anonymous:
              enabled: false
            webhook:
              enabled: true
            x509:
              clientCAFile: /etc/kubernetes/ca.crt
          authorization:
            mode: Webhook
          cgroupDriver: systemd
          clusterDNS:
            - ${cluster_dns_service_ip}
          clusterDomain: cluster.local
          healthzPort: 0
          rotateCertificates: true
          shutdownGracePeriod: 45s
          shutdownGracePeriodCriticalPods: 30s
          staticPodPath: /etc/kubernetes/manifests
          readOnlyPort: 0
          resolvConf: /run/systemd/resolve/resolv.conf
          volumePluginDir: /var/lib/kubelet/volumeplugins

    - path: /opt/bootstrap/layout
      mode: 0544
      contents:
        inline: |
          #!/bin/bash -e
          mkdir -p -- auth tls/{etcd,k8s} static-manifests manifests/{coredns,kube-proxy,network}
          awk '/#####/ {filename=$2; next} {print > filename}' assets
          mkdir -p /etc/ssl/etcd/etcd
          mkdir -p /etc/kubernetes/pki
          mv tls/etcd/{peer*,server*} /etc/ssl/etcd/etcd/
          mv tls/etcd/etcd-client* /etc/kubernetes/pki/
          chown -R etcd:etcd /etc/ssl/etcd
          chmod -R 500 /etc/ssl/etcd
          mv auth/* /etc/kubernetes/pki/
          mv tls/k8s/* /etc/kubernetes/pki/
          mkdir -p /etc/kubernetes/manifests
          mv static-manifests/* /etc/kubernetes/manifests/
          mkdir -p /opt/bootstrap/assets
          mv manifests /opt/bootstrap/assets/manifests
          rm -rf assets auth static-manifests tls manifests
          chcon -R -u system_u -t container_file_t /etc/kubernetes/pki

    - path: /opt/bootstrap/apply
      mode: 0544
      contents:
        inline: |
          #!/bin/bash -e
          export KUBECONFIG=/etc/kubernetes/pki/admin.conf
          until kubectl version; do
            echo "Waiting for static pod control plane"
            sleep 5
          done
          until kubectl apply -f /assets/manifests -R; do
             echo "Retry applying manifests"
             sleep 5
          done

    - path: /etc/systemd/logind.conf.d/inhibitors.conf
      contents:
        inline: |
          [Login]
          InhibitDelayMaxSec=45s

    - path: /etc/sysctl.d/max-user-watches.conf
      contents:
        inline: |
          fs.inotify.max_user_watches=16184

    - path: /etc/sysctl.d/reverse-path-filter.conf
      contents:
        inline: |
          net.ipv4.conf.default.rp_filter=0
          net.ipv4.conf.*.rp_filter=0

    - path: /etc/systemd/network/50-flannel.link
      contents:
        inline: |
          [Match]
          OriginalName=flannel*
          [Link]
          MACAddressPolicy=none

    - path: /etc/systemd/system.conf.d/accounting.conf
      contents:
        inline: |
          [Manager]
          DefaultCPUAccounting=yes
          DefaultMemoryAccounting=yes
          DefaultBlockIOAccounting=yes

systemd:
  units:
    - name: etcd-member.service
      enabled: true
      contents: |
        [Unit]
        Description=etcd (System Container)
        Documentation=https://github.com/etcd-io/etcd
        Wants=network-online.target
        After=network-online.target
        [Service]
        Environment=ETCD_IMAGE=${ETCD_IMAGE}
        Type=exec
        ExecStartPre=/bin/mkdir -p /var/lib/etcd
        ExecStartPre=-/usr/bin/podman rm etcd
        ExecStart=/usr/bin/podman run --name etcd \
          --env-file /etc/etcd/etcd.env \
          --log-driver k8s-file \
          --network host \
          --volume /var/lib/etcd:/var/lib/etcd:rw,Z \
          --volume /etc/ssl/etcd:/etc/ssl/certs:ro,Z ${ETCD_IMAGE}
        ExecStop=/usr/bin/podman stop etcd
        Restart=on-failure
        RestartSec=10s
        TimeoutStartSec=0
        LimitNOFILE=40000
        [Install]
        WantedBy=multi-user.target

    - name: containerd.service
      enabled: true

    - name: wait-for-dns.service
      enabled: true
      contents: |
        [Unit]
        Description=Wait for DNS entries
        Before=kubelet.service
        [Service]
        Type=oneshot
        RemainAfterExit=true
        ExecStart=/bin/sh -c 'while ! /usr/bin/grep '^[^#[:space:]]' /etc/resolv.conf > /dev/null; do sleep 1; done'
        [Install]
        RequiredBy=kubelet.service
        RequiredBy=etcd-member.service

    - name: kubelet.service
      enabled: true
      contents: |
        [Unit]
        Description=Kubelet (System Container)
        Wants=rpc-statd.service
        [Service]
        Environment=KUBELET_IMAGE=${KUBELET_IMAGE}
        ExecStartPre=/bin/mkdir -p /etc/cni/net.d
        ExecStartPre=/bin/mkdir -p /etc/kubernetes/manifests
        ExecStartPre=/bin/mkdir -p /opt/cni/bin
        ExecStartPre=/bin/mkdir -p /var/lib/calico
        ExecStartPre=/bin/mkdir -p /var/lib/kubelet/volumeplugins
        ExecStartPre=/usr/bin/bash -c "grep 'certificate-authority-data' /etc/kubernetes/kubeconfig | awk '{print \$2}' | base64 -d > /etc/kubernetes/ca.crt"
        ExecStartPre=-/usr/bin/podman rm kubelet
        ExecStart=/usr/bin/podman run --name kubelet \
          --log-driver k8s-file \
          --privileged \
          --pid host \
          --network host \
          --volume /etc/cni/net.d:/etc/cni/net.d:ro,z \
          --volume /etc/kubernetes:/etc/kubernetes:ro,z \
          --volume /usr/lib/os-release:/etc/os-release:ro \
          --volume /etc/machine-id:/etc/machine-id:ro \
          --volume /lib/modules:/lib/modules:ro \
          --volume /run:/run \
          --volume /sys/fs/cgroup:/sys/fs/cgroup \
          --volume /etc/selinux:/etc/selinux \
          --volume /sys/fs/selinux:/sys/fs/selinux \
          --volume /var/lib/calico:/var/lib/calico:ro \
          --volume /var/lib/containerd:/var/lib/containerd \
          --volume /var/lib/kubelet:/var/lib/kubelet:rshared,z \
          --volume /var/log:/var/log \
          --volume /var/run/lock:/var/run/lock:z \
          --volume /opt/cni/bin:/opt/cni/bin:z \
          ${KUBELET_IMAGE} \
          --bootstrap-kubeconfig=/etc/kubernetes/kubeconfig \
          --config=/etc/kubernetes/kubelet.yaml \
          --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
          --hostname-override=${VM_NAME} \
          --kubeconfig=/var/lib/kubelet/kubeconfig \
          --node-labels=node.kubernetes.io/controller="true" \
          --register-with-taints=node-role.kubernetes.io/controller=:NoSchedule
        ExecStop=-/usr/bin/podman stop kubelet
        Delegate=yes
        Restart=always
        RestartSec=10
        [Install]
        WantedBy=multi-user.target

    - name: kubelet.path
      enabled: true
      contents: |
        [Unit]
        Description=Watch for kubeconfig
        [Path]
        PathExists=/etc/kubernetes/kubeconfig
        [Install]
        WantedBy=multi-user.target

    - name: bootstrap.service
      contents: |
        [Unit]
        Description=Kubernetes control plane
        ConditionPathExists=!/opt/bootstrap/bootstrap.done
        [Service]
        Type=oneshot
        RemainAfterExit=true
        WorkingDirectory=/opt/bootstrap
        ExecStartPre=-/usr/bin/podman rm bootstrap
        ExecStart=/usr/bin/podman run --name bootstrap \
            --network host \
            --volume /etc/kubernetes/pki:/etc/kubernetes/pki:ro,z \
            --volume /opt/bootstrap/assets:/assets:ro,Z \
            --volume /opt/bootstrap/apply:/apply:ro,Z \
            --entrypoint=/apply ${KUBELET_IMAGE}
        ExecStartPost=/bin/touch /opt/bootstrap/bootstrap.done
        ExecStartPost=-/usr/bin/podman stop bootstrap

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
