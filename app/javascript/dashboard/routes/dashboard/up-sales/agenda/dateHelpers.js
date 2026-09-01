// Small date-grid helpers shared by MonthView/TimeGridView — plain Date math, no library, since the
// only thing Agenda needs is "start of day/week/month" and "add N of a unit", not full calendar
// arithmetic (timezones, DST edge cases are the browser's Date and Google's own ISO offsets to worry
// about, not ours).

export function startOfDay(date) {
  const d = new Date(date);
  d.setHours(0, 0, 0, 0);
  return d;
}

export function addDays(date, days) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

export function startOfWeek(date) {
  const d = startOfDay(date);
  d.setDate(d.getDate() - d.getDay());
  return d;
}

export function startOfMonth(date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

export function addMonths(date, months) {
  return new Date(date.getFullYear(), date.getMonth() + months, 1);
}

export function isSameDay(a, b) {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

// True for a Google Calendar all-day event ("date": "2026-09-04"), false for a timed one
// ("dateTime": "2026-09-04T10:00:00-03:00") — projectEvent (up2-agents) flattens both to a plain
// string, so length is the cheapest reliable discriminator.
export function isAllDayValue(value) {
  return typeof value === 'string' && value.length === 10;
}
