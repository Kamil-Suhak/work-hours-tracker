import { describe, it, expect } from "vitest";
import { validateUpdateNoteRequest } from "../src/events";

describe("Event Note Update Tests", () => {
  it("validates note payload correctly", () => {
    expect(validateUpdateNoteRequest({ note: "Refactored worker" })).toEqual({
      note: "Refactored worker",
    });
    expect(validateUpdateNoteRequest({ note: "" })).toEqual({ note: null });
    expect(validateUpdateNoteRequest({ note: "   " })).toEqual({ note: null });
    expect(validateUpdateNoteRequest({ note: null })).toEqual({ note: null });
    expect(validateUpdateNoteRequest({})).toEqual({ note: null });

    expect(() => validateUpdateNoteRequest({ note: 123 })).toThrow(
      /note must be a string or null/,
    );
    expect(() =>
      validateUpdateNoteRequest({ note: "x".repeat(4001) }),
    ).toThrow(/Note must not exceed 4,000 characters/);
  });
});
