# Create net0 with subnet subnet0
openstack network create --share net0
openstack subnet create subnet0 --ip-version 4 --gateway 10.10.0.1 --network net0 --subnet-range 10.10.0.0/24

# Create net1 with subnet subnet1
openstack network create --share net1
openstack subnet create subnet1 --ip-version 4 --gateway 10.10.1.1 --network net0 --subnet-range 10.10.1.0/24

# Create router router0 and attach subnet0, subnet1 to router0
openstack router create router0
openstack router add subnet router0 subnet0
openstack router add subnet router0 subnet1

# Create fwg1 with default ingress, egress firewall group policy from admin project
project_id=$(openstack project show admin | grep ' id' | awk '{print$4}')
i_fwp_id=$(openstack firewall group policy list --long | grep ingress | grep $project_id | awk '{print$2}')
e_fwp_id=$(openstack firewall group policy list --long | grep egress | grep $project_id | awk '{print$2}')

# Attach fwg1 to internal router port
net0_port=$(openstack port list | grep 10.10.0.1 | awk '{print$2}')
openstack firewall group create --name fwg1 --port $net0_port --ingress-firewall-policy $i_fwp_id --egress-firewall-policy $e_fwp_id
