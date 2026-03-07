#!/bin/bash

# =============================================================
#  STRESS TEST ALL APIs - Ramadan Tracker
#  Tests: POST, GET All, GET by ID, PUT, DELETE
# =============================================================

BASE_URL="http://localhost:8080"
API_URL="${BASE_URL}/api/targets"

# Number of requests PER endpoint
REQUESTS=20

# Max concurrent requests
CONCURRENCY=50

# Sample data for random bodies
IBADAH_LIST=("Sholat Tarawih" "Baca Al-Quran" "Sholat Tahajud" "Sedekah" "Puasa Sunnah" "Dzikir Pagi" "Dzikir Petang" "Tadarus" "Sholat Dhuha" "Berdoa")
STATUS_LIST=("Proses" "Selesai" "Pending")

# Log files
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="stress_test_${TIMESTAMP}.log"
DETAIL_LOG_FILE="stress_test_${TIMESTAMP}_detail.log"
SUMMARY_FILE="stress_test_${TIMESTAMP}_summary.log"

# Temp dir for subprocess communication
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Create subdirs for per-endpoint stats
mkdir -p "$TEMP_DIR"/{post,get_all,get_id,put,delete}

# Init log files
echo "request_no,method,endpoint,http_status,response_time_sec,timestamp" > "$LOG_FILE"
echo "" > "$DETAIL_LOG_FILE"

# ─────────────────────────────────────────────
#  Pre-flight check (is server running?)
# ─────────────────────────────────────────────
echo "Checking if server is reachable at $BASE_URL..."
if ! curl -s --max-time 3 "$BASE_URL" > /dev/null; then
  echo "❌ ERROR: Server at $BASE_URL is not fully reachable or connection refused!"
  echo "Please start the server first (e.g., go run main.go) before running this stress test."
  exit 1
fi
echo "✅ Server is reachable!"

# ─────────────────────────────────────────────
#  Helper: log a single request/response
# ─────────────────────────────────────────────
log_request() {
  local REQ_NUM=$1
  local METHOD=$2
  local ENDPOINT=$3
  local REQUEST_BODY=$4
  local HTTP_CODE=$5
  local RESPONSE_TIME=$6
  local RESPONSE_BODY=$7
  local REQ_TIMESTAMP=$8
  local ENDPOINT_DIR=$9

  # CSV log
  echo "${REQ_NUM},${METHOD},${ENDPOINT},${HTTP_CODE},${RESPONSE_TIME},${REQ_TIMESTAMP}" >> "$LOG_FILE"

  # Detail log
  {
    echo "──────────────────────────────────────────────"
    echo "📨 ${METHOD} #${REQ_NUM} | ${REQ_TIMESTAMP}"
    echo "──────────────────────────────────────────────"
    echo "  ➡️  ${METHOD} ${ENDPOINT}"
    if [ -n "$REQUEST_BODY" ]; then
      echo "  📤 Request Body:"
      echo "$REQUEST_BODY" | sed 's/^/     /'
    fi
    echo "  ⬅️  HTTP ${HTTP_CODE} | ⏱ ${RESPONSE_TIME}s"
    echo "  📦 Response Body:"
    echo "$RESPONSE_BODY" | sed 's/^/     /'
    echo ""
  } >> "$DETAIL_LOG_FILE"

  # Terminal
  echo "[${REQ_TIMESTAMP}] ${METHOD} #${REQ_NUM} | HTTP ${HTTP_CODE} | ${RESPONSE_TIME}s"
  if [ -n "$REQUEST_BODY" ]; then
    echo "  📤 REQ : ${REQUEST_BODY}"
  fi
  echo "  📦 RES : ${RESPONSE_BODY}"

  # Stats
  echo "$HTTP_CODE" >> "$TEMP_DIR/$ENDPOINT_DIR/status_codes.txt"
  echo "$RESPONSE_TIME" >> "$TEMP_DIR/$ENDPOINT_DIR/response_times.txt"
}

