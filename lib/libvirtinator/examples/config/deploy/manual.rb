set :host_machine_name,     "none"
set :user,                  -> { ENV['USER'] }

role :app,                  "none"

set :base_image,            "none"
set :node_name,             "none"

set :data_disk_enabled,     false
set :data_disk_gb,          "0"
set :data_disk_type,        "lv"
set :data_disk_mount_point, "/"
set :data_disk_partition,   "0"

set :memory_gb,             "0"
set :cpus,                  "0"

set :ip,                    "none"
set :cidr,                  "none"

set :node_fqdn,             "none"
set :app_fqdn,              "none"
set :hostname,              "none"

set :usergroups,            ["none"]
