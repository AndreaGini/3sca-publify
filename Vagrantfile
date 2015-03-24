# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|

  config.vm.provision "puppet",
  :options => ["--fileserverconfig=/vagrant/fileserver.conf"] do |puppet|
    puppet.manifests_path = "puppet/manifests"
    puppet.manifest_file = "default.pp"
    puppet.module_path = "puppet/modules"
    puppet.hiera_config_path = "puppet/hiera.yaml"
    puppet.working_directory = "/home/vagrant"
  end

  config.vm.define "db01" do |db01|
    db01.vm.box = "puppetlabs/centos-7.0-64-puppet"
    db01.vm.hostname = "db01.local"
    db01.vm.network "private_network", ip: "192.168.100.10", virtualbox__intnet: true
    db01.vm.provider "virtualbox" do |vb|
      vb.gui = false
      vb.memory = "2048"
      vb.cpus = "1"
      vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-VMs"]
  end
end
  config.vm.define "pb01" do |pb01|
    pb01.vm.box = "puppetlabs/centos-7.0-64-puppet"
    pb01.vm.hostname = "pb01.local"
    pb01.vm.network "private_network", ip: "192.168.100.20", virtualbox__intnet: true
    pb01.vm.provider "virtualbox" do |vb|
      vb.gui = false
      vb.memory = "2048"
      vb.cpus = "1"
      vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-VMs"]
  end
end
  config.vm.define "ha01" do |ha01|
    ha01.vm.box = "puppetlabs/centos-7.0-64-puppet"
    ha01.vm.network "forwarded_port", guest: 3000, host: 3000
    ha01.vm.network "forwarded_port", guest: 80, host: 8080
    ha01.vm.hostname = "ha01.local"
    ha01.vm.network "private_network", ip: "192.168.100.30", virtualbox__intnet: true
    ha01.vm.provider "virtualbox" do |vb|
      vb.gui = false
      vb.memory = "2048"
      vb.cpus = "1"
      vb.customize ["modifyvm", :id, "--nicpromisc2", "allow-VMs"]
  end
end    


end
