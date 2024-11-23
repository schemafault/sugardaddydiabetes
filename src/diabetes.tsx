import { Detail, Toast, showToast, ActionPanel, Action, Icon, openExtensionPreferences } from "@raycast/api";
import { useEffect, useState, useCallback } from "react";
import { fetchGlucoseData } from "./libreview";
import { format } from "date-fns";
import { getLibreViewCredentials } from "./preferences";
import { logout } from "./auth";

// Glucose range constants (mmol/L)
const RANGE = {
  LOW_THRESHOLD: 3.0,
  HIGH_THRESHOLD: 10.0,
  MAX_DISPLAY: 25.0 // Maximum value to show on gauge
};

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

export default function Command() {
  const [readings, setReadings] = useState<GlucoseReading[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const credentials = getLibreViewCredentials();
  const { unit } = credentials;

  const loadData = useCallback(async () => {
    try {
      setIsLoading(true);
      setError(null);
      const data = await fetchGlucoseData();
      setReadings(data);
    } catch (error) {
      console.error('Error fetching glucose data:', error);
      const errorMessage = error instanceof Error ? error.message : "Unknown error";
      setError(errorMessage);
      await showToast({
        style: Toast.Style.Failure,
        title: "Failed to load glucose data",
        message: errorMessage,
      });
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  function getGlucoseStatus(value: number): { symbol: string; status: string } {
    // Always use mmol/L for range checking
    const mmolValue = unit === 'mmol' ? value : value / 18.0;
    
    if (mmolValue < RANGE.LOW_THRESHOLD) {
      return { symbol: "🟡", status: "Low" };
    } else if (mmolValue > RANGE.HIGH_THRESHOLD) {
      return { symbol: "🔴", status: "High" };
    }
    return { symbol: "🟢", status: "In Range" };
  }

  function generateAverageDisplay() {
    if (readings.length === 0) return "";

    const values = readings.map(r => unit === 'mmol' ? r.Value : r.ValueInMgPerDl);
    const average = values.reduce((a, b) => a + b, 0) / values.length;
    const { symbol, status } = getGlucoseStatus(average);
    const unit_label = unit === 'mmol' ? 'mmol/L' : 'mg/dL';

    // Convert to mmol/L for gauge if needed
    const mmolAvg = unit === 'mmol' ? average : average / 18.0;
    
    // Create a gauge with markers
    const gaugeWidth = 34;  // Width of the gauge line
    let gauge = "     Low        In Range        High\n";
    gauge += "     3──────────10──────────────25\n";
    gauge += "     └──────────┴──────────────┘\n";
    
    // Calculate position for the indicator (▲)
    // Scale between 3 and 25 mmol/L
    const minScale = 3;
    const maxScale = 25;
    const scaleRange = maxScale - minScale;
    const normalizedPos = Math.min(Math.max(mmolAvg, minScale), maxScale);
    const positionRatio = (normalizedPos - minScale) / scaleRange;
    const maxPosition = 26; // Reduced maximum position to align just before 25
    const position = Math.round(positionRatio * maxPosition);
    
    // Ensure the value doesn't go beyond the gauge width
    const clampedPosition = Math.min(position, maxPosition);
    const spaces = " ".repeat(5 + clampedPosition); // 5 spaces for left margin
    
    // Add the indicator and value, ensuring they align with the gauge
    gauge += `${spaces}▲\n`;
    gauge += `${spaces}${mmolAvg.toFixed(1)}`;

    return `## 24-Hour Average: ${average.toFixed(1)}${unit_label} ${symbol}
${status}

${gauge}
`;
  }

  function generateBarChart() {
    if (readings.length === 0) {
      return "No glucose readings available. Make sure your LibreView account is connected and has recent readings.";
    }

    const values = readings.map(r => unit === 'mmol' ? r.Value : r.ValueInMgPerDl);
    const maxValue = Math.max(...values);
    const chartHeight = 10;
    const scale = chartHeight / maxValue;

    return readings
      .map(reading => {
        try {
          const value = unit === 'mmol' ? reading.Value : reading.ValueInMgPerDl;
          const barHeight = Math.round(value * scale);
          const { symbol, status } = getGlucoseStatus(value);
          const bar = symbol.repeat(barHeight);
          
          // Parse the Timestamp field from the API
          const [datePart, timePart, period] = reading.Timestamp.split(' ');
          const [month, day, year] = datePart.split('/');
          const [hours, minutes, seconds] = timePart.split(':');
          let hour = parseInt(hours);
          
          // Convert to 24-hour format if PM
          if (period === 'PM' && hour !== 12) {
            hour += 12;
          } else if (period === 'AM' && hour === 12) {
            hour = 0;
          }
          
          const timestamp = new Date(
            parseInt(year),
            parseInt(month) - 1,
            parseInt(day),
            hour,
            parseInt(minutes),
            parseInt(seconds)
          );

          if (isNaN(timestamp.getTime())) {
            console.warn('Invalid timestamp:', reading.Timestamp);
            return null;
          }

          const time = format(timestamp, "HH:mm");
          const unit_label = unit === 'mmol' ? 'mmol/L' : 'mg/dL';
          
          return `${time} ${value.toFixed(1)}${unit_label} (${status})\n${bar}`;
        } catch (error) {
          console.warn('Error formatting reading:', error);
          return null;
        }
      })
      .filter(Boolean)
      .join("\n\n");
  }

  const handleLogout = useCallback(async () => {
    await logout();
    // After logout, open preferences to prompt for re-login
    await openExtensionPreferences();
  }, []);

  // Check if credentials are missing
  if (!credentials.username || !credentials.password) {
    return (
      <Detail
        markdown={`# LibreView Login Required

Please follow these steps to set up your connection:

1. First Time Setup:
   - Download the LibreLinkUp mobile app
   - Create a LibreView account if you don't have one
   - Add the account that has the Libre sensor
   - Wait for them to accept the invitation

2. Configure Extension:
   - Click the "Open Preferences" button below
   - Enter your LibreView account email
   - Enter your LibreView account password
   - Select your preferred glucose unit (mmol/L or mg/dL)

Your data will appear here once you've completed these steps.

Need help? Visit [LibreView Support](https://www.libreview.com/support)`}
        actions={
          <ActionPanel>
            <Action
              title="Open Preferences"
              icon={Icon.Gear}
              onAction={openExtensionPreferences}
            />
          </ActionPanel>
        }
      />
    );
  }

  const markdown = `# Glucose Readings (Last 24 Hours)

${isLoading ? "Loading..." : generateAverageDisplay()}

## Readings
${isLoading ? "Loading..." : generateBarChart()}

${!isLoading && readings.length > 0 ? `
Legend:
 In Range (${RANGE.LOW_THRESHOLD}-${RANGE.HIGH_THRESHOLD} mmol/L)
 Low (< ${RANGE.LOW_THRESHOLD} mmol/L)
 High (> ${RANGE.HIGH_THRESHOLD} mmol/L)
` : ''}
`;

  return (
    <Detail 
      markdown={error ? "# Error Loading Data\n\n" + error : markdown}
      isLoading={isLoading}
      actions={
        <ActionPanel>
          <Action
            title="Refresh"
            icon={Icon.ArrowClockwise}
            onAction={loadData}
            shortcut={{ modifiers: ["cmd"], key: "r" }}
          />
          <Action
            title="Logout"
            icon={Icon.ExitFullScreen}
            onAction={handleLogout}
            shortcut={{ modifiers: ["cmd"], key: "l" }}
          />
          <Action
            title="Open Preferences"
            icon={Icon.Gear}
            onAction={openExtensionPreferences}
          />
        </ActionPanel>
      }
    />
  );
}
