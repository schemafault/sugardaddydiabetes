import { MenuBarExtra } from "@raycast/api";
import { useEffect, useState } from "react";
import { fetchGlucoseData } from "./libreview";
import { getLibreViewCredentials } from "./preferences";
import { GlucoseReading } from "./types";

export default function Command() {
  const [latestReading, setLatestReading] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const credentials = getLibreViewCredentials();
  const unit = credentials.unit || 'mmol';

  useEffect(() => {
    async function loadData() {
      try {
        const data = await fetchGlucoseData();
        if (data && data.length > 0) {
          const latest = data[0];
          const value = unit === 'mmol' ? latest.Value : latest.ValueInMgPerDl;
          const unit_label = unit === 'mmol' ? 'mmol/L' : 'mg/dL';
          
          // Determine status emoji
          let statusEmoji = "🟢";
          const mmolValue = unit === 'mmol' ? value : value / 18.0;
          if (mmolValue < 3.0) {
            statusEmoji = "🟡";
          } else if (mmolValue > 10.0) {
            statusEmoji = "🔴";
          }
          
          setLatestReading(`${value.toFixed(1)}${unit_label} ${statusEmoji}`);
        } else {
          setLatestReading("No data");
        }
      } catch (error) {
        console.error('Error fetching glucose data:', error);
        setLatestReading("Error");
      } finally {
        setIsLoading(false);
      }
    }

    loadData();
    // Refresh data every 5 minutes
    const interval = setInterval(loadData, 5 * 60 * 1000);
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
    </MenuBarExtra>
  );
}
