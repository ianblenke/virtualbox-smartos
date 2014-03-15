Vagrant.require_plugin "vagrant-smartos"

Vagrant.configure("2") do |config|

  # For the time being, use our dummy box
  config.vm.box = "smartos-dummy"

  config.vm.provider :smartos do |smartos, override|
    # Required: This is which hypervisor to provision the VM on.
    # The format must be "<username>@<ip or hostname>"
    smartos.hypervisor = "root@smartos-hypervisor"

    # Required: This is the UUID of the SmartOS image to use for the VMs. 
    # It must already be imported using `imgadm` before running `vagrant up`.
    smartos.image_uuid = "ff86eb8a-a069-11e3-ae0e-4f3c8983a91c" # this is base64:13.4.0

    # Optional: The RAM allocation for the machine, defaults to the SmartOS default (256MB)
    # smartos.ram = 512

    # Optional: Disk quota for the machine, defaults to the SmartOS default (5G)
    # smartos.quota = 10

    # Optional: Specify the nic_tag to use
    # If omitted, 'admin' will be the default
    # smartos.nic_tag = "admin"

    # Optional: Specify a static IP address for the VM
    # If omitted, 'dhcp' will be used
    # smartos.ip_address = "1.2.3.4"

    # Optional: Specify the net-mask (required if not using dhcp)
    # smartos.subnet_mask = "255.255.255.0"

    # Optional: Specify the gateway (required if not using dhcp)
    # smartos.gateway = "255.255.255.0"

    # Optional: Specify a VLAN tag for this VM
    # smartos.vlan = 1234
  end

  # RSync'ed shared folders should work as normal
  config.vm.synced_folder "./", "/work-dir"

  # Multi-VMs should be fine, too; they will take the default parameters from above, and you can override
  # specifics for each VM
  #
  # config.vm.define :box1 do |box|
  #    box.vm.provider :smartos do |smartos, override|
  #      smartos.ip_address = "172.16.251.21"
  #    end
  # end
  #
  # config.vm.define :box2 do |box|
  #    box.vm.provider :smartos do |smartos, override|
  #      smartos.ip_address = "172.16.251.21"
  #    end
  # end
  #

end
