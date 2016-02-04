namespace :users do

  task :load_settings => 'libvirtinator:load_settings' do
    if fetch(:private_key_path).nil?
      SSHKit::Backend::Netssh.configure do |ssh|
        ssh.ssh_options = {
          forward_agent: false,
          auth_methods: %w(publickey)
        }
      end
    else
      SSHKit::Backend::Netssh.configure do |ssh|
        ssh.ssh_options = {
          keys: fetch(:private_key_path),
          forward_agent: false,
          auth_methods: %w(publickey)
        }
      end
    end
  end

  desc "Idempotently setup admin UNIX users using only a domain name (or IP) and usergroups files"
  task :setup_domain => 'libvirtinator:load_settings' do
    if ENV['domain'].nil? or ENV['usergroups'].nil?
      fatal "Please set domain and usergroups like 'cap users:setup_domain domain=example.com usergroups=sysadmins,others'"
      exit
    end
    set :ip,          -> { ENV['domain'] }
    set :usergroups,  -> { Array(ENV['usergroups'].split',') }
    Rake::Task['users:setup'].invoke
  end

  desc "Idempotently setup admin UNIX users."
  task :setup => ['libvirtinator:load_settings', 'users:load_settings'] do
    on "#{fetch(:user)}@#{fetch(:ip)}" do
      as :root do
        fetch(:usergroups).each do |usergroup|
          usergroup = usergroup.to_sym
          require "./config/#{usergroup}_keys.rb"
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
                exit unless test "useradd", "--user-group", "--shell", "/bin/bash", "--create-home", user['name']
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
      run_locally do
        unless fetch(:private_key_path).nil?
          execute "rm", "-f", "#{fetch(:private_key_path)}*"
        end
      end
      info "Finished setting up users"
      end
    end
  end
end
