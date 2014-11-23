# vim: set filetype=ruby :
require 'rubygems'
require 'json'
require 'hashie'
require 'lockfile'

desc "Build a base qcow2 image."
task :build_base do
  on roles(:app) do
    as :root do
      ["first_boot.sh", "vmbuilder-init.sh", "vmbuilder.cfg"].each do |file|
        generated_config_file = generate_config_file("templates/#{file}.erb")
        upload! StringIO.new(generated_config_file), "/tmp/#{file}"
        execute("chown", "-R", "root:root", "/tmp/#{file}")
        execute("chmod", "770", "/tmp/#{file}")
      end
      # rootsize & swapsize settings do not get picked up in cfg file, so set here
      if test fetch(:vmbuilder_run_command)
        execute "mv /tmp/#{fetch(:release_name)}/*.qcow2 /tmp/#{fetch(:release_name)}/#{fetch(:release_name)}.qcow2"
        info("Build finished successfully!")
        info("You probably want to run 'cp /tmp/#{fetch(:release_name)}/#{fetch(:release_name)}.qcow2 <root partitions path>'.")
        info("If you ran this on a Ubuntu 14.04 or later host, you'll probabaly want to make the image compatible " +
            "with older versions of qemu using a command like this: 'sudo qemu-img amend -f qcow2 -o compat=0.10 #{fetch(:release_name)}.qcow2'.")
      end
      remove_file "/tmp/first_boot.sh"
    end
  end
