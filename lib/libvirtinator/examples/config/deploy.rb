# config valid only for Capistrano 3.1
lock '3.2.1'

set :log_level, :info
#set :log_level, :debug

# Setup the host machiness you will use
set "my_host_data_disk_vg_path",          "/dev/ubuntu-vg"
set "my_host_dns_nameservers",            "8.8.8.8 8.8.4.4"
set "my_host_bridge",                     "br0"
set "my_host_root_partitions_path",       "/RootPartitions"

set "my_other_host_data_disk_vg_path",    "/dev/ubuntu-vg"
set "my_other_host_dns_nameservers",      "8.8.8.8 8.8.4.4"
set "my_other_host_bridge",               "br0"
set "my_other_host_root_partitions_path", "/RootPartitions"

# Setup the CIDRs you will use
set "123_123_123_123-27_network",         "123.123.123.0"
set "123_123_123_123-27_gateway",         "123.123.123.1"
set "123_123_123_123-27_broadcast",       "123.123.123.31"
set "123_123_123_123-27_netmask",         "255.255.255.224"

set "231_231_231_231-27_network",         "231.231.231.0"
set "231_231_231_231-27_gateway",         "231.231.231.1"
set "231_231_231_231-27_broadcast",       "231.231.231.31"
set "231_231_231_231-27_netmask",         "255.255.255.224"

# Global dns-search. Can be overridden by setting the same
#   in a VM's settings file, (a config/deploy/<stage>.rb file.)
set :dns_search,                          "example.com example2.com"

# Setup vmbuilder for building a base image
set :release_name,                        "ubuntu-14.04_docker-1.9.1_v0.0.0"
set :build_user,                          -> { ENV['USER'] }
set :build_host,                          "myhost.example.com"
set :vmbuilder_run_command,               -> {
  # [ "vmbuilder", "kvm", "ubuntu", # Ubuntu 12.04 and older hosts
  [ "ubuntu-vm-builder", "kvm", "ubuntu", # Ubuntu 14.04 and newer hosts
    "-o",
    "--debug",
    "--verbose",
    "--dest=/tmp/#{fetch(:release_name)}",
    "--config=/tmp/vmbuilder.cfg",
    "--execscript=/tmp/vmbuilder-init.sh",
    "--firstboot=/tmp/first_boot.sh",
    # rootsize & swapsize settings do not get picked up in cfg file, so set here
    "--rootsize=15360",
    "--swapsize=2048"
  ]
}


## Settings that shouldn't need changed:
set :nbd_run_file,          -> { "/var/lock/#{fetch(:node_name)}.nbd" }
set :nbd_lock_file,         -> { "/var/lock/qemu-nbd-#{fetch(:nbd)}" }
set :dev_nbd,               -> { "/dev/#{fetch(:nbd)}" }
set :dev_nbdp1,             -> { "/dev/#{fetch(:nbd)}p1" }
set :dns_nameservers,       -> { fetch("#{fetch(:host_machine_name)}_dns_nameservers") }
set :bridge,                -> { fetch("#{fetch(:host_machine_name)}_bridge") }
set :root_partitions_path,  -> { fetch("#{fetch(:host_machine_name)}_root_partitions_path") }
set :base_image_path,       -> { "#{fetch(:root_partitions_path)}/#{fetch(:base_image)}" }
set :root_image_path,       -> { "#{fetch(:root_partitions_path)}/#{fetch(:node_name)}-root.qcow2" }
set :mount_point,           -> { "#{fetch(:root_partitions_path)}/#{fetch(:node_name)}-root.qcow2_mnt" }
set :data_disk_vg_path,     -> { fetch("#{fetch(:host_machine_name)}_data_disk_vg_path") }
set :data_disk_lv_name,     -> { "#{fetch(:node_name)}-data" }
set :data_disk_lv_path,     -> { "#{fetch(:data_disk_vg_path)}/#{fetch(:data_disk_lv_name)}" }
set :data_disk_qemu_path,   -> { "#{fetch(:root_partitions_path)}/#{fetch(:node_name)}-data.qcow2" }

