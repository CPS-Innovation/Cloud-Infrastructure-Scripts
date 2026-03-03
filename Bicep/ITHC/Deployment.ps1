# New Network Variables    
$projectName = "Tom"
$location = "UKSouth"   # "uksouth" or "ukwest"
$newVnetAddress = "10.1.1.0/24"     

$externalAccessIP = "10.8.0.5" # CHANGE
$dnsName = "tomtest"


# Hub Network Variables

$projectManager = "TomSchoolar"
$startDate = "2026-12-30"

$location = $location.ToLower()
$locationInital = $location[2]

$hubVnetName = "uk$locationInital-vnet-vft01"   
$hubResourceGroupName = "uk$locationInital-rg-vft01"   
$hubSubscriptionName = "ExpressRoute CLZ Hub (Prod)"
$dnsServers = @("10.7.136.4", "10.14.136.4")

# Static Variables
$subscriptionName = "Cloud Sandbox"  

$upperCaseInital = $locationInital.ToString().ToUpper()
$endBitOfName = "-C$upperCaseInital" + "L-ITHC-$projectName"

$routeTableName = "RT$endBitOfName"
$defaultRouteName = "default"
$newVnetName = "VNET$endBitOfName"
$pipName = "PIP$endBitOfName"
$nicName = "NIC$endBitOfName"
$nsgName = "NSG$endBitOfName"

$resourceGroupName = "RG$endBitOfName"

$hubToSpoke = "Hub-to-$newVnetName"
$spokeToHub = "$newVnetName-to-Hub"

#DNS Servers
$dnsServers = '10.7.136.4','10.14.136.4'
$firewallAddress = "10.8.0.4"

if($locationInital -eq "w")
{
    $firewallAddress = "10.8.16.4" #CHECK
    $dnsServers = '10.14.136.4','10.7.136.4' #IMPROVE
}

$vmName = "VM$endBitOfName"
$osDiskName = "DSK$endBitOfName" + "-OS"


$subscription = Get-AzSubscription -SubscriptionName $subscriptionName
$subscriptionId = $subscription.Id

$hubSubscription = Get-AzSubscription -SubscriptionName $hubSubscriptionName
$hubSubscriptionId = $hubSubscription.Id

Set-AzContext $subscriptionId


New-AzSubscriptionDeployment -Location "uksouth" -TemplateFile "C:\Temp\BicepTest.bicep" -rgName $resourceGroupName

New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName -TemplateFile "C:\Temp\BicepTest2.bicep" `
    -vnetName $newVnetName `
    -routeTableName $routeTableName `
    -pipName $pipName `
    -firewallAddress $firewallAddress `
    -dnsServers $dnsServers `
    -nicName $nicName `
    -vnetAddressRange $newVnetAddress `
    -startDate $startDate `
    -pm $projectManager `
    -vmName $vmName `
    -osDiskName $osDiskName `
    -nsgName $nsgName `
    -externalAccessIP $externalAccessIP `
    -dnsName $dnsName `
    -Mode Incremental #Complete
