import { MenuBarExtra, showToast, Toast, Icon, openExtensionPreferences, open } from "@raycast/api";
import { useEffect, useState, useCallback } from "react";
import { fetchGlucoseData } from "./libreview";
import { getLibreViewCredentials } from "./preferences";
import { logout } from "./auth";
import { GlucoseReading } from "./types";

interface GlucoseStats {
  average: number;
  timeInRange: {
    low: number;
    normal: number;
    high: number;
  };
}

export default function Command() {
  const [latestReading, setLatestReading] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [lastUpdateTime, setLastUpdateTime] = useState<Date | null>(null);
  const [stats, setStats] = useState<GlucoseStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const credentials = getLibreViewCredentials();
  const unit = credentials.unit || 'mmol';

  const calculateStats = (readings: GlucoseReading[]) => {
    const last24Hours = new Date();
    last24Hours.setHours(last24Hours.getHours() - 24);
    
    const recentReadings = readings.filter(r => new Date(r.Timestamp) >= last24Hours);
    if (recentReadings.length === 0) return null;

    const values = recentReadings.map(r => unit === 'mmol' ? r.Value : r.ValueInMgPerDl);
    const average = values.reduce((a, b) => a + b, 0) / values.length;

    const totalReadings = recentReadings.length;

    const lowCount = recentReadings.filter(r => {
      const value = unit === 'mmol' ? r.Value : r.Value / 18.0;
      return value < 3.9;
    }).length;
    const highCount = recentReadings.filter(r => {
      const value = unit === 'mmol' ? r.Value : r.Value / 18.0;
      return value > 10.0;
    }).length;
    const normalCount = totalReadings - lowCount - highCount;

    return {
      average,
      timeInRange: {
        low: (lowCount / totalReadings) * 100,
        normal: (normalCount / totalReadings) * 100,
        high: (highCount / totalReadings) * 100
      }
    };
  };

  const loadData = useCallback(async (showError = true) => {
    try {
      setIsLoading(true);
      setError(null);
      
      const readings = await fetchGlucoseData();
      
      if (readings && readings.length > 0) {
        // Calculate stats
        const glucoseStats = calculateStats(readings);
        setStats(glucoseStats);
        
        // Get the last reading from the full dataset
        const latest = readings[readings.length - 1];
        const value = unit === 'mmol' ? latest.Value : latest.ValueInMgPerDl;
        const unit_label = unit === 'mmol' ? ' mmol/L' : ' mg/dL';
        
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
        if (showError) {
          await showToast({
            style: Toast.Style.Failure,
            title: "No glucose readings available",
            message: "Please check your LibreView connection",
          });
        }
      }
    } catch (error) {
      console.error('Menu Bar - Error:', error);
      setLatestReading("Error");
      setError(error instanceof Error ? error.message : "Unknown error");
      if (showError) {
        await showToast({
          style: Toast.Style.Failure,
          title: "Failed to load glucose data",
          message: error instanceof Error ? error.message : "Unknown error",
        });
      }
    } finally {
      setIsLoading(false);
    }
  }, [unit]);

  const handleLogout = useCallback(async () => {
    await logout();
    // After logout, open preferences to prompt for re-login
    await openExtensionPreferences();
  }, []);

  useEffect(() => {
    // Initial load
    loadData(false);
    // Refresh data every 5 minutes to match package.json interval
    const interval = setInterval(() => loadData(false), 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, [loadData]);

  // Check if credentials are missing
  if (!credentials.username || !credentials.password) {
    return (
      <MenuBarExtra
        title="⚠️ Login Required"
      >
        <MenuBarExtra.Item
          title="Configure LibreView Account"
          icon={Icon.Person}
          onAction={openExtensionPreferences}
        />
        <MenuBarExtra.Separator />
        <MenuBarExtra.Item
          title="Download LibreLinkUp App"
          icon={Icon.Download}
          onAction={() => open("https://www.libreview.com/")}
        />
        <MenuBarExtra.Item
          title="LibreView Support"
          icon={Icon.QuestionMark}
          onAction={() => open("https://www.libreview.com/support")}
        />
      </MenuBarExtra>
    );
  }

  const title = isLoading 
    ? "Loading..." 
    : error 
    ? "⚠️ Error" 
    : latestReading || "No data";

  return (
    <MenuBarExtra
      title={title}
      onOpen={() => loadData(true)}
    >
      <MenuBarExtra.Item
        title={isLoading ? "Updating..." : `Latest: ${latestReading}`}
      />
      {error && (
        <MenuBarExtra.Item
          title={`Error: ${error}`}
        />
      )}
      {lastUpdateTime && (
        <MenuBarExtra.Item
          title={`Reading from: ${lastUpdateTime.toLocaleTimeString()}`}
        />
      )}
      {stats && (
        <>
          <MenuBarExtra.Separator />
          <MenuBarExtra.Item
            title={`24h Average: ${stats.average.toFixed(1)}${unit === 'mmol' ? ' mmol/L' : ' mg/dL'}`}
          />
          <MenuBarExtra.Item
            title="Time in Range (24h)"
          />
          <MenuBarExtra.Item
            title={`🟢 In Range: ${stats.timeInRange.normal.toFixed(1)}%`}
          />
          <MenuBarExtra.Item
            title={`🟡 Low: ${stats.timeInRange.low.toFixed(1)}%`}
          />
          <MenuBarExtra.Item
            title={`🔴 High: ${stats.timeInRange.high.toFixed(1)}%`}
          />
          <MenuBarExtra.Separator />
          <MenuBarExtra.Item
            title="Refresh"
            icon={Icon.ArrowClockwise}
            onAction={() => loadData(true)}
          />
          <MenuBarExtra.Item
            title="Logout"
            icon={Icon.ExitFullScreen}
            onAction={handleLogout}
          />
          <MenuBarExtra.Item
            title="Preferences"
            icon={Icon.Gear}
            onAction={openExtensionPreferences}
          />
        </>
      )}
    </MenuBarExtra>
  );
}
