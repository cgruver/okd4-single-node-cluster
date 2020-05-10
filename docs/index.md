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

Install packages and set up KVM:

    yum -y install wget git net-tools bind bind-utils bash-completion nfs-utils rsync qemu-kvm libvirt libvirt-python libguestfs-tools virt-install iscsi-initiator-utils

    systemctl enable libvirtd
    systemctl start libvirtd

    mkdir /VirtualMachines
    virsh pool-destroy default
    virsh pool-undefine default
    virsh pool-define-as --name default --type dir --target /VirtualMachines
    virsh pool-autostart default
    virsh pool-start default

Create an SSH key pair: (Take the defaults for all of the prompts, don't set a key password)

    ssh-keygen
    <Enter>
    <Enter>
    <Enter>

Update and shutdown the SNC host:

    yum -y update
    shutdown -h now

Disconnect the keyboard, mouse, and display.  Your host is now headless.  

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
1. The Bootstrap node is `okd4-snc-bootstrap`.
1. The Master node for the single node cluster is `okd4-snc-master`.
1. The etcd host is also the master node `etcd-0`
1. There is one wildcard record that OKD needs: __`okd4-snc` is the name of the cluster.__
  
        *.apps.okd4-snc.your.domain.org
   
     The "apps" record will be for all of the applications that you deploy into your OKD cluster.

     This wildcard A record needs to point to the entry point for your OKD cluster.  In this case, the wildcard A record will point to the IP address of your single master node.
1. There are two A records for the Kubernetes API, internal & external.  

       api.okd4-snc.your.domain.org.        IN      A      10.10.11.50
       api-int.okd4-snc.your.domain.org.    IN      A      10.10.11.50

1. There is one SRV record for the etcd host, which is also the master node.

       _etcd-server-ssl._tcp.okd4-snc.your.domain.org    86400     IN    SRV     0    10    2380    etcd-0.okd4.your.domain.org.

1. We are going to take advantage of DNS round-robin for this installation, since we are not using an external load balancer.  Thus, there are duplicate entries for the `api` and `api-int` A records.  The duplicate entries point to the bootstrap node.  These entries will be removed when the cluster bootstrap is completed.

       api.okd4-snc.your.domain.org.        IN      A      10.10.11.49 ; remove after bootstrap
       api-int.okd4-snc.your.domain.org.    IN      A      10.10.11.49 ; remove after bootstrap

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

Create the directory structure for the Fedora CoreOS install files.

    mkdir -p /usr/share/nginx/html/install/fcos/ignition

## Prepare to Install the OKD 4.4 Single Node Cluster

I have provided a set of utility scripts to automate a lot of the tasks associated with deploying and tearing down an your OKD cluster.  In your `~/bin` directory you will see the following:

| | |
|-|-|
| `DeployOkdSnc.sh` | Creates the Bootstrap and Master nodes, and starts the installation |
| `DestroyBootstrap.sh` | Destroys the Bootstrap node |
| `sncPostInstall.sh` | Post cluster install script to set up the cluster for use |
| `UnDeployOkdSnc.sh` | Destroys the single node cluster |

1. Retrieve the `oc` command.  We're going to grab an older version of `oc`, but that's OK.  We just need it to retrieve to current versions of `oc` and `openshift-install`

    Go to: `https://github.com/openshift/okd/releases/tag/4.4.0-0.okd-2020-01-28-022517` and retrieve the `openshift-client-linux-4.4.0-0.okd-2020-01-28-022517.tar.gz` archive.

       wget https://github.com/openshift/okd/releases/download/4.4.0-0.okd-2020-01-28-022517/openshift-client-linux-4.4.0-0.okd-2020-01-28-022517.tar.gz

1. Uncompress the archive and move the `oc` executable to your ~/bin directory.

       tar -xzf openshift-client-linux-4.4.0-0.okd-2020-01-28-022517.tar.gz
       mv oc ~/bin

    The `DeployOkdSnc.sh` script will pull the correct version of `oc` and `openshift-install` when we run it.  It will over-write older versions in `~/bin`.

1. Now, we need a pull secret.  

   The first one is for quay.io.  If you don't already have an account, go to `https://quay.io/` and create a free account.

   Once you have your account, you need to extract your pull secret.

   1. Log into your new Quay.io account.
   1. In the top left corner, click the down arrow next to your user name.  This will expand a menu
   1. Select `Account Settings`
   1. Under `Docker CLI Password`, click on `Generate Encrypted Password`
   1. Type in your quay.io password
   1. Select `Kubernetes Secret`
   1. Select `View <your-userid>-secret.yml`
   1. Copy the base64 encoded string under `.dockerconfigjson`

        It will look something like:

           ewoblahblahblahblahblahblahblahREDACTEDetc...IH0KfQ==

        But much longer...
    1. We need to put the pull secret into a JSON file that we will use to set up the install-config.yaml file.

           echo "PASTE THE COPIED BASE64 STRING HERE" | base64 -d > ${OKD4_LAB_PATH}/pull_secret.json 

1. We need to configure the environment to pull a current version of OKD.  So point your browser at `https://origin-release.svc.ci.openshift.org`.  

    ![OKD Release](images/OKD-Release.png)

    Select the most recent 4.4.0-0.okd release that is in a Phase of `Accepted`, and copy the release name into an environment variable:

       export OKD_RELEASE=4.4.0-0.okd-2020-03-23-073327

1. The next step is to prepare the install-config.yaml file that `openshift-install` will use it to create the `ignition` files for bootstrap and master nodes.

    I have prepared a skeleton file for you in this project, `./install-config-snc.yaml`.

       apiVersion: v1
       baseDomain: %%LAB_DOMAIN%%
       metadata:
         name: okd4-snc
       networking:
         networkType: OpenShiftSDN
         clusterNetwork:
         - cidr: 10.100.0.0/14 
           hostPrefix: 23 
         serviceNetwork: 
         - 172.30.0.0/16
       compute:
       - name: worker
         replicas: 0
       controlPlane:
         name: master
         replicas: 1
       platform:
         none: {}
       pullSecret: '%%PULL_SECRET%%'
       sshKey: %%SSH_KEY%%

    Copy this file to our working directory.

        cp ./Provisioning/install-config-upi.yaml ${OKD4_LAB_PATH}/install-config-snc.yaml

    Patch in some values:

        sed -i "s|%%LAB_DOMAIN%%|${LAB_DOMAIN}|g" ${OKD4_LAB_PATH}/install-config-snc.yaml
        SECRET=$(cat ${OKD4_LAB_PATH}/pull-secret.json)
        sed -i "s|%%PULL_SECRET%%|${SECRET}|g" ${OKD4_LAB_PATH}/install-config-snc.yaml
        SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
        sed -i "s|%%SSH_KEY%%|${SSH_KEY}|g" ${OKD4_LAB_PATH}/install-config-upi.yaml

    Your install-config-upi.yaml file should now look something like:

       apiVersion: v1
       baseDomain: your.domain.org
       metadata:
         name: okd4-snc
       networking:
         networkType: OpenShiftSDN
         clusterNetwork:
         - cidr: 10.100.0.0/14 
           hostPrefix: 23 
         serviceNetwork: 
         - 172.30.0.0/16
       compute:
       - name: worker
         replicas: 0
       controlPlane:
         name: master
         replicas: 1
       platform:
         none: {}
       pullSecret: '{"auths": {"quay.io": {"auth": "Y2dydREDACTEDREDACTEDHeGtREDACTEDREDACTEDU55NWV5MREDACTEDREDACTEDM4bmZB", "email": ""},"nexus.oscluster.clgcom.org:5002": {"auth": "YREDACTEDREDACTED==", "email": ""}}}'
       sshKey: ssh-rsa AAAREDACTEDREDACTEDAQAREDACTEDREDACTEDMnvPFqpEoOvZi+YK3L6MIGzVXbgo8SZREDACTEDREDACTEDbNZhieREDACTEDREDACTEDYI/upDR8TUREDACTEDREDACTEDoG1oJ+cRf6Z6gd+LZNE+jscnK/xnAyHfCBdhoyREDACTEDREDACTED9HmLRkbBkv5/2FPpc+bZ2xl9+I1BDr2uREDACTEDREDACTEDG7Ms0vJqrUhwb+o911tOJB3OWkREDACTEDREDACTEDU+1lNcFE44RREDACTEDREDACTEDov8tWSzn root@snc-host

1. Set a couple of environment variables that the `DeployOkdSnc` script will use for Fedora CoreOS installation. 

    In a browser, go to: `https://getfedora.org/en/coreos/download/`
    
    Make sure you are on the `stable` Stream, select the `Bare Metal & Virtualized` tab, and make note of the current version. 

    ![FCOS Download Page](images/FCOS-Download.png)

    Set the FCOS version as a variable.  For example:

       FCOS_VER=31.20200223.3.0

    Set the FCOS_STREAM variable to `stable` or `testing` to match the stream that you are pulling from.

       FCOS_STREAM=stable

1. Create the cluster virtual machines and start the OKD installation:

       DeployOkdNodes.sh -i=${OKD4_LAB_PATH}/guest-inventory/okd4 -p -m -d1

    This script does a whole lot of work for you.

    1. It will pull the current versions of `oc` and `openshift-install` based on the value of `${OKD_RELEASE}` that we set previously.
    1. fills in the OKD version in the install-config-upi.yaml file and copies that file to the install directory as install-config.yaml.
    1. Invokes the openshift-install command against our install-config to produce ignition files
    1. Copies the ignition files into place for FCOS install
    1. Sets up for a mirrored install by putting `registry.svc.ci.openshift.org` into a DNS sinkhole.
    1. Creates guest VMs for the Boostrap and Master nodes

### Now let's sit back and watch the install:

To watch a node boot and install:

* Bootstrap node:
  
       virsh console okd4-snc-bootstrap

* Master Node:

       virsh console okd4-snc-master

Once a host has installed FCOS you can monitor the install logs:
* Bootstrap Node:

       ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@okd4-bootstrap "journalctl -b -f -u bootkube.service"

* Master Node:

       ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@okd4-master-0 "journalctl -b -f -u kubelet.service"

Monitor OKD install progress:

  * Bootstrap Progress:

        openshift-install --dir=${OKD4_LAB_PATH}/okd4-install-dir wait-for bootstrap-complete --log-level debug

  * When bootstrap is complete, remove the bootstrap node from HA-Proxy

        ssh root@okd4-lb01 "cat /etc/haproxy/haproxy.cfg | grep -v bootstrap > /etc/haproxy/haproxy.tmp && mv /etc/haproxy/haproxy.tmp /etc/haproxy/haproxy.cfg && systemctl restart haproxy.service"

    Destroy the Bootstrap Node on the Bastion host:

        virsh destroy okd4-bootstrap
        vbmc delete okd4-bootstrap

  * Install Progress:

        openshift-install --dir=${OKD4_LAB_PATH}/okd4-install-dir wait-for install-complete --log-level debug

* Install Complete:

    You will see output that looks like:

      INFO Waiting up to 10m0s for the openshift-console route to be created... 
      DEBUG Route found in openshift-console namespace: console 
      DEBUG Route found in openshift-console namespace: downloads 
      DEBUG OpenShift console route is created           
      INFO Install complete!                            
      INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/root/okd4-lab/okd4-install-dir/auth/kubeconfig' 
      INFO Access the OpenShift web-console here: https://console-openshift-console.apps.okd4.your.domain.org 
      INFO Login to the console with user: kubeadmin, password: aBCdE-FGHiJ-klMNO-PqrSt

### Log into your new cluster console:

Point your browser to the url listed at the completion of install: `https://console-openshift-console.apps.okd4.your.domain.org`
Log in as `kubeadmin` with the password from the output at the completion of the install.

__If you forget the password for this initial account, you can find it in the file: `${OKD4_LAB_PATH}/okd4-install-dir/auth/kubeadmin-password`

### Issue commands against your new cluster:

    export KUBECONFIG="${OKD4_LAB_PATH}/okd4-install-dir/auth/kubeconfig"
    oc get pods --all-namespaces

You may need to approve the certs of you master and or worker nodes before they can join the cluster:

    oc get csr

If you see certs in a Pending state:

    oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs oc adm certificate approve

Create an Empty volume for registry storage:

    oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed","storage":{"emptyDir":{}}}}'

### If it all goes pancake shaped:

    openshift-install --dir=okd4-install gather bootstrap --bootstrap 10.11.11.49 --master 10.11.11.60 --master 10.11.11.61 --master 10.11.11.62
