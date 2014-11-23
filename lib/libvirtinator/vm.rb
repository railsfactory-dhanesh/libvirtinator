# vim: set filetype=ruby :
require 'rubygems'

require 'socket'
require 'timeout'

namespace :vm do
  desc "Start a copy-on-write Virtual Machine from a base image."
  task :start do
    on roles(:app) do
      info "Preparing to start #{fetch(:node_name)}"
      Rake::Task['vm:ensure_nbd_module'].invoke
      Rake::Task['vm:ensure_root_partitions_path'].invoke
      Rake::Task['vm:ensure_vm_not_running'].invoke
      Rake::Task['vm:ensure_ip_no_ping'].invoke
      Rake::Task['vm:ensure_vm_not_defined'].invoke
      Rake::Task['vm:verify_base'].invoke
      Rake::Task['vm:remove_root_image'].invoke
      Rake::Task['vm:create_root_image'].invoke
      begin
        Rake::Task["img:mount"].invoke
        Rake::Task['vm:update_root_image'].invoke
      ensure
        Rake::Task["img:umount"].invoke
      end
      Rake::Task['vm:create_data'].invoke
      Rake::Task['vm:define_domain'].invoke
      Rake::Task['vm:start_domain'].invoke
      Rake::Task['vm:reset_known_hosts_on_host'].invoke
      Rake::Task['vm:setup_agent_forwarding'].invoke
      Rake::Task['vm:wait_for_ping'].invoke
      Rake::Task['vm:wait_for_ssh_alive'].invoke
      Rake::Task['users:setup'].invoke
      info "Say, you don't say? Are we finished?"
    end
  end

  task :ensure_root_partitions_path do
    on roles(:app) do
      as :root do
        dir = fetch(:root_partitions_path)
        unless test "[", "-d", dir, "]"
          fatal "Error: root partitions path #{dir} is not a directory!" && raise
        end
      end
    end
  end

  task :ensure_nbd_module do
    on roles(:app) do
      as :root do
        unless test("lsmod | grep -q nbd")
          info 'Running modprobe nbd'
          execute "modprobe", "nbd"
        end
        unless test("lsmod | grep -q nbd")
          fatal "Error: Unable to modprobe nbd!" && raise
        end
      end
    end
  end

  task :ensure_vm_not_running do
    on roles(:app) do
      as :root do
        if test("virsh", "list", "|", "grep", "-q", "#{fetch(:node_name)}")
          fatal "The VM #{fetch(:node_name)} is already running!" && raise
        end
      end
    end
  end

  task :ensure_ip_no_ping do
    run_locally do
      info "Attempting to ping #{fetch(:ip)}"
      if system "bash -c \"ping -c 3 -w 5 #{fetch(:ip)} &> /dev/null\""
        fatal "The IP #{fetch(:ip)} is already pingable!"
        raise
      else
        info "No ping returned, continuing"
      end
    end
  end

  task :ensure_vm_not_defined do
    on roles(:app) do
      as :root do
        if test("virsh", "list", "--all", "|", "grep", "-q", "#{fetch(:node_name)}")
          ask :yes_or_no, "The VM #{fetch(:node_name)} is defined but not running! Do you want to undefine/redefine it?"
          unless fetch(:yes_or_no).chomp.downcase == "yes"
            raise
          else
            execute "virsh", "undefine", fetch(:node_name)
          end
        end
      end
    end
  end

  task :verify_base do
    on roles(:app) do
      as :root do
        unless test "[", "-f", fetch(:base_image_path), "]"
          fatal "Error: cannot find the base image #{fetch(:base_image_path)}" && raise
        end
        raise unless test("chown", "libvirt-qemu:kvm", fetch(:base_image_path))
      end
    end
  end

  task :remove_root_image do
    on roles(:app) do
      as :root do
        # use 'cap <server> create recreate_root=true' to recreate the root image
        if ENV['recreate_root'] == "true"
          if test "[", "-f", root_image_path, "]"
            ask :yes_or_no, "Are you sure you want to remove the existing #{root_image_path} file?"
            if fetch(:yes_or_no).chomp.downcase == "yes"
              info "Removing old image"
              execute "rm", root_image_path
            end
          end
        end
      end
    end
  end

  task :create_root_image do
    on roles(:app) do
      as :root do
        unless test "[", "-f", fetch(:root_image_path), "]"
          info "Creating new image"
          execute "qemu-img", "create", "-b", fetch(:base_image_path), "-f", "qcow2", fetch(:root_image_path)
        else
          ask :yes_or_no, "#{fetch(:root_image_path)} already exists, do you want to continue to update it's configuration?"
          if fetch(:yes_or_no).chomp.downcase == "yes"
            info "Updating file on an existing image."
          else
            raise
          end
        end
      end
    end
  end

  task :update_root_image do
    on roles(:app) do
      as :root do
        # TODO changes this to setup current user for sudo access instead of using root.
        mount_point = fetch(:mount_point)
        raise if mount_point.nil?
        execute "sed", "-i''", "'/PermitRootLogin/c\PermitRootLogin yes'",
          "#{mount_point}/etc/ssh/sshd_config"
        set :logs_path,         -> { fetch(:internal_logs_path) }
        @internal_logs_path     = fetch(:logs_path)
        @node_name              = fetch(:node_name)
        @node_fqdn              = fetch(:node_fqdn)
        @app_fqdn               = fetch(:app_fqdn)
        @hostname               = fetch(:hostname)
        @data_disk_gb           = fetch(:data_disk_gb)
        @data_disk_partition    = fetch(:data_disk_partition)
        @data_disk_mount_point  = fetch(:data_disk_mount_point)
        @network                = fetch("#{fetch(:cidr)}_network")
        @gateway                = fetch("#{fetch(:cidr)}_gateway")
        @ip                     = fetch(:ip)
        @broadcast              = fetch("#{fetch(:cidr)}_broadcast")
        @netmask                = fetch("#{fetch(:cidr)}_netmask")
        @dns_nameservers        = fetch(:dns_nameservers)
        @dns_search             = fetch(:dns_search)
        [
          "sudoers-sudo"      => "#{mount_point}/etc/sudoers.d/sudo",
          "hosts"             => "#{mount_point}/etc/hosts",
          "hostname"          => "#{mount_point}/etc/hostname",
          "fstab"             => "#{mount_point}/etc/fstab",
          "interfaces"        => "#{mount_point}/etc/network/interfaces",
        ].each do |file, path|
          template = File.new(File.expand_path("./templates/#{file}.erb")).read
          generated_config_file = ERB.new(template).result(binding)
          upload! StringIO.new(generated_config_file), "/tmp/#{file}.file"
          execute("mv", "/tmp/#{file}.file", path)
          execute("chown", "root:root", path)
        end
        execute "chmod", "440", "#{mount_point}/etc/sudoers.d/*"
        execute "echo", "-e", "\"\n#includedir /etc/sudoers.d\n\"", ">>", "#{mount_point}/etc/sudoers"
        execute "mkdir", "-p", "#{mount_point}/root/.ssh"
        execute "chmod", "700", "#{mount_point}/root/.ssh"
        path = ""
        until File.exists? path and ! File.directory? path
          ask :path, "Which public key should we install in the root user's authorized_keys file? Specifiy an absolute path:"
        end
        upload! File.open(fetch(:path)), "/tmp/pubkeys"
        execute "mv", "/tmp/pubkeys", "#{mount_point}/root/.ssh/authorized_keys"
        execute("chown", "root:root", "#{mount_point}/root/.ssh/authorized_keys")
        execute "chmod", "600", "#{mount_point}/root/.ssh/authorized_keys"
        execute "mkdir", "-p", "#{mount_point}/#{fetch(:data_disk_mount_point)}" unless data_disk_gb == "0"
      end
    end
  end

  task :create_data do
    on roles(:app) do
      as 'root' do
        vg_path = fetch(:data_vg_path)
        lv_name = "#{fetch(:node_name)}-data"
        lv_path = "#{vg_path}/#{lv_name}"
        size_gb = fetch(:data_disk_db)
        if size_gb == "0"
          info "Not using a separate data disk."
          return
        end
        if fetch(:data_disk_type) == "qemu"
          if ! test("[", "-f", "#{fetch(:root_partitions_path)}/#{fetch(:node_name)}-data.qcow2", "]") or ENV['recreate_data'] == "true"
            execute "guestfish", "--new", "disk:#{fetch(:data_disk_gb)}G << _EOF_
  mkfs ext4 /dev/vda
  _EOF_"
            execute "qemu-img", "convert", "-O", "qcow2", "test1.img", "test1.qcow2"
            execute "rm", "test1.img"
            execute "mv", "test1.qcow2", "#{fetch(:root_partitions_path)}/#{fetch(:node_name)}-data.qcow2"
          end
        elsif fetch(:data_disk_type) == "lv"
          if ENV['recreate_data'] == "true"
            if test "[", "-f", lv_path, "]"
              Rake::Task['lv:recreate'].invoke(vg_path, lv_name, size_gb)
            else
              Rake::Task['lv:create'].invoke(vg_path, lv_name, size_gb)
            end
          else
            if test "[", "-f", lv_path, "]"
              info "Found and using existing logical volume #{lv_path}"
            else
              Rake::Task['lv:create'].invoke(vg_path, lv_name, size_gb)
            end
          end
        else
          fatal "No recognized disk type (lv, qemu), yet size is greater than zero!"
          fatal "Fixed this by adding a recognized disk type (lv, qemu) to your config."
          raise
        end
      end
    end
  end

  task :define_domain do
    on roles(:app) do
      as 'root' do
        # instance variables needed for ERB
        @node_name              = fetch(:node_name)
        @memory_gb              = fetch(:memory_gb).to_i * 1024 * 1024
        @cpus                   = fetch(:cpus)
        @root_partitions_path   = fetch(:root_partitions_path)
        @data_disk_gb           = fetch(:data_disk_gb)
        @data_disk_type         = fetch(:data_disk_type)
        @data_vg_path           = fetch(:data_vg_path)
        @bridge                 = fetch(:bridge)
        template = File.new(File.expand_path("templates/server.xml.erb")).read
        generated_config_file = ERB.new(template).result(binding)
        upload! StringIO.new(generated_config_file), "/tmp/server.xml"
        execute "virsh", "define", "/tmp/server.xml"
        execute "rm", "/tmp/server.xml", "-rf"
      end
    end
  end

  task :start_domain do
    on roles(:app) do
      as 'root' do
        execute "virsh", "start", "#{fetch(:node_name)}"
      end
    end
  end

  # Keep this to aid with users setup
  task :reset_known_hosts_on_host do
    run_locally do
      user = if ENV['SUDO_USER']; ENV['SUDO_USER']; else; ENV['USER']; end
      execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:node_name)}"
      execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:node_fqdn)}"
      execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:hostname)}"
      execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:app_fqdn)}"
      execute "sudo", "-u", user, "ssh-keygen", "-R", "#{fetch(:ip)}"
    end
  end

  task :wait_for_ping do
    run_locally do
      info "Waiting for VM to respond to ping.."
      begin
        Timeout::timeout(30) do
          until system "bash -c \"ping -c 3 -w 5 #{fetch(:ip)} &> /dev/null\"" do
            print ' ...'
          end
          info "Ping alive!"
        end
      rescue Timeout::Error
        puts
        ask :yes_or_no, "Networking on the VM has not come up in 30 seconds, would you like to wait another 30?"
        if fetch(:yes_or_no).chomp.downcase == "yes"
          Rake::Task['vm:wait_for_ping'].reenable
          return Rake::Task['vm:wait_for_ping'].invoke
        else
          warn "Exiting.."
          exit
        end
      end
    end
  end

  task :setup_agent_forwarding do
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

  task :wait_for_ssh_alive do
    run_locally do
      info "Waiting for VM SSH alive.."
      begin
        Timeout::timeout(30) do
          (print "..."; sleep 3) until (TCPSocket.open(fetch(:ip),22) rescue nil)
        end
      rescue TimeoutError
        ask :yes_or_no, "SSH on the VM has not come up in 30 seconds, would you like to wait another 30?"
        if fetch(:yes_or_no).chomp.downcase == "yes"
          Rake::Task['vm:wait_for_ssh_alive'].reenable
          return Rake::Task['vm:wait_for_ssh_alive'].invoke
        else
          warn "Exiting.."
          exit
        end
      end
      info "SSH alive!"
    end
  end
end
