## MAIN FILE CONTAINING PROVIDER AND INSTANCE RESOURCES ##

provider "aws" {
  profile = "${var.aws_profile}"
  region = "${var.region}"
}

resource "aws_instance" "gateway" {
  ami           = "${var.ami_id}"
  instance_type = "${var.gateway_instance_type}"
  key_name = "${var.keypair}"
  tags = {
    Name = "tank-gateway"
  }
  
  root_block_device {
    volume_type = "standard"
    volume_size = "${var.bastion_disk_size}"
    delete_on_termination = true
  }

  ephemeral_block_device {
    no_device = true
    device_name = "/dev/sda"
  }

  vpc_security_group_ids = [ "${aws_security_group.ssh.id}" ]
  associate_public_ip_address = true
  subnet_id = "${aws_subnet.tank_public_subnet[0].id}"
}

resource "aws_instance" "cassandra" {
  ami           = "${var.ami_id}"
  instance_type = "${var.cassandra_instance_type}"
  count = "${var.cassandra_node_count}"
  key_name = "${var.keypair}"
  tags = {
    Name = "${var.ec2_cassandra_instance_prefix}-${count.index}"
  }
  # user_data = "${file("files/attach_ebs.sh")}"
  
  vpc_security_group_ids = [ "${aws_security_group.ssh.id}" ]
  associate_public_ip_address = false
  subnet_id = "${aws_subnet.tank_private_subnet[ count.index % 2 == 0 ? 0 : 1].id}"
}
