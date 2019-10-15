
variable "cluster-name" {}



variable "vpcnet_prefix" {
  default = "10.10"
}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {}

resource "aws_vpc" "eks-vpc" {
  cidr_block           = "${var.vpcnet_prefix}.0.0/16"
  enable_dns_hostnames = true

  tags = "${
    map(
      "Name", "${var.cluster-name}",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
  }"
}

resource "aws_subnet" "eks-public-a" {
  availability_zone = "${data.aws_availability_zones.available.names[0]}"
  cidr_block        = "${var.vpcnet_prefix}.1.0/24"
  vpc_id            = "${aws_vpc.eks-vpc.id}"

  tags = "${
    map(
      "Name", "${var.cluster-name}-public-a",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
    )
  }"
}

resource "aws_subnet" "eks-public-b" {
  availability_zone = "${data.aws_availability_zones.available.names[1]}"
  cidr_block        = "${var.vpcnet_prefix}.2.0/24"
  vpc_id            = "${aws_vpc.eks-vpc.id}"

  tags = "${
    map(
      "Name", "${var.cluster-name}-public-b",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
      "kubernetes.io/role/elb", "1"
    )
  }"
}

