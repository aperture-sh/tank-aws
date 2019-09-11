resource "aws_iam_role" "tank-cluster" {
  name = "terraform-eks-tank-cluster"

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

resource "aws_iam_role_policy_attachment" "tank-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.tank-cluster.name}"
}

resource "aws_iam_role_policy_attachment" "tank-cluster-AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = "${aws_iam_role.tank-cluster.name}"
}

resource "aws_security_group" "tank-cluster" {
  name        = "terraform-eks-tank-cluster"
  description = "Cluster communication with worker nodes"
  vpc_id      = "${aws_vpc.tank_vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "terraform-eks-tank"
  }
}

# OPTIONAL: Allow inbound traffic from your local workstation external IP
#           to the Kubernetes. You will need to replace A.B.C.D below with
#           your real IP. Services like icanhazip.com can help you find this.
resource "aws_security_group_rule" "tank-cluster-ingress-workstation-https" {
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "Allow workstation to communicate with the cluster API Server"
  from_port         = 0
  protocol          = "tcp"
  security_group_id = "${aws_security_group.tank-cluster.id}"
  to_port           = 0
  type              = "ingress"
}

resource "aws_eks_cluster" "tank" {
  name            = "${var.cluster_name}"
  role_arn        = "${aws_iam_role.tank-cluster.arn}"

  vpc_config {
    security_group_ids = ["${aws_security_group.tank-cluster.id}"]
    subnet_ids         = "${aws_subnet.tank_private_subnet.*.id}"
  }

  depends_on = [
    "aws_iam_role_policy_attachment.tank-cluster-AmazonEKSClusterPolicy",
    "aws_iam_role_policy_attachment.tank-cluster-AmazonEKSServicePolicy",
  ]
}
