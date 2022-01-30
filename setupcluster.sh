#!/bin/bash

ssh gary@192.168.0.38
    
MASTER="192.168.0.38"    
NODE1="192.168.0.39"

##################### Run this on all Linux nodes #######################

#Update the server
sudo apt-get update -y
sudo apt-get upgrade -y

#Install containerd
sudo apt-get install containerd -y

#Configure containerd and start the service
sudo mkdir -p /etc/containerd
sudo su -
exit

#Next, install Kubernetes. First you need to add the repository's GPG key with the command:
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add

#Add the Kubernetes repository
sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"

#Install all of the necessary Kubernetes components with the command:
sudo apt-get install kubeadm kubelet kubectl -y

#Modify "sysctl.conf" to allow Linux Node’s iptables to correctly see bridged traffic
sudo nano /etc/sysctl.conf
    #Add this line: net.bridge.bridge-nf-call-iptables = 1

sudo -s
#Allow packets arriving at the node's network interface to be forwaded to pods. 
sudo echo '1' > /proc/sys/net/ipv4/ip_forward
exit

#Reload the configurations with the command:
sudo sysctl --system

#Load overlay and netfilter modules 
sudo modprobe overlay
sudo modprobe br_netfilter
  
#Disable swap by opening the fstab file for editing 
sudo nano /etc/fstab
    #Comment out "/swap.img"

#Disable swap from comand line also 
sudo swapoff -a

#Pull the necessary containers with the command:
sudo kubeadm config images pull

####### This section must be run only on the Master node#############

sudo kubeadm init

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#Download Calico CNI
curl https://docs.projectcalico.org/manifests/calico.yaml > calico.yaml

#Modify the "calico.yaml" file
    #1. calico_backend: "vxlan"
    #2. Comment out "- -bird-live"
    #3. Comment out "- -bird-ready"
    #4.  - name: CALICO_IPV4POOL_VXLAN #CALICO_IPV4POOL_IPIP 
              value: "Always"  
    #5.  - name: CALICO_IPV4POOL_IPIP #Learning Channel
              value: "Never" 

#If you prefer to use the modified "calico.yaml" file I prepared, copy it to your master node:
    #scp -r calico.yaml gary@$MASTER

#Apply Calico CNI
kubectl apply -f ./calico.yaml

#Copy the "/.kube" folder to other nodes
scp -r $HOME/.kube gary@$NODE1:/home/gary


##################### Run this on other Kubernetes nodes #######################

ssh gary@$NODE1
       
sudo -i 
    #Copy the token and cert from "kubeadm init" operation and run it below
  
    #Note to join future nodes after inial cluster set up, run "kubeadm token create --print-join-command" to get a new "kubeadm join" with fresh certs.
exit

#**************************************************Cluster info and tests*******************************************************

#View nodes
kubectl get nodes -o wide

#Optionaly untaint maste so that PODs can be secheuled on master
kubectl taint node kube-master node-role.kubernetes.io/master-


#Show VXLAN VTEP
ip link  show type vxlan

#Show VTEP's ip address
ip addr | grep vxlan.calico

#Schedule a Kubernetes deployment using a container from Google samples
kubectl create deployment hello-world --image=gcr.io/google-samples/hello-app:1.0
#Scale up the replica set to 2
kubectl scale --replicas=2 deployment/hello-world

#View PODs
kubectl get pods -o wide 

#Get the IP address of the POD on the other server (Node1)
POD_IP_ON_NODE1=$(kubectl get pods -o wide | grep kube-node1  | awk '{ print $6}')
echo $POD_IP_ON_NODE1

curl http://$POD_IP_ON_NODE1:8080


#Clean up
kubectl delete deployment hello-world

#**************************************************************Optional install tshark************************************************
#Optional, install tshark 
sudo apt-get install tshark -y

#Start tshark in a new treminal 
sudo tshark -V --color -i eth0 -d udp.port=4789,vxlan -f "port 4789"

#From master, curl the service installed on node1 POD
curl http://$POD_IP_ON_NODE1:8080








