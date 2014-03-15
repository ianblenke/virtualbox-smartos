VERSION:=latest
VBOX_NAME:=smartos
ROOT_VDI:=smartos-$(VERSION).vdi
ZPOOL_VDI:=Zpool.vdi
ZPOOL_SIZE:=4096
CONTROLLER_NAME:=sata1
BASE_FOLDER:=$(shell pwd)
TFTP_ROOT:=$(BASE_FOLDER)/tftp
VBOX_CONFIG=$(BASE_FOLDER)/$(VBOX_NAME)/$(VBOX_NAME).vbox
DHCP:=on
CIDR:=172.16.11.0/24
TFTP_SERVER:=172.16.11.2
TFTP_FILE:=
SSH_PORT:=2223
ROOT_PASSWORD:=vagrant

# https://wiki.openstack.org/wiki/Smartos
all: $(VBOX_CONFIG)

#
# http://wiki.smartos.org/display/DOC/Download+SmartOS
#
smartos-latest-USB.img.bz2:
	wget https://us-east.manta.joyent.com/Joyent_Dev/public/SmartOS/smartos-$(VERSION)-USB.img.bz2

smartos-$(VERSION)-USB.img:
	make smartos-$(VERSION)-USB.img.bz2
	bunzip2 smartos-$(VERSION)-USB.img.bz2

$(ROOT_VDI):
	make smartos-$(VERSION)-USB.img
	VBoxManage convertfromraw smartos-$(VERSION)-USB.img $(ROOT_VDI) --format VDI

$(ZPOOL_VDI):
	VBoxManage createhd --filename $(ZPOOL_VDI) --size $(ZPOOL_SIZE) --format VDI --variant Standard
	VBoxManage modifyhd $(ZPOOL_VDI) --type normal --compact

$(VBOX_CONFIG): $(ROOT_VDI) $(ZPOOL_VDI)
	make $(TFTP_ROOT)/pxelinux.0
	VBoxManage createvm --name $(VBOX_NAME) --ostype Solaris11_64 --register --basefolder $(BASE_FOLDER)
	VBoxManage storagectl $(VBOX_NAME) --name $(CONTROLLER_NAME) --add sata
	VBoxManage storagectl $(VBOX_NAME) --name $(CONTROLLER_NAME) --hostiocache off --bootable off
	# Switched to TFTP booting, no longer need this:
	#VBoxManage storageattach $(VBOX_NAME) --storagectl $(CONTROLLER_NAME) --type hdd --medium $(ROOT_VDI) --mtype normal --port 1
	VBoxManage storageattach $(VBOX_NAME) --storagectl $(CONTROLLER_NAME) --type hdd --medium $(ZPOOL_VDI) --mtype normal --port 1
	VBoxManage modifyvm $(VBOX_NAME) --audio none
	VBoxManage modifyvm $(VBOX_NAME) --nictype1 82540EM
	VBoxManage modifyvm $(VBOX_NAME) --nic1 nat --natpf1 "$(VBOX_NAME)_ssh,tcp,,$(SSH_PORT),,22" --natdnsproxy1 on --natdnshostresolver1 on
	mkdir -p $(TFTP_ROOT)
	VBoxManage modifyvm $(VBOX_NAME) --natnet1 $(CIDR) # --nattftpserver1 $(TFTP_SERVER)
	VBoxManage modifyvm $(VBOX_NAME) --nattftpfile1 pxelinux.0 --nattftpprefix1 $(TFTP_ROOT)
	VBoxManage modifyvm $(VBOX_NAME) --biosbootmenu disabled --boot1 net --boot2 net --boot3 net --boot4 net
	VBoxManage modifyvm $(VBOX_NAME) --pae on --vtxvpid on --vtxux on --largepages on --nestedpaging on
	VBoxManage modifyvm $(VBOX_NAME) --vram 10
	VBoxManage modifyvm $(VBOX_NAME) --memory 4096

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

$(TFTP_ROOT)/pxelinux.0:
	make $(TFTP_ROOT)/pxelinux.cfg/default
	make $(TFTP_ROOT)/smartos/platform
	[ -f /tmp/syslinux-6.02.tar.gz ] || (cd /tmp; wget http://www.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.02.tar.gz )
	[ -d /tmp/syslinux-6.02 ] || tar -xvzf /tmp/syslinux-6.02.tar.gz -C /tmp
	for file in bios/core/pxelinux.0 bios/core/lpxelinux.0 bios/com32/mboot/mboot.c32 bios/com32/modules/reboot.c32 bios/com32/modules/chain.c32 bios/com32/menu/menu.c32 bios/com32/elflink/ldlinux/ldlinux.c32 bios/com32/libutil/libutil.c32 bios/com32/lib/libcom32.c32 ; do cp -f /tmp/syslinux-6.02/$$file $(TFTP_ROOT)/$$(basename $$file) ; done
	rm -fr /tmp/syslinux-6.02
	touch $@

$(TFTP_ROOT)/smartos/platform:
	mkdir -p $(TFTP_ROOT)/smartos
	hdiutil mount smartos-$(VERSION)-USB.img
	rsync -aq /Volumes/HEADNODE/platform/ $(TFTP_ROOT)/smartos/platform/
	hdiutil eject /Volumes/HEADNODE
	touch $@

$(TFTP_ROOT)/pxelinux.cfg/default:
	mkdir -p $(TFTP_ROOT)/pxelinux.cfg
	( echo "DEFAULT menu.c32"; echo "prompt 0"; echo "timeout 1"; echo "label smartos"; echo "kernel mboot.c32"; echo "append smartos/platform/i86pc/kernel/amd64/unix -B console=text,standalone=true,noimport=true,root_shadow='"`openssl passwd -1 $(ROOT_PASSWORD)`"' --- smartos/platform/i86pc/amd64/boot_archive" ) > $@
	touch $@

dist_clean:
	rm -f $(ROOT_VDI) smartos-$(VERSION)-USB.img $(TFTP_ROOT)

