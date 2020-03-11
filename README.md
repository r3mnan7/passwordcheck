# **Password Check**
## **Overview**
Leverages the Active Directory powershell module to poll for users whose passwords are within 7 days of expiration.

An e-mail notification is sent to users whose password expires within 7 days. Users continue to receive e-mails until their passwords are changed or expired.

*Note: You will need your own Mailgun account to make this work, or feel free to fork/branch and add your delivery method.*

## **Use**
Password check is designed to be run as a scheduled task.

### Inform Mode
When run with the -inform switch, the script will send a report of ALL users expiring in the next $warndays days to the $informemail rather than sending messages to users.

The script needs only enough permission to read the DisplayName, EmailAddress, and msDS-UserPasswordExpiryTimeComputed attributes

You will need to fill in the following data in order to make this function:

- variable name - description - line number
- $informemail - E-mail address for sending inform report - 8
- $warndays (optional) - How many days to warn user before password expires (default 7) - 11
- $url - Mailgun API URL - 46
- $auth - Mailgun API Key - 49
- $message (optional) - The message sent to users whose passwords are expiring -  (112 - 115)


## Logging
This script logs to the Windows Application log from the Source password_check and all event IDs correspond to a specific event:

Information Logs
- 1001: Connecting to AD
- 1002: Successful AD connection.
- 1003: Extracting users with expiring passwords.
- 1006: Prepping user notification.
- 1007: Inform report sent.
- 1008: User notification email sent.

Error Logs - Typically log with exception details
- 2001: Failed connecting to AD.
- 2002: Error sending e-mail.
- 2003: Unable to extract expiring users from AD data.

## More info
Check out the comments in the script for more information on how it functions.
    

