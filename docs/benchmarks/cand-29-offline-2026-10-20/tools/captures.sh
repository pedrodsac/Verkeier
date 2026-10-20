# name|capture dir|scenario|shape
typeset -a CAPTURES
C=~/Developer/Verkeier-captures
CAPTURES=(
  "st-L1|$C/server-timing-2026-10-20/L1|live-now|three"
  "s7-L1|$C/step7-2026-10-20/L1|live-now|three"
  "s7-L2|$C/step7-2026-10-20/L2|live-now|three"
  "s7-L3|$C/step7-2026-10-20/L3|live-now|three"
  "c28-now|$C/cand-28-live-2026-10-19/live-now|live-now|one"
  "c28-rev|$C/cand-28-live-2026-10-19/live-reverse|live-reverse|one"
  "c28-esch|$C/cand-28-live-2026-10-19/live-esch|live-esch|one"
)
