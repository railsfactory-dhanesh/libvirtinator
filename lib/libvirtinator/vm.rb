require 'socket'
require 'timeout'
require 'erb'

desc "Run any Capistrano task on all the machines in 'config/deploy/*' one at a time; Usage: `cap all_do task='uptime'`"
task :all_do do
  run_locally do
    tsk = ENV['task']
    if tsk.nil? or tsk.empty?
      fatal "task is unset, try `cap all_do task=\"uptime\"`"
      next
    end
    exec("for machine in $(ls config/deploy/ | cut -c 1-7); do bundle exec cap $machine #{tsk}; if ! [ $? -eq 0 ]; then touch $machine.fail; fi; done")
  end
end

desc "Run the uptime command on the VM"
task :uptime do
  on "#{fetch(:user)}@#{fetch(:app_fqdn)}" do
    info("#{capture("uptime")} - on #{fetch(:app_fqdn)}")
  end
end

desc "Check the current status of a VM"
task :status => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      if test("virsh", "list", "--all", "|", "grep", "-q", "#{fetch(:node_name)}")
        if test("virsh", "list", "|", "grep", "-q", "#{fetch(:node_name)}")
          info "VM #{fetch(:node_name)} exists and is running on #{host}"
        else
          info "VM #{fetch(:node_name)} is defined but not running on #{host}"
        end
      else
        info "VM #{fetch(:node_name)} is undefined on #{host}"
      end
      if system "bash -c \"ping -c 5 #{fetch(:ip)} &> /dev/null\""
        begin
          Timeout::timeout(5) do
            (TCPSocket.open(fetch(:ip),22) rescue nil)
            info "The IP #{fetch(:ip)} is responding to ping and SSH"
          end
        rescue TimeoutError
          info "The IP #{fetch(:ip)} is responding to ping but not SSH"
        end
      else
        info "The IP #{fetch(:ip)} is not responding to ping"
      end
    end
  end
end

desc "Start a copy-on-write VM from a base image."
task :start => 'libvirtinator:load_settings' do
  on roles(:app) do
    info "Preparing to start #{fetch(:node_name)}"
    Rake::Task['ensure_nbd_module'].invoke
    Rake::Task['ensure_root_partitions_path'].invoke
    Rake::Task['ensure_vm_not_running'].invoke
    Rake::Task['ensure_ip_no_ping'].invoke
    Rake::Task['ensure_vm_not_defined'].invoke
    Rake::Task['verify_base'].invoke
    Rake::Task['remove_root_image'].invoke
    Rake::Task['create_root_image'].invoke
    begin
      Rake::Task["image:mount"].invoke
      Rake::Task['update_root_image'].invoke
    ensure
      Rake::Task["image:umount"].invoke
    end
    Rake::Task['create_data'].invoke
    Rake::Task['define_domain'].invoke
    Rake::Task['start_domain'].invoke
    Rake::Task['reset_known_hosts_on_host'].invoke
    Rake::Task['setup_agent_forwarding'].invoke
    Rake::Task['wait_for_ping'].invoke
    Rake::Task['wait_for_ssh_alive'].invoke
    # TODO make users:setup offer a yes/no try-again when a specified key doesn't work to connect.
    # TODO make users:setup failure invoke notice "don't worry, you can resume setting up users with 'cap <stage> users:setup'"
    sleep 2 # wait for SSH to finish booting
    Rake::Task['users:setup'].invoke
    info "Say, you don't say? Are we finished?"
  end
end

task :ensure_root_partitions_path => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      dir = fetch(:root_partitions_path)
      unless test "[", "-d", dir, "]"
        fatal "Error: root partitions path #{dir} is not a directory!"
        exit
      end
    end
  end
end

task :ensure_nbd_module => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      unless test("lsmod | grep -q nbd")
        info 'Running modprobe nbd'
        execute "modprobe", "nbd"
        sleep 0.5
        unless test("lsmod | grep -q nbd")
          fatal "Error: Unable to modprobe nbd!"
          exit
        end
      end
    end
  end
end

task :ensure_vm_not_running => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      if test("virsh", "list", "|", "grep", "-q", "#{fetch(:node_name)}")
        fatal "The VM #{fetch(:node_name)} is already running on #{host}!"
        exit
      end
    end
  end
end

