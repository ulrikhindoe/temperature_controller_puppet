
#
# This Puppet manifest uses these Puppet modules:
#   puppet module install bashtoni/timezone
#   puppet module install example42/php
#   puppet module install example42/rclocal
#   puppet module install puppetlabs/apache
#   puppet module install puppetlabs/mysql
#   puppet module install thias/samba
#   puppet module install puppetlabs/vcsrepo
#
# Run this manifest with
#   puppet apply --modulepath /etc/puppet/modules/ /etc/puppet/manifests/init.pp
#


#####################################################################
# variables
#####################################################################

$username = "ulrik"
$group    = $username
$mysqlUserUsername = $username
$mysqlRootPassword = "mysqlRootPassword_CHANGE_THIS"
$mysqlUserPassword = "mysqlUserPassword_CHANGE_THIS"

$regulatorWebsiteUsername = $username
$regulatorWebsitePassword = "regulatorWebsitePassword_CHANGE_THIS"

$externalControllerWebsiteUrl      = "http://externalControllerWebsite_CHANGE_THIS"                                                     
$externalControllerWebsiteUsername = "temperature_controller"     
$externalControllerWebsitePassword = "externalControllerWebsitePassword_CHANGE_THIS"

$temperatureControllerCodeCloneUrl = "https://github.com/ulrikhindoe/temperature_controller_code.git"

$databaseName = "temperature_controller"
$timezoneRegion = 'Europe'
$timezoneLocality = 'Copenhagen'
$webSiteFolderName = 'temperature_controller'
$projectFolderName = 'temperature_controller'


#####################################################################
# nice to haves
#####################################################################


Exec { path => [ "/bin/", "/sbin/" , "/usr/bin/", "/usr/sbin/" ] }

package { "vim":
  ensure => installed,
}

#####################################################################
# user
#####################################################################

group { $group:
  ensure  => present,
}

user { $username:
  ensure  => present,
  gid     => $group,
  require => Group[$group],
  home    => "/home/${username}",
  shell   => "/bin/bash",
  managehome  => true,
}


#####################################################################
# timezone
#####################################################################

class { 'timezone': 
  region => $timezoneRegion,
  locality => $timezoneLocality, 
}


######################################################################
# PHP
######################################################################

class { 'php': }

php::module { "curl": }
php::module { "mysqlnd": }


######################################################################
# cronjob
######################################################################

cron { temperature_controller_cronjob:
  command => "/usr/bin/php /home/${username}/${projectFolderName}/cronjob/measure_and_regulate.php",
  user    => root,
  minute  => '*/1',
  require => [Class['php'], File["/home/${username}/${projectFolderName}/www/config.php"]]
}


###############################################################
# database
###############################################################

class { 'mysql::server':
  root_password => $mysqlRootPassword,
  databases => {
    "${databaseName}" => {
      ensure  => 'present',
      charset => 'utf8',
    },
  },
  users => {
    "${username}@localhost" => {
      ensure         => 'present',
      password_hash  => mysql_password($mysqlUserPassword)
    },
  },
  grants => {
    "${username}@localhost/${databaseName}.*" => {
      ensure     => 'present',
      options    => ['GRANT'],
      privileges => ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'CREATE'],
      table      => "$databaseName.*",
      user       => "${username}@localhost",
    },
  }
}

file { "/home/${username}/sql":
  path    => "/home/${username}/sql",
  ensure  => directory,
  group   => $group,
  owner   => $username,
  mode    => 0755,
  require  => [ User["${username}"] ],
}

file { "/home/${username}/sql/database_tables.sql":
  path    => "/home/${username}/sql/database_tables.sql",
  ensure  => file,
  group   => $group,
  owner   => $username,
  mode    => 0755,
  source  => 'file:///etc/puppet/manifests/files/database_tables.sql',
  require  => File["/home/${username}/sql"],
}


exec { "create_time_series_db_tables":
  command => "mysql -u${username} -p${mysqlUserPassword} ${databaseName} < /home/${username}/sql/database_tables.sql",
  require => [Class["mysql::server"], File["/home/${username}/sql/database_tables.sql"]]
}

###################################################################
# gpio
###################################################################

rclocal::script { "open_gpio17_for_relay_control":
  priority => "10",
  content  => "echo 17 > /sys/class/gpio/export\necho out > /sys/class/gpio/gpio17/direction\n",
}

