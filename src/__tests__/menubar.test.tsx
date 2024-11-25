import React from "react";
import { render } from "@testing-library/react";
import * as auth from "../auth";
import Command from "../menubar";

jest.mock("../auth");
jest.mock("../libreview", () => ({
  fetchGlucoseData: jest.fn().mockResolvedValue([])
}));

// Mock with exact structure needed by menubar.tsx
jest.mock("@raycast/api", () => ({
  MenuBarExtra: (props: any) => <div>{props.title || "Menu Bar"}</div>,
  getPreferenceValues: () => ({
    username: "test@example.com",
    password: "password123",
    unit: "mmol"
  }),
  Icon: { 
    Circle: "circle",
    Person: "person",
    XmarkCircle: "xmark.circle",
    ExclamationMark: "exclamationmark",
    ArrowClockwise: "arrow.clockwise",
    List: "list",
    Terminal: "terminal",
    Gear: "gear"
  },
  Color: { 
    SecondaryText: "#999",
    Red: "#FF0000",
    Green: "#00FF00",
    Yellow: "#FFFF00"
  },
  Toast: {
    Style: {
      Failure: "failure",
      Success: "success"
    }
  },
  showToast: jest.fn(),
  openExtensionPreferences: jest.fn(),
  popToRoot: jest.fn(),
  open: jest.fn()
}));

describe("MenuBar Command", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it("should render without crashing", () => {
    render(<Command />);
  });
}); 