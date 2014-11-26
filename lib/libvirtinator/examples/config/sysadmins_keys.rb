set :sysadmins, [
  {
    "name"      => "username",
    "disabled"  => false,
    "groups"    => ["sudo", "docker"],
    "ssh_keys"  => [
      "ssh-rsa blahblahblah username@computer",
      "ssh-rsa blahblahblahother username@computer2"
    ]
  },
  {
    "name"      => "username-other",
    "disabled"  => false,
    "groups"    => ["sudo", "docker"],
    "ssh_keys"  => [
      "ssh-rsa blahblahblah username-other@computer",
      "ssh-rsa blahblahblahother username-other@computer2"
    ]
  }
]
