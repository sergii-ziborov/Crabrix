# Shared ingress startup failure — 6 November 2026

## Observed failure and recovery

The Helsinki application containers remained running and Crabrix's loopback
health endpoint returned HTTP 200, while public TCP 443 refused connections.
The shared nginx service stopped at 06:48:35 UTC and failed startup one second
later because an optional upstream hostname in another site's configuration
could not be resolved. The journal establishes this failure, not who initiated
the restart. Do not attribute the initiating action to Hostwatch without its
operation journal or equivalent evidence.

After DNS recovered, `nginx -t` passed and the service was started successfully
at 06:53:17 UTC. Public home, health and lesson requests returned 200 with valid
TLS. No application image, account database or MCP container changed during
recovery. This November 6 incident cannot explain an October 31 search decline.

## Persistent containment

The optional proxy location now resolves its constant hostname at request time,
using the host's existing local resolver and a five-second resolution timeout.
The hostname does not come from user input. Original request URI handling,
certificate validation, SNI and the upstream Host header are retained. The
operator configuration was backed up before editing; config validation and a
graceful reload succeeded. A read-only upstream request kept the same status.

An isolated `nginx -t` regression case with an intentionally nonexistent hostname
fails for a literal proxy target and succeeds for the constant variable plus
resolver configuration. Production DNS was not disrupted to run this check.
The [Nginx proxy documentation](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass)
describes variable targets and resolver handling.

## Follow-up ownership

The user requested that the incident be sent to the Hostwatch chat; the report
was delivered with the exact journal error, times, backup and file hashes.
Requested follow-ups are prevalidation before stopping shared ingress, reload
where suitable, last-known-good recovery for failed startup, persistence of the
operator patch, and external HTTPS health distinct from container state.

These follow-ups are not recorded as implemented by this incident response.
In particular, a container-online result did not establish public availability.
Do not add shared nginx blindly to one site's stop actions: stopping an
individual application must not stop ingress for all sites.
