---
title: "AKS Overlay Network"
date: 2023-10-21T19:22:46+09:00
draft: true
---
<!--more-->
[Azure Cloud Shell](https://shell.azure.com)
```bash
clusterName="myOverlayCluster"
resourceGroup="myResourceGroup"
location="koreacentral"

az group create -n $resourceGroup -l $location

az aks create -n $clusterName -g $resourceGroup --location $location --network-plugin azure --network-plugin-mode overlay --pod-cidr 192.168.0.0/16

az aks get-credentials -n $clusterName -g $resourceGroup
```