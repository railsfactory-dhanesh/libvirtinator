# vim: set filetype=ruby :
  require 'rubygems'
  require 'json'
  require 'hashie'
  require 'sshkit'
  require 'sshkit/dsl'

  desc "Idempotently setup unix users using SSH, sudo rights, and 2 Hashie::Mash'es of attributes."
  def setup(vm_dna, users_dna)
    ensure_running_as_root

    SSHKit::Backend::Netssh.configure do |ssh|
      ssh.ssh_options = {
        keys: get_private_key_path,
        forward_agent: false,
        auth_methods: %w(publickey)
      }
    end

    raise "Need to pass vm_dna!" if vm_dna.empty?
    raise "Need to pass users_dna!" if users_dna.empty?
    on "#{get_user}@#{vm_dna.node.networking.ip}" do |host|
      # sysadmins users
      unless users_dna.usergroups.sysadmins.nil? or users_dna.usergroups.sysadmins.empty?
        users_dna.usergroups.sysadmins.each do |user|
          key_file = "/home/#{user.name}/.ssh/authorized_keys"
          if user.disabled
            if test "sudo id -u #{user.name}"
              execute "sudo bash -c \"echo '' > #{key_file}\""
              execute "sudo passwd -d #{user.name}"
              say "Disabled user #{user.name}", :yellow
            end
          else
            unless test "sudo id -u #{user.name}"
              exit unless test "sudo adduser --disabled-password --gecos \'\' #{user.name}"
            end
            execute "sudo usermod -s '/bin/bash' #{user.name}"
            execute "sudo usermod -a -G sudo #{user.name}"
            execute "sudo usermod -a -G docker #{user.name}"
            execute "sudo mkdir -p /home/#{user.name}/.ssh"
            execute "sudo chown #{user.name}. -R /home/#{user.name}"
            execute "sudo chmod 700 /home/#{user.name}/.ssh"
            contents = StringIO.new("#{user.ssh_keys.join("\n\n")}\n")
            upload! contents, "/tmp/temp_authorized_keys"
            execute "sudo mv /tmp/temp_authorized_keys /home/#{user.name}/.ssh/authorized_keys"
            execute "sudo chown #{user.name}. #{key_file}"
            execute "sudo chmod 600 #{key_file}"
          end
        end
      end

      # SFTP users
      unless users_dna.usergroups.sftp_users.nil? or users_dna.usergroups.sftp_users.empty?
        unless test "sudo egrep -i \"^chrooted\" /etc/group"
          exit unless test "sudo addgroup --gid 3300 #{user.name}"
        end
        users_dna.usergroups.sftp_users.each do |user|
          key_file = "/home/#{user.name}/.ssh/authorized_keys"
          if user.disabled
            if test "sudo id -u #{user.name}"
              execute "sudo bash -c \"echo '' > #{key_file}\""
              execute "sudo passwd -d #{user.name}"
              say "Disabled user #{user.name}", :yellow
            end
          else
            unless test "sudo id -u #{user.name}"
              exit unless test "sudo adduser --disabled-password --gecos \'\' #{user.name}"
            end
            execute "sudo usermod -s '/bin/bash' #{user.name}"
            execute "sudo usermod -a -G chrooted #{user.name}"
            execute "sudo mkdir -p /home/#{user.name}/.ssh"
            user.directories.each do |directory|
              execute "sudo mkdir -p /home/#{user.name}/#{directory}"
            end
            execute "sudo chown #{user.name}. -R /home/#{user.name}"
            execute "sudo chmod 700 /home/#{user.name}/.ssh"
            contents = StringIO.new("#{user.ssh_keys.join("\n\n")}\n")
            upload! contents, "/tmp/temp_authorized_keys"
            execute "sudo mv /tmp/temp_authorized_keys /home/#{user.name}/.ssh/authorized_keys"
            execute "sudo chown #{user.name}. #{key_file}"
            execute "sudo chmod 600 #{key_file}"
            execute "sudo bash -c \"echo '#{user.password}' | chpasswd\"" unless user.password.empty?
          end
        end
      end
    end
    say "Finished setting up users", :green
  end

  desc "Invoke thor users:setup, using attributes in a json file that references 2 other json files."
  def setup_from_file(vm_json_file)
    raise "Need to pass vm_json_file!" if vm_json_file.empty?
    vm_dna = load_vm_json_file(vm_json_file)
    invoke "setup", [vm_dna, load_users_json_file(vm_dna)]
  end

  private
    def load_vm_json_file(vm_json_file)
      raise "Need to pass vm_json_file!" if vm_json_file.empty?
      Hashie::Mash.new(JSON.parse(File.read(vm_json_file)))
    end

    def load_users_json_file(vm_dna)
      raise "Need to pass vm_dna!" if vm_dna.empty?
      Hashie::Mash.new(JSON.parse(File.read(vm_dna.users_json_file)))
    end

    def ensure_running_as_root
      unless Process.uid == 0
        say 'Run me as root!', :red
        exit
      end
    end

    def get_private_key_path
      path = ""
      until File.exists?(path) and (! File.directory?(path))
        path = ask "Which private key has SSH access to the VM? Specifiy an absolute path:", :yellow
      end
      return path
    end

    def get_user
      user = ""
      while user.strip.empty?
        user = ask "Which user has SSH access to the VM with the specified key?", :yellow
      end
      return user
    end
