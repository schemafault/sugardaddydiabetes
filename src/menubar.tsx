import { MenuBarExtra } from "@raycast/api";
import { useEffect, useState } from "react";
import { fetchGlucoseData } from "./libreview";
import { getLibreViewCredentials } from "./preferences";
import { GlucoseReading } from "./types";

export default function Command() {
  const [latestReading, setLatestReading] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdateTime, setLastUpdateTime] = useState<Date | null>(null);
  const credentials = getLibreViewCredentials();
  const unit = credentials.unit || 'mmol';

  useEffect(() => {
    async function loadData() {
      try {
        const readings = await fetchGlucoseData();
        
        if (readings && readings.length > 0) {
          // Get the last reading from the full dataset
          const latest = readings[readings.length - 1];
          const value = unit === 'mmol' ? latest.Value : latest.ValueInMgPerDl;
          const unit_label = unit === 'mmol' ? 'mmol/L' : 'mg/dL';
          
          // Use the reading's timestamp
          const readingTime = new Date(latest.Timestamp);
          
          // Determine status emoji
          let statusEmoji = "🟢";
          const mmolValue = unit === 'mmol' ? value : value / 18.0;
          if (mmolValue < 3.0) {
            statusEmoji = "🟡";
          } else if (mmolValue > 10.0) {
            statusEmoji = "🔴";
          }
          
          const displayText = `${value.toFixed(1)}${unit_label} ${statusEmoji}`;
          setLatestReading(displayText);
          setLastUpdateTime(readingTime);
        } else {
          setLatestReading("No data");
        }
      } catch (error) {
        console.error('Menu Bar - Error:', error);
        setLatestReading("Error");
      } finally {
        setIsLoading(false);
      }
    }

    loadData();
    // Refresh data every 10 minutes
    const interval = setInterval(loadData, 10 * 60 * 1000);
    return () => clearInterval(interval);
  }, [unit]);

  if (!latestReading && !isLoading) {
    return null;
  }

  return (
    <MenuBarExtra
      icon="🩸"
      title={isLoading ? "Loading..." : latestReading || "No data"}
    >
      <MenuBarExtra.Item
        title={isLoading ? "Updating..." : `Latest: ${latestReading}`}
      />
      {lastUpdateTime && (
        <MenuBarExtra.Item
          title={`Reading from: ${lastUpdateTime.toLocaleTimeString()}`}
        />
      )}
    </MenuBarExtra>
  );
}
