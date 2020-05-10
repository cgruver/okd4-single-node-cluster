# OKD 4 Single Node Cluster

## Host setup:

I am using a [NUC8i3BEK](https://ark.intel.com/content/www/us/en/ark/products/126149/intel-nuc-kit-nuc8i3bek.html) with 32GB of RAM for my host. This little box with 32GB of RAM is perfect for this purpose, and also very portable for throwing in a bag to take my dev environment with me.

You need to start with a minimal CentOS 7 install.

    wget https://buildlogs.centos.org/rolling/7/isos/x86_64/CentOS-7-x86_64-Minimal.iso

Use a tool like [balenaEtcher](https://www.balena.io/etcher/) to create a bootable USB key from a CentOS ISO.

You will have to attach monitor, mouse, and keyboard to your NUC for the install.  After the install, this machine can be headless.

* Network:
    * Configure the network interface with a fixed IP address, `10.11.11.10` if you are following this guide.  Otherwise, use the conventions of your local network.
    * Set the system hostname to `snc-host`
* Storage:
    * Take the default sizes for /boot and swap.
    * Do not create a `/home` filesystem (no users on this system)
    Allocate all of the remaining space for the `/` filesystem

After the installation completes, ensure that you can ssh to your host.

    ssh root@10.11.11.10

Install some packages and update:

    yum -y install wget git net-tools bind bind-utils bash-completion nfs-utils rsync qemu-kvm libvirt libvirt-python libguestfs-tools virt-install iscsi-initiator-utils
    yum -y update

Shutdown the host and disconnect the keyboard, mouse, and display.  Your host is now headless.  

### __Power the host up, log in via SSH, and continue the snc-host host set up.__

1. Clone this repository:

       mkdir -p /root/okd4-snc
       cd /root/okd4-snc
       git clone https://github.com/cgruver/okd4-single-node-cluster.git
       cd okd4-single-node-cluster

1. Copy the utility scripts to your local `bin` directory:

       mkdir ~/bin
       cp ./Provisioning/bin/* ~/bin
       chmod 750 ~/bin/*

    Ensure that `~/bin` is in your $PATH.  Modify ~/.bashrc if necessary.

1. One of the included utility scripts will set environment variables for the install.

    Modify `~/bin/setSncEnv.sh` to reflect your network settings.  You will need to set a domain that will be used in the DNS setup.

    | Variable | Example Value | Description |
    | --- | --- | --- |
    | `SNC_DOMAIN` | `snc.test` | The domain that you want for your lab.  This will be part of your DNS setup |
    | `SNC_HOST` | `10.11.11.10` | The IP address of your snc-host host. |
    | `SNC_NAMESERVER` | `${SNC_HOST}` | The IP address of your snc-host host. |
    | `SNC_NETMASK` | `255.255.255.0` | The netmask of your local network |
    | `SNC_GATEWAY` | `10.11.11.1` | The IP address of your local router |
    | `INSTALL_HOST_IP` | `${SNC_HOST}` | The IP address of your snc-host host. |
    | `INSTALL_ROOT` | `/usr/share/nginx/html/install` | The directory that will hold Fedora CoreOS install images |
    | `INSTALL_URL` | `http://${SNC_HOST}/install` | The URL for Fedora CoreOS installation |
    | `OKD4_SNC_PATH` | `/root/okd4-snc` | The path from which we will build our OKD4 cluster |
    | `OKD_REGISTRY` | `registry.svc.ci.openshift.org/origin/release` | The URL for the OKD4 nightly build images |
    | `LOCAL_SECRET_JSON` | `${OKD4_SNC_PATH}/pull-secret.json` | The path to the pull secret needed for accessing the OKD4 images |

    After you you have completed any necessary modifications, add this script to ~/.bashrc so that it will execute on login.

       echo ". /root/bin/setSncEnv.sh" >> ~/.bashrc

    Now, set the environment in your local shell:

       . /root/bin/setSncEnv.sh

1. Install packages and set up KVM:

       yum -y install wget git net-tools bind bind-utils bash-completion nfs-utils rsync qemu-kvm libvirt libvirt-python libguestfs-tools virt-install iscsi-initiator-utils
       yum -y update

       systemctl enable libvirtd
       systemctl start libvirtd

       mkdir /VirtualMachines
       virsh pool-destroy default
       virsh pool-undefine default
       virsh pool-define-as --name default --type dir --target /VirtualMachines
       virsh pool-autostart default
       virsh pool-start default

## DNS Configuration

OKD requires a DNS configuration.  To satisfy that requirement, we will set up bind.  

This tutorial includes pre-configured files for you to modify for your specific installation.  These files will go into your `/etc` directory.  You will need to modify them for your specific setup.

    /etc/named.conf
    /etc/named/named.conf.local
    /etc/named/zones/db.10.11.11
    /etc/named/zones/db.domain.records

__If you set up your router for the 10.11.11/24 network, then you can use the example DNS files as they are for this exercise.  Otherwise, you will need to modify the IP addresses to reflect your local network__

Do the following, from the root of this project:

    cp ./DNS/named.conf /etc
    cp ./DNS/named /etc
    
    mv /etc/named/zones/db.domain.records /etc/named/zones/db.${SNC_DOMAIN}
    sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/named.conf.local
    sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/zones/db.${SNC_DOMAIN}
    sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/zones/db.10.11.11

Now let's talk about this configuration, starting with the A records, (forward lookup zone).  If you did not use the 10.11.11/24 network as illustrated, then you will have to edit the files to reflect the appropriate A and PTR records for your setup.

In the example file, there are some entries to take note of:
  
1. The SNC Host is `snc-host`.
  
1. There is one wildcard record that OKD needs: __`okd4-snc` is the name of the cluster.__
  
        *.apps.okd4-snc.your.domain.org
   
     The "apps" record will be for all of the applications that you deploy into your OKD cluster.

     This wildcard A record needs to point to the entry point for your OKD cluster.  In this case, the wildcard A record will point to the IP address of your single master node.

1. There are two A records for the Kubernetes API, internal & external.  In this case, the same load balancer is handling both.  So, they both point to the IP address of the load balancer.  __Again, `okd4-snc` is the name of the cluster.__

       api.okd4-snc.your.domain.org.        IN      A      10.10.11.50
       api-int.okd4-snc.your.domain.org.    IN      A      10.10.11.50

1. There are three SRV records for the etcd hosts.

       _etcd-server-ssl._tcp.okd4-snc.your.domain.org    86400     IN    SRV     0    10    2380    etcd-0.okd4.your.domain.org.
       _etcd-server-ssl._tcp.okd4-snc.your.domain.org    86400     IN    SRV     0    10    2380    etcd-1.okd4.your.domain.org.
       _etcd-server-ssl._tcp.okd4-snc.your.domain.org    86400     IN    SRV     0    10    2380    etcd-2.okd4.your.domain.org.

When you have completed all of your configuration changes, you can test the configuration with the following command:

        named-checkconf

    If the output is clean, then you are ready to fire it up!

### Starting DNS

Now that we are done with the configuration let's enable DNS and start it up.

    firewall-cmd --permanent --add-service=dns
    firewall-cmd --reload
    systemctl enable named
    systemctl start named

You can now test DNS resolution.  Try some `ping` or `dig` commands.

### __Hugely Helpful Tip:__

__If you are using a MacBook for your workstation, you can enable DNS resolution to your lab by creating a file in the `/etc/resolver` directory on your Mac.__

    sudo bash
    <enter your password>
    vi /etc/resolver/your.domain.com

Name the file `your.domain.com` after the domain that you created for your SNC lab.  Enter something like this example, modified for your DNS server's IP:

    nameserver 10.11.11.10

Save the file.

Your MacBook should now query your new DNS server for entries in your new domain.  __Note:__ If your MacBook is on a different network and is routed to your Lab network, then the `acl` entry in your DNS configuration must allow your external network to query.  Otherwise, you will bang your head wondering why it does not work...







## Nginx Configuration

We are going to install the Nginx HTTP server and configure it to serve up the Fedora CoreOS installation images and the ignition config files.

Open firewall ports for HTTP/S so that we can access the Nginx server:

    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --reload

Install and start Nginx:

    yum -y install nginx
    systemctl enable nginx
    systemctl start nginx

### Host installation, FCOS & CentOS

Now, we are going to set up the artifacts for host installation.  This will include FCOS via `ignition`, and CentOS via `kickstart`.

    mkdir -p /usr/share/nginx/html/install/fcos/ignition

### FCOS:

1. In a browser, go to: `https://getfedora.org/en/coreos/download/`
1. Make sure you are on the `stable` Stream, select the `Bare Metal & Virtualized` tab, and make note of the current version. 

    ![FCOS Download Page](images/FCOS-Download.png)

1. Set the FCOS version as a variable.  For example:

       FCOS_VER=31.20200223.3.0

1. Set the FCOS_STREAM variable to `stable` or `testing` to match the stream that you are pulling from.

    FCOS_STREAM=stable

