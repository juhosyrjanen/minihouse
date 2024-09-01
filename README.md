# A small repo doing Kubernetes stuff

The plan with this repo is to setup a development Kubernetes environment using Fedora CoreOS, Podman, `kubeadm` and ArgoCD.

Roadmap:

 - ✅ Libvirt based CoreOS virtualisation
 - ✅ Kubernetes host provisioning
 - 🚧 `etcd` in Podman
 - 🚧 Automated cluster setup via `kubeadm`
 - 🚧 Automated cluster addon setup via ArgoCD

## Requirements

- Arch Linux or Arch based OS
- [Libvirt](https://libvirt.org/) default networking stack (assumed CIRD currently `192.168.122.0/24`)
- [Task](https://taskfile.dev/)
- CoreOS ISO in `isos/`
- Fighting spirit

Running `task prerequisites` will check that required tools are installed and install them if not.

## Up

Running `task up` will start the virtualisation stack

## Down

Running `task down` will destroy everything created with the tool
