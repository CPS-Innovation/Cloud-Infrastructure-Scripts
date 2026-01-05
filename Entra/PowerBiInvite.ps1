$token = (az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)
$secureToken = $token | ConvertTo-SecureString -AsPlainText -Force                                      
Connect-MgGraph -AccessToken $secureToken

New-MgInvitation -InvitedUserDisplayName "Name" -InvitedUserEmailAddress "name@herts.police.uk" -InviteRedirectUrl "https://myapplications.microsoft.com" -SendInvitationMessage:$true
