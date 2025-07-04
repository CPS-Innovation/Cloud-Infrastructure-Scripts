# New Network Variables    

$subscriptionName = "Azure Subscription 2"  
$resourceGroupName = "SSDF"

$newSubnetName = "default"
$newVnetAddress = "10.0.0.0/16"      
$newSubnetAddress = "10.0.0.0/24"

$location = "UKSouth"   # "uksouth" or "ukwest"


# Possible Variables that need changing

$routeTableName = "RT-$resourceGroupName"
$nsgName = "NSG-$resourceGroupName"
$defaultRouteName = "default"
$newVnetName = "VNET-$resourceGroupName"


# Hub Network Variables

$location = $location.ToLower()
$locationInital = $location[2]

$hubVnetName = "uk$locationInital-vnet-vft01"   
$hubResourceGroupName = "uk$locationInital-rg-vft01"   
$hubSubscriptionName = "ExpressRoute CLZ Hub (Prod)"
$dnsServers = @("10.8.0.6", "10.8.0.7")
$firewallAddress = "10.8.0.4"

# Static Variables

$hubToSpoke = "WANNET-to-$newVnetName"
$spokeToHub = "$newVnetName-to-WANNET"
$everything = "0.0.0.0/0"



$subscription = Get-AzSubscription -SubscriptionName $subscriptionName
$subscriptionId = $subscription.Id

$hubSubscription = Get-AzSubscription -SubscriptionName $hubSubscriptionName
$hubSubscriptionId = $hubSubscription.Id

Set-AzContext $hubSubscriptionId

$hubVnet = Get-AzVirtualNetwork -ResourceGroupName $hubResourceGroupName -Name $hubVnetName 
if (-not $hubVnet) {
    Write-Host "Error: Existing VNet '$hubVnetName' not found!" -ForegroundColor Red
    exit 1
}

Set-AzContext $subscriptionId

# Create Resource Group
$rg = New-AzResourceGroup -Name $resourceGroupName -Location $location

# Create NSG and Route Table
$nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $resourceGroupName -Location $location
$route = New-AzRouteConfig -Name $defaultRouteName -AddressPrefix $everything -NextHopType "VirtualAppliance" -NextHopIpAddress $firewallAddress
$rt = New-AzRouteTable -Name $routeTableName -ResourceGroupName $resourceGroupName -Location $location -Route $route


# Create new VNet and subnet
$newSubnet = New-AzVirtualNetworkSubnetConfig -Name $newSubnetName -AddressPrefix $newSubnetAddress -NetworkSecurityGroup $nsg -RouteTable $rt
$newVNet = New-AzVirtualNetwork -Name $newVnetName -ResourceGroupName $resourceGroupName -Location $location -AddressPrefix $newVnetAddress -Subnet $newSubnet -DNSServer $dnsServers


# Peer the new spoke vnet to the hub vnet
Add-AzVirtualNetworkPeering -Name $spokeToHub -VirtualNetwork $newVNet -RemoteVirtualNetworkId $hubVnet.Id -AllowForwardedTraffic

Set-AzContext $hubSubscriptionId
Add-AzVirtualNetworkPeering -Name $hubToSpoke -VirtualNetwork $hubVnet -RemoteVirtualNetworkId $newVNet.Id -AllowForwardedTraffic

Write-Host "Script Execution Finished"
