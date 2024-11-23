import { LocalStorage } from "@raycast/api";
import { GlucoseReading } from "./types";
import { fetchGlucoseData } from "./libreview";

const CACHE_KEY = "glucose_readings";
const LAST_FETCH_KEY = "last_fetch_time";
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes

interface CachedData {
  readings: GlucoseReading[];
  timestamp: number;
}

class GlucoseStore {
  private static instance: GlucoseStore;
  private fetchPromise: Promise<GlucoseReading[]> | null = null;
  private lastFetchAttempt = 0;

  private constructor() {}

  static getInstance(): GlucoseStore {
    if (!GlucoseStore.instance) {
      GlucoseStore.instance = new GlucoseStore();
    }
    return GlucoseStore.instance;
  }

  async getCachedData(): Promise<CachedData | null> {
    try {
      const data = await LocalStorage.getItem<string>(CACHE_KEY);
      if (!data) return null;
      return JSON.parse(data) as CachedData;
    } catch (error) {
      console.error("Error reading cache:", error);
      return null;
    }
  }

  private async setCachedData(readings: GlucoseReading[]): Promise<void> {
    try {
      const cache: CachedData = {
        readings,
        timestamp: Date.now(),
      };
      await LocalStorage.setItem(CACHE_KEY, JSON.stringify(cache));
    } catch (error) {
      console.error("Error setting cache:", error);
    }
  }

  private shouldFetch(): boolean {
    const now = Date.now();
    return now - this.lastFetchAttempt > CACHE_DURATION;
  }

  async getReadings(forceRefresh = false): Promise<GlucoseReading[]> {
    console.log("Getting readings, force refresh:", forceRefresh);
    
    try {
      // First, try to get cached data
      const cachedData = await this.getCachedData();
      const now = Date.now();

      // If we have a pending fetch, return its promise
      if (this.fetchPromise) {
        console.log("Reusing pending fetch");
        return this.fetchPromise;
      }

      // If we have valid cached data and don't need to refresh
      if (
        !forceRefresh &&
        cachedData &&
        now - cachedData.timestamp < CACHE_DURATION
      ) {
        console.log("Using cached data from:", new Date(cachedData.timestamp).toLocaleTimeString());
        
        // Start a background refresh if needed
        if (this.shouldFetch()) {
          console.log("Starting background refresh");
          this.refreshInBackground().catch(error => {
            console.error("Background refresh failed:", error);
          });
        }
        
        return cachedData.readings;
      }

      // If we need fresh data, start a new fetch
      console.log("Starting new fetch at:", new Date().toLocaleTimeString());
      this.lastFetchAttempt = now;
      
      this.fetchPromise = fetchGlucoseData()
        .then(async (readings) => {
          console.log("Fetch successful, updating cache with", readings.length, "readings");
          await this.setCachedData(readings);
          return readings;
        })
        .catch(async (error) => {
          console.error("Fetch failed:", error);
          
          // If fetch fails but we have cached data, use it
          if (cachedData) {
            console.log("Using cached data after fetch failure, from:", new Date(cachedData.timestamp).toLocaleTimeString());
            return cachedData.readings;
          }
          throw error;
        })
        .finally(() => {
          this.fetchPromise = null;
          console.log("Fetch completed at:", new Date().toLocaleTimeString());
        });

      return this.fetchPromise;
    } catch (error) {
      console.error("Error in getReadings:", error);
      throw error;
    }
  }

  private async refreshInBackground(): Promise<void> {
    if (this.fetchPromise) {
      console.log("Background refresh: Using existing fetch promise");
      return;
    }

    try {
      console.log("Background refresh: Starting new fetch");
      const readings = await fetchGlucoseData();
      await this.setCachedData(readings);
      console.log("Background refresh completed successfully");
    } catch (error) {
      console.error("Background refresh failed:", error);
      // Don't throw the error since this is a background operation
    }
  }

  async clearCache(): Promise<void> {
    try {
      await LocalStorage.removeItem(CACHE_KEY);
      await LocalStorage.removeItem(LAST_FETCH_KEY);
    } catch (error) {
      console.error("Error clearing cache:", error);
    }
  }
}

export const glucoseStore = GlucoseStore.getInstance();
