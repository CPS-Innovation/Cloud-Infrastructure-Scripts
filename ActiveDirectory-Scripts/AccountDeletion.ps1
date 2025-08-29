# Import the Active Directory module if not already imported
Import-Module ActiveDirectory

# Define the root OU
$OU = "OU=CPS Users,DC=cps,DC=gov,DC=uk"


# Define the cutoff date (2 years ago)
$CutoffDate = (Get-Date).AddYears(-2)

# Search AD for users in the OU and sub-OUs
$deletableUsers = Get-ADUser -Filter { msExchRecipientTypeDetails -ne 34359738368 } -SearchBase $OU -SearchScope Subtree -Properties LastLogonDate, whenCreated, whenChanged |
    Where-Object {
        # Some accounts may have never logged in (LastLogonDate is $null)
        ($_.LastLogonDate -eq $null) -or ($_.LastLogonDate -lt $CutoffDate)
    }



# DELETE USERS




$date = Get-Date -Format "MM/dd/yyyy"

# Define ACS SMTP settings
$smtpServer = "smtp.azurecomm.net"
$smtpPort = 587
$username = "" # Fill in

# Get Password from Key Vault
# Get the AuthToken which we will use to access secrets within the Key Vault (the key vault contains the service account password)
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
    $password = (Invoke-RestMethod -Uri https://kv-managementsecrets.vault.azure.net/secrets/AccountDeletions-SMTP?api-version=2016-10-01 -Method GET -Headers @{Authorization="Bearer $KeyVaultToken"})
}
catch {
    LogError -message ("Failed to obtain secret - " + $_.Exception.StatusCode)
    break
}

# Email details
$from = "donotreply@notify.cps.gov.uk"
$to = "" # CGI contact to be confirmed
$subject = "CPS User account deletions "+$date
$body = "CPS User account deletions" + "`n" + $deletableUsers

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
