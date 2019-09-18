FROM ubuntu:bionic as builder

ARG OPENSTACK_PROVIDER_VERSION=1.22.0

ENV HOME /root
ENV GOPATH $HOME/go
ENV GOBIN $GOPATH/bin

RUN apt-get update &&\
    apt-get install -yqq software-properties-common \
                         git \
                         wget \
                         unzip \
                         build-essential &&\
    add-apt-repository ppa:longsleep/golang-backports &&\
    apt-get update &&\
    apt-get install -y golang-go &&\
    mkdir -p $GOPATH/src/github.com/terraform-providers &&\
    wget -O $HOME/terraform-provider-openstack.zip https://github.com/terraform-providers/terraform-provider-openstack/archive/v$OPENSTACK_PROVIDER_VERSION.zip &&\
    cd $GOPATH/src/github.com/terraform-providers/ &&\
    unzip $HOME/terraform-provider-openstack.zip -d . &&\
    mv terraform-provider-openstack-$OPENSTACK_PROVIDER_VERSION \
       terraform-provider-openstack

WORKDIR $GOPATH/src/github.com/terraform-providers/terraform-provider-openstack

RUN make build

FROM hashicorp/terraform:latest

ARG OPENSTACK_PROVIDER_VERSION=1.22.0
ARG ANSIBLE_PROVISIONER_VERSION=2.3.0

ENV GOBIN /root/go/bin
ENV PATH $GOBIN:$PATH

RUN mkdir -p /root/.terraform.d/plugins

COPY --from=builder /root/go/bin/terraform-provider-openstack $GOBIN/terraform-provider-openstack_v$OPENSTACK_PROVIDER_VERSION

RUN wget -O /root/.terraform.d/plugins/terraform-provisioner-ansible_v$ANSIBLE_PROVISIONER_VERSION https://github.com/radekg/terraform-provisioner-ansible/releases/download/v${ANSIBLE_PROVISIONER_VERSION}/terraform-provisioner-ansible-linux-amd64_v${ANSIBLE_PROVISIONER_VERSION} &&\
    chmod +x $GOBIN/terraform-provider-openstack_v$OPENSTACK_PROVIDER_VERSION &&\
    chmod +x /root/.terraform.d/plugins/terraform-provisioner-ansible_v$ANSIBLE_PROVISIONER_VERSION &&\
    apk add --update --no-cache \
        openssh \
        gettext \
        ansible \
        py-pip \
        py-netaddr &&\
    pip install --upgrade pip\
        botocore \
        boto \
        boto3 &&\
    rm -rf /var/cache/apk/* &&\
    mkdir -p /root/.ssh &&\
    chmod 0700 /root/.ssh &&\
    touch /root/.ssh/id_rsa_terraform &&\
    chmod 0600 /root/.ssh/id_rsa_terraform &&\
    echo "    IdentityFile /root/.ssh/id_rsa_terraform" >> /etc/ssh/ssh_config &&\
    mkdir -p /etc/ansible &&\
    chmod 0700 /etc/ansible

ENTRYPOINT ["/bin/sh", "-c"]