task :ensure_ip_no_ping => 'libvirtinator:load_settings' do
  run_locally do
    info "Attempting to ping #{fetch(:ip)}"
    if system "bash -c \"ping -c 5 #{fetch(:ip)} &> /dev/null\""
      fatal "The IP #{fetch(:ip)} is already pingable!"
      exit
    else
      info "No ping returned, continuing"
    end
  end
end

task :ensure_vm_not_defined => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      if test("virsh", "list", "--all", "|", "grep", "-q", "#{fetch(:node_name)}")
        set :yes_or_no, ""
        until fetch(:yes_or_no).chomp.downcase == "yes" or fetch(:yes_or_no).chomp.downcase == "no"
          ask :yes_or_no, "The VM #{fetch(:node_name)} is defined but not running! Do you want to undefine/redefine it?"
        end
        unless fetch(:yes_or_no).chomp.downcase == "yes"
          exit
        else
          execute "virsh", "undefine", fetch(:node_name)
        end
      end
    end
  end
end

task :verify_base => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      unless test "[", "-f", fetch(:base_image_path), "]"
        fatal "Error: cannot find the base image #{fetch(:base_image_path)}"
        exit
      end
      raise unless test("chown", "libvirt-qemu:kvm", fetch(:base_image_path))
    end
  end
end

task :remove_root_image => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      # use 'cap <server> create recreate_root=true' to recreate the root image
      if ENV['recreate_root'] == "true"
        if test "[", "-f", root_image_path, "]"
          set :yes_or_no, ""
          until fetch(:yes_or_no).chomp.downcase == "yes" or fetch(:yes_or_no).chomp.downcase == "no"
            ask :yes_or_no, "Are you sure you want to remove the existing #{root_image_path} file?"
          end
          if fetch(:yes_or_no).chomp.downcase == "yes"
            info "Removing old image"
            execute "rm", root_image_path
          end
        end
      end
    end
  end
end

task :create_root_image => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      unless test "[", "-f", fetch(:root_image_path), "]"
        info "Creating new image"
        execute "qemu-img", "create", "-b", fetch(:base_image_path), "-f", "qcow2", fetch(:root_image_path)
      else
        set :yes_or_no, ""
        until fetch(:yes_or_no).chomp.downcase == "yes" or fetch(:yes_or_no).chomp.downcase == "no"
          ask :yes_or_no, "#{fetch(:root_image_path)} already exists, do you want to continue to update it's configuration?"
        end
        if fetch(:yes_or_no).chomp.downcase == "yes"
          info "Updating file on an existing image."
        else
          exit
        end
      end
    end
  end
end

