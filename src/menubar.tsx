import { format } from "date-fns";
import { MenuBarExtra, showToast, Toast, Icon, openExtensionPreferences, Color, popToRoot, open, preferences } from "@raycast/api";
import { useEffect, useState, useCallback } from "react";
import { getLibreViewCredentials } from "./preferences";
import { logout, isLoggedOut as checkLoggedOut, attemptLogin } from "./auth";
import { glucoseStore } from "./store";
import { GlucoseReading } from "./types";

interface GlucoseStats {
  average: number;
  timeInRange: {
    low: number;
    normal: number;
    high: number;
  };
  low: number;
  normal: number;
  high: number;
}

const calculateStats = (data: GlucoseReading[], unit: string): GlucoseStats => {
  const values = data.map(r => unit === 'mmol' ? r.Value : r.ValueInMgPerDl);
  const avg = values.reduce((a, b) => a + b, 0) / values.length;
  
  const lowThreshold = unit === 'mmol' ? 3.9 : 70;
  const highThreshold = unit === 'mmol' ? 10.0 : 180;
  
  const low = data.filter(r => (unit === 'mmol' ? r.Value : r.ValueInMgPerDl) < lowThreshold).length;
  const high = data.filter(r => (unit === 'mmol' ? r.Value : r.ValueInMgPerDl) > highThreshold).length;
  const normal = data.length - low - high;
  
  return {
    average: avg,
    timeInRange: {
      low: (low / data.length) * 100,
      normal: (normal / data.length) * 100,
      high: (high / data.length) * 100
    },
    low,
    normal,
    high
  };
};

const getValueColor = (value: number | null, unit: string): { source: Icon; tintColor: Color } => {
  if (value === null) return { source: Icon.Circle, tintColor: Color.SecondaryText };
  
  const lowThreshold = unit === 'mmol' ? 3.9 : 70;
  const highThreshold = unit === 'mmol' ? 10.0 : 180;
  
  if (value < lowThreshold) return { source: Icon.Circle, tintColor: Color.Yellow };
  if (value > highThreshold) return { source: Icon.Circle, tintColor: Color.Red };
  return { source: Icon.Circle, tintColor: Color.Green };
};

