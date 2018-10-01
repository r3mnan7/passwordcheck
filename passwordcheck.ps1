# To test this script run from powershell terminal: "./passwordcheck.ps1 -debug $true"
# To run on a regular interval setup a scheduled task (I would recommend on DC) to run at your interval, and run the script with powershell with the debug param $false

param ( [bool]$debug )

# Get list of users from -SearchBase OU
$users = Get-ADUser -Filter * -SearchBase "OU=USERS, DC=MYDC, DC=LOCAL" -Property passwordlastset, mail | select name, mail, passwordlastset

# Get todays date
$today = Get-Date

# This function sends an e-mail to $email with $message as the body text
function sendmail{

    param(

    # Get the information needed to craft the $message
    [string]$name,
    [string]$email,
    [string]$expiration

    )

    $message = "Hello $name,

        I am here to inform you that your domain password (the one you use to login to your computer) is set to expire on $expiration.

        If you are not in the office MAKE SURE YOU LOGIN TO THE VPN BEFORE RESETTING YOUR PASSWORD.
        
        At your earliest convenience please change that password by logging into your computer, pressing CTL+ALT+DEL, and clicking change password

        Thank you very much, and if you have any questions please send them to [e-mail address].

    Password Bot"

    # URL for mailgun API calls
    $url = "[ENTER YOUR MAILGUN URL HERE]"   
    
    # MailGun API Key, this is sensitive, do not share this.
    $auth = "api:[ENTER YOU API KEY HERE]"
    $baseauth = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($auth))

    # Send the Base64 encoded API key in headers to authenticate API call
    $headers = @{ Authorization = "Basic $baseauth" }

    # Data needed to make the API request. 
    # These variables correspond to those of a standard email (to, from, etc...)
    $data = @{
      from = "Password Bot <[MAILGUN EMAIL ADDRESS HERE]"; # from = "Sender Name <sender email address>"
	    to = $email;
	    subject = "Domain Password Expiration Notice";
	    text = $message
        }

        # Take all the information from above and build an API request.
        Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $data

}

# If script is called in debug mode
if($debug -eq $True){

    write-host "Debug Mode"

    # Ask the user for an e-mail to send the debug message to
    $debug_email = Read-Host "Enter e-mail to send test message: "

    # Send the debug message to the specified address
    sendmail -name Debug -email $debug_email -expiration $today

}

# If debug mode is false
if($debug -eq $false){

# For each user we grabbed previously
foreach ($user in $users)
{

    # Set the expiration dates, and dates to begin notifying
    $expired = $user.passwordlastset.AddDays(59)
    $warn14 = $expired.AddDays(-14)
    $warn7 = $expired.AddDays(-7)
    
    # If the users password is expired, or within 7 days of expiration, send them
    # an email every day until it changes
    if ($today -gt $warn7){
    sendmail -name $user.name -email $user.mail -expiration $expired
    }
    # If the users password expires in 14 days send an e-mail letting them know
    elseif ($today -eq $warn14){
    sendmail -name $user.name -email $user.mail -expiration $expired
    }
   
}
}
