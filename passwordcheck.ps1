# Specify script parameters
param (   
[switch] $inform,
[string] $test
)

# Must be configured prior to running.
# When run in inform mode, a single email will be sent to the inform email. This email contains all password expiration information.
$informemail = "changeme@blahblahblah.org"

# Event IDs
# 100x - Informational
# 200x - Error

# Connect to Active Directory and Pull User Expiration Dates
Import-Module ActiveDirectory # Import module for working with Active Directory

if (![system.diagnostics.eventlog]::SourceExists("password_remind.ps1")){
    New-EventLog -LogName Application -Source "password_remind.ps1"
}

Write-EventLog -LogName "Application" -EntryType Information -Source "password_remind.ps1" -EventId 1001 -Message "Attempting connection to Active Directory"

try {
    # Get an array of users who are enabled, with expiring passwords, in the specified search base.
    # Users will not be added if they do not have a DisplayName, ExpirationDate, or E-Mail Address (in the mail attribute).
    $users = @()
	foreach ($user in Get-ADUser -filter {Enabled -eq $True -and PasswordNeverExpires -eq $False} -Properties "DisplayName", "mail", "msDS-UserPasswordExpiryTimeComputed" | Select-Object -Property "Displayname","mail", @{Name="ExpiryDate";Expression={[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")}}){
		if ($user.Displayname -And $user.ExpiryDate -And $user.mail){
			$users += $user
		}
	}
    Write-EventLog -LogName "Application" -EntryType Information -Source "password_remind.ps1" -EventId 1002 -Message "Successfully Connected to Active Directory and Retrieved User Data: $users"
}
catch {
    Write-EventLog -LogName "Application" -EntryType Error -Source "password_remind.ps1" -EventId 2001 -Message "Something went wrong connecting to Active Directory, going back to sleep`nError Details:`n[$($_.Exception.Message)]"
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
        $url = "Mailgun API URL"   
        
        # MailGun API Key, this is sensitive, do not share this.
        $auth = "API KEY HERE"
        $baseauth = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($auth))

        # Send the Base64 encoded API key in headers to authenticate API call
        $headers = @{ Authorization = "Basic $baseauth" }

        # Data needed to make the API request. 
        # These variables correspond to those of a standard email (to, from, etc...)
        $data = @{
        from = "Password Checker <postmaster@noreply.com>"; # from = "Sender Name <sender email address>"
        to = $recipient;
        subject = $subject;
        text = $message
        }

            # Take all the information from above and build an API request.
            Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $data
    }
    
    catch{
        Write-EventLog -LogName "Application" -EntryType Error -Source "password_remind.ps1" -EventId 2002 -Message "Something went wrong sending e-mail to $recipient. `nError Details:`n[$($_.Exception.Message)]"
    }
}

# Populate array with users whose passwords expire between $today and $expcheck.
try{
    Write-EventLog -LogName "Application" -EntryType Information -Source "password_remind.ps1" -EventId 1003 -Message "Gathering user password expiration data."
    foreach ($user in $users){
        $expcheckdate = (Get-Date).AddDays(7)
    
        if ($user.ExpiryDate -le $expcheckdate -and $user.ExpiryDate -ge (Get-Date)){
            $expiringusers += ,@($user)
        }
    }
}
catch {
    Write-EventLog -LogName "Application" -EntryType Error -Source "password_remind.ps1" -EventId 2003 -Message "Something went wrong processing data from active directory, going back to sleep now.`nError Details:`n[$($_.Exception.Message)]"
    exit # Quits script if it cannot pull this data. If not exited this may cause unneccessary e-mails to fire.
}

# Build the Inform Report for Admins
function informreport{
    Write-EventLog -LogName "Application" -EntryType Information -Source "password_remind.ps1" -EventId 1005 -Message "Preparing inform report"
    $informreport = "Name`t`t`t`tExpiration Date`n"
    foreach ($user in $expiringusers){
        $informreport += $user.DisplayName + "`t`t`t" + $user.ExpiryDate + "`n"
        
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

    Write-EventLog -LogName "Application" -EntryType Information -Source "password_remind.ps1" -EventId 1006 -Message "Preparing user notification for $name"
    
    $message = "Hello $name,`n
    Your domain password (the one you use to login to your computer) is set to expire on $expiration.`n
    If your password expires you will be unable to login to your computer, the VPN, or Office 365.`n
    If you are not in the office MAKE SURE YOU LOGIN TO THE VPN BEFORE RESETTING YOUR PASSWORD in order to avoid further issues`n
    At your earliest convenience please change your password by logging into your computer, pressing CTL+ALT+DEL, and clicking change password`n
    Thank you very much, and if you have any questions please send them to supportemail@genericdomain.io.`n`n- Password Checker"

    return $message
}

if ($inform){
    # Chose not to catch errors here as the error will generate from the sendmail function.
    sendmail -Message (informreport) -Recipient $informemail -Subject "Password Expiration Report"
    Write-EventLog -LogName "Application" -EntryType Information -Source "password_remind.ps1" -EventId 1007 -Message "Inform report sent to $informemail"
} elseif ($test) {
    # Chose not to catch errors here as the error will generate from the sendmail function.
    Write-Host "Sending test e-mail to $test"
    sendmail -Message (usermessage -Name "Test User" -Expiration (Get-Date)) -Recipient $test -Subject "[NOTICE] Domain Password Expiration TEST"
} elseif (!$inform) {
    foreach ($user in $expiringusers){
        # Chose not to catch errors here as the error will generate from the sendmail function.
        sendmail -Message (usermessage -Name $user.DisplayName -Expiration $user.ExpiryDate) -Recipient $user.mail -Subject "[NOTICE] Domain Password Expiration"
        $username = $user.DisplayName
        $useremail = $user.mail
        Write-EventLog -LogName "Application" -EntryType Information -Source "password_remind.ps1" -EventId 1008 -Message "User notification sent to $username at $useremail"
        
}}