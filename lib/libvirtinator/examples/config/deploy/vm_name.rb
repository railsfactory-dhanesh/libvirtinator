# vim: set filetype=ruby :
set :host_machine_name, "argon"

role :app, "#{ENV['USER']}@#{fetch(:host_machine_name)}.example.com"

set :base_image,            "ubuntu-14.04-v0.0.0-docker1.3.1.qcow2"
set :node_name,             -> { fetch(:stage) }

set :data_vg_path,          -> { fetch("#{fetch(:host_machine_name)}_data_vg_path") }
set :dns_nameservers,       -> { fetch("#{fetch(:host_machine_name)}_dns_nameservers") }
set :bridge,                -> { fetch("#{fetch(:host_machine_name)}_bridge") }
set :root_partitions_path,  -> { fetch("#{fetch(:host_machine_name)}_root_partitions_path") }

set :base_image_path,       -> { "#{fetch(:root_partitions_path)}/#{fetch(:base_image)}" }
set :root_image_path,       -> { "#{fetch(:root_partitions_path)}/#{fetch(:node_name)}-root.qcow2" }
set :mount_point,           -> { "#{fetch(:root_partitions_path)}/#{fetch(:node_name)}-root.qcow2_mnt" }
set :data_disk_gb,          "50" # set to "0" for no separate data disk
set :data_disk_type,        "lv" # "lv" or "qemu"
set :data_disk_mount_point, "/var/www"
set :data_disk_partition,   "0" # set to "0" for none (normal), set to 1 for legacy hosts
set :memory_gb,             "2"
set :cpus,                  "4"

set :cidr,                  "78_137_162_192-27"
set :ip,                    "78.137.162.206"

set :node_fqdn,             "#{fetch(:stage)}.example.com"
set :app_fqdn,              "my-app.example.com"
set :hostname,              "my-app"
