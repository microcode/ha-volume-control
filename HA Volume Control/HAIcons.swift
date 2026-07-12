import Foundation

enum HAIcons {
    static func sfSymbol(forMDI name: String) -> String? {
        let key = name.hasPrefix("mdi:") ? String(name.dropFirst(4)) : name
        switch key {
        case "speaker", "speaker-bluetooth", "speaker-wireless",
             "speaker-multiple", "speaker-off": return "hifispeaker"
        case "television", "television-classic",
             "television-play", "television-box": return "tv"
        case "cast", "cast-connected", "cast-audio": return "airplayvideo"
        case "music", "music-note", "music-note-eighth",
             "music-note-sixteenth", "music-note-plus",
             "spotify", "lastfm", "soundcloud": return "music.note"
        case "radio": return "radio"
        case "headphones", "headphones-bluetooth",
             "headphones-off": return "headphones"
        case "apple": return "apple.logo"
        case "plex", "filmstrip", "movie", "movie-open",
             "emby", "jellyfin": return "film"
        case "kodi", "roku": return "tv"
        case "home-automation", "home-assistant": return "homekit"
        case "home": return "house"
        case "volume-high": return "speaker.wave.3"
        case "volume-medium": return "speaker.wave.2"
        case "volume-low": return "speaker.wave.1"
        case "volume-off", "volume-mute": return "speaker.slash"
        case "google-home", "amazon-alexa": return "homepod"
        case "airplay": return "airplayvideo"
        case "bluetooth": return "bluetooth"
        default: return nil
        }
    }

    static func sfSymbol(forPlatform platform: String) -> String {
        switch platform {
        case "apple_tv": return "appletv"
        case "cast": return "airplayvideo"
        case "samsungtv", "webostv",
             "androidtv", "roku", "kodi": return "tv"
        case "spotify", "mpd",
             "forked_daapd": return "music.note"
        case "vlc", "vlc_telnet": return "music.note"
        case "sonos", "squeezebox": return "hifispeaker"
        case "plex", "jellyfin", "emby": return "film"
        case "homekit": return "homekit"
        default: return "hifispeaker.fill"
        }
    }

    static func sfSymbol(forEntityID entityID: String) -> String {
        let lower = entityID.lowercased()
        if lower.contains("appletv") {
            return "appletv"
        }
        if lower.contains("homepod") {
            return "homepod.fill"
        }
        if lower.contains("tv") ||
            lower.contains("tele")
        {
            return "tv"
        }
        if lower.contains("airpod") {
            return "airpodspro"
        }
        return "hifispeaker.fill"
    }
}
