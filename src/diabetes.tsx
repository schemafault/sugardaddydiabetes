import { Detail, Toast, showToast } from "@raycast/api";
import { useEffect, useState } from "react";
import { fetchGlucoseData } from "./libreview";
import { format } from "date-fns";
import { getLibreViewCredentials } from "./preferences";

// Glucose range constants (mmol/L)
const RANGE = {
  LOW_THRESHOLD: 3.0,
  HIGH_THRESHOLD: 10.0
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
  const { unit } = getLibreViewCredentials();

  useEffect(() => {
    async function loadData() {
      try {
        const data = await fetchGlucoseData();
        setReadings(data);
      } catch (error) {
        console.error('Error fetching glucose data:', error);
        await showToast({
          style: Toast.Style.Failure,
          title: "Failed to load glucose data",
          message: error instanceof Error ? error.message : "Unknown error",
        });
      } finally {
        setIsLoading(false);
      }
    }

    loadData();
  }, []);

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

  const markdown = `# Glucose Readings (Last 24 Hours)
${isLoading ? "Loading..." : generateBarChart()}

${!isLoading && readings.length > 0 ? `
Legend:
🟢 In Range (${RANGE.LOW_THRESHOLD}-${RANGE.HIGH_THRESHOLD} mmol/L)
🟡 Low (< ${RANGE.LOW_THRESHOLD} mmol/L)
🔴 High (> ${RANGE.HIGH_THRESHOLD} mmol/L)
` : ''}
`;

  return <Detail markdown={markdown} isLoading={isLoading} />;
}
