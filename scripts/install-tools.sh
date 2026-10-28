#!/usr/bin/env bash
set -euo pipefail
[[ $(uname -m) == x86_64 ]] || { echo 'The supplied runner uses Linux amd64.' >&2; exit 1; }
[[ $EUID == 0 ]] || { echo 'Run tool installation as root on the disposable runner.' >&2; exit 1; }
: "${LAB_AKS_VERSION:?Set the AKS Kubernetes version, such as 1.34.3}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
fetch() { curl --fail --silent --show-error --location --retry 3 --max-time 180 "$1" -o "$2"; }
tf_version=1.13.5
fetch "https://releases.hashicorp.com/terraform/$tf_version/terraform_${tf_version}_linux_amd64.zip" terraform.zip
fetch "https://releases.hashicorp.com/terraform/$tf_version/terraform_${tf_version}_SHA256SUMS" terraform.sums
awk '$2 == "terraform_1.13.5_linux_amd64.zip" {print $1 "  terraform.zip"}' terraform.sums > verify.sums
[[ -s verify.sums ]] && sha256sum -c verify.sums
unzip -q terraform.zip terraform
install -m 0755 terraform /usr/local/bin/terraform
flux_version=2.10.0
fetch "https://github.com/fluxcd/flux2/releases/download/v$flux_version/flux_${flux_version}_linux_amd64.tar.gz" flux.tgz
fetch "https://github.com/fluxcd/flux2/releases/download/v$flux_version/flux_${flux_version}_checksums.txt" flux.sums
awk '$2 == "flux_2.10.0_linux_amd64.tar.gz" {print $1 "  flux.tgz"}' flux.sums > verify.sums
[[ -s verify.sums ]] && sha256sum -c verify.sums
tar -xzf flux.tgz flux
install -m 0755 flux /usr/local/bin/flux
helm_version=4.3.1
fetch "https://get.helm.sh/helm-v${helm_version}-linux-amd64.tar.gz" helm.tgz
fetch "https://get.helm.sh/helm-v${helm_version}-linux-amd64.tar.gz.sha256sum" helm.sums
awk '{print $1 "  helm.tgz"}' helm.sums > verify.sums
sha256sum -c verify.sums
tar -xzf helm.tgz linux-amd64/helm
install -m 0755 linux-amd64/helm /usr/local/bin/helm
login_version=0.2.22
fetch "https://github.com/Azure/kubelogin/releases/download/v${login_version}/kubelogin-linux-amd64.zip" kubelogin.zip
fetch "https://github.com/Azure/kubelogin/releases/download/v${login_version}/kubelogin-linux-amd64.zip.sha256" login.sums
awk '{print $1 "  kubelogin.zip"}' login.sums > verify.sums
sha256sum -c verify.sums
unzip -q kubelogin.zip
install -m 0755 bin/linux_amd64/kubelogin /usr/local/bin/kubelogin
minor=${LAB_AKS_VERSION%.*}
fetch "https://dl.k8s.io/release/stable-${minor}.txt" kubernetes.version
kube_version=$(tr -d '\r\n' < kubernetes.version)
[[ "$kube_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Unexpected kubectl version.' >&2; exit 1; }
fetch "https://dl.k8s.io/release/${kube_version}/bin/linux/amd64/kubectl" kubectl
fetch "https://dl.k8s.io/release/${kube_version}/bin/linux/amd64/kubectl.sha256" kubectl.sum
printf '%s  kubectl\n' "$(tr -d '\r\n' < kubectl.sum)" > verify.sums
sha256sum -c verify.sums
install -m 0755 kubectl /usr/local/bin/kubectl
