---
title: "Azurevpn_defaultsite"
date: 2023-11-16T17:39:27+09:00
draft: true
---
<!--more-->
gateway 설정 시 GatewayManager 서비스 태그가 없으면 connection설정 등 gateway명령이 작동하지않음.

$LocalGateway = Get-AzLocalNetworkGateway -Name "vnet2-lgw" -ResourceGroupName "vnettest-rg"
$VirtualGateway = Get-AzVirtualNetworkGateway -Name "vnet1-gw" -ResourceGroupName "vnettest-rg"
Set-AzVirtualNetworkGatewayDefaultSite -GatewayDefaultSite $LocalGateway -VirtualNetworkGateway $VirtualGateway