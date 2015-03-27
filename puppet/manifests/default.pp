#Vargrant specific configuration (usually in pupprt server site.pp)
Package {
   allow_virtual => true,
}
###############################
#Node hosting the Mysql Server#
###############################
node 'db01.local' {

#Override options for Mysql
    $override_options = {
      'mysqld' => {
      'server-id'                 => '1',
      'bind-address'              => '0.0.0.0',
      'innodb_buffer_pool_size'   => '500M',
      'innodb_lock_wait_timeout'  => '5',
      'innodb_thread_concurrency' => '0',
      'innodb_flush_method'       => 'O_DIRECT',
      'log-bin'                   => '/var/lib/mysql',
      'log-bin-index'             => '/var/lib/mysql/log-bin.index',
      'relay-log'                 => '/var/lib/mysql/relay.log',
      'relay-log-info-file'       => '/var/lib/mysql/relay-log.info',
      'relay-log-index'           => '/var/lib/mysql/relay-log.index',
      }
    }

# Install Mysql and set root password
    class { '::mysql::server':
 	  root_password    => 'testdb',
      override_options => $override_options
    }

#Create mysql user to access from network 
      mysql_user { 'root@%':
        ensure        => 'present',
        password_hash => '*9EC001FF562CDE467D041CEAB13160F3BBB49DD2',
      }
      mysql_grant { 'root@%/*.*':
        ensure        => 'present',
        options       => ['GRANT'],
        privileges    => ['ALL'],
        table         => '*.*',
        user          => 'root@%',
      } 

#Stop firewall services
    service { 'firewalld.service': ensure => 'stopped', }
}
#################################
#Node hosting the Publify Server#
#################################
node 'pb01.local' {
#Stop firewall services
    service { 'firewalld.service': ensure => 'stopped', }

#Ruby pre requirement packages
    $rubypre = [ 'git',
                 'gcc',
                 'gcc-c++',
                 'make',
                 'automake',
                 'autoconf',
                 'curl-devel',
                 'openssl-devel',
                 'zlib-devel',
                 'httpd-devel',
                 'apr-devel',
                 'apr-util-devel',
                 'sqlite-devel',
                 'mysql-devel' ]
    package { [$rubypre]: 
    ensure            => installed, }

#Ruby packages
    class { 'ruby':
    gems_version      => 'latest',
    require           => Package [$rubypre]
    }
    class { 'ruby::dev':
    bundler_provider  => 'gem'
    }

    package { [ 'rails', 'eventmachine', 'mysql2', 'nokogiri' ]:
    ensure            => 'installed',
    provider          => 'gem', 
    require           => Class ['ruby::dev']
    }

#Set up parent folder for publify to ensure no errors on deploy
    file { [ '/var/www' ]:
    ensure            => 'directory',
    before            => Exec [ 'clone-publify' ],
    }

#Clone of Publify repo for installation
    exec { 'clone-publify':
    command           => '/usr/bin/git clone https://github.com/publify/publify.git /var/www/publify',
    require           => Package ['git'], 
    }

#Copy the database configuration file from puppet files repo
    file { '/var/www/publify/config/database.yml':
    source  => 'puppet:///files/database.yml.pb01',
    require  => Exec [ 'clone-publify' ] 
    }

#Install Ruby bundle
    ruby::bundle { bundle:
    cwd               => '/var/www/publify' ,
    timeout           => 600,
    require           => [ Exec [ 'clone-publify' ], File ['/var/www/publify/config/database.yml'] ]
    }

#Setting up and seeding Database 
    ruby::rake { 
        'db-setup':
        task          => 'db:setup',
        cwd           => '/var/www/publify',
        rails_env     => 'development',
        require       => Class ['ruby'];
        'db-migrate':
        task          => 'db:migrate',
        cwd           => '/var/www/publify',
        rails_env     => 'development',
        require       => Ruby::Rake['db-setup'];
        'db-seed':
        task          => 'db:seed',
        cwd           => '/var/www/publify',
        rails_env     => 'development',
        require       => Ruby::Rake['db-migrate'];
        'assets-precompile':
        task          => 'assets:precompile',
        rails_env     => 'development',
        cwd           => '/var/www/publify',
        require       => Ruby::Rake['db-seed'];
    }

#Copy the service configuration file from puppet files repo
    file { '/etc/systemd/system/publify.service':
    source  => 'puppet:///files/publify.service.pb01',
    require => Ruby::Rake['assets-precompile'],
    }
    service { 'publify.service': 
    ensure  => 'running',
    require => File ['/etc/systemd/system/publify.service'] 
    }
    
}
#################################
#Node hosting the HAProxy Server#
#################################
node 'ha01.local' {

#Stop firewall services
    service { 'firewalld.service': ensure => 'stopped', }

#Install and configure HAProxy
    class { 'haproxy':
        global_options => {
            'chroot'  => '/var/lib/haproxy',
            'group'   => 'haproxy',
            'user'    => 'haproxy',
            'daemon'  => '', 
            'maxconn' => '4000',
            'pidfile' => '/var/run/haproxy.pid',
            'stats'   => 'socket /var/lib/haproxy/stats',
            'log'     => '127.0.0.1 local0 notice',
        },
        defaults_options => {
            'log'     => 'global',
            'stats'   => 'enable',
            'option'  => [
            'redispatch',
            'forwardfor except 127.0.0.1',
            ],
            'retries' => '3',
            'timeout' => [
            'http-request 20s',
            'queue 10s',
            'connect 10s',
            'client 30s',
            'server 20s',
            'check 10s',
            ],
            'maxconn' => '8000',
        },
    }
    #Cofigure listen for Statistics
    haproxy::listen { 'stats':
      mode             => 'http',
        ipaddress        => '0.0.0.0',
        ports            => '80',
        options => {
            'stats uri' => '/',
            'stats refresh' => '5s',
            'timeout' => [
            'http-request 10s',
            'client 10s',
            ],
        }
    }
    #Configure listen for Publify service
    haproxy::listen { 'publify':
      mode             => 'http',
        collect_exported => false,
        ipaddress        => '*',
        ports            => '3000',
        options   => {
            'balance' => 'roundrobin',
            'option'  => [
            'forwardfor',
            ],
        },
    }
    #Configure BalanceMember (add backend nodes here)
    haproxy::balancermember { 'pb01':
      listening_service => 'publify',
      server_names      => 'pb01.local',
      ipaddresses       => '192.168.100.20',
      ports             => '3000',
    }
}
