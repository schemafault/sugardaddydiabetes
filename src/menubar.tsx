import { MenuBarExtra, showToast, Toast, Icon, openExtensionPreferences } from "@raycast/api";
import { useEffect, useState, useCallback, useMemo } from "react";
import { getLibreViewCredentials } from "./preferences";
import { logout } from "./auth";
import { format } from "date-fns";
import { glucoseStore } from "./store";
import { GlucoseReading } from "./types";
import { debounce } from "lodash";

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

const getValueColor = (value: number, unit: string): string => {
  const lowThreshold = unit === 'mmol' ? 3.9 : 70;
  const highThreshold = unit === 'mmol' ? 10.0 : 180;
  
  if (value < lowThreshold) return '#EAB308'; // Yellow for low
  if (value > highThreshold) return '#EF4444'; // Red for high
  return '#10B981'; // Green for normal
};

export default function Command() {
  const [readings, setReadings] = useState<GlucoseReading[]>([]);
  const [latestReading, setLatestReading] = useState<string | null>(null);
  const [lastUpdateTime, setLastUpdateTime] = useState<Date | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [retryCount, setRetryCount] = useState(0);
  const [stats, setStats] = useState<GlucoseStats | null>(null);
  const { unit } = getLibreViewCredentials();

  const generateChartSVG = useCallback((data: GlucoseReading[]) => {
    if (!data.length) {
      console.log('No readings available for chart');
      return '';
    }

    console.log('Generating chart with readings:', data.length);

    const width = 300;
    const height = 80;
    const padding = 10;

    const chartData = data.slice(0, 24).map(r => ({
      value: unit === 'mmol' ? r.Value : r.ValueInMgPerDl,
      color: getValueColor(unit === 'mmol' ? r.Value : r.ValueInMgPerDl, unit)
    })).reverse();

    const values = chartData.map(d => d.value);
    const min = Math.min(...values) * 0.9;
    const max = Math.max(...values) * 1.1;

    const xScale = (width - 2 * padding) / (chartData.length - 1);
    const yScale = (height - 2 * padding) / (max - min);

    const points = chartData.map((d, i) => {
      const x = padding + i * xScale;
      const y = height - (padding + (d.value - min) * yScale);
      return `${x},${y}`;
    });

    // Create SVG with path and points
    const svg = `<?xml version="1.0" encoding="UTF-8" standalone="no"?>
      <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
      <svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" xmlns="http://www.w3.org/2000/svg" version="1.1">
        <rect width="100%" height="100%" fill="white"/>
        <polyline
          points="${points.join(' ')}"
          fill="none"
          stroke="#3B82F6"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        />
        ${points.map((point, i) => {
          const [x, y] = point.split(',');
          return `
            <circle
              cx="${x}"
              cy="${y}"
              r="3"
              fill="${chartData[i].color}"
              stroke="white"
              stroke-width="1"
            />
          `;
        }).join('')}
      </svg>`.trim();

    // Properly encode the SVG for use in data URL
    const encoded = Buffer.from(svg).toString('base64');
    const dataUrl = `data:image/svg+xml;base64,${encoded}`;
    console.log('Generated SVG data URL:', dataUrl.length, 'characters');
    return dataUrl;
  }, [unit]);

  const chartImage = useMemo(() => {
    if (!readings.length) return '';
    return generateChartSVG(readings);
  }, [readings, generateChartSVG]);

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
        setRetryCount(0);
      } else {
        throw new Error("No readings available");
      }
    } catch (e) {
      const errorMessage = e instanceof Error ? e.message : "Unknown error";
      console.error('Menubar: Error in fetchData:', errorMessage);
      setError(errorMessage);
      
      if (!errorMessage.includes('Rate limited') || retryCount === 0) {
        await showToast({ 
          style: Toast.Style.Failure, 
          title: "Error fetching data",
          message: errorMessage
        });
      }
      
      setRetryCount(prev => prev + 1);
    } finally {
      setIsLoading(false);
    }
  }, [unit, retryCount]);

  useEffect(() => {
    fetchData();
    const interval = setInterval(() => fetchData(false), 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, [fetchData]);

  return (
    <MenuBarExtra
      icon={error ? Icon.ExclamationMark : Icon.Circle}
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
              icon={Icon.Circle}
            />
            {chartImage && (
              <MenuBarExtra.Item
                title=" "
                icon={{
                  source: chartImage,
                  tintColor: null
                }}
              />
            )}
            {stats && (
              <>
                <MenuBarExtra.Item
                  title={`Average: ${stats.average.toFixed(1)} ${unit === 'mmol' ? 'mmol/L' : 'mg/dL'}`}
                  icon={Icon.Circle}
                />
                <MenuBarExtra.Item
                  title={`Time in Range: ${stats.timeInRange.normal.toFixed(1)}%`}
                  icon={Icon.Circle}
                  tooltip={`Low: ${stats.timeInRange.low.toFixed(1)}%, Normal: ${stats.timeInRange.normal.toFixed(1)}%, High: ${stats.timeInRange.high.toFixed(1)}%`}
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
          icon={Icon.ExitFullScreen}
          onAction={logout}
        />
      </MenuBarExtra.Section>
    </MenuBarExtra>
  );
}
