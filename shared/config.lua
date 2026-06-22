Config = {}

Config.Debug = true

-- Key to open radio menu (only works in vehicle)
Config.OpenKey = 'F5'
Config.OpenKeyLabel = 'Open Vehicle Radio'

-- Volume range step size for scroll list
Config.VolumeStep = 10 -- 0, 10, 20, ... 100

-- Default volume for new listeners (0–100)
Config.DefaultVolume = 50

-- Radio stations
-- streamUrl: direct URL to audio stream (.mp3, .ogg, Icecast/Shoutcast endpoint)
--            IMPORTANT: must be a direct stream URL, not a webpage
-- frequency: unique integer identifying the station for internal routing
-- icon: FontAwesome icon name for ox_lib menu
Config.Stations = {
    {
        id          = 'rock_fm',
        label       = 'Rock FM',
        frequency   = 8810,
        streamUrl   = 'https://stream.0nlineradio.com/rock',
        icon        = 'guitar',
        description = 'Classic and modern rock hits',
        hostJobs    = {},
        zones       = {}, -- Allow vehicle-only or add specific zones
        targets     = {}
    },
    {
        id          = 'pop_radio',
        label       = 'Pop Radio',
        frequency   = 8820,
        streamUrl   = 'https://stream.radioparadise.com/mp3-192',
        icon        = 'music',
        description = 'Top pop hits all day',
        hostJobs    = {},
        zones       = {},
        targets     = {}
    },
    {
        id          = 'jazz_radio',
        label       = 'Jazz Radio',
        frequency   = 8820,
        streamUrl   = 'https://livestreaming-node-1.srg-ssr.ch/srgssr/rsj/mp3/128',
        icon        = 'record-vinyl',
        description = 'Top jazz hits all day',
        hostJobs    = {},
        zones       = {},
        targets     = {}
    },
    {
        id          = 'chillhop_radio',
        label       = 'Chillhop Radio',
        frequency   = 8820,
        streamUrl   = 'https://ilm.stream18.radiohost.de/ilm_ilovechillhop_mp3-192?upd-meta&upd-scheme=https&_art=dD0xNzcyMzg0NDAwJmQ9NDQ1OTAxMWZkMzYxYzIyODdlMzI',
        icon        = 'headphones',
        description = 'Top chillhop hits all day',
        hostJobs    = {},
        zones       = {},
        targets     = {}
    },
    {
        id          = 'hiphop_radio',
        label       = 'Hip Hop Radio',
        frequency   = 8820,
        streamUrl   = 'https://ilm.stream18.radiohost.de/ilm_ilovetop100charts_mp3-192?upd-meta&upd-scheme=https&_art=dD0xNzcyMzg0NDQ1JmQ9OTE0YmZjOGFiNDY0YjdiMzQ4NzQ',
        icon        = 'microphone',
        description = 'Top hip hop hits all day',
        hostJobs    = {},
        zones       = {},
        targets     = {}
    },
    {
        id          = 'weazel_news',
        label       = 'Weazel News',
        frequency   = 8830,
        streamUrl   = 'https://stream.0nlineradio.com/talk',
        icon        = 'newspaper',
        description = 'Talk radio around the clock',
        hostJobs = { 'news', 'reporter', 'police' },
        zones = {
            {
                name = 'weazel_news_studio',
                coords = vec3(-1053.68, -230.54, 44.02),
                size = vec3(4.0, 4.0, 3.0),
                heading = 0.0,
                debug = true
            }
        },
        targets = {
            {
                coords = vec3(-1053.09, -231.04, 44.02),
                radius = 0.5,
                label = 'Start Broadcasting',
                icon = 'fa-solid fa-tower-broadcast'
            }
        }
    },
}

-- ACE permission fallback for broadcasting (if player has this, they can broadcast on ANY station)
Config.HostAcePermission = 'group.admin'

-- Auto-stop radio when player exits vehicle
Config.StopOnExitVehicle = true

-- Push-to-Talk Key for Voice Broadcasting
-- This key must be held to transmit voice
Config.PTTKey = 'LMENU' -- Alt key
Config.PTTKeyLabel = 'ALT'
