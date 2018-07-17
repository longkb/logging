.. _config-logging:

================================
Neutron Packet Logging Framework
================================

Packet logging service is designed as a Neutron plug-in that captures network
packets for relevant resources (e.g. security group or firewall group) when the
registerd events occur.

.. image:: figures/logging-framework.png
   :alt: Packet Logging Framework

Supported loggable resource types
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

From Rocky release, both of ``security_group`` and ``firewall_group`` are
supported as resource types in Neutron packet logging framework.


Service Configuration
~~~~~~~~~~~~~~~~~~~~~

To enable the logging service, follow the belowing steps .

#. On Neutron controller node, add ``log`` to ``service_plugins`` setting in
   ``/etc/neutron/neutron.conf`` file. For example:

   .. code-block:: none

     service_plugins = router,metering,log

#. To enable logging service for ``security_group`` in Layer 2, add ``log`` to
   ``[agent] extensions`` in ``/etc/neutron/plugins/ml2/ml2_conf.ini`` for
   controller node and in ``/etc/neutron/plugins/ml2/openvswitch_agent.ini``
   for compute/network nodes. For example:

   .. code-block:: ini

     [agent]
     extensions = log

#. To enable logging service for ``firewall_group`` in Layer 3, add
   ``fwaas_v2_log`` to the ``[AGENT] extensions`` setting in
   ``/etc/neutron/l3_agent.ini`` for both controller node and network nodes.
   For example:

   .. code-block:: ini

     [AGENT]
     extensions = fwaas_v2,fwaas_v2_log

#. On compute/network nodes, add configuration for logging service to
   ``[network_log]`` in ``/etc/neutron/plugins/ml2/openvswitch_agent.ini`` as
   shown bellow:

    .. code-block:: ini

      [network_log]
      rate_limit = 100
      burst_limit = 25
      #local_output_log_base = <None>

    In which, ``rate_limit`` is used to configure the maximum number of packets
    to be logged per second (packets per second). When a high rate triggers
    ``rate_limit``, logging queues packets to be logged. ``burst_limit`` is
    used to configure the maximum of queued packets. And logged packets can be
    stored anywhere by using ``local_output_log_base``.

    .. note::

       - It requires at least ``100`` for ``rate_limit`` and at least ``25``
         for ``burst_limit``.
       - If ``rate_limit`` is unset, logging will log unlimited.
       - If we don't specify ``local_output_log_base``, logged packets will be
         stored in system journal like ``/var/log/syslog`` by default.

#. Trusted projects ``policy.json`` configuration

   With the default ``/etc/neutron/policy.json``, administrators must set up
   resource logging on behalf of the cloud projects.

   If projects are trusted to administer their own loggable resources  in their
   cloud, neutron's policy file ``policy.json`` can be modified to allow this.

   Modify ``/etc/neutron/policy.json`` entries as follows:

   .. code-block:: none

      "get_loggable_resources": "rule:regular_user",
      "create_log": "rule:regular_user",
      "get_log": "rule:regular_user",
      "get_logs": "rule:regular_user",
      "update_log": "rule:regular_user",
      "delete_log": "rule:regular_user",

Service workflow for Operator
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#. To check the loggable resources that are supported by framework:

   .. code-block:: console

      $ openstack network loggable resources list
      +-----------------+
      | Supported types |
      +-----------------+
      | security_group  |
      | firewall_group  |
      +-----------------+

   .. note::

      - In VM ports, logging for ``security_group`` in currently works with
        ``openvswitch`` firewall driver only. ``linuxbridge`` is under
        deverloping.
      - Logging for ``firewall_group`` works on internal router ports only. VM
        ports would be supported in the future.

