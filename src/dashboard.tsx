import { Detail } from "@raycast/api";
import { useEffect, useState } from "react";
import { glucoseStore } from "./store";
import { GlucoseReading } from "./types";
import { format } from "date-fns";
import { getLibreViewCredentials } from "./preferences";

export default function Command() {
  const [readings, setReadings] = useState<GlucoseReading[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const { unit } = getLibreViewCredentials();

  useEffect(() => {
    async function fetchData() {
      try {
        setIsLoading(true);
        const data = await glucoseStore.getReadings(false);
        setReadings(data);
      } catch (error) {
        console.error("Error fetching data:", error);
      } finally {
        setIsLoading(false);
      }
    }
    fetchData();
  }, []);

  const generateBarChart = () => {
    if (readings.length === 0) return "No data available";

    const last24Readings = readings.slice(0, 24).reverse();
    const chartHeight = 8;

    return last24Readings.map(reading => {
      const value = unit === 'mmol' ? reading.Value : reading.ValueInMgPerDl;
      const barHeight = unit === 'mmol' 
        ? Math.round((value / 20) * chartHeight)  // For mmol/L (0-20 range)
        : Math.round((value / 360) * chartHeight); // For mg/dL (0-360 range)
      
      const bar = '█'.repeat(Math.min(barHeight, chartHeight)) + 
                  '░'.repeat(Math.max(0, chartHeight - barHeight));
      
      const datetime = format(new Date(reading.Timestamp), 'MM/dd HH:mm');
      return `${bar} ${value.toFixed(1)}${unit === 'mmol' ? ' mmol/L' : ' mg/dL'} (${datetime})`;
    }).join('\n');
  };

  const calculateStats = () => {
    if (readings.length === 0) return null;

    const last24h = readings.slice(0, 24);
    const values = last24h.map(r => unit === 'mmol' ? r.Value : r.ValueInMgPerDl);
    
    const avg = values.reduce((a, b) => a + b, 0) / values.length;
    const lowThreshold = unit === 'mmol' ? 3.9 : 70;
    const highThreshold = unit === 'mmol' ? 10.0 : 180;
    
    const low = last24h.filter(r => (unit === 'mmol' ? r.Value : r.ValueInMgPerDl) < lowThreshold).length;
    const high = last24h.filter(r => (unit === 'mmol' ? r.Value : r.ValueInMgPerDl) > highThreshold).length;
    const normal = last24h.length - low - high;

    return {
      average: avg.toFixed(1),
      timeInRange: ((normal / last24h.length) * 100).toFixed(1),
      lowPercentage: ((low / last24h.length) * 100).toFixed(1),
      highPercentage: ((high / last24h.length) * 100).toFixed(1)
    };
  };

  const stats = calculateStats();
  const markdown = `
# Glucose Dashboard

${stats ? `
## Current Statistics (Last 24h)
- Average: ${stats.average} ${unit === 'mmol' ? 'mmol/L' : 'mg/dL'}
- Time in Range: ${stats.timeInRange}%
- Below Range: ${stats.lowPercentage}%
- Above Range: ${stats.highPercentage}%
- Last Updated: ${format(new Date(), 'MMM d, h:mm a')}
` : ''}

## Last 24 Hours Trend
\`\`\`
${generateBarChart()}
\`\`\`
`;

  return <Detail markdown={markdown} isLoading={isLoading} />;
} 