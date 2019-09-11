resource "kubernetes_deployment" "alb_ingress" {
  depends_on = ["kubernetes_cluster_role_binding.alb_ingress"]

  metadata {
    name      = "alb-ingress-controller"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/name" = "alb-ingress-controller"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "alb-ingress-controller"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "alb-ingress-controller"
        }
      }

      spec {
        restart_policy                   = "Always"
        termination_grace_period_seconds = 30
        service_account_name             = "alb-ingress-controller"
        automount_service_account_token = true

        container {
          image                    = "docker.io/amazon/aws-alb-ingress-controller:v1.1.2"
          image_pull_policy        = "Always"
          name                     = "alb-ingress-controller"
          termination_message_path = "/dev/termination-log"

          args = [
            "--watch-namespace=default",
            "--ingress-class=alb",
            "--cluster-name=${var.cluster_name}",
            "--aws-vpc-id=${aws_vpc.tank_vpc.id}",
            "--aws-region=${var.region}",
            "--aws-api-debug=true"
          ]

          security_context {
            allow_privilege_escalation = "false"
            privileged = "false"
            run_as_user = "999"
            run_as_non_root = "true"
          }
          env {
            name = "AWS_ACCESS_KEY_ID"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.aws_key.metadata[0].name
                key = "key_id"
              }
            }
          }
          env {
            name = "AWS_SECRET_ACCESS_KEY"

            value_from {
              secret_key_ref {
                name = kubernetes_secret.aws_key.metadata[0].name
                key = "key"
              }
            }
          }
          env {
            name = "AWS_DEFAULT_REGION"
            value = var.region
          }

          
        }

      }
    }
  }
}

resource "kubernetes_cluster_role" "cluster_role" {
  metadata {
    name = "alb-ingress-controller"
    labels = {
      "app" = "alb-ingress-controller"
    }
  }

  rule {
    api_groups = [
      "",
      "extensions",
    ]

    resources = [
      "configmaps",
      "endpoints",
      "events",
      "ingresses",
      "ingresses/status",
      "services",
    ]

    verbs = [
      "create",
      "get",
      "list",
      "update",
      "watch",
      "patch",
    ]
  }
  rule {
    api_groups = [
      "",
      "extensions",
    ]

    resources = [
      "nodes",
      "pods",
      "secrets",
      "services",
      "namespaces",
    ]

    verbs = [
      "get",
      "list",
      "watch",
    ]
  }
}

resource "kubernetes_cluster_role_binding" "alb_ingress" {
  depends_on = ["kubernetes_service_account.alb_ingress"]

  metadata {
    name = "alb-ingress-controller"

    labels = {
      "app.kubernetes.io/name" = "alb-ingress-controller"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cluster_role.metadata[0].name             #TODO: use fine-grained ClusterRole when K8s TF provider supports
  }

  subject {
    kind      = "ServiceAccount"
    name      = "alb-ingress-controller"
    namespace = "kube-system"
    api_group = ""
  }
}

resource "kubernetes_service_account" "alb_ingress" {
  metadata {
    name      = "alb-ingress-controller"
    namespace = "kube-system"

    labels = {
      "app.kubernetes.io/name" = "alb-ingress-controller"
    }
  }

  secret {
    name = kubernetes_secret.aws_key.metadata[0].name
  }

  automount_service_account_token = "true"
}