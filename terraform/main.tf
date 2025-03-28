resource "aws_key_pair" "apg_key" {
  key_name   = "apg_public_key"
  public_key = file(var.public_key)
}

resource "aws_security_group_rule" "incomming_ssh" {
  count = var.enable_rds ? 1: 0
  type              = "ingress"
  from_port         = 0
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = var.inbound_ssh_connection_cidr
  security_group_id = element(aws_security_group.ec2_pgsql_sg.*.id,count.index)
}

resource "aws_security_group_rule" "outgoing_http" {
  count = var.enable_rds ? 1: 0
  type              = "egress"
  from_port         = 0
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = element(aws_security_group.ec2_pgsql_sg.*.id,count.index)
}

resource "aws_security_group_rule" "outgoing_https" {
  count = var.enable_rds ? 1: 0
  type              = "egress"
  from_port         = 0
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = element(aws_security_group.ec2_pgsql_sg.*.id,count.index)
}

resource "aws_security_group" "ec2_pgsql_sg" {
  count = var.enable_rds ? 1: 0
  name        = "apg-ec2-sg"
  description = "Security Group for EC2 pgsql"
  vpc_id = element(module.vpc.*.vpc_id,count.index)
}

resource "aws_instance" "ec2_psql" {
  count = var.enable_rds ? 1: 0
  ami           = "ami-0ebfd941bbafe70c6"
  instance_type = "t3.small"
  key_name = aws_key_pair.apg_key.key_name
  subnet_id = element(module.vpc.*.public_subnets[0],count.index)
  associate_public_ip_address = true
  tags = {
    Name = "Test EC2"
  }
  vpc_security_group_ids = [element(aws_security_group.ec2_pgsql_sg.*.id,count.index), element(module.vpc.*.default_security_group_id,count.index)]
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /opt/scripts",
      "sudo chmod 755 /opt/scripts"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user" # Replace with the appropriate user for your AMI
      private_key = file("${var.private_key}") # Replace with the path to your private key
      host        = self.public_ip
    }
  }

  provisioner "file" {
    source      = var.sql_file_path
    destination = "rds.sql"

    connection {
      type        = "ssh"
      user        = "ec2-user" # Replace with the appropriate user for your AMI
      private_key = file("${var.private_key}") # Replace with the path to your private key
      host        = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cp ~/rds.sql /opt/scripts",
      "sudo chmod 755 /opt/scripts/rds.sql",
      "sudo dnf install -y postgresql15",
      "export PGPASSWORD='${element(data.aws_secretsmanager_secret_version.password.*.secret_string,count.index)}'",
      "psql -h ${element(aws_db_instance.postgresql.*.address,count.index)} -U ${element(aws_db_instance.postgresql.*.username,count.index)} -d ${element(aws_db_instance.postgresql.*.db_name,count.index)} < /opt/scripts/rds.sql"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user" # Replace with the appropriate user for your AMI
      private_key = file("${var.private_key}") # Replace with the path to your private key
      host        = self.public_ip
    }
 }
depends_on = [ aws_db_instance.postgresql ]
}