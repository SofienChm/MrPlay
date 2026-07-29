# Codemagic Environment Variables

The following environment variables must be configured in Codemagic (Settings → Environment variables) for the build pipeline to work:

## Required for App Store Connect Publishing

| Variable | Description | Source |
|----------|-------------|--------|
| `APP_STORE_CONNECT_KEY` | App Store Connect API key | App Store Connect → Users and Access → API Keys → Generate |
| `APP_STORE_CONNECT_KEY_ID` | API Key ID (e.g., D383SF739) | Same page as above |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID (UUID) | Same page as above |

## Required for Code Signing

| Variable | Description | Source |
|----------|-------------|--------|
| `CERTIFICATE` | Base64-encoded Apple Distribution certificate (.p12) | Export from Keychain Access |
| `CERTIFICATE_PASSWORD` | Password for the .p12 certificate | Set when exporting |
| `PROVISIONING_PROFILE` | Base64-encoded App Store provisioning profile (.mobileprovision) | Apple Developer → Certificates, Identifiers & Profiles |
| `APP_STORE_TEAM_ID` | Apple Developer Team ID (e.g., ABC123XYZ) | Apple Developer → Membership |

## Setup Instructions

1. Go to [Codemagic Dashboard](https://codemagic.io/) → Your app → Settings
2. Navigate to "Environment variables" section
3. Add each variable with the "Secure" option enabled (values will be encrypted)
4. Ensure the "Group" is set to "default" (or the group used in your codemagic.yaml)

## Generating App Store Connect API Key

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com/)
2. Navigate to Users and Access → API Keys
3. Click "Generate API Key"
4. Select "App Manager" or "Admin" role
5. Download the API key file (.p8)
6. Copy the Key ID and Issuer ID from the page
7. The API key itself is in the downloaded .p8 file
