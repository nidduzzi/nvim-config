-- Entry point. Everything else lives in lua/config and lua/plugins.
--
-- The key guard goes first, before any plugin has had a chance to map
-- anything: it wraps the mapping functions, so whatever it is not loaded
-- before is invisible to it.
require("config.keyguard").setup()

require("config.lazy")
