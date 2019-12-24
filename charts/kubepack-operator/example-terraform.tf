provider "helm" {
  kubernetes {
    load_config_file = true

    cluster_ca_certificate = file("~/.kube/cluster-ca-cert.pem")
  }
}

locals {
  kubepack_release_name = "kubepack-operator"
  kubepack_namespace    = "kube-system"
}

locals {
  kubepack_chart_name = "kubepack-operator"

  # re-implement: https://github.com/kubepack/kubepack-operator/blob/0.3.0/charts/kubepack-operator/templates/_helpers.tpl#L9-L20
  # in hcl
  kubepack_release_fullname = length(regexall("\\Q${local.kubepack_chart_name}\\E", local.kubepack_release_name)) != 0 ? trimsuffix(substr(local.kubepack_release_name, 0, 63), "-") : trimsuffix(substr("${local.kubepack_release_name}-${local.kubepack_chart_name}", 0, 63), "-")
}

data "helm_repository" "appscode" {
  name = "appscode"
  url  = "https://charts.appscode.com/stable"
}

resource "tls_private_key" "kubepack_ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "kubepack_ca" {
  key_algorithm   = tls_private_key.kubepack_ca.algorithm
  private_key_pem = tls_private_key.kubepack_ca.private_key_pem

  subject {
    common_name = "ca"
  }

  validity_period_hours = 87600
  set_subject_key_id    = false

  is_ca_certificate = true
  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "cert_signing",
    "server_auth",
    "client_auth"
  ]
}

resource "tls_private_key" "kubepack_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "kubepack_server" {
  key_algorithm   = tls_private_key.kubepack_server.algorithm
  private_key_pem = tls_private_key.kubepack_server.private_key_pem

  subject {
    common_name = local.kubepack_release_fullname
  }

  dns_names = [
    "${local.kubepack_release_fullname}.${local.kubepack_namespace}",
    "${local.kubepack_release_fullname}.${local.kubepack_namespace}.svc"
  ]
}

resource "tls_locally_signed_cert" "kubepack_server" {
  ca_key_algorithm   = tls_self_signed_cert.kubepack_ca.key_algorithm
  ca_private_key_pem = tls_private_key.kubepack_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.kubepack_ca.cert_pem

  cert_request_pem = tls_cert_request.kubepack_server.cert_request_pem

  validity_period_hours = 87600
  set_subject_key_id    = false

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
    "client_auth"
  ]
}

resource "helm_release" "kubepack" {
  name = local.kubepack_release_name

  namespace = local.kubepack_namespace

  # executing locally, from in chart folder
  chart = "../kubepack-operator"

  # executing from published chart
  #   repository = data.helm_repository.appscode.metadata[0].name
  #   chart = "kubepack-operator"
  #   version    = "0.2.0"

  set {
    name  = "apiserver.servingCerts.generate"
    value = "false"
  }

  set_sensitive {
    name  = "apiserver.ca"
    value = base64encode(file("~/.kube/cluster-ca-cert.pem"))
  }

  set_sensitive {
    name  = "apiserver.servingCerts.caCrt"
    value = base64encode(tls_self_signed_cert.kubepack_ca.cert_pem)
  }

  set_sensitive {
    name  = "apiserver.servingCerts.serverKey"
    value = base64encode(tls_private_key.kubepack_server.private_key_pem)
  }

  set_sensitive {
    name  = "apiserver.servingCerts.serverCrt"
    value = base64encode(tls_locally_signed_cert.kubepack_server.cert_pem)
  }
}
