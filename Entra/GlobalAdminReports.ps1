Connect-MgGraph

$roleList = @("Global Administrator")

foreach($role in $roleList)
{
	$roleObject = Get-MgDirectoryRole | Where-Object {$_.DisplayName -eq $role}

	$userIds = Get-MgDirectoryRoleMember -DirectoryRoleId $roleObject.Id | Select-Object Id

	$table = @()

	foreach ($userId in $userIds)
	{
		$userObject = Get-MgUser -UserId $userId.Id
	
		$table += [PSCustomObject]@{
			DisplayName = $userObject.DisplayName
			UserPrincipalName = $userObject.UserPrincipalName
		}

	}

	Write-Host $role ($userIds.Count)

	$table | Format-Table -AutoSize
}
