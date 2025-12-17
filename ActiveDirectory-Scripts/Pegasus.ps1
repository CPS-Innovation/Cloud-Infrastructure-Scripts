#################################################
#      Name: Pegasus                            #
#      Author: Tom Schoolar                     #
#      Date: 17/12/2025                         #
#      Version: 1.0                             #
#                                               #
#################################################

$groupName = "CPS NetApp Storage DID"

$didUsers = get-aduser -filter {(Department -like '*DID*') -and (Enabled -eq $True) } -properties SamAccountName

$currentUsersInAccessGroup = Get-ADGroupMember $groupName | Select-Object SamAccountName
$desiredUsersInAccessGroup = $didUsers

$usersToBeAdded     = $desiredUsersInAccessGroup | Where-Object { $_.SamAccountName -notin $currentUsersInAccessGroup.SamAccountName }
$usersToBeRemoved   = $currentUsersInAccessGroup | Where-Object { $_.SamAccountName -notin $desiredUsersInAccessGroup.SamAccountName }


if($usersToBeAdded -ne $null)
{
    Write-Host "Users to be added - Count $($usersToBeAdded.Count)"
    Write-Host $usersToBeAdded
    Add-ADGroupMember $groupName -Members $usersToBeAdded
}
else 
{
    Write-Host "Users to be added - None"
}

if($usersToBeRemoved -ne $null)
{
    Write-Host "Users to be removed - Count $($usersToBeRemoved.Count)"
    Write-Host $usersToBeRemoved
    Remove-ADGroupMember $groupName -Members $usersToBeRemoved -Confirm:$false
}
else 
{
    Write-Host "Users to be removed - None"
}
