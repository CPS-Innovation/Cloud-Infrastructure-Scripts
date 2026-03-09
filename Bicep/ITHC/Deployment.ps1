#################################################
#      Name: ITHC Automated Deployment          #
#      Author: Tom Schoolar                     #
#      Date: 06/03/2026                         #
#      Version: 0.1                             #
#                                               #
#################################################


# -------------------------------------------------------------------------------------
# PROJECT VARIABLES
# -------------------------------------------------------------------------------------  
$projectName = "Tom"
$location = "UKSouth"   # "uksouth" or "ukwest"
$newVnetAddress = "10.7.255.128/25"     

$externalAccessIP = "10.8.0.5" # CHANGE
$dnsName = "tomtest" # for vm connectivity

$projectManager = "TomSchoolar"
$startDate = "2026-12-30"
$endDate = $startDate

$subscriptionName = "Cloud Sandbox"  




$location = $location.ToLower()
$locationInital = $location[2]

#DNS Servers
$dnsServers = '10.7.136.4','10.14.136.4' # unlikely to change
$firewallAddress = "10.8.0.4"

if($locationInital -eq "w")
{
    $firewallAddress = "10.8.16.4" #CHECK
    $dnsServers = '10.14.136.4','10.7.136.4' #IMPROVE
}


# -------------------------------------------------------------------------------------
# AUTOMATED VARIABLE CREATION
# -------------------------------------------------------------------------------------

$hubVnetName = "uk$locationInital-vnet-vft01"

$upperCaseInital = $locationInital.ToString().ToUpper()
$endBitOfName = "-C$upperCaseInital" + "L-ITHC-$projectName"

$routeTableName = "RT$endBitOfName"
$newVnetName = "VNET$endBitOfName"
$pipName = "PIP$endBitOfName"
$nicName = "NIC$endBitOfName"
$nsgName = "NSG$endBitOfName"
$vmName = "VM$endBitOfName"
$osDiskName = "DSK-OS$endBitOfName"
$resourceGroupName = "RG$endBitOfName"

$hubToSpoke = "Hub-to-$newVnetName"
$spokeToHub = "$newVnetName-to-Hub"

$adminUsername = 'azureuser'
$adminPassword = -join ((33..90) + (97..122) | Get-Random -Count 16 | ForEach-Object {[char]$_})

$userProfile = @{
    AdminUsername = $adminUsername
    AdminPassword = $adminPassword
}

# switch

$hubSubscription = Get-AzSubscription -SubscriptionName "ExpressRoute CLZ Hub (Prod)"

Set-AzContext $hubSubscription.name

$hubVnetResource = Get-AzResource -Name $hubVnetName
$hubVnetResourceId = $hubVnetResource.ResourceId
$remoteVnetId = $hubVnetResourceId

$localPeeringName = $newVnetName + "-to-WAN"

# -------------------------------------------------------------------------------------
# CONTEXT SETUP
# -------------------------------------------------------------------------------------

$subscription = Get-AzSubscription -SubscriptionName $subscriptionName
$subscriptionId = $subscription.Id

Set-AzContext $subscriptionId

# Deploy Resource Group
New-AzSubscriptionDeployment -TemplateFile "C:\Temp\ResourceGroup.bicep" `
    -rgName $resourceGroupName `
    -startDate $startDate `
    -endDate $endDate `
    -pm $projectManager `
    -location $location

# Deploy all other resources in that resource group
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile "C:\Temp\Resources.bicep" `
    -vnetName $newVnetName `
    -routeTableName $routeTableName `
    -pipName $pipName `
    -firewallAddress $firewallAddress `
    -dnsServers $dnsServers `
    -nicName $nicName `
    -vnetAddressRange $newVnetAddress `
    -startDate $startDate `
    -endDate $endDate `
    -pm $projectManager `
    -vmName $vmName `
    -osDiskName $osDiskName `
    -nsgName $nsgName `
    -externalAccessIP $externalAccessIP `
    -dnsName $dnsName `
    -userProfile $userProfile `
    -localPeeringLinkName $localPeeringName `
    -remoteVnetId $remoteVnetId ` 
    -Mode Incremental #Complete


Write-Host $vmName
Write-Host $adminPassword

