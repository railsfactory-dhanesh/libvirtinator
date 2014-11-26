namespace :image do
  desc "Build a base qcow2 image."
  task :build_base do
    on roles(:app) do
      as :root do
        ["first_boot.sh", "vmbuilder-init.sh", "vmbuilder.cfg"].each do |file|
          template = File.new(File.expand_path("templates/#{file}.erb")).read
          generated_config_file = ERB.new(template).result(binding)
          upload! StringIO.new(generated_config_file), "/tmp/#{file}"
          execute("chown", "-R", "root:root", "/tmp/#{file}")
          execute("chmod", "770", "/tmp/#{file}")
        end
        # rootsize & swapsize settings do not get picked up in cfg file, so set here
        if test "vmbuilder", fetch(:vmbuilder_run_command)
          execute "mv /tmp/#{fetch(:release_name)}/*.qcow2 /tmp/#{fetch(:release_name)}/#{fetch(:release_name)}.qcow2"
          info("Build finished successfully!")
          info("You probably want to run 'cp /tmp/#{fetch(:release_name)}/#{fetch(:release_name)}.qcow2 <root partitions path>'.")
          info("If you ran this on a Ubuntu 14.04 or later host, you'll probabaly want to make the image compatible " +
              "with older versions of qemu using a command like this: 'sudo qemu-img amend -f qcow2 -o compat=0.10 #{fetch(:release_name)}.qcow2'.")
        end
        execute "rm", "/tmp/first_boot.sh", "-f"
      end
    end
  end

  #desc "Mount qcow2 image by creating a run file holding the nbd needed."
  task :mount do
    on roles(:app) do
      as :root do
        if test "[", "-f", fetch(:nbd_run_file), "]"
          unless test "[", "-f", fetch(:nbd_lock_file), "]"
            unless test "mountpoint", "-q", fetch(:mount_point)
              info "Removing leftover run file"
              execute "rm", fetch(:nbd_run_file), "-f"
              unless test "[", "-f", fetch(:nbd_run_file), "]"
                Rake::Task['image:mount'].reenable
                return Rake::Task['image:mount'].invoke
              end
            end
          end
          raise "nbd run file already exists. is it already connected?"
        end
        info "Mounting #{fetch(:root_image_path)} on #{fetch(:mount_point)}"
        set :nbd_connected, false
        until fetch(:nbd_connected)
          Rake::Task['image:connect_to_unused_nbd'].reenable
          Rake::Task['image:connect_to_unused_nbd'].invoke
        end
        raise "Mount point #{fetch(:mount_point)} is already mounted" if test "mountpoint", "-q", fetch(:mount_point)
        execute "mkdir", "-p", fetch(:mount_point)
        execute "mount", fetch(:dev_nbdp1), fetch(:mount_point)
        raise "Failed to mount #{fetch(:mount_point)}" unless test "mountpoint", "-q", fetch(:mount_point)
        info "Mounted #{fetch(:root_image_path)} on #{fetch(:mount_point)} using #{fetch(:dev_nbd)}"
      end
    end
  end

  #desc "Un-mount qcow2 image"
  task :umount do
    on roles(:app) do
      as :root do
        if test "[", "-f", fetch(:nbd_run_file), "]"
          info "found #{fetch(:nbd_run_file)}"
        else
          info "Unable to read #{fetch(:nbd_run_file)}"
        end
        set :nbd, capture("cat", fetch(:nbd_run_file)).chomp
        unless test "mountpoint", "-q", fetch(:mount_point)
          info "#{fetch(:mount_point)} is not mounted"
        end
        info "Unmounting root image #{fetch(:root_image_path)}"
        execute "umount", fetch(:mount_point)
        if test "mountpoint", "-q", fetch(:mount_point)
          info "Failed to umount #{fetch(:mount_point)}"
        end
        Rake::Task['image:disconnect_from_nbd'].invoke
        execute "rm", fetch(:mount_point), "-rf"
        raise "Failed to remove #{fetch(:mount_point)}" if test "[", "-d", fetch(:mount_point), "]"
      end
    end
  end

  desc "Find the base image for each root qcow2 image."
  task :list_bases do
    on roles(:app) do
      as :root do
        set :files, -> { capture("ls", "#{fetch(:root_partitions_path)}/*.qcow2" ).split }
        if fetch(:files, "").empty?
          fatal "Error: No qcow2 files found in #{fetch(:root_partitions_path)}"
          exit
        end
        fetch(:files).each do |image_file|
          backing_file = ""
          capture("qemu-img info #{image_file}").each_line do |line|
            if line =~ /backing\ file:/
              backing_file = line.split[2]
            end
          end
          unless backing_file.empty?
            info "#{backing_file} < #{image_file}"
          else
            info "No backing file found for #{image_file}"
          end
        end
      end
    end
  end

  task :connect_to_unused_nbd do
    on roles(:app) do
      as :root do
        set :prelock, -> { "#{fetch(:nbd_lock_file)}.prelock" }
        begin
          raise "Error: #{fetch(:root_image_path)} not found!" unless test "[", "-f", fetch(:root_image_path), "]"
          set :nbd, "nbd#{rand(16)}"
          info "Randomly trying the #{fetch(:nbd)} network block device"
          if test "[", "-f", fetch(:prelock), "]"
            info "Another process is checking #{fetch(:nbd)}. Trying again..."
            set :nbd_connected, false
            return
          else
            execute "touch", fetch(:prelock)
            info "Checking for qemu-nbd created lock file"
            if test "[", "-f", fetch(:nbd_lock_file), "]"
              info "#{fetch(:dev_nbd)} lockfile already in place - nbd device may be in use. Trying again..."
              set :nbd_connected, false
              return
            end
            if test "[", "-b", fetch(:dev_nbdp1), "]"
              info "nbd device in use but no lockfile, Trying again..."
              set :nbd_connected, false
              return
            end
            info "Found unused block device"

            execute "qemu-nbd", "-c", fetch(:dev_nbd), fetch(:root_image_path)
            info "Waiting for block device to come online . . . "
            begin
              Timeout::timeout(20) do
                until test "[", "-b", fetch(:dev_nbdp1), "]"
                  sleep 3
                end
                execute "echo", fetch(:nbd), ">", fetch(:nbd_run_file)
                info "device online"
                set :nbd_connected, true
              end
            rescue TimeoutError
              fatal "Error: unable to create block dev #{fetch(:dev_nbd)}, trying again..."
              set :nbd_connected, false
              return
              #raise "unable to create block device #{fetch(:dev_nbd)}"
            end
          end
        ensure
          execute "rm", fetch(:prelock), "-f"
        end
      end
    end
  end

  task :disconnect_from_nbd do
    on roles(:app) do
      as :root do
        execute "qemu-nbd", "-d", fetch(:dev_nbd)
        info "Waiting for block device to go offline . . . "
        begin
          Timeout::timeout(20) do
            while test "[", "-b", fetch(:dev_nbdp1), "]"
              print ". "
              sleep 3
            end
            info "block device offline"
          end
        rescue TimeoutError
          info "Error: unable to free block dev #{fetch(:dev_nbd)}"
          execute "rm", fetch(:nbd_run_file), "-rf"
          execute "touch", fetch(:nbd_lock_file)
          exit 1
        end
        raise "failed to free #{fetch(:dev_nbd)}" if test "[", "-b", fetch(:dev_nbdp1), "]"
        execute "rm", fetch(:nbd_run_file), "-rf"
      end
    end
  end
end
