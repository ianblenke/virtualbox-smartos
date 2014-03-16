VERSION:=latest
VBOX_NAME:=smartos-hypervisor
ZPOOL_VDI:=Zpool.vdi
ZPOOL_SIZE:=10000
CONTROLLER_NAME:=sata1
BASE_FOLDER:=$(shell pwd)
TFTP_ROOT:=$(BASE_FOLDER)/tftp
VBOX_CONFIG=$(BASE_FOLDER)/$(VBOX_NAME)/$(VBOX_NAME).vbox
DHCP:=on
CIDR:=172.16.11.0/24
SSH_PORT:=2223
ROOT_PASSWORD:=vagrant
HOSTNAME:=vagrant

# https://wiki.openstack.org/wiki/Smartos
all: $(VBOX_CONFIG)

#
# http://wiki.smartos.org/display/DOC/Download+SmartOS
#
platform-$(VERSION).tgz:
	wget https://us-east.manta.joyent.com/Joyent_Dev/public/SmartOS/platform-$(VERSION).tgz

$(ZPOOL_VDI):
	VBoxManage createhd --filename $(ZPOOL_VDI) --size $(ZPOOL_SIZE) --format VDI --variant Standard
	VBoxManage modifyhd $(ZPOOL_VDI) --type normal --compact

$(VBOX_CONFIG): $(ZPOOL_VDI)
	make $(TFTP_ROOT)/pxelinux.0
	VBoxManage createvm --name $(VBOX_NAME) --ostype Solaris11_64 --register --basefolder $(BASE_FOLDER)
	VBoxManage storagectl $(VBOX_NAME) --name $(CONTROLLER_NAME) --add sata
	VBoxManage storagectl $(VBOX_NAME) --name $(CONTROLLER_NAME) --hostiocache off --bootable off
	VBoxManage storageattach $(VBOX_NAME) --storagectl $(CONTROLLER_NAME) --type hdd --medium $(ZPOOL_VDI) --mtype normal --port 1
	VBoxManage modifyvm $(VBOX_NAME) --audio none
	VBoxManage modifyvm $(VBOX_NAME) --nictype1 82540EM
	VBoxManage modifyvm $(VBOX_NAME) --nic1 nat --natpf1 "$(VBOX_NAME)_ssh,tcp,,$(SSH_PORT),,22" --natdnsproxy1 on --natdnshostresolver1 on
	mkdir -p $(TFTP_ROOT)
	VBoxManage modifyvm $(VBOX_NAME) --natnet1 $(CIDR)
	VBoxManage modifyvm $(VBOX_NAME) --nattftpfile1 pxelinux.0 --nattftpprefix1 $(TFTP_ROOT)
	VBoxManage modifyvm $(VBOX_NAME) --biosbootmenu disabled --boot1 net --boot2 net --boot3 net --boot4 net
	VBoxManage modifyvm $(VBOX_NAME) --pae on --vtxvpid on --vtxux on --largepages on --nestedpaging on
	VBoxManage modifyvm $(VBOX_NAME) --vram 10
	VBoxManage modifyvm $(VBOX_NAME) --memory 4096
	# For guest additions
	VBoxManage storagectl $(VBOX_NAME) --name PIIX4 --add ide --controller PIIX4
	VBoxManage storageattach $(VBOX_NAME) --storagectl PIIX4 --port 0 --device 0 --type dvddrive --medium emptydrive

enable_trace:
	VBoxManage modifyvm $(VBOX_NAME) --nictrace1 on --nictracefile1 $(BASE_FOLDER)/$(VBOX_NAME).pcap

disable_trace:
	VBoxManage modifyvm $(VBOX_NAME) --nictrace1 off
	rm -f $(VBOX_NAME).pcap || true

start: up
up:
	make $(VBOX_CONFIG)
	VBoxManage startvm $(VBOX_NAME)

stop: down
down:
	VBoxManage controlvm $(VBOX_NAME) acpipowerbutton

clean:
	VBoxManage unregistervm $(VBOX_NAME)
	#VBoxManage natnetwork remove -t nat-$(VBOX_NAME)-network
	rm -f $(VBOX_CONFIG)

showvminfo:
	VBoxManage showvminfo $(VBOX_NAME)

