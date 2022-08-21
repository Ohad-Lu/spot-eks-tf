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

resource "aws_subnet" "private-subnet" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-2a"
  tags = {
    Name = "private-subnet"
  }
}

resource "aws_eip" "eip" {
}

resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.private-subnet.id

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

resource "aws_route_table_association" "private-subnets-rt-association" {
  subnet_id      = aws_subnet.private-subnet.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_subnet" "public-subnet" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-2b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
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

resource "aws_route_table_association" "public-subnets-rt-association" {
  subnet_id      = aws_subnet.public-subnet.id
  route_table_id = aws_route_table.public-rt.id
}


