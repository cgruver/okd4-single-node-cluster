# OKD 4 Single Node Cluster

    yum -y install wget git net-tools bind-utils bash-completion nfs-utils rsync qemu-kvm libvirt libvirt-python libguestfs-tools virt-install iscsi-initiator-utils
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

This tutorial includes pre-configured files for you to modify for your specific installation.  These files will go into your `/etc` directory.  You will need to modify them for your specific setup.

    /etc/named.conf
    /etc/named/named.conf.local
    /etc/named/zones/db.10.11.11
    /etc/named/zones/db.your.domain.org

__If you set up your lab router on the 10.11.11/24 network.  Then you can use the example DNS files as they are for this exercise.__

Do the following, from the root of this project:

    cp ./DNS/named.conf /etc
    cp ./DNS/named /etc
    
    mv /etc/named/zones/db.your.domain.org /etc/named/zones/db.${LAB_DOMAIN} # Don't substitute your.domain.org in this line
    sed -i "s|%%LAB_DOMAIN%%|${LAB_DOMAIN}|g" /etc/named/named.conf.local
    sed -i "s|%%LAB_DOMAIN%%|${LAB_DOMAIN}|g" /etc/named/zones/db.${LAB_DOMAIN}
    sed -i "s|%%LAB_DOMAIN%%|${LAB_DOMAIN}|g" /etc/named/zones/db.10.11.11

Now let's talk about this configuration, starting with the A records, (forward lookup zone).  If you did not use the 10.11.11/24 network as illustrated, then you will have to edit the files to reflect the appropriate A and PTR records for your setup.

In the example file, there are some entries to take note of:
  
1. The Bastion Host is `bastion`.
  
1. There is one wildcard record that OKD needs: __`okd4` is the name of the cluster.__
  
        *.apps.okd4.your.domain.org
   
     The "apps" record will be for all of the applications that you deploy into your OKD cluster.

     This wildcard A record needs to point to the entry point for your OKD cluster.  If you build a cluster with three master nodes like we are doing here, you will need a load balancer in front of the cluster.  In this case, your wildcard A records will point to the IP address of your load balancer.  Never fear, I will show you how to deploy an HA-Proxy load balancer.  

1. There are two A records for the Kubernetes API, internal & external.  In this case, the same load balancer is handling both.  So, they both point to the IP address of the load balancer.  __Again, `okd4` is the name of the cluster.__

       api.okd4.your.domain.org.        IN      A      10.10.11.50
       api-int.okd4.your.domain.org.    IN      A      10.10.11.50

1. There are three SRV records for the etcd hosts.

       _etcd-server-ssl._tcp.okd4.your.domain.org    86400     IN    SRV     0    10    2380    etcd-0.okd4.your.domain.org.
       _etcd-server-ssl._tcp.okd4.your.domain.org    86400     IN    SRV     0    10    2380    etcd-1.okd4.your.domain.org.
       _etcd-server-ssl._tcp.okd4.your.domain.org    86400     IN    SRV     0    10    2380    etcd-2.okd4.your.domain.org.

When you have completed all of your configuration changes, you can test the configuration with the following command:

        named-checkconf

    If the output is clean, then you are ready to fire it up!

### Starting DNS

Now that we are done with the configuration let's enable DNS and start it up.

    firewall-cmd --permanent --add-service=dns
    firewall-cmd --reload
    systemctl enable named
    systemctl start named

You can now test DNS resolution.  Try some `pings` or `dig` commands.

### __Hugely Helpful Tip:__

__If you are using a MacBook for your workstation, you can enable DNS resolution to your lab by creating a file in the `/etc/resolver` directory on your Mac.__

    sudo bash
    <enter your password>
    vi /etc/resolver/your.domain.com

Name the file `your.domain.com` after the domain that you created for your lab.  Enter something like this example, modified for your DNS server's IP:

    nameserver 10.11.11.10

Save the file.

Your MacBook should now query your new DNS server for entries in your new domain.  __Note:__ If your MacBook is on a different network and is routed to your Lab network, then the `acl` entry in your DNS configuration must allow your external network to query.  Otherwise, you will bang your head wondering why it does not work...  __The ACL is very powerful.  Use it.  Just like you are using firewalld.  Right?  I know you did not disable it when you installed your host...__


## Nginx Config & RPM Repository Synch
We are going to install the Nginx HTTP server and configure it to serve up all of the RPM packages that we need to build our guest VMs.

We need to open firewall ports for HTTP/S so that we can access our Nginx server:

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
