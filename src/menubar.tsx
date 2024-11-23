import { format } from "date-fns";
import { MenuBarExtra, showToast, Toast, Icon, openExtensionPreferences, Color, popToRoot } from "@raycast/api";
import { useEffect, useState, useCallback } from "react";
import { getLibreViewCredentials } from "./preferences";
import { logout } from "./auth";
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

const getValueColor = (value: number, unit: string): { source: Icon; tintColor: Color } => {
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

  const getTrendIcon = useCallback(() => {
    if (readings.length < 2) return "→";
    const current = readings[0].Value;
    const previous = readings[1].Value;
    if (current > previous + 0.3) return "↑";
    if (current < previous - 0.3) return "↓";
    return "→";
  }, [readings]);

  const fetchData = useCallback(async (forceRefresh = false) => {
    try {
      setIsLoading(true);
      console.log('Menubar: Starting data fetch');
      const data = await glucoseStore.getReadings(forceRefresh);
      
      if (data && data.length > 0) {
        console.log('Menubar: Got data, processing...');
        setReadings(data);
        const latest = data[0];
        const value = unit === 'mmol' ? latest.Value : latest.ValueInMgPerDl;
        setLatestReading(value.toFixed(1));
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
      
      if (!errorMessage.includes('Rate limited')) {
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

  return (
    <MenuBarExtra
      icon={error ? Icon.ExclamationMark : getValueColor(Number(latestReading), unit)}
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
          title="Preferences"
          icon={Icon.Gear}
          onAction={openExtensionPreferences}
        />
        <MenuBarExtra.Item
          title="Logout"
          icon={Icon.Terminal}
          onAction={logout}
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
