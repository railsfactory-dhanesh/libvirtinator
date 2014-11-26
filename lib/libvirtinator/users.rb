namespace :users do

  task :load_settings do
    set :path, ""
    until File.exists?(fetch(:path)) and (! File.directory?(fetch(:path)))
      ask :path, "Which private key has SSH access to the VM? Specifiy an absolute path"
    end
    SSHKit::Backend::Netssh.configure do |ssh|
      ssh.ssh_options = {
        keys: fetch(:path),
        forward_agent: false,
        auth_methods: %w(publickey)
      }
    end
  end

  desc "Idempotently setup unix admin users using SSH with sudo rights."
  task :setup => :load_settings do
    on "#{fetch(:user)}@#{fetch(:ip)}" do
      as :root do
        fetch(:usergroups).each do |usergroup|
          usergroup = usergroup.to_sym
          next if fetch(usergroup).nil? or fetch(usergroup).empty?
          fetch(usergroup).each do |user|
            key_file = "/home/#{user['name']}/.ssh/authorized_keys"
            if user['disabled']
              if test "id", "-u", user['name']
                execute "bash", "-c", "\"echo", "''", ">", "#{key_file}\""
                execute "passwd", "-d", user['name']
                info "Disabled user #{user['name']}"
              end
            else
              unless test "id", "-u", user['name']
                exit unless test "adduser", "--disabled-password", "--gecos", "\'\'", user['name']
              end
              execute "usermod", "-s", "'/bin/bash'", user['name']
              user['groups'].each do |group|
                execute "usermod", "-a", "-G", group, user['name']
              end
              execute "mkdir", "-p", "/home/#{user['name']}/.ssh"
              execute "chown", "#{user['name']}.", "-R", "/home/#{user['name']}"
              execute "chmod", "700", "/home/#{user['name']}/.ssh"
              content = StringIO.new("#{user['ssh_keys'].join("\n\n")}\n")
              upload! content, "/tmp/temp_authorized_keys"
              execute "mv", "/tmp/temp_authorized_keys", "/home/#{user['name']}/.ssh/authorized_keys"
              execute "chown", "#{user['name']}.", "#{key_file}"
              execute "chmod", "600", "#{key_file}"
            end
          end
        end
      info "Finished setting up users"
      end
    end
  end
end
