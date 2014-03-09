Exec { path => [ "/bin/", "/sbin/" , "/usr/bin/", "/usr/sbin/" ] }


package { "vim":
  ensure => installed,
}

package { 'git':
  ensure => "installed"
}



#####################################################################
# ulrik
#####################################################################

$username = "ulrik"
$group    = "ulrik"


group { $group:
  ensure  => present,
}

user { $username:
  ensure  => present,
  gid     => $group,
  require => Group[$group],
  #uid     => 2000,
  home    => "/home/${username}",
  shell   => "/bin/bash",
  managehome  => true,
}


#####################################################################
# timezone
#####################################################################

class { 'timezone': 
  region => 'Europe',
  locality => 'Copenhagen', 
}


######################################################################
# PHP
######################################################################

class { 'php': }

php::module { "curl": }


######################################################################
# Apache
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

#file { '/tmp/hng':
#  ensure  => present,
#  source  => "file:///etc/puppet/manifests/files/httpd",
#  owner => 'root',
#  group => 'root', mode => '0644',
#  require => Package[$apache],
#  notify  => Service['apache2'],
#}

exec { 'userdir':
  notify  => Service['apache2'],
  command => '/usr/sbin/a2enmod userdir',
  require => Package[$apache],
}


######################################################################
# cronjob
######################################################################

cron { temperature_controller_cronjob:
  command => "/usr/bin/php /home/ulrik/temperature_controller/measure_and_regulate.php",
  user    => root,
  minute  => '*/1',
  require => Class['php'],
}

######################################################################
# website
######################################################################

file { "/home/${username}/www":
  path    => "/home/${username}/www",
  ensure  => directory,
  group   => $group,
  owner   => $username,
  mode    => 0755,
  require  => [ User["${username}"] ],
}

file { '/etc/apache2/sites-available/temperature_control':
  ensure  => file,
  group   => "root",
  owner   => "root",
  mode    => 0644,
  source  => "file:///etc/puppet/manifests/files/temperature_control_apache_conf",
  require => [ File["/home/${username}/www"] ],
}

vcsrepo { "/home/${username}/www/temperature_control":
  ensure => latest,
  provider => git,
  owner    => $username,
  group    => $group,
  source => 'https://github.com/ulrikhindoe/vagrant_test.git',
  require  => [ File["/home/${username}/www"], Package["git"] ],
}

file { '/etc/apache2/sites-enabled/000-default':
   ensure => 'link',
   target => '/etc/apache2/sites-available/temperature_control',
   require  => [ File['/etc/apache2/sites-available/temperature_control'] ],
}





################################################################
# ssh
################################################################

file { "/home/${username}/.ssh":
  ensure => directory,
  require => User["${username}"],
  group  => $group,
  owner => $username,
  mode  => '0700',	
}
 
file { "/home/${username}/.ssh/authorized_keys":
  ensure => present,
  source => 'file:///etc/puppet/manifests/files/authorized_keys',
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

###############################################################
# database
###############################################################

class { 'mysql::server':
  root_password => 'foo',
  databases => {
    'temperature_control' => {
      ensure  => 'present',
      charset => 'utf8',
    },
  },
  users => {
    'ulrik@localhost' => {
      ensure         => 'present',
      password_hash  => mysql_password('fuu')
    },
  },
  grants => {
    "${username}@localhost/temperature_control.*" => {
      ensure     => 'present',
      options    => ['GRANT'],
      privileges => ['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'CREATE'],
      table      => 'temperature_control.*',
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
  command => "mysql -u${username} -pfuu temperature_control < /home/${username}/sql/database_tables.sql",
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

#####################################################################
# samba
#####################################################################

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


