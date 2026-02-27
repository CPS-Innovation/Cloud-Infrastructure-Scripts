# New Network Variables    
$projectName = "Tom"
$location = "UKSouth"   # "uksouth" or "ukwest"
$newVnetAddress = "10.0.0.0/16"      


# Hub Network Variables

$location = $location.ToLower()
$locationInital = $location[2]

$hubVnetName = "uk$locationInital-vnet-vft01"   
$hubResourceGroupName = "uk$locationInital-rg-vft01"   
$hubSubscriptionName = "ExpressRoute CLZ Hub (Prod)"
$dnsServers = @("10.7.136.4", "10.14.136.4")
$firewallAddress = "10.8.0.4"

# Static Variables
$subscriptionName = "Cloud Sandbox"  

$upperCaseInital = $locationInital.ToString().ToUpper()
$endBitOfName = "-C$upperCaseInital" + "L-ITHC-$projectName"

$routeTableName = "RT$endBitOfName"
$nsgName = "NSG$endBitOfName"
$defaultRouteName = "default"
$newVnetName = "VNET$endBitOfName"

$resourceGroupName = "RG$endBitOfName"

$hubToSpoke = "Hub-to-$newVnetName"
$spokeToHub = "$newVnetName-to-Hub"
$everything = "0.0.0.0/0"


$subscription = Get-AzSubscription -SubscriptionName $subscriptionName
$subscriptionId = $subscription.Id

$hubSubscription = Get-AzSubscription -SubscriptionName $hubSubscriptionName
$hubSubscriptionId = $hubSubscription.Id

Set-AzContext $subscriptionId


New-AzSubscriptionDeployment -Location "uksouth" -TemplateFile "C:\Temp\BicepTest.bicep" -rgName $resourceGroupName

New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile "C:\Temp\BicepTest.bicep" -Mode Incremental #Complete



