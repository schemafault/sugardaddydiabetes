import fetch from 'node-fetch';
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

// Rate limiting and caching configuration
let cachedToken: string | null = null;
let lastTokenTime: number = 0;
let lastRequestTime: number = 0;
let backoffDelay: number = 1000;
let consecutiveFailures: number = 0;
let isFetching: boolean = false;
let pendingFetch: Promise<GlucoseReading[]> | null = null;

const TOKEN_EXPIRY = 50 * 60 * 1000;
const MIN_REQUEST_INTERVAL = 30 * 1000;
const MAX_BACKOFF_DELAY = 15 * 60 * 1000;
const INITIAL_BACKOFF_DELAY = 1000;
const MAX_CONSECUTIVE_FAILURES = 5;

// Shared cache for glucose data
let cachedGlucoseData: GlucoseReading[] | null = null;
let lastGlucoseTime: number = 0;
const GLUCOSE_CACHE_EXPIRY = 4 * 60 * 1000;

async function wait(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function throttleRequest(): Promise<void> {
  const now = Date.now();
  const timeSinceLastRequest = now - lastRequestTime;
  
  if (timeSinceLastRequest < MIN_REQUEST_INTERVAL) {
    await wait(MIN_REQUEST_INTERVAL - timeSinceLastRequest);
  }
  
  if (consecutiveFailures > MAX_CONSECUTIVE_FAILURES) {
    const extraDelay = Math.min(consecutiveFailures * 1000, MAX_BACKOFF_DELAY);
    await wait(extraDelay);
  }
  
  lastRequestTime = Date.now();
}

export async function authenticate(): Promise<string> {
  const credentials = getLibreViewCredentials();
  
  // Check if we have a valid cached token
  if (cachedToken && (Date.now() - lastTokenTime) < TOKEN_EXPIRY) {
    return cachedToken;
  }

  if (!credentials?.username || !credentials?.password) {
    throw new Error('Missing LibreView credentials');
  }

  await throttleRequest();

  try {
    const response = await fetch(`${API_BASE}/llu/auth/login`, {
      method: 'POST',
      headers: API_HEADERS,
      body: JSON.stringify({
        email: credentials.username,
        password: credentials.password
      })
    });

    if (!response.ok) {
      throw new Error(`Authentication failed: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    if (!data?.data?.authTicket?.token) {
      throw new Error('Invalid authentication response - no token found');
    }

    const token = data.data.authTicket.token;
    cachedToken = token;
    lastTokenTime = Date.now();
    backoffDelay = INITIAL_BACKOFF_DELAY;
    consecutiveFailures = 0;
    
    return token;
  } catch (error: any) {
    consecutiveFailures++;
    
    if (error.status === 429 || error.status === 430) {
      console.log(`Rate limited, waiting ${backoffDelay/1000}s before retry...`);
      await wait(backoffDelay);
      backoffDelay = Math.min(backoffDelay * 2, MAX_BACKOFF_DELAY);
      return authenticate();
    }
    
    backoffDelay = INITIAL_BACKOFF_DELAY;
    throw error;
  }
}

export async function fetchGlucoseData(): Promise<GlucoseReading[]> {
  console.log('fetchGlucoseData called');
  
  if (isFetching && pendingFetch) {
    console.log('Reusing pending fetch');
    return pendingFetch;
  }

  const now = Date.now();
  if (cachedGlucoseData && (now - lastGlucoseTime) < GLUCOSE_CACHE_EXPIRY) {
    console.log('Using cached data');
    return cachedGlucoseData;
  }

  try {
    console.log('Starting new fetch');
    isFetching = true;
    pendingFetch = (async () => {
      try {
        await throttleRequest();
        console.log('Getting auth token');
        const token = await authenticate();
        
        if (!token) {
          console.error('Failed to get auth token');
          throw new Error('Failed to obtain authentication token');
        }
        console.log('Got auth token successfully');

        const authHeaders = { ...API_HEADERS, Authorization: `Bearer ${token}` };

        console.log('Getting connections...');
        const connectionsResponse = await fetch(`${API_BASE}/llu/connections`, { 
          headers: authHeaders
        });

        if (!connectionsResponse.ok) {
          throw new Error(`Connections request failed: ${connectionsResponse.status} ${connectionsResponse.statusText}`);
        }
        
        const connectionsData = await connectionsResponse.json();
        console.log('Got connections response');
        
        const patientId = connectionsData?.data?.[0]?.patientId;
        if (!patientId) {
          console.error('No patient ID found in response');
          throw new Error('No LibreLinkUp connection found');
        }
        console.log('Found patient ID');

        const endDate = new Date();
        const startDate = new Date();
        startDate.setDate(endDate.getDate() - 1);

        console.log('Requesting glucose data');
        const glucoseResponse = await fetch(
          `${API_BASE}/llu/connections/${patientId}/graph?period=day&startDate=${format(startDate, 'yyyy-MM-dd')}&endDate=${format(endDate, 'yyyy-MM-dd')}`,
          {
            headers: authHeaders
          }
        );

        if (!glucoseResponse.ok) {
          throw new Error(`Glucose request failed: ${glucoseResponse.status} ${glucoseResponse.statusText}`);
        }

        const glucoseData = await glucoseResponse.json();
        console.log('Got glucose response');

        if (!glucoseData?.data?.graphData) {
          throw new Error('No glucose data available in response');
        }

        const readings = glucoseData.data.graphData;
        
        if (!Array.isArray(readings) || readings.length === 0) {
          throw new Error('Invalid or empty glucose readings received');
        }
        
        const validReadings = readings.filter(r => 
          r && typeof r.Value === 'number' && 
          typeof r.Timestamp === 'string' &&
          !isNaN(new Date(r.Timestamp).getTime())
        );
        
        if (validReadings.length === 0) {
          throw new Error('No valid glucose readings found in response');
        }
        
        cachedGlucoseData = validReadings;
        lastGlucoseTime = now;
        backoffDelay = INITIAL_BACKOFF_DELAY;
        consecutiveFailures = 0;
        
        return validReadings;
      } catch (error: any) {
        console.error('Error fetching glucose data:', error);
        
        if (error.status === 429 || error.status === 430) {
          console.log(`Rate limited, waiting ${backoffDelay/1000}s before retry...`);
          
          if (cachedGlucoseData && (Date.now() - lastGlucoseTime) < GLUCOSE_CACHE_EXPIRY * 3) {
            console.log('Returning cached data during rate limit...');
            return cachedGlucoseData;
          }
          
          await wait(backoffDelay);
          backoffDelay = Math.min(backoffDelay * 2, MAX_BACKOFF_DELAY);
          return fetchGlucoseData();
        }
        
        backoffDelay = INITIAL_BACKOFF_DELAY;
        
        if (cachedGlucoseData && (Date.now() - lastGlucoseTime) < GLUCOSE_CACHE_EXPIRY * 2) {
          console.log('Returning cached data after error...');
          return cachedGlucoseData;
        }
        
        throw error;
      } finally {
        isFetching = false;
        pendingFetch = null;
      }
    })();

    return pendingFetch;
  } catch (error) {
    console.error('Error in fetchGlucoseData:', error);
    throw error;
  }
}

// Export a function to check if we have valid cached data
export function hasCachedData(): boolean {
  return !!(cachedGlucoseData && (Date.now() - lastGlucoseTime) < GLUCOSE_CACHE_EXPIRY);
}

// Initialize cache on module load
try {
  fetchGlucoseData().catch(console.error);
} catch (error) {
  console.error('Failed to initialize cache:', error);
}