$(TFTP_ROOT)/platform: platform-$(VERSION).tgz
	mkdir -p $(TFTP_ROOT)/smartos
	tar xvzf platform-$(VERSION).tgz -C $(TFTP_ROOT)/smartos
	ver=`tar tvzf platform-latest.tgz | head -1  | sed -e 's/^.*platform-//' | cut -d/ -f1` && \
		mkdir -p $(TFTP_ROOT)/smartos/$$ver && \
		( [ -d $(TFTP_ROOT)/smartos/$$ver/platform ] || \
			mv $(TFTP_ROOT)/smartos/platform-$$ver $(TFTP_ROOT)/smartos/$$ver/platform ) && \
		ln -fs smartos/$$ver/platform $(TFTP_ROOT)/platform

$(TFTP_ROOT)/pxelinux.0:
	make $(TFTP_ROOT)/pxelinux.cfg/default
	make $(TFTP_ROOT)/platform
	[ -f /tmp/syslinux-6.02.tar.gz ] || (cd /tmp; wget http://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.02.tar.gz )
	[ -d /tmp/syslinux-6.02 ] || tar -xvzf /tmp/syslinux-6.02.tar.gz -C /tmp
	for file in bios/core/pxelinux.0 bios/core/lpxelinux.0 bios/com32/mboot/mboot.c32 bios/com32/modules/reboot.c32 bios/com32/modules/chain.c32 bios/com32/menu/menu.c32 bios/com32/elflink/ldlinux/ldlinux.c32 bios/com32/libutil/libutil.c32 bios/com32/lib/libcom32.c32 ; do cp -f /tmp/syslinux-6.02/$$file $(TFTP_ROOT)/$$(basename $$file) ; done
	rm -fr /tmp/syslinux-6.02
	touch $@

$(TFTP_ROOT)/pxelinux.cfg/default:
	mkdir -p $(TFTP_ROOT)/pxelinux.cfg
	( echo "DEFAULT menu.c32"; echo "prompt 0"; echo "timeout 1"; echo "label smartos"; echo "kernel mboot.c32"; echo "append platform/i86pc/kernel/amd64/unix -v -B console=text,smartos=true,root_shadow='"`openssl passwd -1 $(ROOT_PASSWORD)`"',hostname=$(HOSTNAME) --- platform/i86pc/amd64/boot_archive" ) > $@
	touch $@

dist_clean:
	make clean || true
	rm -f package-$(VERSION).tgz tftp $(VBOX_NAME) $(ZPOOL_VDI)

bootstrap_global_domain:
	# Generate a special virtualbox host key if one doesn't exist yet
	[ -f ~/.ssh/$(VBOX_NAME) ] || ssh-keygen -t rsa -b 2048 -f ~/.ssh/$(VBOX_NAME) -P ''
	# If there is no ssh config stanza for this virtualbox host yet, then add it
	grep "Host $(VBOX_NAME)" ~/.ssh/config > /dev/null || \
	( echo "Host $(VBOX_NAME)"; \
	  echo "  User root"; \
	  echo "  HostName localhost; \
	  echo "  IdentityFile "~/.ssh/$(VBOX_NAME).pub"; \
	  echo "  port 2223" ) >> ~/.ssh/config
	echo "Enter '$(ROOT_PASSWORD)' when/if prompted for a password"
	# Setup root key trust
	scp -P ~/.ssh/$(VBOX_NAME).pub $(VBOX_NAME):.ssh/authorized_keys
	# Install chef on the global domain (wise)
	ssh $(VBOX_NAME) bash -c 'curl -k http://cuddletech.com/smartos/Chef-fatclient-SmartOS-10.14.2.tar.bz2 | bzcat | tar xf - -C /'
	# Install pkgin on the global domain (unwise)
	curl -k http://pkgsrc.joyent.com/packages/SmartOS/bootstrap/bootstrap-2013Q3-`uname -p`.tar.gz | gzcat | tar -xf - -C /
	pkg_admin rebuild
	pkgin -y up

install_vagrant_plugin:
	/Applications/Vagrant/bin/vagrant plugin install --plugin-prerelease --plugin-source https://rubygems.org/ vagrant-smartos
	/Applications/Vagrant/bin/vagrant box add smartos-dummy https://github.com/joshado/vagrant-smartos/raw/master/example_box/smartos.box
	/Applications/Vagrant/bin/vagrant up


