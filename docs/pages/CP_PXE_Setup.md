## Adding PXE capability to your Control Plane server

At this point you need to have set up DNS and HTTP on your Control Plane server.  [Setting Up Control Plane](Control_Plane.md)

First let's install and enable a TFTP server:

    yum -y install tftp tftp-server xinetd
    systemctl start xinetd
    systemctl enable xinetd
    firewall-cmd --add-port=69/tcp --permanent
    firewall-cmd --add-port=69/udp --permanent
    firewall-cmd --reload

Edit the tftp configuration file to enable tftp.  Set `disable = no`

    vi /etc/xinetd.d/tftp

    # default: off
    # description: The tftp server serves files using the trivial file transfer \
    #	protocol.  The tftp protocol is often used to boot diskless \
    #	workstations, download configuration files to network-aware printers, \
    #	and to start the installation process for some operating systems.
    service tftp
    {
    	socket_type		= dgram
    	protocol		= udp
    	wait			= yes
    	user			= root
    	server			= /usr/sbin/in.tftpd
    	server_args		= -s /var/lib/tftpboot
    	disable			= no
    	per_source		= 11
    	cps			= 100 2
    	flags			= IPv4
    }

With TFTP enabled, we need to copy over some files for it to serve up.  Assuming that you have already [set up NGINX](Nginx_Config.md), do the following:

    mkdir -p /var/lib/tftpboot/networkboot
    cd /usr/share/nginx/html/install/centos/
    cp ./EFI/BOOT/BOOTX64.EFI /var/lib/tftpboot
    cp ./images/pxeboot/initrd.img /var/lib/tftpboot/networkboot
    cp ./images/pxeboot/vmlinuz /var/lib/tftpboot/networkboot

We have one more step with TFTP, and that is the grub.cfg file.  I have provided one for you in the `PXE_Setup` folder within this project.  It needs to be configured with the IP address of your HTTP server that is hosting your Install repository, kickstart, firstboot, and hostconfig files.  See [Host OS Provisioning](Setup_Env.md)

    cd PXE_Setup
    mkdir tmp_work
    cp grub.cfg tmp_work
    cd tmp_work
    sed -i "s|%%HTTP_IP%%|10.11.11.10|g" ./grub.cfg  # Replace with the IP address of your Control Plane Server.
    scp grub.cfg root@10.11.11.10:/mnt/sda1/tftpboot # Replace with the IP address of your Control Plane Server.
    cd ..
    rm -rf tmp_work

Finally, your DHCP server needs to be able to direct PXE Boot clients to your TFTP server.  This is normally done by configuring a couple of parameters in your DHCP server, which will look something like:

    next-server = 10.11.11.10  # The IP address of your TFTP server
    filename = "BOOTX64.EFI"

Unfortunately, most home routers don't support the configuration of those parameters.  Your options here are either to use my recommended GL-AR750S-Ext travel router, or configure your Control Plane to serve DHCP.

__Warning:__ If you set up DHCP on the Control Plane you will either have to disable DHCP in your home router, or put your lab on another subnet.  I can't recommend the GL-AR750S-Ext enough.

Assuming that you are using the GL-AR750S-Ext, you will first need to enable root ssh access to your router.  The best way to do this is by adding an SSH key.  If you don't already have an ssh key, create one: (Take the defaults for all of the prompts, don't set a key password)

    ssh-keygen
    <Enter>
    <Enter>
    <Enter>

1. Login to your router with a browser: `https://<router IP>`
2. Expand the `MORE SETTINGS` menu on the left, and select `Advanced`
3. Login to the Advanced Administration console
4. Expand the `System` menu at the top of the screen, and select `Administration`
   1. Ensure that the Dropbear Instance `Interface` is set to `unspecified` and that the `Port` is `22`
   2. Ensure that the following are __NOT__ checked:
      * `Password authentication`
      * `Allow root logins with password`
      * `Gateway ports`
   3. Paste your public SSH key into the `SSH-Keys` section at the bottom of the page
      * Your public SSH key is likely in the file `$HOME/.ssh/id_rsa.pub`
   4. Click `Save & Apply`

Now that we have enabled SSH access to the router, we will login and complete our setup from the command-line.  Replace the IP address below with the IP address of your Control Plane server.

    ssh root@10.11.11.1  # Replace with the IP address of your router.
    uci set dhcp.@dnsmasq[0].dhcp_boot=BOOTX64.EFI,,10.11.11.10
    uci commit dhcp
    /etc/init.d/dnsmasq restart
    exit

### DHCP on Linux:

If you are going to set up your own DHCP server on the Control Plane, do the following:

    yum -y install dhcp
    firewall-cmd --add-service=dhcp --permanent
    firewall-cmd --reload

Now edit the DHCP configuration:

    vi /etc/dhcp/dhcpd.conf

    # DHCP Server Configuration file.

    ddns-update-style interim;
    ignore client-updates;
    authoritative;
    allow booting;
    allow bootp;
    allow unknown-clients;

    # internal subnet for my DHCP Server
    subnet 10.10.11.0 netmask 255.255.255.0 {
    range 10.10.11.11 10.10.11.29;
    option domain-name-servers 10.10.11.10;
    option domain-name "your.domain.org";
    option routers 10.10.11.1;
    option broadcast-address 10.10.11.255;
    default-lease-time 600;
    max-lease-time 7200;

    # IP of TFTP Server
    next-server 10.10.11.10;
    filename "BOOTX64.EFI";
    }

Finally, enable DHCP:

    systemctl enable dhcpd
    systemctl start dhcpd

Regardless of the route that you chose, you should now have an environment ready for PXE Boot!

Assuming that you have followed the steps here: [Host OS Provisioning](Setup_Env.md), then we are ready to [PXE Boot a bare metal host](Install_Bare_Metal.md)
