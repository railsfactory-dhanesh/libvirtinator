set :host_machine_name,     "my-host"

# Specify a user with existing SSH access and passwordless sudo rights on the host.
#   The same user will be setup with SSH access on the VM.
set :user,                  -> { ENV['USER'] }

role :app,                  "#{fetch(:user)}@#{fetch(:host_machine_name)}.example.com"

set :base_image,            "ubuntu-14.04-v0.0.0-docker1.3.1.qcow2"
set :node_name,             -> { fetch(:stage) }

set :data_disk_enabled,     true
set :data_disk_gb,          "50"
set :data_disk_type,        "lv"            # "lv" or "qemu"
set :data_disk_mount_point, "/var/www"      # inside the vm
set :data_disk_partition,   "0"             # set to "0" for none (normal),
                                            # set to <partition number> for legacy logical volumes w/ partitions
set :memory_gb,             "2"
set :cpus,                  "4"

set :ip,                    "123.123.123.123"
set :cidr,                  "123_123_123_123-27"

set :node_fqdn,             -> { "#{fetch(:node_name)}.example.com" }
set :app_fqdn,              -> { "#{fetch(:node_name)}.example.com" }
set :hostname,              -> { fetch(:node_name) }

set :usergroups,            ["sysadmins"]
