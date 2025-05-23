run-ansible-macos TAGS="all":
    #!/usr/bin/env bash
    TAGS={{TAGS}}
    if [ -z "${TAGS}" ]; then
        ansible-playbook ./ansible/macos.yml -i ./ansible/inventory.ini --ask-become-pass -v
    else
        ansible-playbook ./ansible/macos.yml -i ./ansible/inventory.ini --ask-become-pass --tags=${TAGS} -v
    fi
