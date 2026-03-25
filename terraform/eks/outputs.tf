output "cluster_endpoint" {
    value = module.eks.cluster_endpoint
}
output "cluster_certificate_authority_data" {
    value = module.eks.cluster_certificate_authority_data
}
output "oidc_provider_url" {
    value = module.eks.cluster_oidc_issuer_url
}

