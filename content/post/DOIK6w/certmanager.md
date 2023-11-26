```sh
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade cert-manager jetstack/cert-manager \
    --install \
    --create-namespace \
    --wait \
    --namespace cert-manager \
    --set installCRDs=true

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt uses this to contact you about expiring
    # certificates, and issues related to your account.
    email: jkl2554@cloocus.com
    # ACME server URL for Let’s Encrypt’s staging environment.
    # The staging environment won't issue trusted certificates but is
    # used to ensure that the verification process is working properly
    # before moving to production
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource used to store the account's private key.
      name: example-issuer-account-key
    # Enable the HTTP-01 challenge provider
    # you prove ownership of a domain by ensuring that a particular
    # file is present at the domain
    solvers:
      - http01:
           ingress:
              ingressClassName: azure-application-gateway
EOF


cat <<EOF > cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt uses this to contact you about expiring
    # certificates, and issues related to your account.
    email: jkl2554@cloocus.com
    # ACME server URL for Let’s Encrypt’s staging environment.
    # The staging environment won't issue trusted certificates but is
    # used to ensure that the verification process is working properly
    # before moving to production
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      # Secret resource used to store the account's private key.
      name: example-issuer-account-key
    # Enable the HTTP-01 challenge provider
    # you prove ownership of a domain by ensuring that a particular
    # file is present at the domain
    solvers:
      - http01:
           ingress:
              ingressClassName: azure-application-gateway
EOF
kubectl apply -f cluster-issuer.yaml --namespace cert-manager
``````