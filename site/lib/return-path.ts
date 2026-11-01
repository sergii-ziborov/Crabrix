// Dots may only join word characters, so no segment can be `.` or `..`, and every
// segment is non-empty, so the path can never become `//host` or leave /learn/.
const segment = "[a-z0-9_-]+(?:\\.[a-z0-9_-]+)*";
const learnPath = new RegExp(`^/learn/(?:${segment}/)*(?:${segment})?$`);

export function safeReturnPath(value: string) {
  return learnPath.test(value) ? value : "/learn/";
}
