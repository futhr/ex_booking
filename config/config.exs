import Config

# ExBooking is a pure library and requires no configuration of its own.
# Timezone data is provided by the :tz application.
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

import_config "#{config_env()}.exs"
