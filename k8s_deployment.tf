data "aws_eks_cluster_auth" "aws_eks" {
  name = "${var.cluster_name}"
}

provider "kubernetes" {
  host                   = "${aws_eks_cluster.tank.endpoint}"
  cluster_ca_certificate = "${base64decode(aws_eks_cluster.tank.certificate_authority.0.data)}"
  token                  = "${data.aws_eks_cluster_auth.aws_eks.token}"
  load_config_file       = false
  exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      command =  "aws-iam-authenticator"
      args = ["token", "-i", "tank-cluster"]
      env = {
        AWS_PROFILE = "${var.aws_profile}"
      }
    }
}

resource "kubernetes_config_map" "auth" {
  metadata {
    name = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = <<AUTH
- rolearn: ${aws_iam_role.tank-node.arn}
  username: system:node:{{EC2PrivateDNSName}}
  groups:
    - system:bootstrappers
    - system:nodes
AUTH
  }
}

resource "kubernetes_config_map" "nginx_navigator" {
  metadata {
    name = "nginx-conf"
  }

  data = {
    "nginx.conf" = <<CONFIG
    # auto detects a good number of processes to run
worker_processes auto;

#Provides the configuration file context in which the directives that affect connection processing are specified.
events {
    # Sets the maximum number of simultaneous connections that can be opened by a worker process.
    worker_connections 8000;
    # Tells the worker to accept multiple connections at a time
    multi_accept on;
}


http {
    # what times to include
    include       /etc/nginx/mime.types;
    # what is the default one
    default_type  application/octet-stream;

    client_max_body_size 10G;

    server {
        # listen on port 80
        listen 80;

        # what file to server as index
        index index.html index.htm;

        location = / {
           return 301 /navigator;
        }

        location ^~ /navigator {
            alias /usr/share/nginx/html;
            try_files $uri $uri/ =404;
        }

        # Media: images, icons, video, audio, HTC
        location ~* \.(?:jpg|jpeg|gif|png|ico|cur|gz|svg|svgz|mp4|ogg|ogv|webm|htc)$ {
          expires 1M;
          access_log off;
          add_header Cache-Control "public";
        }

        # Javascript and CSS files
        location ~* \.(?:css|js)$ {
            try_files $uri =404;
            expires 1y;
            access_log off;
            add_header Cache-Control "public";
        }

        # Any route containing a file extension (e.g. /devicesfile.js)
        location ~ ^.+\..+$ {
            try_files $uri =404;
        }
    }
}
CONFIG
  }
}

resource "kubernetes_deployment" "tank" {
  metadata {
    name = "tank"
    labels = {
      app = "tank"
    }
  }

  spec {
    replicas = 5

    selector {
      match_labels = {
        app = "tank"
      }
    }

    template {
      metadata {
        labels = {
          app = "tank"
        }
      }

      spec {
        container {
          image = "ap3rture/tank:latest"
          name  = "tank"
          port {
            container_port = 8888
          }

          env {
            name = "TANK_DB_HOSTS"
            value = "${join(",", aws_instance.cassandra.*.private_ip)}"
          }
          env {
            name = "TANK_PREFIX"
            value = "/tank"
          }
        # - name: 
        #   value: 146.140.36.28
        # - name: TANK_DB_STRATEGY
        #   value: NetworkTopologyStrategy
        # - name: TANK_DB_REPL
        #   value: 2
        # - name: TANK_DB_DATACENTER
        #   value: eu-central
        # - name: TANK_EXHAUSTER_ENABLED
        #   value: true
        # - name: TANK_EXHAUSTER_HOST
        #   value: exhauster-service
        # - name: TANK_EXHAUSTER_PORT
        #   value: 8080

          resources {
            limits {
              cpu    = "0.5"
              memory = "1Gi"
            }
            requests {
              cpu    = "0.5"
              memory = "1Gi"
            }
          }

          liveness_probe {
            http_get {
              path = "/tank"
              port = 8888
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "tank" {
  metadata {
    name = "tank-service"
    
  }
  spec {
    selector = {
      app = "${kubernetes_deployment.tank.metadata.0.labels.app}"
    }
    # session_affinity = "ClientIP"

    port {
      # node_port = 8888
      port        = 8888
      target_port = 8888
    }

    type = "NodePort"
  }
}

resource "kubernetes_deployment" "navigator" {
  metadata {
    name = "navigator"
    labels = {
      app = "navigator"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "navigator"
      }
    }

    template {
      metadata {
        labels = {
          app = "navigator"
        }
      }

      spec {
        container {
          image = "ap3rture/navigator:latest"
          name  = "navigator"
          command = ["nginx", "-c", "/opt/nginx/nginx.conf", "-g", "daemon off;"]
          port {
            container_port = 80
          }

          liveness_probe {
            http_get {
              path = "/navigator"
              port = 80
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }

          volume_mount {
            mount_path = "/opt/nginx"
            name       = "nginx-conf"
            read_only  = true
          }
        }
      

      volume {
        name = "nginx-conf"
        config_map {
          name = "nginx-conf"
          items {
            key = "nginx.conf"
            path = "nginx.conf"
          }
        }
      }
    }
    }
  }
}

resource "kubernetes_service" "navigator" {
  metadata {
    name = "navigator-service"
    
  }
  spec {
    selector = {
      app = "${kubernetes_deployment.navigator.metadata.0.labels.app}"
    }
    # session_affinity = "ClientIP"

    port {
      # node_port = 8888
      port        = 8081
      target_port = 80
    }

    type = "NodePort"
  }
}

resource "kubernetes_ingress" "tank" {
  metadata {
    name = "tank-ingress"
    annotations = {
      "kubernetes.io/ingress.class" = "alb"
      "alb.ingress.kubernetes.io/scheme" = "internet-facing"
      "alb.ingress.kubernetes.io/tags" = "Environment=dev,Team=test"
    }
  }

  spec {
    backend {
      service_name = "tank-service"
      service_port = 8888
    }

    rule {
      http {
        path {
          backend {
            service_name = "tank-service"
            service_port = 8888
          }

          path = "/tank/*"
        }

        path {
          backend {
            service_name = "navigator-service"
            service_port = 8081
          }

          path = "/navigator/*"
        }
      }
    }

  }
}