end

  desc "Mount qcow2 image by creating a run file holding the nbd needed."
  def mount(vm_dna, host_dna)
    raise "Need to pass vm_dna!" if vm_dna.empty?
    raise "Need to pass host_dna!" if host_dna.empty?
    ensure_nbd_module
    if nbd_run_file(vm_dna).readable?
      unless lock_file.exist?
        unless mount_point(vm_dna, host_dna).mountpoint?
          say "Removing leftover run file", :red
          remove_file nbd_run_file(vm_dna)
          unless nbd_run_file(vm_dna).exist?
            return mount(vm_dna, host_dna)
          end
        end
      end
      raise "nbd run file already exists. is it already connected?"
    end
    say "Mounting #{root_image(vm_dna, host_dna)} on #{mount_point(vm_dna, host_dna)}", :green
    until connect_to_unused_nbd(vm_dna, host_dna)
      say "Trying again...", :green
    end
    raise "Mount point #{mount_point(vm_dna, host_dna)} is already mounted" if mount_point(vm_dna, host_dna).mountpoint?
    empty_directory(mount_point(vm_dna, host_dna))
    #run "sudo mkdir -p #{mount_point(vm_dna, host_dna)}"
    run "sudo mount #{dev_nbdp1} #{mount_point(vm_dna, host_dna)}"

    raise "Failed to mount #{mount_point(vm_dna, host_dna)}" unless mount_point(vm_dna, host_dna).mountpoint?
    say "Mounted #{root_image(vm_dna, host_dna)} on #{mount_point(vm_dna, host_dna)} using #{dev_nbd}", :green
  end

  desc "Invoke thor img:mount, using attributes in a json file that references another json file."
  def mount_from_file(vm_json_file)
    raise "Need to pass vm_json_file!" if vm_json_file.empty?
    vm_dna = load_vm_json_file(vm_json_file)
    invoke "mount", [vm_dna, load_host_json_file(vm_dna)]
  end

  desc "Un-mount qcow2 image"
  def umount(vm_dna, host_dna)
    raise "Need to pass vm_dna!" if vm_dna.empty?
    raise "Need to pass host_dna!" if host_dna.empty?
    ensure_nbd_module
    if nbd_run_file(vm_dna).readable?
      say "found #{nbd_run_file(vm_dna)}", :green
    else
      say "Unable to read #{nbd_run_file(vm_dna)}", :red
    end
    @nbd = nbd_run_file(vm_dna).read
    unless mount_point(vm_dna, host_dna).mountpoint?
      say "#{mount_point(vm_dna, host_dna)} is not mounted", :red
      return false
    end
    say "Unmounting root image #{root_image(vm_dna, host_dna)}"
    run "umount #{mount_point(vm_dna, host_dna)}"
    if mount_point(vm_dna, host_dna).mountpoint?
      say "Failed to umount #{mount_point(vm_dna, host_dna)}", :red
      return false
    end
    disconnect_from_nbd(vm_dna)
    remove_dir "#{mount_point(vm_dna, host_dna)}"
    raise "Failed to remove #{mount_point(vm_dna, host_dna)}" if mount_point(vm_dna, host_dna).exist?
  end

  desc "Invoke thor img:umount, using attributes in a json file that references another json file."
  def umount_from_file(vm_json_file)
    raise "Need to pass vm_json_file!" if vm_json_file.empty?
    vm_dna = load_vm_json_file(vm_json_file)
    invoke "umount", [vm_dna, load_host_json_file(vm_dna)]
  end

  desc "Find the base image for each root qcow2 image."
  def list_bases(host_dna)
    raise "Need to pass host_dna!" if host_dna.empty?
    if `ls #{host_dna.node.root_partitions_path}` =~ /qcow2/
      files = `ls #{host_dna.node.root_partitions_path}/*.qcow2`.split
    else
      say "Error: No qcow2 files found in #{host_dna.node.root_partitions_path}", :red
      exit
    end
    files.each do |image_file|
      backing_file = ""
      `qemu-img info #{image_file}`.each_line do |line|
        if line =~ /backing\ file:/
          backing_file = line.split[2]
        end
      end
      unless backing_file.empty?
        say "#{backing_file} < #{image_file}", :green
      else
        say "No backing file found for #{image_file}", :yellow
      end
    end
  end

  desc "Invoke thor img:list_bases, using attributes in a json file."
  def list_bases_file(host_json_file)
    raise "Need to pass host_json_file!" if host_json_file.empty?
    invoke "list_bases", [Hashie::Mash.new(JSON.parse(File.read(host_json_file)))]
  end


  private
    def load_vm_json_file(vm_json_file)
      raise "Need to pass vm_json_file!" if vm_json_file.empty?
      Hashie::Mash.new(JSON.parse(File.read(vm_json_file)))
    end

    def load_host_json_file(vm_dna)
      raise "Need to pass vm_dna!" if vm_dna.empty?
      Hashie::Mash.new(JSON.parse(File.read(vm_dna.host_json_file)))
    end

    def ensure_nbd_module
      unless system("lsmod | grep -q nbd")
        say 'Running modprobe nbd', :yellow
        run "sudo modprobe nbd"
      end
      unless system("lsmod | grep -q nbd")
        say "Error: Unable to modprobe nbd!", :red
        exit
      end
    end

    # Try a random network block device
    # returning the nbd or false if it is in use
    def connect_to_unused_nbd(vm_dna, host_dna)
      raise "Need to pass vm_dna!" if vm_dna.empty?
      raise "Need to pass host_dna!" if host_dna.empty?
      raise "Error: #{root_image(vm_dna, host_dna)} not found!" unless root_image(vm_dna, host_dna).exist?
      begin
        Lockfile.new("#{lock_file}.prelock", :retries => 0) do
          @nbd = "nbd#{rand(16)}"
          say "Checking for qemu-nbd created lock file", :yellow
          if lock_file.exist?
            say "#{dev_nbd} lockfile already in place - nbd device may be in use. Trying again...", :red
            return false
          end
          if dev_nbdp1.blockdev?
            say "nbd device in use but no lockfile, Trying again...", :red
            return false
          end
          say "Found unused block device", :green

          run "sudo qemu-nbd -c #{dev_nbd} #{root_image(vm_dna, host_dna)}"
          say "Waiting for block device to come online . . . "
          begin
            Timeout::timeout(20) do
              until dev_nbdp1.blockdev?
                say ". "
                sleep 0.1
              end
              create_file nbd_run_file(vm_dna), @nbd
              say "device online", :green
            end
          rescue TimeoutError
            say "Error: unable to create block dev #{dev_nbd}, trying again...", :red
            return false
            #raise "unable to create block device #{dev_nbd}"
          end
        end
      rescue Lockfile::MaxTriesLockError => e
        say "Another process is checking #{nbd}. Trying again...", :red
        return false
      end
    end

    def disconnect_from_nbd(vm_dna)
      raise "Need to pass vm_dna!" if vm_dna.empty?
      run "sudo qemu-nbd -d #{dev_nbd}"
      say "Waiting for block device to go offline . . . "
      begin
        Timeout::timeout(20) do
          while dev_nbdp1.blockdev?
            say ". "
            sleep 0.1
          end
          say "block device offline", :green
        end
      rescue TimeoutError
        say "Error: unable to free block dev #{dev_nbd}", :red
        remove_dir nbd_run_file(vm_dna)
        create_file lock_file
        exit 1
      end
      raise "failed to free #{dev_nbd}" if dev_nbdp1.blockdev?
      remove_dir nbd_run_file(vm_dna)
    end

    def root_image(vm_dna, host_dna)
      raise "Need to pass vm_dna!" if vm_dna.empty?
      raise "Need to pass host_dna!" if host_dna.empty?
      Pathname.new "#{host_dna.node.root_partitions_path}/#{vm_dna.node.name}-root.qcow2"
    end

    def mount_point(vm_dna, host_dna)
      raise "Need to pass vm_dna!" if vm_dna.empty?
      raise "Need to pass host_dna!" if host_dna.empty?
      Pathname.new "#{host_dna.node.root_partitions_path}/#{vm_dna.node.name}-root.qcow2_mnt"
    end

    def lock_file
      Pathname.new "/var/lock/qemu-nbd-#{@nbd}"
    end

    def dev_nbd
      Pathname.new "/dev/#{@nbd}"
    end

    def dev_nbdp1
      Pathname.new "/dev/#{@nbd}p1"
    end

    def nbd_run_file(vm_dna)
      raise "Need to pass vm_dna!" if vm_dna.empty?
      Pathname.new "/var/lock/#{vm_dna.node.name}.nbd"
    end

    def generate_config_file(template_file_path)
      @internal_data_path           = fetch(:data_path)
      @internal_sites_enabled_path  = fetch(:sites_path)
      @domain                       = fetch(:cdomain)
      template_path = File.expand_path(template_file_path)
      ERB.new(File.new(template_path).read).result(binding)
    end
