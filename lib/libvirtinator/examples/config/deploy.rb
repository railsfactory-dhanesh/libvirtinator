# config valid only for Capistrano 3.1
lock '3.2.1'

set :release_name, "ubuntu-14.04-v0.0.1-docker1.3.1"

set :vmbuilder_run_command, -> {
  [ "vmbuilder kvm ubuntu",
    "-o",
    "--debug",
    "--verbose",
    "--dest=/tmp/#{fetch(:release_name)}",
    "--config=templates/#{fetch(:release_name)}.cfg",
    "--execscript=templates/#{fetch(:release_name)}-init.sh",
    "--firstboot=/tmp/first_boot.sh",
    "--rootsize=15360",
    "--swapsize=2048"
  ].join(' ')
}

set "my_host_data_vg_path",               "/dev/ubuntu-vg"
set "my_host_dns_nameservers",            ""
set "my_host_bridge",                     "br0"
set "my_host_root_partitions_path",       "/RootPartitions"

set "my_other_host_data_vg_path",         "/dev/ubuntu-vg"
set "my_other_host_dns_nameservers",      ""
set "my_other_host_bridge",               "br0"
set "my_other_host_root_partitions_path", "/RootPartitions"
