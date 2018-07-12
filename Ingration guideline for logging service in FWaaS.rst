
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
	
* Devstack local.conf:  http://paste.openstack.org/show/725188/
  
* Install devstack with ./stack.sh

Code integration
================

In **/opt/stack/neutron**:

.. code-block:: console

  # [log] Generic RPC stuffs for logging in server side
  git review -d 534227
  # Generic validate_request method for logging
  git review -x 529814
  # Adding resources callback handler
  git review -x 580575

* **Note:** 534227 patch will conflict with 529814 patch in neutron/services/logapi/drivers/openvswitch/driver.py

In **/opt/stack/neutron-fwaas**:

.. code-block:: console

  # Introduce accepted/dropped/rejected chains for future processing
  git review -d 574128
  # WIP: Add python binding for libnetfilter_log
  git review -x 530694
  # Add log validator for FWaaS side
  git review -x 532792
  # Firewall L3 logging extension
  git review -x 576338
  # [log]: Add rpc stuff for logging
  git review -x 530715
  # Add notification callback events
  git review -x 578718
  # Adding resources callback handler for logging service in FWaaS
  git review -x 580976
  # [log] Logging driver based iptables for FWaaS
  git review -x 553738

  sudo python setup.py install

In **python-neutron client**:

.. code-block:: console

  git clone https://github.com/openstack/python-neutronclient.git && cd python-neutronclient
  git review -d 579466
  sudo python setup.py install

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

* Restart neutron services:

  .. code-block:: console

    sudo systemctl restart devstack@q-svc.service
    sudo systemctl restart devstack@q-agt.service
    sudo systemctl restart devstack@q-l3.service

Network Configuration
=====================

  .. code-block:: console
	
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
	
	# Create vm0, vm1 and attach to net0, net0
	openstack server create  vm0 --image cirros-0.3.5-x86_64-disk --flavor m1.tiny --network net0
	openstack server create  vm1 --image cirros-0.3.5-x86_64-disk --flavor m1.tiny --network net1

	# Create fwg1 with default ingress, egress firewall group policy from admin project
	project_id=$(openstack project show admin | grep ' id' | awk '{print$4}')
	i_fwp_id=$(openstack firewall group policy list --long | grep ingress | grep $project_id | awk '{print$2}')
	e_fwp_id=$(openstack firewall group policy list --long | grep egress | grep $project_id | awk '{print$2}')

	# Attach fwg1 to internal router port that attaches to net0
	net0_port=$(openstack port list | grep 10.10.0.1 | awk '{print$2}')
	openstack firewall group create --name fwg1 --port $net0_port --ingress-firewall-policy $i_fwp_id --egress-firewall-policy $e_fwp_id

The deployed topology should look like:
  
  .. figure:: ./topo.png
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

  **Note:** You can test firewall loging with the following arguments:
  
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
	
	printf "===========\niptables v6\n===========\n"
	sudo ip netns exec $router_ns ip6tables -nvL neutron-l3-agent-accepted
	sudo ip netns exec $router_ns ip6tables -nvL neutron-l3-agent-dropped

* The iptables configuration results when logging is enabled would look like::

	===========
	iptables v4
	===========
	Chain neutron-l3-agent-accepted (4 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all  --  qr-d8998293-03 *       0.0.0.0/0            0.0.0.0/0            state NEW limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
		1    84 NFLOG      all  --  *      qr-d8998293-03  0.0.0.0/0            0.0.0.0/0            state NEW limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
		1    84 NFLOG      all  --  qr-e6aa17bd-be *       0.0.0.0/0            0.0.0.0/0            state NEW limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
		0     0 NFLOG      all  --  *      qr-e6aa17bd-be  0.0.0.0/0            0.0.0.0/0            state NEW limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
	   70  5880 ACCEPT     all  --  *      *       0.0.0.0/0            0.0.0.0/0
	Chain neutron-l3-agent-dropped (3 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all  --  qr-d8998293-03 *       0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
		0     0 NFLOG      all  --  *      qr-d8998293-03  0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
		0     0 NFLOG      all  --  qr-e6aa17bd-be *       0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
		0     0 NFLOG      all  --  *      qr-e6aa17bd-be  0.0.0.0/0            0.0.0.0/0            limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
		0     0 DROP       all  --  *      *       0.0.0.0/0            0.0.0.0/0
	===========
	iptables v6
	===========
	Chain neutron-l3-agent-accepted (4 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all      qr-d8998293-03 *       ::/0                 ::/0                 state NEW limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
		0     0 NFLOG      all      *      qr-d8998293-03  ::/0                 ::/0                 state NEW limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
		0     0 NFLOG      all      qr-e6aa17bd-be *       ::/0                 ::/0                 state NEW limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
		0     0 NFLOG      all      *      qr-e6aa17bd-be  ::/0                 ::/0                 state NEW limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
		0     0 ACCEPT     all      *      *       ::/0                 ::/0
	Chain neutron-l3-agent-dropped (3 references)
	 pkts bytes target     prot opt in     out     source               destination
		0     0 NFLOG      all      qr-d8998293-03 *       ::/0                 ::/0                 limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
		0     0 NFLOG      all      *      qr-d8998293-03  ::/0                 ::/0                 limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
		0     0 NFLOG      all      qr-e6aa17bd-be *       ::/0                 ::/0                 limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
		0     0 NFLOG      all      *      qr-e6aa17bd-be  ::/0                 ::/0                 limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
		0     0 DROP       all      *      *       ::/0                 ::/0

* **Iptables statistic changes:**

  The first packet has passed NFLOG rule in iptables

  .. code-block:: bash

	Chain neutron-l3-agent-accepted (4 references)
	pkts bytes target     prot opt in     out     source               destination
	1    84 NFLOG      all  --  *      qr-d8998293-03  0.0.0.0/0            0.0.0.0/0            state NEW limit: avg 100/sec burst 25 nflog-prefix  11014746673576200064 nflog-group 2
	1    84 NFLOG      all  --  qr-e6aa17bd-be *       0.0.0.0/0            0.0.0.0/0            state NEW limit: avg 100/sec burst 25 nflog-prefix  9822442003606001975 nflog-group 2
		
* Log information is written to the destination if configured in system journal like **/var/log/syslog**

  .. code-block:: bash

    tailf /var/log/syslog | grep -e ACCEPT -e DROP

