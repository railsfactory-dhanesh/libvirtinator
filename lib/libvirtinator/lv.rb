# vim: set filetype=ruby

  desc "Remove a logical volume and recreate it."
  def recreate(vg_path, lv_name, size_gb)
    # TODO raise if unsuccessful
    ensure_running_as_root
    path = Pathname.new("#{vg_path}/#{lv_name}")
    if yes? "Are you sure you want to delete and recreate the logical volume #{path}?", :red
      if path.exist?
        run "lvremove --force #{path}"
        run "sleep 1"
      else
        say "Error: #{path} not found!", :red
      end
      invoke "create", [vg_path, lv_name, size_gb]
    end
  end

  desc "Create a logical volume."
  def create(vg_path, lv_name, size_gb)
    # TODO raise if unsuccessful
    ensure_running_as_root
    if run "lvcreate #{vg_path} -L #{size_gb}G -n #{lv_name}"
      invoke "mkfs", ["#{vg_path}/#{lv_name}"]
    end
  end

  desc "Create an ext4 filesystem."
  def mkfs(path)
    ensure_running_as_root
    path = Pathname.new(path)
    unless path.exist?
      raise "Tried to create filesystem but path does not exist!"
    end
    run "mkfs.ext4 -q -m 0 #{path}"
  end


  private
    def ensure_running_as_root
      unless Process.uid == 0
        say 'Run me as root!', :red
        exit
      end
    end
