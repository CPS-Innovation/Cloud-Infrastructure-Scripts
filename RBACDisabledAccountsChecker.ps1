# Script Title: RBAC Disabled Accounts Cleanup
# Script Author: William Buck
# Creation Date: 07/09/2026
# Last Changed Date: 04/11/2026

<#
Description: This script scans all RBAC roles associated with the connected Azure subscription. It will pull both single entities (users and service principals) and also the groups that allow inherited permissions.
             It caches all of the results into individual arrays to simplify later processing.
             Once all roles have been scanned, it will then loop through the groups and roles and query every single entity classified as a user and pull out specific properties from the accounts.
             It will mark any where the AccountEnabled attribute is set to Disabled and store those accounts in a separate array.
             Once individual entities are complete, it will move onto looping through the groups and doing the same thing as above.
             Any user account which is disabled will then be removed from any roles it is assigned to and any of the groups that grant role assignment through inheritence.            
#>

# Version: v1.0

# CHANGE NOTES:
# ====================================================================================================================================================================
# 07/09/2026 - Initial script created
# ====================================================================================================================================================================
# 08/09/2026 - Overall framework implemented and initial testing started
# ====================================================================================================================================================================
# 09/09/2026 - Changed authentication to enterprise app using client secret for authentication. Required to be a reader of targeted subscriptions.
# ====================================================================================================================================================================
# 10/09/2026 - Additional permissions added to the enterprise app to allow for user, group and role reading. No write permissions yet as script is still in development
# ====================================================================================================================================================================
# 11/09/2026 - Fixed some bugs with property retrieval and an issue where some entities returned no display names are now filtered out.
# ====================================================================================================================================================================
# 14/09/2026 - Changed the formatting of the results to display enabled status to allow for better clarity in testing
# ====================================================================================================================================================================
# 16/09/2026 - Changed the output process to output to a xlsx file for easier validation
# ====================================================================================================================================================================
# 02/11/2026 - Amended the script so it will work correctly with Azure Automation Accounts
# ====================================================================================================================================================================
# 04/11/2026 - Commented out the xlsx generation as this is not handled correctly with Azure Automation. Leaving in for locally ran reporting purposes
# ====================================================================================================================================================================

<#
Required Modules:
Az.Accounts
Az.Resources
Microsoft.Graph.Users
Microsoft.Graph.Groups
ImportExcel
#>

# ----------------------------------------------
# Define fixed variables
# ----------------------------------------------

param(
    [string] $appID = "bd9ba6a4-a621-43ed-9249-eea823b1750c",
    [string] $tenantID = "cpsgovuk.onmicrosoft.com",
    [string] $tenantIDNum = "00dd0d1d-d7e6-4338-ac51-565339c7088c" ,
    [string] $subscriptionID = "87c7bb5c-f6a5-47c3-96cf-471f1b1c62eb"
)

# ----------------------------------------------
# Required modules check and installation
# ----------------------------------------------

$requiredModules = ("Az.Accounts", "Az.Resources", "Microsoft.Graph.Users", "Microsoft.Graph.Groups")

# Check if the required modules are installed. If not, install them.

foreach ($module in $requiredModules){
    if(Get-InstalledModule $module -ErrorAction Ignore){ #ignoring error due to an error being generated when the defined module is not found
        Write-Output "$module already installed." -ForegroundColor Green
    } else {
        Write-Output "$module not installed. Installing...." -ForegroundColor Yellow 
        Install-Module $module -Scope AllUsers -Force
    }
}

# Check if the required modules are imported. If not, import them.

foreach ($module in $requiredModules){
    if(Get-Module $module){
        Write-Output "$module already imported." -ForegroundColor Green
    } else {
        Write-Output "$module not imported. Importing...." -ForegroundColor Yellow 
        Import-Module $module -Scope Local -Force
    }
}



# ----------------------------------------------
# Connect to Graph
# ----------------------------------------------

Set-MgGraphOption -DisableLoginByWAM $true

# Convert the Client Secret to a Secure String
$GraphSecureClientSecret = ConvertTo-SecureString -String $Secret -AsPlainText -Force

# Create a PSCredential Object Using the Client ID and Secure Client Secret
$GraphClientSecretCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $appId, $GraphSecureClientSecret
# Connect to Microsoft Graph Using the Tenant ID and Client Secret Credential
Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $GraphClientSecretCredential 

Start-Sleep 5 

#Connect-MgGraph -UseDeviceCode

# ----------------------------------------------
# Connect to Azure
# ----------------------------------------------


$secureClientSecret = ConvertTo-SecureString $secret -AsPlainText -Force

$credential = New-Object System.Management.Automation.PSCredential($appId, $secureClientSecret)

Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantID -Subscription $subscriptionID

Start-Sleep 5 

#Connect-AzAccount -UseDeviceAuthentication


# ---------------------------------------------------------------------------
# Validate Azure connection and select the subscription
# ---------------------------------------------------------------------------

$azContext = Get-AzContext


if (-not $azContext) {
    throw @"
No active Azure PowerShell session was found.

Connect first using:
Connect-AzAccount -TenantId '$tenantId' -SubscriptionId '$subscriptionId' -DeviceCode
"@
}
else {
    Write-Output "Successfully connected to tenant $tenantId under subscription $subscriptionID" -ForegroundColor Green }



if (
    -not $azContext.Subscription -or
    -not $azContext.Subscription.Id
) {
    throw "The current Azure context does not contain a valid subscription."
}
else {
    Write-Output "Subscription Valid!" -ForegroundColor Green }

