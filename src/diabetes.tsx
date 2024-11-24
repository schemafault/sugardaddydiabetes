import { Action, ActionPanel, Detail, List, showToast, Toast, Icon, openExtensionPreferences } from "@raycast/api";
import { useEffect, useState } from "react";
import { format } from "date-fns";
import { glucoseStore } from "./store";
import { GlucoseReading } from "./types";
import { getLibreViewCredentials } from "./preferences";
import { logout } from "./auth";

export default function Command() {
  const [readings, setReadings] = useState<GlucoseReading[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { unit } = getLibreViewCredentials();

  useEffect(() => {
    async function fetchData() {
      try {
        setIsLoading(true);
        const data = await glucoseStore.getReadings(true);
        setReadings(data);
        setError(null);
      } catch (e) {
        const message = e instanceof Error ? e.message : "Unknown error";
        setError(message);
        await showToast({
          style: Toast.Style.Failure,
          title: "Error fetching glucose data",
          message
        });
      } finally {
        setIsLoading(false);
      }
    }

    fetchData();
    const interval = setInterval(() => {
      glucoseStore.getReadings(false).then(setReadings).catch(console.error);
    }, 5 * 60 * 1000);

    return () => clearInterval(interval);
  }, []);

  const getValueColor = (value: number): string => {
    const lowThreshold = unit === 'mmol' ? 3.9 : 70;
    const highThreshold = unit === 'mmol' ? 10.0 : 180;
    
    if (value < lowThreshold) return '#EAB308'; // Yellow for low
    if (value > highThreshold) return '#EF4444'; // Red for high
    return '#10B981'; // Green for normal
  };

  if (error) {
    return <Detail markdown={`# Error\n\n${error}`} />;
  }

  return (
    <List
      isLoading={isLoading}
      searchBarPlaceholder="Search glucose readings..."
    >
      {readings.map((reading, index) => {
        const value = unit === 'mmol' ? reading.Value : reading.ValueInMgPerDl;
        const trend = index > 0 
          ? value > readings[index - 1].Value + 0.3 
            ? "↑" 
            : value < readings[index - 1].Value - 0.3 
              ? "↓" 
              : "→"
          : "→";

        return (
          <List.Item
            key={reading.Timestamp}
            title={`${value.toFixed(1)} ${unit === 'mmol' ? 'mmol/L' : 'mg/dL'} ${trend}`}
            subtitle={format(new Date(reading.Timestamp), 'MMM d, h:mm a')}
            icon={{ source: Icon.Circle, tintColor: getValueColor(value) }}
            accessories={[
              {
                text: reading.TrendArrow || '-',
                tooltip: "Trend direction"
              }
            ]}
            actions={
              <ActionPanel>
                <Action.CopyToClipboard
                  title="Copy Reading"
                  content={`${value.toFixed(1)} ${unit === 'mmol' ? 'mmol/L' : 'mg/dL'}`}
                />
                <Action.CopyToClipboard
                  title="Copy Time"
                  content={format(new Date(reading.Timestamp), 'MMM d, h:mm a')}
                />
                <Action
                  title="Refresh"
                  icon={Icon.ArrowClockwise}
                  onAction={() => glucoseStore.getReadings(true).then(setReadings)}
                />
                <Action
                  title="Preferences"
                  icon={Icon.Gear}
                  onAction={openExtensionPreferences}
                />
                <Action
                  title="Logout"
                  icon={Icon.Terminal}
                  onAction={logout}
                />
              </ActionPanel>
            }
          />
        );
      })}
    </List>
  );
}