export default function Command() {
  const [readings, setReadings] = useState<GlucoseReading[]>([]);
  const [latestReading, setLatestReading] = useState<string | null>(null);
  const [lastUpdateTime, setLastUpdateTime] = useState<Date | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [stats, setStats] = useState<GlucoseStats | null>(null);
  const { unit } = getLibreViewCredentials();
  const [isVisible, setIsVisible] = useState(true);
  const [isLoggedOut, setIsLoggedOut] = useState(false);

  const getTrendIcon = useCallback(() => {
    if (readings.length < 2) return "→";
    const current = unit === 'mmol' ? readings[0].Value : readings[0].ValueInMgPerDl;
    const previous = unit === 'mmol' ? readings[1].Value : readings[1].ValueInMgPerDl;
    if (current > previous + (unit === 'mmol' ? 0.3 : 5)) return "↑";
    if (current < previous - (unit === 'mmol' ? 0.3 : 5)) return "↓";
    return "→";
  }, [readings, unit]);

  const fetchData = useCallback(async (forceRefresh = false) => {
    try {
      const loggedOutState = await checkLoggedOut();
      if (loggedOutState) {
        const loginSuccess = await attemptLogin();
        if (!loginSuccess) {
          setIsLoggedOut(true);
          return;
        }
      }
      setIsLoggedOut(false);

      setIsLoading(true);
      console.log('Menubar: Starting data fetch');
      const data = await glucoseStore.getReadings(forceRefresh);
      
      if (data && data.length > 0) {
        console.log('Menubar: Latest readings:', data.slice(0, 3).map(r => ({
          value: r.Value,
          mgdl: r.ValueInMgPerDl,
          time: new Date(r.Timestamp).toLocaleTimeString(),
          unit
        })));
        
        setReadings(data);
        const latest = data[0];
        const value = unit === 'mmol' ? latest.Value : latest.ValueInMgPerDl;
        setLatestReading(value.toFixed(1));
        
        console.log('Menubar: Setting latest reading:', {
          raw: value,
          formatted: value.toFixed(1),
          timestamp: new Date(latest.Timestamp).toLocaleTimeString(),
          unit
        });
        
        setLastUpdateTime(new Date(latest.Timestamp));
        setStats(calculateStats(data, unit));
        setError(null);
      } else {
        throw new Error("No readings available");
      }
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : "Unknown error";
      console.error('Menubar: Error in fetchData:', errorMessage);
      setError(errorMessage);
      
      if (errorMessage.includes('Missing LibreView credentials')) {
        setIsLoggedOut(true);
      } else if (!errorMessage.includes('Rate limited')) {
        await showToast({ 
          style: Toast.Style.Failure, 
          title: "Error fetching data",
          message: errorMessage
        });
      }
    } finally {
      setIsLoading(false);
    }
  }, [unit]);

  useEffect(() => {
    fetchData();
    const interval = setInterval(() => fetchData(false), 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, [fetchData]);

  if (!isVisible) return null;

  if (isLoggedOut) {
    return (
      <MenuBarExtra
        icon={Icon.Person}
        title="Login Required"
      >
        <MenuBarExtra.Section>
          <MenuBarExtra.Item
            title="Enter LibreView Credentials"
            icon={Icon.Person}
            onAction={openExtensionPreferences}
          />
          <MenuBarExtra.Item
            title="Quit"
            icon={Icon.XmarkCircle}
            onAction={() => setIsVisible(false)}
          />
        </MenuBarExtra.Section>
      </MenuBarExtra>
    );
  }

  return (
    <MenuBarExtra
      icon={error ? Icon.ExclamationMark : getValueColor(latestReading ? Number(latestReading) : null, unit)}
      title={latestReading ? `${latestReading}${unit === 'mmol' ? ' mmol/L' : ' mg/dL'} ${getTrendIcon()}` : error ? "⚠️ Error" : "Loading..."}
      tooltip={error ? `Error: ${error}` : lastUpdateTime ? `Last updated: ${lastUpdateTime.toLocaleTimeString()}` : "Loading glucose data..."}
      isLoading={isLoading}
    >
      <MenuBarExtra.Section>
        {error ? (
          <MenuBarExtra.Item
            title={`Error: ${error}`}
            icon={Icon.ExclamationMark}
          />
        ) : (
          <>
            <MenuBarExtra.Item
              title={`Last Reading: ${latestReading}${unit === 'mmol' ? ' mmol/L' : ' mg/dL'}`}
              subtitle={lastUpdateTime ? format(lastUpdateTime, 'MMM d, h:mm a') : undefined}
              icon={getValueColor(Number(latestReading), unit)}
            />
            {stats && (
              <>
                <MenuBarExtra.Item
                  title={`Average: ${stats.average.toFixed(1)} ${unit === 'mmol' ? 'mmol/L' : 'mg/dL'}`}
                  icon={Icon.Circle}
                />
                <MenuBarExtra.Item
                  title="Time in Ranges"
                  icon={Icon.Circle}
                />
                <MenuBarExtra.Item
                  title={`    Low: ${stats.timeInRange.low.toFixed(1)}%`}
                  tooltip={`Below ${unit === 'mmol' ? '3.9 mmol/L' : '70 mg/dL'}`}
                />
                <MenuBarExtra.Item
                  title={`    In Range: ${stats.timeInRange.normal.toFixed(1)}%`}
                  tooltip={`${unit === 'mmol' ? '3.9-10.0 mmol/L' : '70-180 mg/dL'}`}
                />
                <MenuBarExtra.Item
                  title={`    High: ${stats.timeInRange.high.toFixed(1)}%`}
                  tooltip={`Above ${unit === 'mmol' ? '10.0 mmol/L' : '180 mg/dL'}`}
                />
              </>
            )}
          </>
        )}
      </MenuBarExtra.Section>

      <MenuBarExtra.Section>
        <MenuBarExtra.Item
          title="Refresh"
          icon={Icon.ArrowClockwise}
          onAction={() => fetchData(true)}
        />
        <MenuBarExtra.Item
          title="Open Detailed View"
          icon={Icon.List}
          onAction={() => {
            open("raycast://extensions/magi/sugardaddydiabetes/dashboard");
            popToRoot();
          }}
        />
        <MenuBarExtra.Item
          title="Preferences"
          icon={Icon.Gear}
          onAction={async () => {
            openExtensionPreferences();
            setTimeout(async () => {
              const success = await attemptLogin();
              if (success) {
                fetchData(true);
              }
            }, 1000);
          }}
        />
        <MenuBarExtra.Item
          title="Logout"
          icon={Icon.Terminal}
          onAction={async () => {
            await logout();
            setIsLoggedOut(true);
          }}
        />
        <MenuBarExtra.Item
          title="Quit"
          icon={Icon.XmarkCircle}
          onAction={() => setIsVisible(false)}
        />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