Write-Output ""
Write-Output "Azure context selected" -ForegroundColor Green
Write-Output "Account:      $($azContext.Account.Id)" -ForegroundColor Cyan
Write-Output "Tenant:       $($azContext.Tenant.Id)" -ForegroundColor Cyan
Write-Output "Subscription: $($azContext.Subscription.Name)" -ForegroundColor Cyan
Write-Output "ID:           $($azContext.Subscription.Id)" -ForegroundColor Cyan


# ---------------------------------------------------------------------------
# Validate Microsoft Graph connection
# ---------------------------------------------------------------------------

$mgContext = Get-MgContext

if (-not $mgContext) {
    throw @"
No active Microsoft Graph session was found.

For an interactive assessment, connect using:
Connect-MgGraph -TenantId '$tenantId' -Scopes 'User.Read.All','Group.Read.All','GroupMember.Read.All'
"@
}

if ($mgContext.TenantId -ne $tenantIdNum) {
    throw (
        "Microsoft Graph is connected to tenant '{0}', but the script is configured for tenant '{1}'." -f
        $mgContext.TenantId,
        $tenantId
    )
}
else {
    Write-Output "Graph successfully connected to Tenant!" -ForegroundColor Green }

Write-Output ""
Write-Output "Microsoft Graph context validated" -ForegroundColor Green
Write-Output "Graph account: $($mgContext.Account)" -ForegroundColor Cyan
Write-Output "Graph tenant:  $($mgContext.TenantId)" -ForegroundColor Cyan


# ---------------------------------------------------------------------------
# Retrieve all Azure Subscriptions
# ---------------------------------------------------------------------------

$subscriptions = @()

$availablesubs = Get-AzSubscription | Select-Object Name, SubscriptionId, State, TenantId

$subscriptions += [PSCustomObject]@{
        Name = $sub.Name
        SubscriptionId = $sub.SubscriptionId
        ResourceCount = $configuredResources
        }


foreach ($sub in $availablesubs){
    $subscriptions += $sub } 
    
# ---------------------------------------------------------------------------
# Create log file
# ---------------------------------------------------------------------------

$path = "C:\Temp\SubAssignmentsEUCOnlyRemovals.xlsx"

if(!(Test-Path $path)){
    New-Item -Path $path -force
    }



# ---------------------------------------------------------------------------
# Retrieve Azure RBAC role assignments from each subscription
# ---------------------------------------------------------------------------

# Store combined results from every successfully processed subscription.
$allSubscriptionFindings = @()
$allSubscriptionSummaries = @()
$subscriptionProcessingResults = @()

