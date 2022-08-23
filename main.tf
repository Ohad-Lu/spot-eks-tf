terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "my-vpc"
  }
}

resource "aws_subnet" "private-subnet-01" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"
  tags = {
    Name = "private-subnet-us-east-2a"
  }
}

resource "aws_subnet" "private-subnet-02" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-2b"
  tags = {
    Name = "private-subnet-us-east-2b"
  }
}

resource "aws_eip" "eip" {
}

resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.private-subnet-01.id

  tags = {
    Name = "gw NAT"
  }
}

resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private-rt-01"
  }
}

resource "aws_route" "private-rt-public-route" {
  route_table_id         = aws_route_table.private-rt.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.example.id
}

resource "aws_route_table_association" "private-subnets-rt-association-01" {
  subnet_id      = aws_subnet.private-subnet-01.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_route_table_association" "private-subnets-rt-association-02" {
  subnet_id      = aws_subnet.private-subnet-02.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_subnet" "public-subnet-01" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "us-east-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-us-east-2a"
  }
}

resource "aws_subnet" "public-subnet-02" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-us-east-2b"
  }
}

resource "aws_internet_gateway" "ig" {
  tags = {
    Name = "main"
  }
}

resource "aws_internet_gateway_attachment" "ig-to-vpc" {
  internet_gateway_id = aws_internet_gateway.ig.id
  vpc_id              = aws_vpc.main.id
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public-rt-01"
  }
}

resource "aws_route" "public-rt-public-route" {
  route_table_id         = aws_route_table.public-rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.ig.id
}

resource "aws_route_table_association" "public-subnets-rt-association-01" {
  subnet_id      = aws_subnet.public-subnet-01.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "public-subnets-rt-association-02" {
  subnet_id      = aws_subnet.public-subnet-02.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_eks_cluster" "eks-cluster" {
  name     = "ohad-eks-01"
  role_arn = aws_iam_role.cluster-role.arn
  version = "1.23"

  vpc_config {
    subnet_ids = [aws_subnet.private-subnet-01.id, aws_subnet.private-subnet-02.id]
    endpoint_public_access = true
    endpoint_private_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster-role-AmazonEKSClusterPolicy-attach,
    aws_vpc.main
  ]
}

resource "aws_iam_role" "cluster-role" {
  name = "eks-cluster-role"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "cluster-role-AmazonEKSClusterPolicy-attach" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster-role.name
}


variable "addons_names_eks" {
  type = set(string)
  default = ["vpc-cni", "coredns", "kube-proxy"]
}


resource "aws_eks_addon" "example" {
  cluster_name = aws_eks_cluster.eks-cluster.name
  for_each = var.addons_names_eks
  addon_name   = each.value
}





# TODO: 
#   - addons: Amazon VPC CNI, CoreDNS, kube-proxy
#   - nodes
#   - modulate - vpc and eks