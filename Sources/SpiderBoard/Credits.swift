/// Who made what (Settings ▸ Credits, the website, About). Links point at the source file pages
/// listed in Sources/SpiderSolitaire/Resources/Cards/CREDITS.md and at the licence texts.
public struct Credit: Hashable, Sendable {
    public struct Link: Hashable, Sendable {
        public let title: String
        public let url: String
    }

    public let title: String
    public let detail: String
    public let links: [Link]
}

public enum Credits {
    public static let website: String = "https://dansailer.github.io/SpiderSolitaire/"
    public static let repository: String = "https://github.com/dansailer/SpiderSolitaire"

    public static let all: [Credit] = [
        Credit(
            title: "Classic card faces",
            detail:
                "The \"English pattern\" playing cards by Dmitry Fomin, dedicated to the public domain under CC0 1.0.",
            links: [
                Credit.Link(
                    title: "Cards on Wikimedia Commons",
                    url: "https://commons.wikimedia.org/wiki/Category:SVG_English_pattern_playing_cards"),
                Credit.Link(
                    title: "King of spades file page",
                    url: "https://commons.wikimedia.org/wiki/File:English_pattern_king_of_spades.svg"),
                Credit.Link(title: "CC0 1.0", url: "https://creativecommons.org/publicdomain/zero/1.0/"),
            ]),
        Credit(
            title: "Ornate ace of spades",
            detail:
                "The centre of the ace of spades comes from Byron Knoll's vector playing cards, released into the public domain by its author.",
            links: [
                Credit.Link(
                    title: "Ace of spades file page", url: "https://commons.wikimedia.org/wiki/File:Ace_of_spades.svg"),
                Credit.Link(title: "Public domain", url: "https://en.wikipedia.org/wiki/Public_domain"),
            ]),
        Credit(
            title: "Sounds",
            detail: "The short sounds are the ones built into macOS.",
            links: []),
        Credit(
            title: "Spider Solitaire",
            detail: "Free and open source under the MIT licence. A tribute to the Windows XP classic.",
            links: [
                Credit.Link(title: "Website", url: website),
                Credit.Link(title: "Source code on GitHub", url: repository),
                Credit.Link(title: "MIT licence", url: repository + "/blob/main/LICENSE"),
            ]),
    ]
}
