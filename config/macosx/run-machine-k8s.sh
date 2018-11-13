#!/usr/bin/env bash

minikube start
minikube ssh "sudo mkdir /Users && sudo mount.nfs 192.168.99.1:/Users /Users -o exec,rw,user,vers=3"
sudo route -n add -net 172.17.0.0/12 $(minikube ip)
/usr/local/bin/fsevent-start
