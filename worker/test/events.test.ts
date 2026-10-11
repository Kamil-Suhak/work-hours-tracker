import { describe, it, expect } from "vitest";
import { validateManualEventRequest, validateUpdateNoteRequest } from "../src/events";

describe("Admin Manual Events Validation", () => {
  it("rejects requests with missing reason", () => {
    expect(() =>
      validateManualEventRequest({
        clockInAt: "2026-10-02T06:00:00.000Z",
        clockOutAt: "2026-10-02T14:00:00.000Z",
        reason: "   ",
        requestId: "req-backfill-1",
      }),
    ).toThrow(/reason is required/);
  });

  it("rejects requests where clockOutAt is earlier than or equal to clockInAt", () => {
    expect(() =>
      validateManualEventRequest({
        clockInAt: "2026-10-02T14:00:00.000Z",
        clockOutAt: "2026-10-02T06:00:00.000Z",
        reason: "Backfill test",
        requestId: "req-backfill-2",
      }),
    ).toThrow(/clockOutAt must be strictly greater than clockInAt/);

    expect(() =>
      validateManualEventRequest({
        clockInAt: "2026-10-02T14:00:00.000Z",
        clockOutAt: "2026-10-02T14:00:00.000Z",
        reason: "Backfill test",
        requestId: "req-backfill-3",
      }),
    ).toThrow(/clockOutAt must be strictly greater than clockInAt/);
  });

  it("rejects requests exceeding maximum 24 hour shift duration", () => {
    expect(() =>
      validateManualEventRequest({
        clockInAt: "2026-10-01T06:00:00.000Z",
        clockOutAt: "2026-10-02T07:00:00.000Z", // 25 hours
        reason: "Extra long shift",
        requestId: "req-backfill-4",
      }),
    ).toThrow(/exceeds the maximum allowed 24h 0m/);
  });

  it("accepts valid historical shift backfills", () => {
    const valid = validateManualEventRequest({
      clockInAt: "2026-10-02T06:00:00.000Z",
      clockOutAt: "2026-10-02T14:00:00.000Z",
      reason: "Backfill for first work day",
      requestId: "req-backfill-5",
    });

    expect(valid.clockInAt).toBe("2026-10-02T06:00:00.000Z");
    expect(valid.clockOutAt).toBe("2026-10-02T14:00:00.000Z");
    expect(valid.reason).toBe("Backfill for first work day");
    expect(valid.requestId).toBe("req-backfill-5");
  });

  it("rejects manual shift notes exceeding 4,000 characters", () => {
    expect(() =>
      validateManualEventRequest({
        clockInAt: "2026-10-02T06:00:00.000Z",
        clockOutAt: "2026-10-02T14:00:00.000Z",
        reason: "Valid reason",
        requestId: "req-backfill-note-len",
        note: "a".repeat(4001),
      }),
    ).toThrow(/Note must not exceed 4,000 characters/);
  });
});

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
