namespace :libvirtinator do
  set :stage, :staging
  desc 'Write example config files'
  task :install do
    run_locally do
      execute "mkdir", "-p", "config/deploy", "templates/libvirtinator"
      {
        'examples/Capfile'                    => 'Capfile_example',
        'examples/config/deploy.rb'           => 'config/deploy_example.rb',
        'examples/config/deploy/vm_name.rb'   => 'config/deploy/vm_name_example.rb',
        'examples/first_boot.sh.erb'          => 'templates/libvirtinator/first_boot_example.sh.erb',
        'examples/fstab.erb'                  => 'templates/libvirtinator/fstab_example.erb',
        'examples/hostname.erb'               => 'templates/libvirtinator/hostname_example.erb',
        'examples/hosts.erb'                  => 'templates/libvirtinator/hosts_example.erb',
        'examples/interfaces.erb'             => 'templates/libvirtinator/interfaces_example.erb',
        'examples/server.xml.erb'             => 'templates/libvirtinator/server_example.xml.erb',
        'examples/sudoers-sudo.erb'           => 'templates/libvirtinator/sudoers-sudo_example.erb',
        'examples/vmbuilder-init.sh.erb'      => 'templates/libvirtinator/vmbuilder-init_example.sh.erb',
        'examples/vmbuilder.cfg.erb'          => 'templates/libvirtinator/vmbuilder_example.cfg.erb',
      }.each do |source, destination|
        config = File.read(File.dirname(__FILE__) + "/#{source}")
        File.open("./#{destination}", 'w') { |f| f.write(config) }
        info "Wrote '#{destination}'"
      end
      info "Now remove the '_example' portion of their names or diff with existing files and add the needed lines."
    end
  end
end
