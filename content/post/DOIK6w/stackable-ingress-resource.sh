myDomain=hyugo.biz

cat <<EOT > minio-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  labels: 
    app: minio
  name: minio
spec: 
  ingressClassName: azure-application-gateway
  rules: 
  - host: minio.$myDomain
    http: 
      paths: 
      - backend: 
          service: 
            name: minio-console
            port: 
              number: 9001
        path: /*
        pathType: ImplementationSpecific
EOT
kubectl apply -f minio-ingress.yaml

cat <<EOT > minio-ingress-https.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  labels: 
    app: minio
  name: minio
  annotations: 
    cert-manager.io/cluster-issuer: letsencrypt-staging
spec: 
  ingressClassName: azure-application-gateway
  tls:
  - hosts:
    - minio.$myDomain
    secretName: minio-cert
  rules: 
  - host: minio.$myDomain
    http: 
      paths: 
      - backend: 
          service: 
            name: minio-console
            port: 
              number: 9001
        path: /*
        pathType: ImplementationSpecific
EOT
kubectl apply -f minio-ingress-https.yaml

cat <<EOT > trino-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  labels: 
    app: trino
  name: trino
  annotations: 
    appgw.ingress.kubernetes.io/backend-protocol: "https"
spec: 
  ingressClassName: azure-application-gateway
  rules: 
  - host: trino.$myDomain
    http: 
      paths: 
      - backend: 
          service: 
            name: trino-coordinator
            port: 
              number: 8443
        path: /*
        pathType: ImplementationSpecific
EOT
kubectl apply -f trino-ingress.yaml

AZURE_AKS_RESOURCE_GROUP="myaks-RG" # name of resource group where aks cluster was created
AZURE_AKS_CLUSTER_NAME="myaks" # name of aks cluster previously created
LOCATION="koreacentral"
APPGW_NAME="agic-appgw"
CLUSTER_RESOURCE_GROUP="$(az aks show -g ${AZURE_AKS_RESOURCE_GROUP} -n ${AZURE_AKS_CLUSTER_NAME} --query "nodeResourceGroup" -o tsv)" 
az network application-gateway root-cert create --cert-file trino-self-signed-cert.cer --gateway-name $APPGW_NAME  --name trino-self-signed-cert --resource-group $CLUSTER_RESOURCE_GROUP


cat <<EOT > trino-ingress-https.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  labels: 
    app: trino
  name: trino
  annotations: 
    cert-manager.io/cluster-issuer: letsencrypt-staging
    appgw.ingress.kubernetes.io/backend-protocol: "https"
    appgw.ingress.kubernetes.io/appgw-trusted-root-certificate: "trino-self-signed-cert"
    appgw.ingress.kubernetes.io/backend-hostname: "trino-coordinator-default.default.svc.cluster.local"
spec: 
  ingressClassName: azure-application-gateway
  tls:
  - hosts:
    - trino.$myDomain
    secretName: trino-cert
  rules: 
  - host: trino.$myDomain
    http: 
      paths: 
      - backend: 
          service: 
            name: trino-coordinator
            port: 
              number: 8443
        path: /*
        pathType: ImplementationSpecific
EOT
kubectl apply -f trino-ingress-https.yaml