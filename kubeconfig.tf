data  "template_file" "kubeconfig" {
    template = "${file("./templates/kubeconfig.tpl")}"
    vars = {
      cluster_endpoint = "${aws_eks_cluster.tank.endpoint}"
      ca = "${aws_eks_cluster.tank.certificate_authority.0.data}"
      aws_profile = "${var.aws_profile}"
    }
}

resource "local_file" "kubeconfig" {
  content  = "${data.template_file.kubeconfig.rendered}"
  filename = "./tmp/kubeconfig"
}

data  "template_file" "config_map_auth" {
    template = "${file("./templates/config_map_auth.tpl")}"
    vars = {
      iam_role_arn = "${aws_iam_role.tank-node.arn}"
    }
}

resource "local_file" "config_map_auth" {
  content  = "${data.template_file.config_map_auth.rendered}"
  filename = "./tmp/config_map_auth.yml"
}
