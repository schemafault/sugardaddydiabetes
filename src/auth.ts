import { clearLocalStorage, showToast, Toast, LocalStorage } from "@raycast/api";
import fetch from 'node-fetch';
import { getLibreViewCredentials } from "./preferences";

const API_BASE = "https://api.libreview.io";
const API_HEADERS = {
  'Content-Type': 'application/json',
  'Product': 'llu.android',
  'Version': '4.7.0',
  'Accept-Encoding': 'gzip'
};

const LOGGED_OUT_KEY = 'logged_out';

interface AuthResponse {
  data: {
    authTicket: {
      token: string;
    };
  };
}

function isAuthResponse(data: any): data is AuthResponse {
  return (
    typeof data === 'object' &&
    data !== null &&
    'authTicket' in data &&
    typeof data.authTicket === 'object' &&
    data.authTicket !== null &&
    'token' in data.authTicket
  );
}

export async function authenticate(): Promise<string> {
  console.log('Authenticating...');
  const credentials = getLibreViewCredentials();
  
  if (!credentials?.username || !credentials?.password) {
    console.error('No credentials found');
    throw new Error('Missing LibreView credentials');
  }
  console.log('Got credentials, attempting login...');
  
  try {
    console.log('Sending auth request...');
    const response = await fetch(`${API_BASE}/llu/auth/login`, {
      method: 'POST',
      headers: API_HEADERS,
      body: JSON.stringify({
        email: credentials.username,
        password: credentials.password
      })
    });

    if (!response.ok) {
      console.error('Auth request failed:', response.status, response.statusText);
      throw new Error(`Authentication failed: ${response.status} ${response.statusText}`);
    }

    console.log('Got auth response...');
    const data = await response.json();
    if (!isAuthResponse(data)) {
      throw new Error('Invalid response format');
    }
    console.log('Auth response data:', JSON.stringify(data, null, 2));
    
    if (!data?.data?.authTicket?.token) {
      console.error('No token in auth response');
      throw new Error('Invalid authentication response - no token');
    }

    console.log('Authentication successful');
    return data.data.authTicket.token;
  } catch (error) {
    console.error('Authentication error:', error);
    throw error;
  }
}

export async function logout() {
  try {
    await clearLocalStorage();
    await LocalStorage.setItem(LOGGED_OUT_KEY, 'true');
    await showToast({
      style: Toast.Style.Success,
      title: "Logged out successfully"
    });
  } catch (error) {
    console.error('Error during logout:', error);
    await showToast({
      style: Toast.Style.Failure,
      title: "Failed to log out",
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
}

export async function isLoggedOut(): Promise<boolean> {
  try {
    const value = await LocalStorage.getItem(LOGGED_OUT_KEY);
    return value === 'true';
  } catch {
    return false;
  }
}

export async function clearLoggedOutState() {
  await LocalStorage.removeItem(LOGGED_OUT_KEY);
}
