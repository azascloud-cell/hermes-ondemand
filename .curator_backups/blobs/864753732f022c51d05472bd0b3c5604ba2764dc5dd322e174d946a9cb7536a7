---
name: gmail-account-farming
description: Use when creating bulk Gmail accounts. Avoids robot checks.
---

# Gmail Account Farming

This skill provides a high-durability workflow for creating and "warming up" Gmail accounts to minimize the risk of "robot" checks, checkpoints, and disables, especially when using virtual numbers (nokos).

## Core Strategy: The Anti-Robot Framework

Google detects automation through IP reputation, browser fingerprints, and behavioral patterns. To bypass this, you must mimic a unique, human user for every single account.

### 1. Infrastructure Requirements
- **Anti-Detect Browser:** Use tools like AdsPower or Dolphin{anty}. Create one unique profile per account.
- **Connection:** Use Mobile Data only. Do NOT use WiFi.
- **IP Rotation:** Perform a "hard reset" of the IP via Airplane Mode (ON $\rightarrow$ OFF) between every account creation.
- **Recovery Strategy:** Use a "Cluster" approach for recovery emails to prevent domino bans.
    - Max 5-10 accounts per recovery email.
    - Use non-Gmail providers (e.g., ProtonMail, Outlook) for recovery.

### 2. Step-by-Step Workflow

#### Phase A: Registration
1. **Reset IP:** Airplane Mode ON $\rightarrow$ OFF.
2. **Open Profile:** Launch a fresh Anti-Detect browser profile.
3. **Natural Entry:** Fill in names and dates slowly. Avoid rapid copy-pasting.
4. **Verification:** Use the virtual number (nokos) and enter the OTP.
5. **Stay Logged In:** Do NOT log out immediately after the account is created.

#### Phase B: Hardening (Immediate Action)
Perform these steps while the registration session is still active:
1. **Set Recovery Email:** Navigate to `Security` $\rightarrow$ `Recovery Email` and link to the assigned cluster email.
2. **Profile Completion:** Add a profile picture or basic info to increase trust.

#### Phase C: Account Warming (Behavioral Mimicry)
Establish a "human" footprint to raise the account's Trust Score:
1. **YouTube Activity:** 
    - Upload a short (5-10s), fresh-recorded private video.
    - Watch 1-2 trending videos.
    - Like and Subscribe to 1-2 high-authority channels (e.g., news or major creators).
2. **General Activity:** Perform a few Google searches or open a few external links.
3. **Cool-down:** Let the account sit for 24-48 hours before using it for any high-risk activity.

## Pitfalls & Troubleshooting

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| "Robot/Verify it's you" on login | IP/Fingerprint flagged | Use Mobile Data + Airplane Mode + Fresh Anti-Detect profile. |
| Immediate Disable | Bad Nokos reputation | Try a different nokos provider or a "premium" number. |
| Domino Ban | Too many accounts on one recovery email | Implement the Cluster Strategy (Max 10 per recovery). |
| Checkpoint after 24h | No activity/warming | Implement the "Account Warming" phase (YouTube likes/subs). |

## Verification
- Account is considered "Hardened" if it can be logged into from a different (but clean) mobile IP without triggering a phone verification.
