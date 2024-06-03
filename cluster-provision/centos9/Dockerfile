FROM quay.io/fedora/fedora:39 AS customizevmimage

ARG BUILDARCH

ARG centos_version

RUN dnf -y install libguestfs libguestfs-tools-c && dnf clean all

WORKDIR /

ENV LIBGUESTFS_BACKEND=direct

ENV CENTOS_URL_amd64 https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-Vagrant-9-$centos_version.x86_64.vagrant-libvirt.box

ENV CENTOS_URL_s390x https://cloud.centos.org/centos/9-stream/s390x/images/CentOS-Stream-GenericCloud-9-$centos_version.s390x.qcow2

COPY scripts/download_box.sh /

RUN echo "Centos9 version $centos_version"


RUN CENTOS_URL=$(eval echo \$CENTOS_URL_${BUILDARCH}) && \
   /download_box.sh $CENTOS_URL

RUN if test "${BUILDARCH}" != "s390x"; then \
       curl -L -o /initramfs-amd64.img http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/images/pxeboot/initrd.img && \
       curl -L -o /vmlinuz-amd64  http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/images/pxeboot/vmlinuz; \
    else \
       virt-sysprep -v -x -a box.qcow2 --no-selinux-relabel --run-command "useradd -m cloud-user" && \
       virt-sysprep -a box.qcow2 --no-selinux-relabel --append '/etc/cloud/cloud.cfg:runcmd:' && \
       virt-sysprep -a box.qcow2 --no-selinux-relabel --append '/etc/cloud/cloud.cfg: - hostnamectl set-hostname ""' && \
       virt-sysprep -a box.qcow2 --no-selinux-relabel --root-password password:Zxc@123 --ssh-inject cloud-user:string:"ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key" && \
       guestfish --ro --add box.qcow2 --mount /dev/sda1:/ ls /boot/ | grep -E '^vmlinuz-|^initramfs-' | xargs -I {} guestfish --ro --add box.qcow2 -i copy-out /boot/{} / && \
       guestfish --rw --add box.qcow2 --mount /dev/sda1:/ selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts / ; \
    fi


FROM quay.io/fedora/fedora:39

ARG BUILDARCH

RUN dnf -y install jq iptables iproute dnsmasq qemu socat openssh-clients screen bind-utils tcpdump iputils && dnf clean all

WORKDIR /

COPY vagrant.key /vagrant.key

RUN chmod 700 vagrant.key

ENV DOCKERIZE_VERSION v0.6.1

ENV DOCKERIZE_URL_s390x https://github.com/ibm-jitendra/kubevirt_pkgs/raw/main/dockerize-linux-s390x.tar.gz

ENV DOCKERIZE_URL_amd64 https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz


RUN DOCKERIZE_URL=$(eval echo \$DOCKERIZE_URL_${BUILDARCH}) && \
    echo "Downloading from $DOCKERIZE_URL" && \
    curl -L -o dockerize-linux-$BUILDARCH.tar.gz $DOCKERIZE_URL && \
    tar -xzvf dockerize-linux-$BUILDARCH.tar.gz && \
    chmod u+x dockerize && \
    mv dockerize /usr/local/bin/


COPY  --from=customizevmimage /box.qcow2 box.qcow2
COPY --from=customizevmimage /vmlinuz-* /vmlinuz
COPY --from=customizevmimage /initramfs-* /initrd.img

COPY scripts/* /