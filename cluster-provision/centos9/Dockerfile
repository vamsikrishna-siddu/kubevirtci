ARG ARCH

FROM fedora:latest as base

ARG centos_version

RUN dnf -y install jq iptables iproute dnsmasq qemu openssh-clients screen bind-utils tcpdump iputils && dnf clean all

FROM base AS fedora-x86

WORKDIR /

COPY vagrant.key /vagrant.key

RUN chmod 700 vagrant.key

ENV DOCKERIZE_VERSION v0.6.1

RUN curl -LO https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
  && tar -xzvf dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
  && rm dockerize-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
  && chmod u+x dockerize \
  && mv dockerize /usr/local/bin/

COPY scripts/download_box.sh /

RUN echo "Centos9 version $centos_version"

ENV CENTOS_URL https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-Vagrant-9-$centos_version.x86_64.vagrant-libvirt.box

RUN /download_box.sh ${CENTOS_URL}

RUN curl -L -o /initrd.img http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/images/pxeboot/initrd.img
RUN curl -L -o /vmlinuz http://mirror.stream.centos.org/9-stream/BaseOS/x86_64/os/images/pxeboot/vmlinuz


FROM base as fedora-s390x

RUN dnf -y install libguestfs libguestfs-tools-c && dnf clean all

WORKDIR /

COPY s390x_user.key /s390x_user.key

RUN chmod 700 s390x_user.key

RUN curl -LO https://github.com/ibm-jitendra/kubevirt_pkgs/raw/main/dockerize-linux-s390x.tar.gz \
  && tar -xvf dockerize-linux-s390x.tar.gz \
  && rm dockerize-linux-s390x.tar.gz \
  && chmod u+x dockerize \
  && mv dockerize /usr/local/bin/

RUN echo "Centos9 version $centos_version"

ENV CENTOS_URL https://cloud.centos.org/centos/9-stream/s390x/images/CentOS-Stream-GenericCloud-9-$centos_version.s390x.qcow2

RUN /download_box.sh ${CENTOS_URL}

ENV LIBGUESTFS_BACKEND=direct

RUN virt-sysprep -v -x -a box.qcow2 --no-selinux-relabel --run-command "useradd -m cloud-user" || cat /var/log/virt-customize.log

RUN virt-sysprep -a box.qcow2 --no-selinux-relabel --root-password password:Zxc@123 --ssh-inject cloud-user:string:"ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCR8M7jpRiuo1DdLyzDSndeGgsjDlrZBn6R8OLTb7P23wP9EjGhD+Tztf0hpgjsKtpGoDOGudQ+is5vob2m9jWmRibTJ4cv7/hp9lHboZGuCba40JAMUJfcO9hOzviVInBmxAcC7KUZ0AtYNs7ClYs0txd+Ibhtx1zh0GKrooyfXSfL5+CIZ78gJVED9D0ZGy9hF+HMyVM/bcmq2LPkpsk+B4zxfHuDvqzzG2wk93pnNgXuihxKqNo64gZ94/FwpnNkQq2sa9Alrudfs+l/DWPjhJle17o6Xg1Ai0N/32BGKtqpxbfGwcRcnLBGG+f1LGiau31Y9vpP+A+0FH810b4gY0BEtCd7JqqYjXqVdzTl2NzKnMDmO/NYEgi7Y75wZsKtF1T30GKYrnfevKpg2qLW2exEJXwkv6/enx5t7Mzvg8hZ+Am4uPajLAA6PVtFf2d8TE3TpIPhBakhbx3xrWiHxnmDYCEw/m1Q1k7H6cEGpk5jqdRaOBLAY74H4XU+pMIN6uoZSTN3bwYyTwbsOZmY+qWtZwhi5uQyFiNJfzbotIYZ4foajgHAf1I9LqLCzL7kmGOTv2dqab+NdCACJiNxECOz50gNjhkZ+03k1F5uLdgP4fagpOy+knJ1w/Vpn47RVUefknazZOXoOlI3dRlq844dpya1sYeO80ieEiNQHw== centos@localhost"

RUN guestfish --rw --add box.qcow2 --mount /dev/sda1:/ selinux-relabel /etc/selinux/targeted/contexts/files/file_contexts /

FROM fedora-${ARCH} AS final

COPY scripts/* /
