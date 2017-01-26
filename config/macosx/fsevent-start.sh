#!/usr/bin/env bash
killall -9 fsevents_to_vm
fsevents_to_vm start --debug --ssh-identity-file ~/.docker/machine/machines/dinghy/id_rsa --ssh-ip $(dinghy)