foreach ($permSub in $subscriptions) {

    $subscriptionId = $permSub.SubscriptionId
    $subscriptionName = $permSub.Name
    $tenantId = $permSub.TenantId

    Write-Output ""
    Write-Output "========================================" -ForegroundColor Cyan
    Write-Output "Processing subscription" -ForegroundColor Yellow
    Write-Output "========================================" -ForegroundColor Cyan
    Write-Output "Name: $subscriptionName" -ForegroundColor Cyan
    Write-Output "ID:   $subscriptionId" -ForegroundColor Cyan

    try {
        # Set-AzContext returns the context that was selected.
        $azContext = Set-AzContext `
            -SubscriptionId $subscriptionId `
            -TenantId $tenantId `
            -ErrorAction Stop

        Write-Output (
            "Connected to subscription '{0}' [{1}]" -f
            $azContext.Subscription.Name,
            $azContext.Subscription.Id
        ) -ForegroundColor Magenta
    }
    catch {
        Write-Warning (
            "Could not select subscription '{0}' [{1}]: {2}" -f
            $subscriptionName,
            $subscriptionId,
            $_.Exception.Message
        )

        $subscriptionProcessingResults += [PSCustomObject]@{
            SubscriptionName = $subscriptionName
            SubscriptionId   = $subscriptionId
            TenantId         = $tenantId
            Status           = "Context selection failed"
            AssignmentCount  = 0
            FindingCount     = 0
            ErrorMessage     = $_.Exception.Message
        }

        # Move to the next subscription instead of terminating the script.
        continue
    }

    Write-Output ""
    Write-Output (
        "Retrieving Azure RBAC assignments for subscription '{0}'..." -f
        $azContext.Subscription.Name
    ) -ForegroundColor Yellow

    try {
        $assignments = @(
            Get-AzRoleAssignment `
                -Scope "/subscriptions/$subscriptionId" `
                -ErrorAction Stop
        )
    }
    catch {
        Write-Warning (
            "Could not retrieve Azure RBAC assignments for subscription '{0}' [{1}]: {2}" -f
            $subscriptionName,
            $subscriptionId,
            $_.Exception.Message
        )

        $subscriptionProcessingResults += [PSCustomObject]@{
            SubscriptionName = $subscriptionName
            SubscriptionId   = $subscriptionId
            TenantId         = $tenantId
            Status           = "RBAC retrieval failed"
            AssignmentCount  = 0
            FindingCount     = 0
            ErrorMessage     = $_.Exception.Message
        }

        continue
    }

    if ($assignments.Count -eq 0) {
        Write-Warning (
            "No Azure RBAC assignments were returned for subscription '{0}' [{1}]." -f
            $subscriptionName,
            $subscriptionId
        )

        $subscriptionProcessingResults += [PSCustomObject]@{
            SubscriptionName = $subscriptionName
            SubscriptionId   = $subscriptionId
            TenantId         = $tenantId
            Status           = "No assignments returned"
            AssignmentCount  = 0
            FindingCount     = 0
            ErrorMessage     = $null
        }

        # Do not use return here because that exits the entire script.
        continue
    }

    Write-Output (
        "Azure RBAC assignments retrieved: {0}" -f
        $assignments.Count
    ) -ForegroundColor Green

    # Continue with the rest of your existing per-subscription processing here.


    # ---------------------------------------------------------------------------
    # Initialise caches and result arrays
    # ---------------------------------------------------------------------------

    # Caches prevent repeated Microsoft Graph queries for the same object.
    $userCache  = @{}
    $groupCache = @{}

    # Store every direct user and group Azure RBAC assignment.
    # Duplicate objects are intentionally retained where they have different
    # roles or scopes.
    $allUserAssignments  = @()
    $allGroupAssignments = @()

    # Disabled accounts discovered through RBAC-assigned groups.
    $potentialRemovals = @()

    # Final combined report of disabled accounts with direct or group-based access.
    $disabledAccountFindings = @()

    # Consolidated report containing one record per disabled user.
    $disabledUserSummary = @()

    # Prevent duplicate reporting of the same user, group, role and scope path.
    $processedMemberships = @{}


    # ---------------------------------------------------------------------------
    # Process Azure RBAC assignments
    # ---------------------------------------------------------------------------

    $assignments |
        Group-Object RoleDefinitionName |
        Sort-Object Name |
        ForEach-Object {

            $roleName        = $_.Name
            $roleAssignments = $_.Group

            Write-Output ""
            Write-Output "========================================" -ForegroundColor Cyan
            Write-Output "Role: $roleName" -ForegroundColor Yellow
            Write-Output "========================================" -ForegroundColor Cyan

            $roleOutput = foreach ($assignment in $roleAssignments) {

                $enabled = "N/A"

                switch ($assignment.ObjectType) {

                    # -----------------------------------------------------------
                    # Direct user assignment processing
                    # -----------------------------------------------------------

                    "User" {
                        try {
                            # Query Graph only if the user is not already cached.
                            if (-not $userCache.ContainsKey($assignment.ObjectId)) {

                                Write-Verbose (
                                    "Retrieving user {0}" -f
                                    $assignment.ObjectId
                                )

                                $userCache[$assignment.ObjectId] = Get-MgUser `
                                    -UserId $assignment.ObjectId `
                                    -Property "Id,DisplayName,UserPrincipalName,AccountEnabled" `
                                    -ErrorAction Stop
                            }

                            $user = $userCache[$assignment.ObjectId]

                            $enabled = if ($user.AccountEnabled -eq $true) {
                                "True"
                            }
                            elseif ($user.AccountEnabled -eq $false) {
                                "False"
                            }
                            else {
                                "Unknown"
                            }

                            # Store every direct user role assignment.
                            $allUserAssignments += [PSCustomObject]@{
                                RoleName          = $roleName
                                ObjectId          = $user.Id
                                DisplayName       = $user.DisplayName
                                UserPrincipalName = $user.UserPrincipalName
                                AccountEnabled    = $user.AccountEnabled
                                Scope             = $assignment.Scope
                            }
                        }
                        catch {
                            $enabled = "Unknown"

                            Write-Warning (
                                "Could not retrieve user '{0}' [{1}]: {2}" -f
                                $assignment.DisplayName,
                                $assignment.ObjectId,
                                $_.Exception.Message
                            )

                            # Retain unresolved assignments for visibility.
                            $allUserAssignments += [PSCustomObject]@{
                                RoleName          = $roleName
                                ObjectId          = $assignment.ObjectId
                                DisplayName       = $assignment.DisplayName
                                UserPrincipalName = $assignment.SignInName
                                AccountEnabled    = $null
                                Scope             = $assignment.Scope
                            }
                        }

                        break
                    }


                    # -----------------------------------------------------------
                    # Group assignment processing
                    # -----------------------------------------------------------

                    "Group" {
                        try {
                            # Query Graph only if the group is not already cached.
                            if (-not $groupCache.ContainsKey($assignment.ObjectId)) {

                                Write-Verbose (
                                    "Retrieving group {0}" -f
                                    $assignment.ObjectId
                                )

                                $groupCache[$assignment.ObjectId] = Get-MgGroup `
                                    -GroupId $assignment.ObjectId `
                                    -Property "Id,DisplayName,Mail,MailEnabled,SecurityEnabled" `
                                    -ErrorAction Stop
                            }

                            $group = $groupCache[$assignment.ObjectId]

                            # Only add the group when its name contains something
                            # other than spaces.
                            if (
                                $group.DisplayName -and
                                $group.DisplayName.Trim().Length -gt 0
                            ) {
                                $allGroupAssignments += [PSCustomObject]@{
                                    RoleName        = $roleName
                                    ObjectId        = $group.Id
                                    DisplayName     = $group.DisplayName
                                    Mail            = $group.Mail
                                    MailEnabled     = $group.MailEnabled
                                    SecurityEnabled = $group.SecurityEnabled
                                    Scope           = $assignment.Scope
                                }
                            }
                            else {
                                Write-Warning (
                                    "Group [{0}] assigned to role '{1}' at scope '{2}' was excluded because its display name is blank." -f
                                    $assignment.ObjectId,
                                    $roleName,
                                    $assignment.Scope
                                )
                            }
                        }
                        catch {
                            Write-Warning (
                                "Could not retrieve group '{0}' [{1}]: {2}" -f
                                $assignment.DisplayName,
                                $assignment.ObjectId,
                                $_.Exception.Message
                            )

                            # Retain fallback RBAC data only when Azure supplied
                            # a valid group display name.
                            if (
                                $assignment.DisplayName -and
                                $assignment.DisplayName.Trim().Length -gt 0
                            ) {
                                $allGroupAssignments += [PSCustomObject]@{
                                    RoleName        = $roleName
                                    ObjectId        = $assignment.ObjectId
                                    DisplayName     = $assignment.DisplayName
                                    Mail            = $null
                                    MailEnabled     = $null
                                    SecurityEnabled = $null
                                    Scope           = $assignment.Scope
                                }
                            }
                            else {
                                Write-Warning (
                                    "Unresolved group [{0}] assigned to role '{1}' at scope '{2}' was excluded because no display name was available." -f
                                    $assignment.ObjectId,
                                    $roleName,
                                    $assignment.Scope
                                )
                            }
                        }

                        break
                    }


                    # -----------------------------------------------------------
                    # Other Azure RBAC principal types
                    # -----------------------------------------------------------

                    default {
                        Write-Verbose (
                            "Skipping unsupported RBAC object type '{0}' for object [{1}]." -f
                            $assignment.ObjectType,
                            $assignment.ObjectId
                        )
                    }
                }

                # Output displayed beneath the applicable Azure RBAC role.
                [PSCustomObject]@{
                    DisplayName = $assignment.DisplayName
                    SignInName  = $assignment.SignInName
                    ObjectType  = $assignment.ObjectType
                    Enabled     = $enabled
                    Scope       = $assignment.Scope
                }
            }

            $roleOutput |
                Sort-Object DisplayName |
                Format-Table `
                    DisplayName,
                    SignInName,
                    ObjectType,
                    Enabled,
                    Scope `
                    -AutoSize
        }


    # ---------------------------------------------------------------------------
    # Initial RBAC processing summary
    # ---------------------------------------------------------------------------

    Write-Output ""
    Write-Output "========================================" -ForegroundColor Cyan
    Write-Output "RBAC assignment processing summary" -ForegroundColor Yellow
    Write-Output "========================================" -ForegroundColor Cyan

    Write-Output (
        "Unique users cached:       {0}" -f
        $userCache.Count) -ForegroundColor Green

    Write-Output (
        "User assignments stored:   {0}" -f
        $allUserAssignments.Count) -ForegroundColor Green

    Write-Output (
        "Unique groups cached:      {0}" -f
        $groupCache.Count) -ForegroundColor Green

    Write-Output (
        "Group assignments stored:  {0}" -f
        $allGroupAssignments.Count) -ForegroundColor Green


    # ---------------------------------------------------------------------------
    # Process members of groups that have Azure RBAC assignments
    # ---------------------------------------------------------------------------

    # -----------------------------------------------------------
    # Removal Control
    # $false = Report only
    # $true  = Actually remove users from groups
    # -----------------------------------------------------------
    $PerformRemoval = $false

    foreach ($newGroup in $allGroupAssignments) {

        Write-Output ""
        Write-Output (
            "Processing group: {0} | Role: {1} | Scope: {2}" -f
            $newGroup.DisplayName,
            $newGroup.RoleName,
            $newGroup.Scope
        ) -ForegroundColor Green

        try {
            $members = @(
                Get-MgGroupMember `
                    -GroupId $newGroup.ObjectId `
                    -All `
                    -ErrorAction Stop
            )

            Write-Output (
                "Members returned: {0}" -f
                $members.Count
            ) -ForegroundColor Cyan

            foreach ($member in $members) {

                Write-Output (
                    "Assessing member {0}..." -f
                    $member.Id
                ) -ForegroundColor Yellow

                try {
                    # Get-MgGroupMember returns generic directory objects.
                    # Attempt to resolve each returned object as a user.
                    if (-not $userCache.ContainsKey($member.Id)) {

                        $userCache[$member.Id] = Get-MgUser `
                            -UserId $member.Id `
                            -Property "Id,DisplayName,UserPrincipalName,AccountEnabled" `
                            -ErrorAction Stop
                    }

                    $user = $userCache[$member.Id]

                    $enabledStatus = if ($user.AccountEnabled -eq $true) {
                        "Enabled"
                    }
                    elseif ($user.AccountEnabled -eq $false) {
                        "Disabled"
                    }
                    else {
                        "Unknown"
                    }

                    Write-Output (
                        "User: {0} | UPN: {1} | Status: {2}" -f
                        $user.DisplayName,
                        $user.UserPrincipalName,
                        $enabledStatus
                    ) -ForegroundColor Yellow

                    # -----------------------------------------------------------
                    # Record disabled users found through group membership
                    # -----------------------------------------------------------

                    if ($user.AccountEnabled -eq $false) {

                        $membershipKey = "{0}|{1}|{2}|{3}" -f `
                            $newGroup.ObjectId, `
                            $user.Id, `
                            $newGroup.RoleName, `
                            $newGroup.Scope

                        if (-not $processedMemberships.ContainsKey($membershipKey)) {

                            $processedMemberships[$membershipKey] = $true

                            Write-Output (
                                "REAL-WORLD ACTION: Disabled user '{0}' would be removed from group '{1}', removing access inherited through role '{2}' at scope '{3}'." -f
                                $user.UserPrincipalName,
                                $newGroup.DisplayName,
                                $newGroup.RoleName,
                                $newGroup.Scope
                            ) -ForegroundColor Red

                            # ---------------------------------------------------
                            # Optional Removal
                            # ---------------------------------------------------
                            if ($PerformRemoval) {

                                try {
                                    Remove-MgGroupMemberByRef `
                                        -GroupId $newGroup.ObjectId `
                                        -DirectoryObjectId $user.Id `
                                        -ErrorAction Stop

                                    Write-Output (
                                        "REMOVED: {0} from {1}" -f
                                        $user.UserPrincipalName,
                                        $newGroup.DisplayName
                                    ) -ForegroundColor Magenta
                                }
                                catch {
                                    Write-Warning (
                                        "Failed to remove '{0}' from '{1}': {2}" -f
                                        $user.UserPrincipalName,
                                        $newGroup.DisplayName,
                                        $_.Exception.Message
                                    )
                                }
                            }
                            else {
                                Write-Output (
                                    "DRY RUN: Removal disabled. No changes made."
                                ) -ForegroundColor DarkYellow
                            }

                            $potentialRemovals += [PSCustomObject]@{
                                UserId            = $user.Id
                                DisplayName       = $user.DisplayName
                                UserPrincipalName = $user.UserPrincipalName
                                AccountEnabled    = $user.AccountEnabled
                                GroupId           = $newGroup.ObjectId
                                GroupName         = $newGroup.DisplayName
                                RoleName          = $newGroup.RoleName
                                Scope             = $newGroup.Scope
                                ProposedAction    = if ($PerformRemoval) {
                                    "Removed disabled user from group"
                                }
                                else {
                                    "Remove disabled user from group"
                                }
                            }
                        }
                        else {
                            Write-Output (
                                "This disabled user access path has already been reported."
                            ) -ForegroundColor DarkGray
                        }
                    }
                }
                catch {
                    Write-Warning (
                        "Member [{0}] could not be resolved as a user: {1}" -f
                        $member.Id,
                        $_.Exception.Message
                    )
                }
            }
        }
        catch {
            Write-Warning (
                "Could not retrieve members of group '{0}' [{1}]: {2}" -f
                $newGroup.DisplayName,
                $newGroup.ObjectId,
                $_.Exception.Message
            )
        }
    }


    # ---------------------------------------------------------------------------
    # Add directly assigned disabled users to the combined findings
    # ---------------------------------------------------------------------------

    $directDisabledUsers = @(
        $allUserAssignments |
            Where-Object {
                $_.AccountEnabled -eq $false
            }
    )

    foreach ($directUser in $directDisabledUsers) {

        Write-Output (
            "REAL-WORLD ACTION: Disabled user '{0}' would have direct role '{1}' removed at scope '{2}'." -f
            $directUser.UserPrincipalName,
            $directUser.RoleName,
            $directUser.Scope
        ) -ForegroundColor Red

        # -----------------------------------------------------------
        # Optional Removal
        # -----------------------------------------------------------
        if ($PerformRemoval) {

            try {

                Remove-AzRoleAssignment `
                    -ObjectId $directUser.ObjectId `
                    -RoleDefinitionName $directUser.RoleName `
                    -Scope $directUser.Scope `
                    -ErrorAction Stop

                Write-Output (
                    "REMOVED: Direct role '{0}' from '{1}' at scope '{2}'." -f
                    $directUser.RoleName,
                    $directUser.UserPrincipalName,
                    $directUser.Scope
                ) -ForegroundColor Magenta
            }
            catch {
                Write-Warning (
                    "Failed to remove direct role assignment for '{0}': {1}" -f
                    $directUser.UserPrincipalName,
                    $_.Exception.Message
                )
            }
        }
        else {
            Write-Output (
                "DRY RUN: Direct role removal disabled. No changes made."
            ) -ForegroundColor DarkYellow
        }

        $disabledAccountFindings += [PSCustomObject]@{
            UserId            = $directUser.ObjectId
            DisplayName       = $directUser.DisplayName
            UserPrincipalName = $directUser.UserPrincipalName
            AccountEnabled    = $directUser.AccountEnabled
            AccessType        = "Direct role assignment"
            GroupId           = $null
            GroupName         = $null
            RoleName          = $directUser.RoleName
            Scope             = $directUser.Scope
            ProposedAction    = if ($PerformRemoval) {
                "Removed direct Azure RBAC role assignment"
            }
            else {
                "Remove direct Azure RBAC role assignment"
            }
        }
    }


    # ---------------------------------------------------------------------------
    # Add group-based disabled users to the combined findings
    # ---------------------------------------------------------------------------

    foreach ($groupUser in $potentialRemovals) {

        $disabledAccountFindings += [PSCustomObject]@{
            UserId            = $groupUser.UserId
            DisplayName       = $groupUser.DisplayName
            UserPrincipalName = $groupUser.UserPrincipalName
            AccountEnabled    = $groupUser.AccountEnabled
            AccessType        = "Group membership"
            GroupId           = $groupUser.GroupId
            GroupName         = $groupUser.GroupName
            RoleName          = $groupUser.RoleName
            Scope             = $groupUser.Scope
            ProposedAction    = "Remove disabled user from group"
        }
    }


    # ---------------------------------------------------------------------------
    # Calculate finding counts
    # ---------------------------------------------------------------------------

    $uniqueDisabledUsers = @(
        $disabledAccountFindings |
            Group-Object UserId |
            ForEach-Object {
                $_.Group |
                    Select-Object -First 1
            }
    )

    $directAssignmentCount = @(
        $disabledAccountFindings |
            Where-Object {
                $_.AccessType -eq "Direct role assignment"
            }
    ).Count

    $groupAccessCount = @(
        $disabledAccountFindings |
            Where-Object {
                $_.AccessType -eq "Group membership"
            }
    ).Count


    # ---------------------------------------------------------------------------
    # Display every disabled account access path
    # ---------------------------------------------------------------------------

    Write-Output ""
    Write-Output "========================================" -ForegroundColor Cyan
    Write-Output "Disabled accounts with Azure RBAC access" -ForegroundColor Yellow
    Write-Output "========================================" -ForegroundColor Cyan

    if ($disabledAccountFindings.Count -gt 0) {

        Write-Output (
            "Unique disabled users identified: {0}" -f
            $uniqueDisabledUsers.Count
        ) -ForegroundColor Red

        Write-Output (
            "Disabled direct role assignments: {0}" -f
            $directAssignmentCount
        ) -ForegroundColor Red

        Write-Output (
            "Disabled group-based access paths: {0}" -f
            $groupAccessCount
        ) -ForegroundColor Red

        Write-Output (
            "Total disabled account access paths: {0}" -f
            $disabledAccountFindings.Count
        ) -ForegroundColor Red

        Write-Output ""
        Write-Output (
            "REAL-WORLD ACTION: Any roles or group found will be removed from the disabled accounts."
        ) -ForegroundColor Red

        Write-Output ""
        Write-Output "All disabled account access paths" -ForegroundColor Yellow

        $disabledAccountFindings |
            Sort-Object `
                DisplayName,
                AccessType,
                GroupName,
                RoleName,
                Scope |
            Format-Table `
                DisplayName,
                UserPrincipalName,
                AccessType,
                GroupName,
                RoleName,
                Scope,
                ProposedAction `
                -AutoSize
    }
    else {
        Write-Output (
            "No disabled accounts were found with direct or group-based Azure RBAC access."
        ) -ForegroundColor Green
    }


    # ---------------------------------------------------------------------------
    # Build one consolidated record per disabled user
    # ---------------------------------------------------------------------------

    if ($disabledAccountFindings.Count -gt 0) {

        $disabledUserSummary = @(
            $disabledAccountFindings |
                Group-Object UserId |
                ForEach-Object {

                    $userFindings = @($_.Group)

                    $firstFinding = $userFindings |
                        Select-Object -First 1

                    $accessTypes = @(
                        $userFindings.AccessType |
                            Where-Object {
                                $_ -and $_.Trim().Length -gt 0
                            } |
                            Sort-Object -Unique
                    )

                    $roles = @(
                        $userFindings.RoleName |
                            Where-Object {
                                $_ -and $_.Trim().Length -gt 0
                            } |
                            Sort-Object -Unique
                    )

                    $groups = @(
                        $userFindings.GroupName |
                            Where-Object {
                                $_ -and $_.Trim().Length -gt 0
                            } |
                            Sort-Object -Unique
                    )

                    $scopes = @(
                        $userFindings.Scope |
                            Where-Object {
                                $_ -and $_.Trim().Length -gt 0
                            } |
                            Sort-Object -Unique
                    )

                    [PSCustomObject]@{
                        DisplayName       = $firstFinding.DisplayName
                        UserPrincipalName = $firstFinding.UserPrincipalName
                        UserId            = $firstFinding.UserId
                        AccountEnabled    = $firstFinding.AccountEnabled
                        AccessPathCount   = $userFindings.Count
                        AccessTypes       = $accessTypes -join ", "
                        Roles             = $roles -join ", "
                        Groups            = $groups -join ", "
                        Scopes            = $scopes -join ", "
                    }
                }
        )


        # -----------------------------------------------------------------------
        # Display the consolidated disabled-user summary
        # -----------------------------------------------------------------------

        Write-Output ""
        Write-Output "========================================" -ForegroundColor Cyan
        Write-Output "Unique disabled user summary" -ForegroundColor Yellow
        Write-Output "========================================" -ForegroundColor Cyan

        $disabledUserSummary |
            Sort-Object DisplayName |
            Format-Table `
                DisplayName,
                UserPrincipalName,
                AccessPathCount,
                AccessTypes,
                Roles,
                Groups `
                -AutoSize
    }


    $rolesSearched = @(
        $assignments.RoleDefinitionName |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    Write-Output ""
    Write-Output "Azure RBAC roles searched:" -ForegroundColor Cyan

    foreach ($role in $rolesSearched) {
        Write-Output "  - $role" -ForegroundColor DarkCyan
    }

    Write-Output ""
    Write-Output (
        "Total unique Azure RBAC roles searched: {0}" -f
        $rolesSearched.Count
    ) -ForegroundColor Cyan

       # ---------------------------------------------------------------------------
    # Add this subscription's findings to the combined report
    # ---------------------------------------------------------------------------

    if ($disabledAccountFindings.Count -gt 0) {
        $allSubscriptionFindings += $disabledAccountFindings
    }

    if ($disabledUserSummary.Count -gt 0) {
        $allSubscriptionSummaries += $disabledUserSummary
    }

    $subscriptionProcessingResults += [PSCustomObject]@{
        SubscriptionName = $subscriptionName
        SubscriptionId   = $subscriptionId
        TenantId         = $tenantId
        Status           = "Successfully processed"
        AssignmentCount  = $assignments.Count
        FindingCount     = $disabledAccountFindings.Count
        ErrorMessage     = $null
    }

    Write-Output ""
    Write-Output (
        "Completed subscription '{0}'. Moving to the next subscription." -f
        $subscriptionName
    ) -ForegroundColor Green

} # End foreach subscription

# ---------------------------------------------------------------------------
# Combined multi-subscription results
# ---------------------------------------------------------------------------

Write-Output ""
Write-Output "========================================" -ForegroundColor Cyan
Write-Output "Multi-subscription processing summary" -ForegroundColor Yellow
Write-Output "========================================" -ForegroundColor Cyan

$subscriptionProcessingResults |
    Sort-Object SubscriptionName |
    Format-Table `
        SubscriptionName,
        SubscriptionId,
        Status,
        AssignmentCount,
        FindingCount,
        ErrorMessage `
        -AutoSize

$successfullyProcessedCount = @(
    $subscriptionProcessingResults |
        Where-Object {
            $_.Status -eq "Successfully processed"
        }
).Count

Write-Output ""
Write-Output (
    "Subscriptions checked: {0}" -f
    $subscriptionProcessingResults.Count
) -ForegroundColor Cyan

Write-Output (
    "Subscriptions successfully processed: {0}" -f
    $successfullyProcessedCount
) -ForegroundColor Green

Write-Output (
    "Total disabled account access paths found: {0}" -f
    $allSubscriptionFindings.Count
) -ForegroundColor Red


# ---------------------------------------------------------------------------
# Build a unique disabled-user report across all subscriptions
# ---------------------------------------------------------------------------

$uniqueDisabledUsers = @(
    $allSubscriptionFindings |
        Group-Object UserId |
        ForEach-Object {

            $userFindings = @($_.Group)
            $firstFinding = $userFindings | Select-Object -First 1

            $subscriptionNames = @(
                $userFindings.SubscriptionName |
                    Where-Object {
                        $_ -and $_.Trim().Length -gt 0
                    } |
                    Sort-Object -Unique
            )

            $subscriptionIds = @(
                $userFindings.SubscriptionId |
                    Where-Object {
                        $_ -and $_.Trim().Length -gt 0
                    } |
                    Sort-Object -Unique
            )

            $accessTypes = @(
                $userFindings.AccessType |
                    Where-Object {
                        $_ -and $_.Trim().Length -gt 0
                    } |
                    Sort-Object -Unique
            )

            $roles = @(
                $userFindings.RoleName |
                    Where-Object {
                        $_ -and $_.Trim().Length -gt 0
                    } |
                    Sort-Object -Unique
            )

            $groups = @(
                $userFindings.GroupName |
                    Where-Object {
                        $_ -and $_.Trim().Length -gt 0
                    } |
                    Sort-Object -Unique
            )

            $scopes = @(
                $userFindings.Scope |
                    Where-Object {
                        $_ -and $_.Trim().Length -gt 0
                    } |
                    Sort-Object -Unique
            )

            [PSCustomObject]@{
                DisplayName       = $firstFinding.DisplayName
                UserPrincipalName = $firstFinding.UserPrincipalName
                UserId            = $firstFinding.UserId
                AccountEnabled    = $firstFinding.AccountEnabled
                AccessPathCount   = $userFindings.Count
                SubscriptionCount = $subscriptionIds.Count
                Subscriptions     = $subscriptionNames -join "; "
                SubscriptionIds   = $subscriptionIds -join "; "
                AccessTypes       = $accessTypes -join "; "
                Roles             = $roles -join "; "
                Groups            = $groups -join "; "
                Scopes            = $scopes -join "; "
            }
        }
)

# ---------------------------------------------------------------------------
# Build affected Azure RBAC scope and resource summary
# ---------------------------------------------------------------------------

$affectedResourceSummary = @(
    $allSubscriptionFindings |
        Group-Object {
            "{0}|{1}|{2}" -f
                $_.SubscriptionId,
                $_.Scope,
                $_.RoleName
        } |
        ForEach-Object {

            $scopeFindings = @($_.Group)
            $firstFinding = $scopeFindings | Select-Object -First 1

            # Disabled users with direct role assignments.
            $directFindings = @(
                $scopeFindings |
                    Where-Object {
                        $_.AccessType -eq "Direct role assignment"
                    }
            )

            # Disabled users receiving access through group membership.
            $groupFindings = @(
                $scopeFindings |
                    Where-Object {
                        $_.AccessType -eq "Group membership"
                    }
            )

            # Unique groups containing at least one disabled account.
            $affectedGroups = @(
                $groupFindings |
                    Where-Object {
                        $_.GroupId
                    } |
                    Group-Object GroupId |
                    ForEach-Object {
                        $_.Group |
                            Select-Object -First 1
                    }
            )

            $groupNames = @(
                $affectedGroups.GroupName |
                    Where-Object {
                        $_ -and $_.Trim().Length -gt 0
                    } |
                    Sort-Object -Unique
            )

            # Unique disabled users with direct access at this role and scope.
            $uniqueDirectUsers = @(
                $directFindings |
                    Where-Object {
                        $_.UserId
                    } |
                    Group-Object UserId
            )

            # Unique disabled users with group-based access at this role and scope.
            $uniqueGroupUsers = @(
                $groupFindings |
                    Where-Object {
                        $_.UserId
                    } |
                    Group-Object UserId
            )

            # Unique disabled users across both access types.
            $uniqueAffectedUsers = @(
                $scopeFindings |
                    Where-Object {
                        $_.UserId
                    } |
                    Group-Object UserId
            )

            # Determine the type and name of the affected RBAC scope.
            $scopeType = "Unknown"
            $resourceName = $null
            $resourceGroupName = $null

            if (
                $firstFinding.Scope -match
                "^/subscriptions/[^/]+$"
            ) {
                $scopeType = "Subscription"
                $resourceName = $firstFinding.SubscriptionName
            }
            elseif (
                $firstFinding.Scope -match
                "^/subscriptions/[^/]+/resourceGroups/([^/]+)$"
            ) {
                $scopeType = "Resource group"
                $resourceGroupName = $Matches[1]
                $resourceName = $Matches[1]
            }
            elseif (
                $firstFinding.Scope -match
                "^/subscriptions/[^/]+/resourceGroups/([^/]+)/providers/.+$"
            ) {
                $scopeType = "Resource"
                $resourceGroupName = $Matches[1]

                $scopeParts = @(
                    $firstFinding.Scope -split "/" |
                        Where-Object {
                            $_ -and $_.Trim().Length -gt 0
                        }
                )

                if ($scopeParts.Count -gt 0) {
                    $resourceName = $scopeParts[-1]
                }
            }
            elseif (
                $firstFinding.Scope -match
                "^/providers/Microsoft.Management/managementGroups/([^/]+)$"
            ) {
                $scopeType = "Management group"
                $resourceName = $Matches[1]
            }

            [PSCustomObject]@{
                Subscription                = $firstFinding.SubscriptionName
                SubscriptionId              = $firstFinding.SubscriptionId
                ScopeType                    = $scopeType
                ResourceGroup                = $resourceGroupName
                Resource                     = $resourceName
                Scope                        = $firstFinding.Scope
                Role                         = $firstFinding.RoleName
                Groups                       = $groupNames -join "; "
                AffectedGroupCount           = $affectedGroups.Count
                GroupAssignedDisabledUsers   = $uniqueGroupUsers.Count
                DirectlyAssignedDisabledUsers = $uniqueDirectUsers.Count
                TotalUniqueDisabledUsers     = $uniqueAffectedUsers.Count
                TotalAccessPaths             = $scopeFindings.Count
            }
        } |
        Sort-Object `
            Subscription,
            Scope,
            Role
)

