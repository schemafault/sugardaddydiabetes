type GlucoseUnit = 'mmol' | 'mgdl';

export function getValueColor(value: number, unit: GlucoseUnit): string {
  // Convert mgdl to mmol for consistent comparison
  const mmolValue = unit === 'mgdl' ? value / 18 : value;
  
  // Low: < 4.0 mmol/L (72 mg/dL)
  if (mmolValue < 4.0) {
    return '#EAB308'; // yellow
  }
  
  // High: > 10.0 mmol/L (180 mg/dL)
  if (mmolValue > 10.0) {
    return '#EF4444'; // red
  }
  
  // Normal: between 4.0 and 10.0 mmol/L
  return '#10B981'; // green
} 