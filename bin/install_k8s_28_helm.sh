#!/bin/bash -x
#
################################################################################
#   Copyright (c) 2019 AT&T Intellectual Property.                             #
#   Copyright (c) 2022 Nokia.                                                  #
#                                                                              #
#   Licensed under the Apache License, Version 2.0 (the "License");            #
#   you may not use this file except in compliance with the License.           #
#   You may obtain a copy of the License at                                    #
#                                                                              #
#       http://www.apache.org/licenses/LICENSE-2.0                             #
#                                                                              #
#   Unless required by applicable law or agreed to in writing, software        #
#   distributed under the License is distributed on an "AS IS" BASIS,          #
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
#   See the License for the specific language governing permissions and        #
#   limitations under the License.                                             #
################################################################################


usage() {
    echo "Usage: $0 [ -k <k8s version> -d <docker version> -e <helm version> -c <cni-version>" 1>&2;

    echo "k:    kubernetes version" 1>&2;
    echo "c:    kubernetes CNI  version" 1>&2;
    echo "d:    docker version" 1>&2;
    echo "e:    helm version" 1>&2;
    exit 1;
}


wait_for_pods_running () {
  NS="$2"
  CMD="kubectl get pods --all-namespaces "
  if [ "$NS" != "all-namespaces" ]; then
    CMD="kubectl get pods -n $2 "
  fi
  KEYWORD="Running"
  if [ "$#" == "3" ]; then
    KEYWORD="${3}.*Running"
  fi

  CMD2="$CMD | grep \"$KEYWORD\" | wc -l"
  NUMPODS=$(eval "$CMD2")
  echo "waiting for $NUMPODS/$1 pods running in namespace [$NS] with keyword [$KEYWORD]"
  while [  $NUMPODS -lt $1 ]; do
    sleep 5
    NUMPODS=$(eval "$CMD2")
    echo "> waiting for $NUMPODS/$1 pods running in namespace [$NS] with keyword [$KEYWORD]"
  done 
}


#defining versions
KUBEV="1.28.0-1.1"
KUBECNIV="3.26.4"
HELMV="3.5.4"
#RUNCVERS="1.1.4"
CONTAINERDV="1.6.26-1"
KUBEPKG="v1.28"
KUBEIMG="v1.28.0"

echo running ${0}
while getopts ":k:d:e:n:c" o; do
    case "${o}" in
    e)	
       HELMV=${OPTARG}
        ;;
    d)
       CONTAINERDV=${OPTARG}
        ;;
    k)
       KUBEV=${OPTARG}
       ;;
    c)
       KUBECNIV=${OPTARG}
       ;;
    *)
       usage
       ;;
    esac
done

#verifying unsupported helm version
if [[ ${HELMV} == 2.* ]]; then
  echo "helm 2 ("${HELMV}")not supported anymore" 34.83.202.80
  exit -1
fi

set -x
export DEBIAN_FRONTEND=noninteractive
echo "$(hostname -I) $(hostname)" >> /etc/hosts
printenv

#echo "### Containerd version  = "${CONTAINERDV}
echo "### k8s version     = "${KUBEV}
echo "### helm version    = "${HELMV}
echo "### k8s cni version = "${KUBECNIV}



#disable swap & add kernel parameters
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab



sudo modprobe overlay
sudo modprobe br_netfilter

# Set up the IPV4 bridge on all nodes
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

sudo tee /etc/sysctl.d/kubernetes.conf <<EOT
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT

sudo sysctl --system

#Update the repo and download all the required packages
apt install -y curl gnupg software-properties-common apt-transport-https ca-certificates


#Add Docker Repo to apt
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

#curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
#echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

#apt-get install -y --no-install-recommends containerd.io="${CONTAINERD_VERSION}"

sudo apt update

if [ -z ${CONTAINERDV} ]; then
  apt install -y $APTOPTS containerd.io
