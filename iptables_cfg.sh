router_id=$(openstack router list | grep router0 | awk '{print$2}')
router_ns='qrouter-'$router_id

printf "===========\niptables v4\n===========\n"
sudo ip netns exec $router_ns iptables -nvL neutron-l3-agent-accepted
sudo ip netns exec $router_ns iptables -nvL neutron-l3-agent-dropped
	
printf "===========\niptables v6\n===========\n"
sudo ip netns exec $router_ns ip6tables -nvL neutron-l3-agent-accepted
sudo ip netns exec $router_ns ip6tables -nvL neutron-l3-agent-dropped