# ─────────────────────────────────────────────
#  Helper: print stats for an endpoint
# ─────────────────────────────────────────────
print_endpoint_stats() {
  local LABEL=$1
  local DIR=$2
  local EXPECTED_CODE=$3

  local TOTAL=$(wc -l < "$TEMP_DIR/$DIR/status_codes.txt" 2>/dev/null | tr -d ' ')
  [ -z "$TOTAL" ] && TOTAL=0
  
  local SUCCESS=$(grep -c "^${EXPECTED_CODE}$" "$TEMP_DIR/$DIR/status_codes.txt" 2>/dev/null)
  [ -z "$SUCCESS" ] && SUCCESS=0
  
  local FAILED=$((TOTAL - SUCCESS))

  if [ "$TOTAL" -gt 0 ]; then
    local RATE=$(echo "scale=1; ($SUCCESS * 100) / $TOTAL" | bc)
    local AVG=$(awk '{ s+=$1; c++ } END { if(c>0) printf "%.4f",s/c }' "$TEMP_DIR/$DIR/response_times.txt")
    local MIN=$(sort -n "$TEMP_DIR/$DIR/response_times.txt" | head -1)
    local MAX=$(sort -n "$TEMP_DIR/$DIR/response_times.txt" | tail -1)
  else
    local RATE="0"; local AVG="N/A"; local MIN="N/A"; local MAX="N/A"
  fi

  printf "  %-22s | %4s reqs | ✅ %4s | ❌ %3s | %5s%% | ⏱ %ss avg | 🚀 %ss | 🐢 %ss\n" \
    "$LABEL" "$TOTAL" "$SUCCESS" "$FAILED" "$RATE" "$AVG" "$MIN" "$MAX"

  # Return values for grand total
  echo "$TOTAL $SUCCESS $FAILED" >> "$TEMP_DIR/grand_total.txt"
}

# ─────────────────────────────────────────────
#  Wait for background jobs with throttle
# ─────────────────────────────────────────────
ACTIVE=0
throttle() {
  ACTIVE=$((ACTIVE + 1))
  if [ $ACTIVE -ge $CONCURRENCY ]; then
    wait -n 2>/dev/null || wait
    ACTIVE=$((ACTIVE - 1))
  fi
}
wait_all() {
  wait
  ACTIVE=0
}

# =============================================================
#  START
# =============================================================
echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  🧪 STRESS TEST ALL APIs - Ramadan Tracker"
echo "══════════════════════════════════════════════════════════════"
echo "  Base URL    : $BASE_URL"
echo "  Requests    : $REQUESTS per endpoint (x5 = $((REQUESTS * 5)) total)"
echo "  Concurrency : $CONCURRENCY"
echo "  Log File    : $LOG_FILE"
echo "  Detail Log  : $DETAIL_LOG_FILE"
echo "  Started at  : $(date '+%Y-%m-%d %H:%M:%S')"
echo "══════════════════════════════════════════════════════════════"
echo ""

