#!/usr/bin/env bash
docker-machine start dev
sudo route -n add -net 172.16.0.0/12 $(docker-machine ip dev)
