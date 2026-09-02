import Config

# The prod release is the always-up service — long-lived, journald-backed. :debug would
# fill the journal with every Ecto query (and leak through `server:dossier`/`server:console`,
# which read via the live node). :info is the service floor: boot, the MCP listener line,
# warnings, errors — not each SELECT. Dev/test keep :debug for the inner loop; this is
# only the release the systemd unit runs. Bump back to :debug here + rebuild to trace.
config :logger, level: :info
