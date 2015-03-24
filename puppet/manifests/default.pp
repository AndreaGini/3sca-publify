Package {
   allow_virtual => true,
}
#Node hosting the Mysql Server
node 'db01.local' {
    $override_options = {
      'mysqld' => {
        'server-id' => '1',
        'bind-address' => '0.0.0.0',
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

    class { '::mysql::server':
 	  root_password           => 'testdb',
      	override_options => $override_options
    }
      mysql_user { 'root@%':
        ensure                   => 'present',
        password_hash            => '*9EC001FF562CDE467D041CEAB13160F3BBB49DD2',
      }
      mysql_grant { 'root@%/*.*':
        ensure     => 'present',
        options    => ['GRANT'],
        privileges => ['ALL'],
        table      => '*.*',
        user       => 'root@%',
      }  

    package { 'git': ensure => installed }
    service { "firewalld.service": ensure => "stopped", }
}
#Node hosting the Publify Server
node 'pb01.local' {
    service { "firewalld.service": ensure => "stopped", }
    exec { "update-gem":
    command => "/bin/gem update --system", }
    $rubypre = [ 'git','ruby-devel','gcc','gcc-c++','make','automake','autoconf','curl-devel','openssl-devel','zlib-devel','httpd-devel','apr-devel','apr-util-devel','sqlite-devel', 'mysql-devel' ]
    package { [$rubypre]: 
    ensure => installed, }
    package { [ 'rake', 'rails', 'eventmachine', 'mysql2', 'nokogiri' ]:
    ensure   => 'installed',
    provider => 'gem', 
    require  => [ Package [$rubypre], Exec ["update-gem"] ] }
    exec { "clone-publify":
    command => "/usr/bin/git clone https://github.com/publify/publify.git /opt/publify",
    require  => Package ['git'] }
    file { '/opt/publify/config/database.yml':
    source => 'puppet:///files/database.yml.pb01',
    require => Exec [ "clone-publify" ], }
    exec { "bunle-install":
    cwd => "/opt/publify/" ,
    command => "/usr/local/bin/bundle install" ,
    onlyif => "/usr/bin/test -f /opt/publify/config/database.yml", 
    require => Package ['rake', 'rails', 'eventmachine', 'mysql2', 'nokogiri'] }
    exec { "db-setup":
    command => "/usr/local/bin/rake db:setup -f /opt/publify/Rakefile",
    require =>  Exec [ "bunle-install" ], }
    exec { "db-migrate":
    command => "/usr/local/bin/rake db:migrate -f /opt/publify/Rakefile" ,
    require => Exec [ "db-setup" ], }
    exec { "db-seed":
    command => "/usr/local/bin/rake db:seed -f /opt/publify/Rakefile",
    require => Exec [ "db-migrate" ], }
    exec { "assets-precompile":
    command => "/usr/local/bin/rake assets:precompile -f /opt/publify/Rakefile",
    require => Exec [ "db-seed" ], }
    exec { "start-rails":
    cwd => "/opt/publify/" ,
    command => "/bin/nohup /usr/local/bin/rails server -b 0.0.0.0 -d",
    require => Exec [ "assets-precompile" ], }
}
#Node hosting the HAProxy Server
node 'ha01.local' {
    service { "firewalld.service": ensure => "stopped", }
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
            'http-request 2s',
            'queue 1s',
            'connect 1s',
            'client 3s',
            'server 2s',
            'check 1s',
            ],
            'maxconn' => '8000',
        },
    }
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
    haproxy::balancermember { 'pb01':
      listening_service => 'publify',
      server_names      => 'pb01.local',
      ipaddresses       => '192.168.100.20',
      ports             => '3000',
    }
}