task :update_root_image => 'libvirtinator:load_settings' do
  on roles(:app) do
    as :root do
      mount_point = fetch(:mount_point)
      raise if mount_point.nil?
      set :logs_path,         -> { fetch(:internal_logs_path) }
      @internal_logs_path     = fetch(:logs_path)
      @node_name              = fetch(:node_name)
      @node_fqdn              = fetch(:node_fqdn)
      @app_fqdn               = fetch(:app_fqdn)
      @hostname               = fetch(:hostname)
      @data_disk_enabled      = fetch(:data_disk_enabled)
      @data_disk_partition    = fetch(:data_disk_partition)
      @data_disk_mount_point  = fetch(:data_disk_mount_point)
      @network                = fetch("#{fetch(:cidr)}_network")
      @gateway                = fetch("#{fetch(:cidr)}_gateway")
      @ip                     = fetch(:ip)
      @broadcast              = fetch("#{fetch(:cidr)}_broadcast")
      @netmask                = fetch("#{fetch(:cidr)}_netmask")
      @dns_nameservers        = fetch(:dns_nameservers)
      @dns_search             = fetch(:dns_search)
      {
        "sudoers-sudo"      => "#{mount_point}/etc/sudoers.d/sudo",
        "hosts"             => "#{mount_point}/etc/hosts",
        "hostname"          => "#{mount_point}/etc/hostname",
        "fstab"             => "#{mount_point}/etc/fstab",
        "interfaces"        => "#{mount_point}/etc/network/interfaces",
      }.each do |file, path|
        template = File.new(File.expand_path("./templates/libvirtinator/#{file}.erb")).read
        generated_config_file = ERB.new(template).result(binding)
        upload! StringIO.new(generated_config_file), "/tmp/#{file}.file"
        execute("mv", "/tmp/#{file}.file", path)
        execute("chown", "root:root", path)
        execute("chmod", "644", path)
      end
      execute "sed", "-i\"\"", "\"/PermitRootLogin/c\\PermitRootLogin no\"",
        "#{mount_point}/etc/ssh/sshd_config"
      execute "chmod", "440", "#{mount_point}/etc/sudoers.d/*"
      execute "echo", "-e", "\"\n#includedir /etc/sudoers.d\n\"", ">>",
        "#{mount_point}/etc/sudoers"
      user = fetch(:user)
      begin
        mounts = ["sys", "dev", "proc"]
        mounts.each do |mount|
          execute "mount", "-o", "bind", "/#{mount}", "#{mount_point}/#{mount}"
        end
        execute "chroot", mount_point, "/bin/bash", "-c",
          "\"if", "!", "id", user, "&>", "/dev/null;", "then",
          "useradd", "--user-group", "--shell",
          "/bin/bash", "--create-home", "#{user};", "fi\""
        execute "chroot", mount_point, "/bin/bash", "-c",
          "\"usermod", "-a", "-G", "sudo", "#{user}\""
        execute "mkdir", "-p", "#{mount_point}/home/#{user}/.ssh"
        execute "chroot", mount_point, "/bin/bash", "-c",
          "\"chown", "#{user}:#{user}", "/home/#{user}", "/home/#{user}/.ssh\""
        execute "chmod", "700", "#{mount_point}/home/#{user}/.ssh"
        run_locally do
          execute "rm", "-f", fetch(:private_key_path)
          execute "ssh-keygen", "-P", "''", "-f", fetch(:private_key_path)
        end
        upload! File.open("#{fetch(:private_key_path)}.pub"), "/tmp/pubkeys"
        execute "mv", "/tmp/pubkeys", "#{mount_point}/home/#{user}/.ssh/authorized_keys"
        execute "chroot", mount_point, "/bin/bash", "-c",
          "\"chown", "#{user}:#{user}", "/home/#{user}/.ssh/authorized_keys\""
        execute "chmod", "600", "#{mount_point}/home/#{user}/.ssh/authorized_keys"
        execute "mkdir", "-p", "#{mount_point}#{fetch(:data_disk_mount_point)}" if fetch(:data_disk_enabled)
      ensure
        mounts.each do |mount|
          execute "umount", "#{mount_point}/#{mount}"
        end
      end
    end
  end
end

task :create_data => 'libvirtinator:load_settings' do
  on roles(:app) do
    as 'root' do
      unless fetch(:data_disk_enabled)
        info "Not using a separate data disk."
        break
      end
      if fetch(:data_disk_type) == "qemu"
        if ! test("[", "-f", fetch(:data_disk_qemu_path), "]") or ENV['recreate_data'] == "true"
          execute "guestfish", "--new", "disk:#{fetch(:data_disk_gb)}G << _EOF_
mkfs ext4 /dev/vda
_EOF_"
          execute "qemu-img", "convert", "-O", "qcow2", "test1.img", "test1.qcow2"
          execute "rm", "test1.img"
          execute "mv", "test1.qcow2", fetch(:data_disk_qemu_path)
        end
      elsif fetch(:data_disk_type) == "lv"
        if ENV['recreate_data'] == "true"
          if test "[", "-b", fetch(:data_disk_lv_path), "]"
            Rake::Task['lv:recreate'].invoke
          else
            Rake::Task['lv:create'].invoke
          end
        else
          if test "[", "-b", fetch(:data_disk_lv_path), "]"
            info "Found and using existing logical volume #{fetch(:data_disk_lv_path)}"
          else
            Rake::Task['lv:create'].invoke
          end
        end
      else
        fatal "No recognized disk type (lv, qemu), yet size is greater than zero!"
        fatal "Fixed this by adding a recognized disk type (lv, qemu) to your config."
        exit
      end
    end
  end
end

