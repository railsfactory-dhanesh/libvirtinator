libvirtinator
============

* this is an incomplete work in progress

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
* 

### TODO:
Fix needing to define a stage before being able to 'cap libvirtinator:install'
Test the build_base task.
Document better.

###### Debugging:
* You can add the `--trace` option at the end of a command to see when which tasks are invoked, and when which task is actually executed.
* If you want to put on your DevOps hat, you can run `cap -T -A` to see each individually available task, and run them one at a time to debug each one.

