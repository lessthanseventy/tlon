// The shape of a day and of a year, as pure functions of the clock: when the office breaks for lunch
// or heads home, and which season the date puts at the windows.

export type Rush = "lunch" | "leaving"

/** 12:00-12:30 the kitchen fills; 17:30-18:00 whoever is idle gathers at the door */
export function rushOf(now: Date): Rush | null {
  const m = now.getHours() * 60 + now.getMinutes()
  if (m >= 720 && m < 750) return "lunch"
  if (m >= 1050 && m < 1080) return "leaving"
  return null
}

export type Season = "spring" | "summer" | "pi" | "nye"

/** a day that is its own (Pi Day, New Year's Eve) wins over its month; spring is March-May, summer June-August; October, December and 14 February are the room's own and have no entry here */
export function seasonOf(date: Date): Season | null {
  const m = date.getMonth(), d = date.getDate()
  if (m === 2 && d === 14) return "pi"
  if (m === 11 && d === 31) return "nye"
  if (m >= 2 && m <= 4) return "spring"
  if (m >= 5 && m <= 7) return "summer"
  return null
}
