provider "aws" {
    region = "us-west-2"
}

// create VPC setup
// need 1 VPC, 3 subnets, a internet gateway, nessersary routes

resource "aws_vpc" "eks_vpc" {
    cidr_block = "10.69.0.0/16"
    instance_tenancy = "default"

}

resource "aws_subnet" "a" {
    map_public_ip_on_launch = true
    vpc_id = aws_vpc.eks_vpc.id
    cidr_block = "10.69.0.0/24"
    availability_zone_id = "usw2-az1"
    tags = {
        "kubernetes.io/cluster/test_cluster" = "shared"
    }
}

resource "aws_subnet" "b" {
    vpc_id = aws_vpc.eks_vpc.id
    map_public_ip_on_launch = true
    cidr_block = "10.69.1.0/24"
    availability_zone_id = "usw2-az2"
    tags = {
        "kubernetes.io/cluster/test_cluster" = "shared"
    }
}

resource "aws_subnet" "c" {
    vpc_id = aws_vpc.eks_vpc.id
    map_public_ip_on_launch = true
    cidr_block = "10.69.2.0/24"
    availability_zone_id = "usw2-az3"
    tags = {
        "kubernetes.io/cluster/test_cluster" = "shared"
    }
}

resource "aws_internet_gateway" "igw_eks" {
    vpc_id = aws_vpc.eks_vpc.id
}

resource "aws_route_table" "eks_table" {
    vpc_id = aws_vpc.eks_vpc.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw_eks.id
    }
}

resource "aws_route_table_association" "asso_eks_a" {
    subnet_id = aws_subnet.a.id
    route_table_id = aws_route_table.eks_table.id
}

resource "aws_route_table_association" "asso_eks_b" {
    subnet_id = aws_subnet.b.id
    route_table_id = aws_route_table.eks_table.id
}

resource "aws_route_table_association" "asso_eks_c" {
    subnet_id = aws_subnet.c.id
    route_table_id = aws_route_table.eks_table.id
}

//implement security group for EKS API plane

resource "aws_security_group" "eks_api_plane_sg" {
    name = "eks_api_plane_sg"
    description = "the SG for EKS API control plane"
    vpc_id = aws_vpc.eks_vpc.id
    ingress { 
        description = "HTTPs Traffic"
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [aws_vpc.eks_vpc.cidr_block]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

// create the nessersary IAM roles

resource "aws_iam_role" "eks_control_plane_iam" {
    name = "eks_control_plane_role"
    assume_role_policy = <<EOF
{"Version": "2012-10-17","Statement": [{"Effect": "Allow","Principal": {"Service": "eks.amazonaws.com"},"Action": "sts:AssumeRole"}]}
    EOF
}

resource "aws_iam_role_policy_attachment" "eks_control_plane_iam_attachment" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    role = aws_iam_role.eks_control_plane_iam.id
}

resource "aws_iam_role" "eks_node_group_iam" {
    name = "eks_iam_nodegroup_role"
    assume_role_policy = <<EOF
{"Version": "2012-10-17","Statement": [{"Effect": "Allow","Principal": {"Service": "ec2.amazonaws.com"},"Action": "sts:AssumeRole"}]}
    EOF
}

resource "aws_iam_role_policy_attachment" "eks_nodegroup_iam_attachment" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
    role = aws_iam_role.eks_node_group_iam.name
}

resource "aws_iam_role_policy_attachment" "eks_nodegroup_iam_attachment2" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
    role = aws_iam_role.eks_node_group_iam.name
}

resource "aws_iam_role_policy_attachment" "eks_nodegroup_iam_attachment3" {
    policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    role = aws_iam_role.eks_node_group_iam.name
}
//finally, provision the actual cluster

resource "aws_eks_cluster" "test_cluster" {
    name = "test_cluster"
    role_arn = aws_iam_role.eks_control_plane_iam.arn
    vpc_config {
        subnet_ids = [ aws_subnet.a.id, aws_subnet.b.id, aws_subnet.c.id ]
    }
}

//create the node group

resource "aws_eks_node_group" "test_cluster_node_group" {
    cluster_name = aws_eks_cluster.test_cluster.name
    node_group_name = "group_1"
    node_role_arn = aws_iam_role.eks_node_group_iam.arn
    subnet_ids = [aws_subnet.a.id, aws_subnet.b.id, aws_subnet.c.id]
    scaling_config {
        desired_size = 2
        max_size = 69
        min_size = 1
    }
    instance_types = [ "t3.large" ]
}