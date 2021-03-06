Gem::Specification.new do |s|
  s.name        = 'libvirtinator'
  s.version     = '0.1.7'
  s.date        = '2016-04-08'
  s.summary     = "Deploy libvirt VMs"
  s.description = "An Opinionated libvirt VM Deployment gem"
  s.authors     = ["david amick"]
  s.email       = "davidamick@ctisolutionsinc.com"
  s.files       = [
    "lib/libvirtinator.rb",
    "lib/libvirtinator/config.rb",
    "lib/libvirtinator/vm.rb",
    "lib/libvirtinator/users.rb",
    "lib/libvirtinator/image.rb",
    "lib/libvirtinator/lv.rb",
    "lib/libvirtinator/examples/Capfile",
    "lib/libvirtinator/examples/config/deploy.rb",
    "lib/libvirtinator/examples/config/deploy/vm_name.rb",
    "lib/libvirtinator/examples/config/sysadmins_keys.rb",
    "lib/libvirtinator/examples/first_boot.sh.erb",
    "lib/libvirtinator/examples/fstab.erb",
    "lib/libvirtinator/examples/hostname.erb",
    "lib/libvirtinator/examples/hosts.erb",
    "lib/libvirtinator/examples/interfaces.erb",
    "lib/libvirtinator/examples/server.xml.erb",
    "lib/libvirtinator/examples/sudoers-sudo.erb",
    "lib/libvirtinator/examples/vmbuilder-init.sh.erb",
    "lib/libvirtinator/examples/vmbuilder.cfg.erb"
  ]
  s.required_ruby_version   =   '>= 1.9.3'
  s.add_runtime_dependency  'capistrano',  '~> 3.2.1'
  s.add_runtime_dependency  'net-ssh',     '~> 2.9.1'
  s.homepage                =   'https://github.com/snarlysodboxer/libvirtinator'
  s.license                 =   'GNU'
end
