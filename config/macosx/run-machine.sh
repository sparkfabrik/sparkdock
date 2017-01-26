#!/usr/bin/env bash
dinghy up
sudo route -n add -net 172.16.0.0/12 $(docker-machine ip dinghy)
/usr/local/bin/fsevent-start
