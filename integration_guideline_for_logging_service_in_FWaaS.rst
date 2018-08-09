
Integration guideline for logging service in FWaaS
==================================================

* Related bug: https://bugs.launchpad.net/neutron/+bug/1720727
* Related patches: https://review.openstack.org/#/q/topic:bug/1720727+(status:open+OR+status:merged)

Environment
===========

* Ubuntu 16.04
* Dependencies
  
  Install the required dependencies for python-libnetfilter on Ubuntu 

  .. code-block:: console

    sudo apt-get install libnetfilter-log1 python-zmq
	
* Devstack local.conf:  http://paste.openstack.org/show/725635/
  
  .. code-block:: block
  
    [[local|localrc]]
    ADMIN_PASSWORD=stack
    DATABASE_PASSWORD=stack
    RABBIT_PASSWORD=stack
    SERVICE_PASSWORD=$ADMIN_PASSWORD
    LOGFILE=$DEST/logs/stack.sh.log
    LOGDAYS=2
    RECLONE=Yes
    disable_service n-net
    disable_service tempest
    disable_service c-api
    disable_service c-vol
    disable_service c-sch
    enable_service neutron
    enable_service q-log
    enable_plugin neutron-fwaas https://github.com/openstack/neutron-fwaas.git refs/changes/91/589991/4
    enable_service q-fwaas-v2
    FW_L2_DRIVER=ovs
    
    [[post-config|/etc/neutron/l3_agent.ini]]
    [AGENT]
    extensions = fwaas_v2,fwaas_v2_log 

* Install devstack with ./stack.sh

Code integration
================

Devstack configuration
======================

To enable the service, follow the steps below.

* On Neutron side:

  - Ensure that **log** already added into **/etc/neutron/neutron.conf** as service plugin. For example:
  
  .. code-block:: block

    [DEFAULT]
    service_plugins = neutron.services.l3_router.l3_router_plugin.L3RouterPlugin,neutron.services.metering.metering_plugin.MeteringPlugin,log,firewall_v2

* On FWaaS side:

  - Add the **fwaas_v2_log** as Logging extension to the extensions setting in **/etc/neutron/l3_agent.ini**:
  
  .. code-block:: block

    [AGENT]
    extensions = fwaas_v2,fwaas_v2_log

  - Besides, FWaaS v2 logging also enable some optional configuraion. In **/etc/neutron/l3_agent.ini**, config logging service as bellow:

  .. code-block:: block

     [network_log]
     rate_limit = 100
     burst_limit = 25
     local_output_log_base = /home/stack/fw_log

* Restart neutron services:

  .. code-block:: console

    sudo systemctl restart devstack@q-svc.service
    sudo systemctl restart devstack@q-agt.service
    sudo systemctl restart devstack@q-l3.service

Network Configuration
=====================

  .. code-block:: console
	
	# Remove existing network resources
	source ~/devstack/openrc admin admin
	openstack router remove subnet router1 private-subnet
	openstack router remove subnet router1 ipv6-private-subnet
	openstack router delete router1
	openstack network delete private public

	# Create net0 with subnet subnet0
	openstack network create --share net0
	openstack subnet create subnet0 --ip-version 4 --gateway 10.10.0.1 --network net0 --subnet-range 10.10.0.0/24

	# Create net1 with subnet subnet1
	openstack network create --share net1
	openstack subnet create subnet1 --ip-version 4 --gateway 10.10.1.1 --network net1 --subnet-range 10.10.1.0/24
	
	# Create router router0 and attach subnet0, subnet1 to router0
	openstack router create router0
	openstack router add subnet router0 subnet0
	openstack router add subnet router0 subnet1
	
	# Create vm0, vm1 and attach to net0, net1
	openstack server create  vm0 --image cirros-0.3.5-x86_64-disk --flavor m1.tiny --network net0
	openstack server create  vm1 --image cirros-0.3.5-x86_64-disk --flavor m1.tiny --network net1

	# Create fwg1 with default ingress, egress firewall group policy from admin project
	project_id=$(openstack project show admin | grep ' id' | awk '{print$4}')
	i_fwp_id=$(openstack firewall group policy list --long | grep ingress | grep $project_id | awk '{print$2}')
	e_fwp_id=$(openstack firewall group policy list --long | grep egress | grep $project_id | awk '{print$2}')

	# Create and attach fwg1 to internal router port that attaches to net0
	net0_port=$(openstack port list | grep -e "'10.10.0.1'" | awk '{print$2}')
	openstack firewall group create --name fwg1 --port $net0_port --ingress-firewall-policy $i_fwp_id --egress-firewall-policy $e_fwp_id
	
	# Create fwg2
	openstack firewall group create --name fwg2 --ingress-firewall-policy $i_fwp_id --egress-firewall-policy $e_fwp_id

The deployed topology should look like:
  
  .. figure:: figures/topo.png
     :alt: Network topology for testing

Workflow testing scenario
=========================

* Confirm **firewall_group** are supported as logging resource:

  .. code-block:: console

	$ openstack network loggable resources list
	+-----------------+
	| Supported types |
	+-----------------+
	| security_group  |
	| firewall_group  |
	+-----------------+

* Create a logging resource for **ALL** event with **firewall_group** as a resource type:

  .. code-block:: console

	openstack network log create --resource-type firewall_group --enable --event ALL Log_all

  **Note:** You can test firewall logging with the following arguments:
  
  - **--event <event>** *#[ALL, ACCEPT, DROP]*

  -	**--resource-type firewall_group**

  - **--resource <resource>** *# Firewall Group name or ID*

  - **--target <target>** *# Port Name or ID*

	