#. Log creation:

   * Create a logging resource with an appropriate resource type

     .. code-block:: console

      $ openstack network log create --resource-type security_group \
        --description "Collecting all security events" \
        --event ALL Log_Created
      +-----------------+------------------------------------------------+
      | Field           | Value                                          |
      +-----------------+------------------------------------------------+
      | Description     | Collecting all security events                 |
      | Enabled         | True                                           |
      | Event           | ALL                                            |
      | ID              | 8085c3e6-0fa2-4954-b5ce-ff6207931b6d           |
      | Name            | Log_Created                                    |
      | Project         | 02568bd62b414221956f15dbe9527d16               |
      | Resource        | None                                           |
      | Target          | None                                           |
      | Type            | security_group                                 |
      | created_at      | 2017-07-05T02:56:43Z                           |
      | revision_number | 0                                              |
      | tenant_id       | 02568bd62b414221956f15dbe9527d16               |
      | updated_at      | 2017-07-05T02:56:43Z                           |
      +-----------------+------------------------------------------------+

   * Create logging resource with a given firewall group resource (sg1 and fwg1)

     .. code-block:: console

      $ openstack network log create my-log --resource-type security_group --resource sg1
      $ openstack network log create my-log --resource-type firewall_group --resource fwg1

   * Create logging resource with a given target (portA)

     .. code-block:: console

      $ openstack network log create my-log --resource-type security_group --target portA

   * Create logging resource for only the given target (portB) and the given
     resource (sg1 or fwg1)

     .. code-block:: console

      $ openstack network log create my-log --resource-type security_group --target portB --resource sg1
      $ openstack network log create my-log --resource-type firewall_group --target portB --resource fwg1

   .. note::

      - The ``Enabled`` field is set to ``True`` by default. If enabled, logged
        events is written to the destination if ``local_output_log_base`` is
        configured or ``/var/log/syslog`` in default.
      - ``Event`` field will be set to ``ALL`` if ``--event`` is not specified
        from log creation request.

#. Enable/Disable log

   We can ``enable`` or ``disable`` logging objects at runtime. It means that
   it will apply to all registered ports with the logging object immediately.
   For example:

   .. code-block:: console

      $ openstack network log set --disable Log_Created
      $ openstack network log show Log_Created
       +-----------------+------------------------------------------------+
       | Field           | Value                                          |
       +-----------------+------------------------------------------------+
       | Description     | Collecting all security events                 |
       | Enabled         | False                                          |
       | Event           | ALL                                            |
       | ID              | 8085c3e6-0fa2-4954-b5ce-ff6207931b6d           |
       | Name            | Log_Created                                    |
       | Project         | 02568bd62b414221956f15dbe9527d16               |
       | Resource        | None                                           |
       | Target          | None                                           |
       | Type            | security_group                                 |
       | created_at      | 2017-07-05T02:56:43Z                           |
       | revision_number | 1                                              |
       | tenant_id       | 02568bd62b414221956f15dbe9527d16               |
       | updated_at      | 2017-07-05T03:12:01Z                           |
       +-----------------+------------------------------------------------+

Logged events description
~~~~~~~~~~~~~~~~~~~~~~~~~

Currently, packet logging framework supports to collect ``ACCEPT`` or ``DROP``
or both events related to registered resources. As mentioned above, Neutron
packet logging framework offers two loggable resources through the ``log``
service plug-in: ``security_group`` and ``firewall_group``.

The  general characteristics of each event will be shown as the following:

* Log every ``DROP`` events: Every ``DROP`` security events will be generated
  when an incoming or outgoing session is blocked by the security groups or
  firewall groups

* Log an ``ACCEPT`` event: The ``ACCEPT`` security event will be generated only
  for each ``NEW`` incoming or outgoing session that is allowed by security
  groups or firewall groups. More details for the ``ACCEPT`` events are shown
  as bellow:

  * North/South ``ACCEPT``: For a North/South session there would be a single
    ``ACCEPT`` event irrespective of direction.

  * East/West ``ACCEPT``/``ACCEPT``: In an intra-project East/West session
    where the originating port allows the session and the destination port
    allows the session, i.e. the traffic is allowed, there would be two
    ``ACCEPT`` security events generated, one from the perspective of the
    originating port and one from the perspective of the destination port.

  * East/West ``ACCEPT``/``DROP``: In an intra-project East/West session
    initiation where the originating port allows the session and the
    destination port does not allow the session there would be ``ACCEPT``
    security events generated from the perspective of the originating port and
    ``DROP`` security events generated from the perspective of the destination
    port.

