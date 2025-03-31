# Setup passwordless SSH on Nodes

Generate keypair locally: `ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""`

Copy ssh key to the Node: `ssh-copy-id -i ~/.ssh/id_rsa.pub youruser@<ip>`

Enable passwordless sudo for the user nick on the nodes via visudo 

# Run Ansible 

`ansible-playbook ansible/install-k3s.yaml -i ansible/inventory.yaml`