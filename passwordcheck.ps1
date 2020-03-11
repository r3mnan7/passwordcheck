# Specify script parameters
param (   
[switch] $inform
)

# Must be configured prior to running.
# When run in inform mode, a single email will be sent to the inform email. This email contains all password expiration information.
$informemail = "[EMAIL FOR SENDING INFORM REPORTS]"

# Event IDs
# 100x - Informational
# 200x - Error

# Connect to Active Directory and Pull User Expiration Dates
Import-Module ActiveDirectory # Import module for working with Active Directory

# Add the "password_check" source to the application log if it does not already exist.
if (![system.diagnostics.eventlog]::SourceExists("password_check")){
    New-EventLog -LogName Application -Source "password_check"
}

Write-EventLog -LogName "Application" -EntryType Information -Source "password_check" -EventId 1001 -Message "Attempting connection to Active Directory"

try {
    # Get an array of users who are enabled, with expiring passwords, in the specified search base.
    $users = Get-ADUser -filter 'Enabled -eq $True -and PasswordNeverExpires -eq $False' -SearchBase "OU=Users, DC=DOMAIN, DC=LOCAL" -Properties DisplayName, EmailAddress, msDS-UserPasswordExpiryTimeComputed | Select-Object DisplayName, EmailAddress, @{Name="Expiration"; Expression={[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")}} 
    Write-EventLog -LogName "Application" -EntryType Information -Source "password_check" -EventId 1002 -Message "Successfully Connected to Active Directory and Retrieved User Data"
}
catch {
    Write-EventLog -LogName "Application" -EntryType Error -Source "password_check" -EventId 2001 -Message "Something went wrong connecting to Active Directory, going back to sleep`nError Details:`n[$($_.Exception.Message)]"
    exit # Exit if a connection to AD cannot be made, no sense running the rest of the script and junk e-mails may be fired.
}

function sendmail{
    # Sends e-mail to users based on supplied parameters.
    
    param(
    # Get the information needed to craft the $message
    [string]$message,
    [string]$recipient,
    [string]$subject
    )

    try{
        # URL for mailgun API calls
        $url = "[ENTER MAILGUN URL HERE]"   
        
        # MailGun API Key, this is sensitive, do not share this.
        $auth = "[ENTER MAILGUN API KEY HERE]"
        $baseauth = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($auth))

        # Send the Base64 encoded API key in headers to authenticate API call
        $headers = @{ Authorization = "Basic $baseauth" }

        # Data needed to make the API request. 
        # These variables correspond to those of a standard email (to, from, etc...)
        $data = @{
        from = "Password Checker <[SENDER ADDRESS HERE]>"; # from = "Sender Name <sender email address>"
        to = $recipient;
        subject = $subject;
        text = $message
        }
            # Take all the information from above and build an API request.
            Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $data

    }
    
    catch{
        Write-EventLog -LogName "Application" -EntryType Error -Source "password_check" -EventId 2002 -Message "Something went wrong sending e-mail to $recipient. `nError Details:`n[$($_.Exception.Message)]"
    }
}

# Populate array with users whose passwords expire between $today and $expcheck.
try{
    Write-EventLog -LogName "Application" -EntryType Information -Source "password_check" -EventId 1004 -Message "Gathering user password expiration data."
    foreach ($user in $users){
        $today = Get-Date -DisplayHint Date
        $expcheck = $today.AddDays(7)
    
        if ($user.Expiration -le $expcheck -and $user.Expiration -ge $today){
            $expiringusers += ,@($user)
        }
    }
}
catch {
    Write-EventLog -LogName "Application" -EntryType Error -Source "password_check" -EventId 2003 -Message "Something went wrong processing data from active directory, going back to sleep now.`nError Details:`n[$($_.Exception.Message)]"
    exit # Quits script if it cannot pull this data. If not exited this may cause unneccessary e-mails to fire.
}

# Build the Inform Report for Admins
function informreport{
    Write-EventLog -LogName "Application" -EntryType Information -Source "password_check" -EventId 1005 -Message "Preparing inform report"
    $informreport = "Name`t`t`t`tExpiration Date`n"
    foreach ($user in $expiringusers){
        $informreport += $user.DisplayName + "`t`t`t" + $user.Expiration + "`n"
        
    }
    return $informreport
}

# Build message to send to user
function usermessage{
    param(
        [Parameter(Mandatory)]
        [string] $name,
        [Parameter(Mandatory)]
        [string] $expiration
    )

    Write-EventLog -LogName "Application" -EntryType Information -Source "password_check" -EventId 1006 -Message "Preparing user notification for $name"
    
    $message = "Hello $name,`n
    Your domain password (the one you use to login to your computer) is set to expire on $expiration.`n
    At your earliest convenience please change your password by logging into your computer, pressing CTL+ALT+DEL, and clicking change password`n
    Thank you very much, and if you have any questions please send them to [SUPPORT EMAIL]."

    return $message
}

if ($inform){
    # Chose not to catch errors here as the error will generate from the sendmail function.
    sendmail -Message (informreport) -Recipient $informemail -Subject "Password Expiration Report"
    Write-EventLog -LogName "Application" -EntryType Information -Source "password_check" -EventId 1007 -Message "Inform report sent to $informemail"
} elseif (!$inform) {
    foreach ($user in $expiringusers){
        # Chose not to catch errors here as the error will generate from the sendmail function.
        sendmail -Message (usermessage -Name $user.DisplayName -Expiration $user.Expiration) -Recipient $user.EmailAddress -Subject "[NOTICE] Domain Password Expiration"
        $username = $user.DisplayName
        $useremail = $user.EmailAddress
        Write-EventLog -LogName "Application" -EntryType Information -Source "password_check" -EventId 1008 -Message "User notification sent to $username at $useremail"
        
    }
}