#. The security events that are collected by security group should include:

   * A timestamp of the flow.
   * A status of the flow ``ACCEPT``/``DROP``.
   * An indication of the originator of the flow, e.g which project or log resource
     generated the events.
   * An identifier of the associated instance interface (neutron port id).
   * A layer 2, 3 and 4 information (mac, address, port, protocol, etc).

   * Security event record format:

     * Logged data of an ``ACCEPT`` event would look like:

     .. code-block:: console

         May 5 09:05:07 action=ACCEPT project_id=736672c700cd43e1bd321aeaf940365c
         log_resource_ids=['4522efdf-8d44-4e19-b237-64cafc49469b', '42332d89-df42-4588-a2bb-3ce50829ac51']
         vm_port=e0259ade-86de-482e-a717-f58258f7173f
         ethernet(dst='fa:16:3e:ec:36:32',ethertype=2048,src='fa:16:3e:50:aa:b5'),
         ipv4(csum=62071,dst='10.0.0.4',flags=2,header_length=5,identification=36638,offset=0,
         option=None,proto=6,src='172.24.4.10',tos=0,total_length=60,ttl=63,version=4),
         tcp(ack=0,bits=2,csum=15097,dst_port=80,offset=10,option=[TCPOptionMaximumSegmentSize(kind=2,length=4,max_seg_size=1460),
         TCPOptionSACKPermitted(kind=4,length=2), TCPOptionTimestamps(kind=8,length=10,ts_ecr=0,ts_val=196418896),
         TCPOptionNoOperation(kind=1,length=1), TCPOptionWindowScale(kind=3,length=3,shift_cnt=3)],
         seq=3284890090,src_port=47825,urgent=0,window_size=14600)

     * Logged data of a ``DROP`` event:

     .. code-block:: console

         May 5 09:05:07 action=DROP project_id=736672c700cd43e1bd321aeaf940365c
         log_resource_ids=['4522efdf-8d44-4e19-b237-64cafc49469b'] vm_port=e0259ade-86de-482e-a717-f58258f7173f
         ethernet(dst='fa:16:3e:ec:36:32',ethertype=2048,src='fa:16:3e:50:aa:b5'),
         ipv4(csum=62071,dst='10.0.0.4',flags=2,header_length=5,identification=36638,offset=0,
         option=None,proto=6,src='172.24.4.10',tos=0,total_length=60,ttl=63,version=4),
         tcp(ack=0,bits=2,csum=15097,dst_port=80,offset=10,option=[TCPOptionMaximumSegmentSize(kind=2,length=4,max_seg_size=1460),
         TCPOptionSACKPermitted(kind=4,length=2), TCPOptionTimestamps(kind=8,length=10,ts_ecr=0,ts_val=196418896),
         TCPOptionNoOperation(kind=1,length=1), TCPOptionWindowScale(kind=3,length=3,shift_cnt=3)],
         seq=3284890090,src_port=47825,urgent=0,window_size=14600)

#. The events that are collected by firewall group should include:

   * A timestamp of the flow.
   * A status of the flow ``ACCEPT``/``DROP``.
   * The identifier of log objects that are collecting this event
   * An identifier of the associated instance interface (neutron port id).
   * A layer 2, 3 and 4 information (mac, address, port, protocol, etc).

   * Security event record format:

     * Logged data of an ``ACCEPT`` event would look like:

     .. code-block:: console

2018-07-20 12:15:04.551795
event=ACCEPT, log_ids=[u'2da69392-fdde-41ec-945a-2c235d75cf03'], port=6270396a-7bbb-4a75-a94f-7c978e7ea14b 
pkt=ethernet(dst='fa:16:3e:31:6a:81',ethertype=2048,src='fa:16:3e:7c:a6:d6')
ipv4(csum=51375,dst='10.10.1.8',flags=2,header_length=5,identification=24020,offset=0,option=None,proto=1,src='10.10.0.10',tos=0,total_length=84,ttl=63,version=4)
icmp(code=0,csum=47365,data=echo(data='\xdb\xce\xf1)\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00',id=29185,seq=0),type=8)

     * Logged data of a ``DROP`` event:

     .. code-block:: console

2018-07-20 12:19:14.367804
event=DROP, log_ids=[u'cf6260c0-43a0-4d37-abf8-9823e58c7ce8'], port=6270396a-7bbb-4a75-a94f-7c978e7ea14b
pkt=ethernet(dst='fa:16:3e:f1:49:e0',ethertype=2048,src='fa:16:3e:74:01:fc')
ipv4(csum=14186,dst='10.10.0.10',flags=2,header_length=5,identification=61209,offset=0,option=None,proto=1,src='10.10.1.8',tos=0,total_length=84,ttl=63,version=4)
icmp(code=0,csum=17412,data=echo(data='\xac\x7fz6\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00
\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00',id=36097,seq=68),type=8)

.. note::

   No other extraneous events are generated within the security event logs,
   e.g. no debugging data, etc.