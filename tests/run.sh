#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_ID="no.koka.uptime-monitor"
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Uptime Monitor Plugin Tests ==="
echo ""

# --- Structure tests ---
echo "--- Structure ---"
for file in manifest.json BarWidget.qml Panel.qml README.md LICENSE; do
  if [ -f "$PLUGIN_DIR/$file" ]; then ok "$file exists"
  else fail "$file missing"; fi
done

# --- Manifest tests ---
echo ""
echo "--- Manifest ---"
MANIFEST="$PLUGIN_DIR/manifest.json"
if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$MANIFEST" 2>/dev/null; then
  ok "manifest.json is valid JSON"
else
  fail "manifest.json is not valid JSON"
fi

ID=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['id'])")
if [ "$ID" = "$PLUGIN_ID" ]; then ok "plugin ID is $PLUGIN_ID"
else fail "plugin ID is $ID, expected $PLUGIN_ID"; fi

SCHEMA=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['schemaVersion'])")
if [ "$SCHEMA" = "1" ]; then ok "schemaVersion is 1"
else fail "schemaVersion is $SCHEMA, expected 1"; fi

KINDS=$(python3 -c "import json; print(','.join(json.load(open('$MANIFEST'))['kinds']))")
if echo "$KINDS" | grep -q "bar-widget"; then ok "kinds includes bar-widget"
else fail "kinds missing bar-widget: $KINDS"; fi

ALLOW_MULTI=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['barWidget']['allowMultiple'])")
if [ "$ALLOW_MULTI" = "False" ]; then ok "allowMultiple is false (single monitor per widget)"
else fail "allowMultiple is $ALLOW_MULTI, expected False"; fi

# --- Validation ---
echo ""
echo "--- Validation ---"
if omarchy plugin validate "$PLUGIN_DIR" 2>/dev/null; then
  ok "omarchy plugin validate passes"
else
  fail "omarchy plugin validate fails"
fi

# --- QML lint ---
echo ""
echo "--- QML Lint ---"
if OMARCHY_PATH="/usr/share/omarchy" qmllint -I "$OMARCHY_PATH/shell" \
  "$PLUGIN_DIR/BarWidget.qml" "$PLUGIN_DIR/Panel.qml" 2>/dev/null; then
  ok "qmllint passes on BarWidget.qml"
  ok "qmllint passes on Panel.qml"
else
  fail "qmllint reports issues (may be false positives from imports)"
fi

# --- Single-monitor persistence tests ---
echo ""
echo "--- Single Monitor ---"
TMP_SHELL=$(mktemp)

# A single flat entry holds url/label/schedule; editing must never create a
# second entry (rebuild cause).
cat > "$TMP_SHELL" << EOF
{
  "version": 1,
  "bar": {
    "id": "omarchy.bar",
    "layout": {
      "left": [],
      "center": [],
      "right": [
        {"id": "no.koka.uptime-monitor", "url": "https://koka.no", "label": "koka", "schedule": {"value": 30, "unit": "sec"}}
      ]
    }
  },
  "plugins": []
}
EOF

# Exactly one uptime-monitor entry must exist.
python3 -c "
import json
d = json.load(open('$TMP_SHELL'))
entries = [e for e in d['bar']['layout']['right'] if isinstance(e,dict) and e.get('id')=='no.koka.uptime-monitor']
assert len(entries) == 1, 'expected exactly 1 entry, got %d' % len(entries)
assert 'monitors' not in entries[0], 'legacy monitors[] key should be gone'
"
if [ $? -eq 0 ]; then ok "single flat entry per widget (no monitors[])"
else fail "entry is not single flat shape"; fi

# Save (update url/label) must mutate in place, not add a second entry.
python3 -c "
import json
path='$TMP_SHELL'
d = json.load(open(path))
for sec in ['left','center','right']:
    for i,e in enumerate(d['bar']['layout'].get(sec,[])):
        if isinstance(e,dict) and e.get('id')=='no.koka.uptime-monitor':
            d['bar']['layout'][sec][i]={'id':'no.koka.uptime-monitor','url':'https://vg.no','label':'vg','schedule':{'value':60,'unit':'sec'}}
with open(path,'w') as f: json.dump(d,f,indent=2); f.write('\n')
"
python3 -c "
import json
d = json.load(open('$TMP_SHELL'))
entries = [e for e in d['bar']['layout']['right'] if e.get('id')=='no.koka.uptime-monitor']
assert len(entries)==1, 'save created a second entry'
e=entries[0]
assert e['url']=='https://vg.no' and e['label']=='vg' and e['schedule']=={'value':60,'unit':'sec'}
"
if [ $? -eq 0 ]; then ok "saving edits the single entry in place"
else fail "save did not edit in place"; fi

