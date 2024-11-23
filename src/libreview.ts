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
    glucoseMeasurement?: GlucoseReading;
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
    connection?: {
      glucoseMeasurement: GlucoseReading;
    };
  };
}

let cachedToken: string | null = null;
let lastTokenTime: number = 0;
const TOKEN_EXPIRY = 50 * 60 * 1000; // 50 minutes in milliseconds
const RATE_LIMIT_DELAY = 60 * 1000; // 1 minute delay for rate limiting

export async function authenticate(): Promise<string> {
  // Check if we have a valid cached token
  const now = Date.now();
  if (cachedToken && (now - lastTokenTime) < TOKEN_EXPIRY) {
    return cachedToken;
  }

  const { username, password } = getLibreViewCredentials();
  
  try {
    const response = await axios.post(
      `${API_BASE}/llu/auth/login`,
      { email: username, password },
      { headers: API_HEADERS }
    );

    if (response.status === 200 && response.data.data.authTicket) {
      cachedToken = response.data.data.authTicket.token;
      lastTokenTime = now;
      return cachedToken;
    }
    
    throw new Error('Authentication failed');
  } catch (error: any) {
    if (error.response?.status === 430) {
      console.log('Rate limited, waiting before retry...');
      await new Promise(resolve => setTimeout(resolve, RATE_LIMIT_DELAY));
      return authenticate(); // Retry after delay
    }
    throw error;
  }
}

export async function fetchGlucoseData(): Promise<GlucoseReading[]> {
  try {
    const token = await authenticate();
    const authHeaders = { ...API_HEADERS, Authorization: `Bearer ${token}` };

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

  } catch (error: any) {
    if (error.response?.status === 430) {
      console.log('Rate limited, waiting before retry...');
      await new Promise(resolve => setTimeout(resolve, RATE_LIMIT_DELAY));
      return fetchGlucoseData(); // Retry after delay
    }
    throw error;
  }
}