file_line { 'w1-gpio':
  ensure => present,
  line => 'w1-gpio',
  path => '/etc/modules',
}

file_line { 'w1-therm':
  ensure => present,
  line => 'w1-therm',
  path => '/etc/modules',
  require => File_line["w1-gpio"]
}


######################################################################
# Apache - Not used yet
######################################################################

$apache = ['apache2', 'apache2.2-common']

package { $apache: 
  ensure => 'latest'	
}

service { 'apache2':
  ensure  => running,
  enable  => true,
  require => Package[$apache],
}

file { '/etc/apache2/apache2.conf':
  ensure  => present,
  source  => "file:///etc/puppet/manifests/files/apache2.conf",
  owner => 'root',
  group => 'root', mode => '0644',
  require => Package[$apache],
  notify  => Service['apache2'],
}

exec { 'userdir':
  notify  => Service['apache2'],
  command => '/usr/sbin/a2enmod userdir',
  require => Package[$apache],
}


######################################################################
# website
######################################################################

file { "/etc/apache2/sites-available/${webSiteFolderName}":
  ensure  => file,
  group   => "root",
  owner   => "root",
  mode    => 0644,
  content  => template("/etc/puppet/manifests/files/temperature_controller_apache_conf.erb"),
  require => Vcsrepo["/home/${username}/${projectFolderName}"],
}

package { 'git':
  ensure => "installed"
}

vcsrepo { "/home/${username}/${projectFolderName}":
  ensure => present,
  provider => git,
  owner    => $username,
  group    => $group,
  source => $temperatureControllerCodeCloneUrl,
  require  => [ User[$username], Package["git"] ],
}

file { "/home/${username}/${projectFolderName}/www/config.php":
  ensure => file,
  owner  => $username,
  group  => $group,
  content  => template("/etc/puppet/manifests/files/temperature_controller_config_php.erb"),	
  require => Vcsrepo["/home/${username}/${projectFolderName}"],
}

file { '/etc/apache2/sites-enabled/000-default':
   ensure => 'link',
   target => "/etc/apache2/sites-available/${webSiteFolderName}",
   require  => [ File["/etc/apache2/sites-available/${webSiteFolderName}"] ],
}



################################################################
# ssh
################################################################

#
# The public SSH key for the user $username shall be placed in the
# file /home/${username}/.ssh/authorized_keys
#
# The format of the line in /home/${username}/.ssh/authorized_keys is 
# something like "ssh-dss AAAAB...7Q=="
#
# When you have tested that ssh works with the public key you can disable
# password access by setting
#    PasswordAuthentication no
# in /etc/ssh/sshd_config and restarting Samba with 
#    sudo /etc/init.d/ssh reload
#

file { "/home/${username}/.ssh":
  ensure => directory,
  require => User["${username}"],
  group  => $group,
  owner => $username,
  mode  => '0700',	
}
 
file { "/home/${username}/.ssh/authorized_keys":
  ensure => present,
  group  => $group,
  owner => $username,
  mode  => '0600',
  require => File["/home/${username}/.ssh"],
} 

file_line { 'RSAAuthentication yes':
  ensure => present,
  line => 'RSAAuthentication yes',
  path => '/etc/ssh/sshd_config',
}

file_line { 'PubkeyAuthentication yes':
  ensure => present,
  line => 'PubkeyAuthentication yes',
  path => '/etc/ssh/sshd_config',
}

file_line { 'RSAAuthentication no':
  ensure => absent,
  line => 'RSAAuthentication no',
  path => '/etc/ssh/sshd_config',
}

file_line { 'PubkeyAuthentication no':
  ensure => absent,
  line => 'PubkeyAuthentication no',
  path => '/etc/ssh/sshd_config',
}

#####################################################################
# samba
#####################################################################

#
# After running this manifest set the Samba password for user $username with
#    sudo smbpasswd -a ulrik
# where ulrik should be replaced with $mysqlUserUsername
#

package {"samba-common-bin":
  ensure => installed,
}

class { 'samba::server':
  workgroup => 'WORKGROUP',
  shares => {
    'homes' => [
      "path = /home/${username}",
      'comment = Home Directories',
      'browseable = yes',
      'readable = yes',
      'writable = yes',
    ],
  },
  require => User["${username}"],
}

