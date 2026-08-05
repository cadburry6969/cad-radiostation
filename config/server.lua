return {
    -- Players with this ACE may broadcast on any station
    hostAcePermission = 'group.admin',

    -- Players with this ACE may create, edit and delete stations in-game
    editorAcePermission = 'group.admin',

    -- Framework groups treated as staff for both permissions above
    adminGroups = {
        admin      = true,
        superadmin = true,
        god        = true,
    },

    -- Persist in-game station edits to the server KVP store
    -- When false the list is rebuilt from `stations` below on every restart
    persistStations = true,

    -- Default stations, used to seed the store on first run and on editor reset
    -- streamUrl: direct audio stream or a media link, empty for talk-only stations
    -- frequency: unique integer identifying the station for internal routing
    -- icon: FontAwesome solid icon name
    -- hostJobs: jobs allowed to broadcast on this station
    -- zones: box zones a host must stand in to broadcast
    -- targets: interaction points that open the station interface
    ---@type Station[]
    stations = {
        {
            id          = 'rock_fm',
            label       = 'Rock FM',
            frequency   = 8810,
            streamUrl   = 'https://0nlineradio.stream42.radiohost.de/0r-rock?upd-meta&upd-scheme=https',
            icon        = 'guitar',
            description = 'Classic and modern rock hits',
            hostJobs    = {},
            zones       = {},
            targets     = {},
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
            targets     = {},
        },
        {
            id          = 'jazz_radio',
            label       = 'Jazz Radio',
            frequency   = 8840,
            streamUrl   = 'https://livestreaming-node-1.srg-ssr.ch/srgssr/rsj/mp3/128',
            icon        = 'record-vinyl',
            description = 'Top jazz hits all day',
            hostJobs    = {},
            zones       = {},
            targets     = {},
        },
        {
            id          = 'chillhop_radio',
            label       = 'Chillhop Radio',
            frequency   = 8850,
            streamUrl   = 'https://ilm.stream18.radiohost.de/ilm_ilovechillhop_mp3-192?upd-meta&upd-scheme=https',
            icon        = 'headphones',
            description = 'Top chillhop hits all day',
            hostJobs    = {},
            zones       = {},
            targets     = {},
        },
        {
            id          = 'hiphop_radio',
            label       = 'Hip Hop Radio',
            frequency   = 8860,
            streamUrl   = 'https://ilm.stream18.radiohost.de/ilm_ilovetop100charts_mp3-192?upd-meta&upd-scheme=https',
            icon        = 'microphone',
            description = 'Top hip hop hits all day',
            hostJobs    = {},
            zones       = {},
            targets     = {},
        },
        {
            id          = 'weazel_news',
            label       = 'Weazel News',
            frequency   = 8830,
            streamUrl   = '',
            icon        = 'newspaper',
            description = 'Talk radio around the clock',
            hostJobs    = { 'news', 'reporter', 'police' },
            zones       = {
                {
                    coords  = vec3(-1053.68, -230.54, 44.02),
                    size    = vec3(4.0, 4.0, 3.0),
                    heading = 0.0,
                },
            },
            targets     = {
                {
                    coords = vec3(-1053.09, -231.04, 44.02),
                    radius = 0.5,
                    label  = 'Weazel News Studio',
                    icon   = 'fa-solid fa-tower-broadcast',
                },
            },
        },
    },
}
