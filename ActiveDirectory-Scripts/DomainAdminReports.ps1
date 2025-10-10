Import-Module ActiveDirectory -ErrorAction Stop

$Server = "cps.gov.uk"
$TargetGroup = "Domain Admins"

# Hashtable: group DN -> list of direct members
$groupMembers = @{}

# Hashtable: user DN -> the first group (lowest-level) that links them to Domain Admins
$userSourceGroup = @{}

# Queue of group DNs to process
$queue = New-Object System.Collections.Queue

# Start with Domain Admins
$startGroup = Get-ADGroup -Server $Server -Identity $TargetGroup
$queue.Enqueue(@{
    GroupDN = $startGroup.DistinguishedName
    GroupName = $startGroup.Name
})

# Traverse nested groups
while ($queue.Count -gt 0) {
    $current = $queue.Dequeue()
    $groupDN = $current.GroupDN
    $groupName = $current.GroupName

    if (-not $groupMembers.ContainsKey($groupDN)) {
        $members = Get-ADGroupMember -Server $Server -Identity $groupDN -ErrorAction SilentlyContinue
        $groupMembers[$groupDN] = $members
    } else {
        $members = $groupMembers[$groupDN]
    }

    foreach ($member in $members) {
        switch ($member.ObjectClass) {
            'user' {
                if (-not $userSourceGroup.ContainsKey($member.DistinguishedName)) {
                    $userSourceGroup[$member.DistinguishedName] = $groupName
                }
            }
            'group' {
                $queue.Enqueue(@{
                    GroupDN = $member.DistinguishedName
                    GroupName = $member.Name
                })
            }
        }
    }
}

# Format results into a string
$resultLines = foreach ($userDN in $userSourceGroup.Keys) {
    $user = Get-ADUser -Server $Server -Identity $userDN -Properties SamAccountName -ErrorAction SilentlyContinue
    if ($user) {
        "$($user.SamAccountName) - via $($userSourceGroup[$userDN])"
    }
}

# Output to console
$domainstring = $resultLines -join "`n"

$enterprise = Get-ADGroupMember -Server "cps.gov.uk" -Identity "Enterprise Admins" -Recursive

$enterprisestring = ($enterprise.Name) -join "`n"

$schema = Get-ADGroupMember -Server "cps.gov.uk" -Identity "Schema Admins" -Recursive

$schemastring = ($schema.Name) -join "`n"


$date = Get-Date -Format "MM/dd/yyyy"

# Define ACS SMTP settings
$smtpServer = "smtp.azurecomm.net"
$smtpPort = 587
$username = "CPS-ACS-Platform.3c1da28c-0b97-4c23-82f0-25c62adbd298.00dd0d1d-d7e6-4338-ac51-565339c7088c"

# Get Password from Key Vault
#Get the AuthToken which we will use to access secrets within the Key Vault (the key vault contains the service account password)
try {
  $Response = Invoke-RestMethod -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -Method GET -Headers @{Metadata="true"}
  $KeyVaultToken = $Response.access_token
}
catch {
    LogError -message "Failed to recieve AuthToken for Azure Key Vault"
    break
}


#Use the AuthToken to access the service account password from the Key Vault
#Note: The FQDN used in this request is currently configured within the host file of the server
try {
    $password = (Invoke-RestMethod -Uri https://kv-managementsecrets.vault.azure.net/secrets/DomainAdminReports-SMTP?api-version=2016-10-01 -Method GET -Headers @{Authorization="Bearer $KeyVaultToken"})
}
catch {
    LogError -message ("Failed to obtain secret - " + $_.Exception.StatusCode)
    break
}

# Email details
$from = "donotreply@notify.cps.gov.uk"
$to = "cpscybersecurityteam@cps.gov.uk"
$subject = "Domain Admins "+$date
$body = "Domain Admins: (Count: " + $domain.Count + ")" + "`n" + $domainstring + "`n`n" + "Enterpise Admins: " + "`n" + $enterprisestring + "`n`n" + "Schema Admins: " + "`n" + $schemastring

# Create credentials object
$securePassword = ConvertTo-SecureString $password.value -AsPlainText -Force
$credentials = New-Object System.Management.Automation.PSCredential($username, $securePassword)

# Create the mail message
$message = New-Object System.Net.Mail.MailMessage $from, $to, $subject, $body
$message.IsBodyHtml = $false

# Create SMTP client and send
$smtp = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)
$smtp.EnableSsl = $true
$smtp.Credentials = $credentials

try {
    $smtp.Send($message)
    Write-Host "Email sent successfully."
} catch {
    Write-Error "Failed to send email: $_"
}
