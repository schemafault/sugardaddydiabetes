import { useState, useEffect } from "react";
import { Detail, Grid, Icon, List, showToast, Toast, Action, ActionPanel } from "@raycast/api";
import { glucoseStore } from "./store";
import { getLibreViewCredentials } from "./preferences";
import { isLoggedOut as checkLoggedOut, attemptLogin } from "./auth";
import * as d3 from "d3";
import { GlucoseReading } from "./types";

export default function Command() {
  const [readings, setReadings] = useState<GlucoseReading[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [isLoggedOut, setIsLoggedOut] = useState(false);
  const [timeRange, setTimeRange] = useState<"day" | "week" | "month">("day");
  const { unit } = getLibreViewCredentials();

  const fetchData = async () => {
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
      const data = await glucoseStore.getReadings(true);
      setReadings(data);
    } catch (err) {
      console.error("Error fetching data:", err);
      const errorObj = err instanceof Error ? err : new Error("Unknown error fetching data");
      setError(errorObj);
      
      if (err instanceof Error && err.message.includes("Missing LibreView credentials")) {
        setIsLoggedOut(true);
      }
      
      showToast({
        style: Toast.Style.Failure,
        title: "Error fetching data",
        message: errorObj.message,
      });
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, []);

  // Filter readings based on selected time range
  const filteredReadings = (() => {
    const now = new Date();
    let startDate = new Date();
    
    switch (timeRange) {
      case "day":
        startDate.setDate(now.getDate() - 1);
        break;
      case "week":
        startDate.setDate(now.getDate() - 7);
        break;
      case "month":
        startDate.setMonth(now.getMonth() - 1);
        break;
    }
    
    return readings.filter(
      (reading) => new Date(reading.Timestamp) >= startDate && new Date(reading.Timestamp) <= now
    );
  })();

  // Format statistics for the selected time range
  const calculateStats = () => {
    if (!filteredReadings.length) return null;
    
    const values = filteredReadings.map((r) => (unit === "mmol" ? r.Value : r.ValueInMgPerDl));
    const avg = values.reduce((a, b) => a + b, 0) / values.length;

    const lowThreshold = unit === "mmol" ? 4.0 : 72;
    const highThreshold = unit === "mmol" ? 10.0 : 180;

    const low = filteredReadings.filter(
      (r) => (unit === "mmol" ? r.Value : r.ValueInMgPerDl) < lowThreshold
    ).length;
    const high = filteredReadings.filter(
      (r) => (unit === "mmol" ? r.Value : r.ValueInMgPerDl) > highThreshold
    ).length;
    const normal = filteredReadings.length - low - high;

    return {
      average: avg.toFixed(1),
      timeInRange: ((normal / filteredReadings.length) * 100).toFixed(1),
      lowPercentage: ((low / filteredReadings.length) * 100).toFixed(1),
      highPercentage: ((high / filteredReadings.length) * 100).toFixed(1),
      readingsCount: filteredReadings.length,
      normal,
      low,
      high
    };
  };

  const stats = calculateStats();

  const navigationTitle = 
    timeRange === "day" ? "Last 24 Hours" : 
    timeRange === "week" ? "Last 7 Days" : 
    "Last 30 Days";

  if (isLoggedOut) {
    return (
      <Detail
        markdown="## Login Required
        
Please enter your LibreView credentials in the extension preferences to view your glucose data."
      />
    );
  }

  if (isLoading) {
    return <Detail isLoading={true} markdown="Loading glucose data..." />;
  }

  if (error) {
    return (
      <Detail
        markdown={`## Error Loading Data
        
${error.message}`}
      />
    );
  }

  if (filteredReadings.length === 0) {
    return (
      <Detail
        navigationTitle={`Glucose Chart - ${navigationTitle}`}
        markdown={`## No Data Available
        
No glucose readings found for the selected time range: ${navigationTitle}`}
        metadata={
          <Detail.Metadata>
            <Detail.Metadata.TagList title="Time Range">
              <Detail.Metadata.TagList.Item 
                text="Last 24 Hours" 
                color={timeRange === "day" ? "#007AFF" : "#8E8E93"} 
                onAction={() => setTimeRange("day")}
              />
              <Detail.Metadata.TagList.Item 
                text="Last 7 Days" 
                color={timeRange === "week" ? "#007AFF" : "#8E8E93"} 
                onAction={() => setTimeRange("week")}
              />
              <Detail.Metadata.TagList.Item 
                text="Last 30 Days" 
                color={timeRange === "month" ? "#007AFF" : "#8E8E93"} 
                onAction={() => setTimeRange("month")}
              />
            </Detail.Metadata.TagList>
          </Detail.Metadata>
        }
      />
    );
  }

  return (
    <List isLoading={isLoading} searchBarPlaceholder="Filter readings...">
      <List.Section title="Chart View">
        <List.Item 
          title="Last 24 Hours" 
          icon={timeRange === "day" ? Icon.CheckCircle : Icon.Circle}
          actions={
            <ActionPanel>
              <Action title="View 24-Hour Chart" onAction={() => setTimeRange("day")} />
            </ActionPanel>
          }
        />
        <List.Item 
          title="Last 7 Days" 
          icon={timeRange === "week" ? Icon.CheckCircle : Icon.Circle}
          actions={
            <ActionPanel>
              <Action title="View 7-Day Chart" onAction={() => setTimeRange("week")} />
            </ActionPanel>
          }
        />
        <List.Item 
          title="Last 30 Days" 
          icon={timeRange === "month" ? Icon.CheckCircle : Icon.Circle}
          actions={
            <ActionPanel>
              <Action title="View 30-Day Chart" onAction={() => setTimeRange("month")} />
            </ActionPanel>
          }
        />
      </List.Section>

      {stats && (
        <List.Section title={`Statistics (${navigationTitle})`}>
          <List.Item 
            title={`Average: ${stats.average} ${unit === "mmol" ? "mmol/L" : "mg/dL"}`} 
            icon={Icon.Circle} 
          />
          <List.Item 
            title={`Time in Range: ${stats.timeInRange}%`} 
            icon={Icon.Circle} 
            accessories={[{ text: `${stats.normal} readings` }]}
          />
          <List.Item 
            title={`Below Range: ${stats.lowPercentage}%`} 
            icon={{ source: Icon.Circle, tintColor: "#EAB308" }}
            accessories={[{ text: `${stats.low} readings` }]} 
          />
          <List.Item 
            title={`Above Range: ${stats.highPercentage}%`} 
            icon={{ source: Icon.Circle, tintColor: "#EF4444" }}
            accessories={[{ text: `${stats.high} readings` }]} 
          />
          <List.Item 
            title={`Total Readings: ${stats.readingsCount}`} 
            icon={Icon.List} 
          />
        </List.Section>
      )}

      <List.Section title="Readings">
        {filteredReadings.map((reading) => {
          const value = unit === "mmol" ? reading.Value : reading.ValueInMgPerDl;
          const valueColor = 
            value < (unit === "mmol" ? 4.0 : 72) ? "#EAB308" : 
            value > (unit === "mmol" ? 10.0 : 180) ? "#EF4444" : 
            "#10B981";
          
          return (
            <List.Item
              key={reading.Timestamp}
              title={`${value.toFixed(1)} ${unit === "mmol" ? "mmol/L" : "mg/dL"}`}
              subtitle={new Date(reading.Timestamp).toLocaleString()}
              icon={{ source: Icon.Circle, tintColor: valueColor }}
            />
          );
        })}
      </List.Section>
    </List>
  );
} 