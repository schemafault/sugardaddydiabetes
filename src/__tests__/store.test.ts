import { glucoseStore } from "../store";
import { getLibreViewCredentials } from "../preferences";
import * as libreview from "../libreview";

jest.mock("../preferences", () => ({
  getLibreViewCredentials: () => ({
    username: "test@example.com",
    password: "password123",
    unit: "mmol"
  })
}));

jest.mock("../libreview", () => ({
  fetchGlucoseData: jest.fn().mockResolvedValue([])
}));

describe("GlucoseStore", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should return empty readings when no data exists", async () => {
    const readings = await glucoseStore.getReadings();
    expect(Array.isArray(readings)).toBe(true);
    expect(readings.length).toBe(0);
  });
}); 