task :define_domain => 'libvirtinator:load_settings' do
  on roles(:app) do
    as 'root' do
      # instance variables needed for ERB
      @node_name              = fetch(:node_name)
      @memory_gb              = fetch(:memory_gb).to_i * 1024 * 1024
      @cpus                   = fetch(:cpus)
      @root_image_path        = fetch(:root_image_path)
      @data_disk_enabled      = fetch(:data_disk_enabled)
      @data_disk_type         = fetch(:data_disk_type)
      @data_disk_lv_path      = fetch(:data_disk_lv_path)
      @data_disk_qemu_path    = fetch(:data_disk_qemu_path)
      @bridge                 = fetch(:bridge)
      @bridge_1               = fetch(:bridge_1)
      if (@private_net == true)
      template = File.new(File.expand_path("templates/libvirtinator/server_private_net.xml.erb")).read
      generated_config_file = ERB.new(template).result(binding)
      upload! StringIO.new(generated_config_file), "/tmp/server_private_net.xml"
      execute "virsh", "define", "/tmp/server_private_net.xml"
      execute "rm", "/tmp/server_private_net.xml", "-rf"
      else
      template = File.new(File.expand_path("templates/libvirtinator/server.xml.erb")).read
      generated_config_file = ERB.new(template).result(binding)
      upload! StringIO.new(generated_config_file), "/tmp/server.xml"
      execute "virsh", "define", "/tmp/server.xml"
      execute "rm", "/tmp/server.xml", "-rf"
    end
  end
end

task :start_domain => 'libvirtinator:load_settings' do
  on roles(:app) do
    as 'root' do
      execute "virsh", "start", "#{fetch(:node_name)}"
    end
  end
end

# Keep this to aid with users setup
task :reset_known_hosts_on_host => 'libvirtinator:load_settings' do
  run_locally do
    user = if ENV['SUDO_USER']; ENV['SUDO_USER']; else; ENV['USER']; end
    execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:node_name)}"
    execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:node_fqdn)}"
    execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:hostname)}"
    execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:app_fqdn)}"
    execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:ip)}"
  end
end

task :wait_for_ping => 'libvirtinator:load_settings' do
  run_locally do
    info "Waiting for VM to respond to ping.."
    begin
      Timeout::timeout(30) do
        until system "bash -c \"ping -c 5 #{fetch(:ip)} &> /dev/null\"" do
          print ' ...'
        end
        info "Ping alive!"
      end
    rescue Timeout::Error
      puts
      set :yes_or_no, ""
      until fetch(:yes_or_no).chomp.downcase == "yes" or fetch(:yes_or_no).chomp.downcase == "no"
        ask :yes_or_no, "Networking on the VM has not come up in 30 seconds, would you like to wait another 30?"
      end
      if fetch(:yes_or_no).chomp.downcase == "yes"
        Rake::Task['wait_for_ping'].reenable
        return Rake::Task['wait_for_ping'].invoke
      else
        warn "Exiting.."
        exit
      end
    end
  end
end

# TODO confirm and remove auto-setup of agent forwarding,
#   not only is this not idempotent (it continually adds to `.ssh/config`),
#   but it should not be needed, since capistrano forwards the agent automatically.
#   Manual SSH configuration for agent fowarding should be needed. - Confirm VM creation still work this way.
task :setup_agent_forwarding => 'libvirtinator:load_settings' do
  run_locally do
    lines = <<-eos
\nHost #{fetch(:node_fqdn)}
  ForwardAgent yes
Host #{fetch(:hostname)}
  ForwardAgent yes
Host #{fetch(:app_fqdn)}
  ForwardAgent yes
Host #{fetch(:ip)}
  ForwardAgent yes
Host #{fetch(:node_name)}
  ForwardAgent yes\n
    eos
    {ENV['USER'] => "/home/#{ENV['USER']}/.ssh"}.each do |user, dir|
      if File.directory?(dir)
        unless File.exists?("#{dir}/config")
          execute "sudo", "-u", "#{user}", "touch", "#{dir}/config"
          execute "chmod", "600", "#{dir}/config"
        end
        execute "echo", "-e", "\"#{lines}\"", ">>", "#{dir}/config"
      end
    end
  end
end

task :wait_for_ssh_alive => 'libvirtinator:load_settings' do
  run_locally do
    info "Waiting for VM SSH alive.."
    begin
      Timeout::timeout(30) do
        (print "..."; sleep 3) until (TCPSocket.open(fetch(:ip),22) rescue nil)
      end
    rescue TimeoutError
      set :yes_or_no, ""
      until fetch(:yes_or_no).chomp.downcase == "yes" or fetch(:yes_or_no).chomp.downcase == "no"
        ask :yes_or_no, "SSH on the VM has not come up in 30 seconds, would you like to wait another 30?"
      end
      if fetch(:yes_or_no).chomp.downcase == "yes"
        Rake::Task['wait_for_ssh_alive'].reenable
        return Rake::Task['wait_for_ssh_alive'].invoke
      else
        warn "Exiting.."
        exit
      end
    end
    info "SSH alive!"
  end
end
