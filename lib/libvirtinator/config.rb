module Capistrano
  module TaskEnhancements
    alias_method :original_default_tasks, :default_tasks
    def default_tasks
      original_default_tasks + [
        "libvirtinator:install",
        "libvirtinator:install_vm",
        "image:list_bases",
        "image:build_base",
        "users:setup_domain"
      ]
    end
  end
end

namespace :libvirtinator do
  task :load_settings do
    # load "./config/deploy.rb" # this seems unneeded and to cause tasks to run twice, previously i thought it was needed
    SSHKit.config.output_verbosity = fetch(:log_level)
  end

  desc 'Write example config files'
  task :install => 'libvirtinator:load_settings' do
    run_locally do
      execute "mkdir", "-p", "config/deploy", "templates/libvirtinator"
      {
        'examples/Capfile'                      => 'Capfile_example',
        'examples/config/deploy.rb'             => 'config/deploy_example.rb',
        'examples/config/sysadmins_keys.rb'     => 'config/sysadmins_keys_example.rb',
        'examples/config/deploy/vm_name.rb'     => 'config/deploy/vm_name_example.rb',
        'examples/first_boot.sh.erb'            => 'templates/libvirtinator/first_boot_example.sh.erb',
        'examples/fstab.erb'                    => 'templates/libvirtinator/fstab_example.erb',
        'examples/hostname.erb'                 => 'templates/libvirtinator/hostname_example.erb',
        'examples/hosts.erb'                    => 'templates/libvirtinator/hosts_example.erb',
        'examples/interfaces.erb'               => 'templates/libvirtinator/interfaces_example.erb',
        'examples/server.xml.erb'               => 'templates/libvirtinator/server_example.xml.erb',
        'examples/sudoers-sudo.erb'             => 'templates/libvirtinator/sudoers-sudo_example.erb',
        'examples/vmbuilder-init.sh.erb'        => 'templates/libvirtinator/vmbuilder-init_example.sh.erb',
        'examples/vmbuilder.cfg.erb'            => 'templates/libvirtinator/vmbuilder_example.cfg.erb',
      }.each do |source, destination|
        config = File.read(File.dirname(__FILE__) + "/#{source}")
        File.open("./#{destination}", 'w') { |f| f.write(config) }
        info "Wrote '#{destination}'"
      end
      info "Now remove the '_example' portion of their names or diff with existing files and add the needed lines."
    end
  end

  desc 'Write an example VM config file'
  task :install_vm => 'libvirtinator:load_settings' do
    run_locally do
      execute "mkdir", "-p", "config/deploy"
      {
        'examples/config/deploy/vm_name.rb'     => 'config/deploy/vm_name_example.rb',
      }.each do |source, destination|
        config = File.read(File.dirname(__FILE__) + "/#{source}")
        File.open("./#{destination}", 'w') { |f| f.write(config) }
        info "Wrote '#{destination}'"
      end
      info "Now remove the '_example' portion of the name or diff with existing files and add the needed lines."
    end
  end
end