else
  apt install -y containerd.io=${CONTAINERDV}
fi

#configure cgroup
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml

sudo curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /etc/systemd/system/containerd.service


sudo systemctl restart containerd
sudo systemctl enable containerd

#install dependencies
apt -y install curl vim git wget apt-transport-https gpg


# Add Apt Repository for Kubernetes. Download the Google Cloud public signing key.
mkdir -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/${KUBEPKG}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update

if [ -z ${KUBEV} ]; then
  apt install -y $APTOPTS kubeadm kubelet kubectl
else
  apt install -y $APTOPTS kubeadm=${KUBEV} kubelet=${KUBEV} kubectl=${KUBEV}
fi

apt-mark hold containerd.io kubernetes-cni kubelet kubeadm kubectl
kubectl version --client && kubeadm version
systemctl enable kubelet


#systemctl restart containerd
kubeadm config images pull --cri-socket unix:///run/containerd/containerd.sock --kubernetes-version ${KUBEIMG}

sudo kubeadm init --pod-network-cidr 10.244.0.0/16  --upload-certs --kubernetes-version v1.28.0  --control-plane-endpoint $(hostname):6443 --ignore-preflight-errors=all  --cri-socket unix:///run/containerd/containerd.sock

#kubeadm init --pod-network-cidr=10.1.0.0/16 --control-plane-endpoint k8s-endpoint:6443
#kubeadm init --upload-certs --kubernetes-version=v1.28.0  --control-plane-endpoint=$(hostname) --ignore-preflight-errors=all  --cri-socket unix:///run/containerd/containerd.sock
#kubeadm init --config /root/config.yaml --ignore-preflight-errors all --cri-socket unix:///run/containerd/containerd.sock
#kubeadm init --control-plane-endpoint k8s-endpoint:6443



cd /root
rm -rf .kube
mkdir -p .kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config
export KUBECONFIG=/root/.kube/config
echo "KUBECONFIG=${KUBECONFIG}" >> /etc/environment

kubectl get pods --all-namespaces


kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/tigera-operator.yaml
wget https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/custom-resources.yaml
sed -i 's/cidr: 192\.168\.0\.0\/16/cidr: 10.244.0.0\/16/g' custom-resources.yaml
kubectl apply -f custom-resources.yaml

wait_for_pods_running 7 kube-system

kubectl taint nodes --all node-role.kubernetes.io/master-


if [ ! -e helm-v${HELMV}-linux-amd64.tar.gz ]; then
  wget https://get.helm.sh/helm-v${HELMV}-linux-amd64.tar.gz
fi
cd /root && rm -rf Helm && mkdir Helm && cd Helm
tar -xvf ../helm-v${HELMV}-linux-amd64.tar.gz
mv linux-amd64/helm /usr/local/bin/helm

cd /root

rm -rf /root/.helm

  while ! helm version; do
    echo "Waiting for Helm to be ready"
    sleep 15
  done

  echo "Preparing a master node (lower ID) for using local FS for PV"
  PV_NODE_NAME=$(kubectl get nodes |grep control-plane | cut -f1 -d' ' | sort | head -1)
  kubectl label --overwrite nodes $PV_NODE_NAME local-storage=enable
  if [ "$PV_NODE_NAME" == "$(hostname)" ]; then
    mkdir -p /opt/data/dashboard-data
  fi

  echo "Done with master node setup"
fi

if [[ ! -z "" && ! -z "" ]]; then 
  echo " " >> /etc/hosts
fi

if [[ ! -z "" && ! -z "" ]]; then 
  echo " " >> /etc/hosts
fi

if [[ ! -z "" && ! -z "helm.ricinfra.local" ]]; then 
  echo " helm.ricinfra.local" >> /etc/hosts
fi

if [[ "1" -gt "100" ]]; then
  cat <<EOF >/etc/ca-certificates/update.d/helm.crt

EOF
fi


