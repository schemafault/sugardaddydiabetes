import React, { useState } from "react";
import { List, Icon, Action, ActionPanel } from "@raycast/api";
import { GlucoseReading } from "../types";
import { format } from "date-fns";
import { getValueColor } from "../utils/glucose";

interface GlucoseChartViewProps {
  readings: GlucoseReading[];
  unit: "mmol" | "mgdl";
}

export const GlucoseChartView: React.FC<GlucoseChartViewProps> = ({ readings, unit }) => {
  const [timeRange, setTimeRange] = useState<"day" | "week" | "month">("day");

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

  return (
    <List navigationTitle={`Glucose Readings - ${navigationTitle}`}>
      <List.Section title="Time Range">
        <List.Item 
          title="Last 24 Hours" 
          icon={timeRange === "day" ? Icon.CheckCircle : Icon.Circle}
          actions={
            <ActionPanel>
              <Action title="View 24-Hour Readings" onAction={() => setTimeRange("day")} />
            </ActionPanel>
          }
        />
        <List.Item 
          title="Last 7 Days" 
          icon={timeRange === "week" ? Icon.CheckCircle : Icon.Circle}
          actions={
            <ActionPanel>
              <Action title="View 7-Day Readings" onAction={() => setTimeRange("week")} />
            </ActionPanel>
          }
        />
        <List.Item 
          title="Last 30 Days" 
          icon={timeRange === "month" ? Icon.CheckCircle : Icon.Circle}
          actions={
            <ActionPanel>
              <Action title="View 30-Day Readings" onAction={() => setTimeRange("month")} />
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
          const valueColor = getValueColor(value, unit);
          
          return (
            <List.Item
              key={reading.Timestamp}
              title={`${value.toFixed(1)} ${unit === "mmol" ? "mmol/L" : "mg/dL"}`}
              subtitle={format(new Date(reading.Timestamp), "MMM d, h:mm a")}
              icon={{ source: Icon.Circle, tintColor: valueColor }}
            />
          );
        })}
      </List.Section>
    </List>
  );
}; 