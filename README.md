# SugarDaddyDiabetes

A Raycast extension that helps monitor glucose data from Freestyle Libre 2 & 3 devices through LibreView integration.

## Features

- 📊 Real-time glucose monitoring through LibreView
- 📈 24-hour glucose average with visual gauge
- 🎯 Color-coded readings (In Range 🟢, Low 🟡, High 🔴)
- 🔔 Menu bar quick view for latest readings
- 🔄 Automatic updates every 5 minutes
- 📱 Support for both mmol/L and mg/dL units

## Prerequisites

Before using this extension, you need:

1. A LibreView account (https://www.libreview.com)
2. The LibreLinkUp mobile app installed and configured
3. A Freestyle Libre 2 or 3 sensor actively sharing data
4. Raycast installed on your Mac (https://raycast.com)

## Setup Instructions

1. Install the extension from the Raycast Store
2. Configure the required preferences:
   - LibreView Username (your account email)
   - LibreView Password
   - Preferred Glucose Unit (mmol/L or mg/dL)
3. If you haven't set up LibreLinkUp sharing:
   1. Download the LibreLinkUp app
   2. Log in with your LibreView credentials
   3. Add the account that has the Libre sensor
   4. Wait for them to accept the invitation
   5. Once connected, the extension will start showing data

## LibreView API Requirements

This extension uses the LibreView API with the following specifications:

- Authentication: Token-based with 50-minute expiry
- Rate Limiting: Implements automatic retry with 1-minute delay
- Data Refresh: Every 5 minutes for menu bar updates
- API Endpoints Used:
  - Login: `/llu/auth/login`
  - Connections: `/llu/connections`
  - Glucose Data: `/llu/connections/{patientId}/graph`

## Privacy Policy

SugarDaddyDiabetes takes your privacy and data security seriously:

1. Data Collection
   - The extension only collects necessary glucose data from LibreView
   - No personal data is stored locally
   - Credentials are securely stored in Raycast's preference system

2. Data Handling
   - All data is fetched in real-time from LibreView
   - No historical data is cached or stored
   - Data is only displayed within the Raycast interface

3. Data Transmission
   - All API communications use secure HTTPS
   - Authentication tokens are stored temporarily in memory
   - No data is shared with third parties

4. Security Measures
   - Credentials are stored securely using Raycast's encryption
   - API tokens expire after 50 minutes
   - Rate limiting protection is implemented
   - No sensitive data is logged or stored

## Troubleshooting

If you encounter issues:

1. Verify your LibreView credentials are correct
2. Ensure your LibreLinkUp connection is active
3. Check if your sensor is actively sharing data
4. Try refreshing the extension
5. Ensure you have a stable internet connection

For additional support, please open an issue on GitHub.

## License

This project is licensed under the MIT License - see the LICENSE file for details.