## Building an OpenShift - OKD 4.X Single Node Cluster

### Work In Progress.  Documentation is incomplete.

## Setting up the Centos 7.6 host

This host will have the following services deployed:

* Nginx for hosting RPMs and iPXE install files.
* A DNS server for the lab ecosystem.
* Sonatype Nexus for the OKD registry mirror, Maven Artifacts, and Container Images.
* DHCP for iPXE boot

This host will also run the load-balancer VM, Bootstrap VM, and your Single Node Cluster.  I am using a [NUC8i3BEK](https://ark.intel.com/content/www/us/en/ark/products/126149/intel-nuc-kit-nuc8i3bek.html) with 32GB of RAM for my host. This little box with 32GB of RAM is perfect for this purpose, and also very portable for throwing in a bag to take my dev environment with me.

You need to start with a minimal CentOS 7 install. (__This tutorial assumes that you are comfortable installing a Linux OS.__)

    wget https://buildlogs.centos.org/rolling/7/isos/x86_64/CentOS-7-x86_64-Minimal.iso

I use [balenaEtcher](https://www.balena.io/etcher/) to create a bootable USB key from a CentOS ISO.

You will have to attach monitor, mouse, and keyboard to your NUC for the install.  After the install, this machine will be headless.

### Install CentOS:

* Network:
    * Configure the network interface with a fixed IP address, `10.11.11.10` if you are following this guide exactly.
    * Set the system hostname to `lab-controller`
* Storage:
    * Take the default sizes for /boot and swap.
    * Do not create a `/home` filesystem (no users on this system)
    Allocate all of the remaining space for the `/` filesystem

After the installation completes, ensure that you can ssh to your host.

    ssh root@10.11.11.10

Create an SSH key pair on your workstation, if you don't already have one:

    ssh-keygen  # Take all the defaults

Enable password-less SSH:

    ssh-copy-id root@10.11.11.10

Shutdown the host and disconnect the keyboard, mouse, and display.  Your host is now headless.  

### __Power the host back on, log in via SSH, and continue the lab-controller host set up.__

Install some added packages:

1. We're going to use the kvm-common repository to ensure we get a new enough version of KVM.

       cat << EOF > /etc/yum.repos.d/kvm-common.repo
       [kvm-common]
       name=KVM Common
       baseurl=http://mirror.centos.org/centos/7/virt/x86_64/kvm-common/
       gpgcheck=0
       enabled=1
       EOF

1. Now install the packages that we are going to need.

       yum -y install wget git net-tools bind bind-utils bash-completion nfs-utils rsync ipmitool python3-pip yum-utils qemu-kvm libvirt libvirt-python libguestfs-tools virt-install iscsi-initiator-utils createrepo docker libassuan-devel java-1.8.0-openjdk.x86_64 epel-release ipxe-bootimgs python36-devel libvirt-devel httpd-tools

1. Install Virtual BMC:

       pip3.6 install virtualbmc

    Set up VBMC as a systemd controlled service:

       cat > /etc/systemd/system/vbmcd.service <<EOF
       [Install]
       WantedBy = multi-user.target
       [Service]
       BlockIOAccounting = True
       CPUAccounting = True
       ExecReload = /bin/kill -1 $MAINPID
       ExecStop = /bin/kill -15 $MAINPID
       ExecStart = /usr/local/bin/vbmcd --foreground
       Group = root
       Restart = on-failure
       RestartSec = 2
       Slice = vbmc.slice
       TimeoutSec = 120
       Type = simple
       User = root
       [Unit]
       After = libvirtd.service
       After = syslog.target
       After = network.target
       Description = vbmc service
       EOF

    Enable the vbmcd service:

       systemctl enable vbmcd.service
       systemctl start vbmcd.service

Next, we need to set up some environment variables that we will use to set up the rest of the lab.  You need to make some decisions at this point, fill in the following information, and then set temporary variables for each:

| Variable | Example Value | Description |
| --- | --- | --- |
| `LAB_DOMAIN` | `your.domain.org` | The domain that you want for your lab.  This will be part of your DNS setup |
| `LAB_NAMESERVER` | `10.11.11.10` | The IP address of your lab-controller host. |
| `LAB_NETMASK` | `255.255.255.0` | The netmask of your router |
| `LAB_GATEWAY` | `10.11.11.1` | The IP address of your router |
| `INSTALL_HOST_IP` | `10.11.11.10` | The IP address of your lab-controller host. |
| `INSTALL_ROOT` | `/usr/share/nginx/html/install` | The directory that will hold CentOS install images |
| `REPO_HOST` | `lab-controller` | The lab-controller hostname |
| `REPO_PATH` | `/usr/share/nginx/html/repos` | The directory that will hold an RPM repository mirror |
| `OKD4_LAB_PATH` | `~/okd4-lab` | The path from which we will build our OKD4 cluster |
| `OKD_REGISTRY` | `registry.svc.ci.openshift.org/origin/release` | This is where we will get our OKD 4 images from to populate our local mirror |
| `LOCAL_REGISTRY` | `nexus.${LAB_DOMAIN}:5001` | The URL that we will use for our local mirror of the OKD registry images | 
| `LOCAL_REPOSITORY` | `origin` | The repository where the local OKD image mirror will be pushed |
| `LOCAL_SECRET_JSON` | `${OKD4_LAB_PATH}/pull-secret.json` | The path to the pull secret that we will need for mirroring OKD images |

When you have selected values for the variables.  Set them in the shell like this: 

    LAB_DOMAIN=your.domain.org
    LAB_NAMESERVER=10.11.11.10
    LAB_NETMASK=255.255.255.0
    LAB_GATEWAY=10.11.11.1
    INSTALL_HOST_IP=10.11.11.1
    INSTALL_ROOT=/usr/share/nginx/html/install
    REPO_HOST=ocp-controller01
    REPO_PATH=/usr/share/nginx/html/repos
    OKD4_LAB_PATH=~/okd4-lab
    LOCAL_REGISTRY=nexus.${LAB_DOMAIN}:5001
    LOCAL_REPOSITORY=origin

Now, let's create a utility script that will persist these values for us:

    mkdir -p ~/bin/lab_bin

    cat <<EOF > ~/bin/lab_bin/setLabEnv.sh
    #!/bin/bash

    export PATH=${PATH}:~/bin/lab_bin
    export LAB_DOMAIN=${LAB_DOMAIN}
    export LAB_NAMESERVER=${LAB_NAMESERVER}
    export LAB_NETMASK=${LAB_NETMASK}
    export LAB_GATEWAY=${LAB_GATEWAY}
    export REPO_HOST=${REPO_HOST}
    export INSTALL_HOST_IP=${INSTALL_HOST_IP}
    export INSTALL_ROOT=${INSTALL_ROOT}
    export REPO_URL=http://${REPO_HOST}.${LAB_DOMAIN}
    export INSTALL_URL=http://${INSTALL_HOST_IP}/install
    export REPO_PATH=${REPO_PATH}
    export OKD4_LAB_PATH=${OKD4_LAB_PATH}
    export OKD_REGISTRY=registry.svc.ci.openshift.org/origin/release
    export LOCAL_REGISTRY=${LOCAL_REGISTRY}
    export LOCAL_REPOSITORY=${LOCAL_REPOSITORY}
    export LOCAL_SECRET_JSON=${OKD4_LAB_PATH}/pull-secret.json
    EOF

Configure bash to execute this script on login:

    chmod 750 ~/bin/lab_bin/setLabEnv.sh
    echo ". /root/bin/lab_bin/setLabEnv.sh" >> ~/.bashrc

Clone this project:

    git clone https://github.com/cgruver/okd4-upi-lab-setup
    cd okd4-upi-lab-setup

Copy the utility scripts that I have prepared for you:

    cp ./Provisioning/bin/*.sh ~/bin/lab_bin
    chmod 700 ~/bin/lab_bin/*.sh

Enable this host to be a time server for the rest of your lab: (adjust the network value if you are using a different IP range)

    echo "allow 10.11.11.0/24" >> /etc/chrony.conf

Finally, create an SSH key pair: (Take the defaults for all of the prompts, don't set a key password)

    ssh-keygen
    <Enter>
    <Enter>
    <Enter>

Now is a good time to update and reboot the lab-controller host:

    yum -y update
    shutdown -r now

Log back in and you should see all of the environment variables that we just set in the output of an `env` command.

__For the rest of this setup, unless otherwise specified, it is assumed that you are working from the lab-controller Host.  You will need the environment variables that we just set up for some of the commands that you will be executing.__

Now we are ready to set up our router: [Router Setup](GL-AR750S-Ext.md)