# ---------------------------------------------------------------------------
# Display combined findings
# ---------------------------------------------------------------------------

if ($allSubscriptionFindings.Count -gt 0) {

    Write-Output ""
    Write-Output "Combined findings from all subscriptions" -ForegroundColor Yellow


    $allSubscriptionFindings |
        Sort-Object `
            SubscriptionName,
            DisplayName,
            AccessType,
            RoleName |
        Format-Table `
            SubscriptionName,
            DisplayName,
            UserPrincipalName,
            AccessType,
            GroupName,
            RoleName,
            Scope `
            -AutoSize

    Write-Output ""
    Write-Output (
        "Unique disabled users found: {0}" -f
        $uniqueDisabledUsers.Count
    ) -ForegroundColor Red

    Write-Output ""
    Write-Output "Unique disabled users" -ForegroundColor Yellow

    $uniqueDisabledUsers |
        Sort-Object DisplayName |
        Format-Table `
            DisplayName,
            UserPrincipalName,
            AccessPathCount,
            SubscriptionCount,
            Subscriptions,
            AccessTypes,
            Roles,
            Groups `
            -AutoSize

Write-Output ""
Write-Output "========================================" -ForegroundColor Cyan
Write-Output "Affected Azure RBAC scopes and resources" -ForegroundColor Yellow
Write-Output "========================================" -ForegroundColor Cyan

if ($affectedResourceSummary.Count -gt 0) {

    $affectedResourceSummary |
        Format-Table `
            Subscription,
            ScopeType,
            Resource,
            Role,
            AffectedGroupCount,
            GroupAssignedDisabledUsers,
            DirectlyAssignedDisabledUsers,
            TotalUniqueDisabledUsers `
            -AutoSize

    Write-Output ""
    Write-Output (
        "Affected role and scope combinations: {0}" -f
        $affectedResourceSummary.Count
    ) -ForegroundColor Red
}
else {
    Write-Output (
        "No affected Azure RBAC scopes or resources were identified."
    ) -ForegroundColor Green
}

<#
    # -----------------------------------------------------------------------
    # Export the Excel workbook
    # -----------------------------------------------------------------------

    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        throw (
            "The ImportExcel PowerShell module is required. " +
            "Install it by running: Install-Module ImportExcel -Scope CurrentUser"
        )
    }

    Import-Module ImportExcel -ErrorAction Stop

    # The path must use the .xlsx extension.
    $excelPath = $path

    if ([System.IO.Path]::GetExtension($excelPath) -ne ".xlsx") {
        $excelPath = [System.IO.Path]::ChangeExtension(
            $excelPath,
            ".xlsx"
        )
    }

    # Remove the previous report so that old worksheets or data are not retained.
    if (Test-Path -Path $excelPath) {
        Remove-Item -Path $excelPath -Force
    }

    # Sheet 1: Every disabled account access path.
    $allSubscriptionFindings |
        Sort-Object `
            SubscriptionName,
            DisplayName,
            AccessType,
            RoleName,
            Scope |
        Export-Excel `
            -Path $excelPath `
            -WorksheetName "All Access Paths" `
            -TableName "AllAccessPaths" `
            -TableStyle Medium2 `
            -AutoSize `
            -AutoFilter `
            -FreezeTopRow

    # Sheet 2: One record for each unique disabled user.
    $uniqueDisabledUsers |
        Sort-Object DisplayName |
        Export-Excel `
            -Path $excelPath `
            -WorksheetName "Unique Disabled Users" `
            -TableName "UniqueDisabledUsers" `
            -TableStyle Medium4 `
            -AutoSize `
            -AutoFilter `
            -FreezeTopRow `
            -Append

    # Sheet 3: Status of each subscription processed.
    $subscriptionProcessingResults |
        Sort-Object SubscriptionName |
        Export-Excel `
            -Path $excelPath `
            -WorksheetName "Processing Summary" `
            -TableName "ProcessingSummary" `
            -TableStyle Medium9 `
            -AutoSize `
            -AutoFilter `
            -FreezeTopRow `
            -Append

    # Sheet 4: Azure scopes and resources with disabled account access.
    $affectedResourceSummary |
        Export-Excel `
            -Path $excelPath `
            -WorksheetName "Affected RBAC Resources" `
            -TableName "AffectedRbacResources" `
            -TableStyle Medium6 `
            -AutoSize `
            -AutoFilter `
            -FreezeTopRow `
            -Append

    Write-Output ""
    Write-Output (
        "Excel report exported to: {0}" -f
        $excelPath
    ) -ForegroundColor Green

    Write-Output "Worksheets created:" -ForegroundColor Cyan
    Write-Output "  - All Access Paths" -ForegroundColor DarkCyan
    Write-Output "  - Unique Disabled Users" -ForegroundColor DarkCyan
    Write-Output "  - Processing Summary" -ForegroundColor DarkCyan
    Write-Output "  - Affected RBAC Resources" -ForegroundColor DarkCyan
}
#>
else {
    Write-Output (
        "No disabled accounts with Azure RBAC access were found across the processed subscriptions."
    ) -ForegroundColor Green
}
}