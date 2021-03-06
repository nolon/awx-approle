#!/bin/bash
export user=vagrant
export home=/home/vagrant
export PATH="$PATH:/usr/local/bin/"
echo "[Setup] - Starting AWX setup"

# Python and ansible
echo "[Setup] - Installing Python and Ansible"
dnf update -y
dnf install python3 python3-pip -y
pip3 install ansible
subscription-manager repos --enable ansible-2.8-for-rhel-8-x86_64-rpms
dnf -y install ansible
ansible --version

# Python and ansible
echo "[Setup] - Installing Docker and Docker compose"
dnf install epel-release -y
dnf install git gcc gcc-c++ nodejs gettext device-mapper-persistent-data lvm2 bzip2 python3-pip -y
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install docker-ce-3:18.09.1-3.el7 -y
docker --version
systemctl start docker
systemctl enable --now docker.service
sudo usermod -aG docker ${user}
alternatives --set python /usr/bin/python3
pip3 install docker-compose

echo "[Setup] - Installing tools and Vault binary"
cd ${home}
dnf install wget unzip jq git emacs -y
wget https://releases.hashicorp.com/vault/1.3.2/vault_1.3.2_linux_amd64.zip -o wget.log
unzip vault_1.3.2_linux_amd64.zip
mv ./vault /usr/local/bin
chmod +x /usr/local/bin/vault
vault --version

echo "[Setup] - Cloning Amsible AWX repository"    
cd ${home}
git clone https://github.com/ansible/awx.git
chown -R ${user}:${user} ${home}/awx/
chown -R ${user}:${user} ${home}/assets/

echo "[Setup] - Building updated Dockerfile"
cd ${home}/assets/
tags=$(curl -s https://hub.docker.com/v2/repositories/ansible/awx_web/tags | jq -r .results[].name | sort -r | tr '\n' ' ')
most_recent=$(echo $tags | awk '{print $2}')
if [ ! -z $most_recent ]; then
  echo "[Setup] - Using Docker image: ansible/awx_web:$most_recent"
else
  most_recent="9.3.0"
  echo "[Setup] - Could not determine most recent image. Using ansible/awx_web:$most_recent"
fi
echo "[Setup] - Building Dockerfile"
cat <<EOF > Dockerfile
FROM ansible/awx_web:$most_recent
COPY ./hashivault.py.v1 /var/lib/awx/venv/awx/lib/python3.6/site-packages/awx/main/credential_plugins/hashivault.py
EOF
echo "[Setup] - Dockerfile contents"
cat Dockerfile
sudo docker build -t ansible/awx_web:$most_recent .

echo "[Setup] - Copying updated inventory file"
cd ${home}/awx/installer
cp inventory inventory.backup
cp ${home}/assets/inventory .
cp ${home}/assets/hashivault.py.v1 ${home}/awx/awx/main/credential_plugins/hashivault.py

echo "[Setup] - Starting playbook install"
grep -v '^#' inventory | grep -v '^$'
/usr/local/bin/ansible-playbook -i inventory install.yml
#echo "[Setup] - Copying updated version of hashivault.py to awx_web and awx_task"
#docker cp ${home}/assets/hashivault.py.v1 awx_task:/var/lib/awx/venv/awx/lib/python3.6/site-packages/awx/main/credential_plugins/hashivault.py
#docker cp ${home}/assets/hashivault.py.v1 awx_web:/var/lib/awx/venv/awx/lib/python3.6/site-packages/awx/main/credential_plugins/hashivault.py

echo "[Setup] - Starting Dev vault instance on Docker"
docker run -d --name=vault -p 8200:8200 --cap-add=IPC_LOCK -e 'VAULT_DEV_ROOT_TOKEN_ID=root' --network="awxcompose_default" vault
echo "[Setup] - Pausing for Vault to start"
sleep 60
export VAULT_ADDR=http://127.0.0.1:8200 && export VAULT_TOKEN=root
vault token lookup
vault audit enable file file_path=/tmp/vault_audit.log

echo "[Setup] - Calling the setup-vault.sh script"
cd ${home}/assets/
chmod +x setup-vault.sh
./setup-vault.sh

echo "[Setup] - Vault configuration completed: Displaying AppRole parameters, public key and VAULT_ADDR"
echo "[Setup] - VAULT_ADDR for Ansible tower: http://$(sudo docker inspect vault | jq -r '.[0].NetworkSettings.Networks.awxcompose_default.IPAddress'):8200"
cat role.json | jq -r '.data'
cat secretid.json | jq -r '.data'
cat ansible-key.pub