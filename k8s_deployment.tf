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
    mapRoles = "${file("./tmp/config_map_auth.yml")}"
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
    replicas = 7

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
              path = "/"
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
    annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-internal" = "0.0.0.0/0"
    }
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

    type = "LoadBalancer"
  }
}
