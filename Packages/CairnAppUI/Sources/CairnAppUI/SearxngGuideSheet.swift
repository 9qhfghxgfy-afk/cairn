import SwiftUI
import CairnChatDomain

/// How to run a search instance of your own, and what to type into Cairn when it is running.
///
/// Prose only. Nothing in this sheet reaches the network — the whole reason it exists is that a self-hosted
/// instance removes the third party from the request, and a person who has read this page once will not need
/// to be told twice why the address field accepts `http` on a LAN address. The commands are for the user to
/// run on their own machine, in their own terminal.
struct SearxngGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(lead).font(.body).foregroundStyle(CairnTheme.stoneLight)
                    stepOne
                    stepTwo
                    stepThree
                    meanings
                    Text(footnote).font(.caption).foregroundStyle(CairnTheme.stoneLight)
                }
                .padding(20)
            }
            .background(CairnTheme.slateDeep)
            .navigationTitle("SearXNG")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    var lead: String {
        """
        SearXNG is a search engine you run yourself. It talks to other search engines and hands back merged
        results, which means the query reaches those engines from your machine rather than from a service
        Cairn happens to trust. Nothing between Cairn and that box is a company you have to accept terms
        from.
        """
    }

    var stepOne: some View {
        GuideBlock(
            title: "One — run it",
            body: "Docker is the shortest way. JSON output has to be enabled explicitly; without it Cairn "
                + "would have to read HTML, which changes whenever the instance's theme changes.",
            command: """
            docker run -d -p 8888:8051 \\
              -e SEARXNG_BASE_URL=http://your-box.local:8888 \\
              searxng/searxng
            """
        )
    }

    var stepTwo: some View {
        GuideBlock(
            title: "Two — switch on the JSON API",
            body: "Edit the instance's settings.yml so it will answer in JSON instead of only as a web page.",
            command: """
            # /etc/searxng/settings.yml
            search:
              formats:
                - html
                - json
            # then restart the container
            """
        )
    }

    var stepThree: some View {
        GuideBlock(
            title: "Three — add the row in Cairn",
            body: "Type the instance's address, not the path — Cairn appends /search itself. A LAN address "
                + "or a .local name may use http; a host on the public internet must be https. The first "
                + "search to a new local address triggers the iOS Local Network prompt, and a search cannot "
                + "reach the instance until that prompt is allowed."
        )
    }

    /// What each test answer means, in the same words the tool uses mid-conversation. A user who has seen
    /// `blocked` here will know what it meant when the chat said it.
    var meanings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What the answers mean").font(.headline)
            meaning("ok", "It answered. Latency is the measured round trip, so a tunnel's hop shows up in it.")
            meaning("no results", "It answered and found nothing for the test query. The provider works.")
            meaning("blocked", "Refused or timed out — usually the JSON format is not enabled, or a proxy "
                + "in front of the instance is rejecting the request.")
            meaning("https required", "A public host over http. Point the row at the https address.")
            meaning("not configured", "The row's address is not something Cairn will dial.")
        }
    }

    func meaning(_ term: String, _ explanation: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(term)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(CairnTheme.amber)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(CairnTheme.stoneLight)
        }
    }

    var footnote: String {
        """
        Cairn sends the query text, the number of results and the language to whichever provider is active,
        plus whatever headers the row itself defines. It does not send anything from a conversation to set
        this up, and reading this page causes no traffic at all.
        """
    }
}
