import Foundation

struct KnownApp: Identifiable {
    let id: String
    let name: String
    let domains: [String]
}

struct AppCategory: Identifiable {
    let id: String
    let name: String
    let apps: [KnownApp]
}

let appCategories: [AppCategory] = [
    AppCategory(id: "social", name: "Social Media", apps: [
        KnownApp(id: "instagram",  name: "Instagram",       domains: ["instagram.com", "cdninstagram.com"]),
        KnownApp(id: "tiktok",     name: "TikTok",          domains: ["tiktok.com", "tiktokv.com", "musical.ly"]),
        KnownApp(id: "twitter",    name: "Twitter / X",     domains: ["twitter.com", "x.com", "t.co"]),
        KnownApp(id: "facebook",   name: "Facebook",        domains: ["facebook.com", "fb.com", "fbcdn.net", "fbsbx.com"]),
        KnownApp(id: "snapchat",   name: "Snapchat",        domains: ["snapchat.com", "sc-cdn.net", "snap.com"]),
        KnownApp(id: "threads",    name: "Threads",         domains: ["threads.net"]),
        KnownApp(id: "bereal",     name: "BeReal",          domains: ["bere.al", "bereal.com"]),
        KnownApp(id: "reddit",     name: "Reddit",          domains: ["reddit.com", "redd.it", "redditmedia.com", "reddituploads.com", "redditstatic.com"]),
        KnownApp(id: "pinterest",  name: "Pinterest",       domains: ["pinterest.com", "pinimg.com"]),
        KnownApp(id: "linkedin",   name: "LinkedIn",        domains: ["linkedin.com", "licdn.com"]),
        KnownApp(id: "discord",    name: "Discord",         domains: ["discord.com", "discordapp.com", "discordcdn.com"]),
    ]),
    AppCategory(id: "streaming", name: "Streaming", apps: [
        KnownApp(id: "youtube",    name: "YouTube",         domains: ["youtube.com", "youtu.be", "googlevideo.com", "ytimg.com"]),
        KnownApp(id: "netflix",    name: "Netflix",         domains: ["netflix.com", "nflxvideo.net", "nflximg.net"]),
        KnownApp(id: "hulu",       name: "Hulu",            domains: ["hulu.com", "hulustream.com"]),
        KnownApp(id: "appletv",    name: "Apple TV+",       domains: ["tv.apple.com"]),
        KnownApp(id: "primevideo", name: "Prime Video",     domains: ["primevideo.com", "aiv-cdn.net"]),
        KnownApp(id: "twitch",     name: "Twitch",          domains: ["twitch.tv", "twitchapps.com", "jtvnw.net"]),
        KnownApp(id: "spotify",    name: "Spotify",         domains: ["spotify.com", "scdn.co", "spotifycdn.com"]),
    ]),
    AppCategory(id: "news", name: "News", apps: [
        KnownApp(id: "nytimes",    name: "NY Times",        domains: ["nytimes.com", "nyt.com"]),
        KnownApp(id: "washpost",   name: "Washington Post", domains: ["washingtonpost.com"]),
        KnownApp(id: "cnn",        name: "CNN",             domains: ["cnn.com"]),
        KnownApp(id: "foxnews",    name: "Fox News",        domains: ["foxnews.com"]),
        KnownApp(id: "bbc",        name: "BBC News",        domains: ["bbc.com", "bbc.co.uk"]),
        KnownApp(id: "gnews",      name: "Google News",     domains: ["news.google.com"]),
        KnownApp(id: "apnews",     name: "AP News",         domains: ["apnews.com"]),
    ]),
    AppCategory(id: "gambling", name: "Gambling", apps: [
        KnownApp(id: "draftkings", name: "DraftKings",      domains: ["draftkings.com"]),
        KnownApp(id: "fanduel",    name: "FanDuel",         domains: ["fanduel.com"]),
        KnownApp(id: "betmgm",     name: "BetMGM",          domains: ["betmgm.com"]),
        KnownApp(id: "caesars",    name: "Caesars",         domains: ["caesarssportsbook.com", "williamhill.com"]),
        KnownApp(id: "espnbet",    name: "ESPN Bet",        domains: ["espnbet.com"]),
        KnownApp(id: "pointsbet",  name: "PointsBet",       domains: ["pointsbet.com"]),
    ]),
]

let knownApps: [KnownApp] = appCategories.flatMap { $0.apps }
