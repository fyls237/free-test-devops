/* Bonjour je vous présente le projet de déploiement d'un Cluster Kubernetes sur le fournisseur Scaleway en utilisant Terraform.
  Le projet vise à déployer un Cluster Kubernetes, un contrôleur Ingress NGINX,
  un load balancer et une application hello-world accessible via l'adresse IP publique du load balancer.

  auteur du code : Loic Steve

*/

// Création du cluster et du pool de cluster 
resource "scaleway_vpc_private_network" "hedy" {}

resource "scaleway_k8s_cluster" "loicsteve_cluster" {
  name    = "loicsteve"
  version = "1.24.3"
  cni     = "flannel"
  
  region = var.region
  private_network_id = scaleway_vpc_private_network.hedy.id
  delete_additional_resources = false
}

resource "scaleway_k8s_pool" "loicsteve_pool" {
  cluster_id  = scaleway_k8s_cluster.loicsteve_cluster.id
  name        = "loicsteve-pool"
  node_type   = "DEV1-M" 
  size        = 2 
  min_size = 1
  autoscaling = true
  autohealing = true
}


resource "null_resource" "kubeconfig" {
  depends_on = [scaleway_k8s_pool.loicsteve_pool]
  triggers = {
    host                   = scaleway_k8s_cluster.loicsteve_cluster.kubeconfig[0].host
    token                  = scaleway_k8s_cluster.loicsteve_cluster.kubeconfig[0].token
    cluster_ca_certificate = scaleway_k8s_cluster.loicsteve_cluster.kubeconfig[0].cluster_ca_certificate
  }
}

provider "kubectl" {
  load_config_file = "false"
  host = null_resource.kubeconfig.triggers.host
  token = null_resource.kubeconfig.triggers.token
  cluster_ca_certificate = base64decode(
    null_resource.kubeconfig.triggers.cluster_ca_certificate
  )
}

// Céation du controller Ingress nginx via helm

provider "helm" {
  kubernetes {
    host = null_resource.kubeconfig.triggers.host
    token = null_resource.kubeconfig.triggers.token
    cluster_ca_certificate = base64decode(
      null_resource.kubeconfig.triggers.cluster_ca_certificate
    )
  }
}

resource "scaleway_lb_ip" "nginx_ip" {
  zone       = var.zone
  project_id = scaleway_k8s_cluster.loicsteve_cluster.project_id
}


resource "helm_release" "nginx_ingress" {
  name      = "nginx-ingress"
  namespace = "default"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart = "ingress-nginx"
  

  set {
    name = "controller.service.loadBalancerIP"
    value = scaleway_lb_ip.nginx_ip.ip_address
  }

  set {
    name = "controller.config.use-proxy-protocol"
    value = "true"
  }
  set {
    name = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/scw-loadbalancer-proxy-protocol-v2"
    value = "true"
  }
  set {
    name = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/scw-loadbalancer-zone"
    value = scaleway_lb_ip.nginx_ip.zone
  }

  set {
    name = "controller.service.externalTrafficPolicy"
    value = "Cluster"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/scw-loadbalancer-use-hostname"
    value = "true"
  }

  set {
    name = "controller.service.annotations.kubernetes\\.io/ingress.class"
    value = "nginx"
  }

  set {
    name = "controller.service.annotations.nginx\\.ingress\\.kubernetes\\.io/rewrite-target"
    value = "/"
  }


  // Ajoutez cette nouvelle annotation pour rediriger les défis ACME
  set {
    name = "controller.service.annotations.nginx\\.ingress\\.kubernetes\\.io/whitelist-source-range"
    value = "0.0.0.0/0" // ou votre plage IP spécifique pour les demandes ACME
  }



  depends_on = [
    scaleway_k8s_pool.loicsteve_pool
  ]
}


data "kubectl_file_documents" "hello_world" {
  content = file("./hello-world-service.yaml")
}

resource "kubectl_manifest" "hello_world" {
    for_each = data.kubectl_file_documents.hello_world.manifests
    yaml_body = each.value
}


resource "local_file" "kubeconfig" {
  content = scaleway_k8s_cluster.loicsteve_cluster.kubeconfig[0].config_file
  filename = "${path.module}/kubeconfig"
}

output "public_loadbalancer_ip" {
  value = scaleway_lb_ip.nginx_ip.ip_address
}


output "helm_nginx_ingress_status" {
  value = helm_release.nginx_ingress.status
}





