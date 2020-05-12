#!/usr/bin/env bash

# TODO:
#  - bump VM cores to avilable cores (looks like 2, but will use nproc)
#  - add -j nproc to build commands

set -ev

TEST_RUNNER="scripts/ci/fedora-test-runner.sh"

#
# Travis gives us about 7.5GB of RAM and two cores
# https://docs.travis-ci.com/user/reference/overview/
MEMORY=4096
VCPUS=2

echo "KVM Execution Hook"

# Install these here so other builds don't have to wait on these deps to download and install
sudo apt-get install qemu-kvm libvirt-bin virtinst bridge-utils cpu-checker libguestfs-tools

sudo usermod -a -G kvm,libvirt,libvirt-qemu $USER

kvm-ok

#Debug
pwd

#
# Hrmm we may have to tinker with config...
#
sudo cat /etc/libvirt/qemu.conf

sudo systemctl enable libvirtd
sudo systemctl start libvirtd

sudo virsh list --all

ls $HOME/.ssh
ssh-keygen -N "" -f "$HOME/.ssh/id_rsa"

#
# Get the Fedora Cloud Image, It is a base image that small and ready to go, extract it and modify it with virt-sysprep
#
# TODO Should we verify this with sha256sum compare to expected or perhaps just pull in Fedora's keys?
#  - https://alt.fedoraproject.org/en/verify.html
# It is https, so we are at least (hopefully) not getting MITM on the image...
# Do this in $HOME so we don't try and copy the image file along with the source code into the image file with virt-sysprep
# We can probably just cd to home in the beginning...
pushd $HOME
echo "Starting wget"
wget https://download.fedoraproject.org/pub/fedora/linux/releases/32/Cloud/x86_64/images/Fedora-Cloud-Base-32-1.6.x86_64.raw.xz
echo "Got image, unxz'ing"
unxz -T0 Fedora-Cloud-Base-32-1.6.x86_64.raw.xz
echo "unxz image"

# XXX dbg
ls -la "$HOME/Fedora-Cloud-Base-32-1.6.x86_64.raw"
sudo chown root:root "$HOME/Fedora-Cloud-Base-32-1.6.x86_64.raw"
sudo chmod a+rw "$HOME/Fedora-Cloud-Base-32-1.6.x86_64.raw"
ls -la "$HOME/Fedora-Cloud-Base-32-1.6.x86_64.raw"

# We might not need the chown magic above... it might have been search
# missing on directories.
chmod a+x $HOME

#
# Modify the virtual image to:
#   - Enable a login, we just use root
#   - Enable passwordless login
#     - Force a relabel to fix labels on ssh keys
#
echo "Starting sysprep"
sudo virt-sysprep -a "$HOME/Fedora-Cloud-Base-32-1.6.x86_64.raw" \
  --root-password password:123456 \
  --hostname demo \
  --append-line '/etc/ssh/sshd_config:PermitRootLogin yes' \
  --append-line '/etc/ssh/sshd_config:PubkeyAuthentication yes' \
  --mkdir /root/.ssh \
  --upload "$HOME/.ssh/id_rsa.pub:/root/.ssh/authorized_keys" \
  --chmod '0600:/root/.ssh/authorized_keys' \
  --run-command 'chown root:root /root/.ssh/authorized_keys' \
  --copy-in "$TRAVIS_BUILD_DIR:/root" \
  --network \
  --selinux-relabel
echo "Finish sysprep"

#
# Now we create a domain by using virt-install. This not only creates the domain, but runs the VM as well
# It should be ready to go for ssh, once ssh starts.
#
echo "Starting virt-install"
sudo virt-install \
  --name demo \
  --memory $MEMORY \
  --vcpus $VCPUS \
  --disk "$HOME/Fedora-Cloud-Base-32-1.6.x86_64.raw" \
  --import --noautoconsole
echo "Finishing virt-install"

#
# Here comes the tricky part, we have to figure out when the VM comes up AND we need the ip address for ssh. So we
# can check the net-dhcp leases, for our host. We have to poll, and we will poll for up 3 minutes in 6 second
# intervals, so 30 poll attempts (0-29 inclusive). I don't know of a better way to do this.
#
# We have a full reboot + relabel, so first sleep gets us close
#
sleep 30
for i in $(seq 0 29); do
    echo "loop $i"
    sleep 6s
    # Get the leases, but tee it so it's easier to debug
    sudo virsh net-dhcp-leases default | tee dhcp-leases.txt

    # get our ipaddress
    ipaddy=$(grep demo dhcp-leases.txt | awk {'print $5'} | cut -d'/' -f 1-1)
    if [ -n "$ipaddy" ]; then
        # found it, we're done looking, print it for debug logs
        echo "ipaddy: $ipaddy"
        break
    fi
    # it's empty/not found, loop back and try again.
done

# Did we find it? If not die.
if [ -z "$ipaddy" ]; then
    echo "ipaddy zero length, exiting with error 1"
    exit 1
fi

#
# Great we have a host running, ssh into it. We specify -o so
# we don't get blocked on asking to add the servers key to
# our known_hosts.
#
# TODO: Inject a script in the virt-sysprep to run our tests
#  and invoke it here.
#
ssh -o StrictHostKeyChecking=no "root@$ipaddy" "/root/selinux/$TEST_RUNNER"

exit 0
