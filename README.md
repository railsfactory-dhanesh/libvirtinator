libvirtinator
============

*Opinionatedly Deploy libvirt VM instances.*

This is a Capistrano 3.x plugin, and relies on SSH access with passwordless sudo rights.


### Installation:
* `gem install libvirtinator` (Or add it to your Gemfile and `bundle install`.)
* Add "require 'libvirtinator'" to your Capfile
`echo "require 'libvirtinator'" >> Capfile`
* Create example configs:
`cap write_example_configs`
* Turn them into real configs by removing the `_example` portions of their names, and adjusting their content to fit your needs. (Later when you upgrade to a newer version of libvirtinator, you can `cap write_example_configs` again and diff your current configs against the new configs to see what you need to add.)
* You can add any custom libvirt setting you need by adjusting the content of the ERB templates. You won't need to change them to get started, except for adding a valid SSL cert/key set.

### Usage:
`cap -T` will help remind you of the available commands, see this for more details.
* `cap libvirtinator:install`               # Write example config files
* `cap libvirtinator:install_vm`            # Write an example VM config file
* `cap <vm-name> status`                    # Check the current status of a VM
* `cap <vm-name> start`                     # Start a copy-on-write VM from a base image\*
* `cap <vm-name> users:setup`               # Idempotently setup admin UNIX users\*
* `cap users:setup_domain domain=example.com usergroups=sysadmins` # Idempotently setup admin UNIX users using only a domain name (or IP) and usergroup files\*
* `cap image:build_base`                    # Build a base qcow2 image
* `cap <vm-name> image:list_bases`          # Find the base image for each root qcow2 image on the VM's host machine

\* With these commands you can add `key_path=/home/<your_username>/.ssh/id_rsa` to the end, this will skip the required interactive question asking for the path to your private key (to be used like 'ssh -i key_path user@my_app.example.com'.)

### TODO:
* Setup useful errors/feedback when required variables are unset.
* Add a 'non-interactive=true' switch to all interactive questions
* Add reminder after setup finishes to `apt-get update && apt-get dist-upgrade`
* Remove usage of instance variables in .erb files, intead just use `fetch(:var)`
* Add ability to set filesystem type in each VM config file rather than in the fstab template (don't be locked into ext4)
* Confirm and remove auto-setup of agent forwarding
* Make users:setup failure invoke notice "don't worry, you can resume setting up users with 'cap <stage> users:setup'"
* Add a locking mechanism for keeping track of users for a VM, and disabling their accounts when removed from config
* Fix bug preventing usage on a Mac

###### Debugging:
* You can add the `--trace` option at the end of a command to see when which tasks are invoked, and when which task is actually executed.
* If you want to put on your DevOps hat, you can run `cap -T -A` to see each individually available task, and run them one at a time to debug each one.

