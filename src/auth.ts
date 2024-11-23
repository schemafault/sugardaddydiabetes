import { clearLocalStorage, showToast, Toast, LocalStorage } from "@raycast/api";
import axios from 'axios';
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

const LOGGED_OUT_KEY = 'logged_out';

export async function authenticate(): Promise<string> {
  console.log('Starting authentication...');
  const credentials = getLibreViewCredentials();
  
  if (!credentials.username || !credentials.password) {
    console.error('Missing credentials');
    throw new Error('LibreView credentials not found');
  }
  console.log('Got credentials, attempting login...');
  
  try {
    console.log('Sending auth request...');
    const response = await axios.post<AuthResponse>(
      `${API_BASE}/llu/auth/login`,
      {
        email: credentials.username,
        password: credentials.password
      },
      {
        headers: API_HEADERS,
        timeout: 10000
      }
    ).catch(error => {
      console.error('Auth request failed:', error.response?.status, error.message);
      if (error.response?.data) {
        console.error('Error response data:', error.response.data);
      }
      throw error;
    });

    if (!response.data) {
      console.error('No response data from auth request');
      throw new Error('Invalid authentication response - no data');
    }

    console.log('Got auth response:', JSON.stringify(response.data, null, 2));
    const token = response.data?.data?.authTicket?.token;
    if (!token) {
      console.error('No token in auth response');
      throw new Error('Invalid authentication response - no token');
    }

    console.log('Authentication successful');
    return token;
  } catch (error: any) {
    console.error('Authentication error:', error.message);
    if (error.response?.status === 401) {
      throw new Error('Invalid LibreView credentials');
    }
    if (error.response?.status === 429 || error.response?.status === 430) {
      throw new Error('Rate limited during authentication');
    }
    throw new Error(`Authentication failed: ${error.message}`);
  }
}

export async function logout() {
  try {
    await clearLocalStorage();
    await showToast({
      style: Toast.Style.Success,
      title: "Logged out successfully",
      message: "Your LibreView credentials have been cleared"
    });
  } catch (error) {
    console.error('Logout error:', error);
    await showToast({
      style: Toast.Style.Failure,
      title: "Logout failed",
      message: error instanceof Error ? error.message : "Unknown error"
    });
  }
}

export async function isLoggedOut(): Promise<boolean> {
  try {
    return await LocalStorage.getItem(LOGGED_OUT_KEY) === "true";
  } catch {
    return false;
  }
}

export async function clearLoggedOutState() {
  await LocalStorage.removeItem(LOGGED_OUT_KEY);
}
