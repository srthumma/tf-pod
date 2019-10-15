
variable "cluster-name" {}

variable "corporate_cidr_list" {
  type = "list"

  default = []
}

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

resource "aws_subnet" "eks-subnet-private" {
  cidr_block        = "${var.vpcnet_prefix}.5.0/24"
  vpc_id            = "${aws_vpc.eks-vpc.id}"
  availability_zone = "${data.aws_availability_zones.available.names[0]}"

  tags = "${
    map(
      "Name", "${var.cluster-name}-private",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
      "kubernetes.io/role/internal-elb", "1"
    )
  }"
}

resource "aws_subnet" "eks-subnet-private-b" {
  cidr_block        = "${var.vpcnet_prefix}.6.0/24"
  vpc_id            = "${aws_vpc.eks-vpc.id}"
  availability_zone = "${data.aws_availability_zones.available.names[1]}"

  tags = "${
    map(
      "Name", "${var.cluster-name}-private-b",
      "kubernetes.io/cluster/${var.cluster-name}", "shared",
      "kubernetes.io/role/internal-elb", "1"
    )
  }"
}

resource "aws_internet_gateway" "eks-igw" {
  vpc_id = "${aws_vpc.eks-vpc.id}"

  tags = {
    Name = "${var.cluster-name}"
  }


}

resource "aws_eip" "eks-nat-eip" {
  vpc = true

  tags = {
    Name = "${var.cluster-name}-nat-eip"
  }
  depends_on = ["aws_internet_gateway.eks-igw"]
}

resource "aws_nat_gateway" "eks-natgw" {
  allocation_id = "${aws_eip.eks-nat-eip.id}"
  subnet_id     = "${aws_subnet.eks-public-a.id}"

  tags = {
    Name = "${var.cluster-name}-nat"
  }
  depends_on = ["aws_internet_gateway.eks-igw"]
}



resource "aws_route_table" "eks-rt" {
  vpc_id = "${aws_vpc.eks-vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.eks-igw.id}"
  }

  tags = {
    Name = "${var.cluster-name}-rt-public"
  }
}

resource "aws_route_table" "eks-rt-private" {
  vpc_id = "${aws_vpc.eks-vpc.id}"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.eks-natgw.id}"
  }

  tags = {
    Name = "${var.cluster-name}-rt-private"
  }
}

resource "aws_route_table_association" "eks-rta-b" {
  subnet_id      = "${aws_subnet.eks-public-a.id}"
  route_table_id = "${aws_route_table.eks-rt.id}"
}

resource "aws_route_table_association" "eks-rta-a" {
  subnet_id      = "${aws_subnet.eks-public-b.id}"
  route_table_id = "${aws_route_table.eks-rt.id}"
}

resource "aws_route_table_association" "eks-rta-private" {
  subnet_id      = "${aws_subnet.eks-subnet-private.id}"
  route_table_id = "${aws_route_table.eks-rt-private.id}"
}

resource "aws_route_table_association" "eks-rta-private-b" {
  subnet_id      = "${aws_subnet.eks-subnet-private-b.id}"
  route_table_id = "${aws_route_table.eks-rt-private.id}"
}

resource "aws_security_group" "eks-cluster-master" {
  name        = "${var.cluster-name}-master"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "self"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${aws_vpc.eks-vpc.cidr_block}"]
    description = "ingress from cluster vpc"
  }

 tags = {
    Name = "${var.cluster-name}-master"
  }
}

resource "aws_security_group" "eks-transit" {
  name        = "${var.cluster-name}-transit"
  description = "Transit SG"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "self"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = ["${aws_security_group.eks-corporate.id}"]
  }

 tags = {
    Name = "${var.cluster-name}-transit"
  }
}

resource "aws_security_group" "eks-node" {
  name        = "${var.cluster-name}-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "self"
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = ["${aws_security_group.eks-cluster-master.id}"]
  }

  ingress {
    from_port   = 30000
    to_port     = 35000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = ["${aws_security_group.eks-cluster-master.id}"]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${aws_security_group.gateway.id}"]
  }

  tags = "${
    map(
    "Name", "${var.cluster-name}-nodes",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}

resource "aws_security_group" "eks-node-private" {
  name        = "${var.cluster-name}-node-private"
  description = "Security group for all private nodes in the cluster"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "self"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = ["${aws_security_group.eks-corporate.id}"]
    description     = "eks-corporate"
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = ["${aws_security_group.eks-cluster-master.id}"]
    description     = "eks-cluster-master"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = ["${aws_security_group.eks-cluster-master.id}"]
    description     = "eks-cluster-master"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${aws_security_group.gateway.id}"]
    description     = "gateway"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${aws_vpc.eks-vpc.cidr_block}"]
    description = "allow from cluster vpc"
  }

  tags = "${
    map(
    "Name", "${var.cluster-name}-nodes-private",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}

resource "aws_security_group" "eks-node-secure" {
  name        = "${var.cluster-name}-node-secure"
  description = "Security group for all secure nodes in the cluster"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "self"
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = ["${aws_security_group.eks-node-private.id}"]
    description     = "eks-node-private"
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = ["${aws_security_group.eks-cluster-master.id}"]
    description     = "eks-cluster-master "
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = ["${aws_security_group.eks-cluster-master.id}"]
    description     = "eks-cluster-master"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = ["${aws_security_group.gateway.id}"]
    description     = "gateway"
  }

  tags = "${
    map(
    "Name", "${var.cluster-name}-nodes-secure",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}

resource "aws_security_group" "eks-public-web" {
  name        = "${var.cluster-name}-public-web"
  description = "Security group for public web ports"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "self"
  }

 

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
    "Name", "${var.cluster-name}-public-web",
     "kubernetes.io/cluster/${var.cluster-name}", "owned",
    )
  }"
}
resource "aws_security_group" "eks-corporate" {
  name        = "${var.cluster-name}-corporate"
  description = "Security group for all coporate communications"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "self"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${aws_vpc.eks-vpc.cidr_block}"]
    description = "cluster VPC"
  }

  ingress {
    from_port       = 1025
    to_port         = 65535
    protocol        = "tcp"
    security_groups = ["${aws_security_group.eks-cluster-master.id}"]
    description     = "eks-cluster-master"
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = ["${aws_security_group.eks-cluster-master.id}"]
    description     = "eks-cluster-master"
  }

  tags = "${
    map(
    "Name", "${var.cluster-name}-corp"
    )
  }"
}

resource "aws_security_group" "gateway" {
  name        = "${var.cluster-name}-gateway"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.eks-vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "public ssh"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${aws_vpc.eks-vpc.cidr_block}"]
    description = "Cluster VPC"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${aws_vpc.eks-vpc.cidr_block}"]
    description = "Cluster VPC"
  }

 tags = {
    Name = "${var.cluster-name}-gateway"
  }
}

resource "aws_security_group_rule" "eks-node-ingress-corporate" {
  count             = 1
  cidr_blocks       = ["${var.corporate_cidr_list[count.index]}"]
  description       = "Allow corporate networks to communicate with nodes"
  from_port         = 0
  protocol          = "tcp"
  security_group_id = "${aws_security_group.eks-corporate.id}"
  to_port           = 65535
  type              = "ingress"
}

resource "aws_security_group_rule" "master-cluster-ingress-trusted" {
  count             = 1
  cidr_blocks       = ["${var.corporate_cidr_list[count.index]}"]
  description       = "Allow corporate networks to communicate with nodes"
  from_port         = 0
  protocol          = "tcp"
  security_group_id = "${aws_security_group.eks-cluster-master.id}"
  to_port           = 65535
  type              = "ingress"
}
