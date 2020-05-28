#!/bin/bash
set -eux

yum -y update
yum -y install ansible jq
cd /tmp/src/
curl -s https://releases.hashicorp.com/terraform/0.12.25/terraform_0.12.25_linux_amd64.zip > /tmp/src/terraform.zip
unzip terraform.zip
mv terraform /usr/local/bin

su ansible -c bash <<'ANSIBLE_EOF'
#!/bin/bash
# abort this script on errors.
set -eux

# configure git.
# see http://stackoverflow.com/a/12492094/477532
git config --global user.name 'nolon'
git config --global user.email 'nolon@gmx.net'
git config --global push.default simple
#git config --list --show-origin
ANSIBLE_EOF