* Using **ping** command as traffic generator to test traffic logging from vm0 to vm1

  - Access the console of vm0
  
  - ping from vm0 to vm1
  
* Check nflog rule creation in **accepted** and **dropped** chain from both **iptables** and **ip6tables**

  .. code-block:: bash

	router_id=$(openstack router list | grep router0 | awk '{print$2}')
	router_ns='qrouter-'$router_id

	printf "===========\niptables v4\n===========\n"
	sudo ip netns exec $router_ns iptables -nvL neutron-l3-agent-accepted
	sudo ip netns exec $router_ns iptables -nvL neutron-l3-agent-dropped
	sudo ip netns exec $router_ns iptables -nvL neutron-l3-agent-rejected
	
	printf "===========\niptables v6\n===========\n"
	sudo ip netns exec $router_ns ip6tables -nvL neutron-l3-agent-accepted
	sudo ip netns exec $router_ns ip6tables -nvL neutron-l3-agent-dropped
	sudo ip netns exec $router_ns iptables -nvL neutron-l3-agent-rejected

* The iptables configuration results when logging is enabled would look like::

	===========
	iptables v4
	===========
	Chain neutron-l3-agent-accepted (2 references)
	 pkts bytes target     prot opt in     out     source               destination
	   10   840 NFLOG      all  --  qr-0a3238aa-fd *       0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  13056991142078571324
		0     0 NFLOG      all  --  *      qr-0a3238aa-fd  0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  13056991142078571324
	   10   840 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0
	Chain neutron-l3-agent-dropped (7 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all  --  qr-0a3238aa-fd *       0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  9844330454595421866
		0     0 NFLOG      all  --  *      qr-0a3238aa-fd  0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  9844330454595421866
		0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0
	Chain neutron-l3-agent-rejected (0 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all  --  qr-0a3238aa-fd *       0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  9844330454595421866
		0     0 NFLOG      all  --  *      qr-0a3238aa-fd  0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  9844330454595421866
		0     0 REJECT     all  --  *      *       0.0.0.0/0            0.0.0.0/0            reject-with icmp-port-unreachable
	===========
	iptables v6
	===========
	Chain neutron-l3-agent-accepted (2 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all      qr-0a3238aa-fd *       ::/0                 ::/0                 limit: avg 100/sec burst 25 nflog-prefix  13056991142078571324
		0     0 NFLOG      all      *      qr-0a3238aa-fd  ::/0                 ::/0                 limit: avg 100/sec burst 25 nflog-prefix  13056991142078571324
		0     0 ACCEPT     all      *      *       ::/0                 ::/0
	Chain neutron-l3-agent-dropped (7 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all      qr-0a3238aa-fd *       ::/0                 ::/0                 limit: avg 100/sec burst 25 nflog-prefix  9844330454595421866
		0     0 NFLOG      all      *      qr-0a3238aa-fd  ::/0                 ::/0                 limit: avg 100/sec burst 25 nflog-prefix  9844330454595421866
		0     0 DROP       all      *      *       ::/0                 ::/0
	Chain neutron-l3-agent-rejected (0 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all  --  qr-0a3238aa-fd *       0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  9844330454595421866
		0     0 NFLOG      all  --  *      qr-0a3238aa-fd  0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  9844330454595421866



* **Iptables statistic changes:**

  The first packet has passed NFLOG rule in iptables

  .. code-block:: bash

	Chain neutron-l3-agent-accepted (2 references)
	 pkts bytes target     prot opt in     out     source               destination
	   10   840 NFLOG      all  --  qr-0a3238aa-fd *       0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  13056991142078571324
	    0     0 NFLOG      all  --  *      qr-0a3238aa-fd  0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  13056991142078571324
	   10   840 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0

* Log information is written to the destination if configured **/etc/neutron/l3_agent.ini** or **/var/log/syslog** by default

  .. code-block:: bash

    $ tailf /home/stack/fw_log | grep -e ACCEPT -e DROP

      2018-08-09 14:18:58 action=ACCEPT, project_id=150b504a5d474561872ee1e6c0dfb191, log_resource_ids=['36003ab5-7a87-4ef6-976c-01ebf4f3a19c'], port=0a3238aa-fd65-4fde-b86c-ad4b6f8dc6d7, pkt=ethernet(dst='fa:16:3e:3d:da:48',ethertype=2048,src='fa:16:3e:77:de:99')ipv4(csum=34424,dst='10.10.1.12',flags=2,header_length=5,identification=40951,offset=0,option=None,proto=1,src='10.10.0.26',tos=0,total_length=84,ttl=63,version=4)icmp(code=0,csum=56449,data=echo(data='\x1fId3\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00',id=38913,seq=0),type=8)
      2018-08-09 14:21:49 action=DROP, project_id=150b504a5d474561872ee1e6c0dfb191, log_resource_ids=['36003ab5-7a87-4ef6-976c-01ebf4f3a19c'], port=a3b81de4-885d-4787-8337-8e519df95003, pkt=ipv4(csum=22235,dst='10.10.0.26',flags=2,header_length=5,identification=53140,offset=0,option=None,proto=1,src='10.10.1.12',tos=0,total_length=84,ttl=63,version=4)icmp(code=0,csum=64811,data=echo(data='0\x93I=\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00',id=33025,seq=2),type=8)
