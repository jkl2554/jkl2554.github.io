########### 수정중 ################
# 노드 PrivateIP 변수 지정
N1=$(kubectl get node --label-columns=topology.kubernetes.io/zone --selector=topology.kubernetes.io/zone=ap-northeast-2a -o jsonpath={.items[0].status.addresses[0].address})
N2=$(kubectl get node --label-columns=topology.kubernetes.io/zone --selector=topology.kubernetes.io/zone=ap-northeast-2b -o jsonpath={.items[0].status.addresses[0].address})
N3=$(kubectl get node --label-columns=topology.kubernetes.io/zone --selector=topology.kubernetes.io/zone=ap-northeast-2c -o jsonpath={.items[0].status.addresses[0].address})
echo "export N1=$N1" >> /etc/profile
echo "export N2=$N2" >> /etc/profile
echo "export N3=$N3" >> /etc/profile
echo $N1, $N2, $N3

# 노드 보안그룹에 eksctl-host 에서 노드(파드)에 접속 가능하게 룰(Rule) 추가 설정
NGSGID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=*ng1* --query "SecurityGroups[*].[GroupId]" --output text)
aws ec2 authorize-security-group-ingress --group-id $NGSGID --protocol '-1' --cidr 192.168.1.100/32

# AWS LoadBalancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller

# ExternalDNS 컨트롤러 설치 
MyDomain=hyugo.click
echo "export MyDomain=hyugo.click" >> /etc/profile
MyDnsHostedZoneId=$(aws route53 list-hosted-zones-by-name --dns-name "${MyDomain}." --query "HostedZones[0].Id" --output text)
echo $MyDomain, $MyDnsHostedZoneId
curl -s -O https://raw.githubusercontent.com/cloudneta/cnaeblab/master/_data/externaldns.yaml
MyDomain=$MyDomain MyDnsHostedZoneId=$MyDnsHostedZoneId envsubst < externaldns.yaml | kubectl apply -f -

# kube-ops-view
helm repo add geek-cookbook https://geek-cookbook.github.io/charts/
helm install kube-ops-view geek-cookbook/kube-ops-view --version 1.2.2 --set env.TZ="Asia/Seoul" --namespace kube-system
kubectl patch svc -n kube-system kube-ops-view -p '{"spec":{"type":"LoadBalancer"}}'
kubectl annotate service kube-ops-view -n kube-system "external-dns.alpha.kubernetes.io/hostname=kubeopsview.$MyDomain"
echo -e "Kube Ops View URL = http://kubeopsview.$MyDomain:8080/#scale=1.5"

# ebs gp3 스토리지 클래스 생성
kubectl patch sc gp2 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl apply -f https://raw.githubusercontent.com/gasida/DOIK/main/1/gp3-sc.yaml

# efs 스토리지 클래스 생성
cat <<EOT > efs-sc.yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata: 
  name: efs-sc
provisioner: efs.csi.aws.com
parameters: 
  provisioningMode: efs-ap
  fileSystemId: $EFS_ID
  directoryPerms: "700"
EOT
kubectl apply -f efs-sc.yaml

# Metrics-server 배포
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml



# Cert Manager 설치
## Email 주소 설정
E_MAIL_ADDRESS=<Your Email>


helm repo add jetstack https://charts.jetstack.io
helm repo update
# install Cert Manager 
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml
helm install   cert-manager jetstack/cert-manager   --namespace cert-manager   --create-namespace   --version v1.13.2


kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # You must replace this email address with your own.
    # Let's Encrypt uses this to contact you about expiring
    # certificates, and issues related to your account.
    email: ${E_MAIL_ADDRESS}
    # ACME server URL for Let's Encrypt's staging environment.
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
              class: azure/application-gateway
EOF



# 프로메테우스-스택 생성
kubectl create ns monitoring
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

## 파라미터 파일 생성
cat <<EOT > monitor-values.yaml
prometheus:
  prometheusSpec:
    podMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    #probeSelectorNilUsesHelmValues: false
    retention: 5d
    retentionSize: "10GiB"
    scrapeInterval: '15s'
    evaluationInterval: '15s'

  ingress:
    enabled: true
    ingressClassName: azure-application-gateway
    hosts: 
      - prometheus.$MyDomain
    paths: 
      - /*
    annotations:
      appgw.ingress.kubernetes.io/ssl-redirect: "true"
      appgw.ingress.kubernetes.io/appgw-ssl-certificate: letsencrypt-prod

grafana:
  defaultDashboardsTimezone: Asia/Seoul
  adminPassword: prom-operator
  defaultDashboardsEnabled: false

  ingress:
    enabled: true
    ingressClassName: azure-application-gateway
    hosts: 
      - grafana.$MyDomain
    paths: 
      - /*
    annotations:
      appgw.ingress.kubernetes.io/ssl-redirect: "true"
      appgw.ingress.kubernetes.io/appgw-ssl-certificate: letsencrypt-prod

defaultRules:
  create: false
kubeEtcd:
  enabled: false
alertmanager:
  enabled: false
EOT

## 배포
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --version 51.7.0 \
-f monitor-values.yaml --namespace monitoring

## 그라파나 ingress 도메인으로 웹 접속 : 기본 계정 - admin / prom-operator
echo -e "Grafana Web URL = https://grafana.$MyDomain"