---
title: "Azure AKS ExernalDNS 설치"
date: 2023-11-08T13:07:45+09:00
draft: false
---
<!--more-->

# Azure AKS ExeternalDNS
## 선행조건 및 설명
이 자습서에서는 Azure Kubernetes Service를 사용하여 Azure DNS에 대한 ExternalDNS를 설정하는 방법을 설명합니다.  
이 자습서에서는 >=0.13.6 버전의 ExternalDNS를 사용해야 합니다.  
이 자습서에서는 `Azure CLI 2.53.1`, `kubectl v1.28.3`을 사용합니다.  
이 자습서에서는 Managed Identity Using Workload Identity를 사용해서 ExternalDNS를 설치합니다.  
*[External-dns Azure 튜토리얼 페이지](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/azure.md#managed-identity-using-workload-identity)
## Azure AKS Cluster 배포
```sh
AZURE_AKS_RESOURCE_GROUP="myaks-RG" # name of resource group where aks cluster was created
AZURE_AKS_CLUSTER_NAME="myaks" # name of aks cluster previously created
LOCATION="koreacentral"

# 클러스터 신규 배포
az group create -n ${AZURE_AKS_RESOURCE_GROUP} -l ${LOCATION}

az aks create -n ${AZURE_AKS_CLUSTER_NAME} -g ${AZURE_AKS_RESOURCE_GROUP} --network-plugin azure \
              --enable-oidc-issuer --enable-workload-identity --generate-ssh-keys

# 기존 클러스터 업그레이드
# az aks update --resource-group ${AZURE_AKS_RESOURCE_GROUP} --name ${AZURE_AKS_CLUSTER_NAME} --enable-oidc-issuer --enable-workload-identity

# kubeconfig 파일 생성 및 환경변수 설정
az aks get-credentials -n ${AZURE_AKS_CLUSTER_NAME} -g ${AZURE_AKS_RESOURCE_GROUP} -f ./kubeconfig --overwrite-existing
export KUBECONFIG="$(pwd)/kubeconfig"
```

## AGIC Add-on 배포
```sh
APPGW_NAME="agic-appgw"
APPGW_SUBNET="${APPGW_NAME}-subnet"

CLUSTER_RESOURCE_GROUP="$(az aks show -g ${AZURE_AKS_RESOURCE_GROUP} -n ${AZURE_AKS_CLUSTER_NAME} --query "nodeResourceGroup" -o tsv)" 
CLUSTER_VNET=$(az network vnet list -g ${CLUSTER_RESOURCE_GROUP} -o tsv --query "[0].name")

# Create AGIC Subnet
az network vnet subnet create -n ${APPGW_SUBNET} -g ${CLUSTER_RESOURCE_GROUP} \
                        --vnet-name ${CLUSTER_VNET} --address-prefixes "10.225.0.0/16"


## Application Gateway 생성
az network application-gateway create -n ${APPGW_NAME} -g ${CLUSTER_RESOURCE_GROUP} \
                         --sku Standard_v2 --public-ip-address "${APPGW_NAME}-pip" \
                         --vnet-name ${CLUSTER_VNET} --subnet ${APPGW_SUBNET} --priority 100

# Enable AGIC Add-on
APPGW_ID=$(az network application-gateway show -n ${APPGW_NAME} -g ${CLUSTER_RESOURCE_GROUP} -o tsv --query "id")
az aks enable-addons -n ${AZURE_AKS_CLUSTER_NAME} -g ${AZURE_AKS_RESOURCE_GROUP} -a ingress-appgw --appgw-id ${APPGW_ID}
```
## Azure External DNS 설치
```sh
## Managed Identity 배포
IDENTITY_NAME="ExternalDNS-${AZURE_AKS_CLUSTER_NAME}"

# create a managed identity
az identity create --resource-group "${CLUSTER_RESOURCE_GROUP}" --name "${IDENTITY_NAME}"
```
### Azure DNS Zone 권한 설정
```sh
AZURE_DNS_ZONE_RESOURCE_GROUP="<DNS RG>" # name of resource group where dns zone is hosted
AZURE_DNS_ZONE="<DNS ZONE>" # DNS zone name like example.com or sub.example.com

# fetch identity client id from managed identity created earlier
IDENTITY_CLIENT_ID=$(az identity show --resource-group "${CLUSTER_RESOURCE_GROUP}" \
  --name "${IDENTITY_NAME}" --query "clientId" --output tsv)
# fetch DNS id used to grant access to the managed identity
DNS_ID=$(az network dns zone show --name "${AZURE_DNS_ZONE}" \
  --resource-group "${AZURE_DNS_ZONE_RESOURCE_GROUP}" --query "id" --output tsv)
# RESOURCE_GROUP_ID=$(az group show --name "${AZURE_DNS_ZONE_RESOURCE_GROUP}" --query "id" --output tsv)

az role assignment create --role "DNS Zone Contributor" \
  --assignee "${IDENTITY_CLIENT_ID}" --scope "${DNS_ID}"
# az role assignment create --role "Reader" \
#   --assignee "${IDENTITY_CLIENT_ID}" --scope "${RESOURCE_GROUP_ID}"
```

```sh
OIDC_ISSUER_URL="$(az aks show -n ${AZURE_AKS_CLUSTER_NAME} -g ${AZURE_AKS_RESOURCE_GROUP} --query "oidcIssuerProfile.issuerUrl" -otsv)"

az identity federated-credential create --name ${IDENTITY_NAME} --identity-name ${IDENTITY_NAME} --resource-group ${CLUSTER_RESOURCE_GROUP} --issuer "${OIDC_ISSUER_URL}" --subject "system:serviceaccount:default:external-dns"
```
*페더레이션 자격증명의 namespace 및 ServiceAccount를 확인해야합니다.`system:serviceaccount:<NAMESPACE>:<SERVICE_ACCOUNT>`

## option1:manifest

### ExternalDNS Config Secret 배포
```sh
cat <<EOF > azure.json
{
  "subscriptionId": "$(echo ${DNS_ID} | cut -c 16-51)",
  "resourceGroup": "${AZURE_DNS_ZONE_RESOURCE_GROUP}",
  "useWorkloadIdentityExtension": true
}
EOF
kubectl create secret generic azure-config-file --namespace "default" --from-file azure.json
```

```sh
cat << EOF > ExternalDNS-RBAC.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  annotations:
    azure.workload.identity/client-id: "${IDENTITY_CLIENT_ID}"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
  - apiGroups: [""]
    resources: ["services","endpoints","pods", "nodes"]
    verbs: ["get","watch","list"]
  - apiGroups: ["extensions","networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get","watch","list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
  - kind: ServiceAccount
    name: external-dns
    namespace: default
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: external-dns
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:v0.14.0
          args:
            - --source=service
            - --source=ingress
            - --domain-filter=${AZURE_DNS_ZONE} # (optional) limit to only ${AZURE_DNS_ZONE} domains; change to match the zone created above.
            - --provider=azure
            - --azure-resource-group=${AZURE_DNS_ZONE_RESOURCE_GROUP} # (optional) use the DNS zones from the tutorial's resource group
            - --txt-prefix=externaldns-
          volumeMounts:
            - name: azure-config-file
              mountPath: /etc/kubernetes
              readOnly: true
      volumes:
        - name: azure-config-file
          secret:
            secretName: azure-config-file
EOF
## deploy ExternalDNS With RBAC cluster
kubectl apply -f ExternalDNS-RBAC.yaml

```

## option2:helm
*[ExternalDNS Artifect Hub 페이지](https://artifacthub.io/packages/helm/external-dns/external-dns)  

### values.yaml
```sh

cat << EOF > ExternalDNS-values.yaml
fullnameOverride: external-dns

serviceAccount:
  annotations:
    azure.workload.identity/client-id: "${IDENTITY_CLIENT_ID}"

podLabels:
  azure.workload.identity/use: "true"

provider: azure

secretConfiguration:
  enabled: true
  mountPath: "/etc/kubernetes/"
  data:
    azure.json: |
      {
        "subscriptionId": "$(echo ${DNS_ID} | cut -c 16-51)",
        "resourceGroup": "${AZURE_DNS_ZONE_RESOURCE_GROUP}",
        "useWorkloadIdentityExtension": true
      }
EOF
```

```sh
##  Add Repo
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
## Install Exeternal DNS by helm
helm upgrade --install azure-external-dns external-dns/external-dns --version 1.13.1 -f ExternalDNS-values.yaml
```

## ExternalDNS 테스트
### 로그 체크
```sh
# deployment logs
kubectl logs -f $(kubectl get po -l "azure.workload.identity/use=true" -o jsonpath={.items[0].metadata.name})
# time="2023-11-09T05:30:22Z" level=info msg="config: {APIServerURL: KubeConfig: RequestTimeout:30s DefaultTargets:[] GlooNamespaces:
# 
#   ...
# 
# WebhookProviderWriteTimeout:10s WebhookServer:false}"
# time="2023-11-09T05:30:22Z" level=info msg="Instantiating new Kubernetes client"
# time="2023-11-09T05:30:22Z" level=info msg="Using inCluster-config based on serviceaccount-token"
# time="2023-11-09T05:30:22Z" level=info msg="Created Kubernetes client https://10.0.0.1:443"
# time="2023-11-09T05:30:22Z" level=info msg="Using workload identity extension to retrieve access token for Azure API."
# time="2023-11-09T05:30:24Z" level=info msg="All records are already up to date"
```

### 기능 테스트
```sh
## test
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
spec:
  rules:
    - host: test.hyugo.biz
      http:
        paths:
        - path: /
          backend:
            service:
              name: contoso-service
              port:
                number: 80
          pathType: Exact
EOF

# ingress 배포 체크
kubectl get ingress
# NAME                CLASS    HOSTS             ADDRESS          PORTS   AGE
# test-ingress        <none>   test.hyugo.biz    20.196.232.231   80      10s

# Pod 로그
# time="2023-11-09T05:38:28Z" level=info msg="Updating A record named 'test' to '20.200.221.231' for Azure DNS zone 'hyugo.biz'."
# time="2023-11-09T05:38:29Z" level=info msg="Updating TXT record named 'externaldns-test' to '\"heritage=external-dns,external-dns/owner=default,external-dns/resource=ingress/default/test-ingress\"' for Azure DNS zone 'hyugo.biz'."
# time="2023-11-09T05:38:31Z" level=info msg="Updating TXT record named 'externaldns-a-test' to '\"heritage=external-dns,external-dns/owner=default,external-dns/resource=ingress/default/test-ingress\"' for Azure DNS zone 'hyugo.biz'."
# time="2023-11-09T05:39:28Z" level=info msg="All records are already up to date"


# 도메인 체크
nslookup test.hyugo.biz
# Server:         168.63.129.16
# Address:        168.63.129.16#53
# 
# Non-authoritative answer:
# Name:   test.hyugo.biz
# Address: 20.200.221.231

#### 현재 helm의 이미지가 registry.k8s.io/external-dns/external-dns:v0.13.6이여서 Azure DNS 삭제 동작이 작동하지 않음.#####
# ingress 삭제
kubectl delete ingress test-ingress

# Pod 로그
# time="2023-11-09T05:42:30Z" level=info msg="Deleting A record named 'test' for Azure DNS zone 'hyugo.biz'."
# time="2023-11-09T05:42:32Z" level=info msg="Deleting TXT record named 'externaldns-test' for Azure DNS zone 'hyugo.biz'."
# time="2023-11-09T05:42:33Z" level=info msg="Deleting TXT record named 'externaldns-a-test' for Azure DNS zone 'hyugo.biz'."
# time="2023-11-09T05:43:30Z" level=info msg="All records are already up to date"


# 도메인 체크
nslookup test.hyugo.biz
# Server:         168.63.129.16
# Address:        168.63.129.16#53
# 
# ** server can't find test.hyugo.biz: NXDOMAIN

```
## 리소스 정리
```sh
az group delete -n ${AZURE_AKS_RESOURCE_GROUP}

```