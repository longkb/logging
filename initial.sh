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

# Update port name
port0=$(openstack port list | grep 10.10.0.1 | awk '{print$2}')
openstack port set --name port0 $port0
port1=$(openstack port list | grep 10.10.1.1 | awk '{print$2}')
openstack port set --name port1 $port1

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

#Create fwg2
openstack firewall group create --name fwg2 --ingress-firewall-policy $i_fwp_id --egress-firewall-policy $e_fwp_id
