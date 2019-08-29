resource "aws_iam_role" "tank-node" {
  name = "terraform-eks-tank-node"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "tank-node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.tank-node.name}"
}

resource "aws_iam_role_policy_attachment" "tank-node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.tank-node.name}"
}

resource "aws_iam_role_policy_attachment" "tank-node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.tank-node.name}"
}

resource "aws_iam_instance_profile" "tank-node" {
  name = "terraform-eks-tank"
  role = "${aws_iam_role.tank-node.name}"
}

resource "aws_security_group" "tank-node" {
  name        = "terraform-eks-tank-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = "${aws_vpc.tank_vpc.id}"

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
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    map(
     "Name", "terraform-eks-tank-node",
     "kubernetes.io/cluster/${var.cluster_name}", "owned",
    )
  }"
}

resource "aws_security_group_rule" "tank-node-ingress-self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.tank-node.id}"
  source_security_group_id = "${aws_security_group.tank-node.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "tank-node-ingress-cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.tank-node.id}"
  source_security_group_id = "${aws_security_group.tank-cluster.id}"
  to_port                  = 65535
  type                     = "ingress"
}

resource "aws_security_group_rule" "tank-cluster-ingress-node-https" {
  description              = "Allow pods to communicate with the cluster API Server"
  from_port                = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.tank-cluster.id}"
  source_security_group_id = "${aws_security_group.tank-node.id}"
  to_port                  = 443
  type                     = "ingress"
}

data "aws_ami" "eks-worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.tank.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

# EKS currently documents this required userdata for EKS worker nodes to
# properly configure Kubernetes applications on the EC2 instance.
# We implement a Terraform local here to simplify Base64 encoding this
# information into the AutoScaling Launch Configuration.
# More information: https://docs.aws.amazon.com/eks/latest/userguide/launch-workers.html
locals {
  tank-node-userdata = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${aws_eks_cluster.tank.endpoint}' --b64-cluster-ca '${aws_eks_cluster.tank.certificate_authority.0.data}' '${var.cluster_name}'
USERDATA
}

resource "aws_launch_configuration" "tank" {
  associate_public_ip_address = true
  iam_instance_profile        = "${aws_iam_instance_profile.tank-node.name}"
  image_id                    = "${data.aws_ami.eks-worker.id}"
  instance_type               = "t2.large"
  name_prefix                 = "tank-eks"
  security_groups             = ["${aws_security_group.tank-node.id}"]
  user_data_base64            = "${base64encode(local.tank-node-userdata)}"
  key_name = "${var.keypair}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "tank" {
  desired_capacity     = 3
  launch_configuration = "${aws_launch_configuration.tank.id}"
  max_size             = 3
  min_size             = 1
  name                 = "terraform-eks-tank"
  vpc_zone_identifier  = "${aws_subnet.tank_private_subnet.*.id}"

  tag {
    key                 = "Name"
    value               = "terraform-eks-tank"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  depends_on = [
    "aws_eks_cluster.tank",
    "kubernetes_config_map.auth"
  ]
}

