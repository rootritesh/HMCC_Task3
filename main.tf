provider "aws" {
  region = "ap-south-1" 
}


resource "aws_vpc" "main" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"

  tags = {
    Name = "VPC_MY"
  }
}

resource "aws_subnet" "wp_public" {
  depends_on=[
      aws_vpc.main
  ]
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"

  tags = {
    Name = "wordpress_pub"
  }
}

resource "aws_subnet" "mq_private" {
  depends_on=[
      aws_vpc.main
  ]
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "ap-south-1a"

  tags = {
    Name = "mysql_pub"
  }
}


resource "aws_internet_gateway" "IG" {
    depends_on=[
        aws_vpc.main
    ]
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "IG_MY"
  }
}


resource "aws_route_table" "myroute" {
    depends_on=[aws_internet_gateway.IG]
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IG.id
  }

  tags = {
    Name = "route_my"
  }
}

resource "aws_route_table_association" "a" {
    depends_on=[aws_route_table.myroute]
  subnet_id      = aws_subnet.wp_public.id
  route_table_id = aws_route_table.myroute.id
}


resource "aws_security_group" "sg_wordpress" {
    depends_on=[
        aws_route_table_association.a
    ]
  name        = "mywordpresssg"
  description = "for wordpress port"
  vpc_id      = aws_vpc.main.id


  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "wordpress_sec"
  }
}

resource "aws_security_group" "sg_mysql" {
    depends_on=[
        aws_security_group.sg_wordpress
    ]
  name        = "formysql"
  description = "formysqlport"
  vpc_id      = aws_vpc.main.id


  ingress {
    description = "mysqport"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "mysql_sec"
  }
}

resource "tls_private_key" "mykey"{
    depends_on=[aws_security_group.sg_mysql]
  algorithm = "RSA"
}

resource "tls_private_key" "key_ssh" {
    depends_on=[tls_private_key.mykey]

   algorithm  = "RSA"
  rsa_bits   = 4096
}
resource "aws_key_pair" "key5" {
    depends_on=[tls_private_key.key_ssh]
  key_name   = "key5"
  public_key = tls_private_key.key_ssh.public_key_openssh
}
output "key_ssh" {
  value = tls_private_key.key_ssh.private_key_pem
}
resource "local_file" "save_key" {
    depends_on=[aws_key_pair.key5]
    content     = tls_private_key.key_ssh.private_key_pem
    filename = "key5.pem"
}

resource "aws_instance" "wp_public" {
    depends_on=[
        tls_private_key.mykey,
        tls_private_key.key_ssh,
        aws_key_pair.key5,
        local_file.save_key,
    ]
  ami           = "ami-035f4044ec687ce38"
  instance_type = "t2.micro"
  key_name = "key5"
  availability_zone = "ap-south-1a"
  subnet_id = aws_subnet.wp_public.id
  vpc_security_group_ids  = [aws_security_group.sg_wordpress.id]

  tags = {
    Name = "wordpress_public"
  }
}



resource "aws_instance" "mys_priv" {
    depends_on=[
        aws_instance.wp_public
    ]
  ami           = "ami-00b494160520dceca"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  subnet_id = aws_subnet.mq_private.id
  vpc_security_group_ids  = [aws_security_group.sg_mysql.id]

  tags = {
    Name = "mysql_private"
  }
}

resource "null_resource" "null1"{
      depends_on = [
        aws_instance.wp_public,
        aws_instance.mys_priv
      ]
    
        connection {
            type = "ssh"
            user = "ubuntu"
            private_key = tls_private_key.key_ssh.private_key_pem
            host = aws_instance.wp_public.public_ip
        }


        provisioner "remote-exec" {
            inline = [
               "cd /var/www/wordpress/",
               "sudo sed -i 's/myhost/${aws_instance.mys_priv.private_ip}/g' wp-config.php",
            ]
        
        }
    }

resource "null_resource" "final" {
  depends_on =  [
           null_resource.null1,
  ]
 provisioner "local-exec" {
    command = "chrome ${aws_instance.wp_public.public_ip}"
  }
}

