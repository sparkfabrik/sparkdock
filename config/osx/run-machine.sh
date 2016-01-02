#!/usr/bin/env bash
docker-machine start dev
sudo route -n add -net 172.17.0.0 $(docker-machine ip dev)