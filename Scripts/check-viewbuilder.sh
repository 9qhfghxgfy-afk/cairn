#!/usr/bin/env bash
# Catch the class of Swift error a parse-only check cannot see.
#
# `var body: some View` gets a result builder from the `View` protocol requirement. A hand-written
# `var somethingElse: some View` gets none, so a body holding two sibling `Section`s is not a tuple of
# views — it is "function declares an opaque return type, but has no return statements in its body",
# which is how CI 44660409341 died. The fix is one attribute, `@ViewBuilder`, and it is worth catching
# here rather than six minutes into a macOS build.
#
# Heuristic, not a parser: brace counting inside string interpolation can miscount, so this reports
# candidates for a human to confirm. Silence means no candidate, not proof of correctness.
set -uo pipefail

if [ "$#" -eq 0 ]; then
  # No arguments means "scan the tree the way CI does", so the call inside `Scripts/ci.sh guards`
  # and a call from a laptop look the same.
  set -- $(find Packages App Tests -name '*.swift' -type f 2>/dev/null)
fi

status=0
for file in "$@"; do
  [ -f "$file" ] || continue
  out=$(awk '
    function report() {
      if (inprop && top >= 2 && !decorated) {
        printf "%s:%d: var %s — %d top-level views, no @ViewBuilder\n", FILENAME, declnr, name, top
        status = 1
      }
      inprop = 0
    }
    {
      line = $0
      if (inprop) {
        stripped = line
        gsub(/^[ \t]+/, "", stripped)
        if (depth == 1 && stripped ~ /^(Section|VStack|HStack|ZStack|Group|Form|List|Text|Image|Link|if |ForEach|Button|LabeledContent|ScrollView|InfoRow|InfoSectionHeader|SectionHeader|InfoButton|EmptyView|Divider|Spacer|DisclosureGroup|NavigationLink|Toggle|Picker|Menu|Slider|Stepper|TextField|SecureField|ProgressView|ContentUnavailableView|TabView)/) top++
        opens = gsub(/\{/, "{", line)
        closes = gsub(/\}/, "}", line)
        depth += opens - closes
        if (depth <= 0) report()
        prev = $0
        next
      }
      if ($0 ~ /some View[ ]*\{[ ]*$/ && $0 !~ /var body[ ]*:/) {
        declnr = NR
        # The attribute may sit on the line above or on the same line as the declaration.
        decorated = (prev ~ /@ViewBuilder/ || $0 ~ /@ViewBuilder/) ? 1 : 0
        name = $0
        sub(/.*(var|func) /, "", name); sub(/[^A-Za-z0-9_].*/, "", name)
        inprop = 1; depth = 1; top = 0
      }
      prev = $0
    }
    END { if (inprop) report() }
  ' "$file")
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    status=1
  fi
done

if [ "$status" -ne 0 ]; then
  echo "candidate found: add @ViewBuilder, or wrap the body in a Group"
  exit 1
fi
echo "ok: no multi-view property without @ViewBuilder"
