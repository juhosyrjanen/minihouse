# A small repo doing Kubernetes stuff

The plan with this repo is to setup a "pure" development Kubernetes environment using Fedora CoreOS, `kubeadm` and ArgoCD.

Roadmap:

✅ - Libvirt based CoreOS virtualisation
✅ - Kubernetes host provisioning
🚧 - Automated cluster setup via `kubeadm`
🚧 - Automated cluster addon setup via ArgoCD

## Requirements

- Arch Linux or Arch based OS
- [Libvirt](https://libvirt.org/) default networking stack (assumed CIRD currently `192.168.68.0/24`)
- [Task](https://taskfile.dev/)
- CoreOS ISO in `isos/`
- Fighting spirit
