import axios from "axios";
import { format } from "date-fns";
import { getLibreViewCredentials } from "./preferences";

const API_BASE = "https://api.libreview.io";
const API_HEADERS = {
  'Content-Type': 'application/json',
  'Product': 'llu.android',
  'Version': '4.7.0',
  'Accept-Encoding': 'gzip'
};

interface AuthResponse {
  data: {
    authTicket: {
      token: string;
    };
  };
}

interface ConnectionsResponse {
  data: Array<{
    patientId: string;
  }>;
}

interface GlucoseReading {
  Timestamp: string;
  ValueInMgPerDl: number;
  Value: number; // mmol/L
  FactoryTimestamp: string;
  type: number;
  MeasurementColor: number;
  GlucoseUnits: number;
  isHigh: boolean;
  isLow: boolean;
}

interface GlucoseResponse {
  data: {
    graphData: GlucoseReading[];
    startDate: string;
    endDate: string;
  };
}

export async function fetchGlucoseData(): Promise<GlucoseReading[]> {
  try {
    console.log('Attempting to authenticate with LibreLinkUp...');
    const { username, password } = getLibreViewCredentials();

    // First authenticate with LibreLinkUp
    const authResponse = await axios.post<AuthResponse>(`${API_BASE}/llu/auth/login`, 
      {
        email: username,
        password: password
      },
      { headers: API_HEADERS }
    );

    console.log('Auth successful, getting token...');
    const token = authResponse.data.data.authTicket.token;
    const authHeaders = { ...API_HEADERS, Authorization: `Bearer ${token}` };

    // Get patient ID from connections
    console.log('Getting connections...');
    const connectionsResponse = await axios.get<ConnectionsResponse>(
      `${API_BASE}/llu/connections`,
      { headers: authHeaders }
    );

    console.log('Connections response:', connectionsResponse.data);

    // Get the first patient ID
    const patientId = connectionsResponse.data.data[0]?.patientId;
    if (!patientId) {
      throw new Error(
        'No LibreLinkUp connection found. Please:\n' +
        '1. Download the LibreLinkUp app\n' +
        '2. Log in with your LibreView credentials\n' +
        '3. Add the account that has the Libre sensor\n' +
        '4. Wait for them to accept the invitation\n' +
        '5. Try again after connection is established'
      );
    }

    // Calculate date range - last 24 hours
    const endDate = new Date();
    const startDate = new Date();
    startDate.setDate(endDate.getDate() - 1);

    console.log('Fetching glucose data:', {
      startDate: startDate.toISOString(),
      endDate: endDate.toISOString()
    });

    // Get glucose data for the patient
    const glucoseResponse = await axios.get<GlucoseResponse>(
      `${API_BASE}/llu/connections/${patientId}/graph`,
      {
        headers: authHeaders,
        params: {
          period: 'custom',
          startDate: startDate.toISOString(),
          endDate: endDate.toISOString()
        }
      }
    );

    if (!glucoseResponse.data?.data?.graphData) {
      console.error('Unexpected response format:', glucoseResponse.data);
      throw new Error('No glucose data available in response');
    }

    const readings = glucoseResponse.data.data.graphData;
    console.log('Received readings:', {
      count: readings.length,
      firstReading: readings[0],
      lastReading: readings[readings.length - 1]
    });

    return readings;

  } catch (error) {
    console.error('Error fetching Libre data:', error);
    if (axios.isAxiosError(error)) {
      console.error('Response data:', error.response?.data);
      console.error('Response status:', error.response?.status);
      throw new Error(`LibreView API error: ${error.response?.data?.message || error.message}`);
    }
    throw error;
  }
}
