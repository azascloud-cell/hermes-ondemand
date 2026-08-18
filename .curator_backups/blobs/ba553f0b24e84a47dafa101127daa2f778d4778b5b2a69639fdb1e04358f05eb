---
name: gmail-account-management
description: "Use when verifying or warming bulk Gmail accounts."
version: 1.0.0
author: community
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [Gmail, Account-Farming, Warming, Bulk-Management]
---

# Gmail Account Management & Warming

This skill governs the process of verifying the status of bulk Gmail accounts (e.g., 'farming' accounts) and performing 'warming' activities to ensure they appear as legitimate human accounts before being sold or used for automation.

## Core Workflow

### 1. Status Verification (Active vs. Kenon)
When checking if accounts are active or "kenon" (disabled/banned):
1. **Avoid Blind Login:** Do not attempt mass logins without explicit user confirmation, as this can trigger security alerts (especially on new IPs).
2. **Verification Method:** Use a CLI email client (like `himalaya`) with a temporary configuration to test IMAP connectivity.
3. **Handling 'Child' Accounts:** Be aware that managed accounts (Family Link) may have stricter third-party access rules and may require specific app passwords.

### 2. Account Warming (Humanization)
To reduce the risk of bans after creation:
- **Inter-Account Communication:** Send natural, non-templated emails between accounts in the cluster.
- **Inbox Maintenance:** Delete spam and organize folders to mimic human behavior.
- **Activity Simulation:** Maintain a history of sent/received mail before moving the account to a 'payment' or 'delivery' stage.

## Pitfalls & Safety
- **Security Alerts:** Accessing accounts from unknown environments often triggers Google's security check. Always notify the user before attempting a login that might lock the account.
- **Auth Failures:** An "Authentication Failed" error in IMAP doesn't always mean the account is "kenon"; it could mean "Less Secure Apps" is disabled or 2FA is required.
- **Rate Limiting:** Do not attempt to verify hundreds of accounts in a tight loop from a single IP.

## Verification
- **Active:** Successful IMAP connection and ability to list envelopes.
- **Kenon/Disabled:** Explicit "Account disabled" message or persistent auth failure despite correct credentials.
- **Bounce Test:** Sending an external email to the target; a "User not found" bounce confirms deletion, but a successful delivery does NOT confirm the account isn't disabled.
