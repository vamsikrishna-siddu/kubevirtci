ARG ARCH

FROM fedora:latest as base

ARG centos_version

RUN dnf -y install jq iptables iproute dnsmasq qemu openssh-clients screen bind-utils tcpdump iputils && dnf clean all

COPY scripts/* /

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

WORKDIR /

COPY s390x_user.key /s390x_user.key

RUN chmod 700 s390x_user.key

RUN curl -LO https://github.com/ibm-jitendra/kubevirt_pkgs/raw/main/dockerize-linux-s390x.tar.gz \
  && tar -xvf dockerize-linux-s390x.tar.gz \
  && rm dockerize-linux-s390x.tar.gz \
  && chmod u+x dockerize \
  && mv dockerize /usr/local/bin/

COPY  CentOS-Stream-GenericCloud-9-latest.s390x.qcow2 box.qcow2

FROM fedora-${ARCH} AS final
