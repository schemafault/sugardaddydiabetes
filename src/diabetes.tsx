import { Detail, Toast, showToast } from "@raycast/api";
import { useEffect, useState } from "react";
import { fetchGlucoseData } from "./libreview";
import { format } from "date-fns";

interface GlucoseReading {
  Timestamp: string;
  ValueInMgPerDl: number;
}

export default function Command() {
  const [readings, setReadings] = useState<GlucoseReading[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    async function loadData() {
      try {
        const data = await fetchGlucoseData();
        console.log('Glucose data received:', JSON.stringify(data, null, 2));
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

  function generateBarChart() {
    if (readings.length === 0) {
      return "No glucose readings available. Make sure your LibreView account is connected and has recent readings.";
    }

    const maxValue = Math.max(...readings.map(r => r.ValueInMgPerDl));
    const chartHeight = 10;
    const scale = chartHeight / maxValue;

    return readings
      .map(reading => {
        try {
          const barHeight = Math.round(reading.ValueInMgPerDl * scale);
          const bar = "█".repeat(barHeight);
          
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
          return `${time} ${reading.ValueInMgPerDl}mg/dL\n${bar}`;
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
`;

  return <Detail markdown={markdown} isLoading={isLoading} />;
}
