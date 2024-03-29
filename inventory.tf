## CREATES ANSIBLE HOSTS FILE FROM TEMPLATE ##

data  "template_file" "aws" {
    template = "${file("./templates/hosts.tpl")}"
    vars = {
        cassandra_nodes = "${join("\n", aws_instance.cassandra.*.private_ip)}"
        number_of_seeds = "${var.number_of_cassandra_seeds}"
        vm_username = "ubuntu"
        cassandra_data_dir = "/opt/data"
        bastion_node = aws_instance.gateway.public_dns
        public_endpoint = aws_lb.tank_alb.dns_name
        cloud_provider = "aws"
        cloud_region = "${ var.region }"
        proxy_node = aws_instance.gateway.private_ip
        db_vol_device = "/dev/xvdf"
        mapbox_key = "${var.mapbox_key}"
    }
}

resource "local_file" "aws_file" {
  content  = "${data.template_file.aws.rendered}"
  filename = "./tmp/cloud-hosts"
}