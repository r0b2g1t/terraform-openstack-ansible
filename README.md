# Terraform with OpenStack provider and Ansible Provisioner for Gitlab CI

The repository is forked from [Terraform-AWS-Ansible](https://github.com/rflume/Terraform-with-AWS-Provisioner-and-Ansible-Provider-for-Gitlab-CI) and is modified for use with OpenStack.

This Docker images is based on the official `hashicorp/terraform:latest` Terraform image and extends it with the [Terraform OpenStack Provider](https://github.com/terraform-providers/terraform-provider-openstack/releases) and [Ansible Provisioner by radekg](https://github.com/radekg/terraform-provisioner-ansible).

**It is intended for the use as base image for [GitLab CI pipelines](https://docs.gitlab.com/ce/ci/quick_start/README.html).** You can read my full article on how to use the image at Medium.com: [About Infrastructure on AWS, Automated with Terraform, Ansible and GitLab CI](https://medium.com/@robinflume/about-infrastructure-on-aws-automated-with-terraform-ansible-and-gitlab-ci-5888fe2e85fc).

The image is build as [Docker Multi-Stage Build](https://docs.docker.com/develop/develop-images/multistage-build/). This feature requires Docker Engine `v17.05` or higher.*

## Table of Contents

- [Terraform with OpenStack provider and Ansible Provisioner for Gitlab CI](#terraform-with-openstack-provider-and-ansible-provisioner-for-gitlab-ci)
  - [Table of Contents](#table-of-contents)
  - [Docker Tags](#docker-tags)
  - [Default Versions](#default-versions)
  - [Usage](#usage)
    - [Required Secrets](#required-secrets)
    - [Project Layout](#project-layout)
    - [Ansible Provisioning](#ansible-provisioning)
    - [Gitlab CI Pipeline Configuration](#gitlab-ci-pipeline-configuration)
  - [Software Licenses](#software-licenses)

## Docker Tags

The image is build with with the following tags:

* `latest`: Built from `master` branch. Contains the software versions stated below in the [Default Versions](#default-versions) section.
* `tf-x.yy.zz`: Built from any branch starting with `tf-[x].[yy].[zz][...]`. The Terraform version seems to me to be the most relevant software version, so any other version is ommitted.

If you need to pull images by the OpenStack Provider and Ansible Provisioner versions as well, please open an issue.

## Default Versions

The image needs to be build with Docker `build-args` which default to the following versions:

* Terraform: `0.12.9`
* Openstack Provisioner: `1.22.0`
* Ansible Provisioner: `2.3.0`

You can overwrite the versions of both the OpenStack Provisioner and the Ansible Provider within the `docker build` command:

```bash
docker build -t terraform-openstack-ansible --build-arg OPENSTACK_PROVIDER_VERSION=1.22.0 --build-arg ANSIBLE_PROVISIONER_VERSION=2.3.0 .
```

Available versions can be found here:

* [OpenStack Provider Versions](https://github.com/terraform-providers/terraform-provider-openstack/releases)
* [Ansible Provisioner Versions](https://github.com/radekg/terraform-provisioner-ansible/releases)

## Usage

The sections below will provide some example configuration how to use this Docker imnage.

### Required Secrets

The image can be used to automate your infrastructure creation with Gitlab CI pipelines. It is therefor required to provide both OpenStack credentials and login data of the user that the Ansible provisioner uses.

These must be provided as Gitlab CI secrets (project environment variables):

* `ANSIBLE_BECOME_PASS`: The password to become root on the hosts to be provisioned by ansible
* `ANSIBLE_VAULT_PASS`: The password the decrypt the [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html) (optional)
* `OS_AUTH_URL`: OpenStack authentication URL
* `OS_USERNAME`: OpenStack user name
* `OS_PASSWORD`: OpenStack password
* `OS_USER_DOMAIN_NAME`: OpenStack user's domain name
* `OS_TENANT_NAME`: OpenStack tenant name
* `OS_PROJECT_NAME`: OpenStack project name
* `ID_RSA_TERRAFORM`: An SSH private key to be used by Ansible

### Project Layout

The GitLab CI example pipeline configuration in section [Gitlab CI Pipeline Configuration](#gitlab-ci-pipeline-configuration) works for the following project layout:

```text
├── ansible-provisioning
│ └── roles
│   └── my-global-role
│     └── ...
│
├── global
│   ├── files
│   │ └── user_data.sh
│   └── {main|outputs|terraform|vars}.tf
│
├── environments
│ ├── dev
│ │ └── {main|outputs|terraform|vars}.tf
│ ├── stage
│ │ └── {main|outputs|terraform|vars}.tf
│ └── prod
│   └── {main|outputs|terraform|vars}.tf
│
├── modules
│ └── my_module
│   ├── ansible
|   │ └── playbook
|   │   └── …
│   └── {main|outputs|terraform|vars}.tf
│
├── .gitlab-ci.yml
└── README.md
```

### Ansible Provisioning

To provision a newly created resource *directly* within Terraform, the Ansible provisioner is included in the image. For more information on available parameters, checkout the [GitHub project by radekg](https://github.com/radekg/terraform-provisioner-ansible).

This is a brief example on how to use Ansible provisioning with this Docker image:

```t
# ec2 instance
resource "openstack_compute_instance_v2" "default" {
  name            = "default"
  image_id        = "ad091b52-742f-469e-8f3c-xxxxxxxxxxxx"
  flavor_id       = "3"
  key_pair        = "my_key_pair_name"
  security_groups = ["default"]

  metadata = {
    this = "that"
  }

  network {
    name = "my_network"
  }
}

# instance provisioner
resource "null_resource" "default_provisioner" {
  triggers {
    default_instance_id = "${openstack_compute_instance_v2.default.id}"
  }

  connection {
    host = "${openstack_compute_instance_v2.default.access_ip_v4}"
    type = "ssh"
    user = "terraform"   # as created in 'user_data'
    private_key = "${file("/root/.ssh/id_rsa_terraform")}"
  }
  # wait for the instance to become available
  provisioner "remote-exec" {
    inline = [
      "echo 'ready'"
    ]
  }
  # ansible provisioner
  provisioner "ansible" {
    plays {
      playbook = {
        file_path = "${path.module}/ansible/playbook/main.yml"
        roles_path = [
          "${path.module}/../../../../../ansible-provisioning/roles",
        ]
      }
    hosts = ["${openstack_compute_instance_v2.default.access_ip_v4}"]
    become = true
    become_method = "sudo"
    become_user = "root"

    extra_vars = {
      ...
      ansible_become_pass = "${file("/etc/ansible/become_pass")}"
    }

    vault_password_file = "/etc/ansible/vault_password_file"
  }
}
```

### Gitlab CI Pipeline Configuration

The actual pipeline can be configured as shown in this example:

```yml
image:
  name: r0b2g1t/terraform-openstack-ansible:latest

stages:
  # Dev environment stages
  - validate dev
  - plan dev
  - apply dev

variables:
  OS_AUTH_URL: $OS_AUTH_URL 
  OS_USERNAME: $OS_USERNAME
  OS_PASSWORD: $OS_PASSWORD
  OS_USER_DOMAIN_NAME: $OS_USER_DOMAIN_NAME
  OS_TENANT_NAME: $OS_TENANT_NAME
  OS_PROJECT_NAME: $OS_PROJECT_NAME

# Create files w/ required the secrets
before_script:
  - echo "$ID_RSA_TERRAFORM" > /root/.ssh/id_rsa_terraform
  - echo "$ANSIBLE_VAULT_PASS" > /etc/ansible/vault_password_file
  - echo "$ANSIBLE_BECOME_PASS" > /etc/ansible/become_pass

# Apply Terraform on DEV environment
validate:dev:
  stage: validate dev
  script:
    - cd environments/dev
    - terraform init
    - terraform validate
  only:
    changes:
      - environments/dev/**/*
      - modules/**/*

plan:dev:
  stage: plan dev
  script:
    - cd environments/dev
    - terraform init
    - terraform plan -out "planfile_dev"
  artifacts:
    paths:
      - environments/dev/planfile_dev
  only:
    changes:
      - environments/dev/**/*
      - modules/**/*

apply:dev:
  stage: apply dev
  script:
    - cd environments/dev
    - terraform init
    - terraform apply -input=false "planfile_dev"
  dependencies:
    - plan:dev
  allow_failure: false
  only:
    refs:
      - master
    changes:
      - environments/dev/**/*
      - modules/**/*
```

## Software Licenses

Note that the software included in the Docker image underlies licenses that may differ from the one for this Dockerfile / Docker image.<br/>
To view them, follow these links:

* [Terraform License](https://github.com/hashicorp/terraform/blob/master/LICENSE)
* [Terraform OpenStack Provider License](https://github.com/terraform-providers/terraform-provider-openstack/blob/master/LICENSE)
* [Terraform Provisioner Ansible License](https://github.com/radekg/terraform-provisioner-ansible/blob/master/LICENSE)