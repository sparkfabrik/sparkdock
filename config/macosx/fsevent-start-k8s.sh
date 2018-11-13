#!/usr/bin/env bash
minikube ssh "echo fs.inotify.max_user_watches=524288 | sudo tee -a /etc/sysctl.conf"
killall -9 fsevents_to_vm
fsevents_to_vm start --ssh-identity-file ~/.minikube/machines/minikube/id_rsa --ssh-ip $(minikube ip) &