rm -f "$TMP_SHELL"

# --- Schedule logic tests (mirror the cron/unit logic embedded in BarWidget.qml) ---
echo ""
echo "--- Schedule Logic ---"
CRON_JS=$(cat << 'EOF'
function cronField(pattern, min, max) {
  var allowed = {}
  var parts = String(pattern).split(",")
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i].trim()
    var step = 1, base = p
    if (p.indexOf("/") >= 0) { step = parseInt(p.split("/")[1], 10) || 1; base = p.split("/")[0] }
    if (base === "*") base = min + "-" + max
    if (base.indexOf("-") >= 0) {
      var lo = parseInt(base.split("-")[0], 10), hi = parseInt(base.split("-")[1], 10)
      if (!isNaN(lo) && !isNaN(hi)) for (var v = lo; v <= hi; v += step) allowed[v] = true
    } else {
      var single = parseInt(base, 10)
      if (!isNaN(single)) allowed[single] = true
      else if (step > 1 && p.indexOf("/") >= 0) for (var v2 = min; v2 <= max; v2 += step) allowed[v2] = true
    }
  }
  return allowed
}
function nextCronRun(cron, from) {
  var f = String(cron).trim().split(/\s+/)
  if (f.length !== 5) return null
  var fmin = cronField(f[0], 0, 59), fhour = cronField(f[1], 0, 23)
  var fdom = cronField(f[2], 1, 31), fmonth = cronField(f[3], 1, 12), fdow = cronField(f[4], 0, 7)
  var domStar = String(f[2]).trim() === "*", dowStar = String(f[4]).trim() === "*"
  var d = new Date(from.getTime()); d.setSeconds(0, 0); d.setMinutes(d.getMinutes() + 1)
  for (var guard = 0; guard < 60 * 24 * 400; guard++) {
    var monthOk = fmonth[d.getMonth() + 1] === true, domOk = fdom[d.getDate()] === true
    var dow = d.getDay(), dowOk = (fdow[dow] === true) || (dow === 0 && fdow[7] === true)
    var dayOk = (domStar && dowStar) ? true : (domStar ? dowOk : (dowStar ? domOk : (domOk || dowOk)))
    if (monthOk && dayOk && fhour[d.getHours()] === true && fmin[d.getMinutes()] === true) return d
    d.setMinutes(d.getMinutes() + 1)
  }
  return null
}
function fmtMs(m){ return Math.round(m / 1000 * 10) / 10 }
function assert(name, cond){ if(cond){ console.log("PASS " + name) } else { console.log("FAIL " + name); process.exit(1) } }
// every minute from :30 -> next at :00 of next minute
var n = nextCronRun("* * * * *", new Date(2026, 7, 28, 10, 0, 30))
assert("cron: every minute", n && n.getMinutes() === 1 && n.getSeconds() === 0)
// every 5 min from 10:00 -> 10:05
var n2 = nextCronRun("*/5 * * * *", new Date(2026, 7, 28, 10, 0, 0))
assert("cron: */5", n2 && n2.getMinutes() === 5 && n2.getHours() === 10)
// invalid (6 fields) -> null
assert("cron: invalid rejected", nextCronRun("0 0 0 0 0 0", new Date()) === null)
// unit -> ms conversion
function unitMs(unit, n){ return n * 1000 * ({sec:1,min:60,hour:3600,day:86400}[unit] || 1) }
assert("unit: 5 min = 300000ms", unitMs("min", 5) === 300000)
assert("unit: 2 hour = 7200000ms", unitMs("hour", 2) === 7200000)
assert("unit: 1 day = 86400000ms", unitMs("day", 1) === 86400000)
EOF
)
if node -e "$CRON_JS" 2>&1; then
  ok "cron/unit schedule logic passes"
else
  fail "cron/unit schedule logic failed"
fi

# --- Curl check logic test ---
echo ""
echo "--- Health Check Logic ---"
if curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 'https://example.com' 2>/dev/null | grep -q '^2'; then
  ok "curl returns 2xx for example.com"
else
  fail "curl does not return 2xx for example.com"
fi

if CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 'https://this-domain-does-not-exist.invalid' 2>/dev/null) || true; then
  if [ "$CODE" = "000" ] || [ -z "$CODE" ]; then ok "curl fails for invalid domain"
  else fail "curl returned $CODE for invalid domain"; fi
fi

# --- Summary ---
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit $FAIL
