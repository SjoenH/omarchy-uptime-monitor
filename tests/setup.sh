# Sourced by run.sh: starts the local endpoints the spec probes and exports
# their port.
coproc SPEC_SERVER { exec python3 -I "$here/fixtures/server.py"; }
read -r SPEC_HTTP_PORT <&"${SPEC_SERVER[0]}"
export SPEC_HTTP_PORT

spec_teardown() {
  kill "$SPEC_SERVER_PID" 2>/dev/null
}