# =============================================================
#  1️⃣  POST /api/targets - Create
# =============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1️⃣  POST /api/targets (Create $REQUESTS targets)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for i in $(seq 1 $REQUESTS); do
  (
    RANDOM_IBADAH=${IBADAH_LIST[$((RANDOM % ${#IBADAH_LIST[@]}))]}
    RANDOM_STATUS=${STATUS_LIST[$((RANDOM % ${#STATUS_LIST[@]}))]}
    REQ_BODY=$(printf '{"id":"stress-%s","ibadah":"%s","status":"%s"}' "$i" "$RANDOM_IBADAH" "$RANDOM_STATUS")

    BODY_FILE=$(mktemp "$TEMP_DIR/body_XXXXXX")
    CURL_OUT=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -d "$REQ_BODY" \
      -o "$BODY_FILE" \
      -w "%{http_code},%{time_total}" \
      "$API_URL" 2>/dev/null)
    HTTP_CODE=$(echo "$CURL_OUT" | cut -d',' -f1)
    RESP_TIME=$(echo "$CURL_OUT" | cut -d',' -f2)
    RESP_BODY=$(cat "$BODY_FILE" 2>/dev/null)
    rm -f "$BODY_FILE"

    log_request "$i" "POST" "$API_URL" "$REQ_BODY" "$HTTP_CODE" "$RESP_TIME" "$RESP_BODY" "$(date '+%Y-%m-%d %H:%M:%S')" "post"
  ) &
  throttle
done
wait_all
echo ""

# =============================================================
#  2️⃣  GET /api/targets - Get All
# =============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  2️⃣  GET /api/targets (Get All - $REQUESTS requests)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for i in $(seq 1 $REQUESTS); do
  (
    BODY_FILE=$(mktemp "$TEMP_DIR/body_XXXXXX")
    CURL_OUT=$(curl -s -o "$BODY_FILE" -w "%{http_code},%{time_total}" "$API_URL" 2>/dev/null)
    HTTP_CODE=$(echo "$CURL_OUT" | cut -d',' -f1)
    RESP_TIME=$(echo "$CURL_OUT" | cut -d',' -f2)
    RESP_BODY=$(cat "$BODY_FILE" 2>/dev/null)
    rm -f "$BODY_FILE"

    # Truncate response body for terminal (GET all can be very long)
    RESP_SHORT=$(echo "$RESP_BODY" | head -c 200)
    if [ ${#RESP_BODY} -gt 200 ]; then
      RESP_SHORT="${RESP_SHORT}... (truncated)"
    fi

    log_request "$i" "GET" "$API_URL" "" "$HTTP_CODE" "$RESP_TIME" "$RESP_SHORT" "$(date '+%Y-%m-%d %H:%M:%S')" "get_all"
  ) &
  throttle
done
wait_all
echo ""

# =============================================================
#  3️⃣  GET /api/targets/:id - Get By ID
# =============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  3️⃣  GET /api/targets/:id (Get By ID - $REQUESTS requests)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for i in $(seq 1 $REQUESTS); do
  (
    TARGET_ID="stress-$i"
    ENDPOINT="${API_URL}/${TARGET_ID}"

    BODY_FILE=$(mktemp "$TEMP_DIR/body_XXXXXX")
    CURL_OUT=$(curl -s -o "$BODY_FILE" -w "%{http_code},%{time_total}" "$ENDPOINT" 2>/dev/null)
    HTTP_CODE=$(echo "$CURL_OUT" | cut -d',' -f1)
    RESP_TIME=$(echo "$CURL_OUT" | cut -d',' -f2)
    RESP_BODY=$(cat "$BODY_FILE" 2>/dev/null)
    rm -f "$BODY_FILE"

    log_request "$i" "GET/:id" "$ENDPOINT" "" "$HTTP_CODE" "$RESP_TIME" "$RESP_BODY" "$(date '+%Y-%m-%d %H:%M:%S')" "get_id"
  ) &
  throttle
done
wait_all
echo ""

# =============================================================
#  4️⃣  PUT /api/targets/:id - Update
# =============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  4️⃣  PUT /api/targets/:id (Update - $REQUESTS requests)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for i in $(seq 1 $REQUESTS); do
  (
    TARGET_ID="stress-$i"
    ENDPOINT="${API_URL}/${TARGET_ID}"
    RANDOM_IBADAH=${IBADAH_LIST[$((RANDOM % ${#IBADAH_LIST[@]}))]}
    REQ_BODY=$(printf '{"id":"stress-%s","ibadah":"%s (Updated)","status":"Selesai"}' "$i" "$RANDOM_IBADAH")

    BODY_FILE=$(mktemp "$TEMP_DIR/body_XXXXXX")
    CURL_OUT=$(curl -s -X PUT \
      -H "Content-Type: application/json" \
      -d "$REQ_BODY" \
      -o "$BODY_FILE" \
      -w "%{http_code},%{time_total}" \
      "$ENDPOINT" 2>/dev/null)
    HTTP_CODE=$(echo "$CURL_OUT" | cut -d',' -f1)
    RESP_TIME=$(echo "$CURL_OUT" | cut -d',' -f2)
    RESP_BODY=$(cat "$BODY_FILE" 2>/dev/null)
    rm -f "$BODY_FILE"

    log_request "$i" "PUT" "$ENDPOINT" "$REQ_BODY" "$HTTP_CODE" "$RESP_TIME" "$RESP_BODY" "$(date '+%Y-%m-%d %H:%M:%S')" "put"
  ) &
  throttle
done
wait_all
echo ""

# =============================================================
#  5️⃣  DELETE /api/targets/:id - Delete
# =============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  5️⃣  DELETE /api/targets/:id (Delete - $REQUESTS requests)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for i in $(seq 1 $REQUESTS); do
  (
    TARGET_ID="stress-$i"
    ENDPOINT="${API_URL}/${TARGET_ID}"

    BODY_FILE=$(mktemp "$TEMP_DIR/body_XXXXXX")
    CURL_OUT=$(curl -s -X DELETE \
      -o "$BODY_FILE" \
      -w "%{http_code},%{time_total}" \
      "$ENDPOINT" 2>/dev/null)
    HTTP_CODE=$(echo "$CURL_OUT" | cut -d',' -f1)
    RESP_TIME=$(echo "$CURL_OUT" | cut -d',' -f2)
    RESP_BODY=$(cat "$BODY_FILE" 2>/dev/null)
    rm -f "$BODY_FILE"

    log_request "$i" "DELETE" "$ENDPOINT" "" "$HTTP_CODE" "$RESP_TIME" "$RESP_BODY" "$(date '+%Y-%m-%d %H:%M:%S')" "delete"
  ) &
  throttle
done
wait_all
echo ""

# =============================================================
#  📊 SUMMARY
# =============================================================
echo ""
echo "══════════════════════════════════════════════════════════════════════════════════════════════════════════════"
echo "  📊 STRESS TEST SUMMARY - ALL APIs"
echo "══════════════════════════════════════════════════════════════════════════════════════════════════════════════"
echo ""
printf "  %-22s | %9s | %6s | %5s | %6s | %12s | %12s | %12s\n" \
  "Endpoint" "Requests" "Pass" "Fail" "Rate" "Avg Time" "Min Time" "Max Time"
echo "  ────────────────────────┼───────────┼────────┼───────┼────────┼──────────────┼──────────────┼──────────────"

print_endpoint_stats "POST /api/targets"      "post"    "201"
print_endpoint_stats "GET /api/targets"        "get_all" "200"
print_endpoint_stats "GET /api/targets/:id"    "get_id"  "200"
print_endpoint_stats "PUT /api/targets/:id"    "put"     "200"
print_endpoint_stats "DELETE /api/targets/:id" "delete"  "200"

echo ""

# Grand total
GRAND_TOTAL=0; GRAND_SUCCESS=0; GRAND_FAILED=0
while read total success failed; do
  GRAND_TOTAL=$((GRAND_TOTAL + total))
  GRAND_SUCCESS=$((GRAND_SUCCESS + success))
  GRAND_FAILED=$((GRAND_FAILED + failed))
done < "$TEMP_DIR/grand_total.txt"

[ -z "$GRAND_TOTAL" ] && GRAND_TOTAL=0
[ -z "$GRAND_SUCCESS" ] && GRAND_SUCCESS=0
[ -z "$GRAND_FAILED" ] && GRAND_FAILED=0

if [ "$GRAND_TOTAL" -gt 0 ]; then
  GRAND_RATE=$(echo "scale=1; ($GRAND_SUCCESS * 100) / $GRAND_TOTAL" | bc)
else
  GRAND_RATE="0"
fi

# All response times combined
cat "$TEMP_DIR"/*/response_times.txt > "$TEMP_DIR/all_times.txt" 2>/dev/null
ALL_AVG=$(awk '{ s+=$1; c++ } END { if(c>0) printf "%.4f",s/c }' "$TEMP_DIR/all_times.txt" 2>/dev/null)
ALL_MIN=$(sort -n "$TEMP_DIR/all_times.txt" 2>/dev/null | head -1)
ALL_MAX=$(sort -n "$TEMP_DIR/all_times.txt" 2>/dev/null | tail -1)

echo "  ────────────────────────────────────────────────────────"
echo "  🏆 GRAND TOTAL"
echo "  ────────────────────────────────────────────────────────"
echo "  Total Requests   : $GRAND_TOTAL"
echo "  ✅ Success        : $GRAND_SUCCESS"
echo "  ❌ Failed          : $GRAND_FAILED"
echo "  📊 Success Rate    : ${GRAND_RATE}%"
echo ""
echo "  ⏱  Avg Response   : ${ALL_AVG}s"
echo "  🚀 Min Response   : ${ALL_MIN}s"
echo "  🐢 Max Response   : ${ALL_MAX}s"
echo ""
echo "  Finished at: $(date '+%Y-%m-%d %H:%M:%S')"
echo "══════════════════════════════════════════════════════════════════════════════════════════════════════════════"

# HTTP status code breakdown (all endpoints)
echo ""
echo "  HTTP Status Code Breakdown (All Endpoints):"
cat "$TEMP_DIR"/*/status_codes.txt 2>/dev/null | sort | uniq -c | sort -rn | while read count code; do
  echo "    HTTP $code : $count requests"
done

echo ""
echo "  📄 CSV log saved to  : $LOG_FILE"
echo "  📄 Detail log saved  : $DETAIL_LOG_FILE"
echo "══════════════════════════════════════════════════════════════════════════════════════════════════════════════"

# Save summary
{
  echo "Stress Test All APIs - $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Base URL: $BASE_URL"
  echo "Requests per endpoint: $REQUESTS"
  echo ""
  echo "Grand Total: $GRAND_TOTAL"
  echo "Success: $GRAND_SUCCESS"
  echo "Failed: $GRAND_FAILED"
  echo "Success Rate: ${GRAND_RATE}%"
  echo "Avg Response: ${ALL_AVG}s"
  echo "Min Response: ${ALL_MIN}s"
  echo "Max Response: ${ALL_MAX}s"
} > "$SUMMARY_FILE"

echo "  📄 Summary saved to  : $SUMMARY_FILE"
echo ""
