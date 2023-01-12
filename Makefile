run-ansible-macos:
ifeq ($(TAGS),)
	ansible-playbook ./ansible/macos.yml --ask-become-pass
else
	ansible-playbook ./ansible/macos.yml --ask-become-pass --tags=$(TAGS)
endif