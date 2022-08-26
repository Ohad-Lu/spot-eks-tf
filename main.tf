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

#region vpc
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "my-vpc"
  }

  enable_dns_support   = true
  enable_dns_hostnames = true
}

#region private-subnet
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
  subnet_id     = aws_subnet.public-subnet-01.id

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
#endregion

#region public-subnet
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
#endregion
#endregion

#region eks
resource "aws_eks_cluster" "eks-cluster" {
  name     = "ohad-eks-01"
  role_arn = aws_iam_role.cluster-role.arn
  version  = "1.23"

  vpc_config {
    subnet_ids              = [aws_subnet.private-subnet-01.id, aws_subnet.private-subnet-02.id]
    endpoint_public_access  = true
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
  type    = set(string)
  default = ["vpc-cni", "coredns", "kube-proxy"]
}


resource "aws_eks_addon" "example" {
  cluster_name = aws_eks_cluster.eks-cluster.name
  for_each     = var.addons_names_eks
  addon_name   = each.value
}

resource "aws_iam_role" "node-role" {
  name = "eks-node-group-role"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node-role.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node-role.name
}

resource "aws_iam_role_policy_attachment" "example-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node-role.name
}

resource "aws_eks_node_group" "node-group-01-spot" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "node-group-01-spot"
  node_role_arn   = aws_iam_role.node-role.arn
  subnet_ids      = [aws_subnet.private-subnet-01.id, aws_subnet.private-subnet-02.id]
  capacity_type   = "SPOT"
  instance_types  = ["t3a.small", "t3.small"]
  disk_size       = 10

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 0
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.example-AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_eks_node_group" "node-group-02-spot" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "node-group-02-spot"
  node_role_arn   = aws_iam_role.node-role.arn
  subnet_ids      = [aws_subnet.private-subnet-01.id, aws_subnet.private-subnet-02.id, aws_subnet.public-subnet-01.id, aws_subnet.public-subnet-02.id]
  capacity_type   = "SPOT"
  instance_types  = ["t3a.micro", "t3.micro"]
  disk_size       = 10

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 0
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.example-AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "aws_eks_node_group" "node-group-ondeman" {
  cluster_name    = aws_eks_cluster.eks-cluster.name
  node_group_name = "node-group-ondemand-03"
  node_role_arn   = aws_iam_role.node-role.arn
  subnet_ids      = [aws_subnet.private-subnet-01.id, aws_subnet.private-subnet-02.id]
  capacity_type   = "SPOT"
  instance_types  = ["t3a.small", "t3.small"]
  disk_size       = 10

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 0
  }

  update_config {
    max_unavailable = 1
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.example-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.example-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.example-AmazonEC2ContainerRegistryReadOnly,
  ]
}

#endregion 


# TODO: 
#   - nodes
#   - modulate - vpc and eks
