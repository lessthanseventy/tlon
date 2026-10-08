// The floor's light as a pure function of the clock, on the same hours as the windows' sky
// (`WideRoom.windows`): dusk 18:30 to 20:30, dawn 6:00 to 7:30.

/** 0 in full day, 1 in full dark, a straight slope across dusk and dawn */
export function darkness(hour: number): number {
  if (hour >= 7.5 && hour < 18.5) return 0
  if (hour >= 18.5 && hour < 20.5) return (hour - 18.5) / 2
  if (hour >= 6 && hour < 7.5) return (7.5 - hour) / 1.5
  return 1
}

/** how many of `n` lamps are on: the first as the light starts to fail, the last in full dark */
export const lampsLit = (hour: number, n: number): number => Math.ceil(darkness(hour) * n)

/** full dark: the pets turn in, and you are off the clock */
export const dark = (hour: number): boolean => darkness(hour) === 1
