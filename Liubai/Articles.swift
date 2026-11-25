import Foundation
import Observation

struct Article: Identifiable, Hashable, Codable {
    let id: String
    let category: String
    let theme: String
    let title: String
    let subtitle: String
    let excerpt: String
    let minutes: Int
    var source: String = "AI 生成"
    let markdown: String

    var displayTitle: String { subtitle.isEmpty ? title : title + subtitle }
}

@MainActor
@Observable final class ArticleFeed {
    private(set) var articles = Article.samples
    private(set) var isRefreshing = false

    func article(_ id: String) -> Article? { articles.first { $0.id == id } }

    func refresh() async {
        guard !isRefreshing,
              let value = Bundle.main.object(forInfoDictionaryKey: "ArticleFeedURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                  http.url?.scheme == "https", data.count <= 8_000_000 else { return }
            let incoming = try JSONDecoder().decode([Article].self, from: data)
            var seen = Set<String>()
            let valid = incoming.filter {
                !$0.id.isEmpty && !$0.title.isEmpty && !$0.markdown.isEmpty && $0.minutes > 0
                    && seen.insert($0.id).inserted
            }
            guard !valid.isEmpty else { return }
            articles = valid + Article.samples.filter { !seen.contains($0.id) }
        } catch {
            // Keep the current reading list available while offline.
        }
    }
}

extension Article {
    static let samples: [Article] = [
        Article(
            id: "return-to-now", category: "心理学", theme: "当下",
            title: "把自己带回", subtitle: "此刻",
            excerpt: "当思绪跑得太远，试着回到眼前这件小事。", minutes: 3,
            markdown: """
            有时候，我们坐在桌前，心却已经走到了明天。它在排练一场还没发生的对话，又绕回昨晚那句没说好的话。等回过神，杯里的水已经凉了。

            > 此刻能给你的，往往只是一件小事。也许这就够了。

            ## 觉察从哪里开始

            在正念练习里，**觉察**可以从注意到一件正在发生的事开始。你可能发现自己在担心，也可能发现手指碰到了杯壁。两者都可以被看见。当注意力又跑开时，轻轻带它回来，本身就是练习的一部分。

            试着把「我怎么又想多了」换成「我注意到自己正在想那件事」。这点语言上的变化，给你留出一点空间，去感受接下来想怎么做。

            ## 留给自己一分钟

            1. 找到一个舒服的姿势，感受身体和椅子或地面接触的位置。
            2. 留意一个声音，或者眼前一处颜色。用自己的话描述它。
            3. 问问自己，现在这一刻，有哪件事值得我先做？

            你可以把这分钟安排在午饭前、打开手机前，或者下一次停在红灯前。熟悉的小场景会提醒你，练习随时可以开始。

            ## 写给自己

            当我的注意力离开此刻时，它最常去哪里？今天，有什么小事让我愿意停下来多看一眼？
            """
        ),
        Article(
            id: "circle-of-choice", category: "哲学", theme: "选择",
            title: "分清你能", subtitle: "决定的事",
            excerpt: "在结果之外，重新看见手里还有哪些选择。", minutes: 4,
            markdown: """
            发出一条重要消息之后，最难熬的也许是等待。我们会一遍遍点亮屏幕，揣测那头正在发生什么。越想知道答案，手里的时间越容易被等待拿走。

            ## 两种范围

            斯多葛哲学里有一个朴素的区分。爱比克泰德在《手册》开篇谈到，有些事取决于我们，比如判断和行动。有些事也受外界左右，比如别人怎样评价我们。

            这个区分尤其适合用在结果悬而未决的时候。你可以认真措辞、如实表达，也可以约定一个合适的跟进时间。直到对方回复之前，这些行动都已经有了自己的价值。

            > 把心力还给那些目前可以采取的行动。

            ## 把烦恼写下来

            - 写下一件最近让你反复惦记的事。
            - 圈出一句由「我可以」开头、今天能够完成的话。
            - 给暂时无法决定的部分留一点空白，晚些再回来看看。

            你也可以把原本要花在刷新消息上的五分钟，用来做一件独立于结果的事。例如伸展一下、走到窗边，或者把今天的晚餐好好吃完。

            ## 写给自己

            有哪件事我已经尽了力？有没有一个很小的下一步，仍然由我决定？
            """
        ),
        Article(
            id: "name-the-feeling", category: "心理学", theme: "情绪",
            title: "给感觉", subtitle: "起个名字",
            excerpt: "一句更具体的话，可能让你更容易听懂自己。", minutes: 3,
            markdown: """
            「今天很糟。」这样的句子来得最快。有时停几秒，我们还会找到别的词：委屈、失落、尴尬，或者只是累。这些词指向不同的需要。

            ## 找一个贴近的词

            给情绪命名是一种辨认感受的方法。可以先问自己身体哪里紧绷，接着回想事情发生时，自己期待什么。几种情绪同时出现也很平常。你可能为朋友开心，同时为自己的处境失落。

            > 我现在感到……也许因为我很在意……

            ## 从辨认走向照顾

            - 如果是疲惫，给自己安排一段真正能休息的时间。
            - 如果是委屈，想想哪项期待值得找机会说清楚。
            - 如果暂时没有合适的词，写下身体里的感受也可以。

            名字只是一个起点。下次想起这件事，你可以换一个更贴近当时经验的说法。

            ## 写给自己

            今天我最容易用哪个词带过自己的感受？如果再具体一点，我会怎么写？
            """
        ),
        Article(
            id: "small-good-life", category: "哲学", theme: "生活",
            title: "好的生活", subtitle: "藏在细节里",
            excerpt: "想过什么样的生活，也可以从今天的一小时看起。", minutes: 4,
            markdown: """
            我们常常用重要时刻描述人生。搬去一个地方，决定做一份工作，和某个人道别。更多的日子，则由重复的小事组成。那些事情同样参与塑造我们。

            ## 习惯也是选择

            在亚里士多德的伦理学里，品格和反复的实践有关。一个人可以在每天的互动中练习诚实、耐心和慷慨。这样的视角让「怎么生活」有了可以亲手触碰的尺寸。

            例如，想要练习倾听，可以从今晚的一次对话开始。试着让对方把想说的话说完，听到一个自己意外的细节，再开口。

            > 你想成为的人，可以出现在一件小事里。

            ## 观察一段时间

            1. 想起昨天过得最像自己的一小时。
            2. 描述那小时里，你在做什么，怎样对待周围的人。
            3. 为今天预留一点空间，让那件事再出现一次。

            ## 写给自己

            如果回看这个星期，我希望在哪个具体瞬间认出自己？
            """
        ),
        Article(
            id: "kind-to-yourself", category: "心理学", theme: "善待",
            title: "对自己", subtitle: "温和一点",
            excerpt: "犯错之后，你也可以用支持朋友的方式和自己说话。", minutes: 3,
            markdown: """
            当朋友讲起一次失败，我们常能理解当时的难处。轮到自己，心里却只剩一句「我早该想到」。两种说法都来自同一个人。

            ## 换一个说话的位置

            自我关怀的练习，可以从承认困难开始。说出「刚才那件事对我挺难的」，然后让自己看看有哪些地方可以补救。一句温和的话，有时能让后续行动变得更具体。

            > 这件事让我难受。我可以先陪自己待一会儿，然后想下一步。

            ## 给自己写三句话

            1. 用能被观察到的事实描述发生了什么。
            2. 承认它带来的感受。
            3. 写下一件照顾自己或修复情况的小事。

            你可以把三句话读给自己听。留意哪些词更接近你真正会对朋友说的话。

            ## 写给自己

            如果一个亲近的人经历了同样的事，我此刻最想对他说什么？
            """
        ),
        Article(
            id: "room-for-uncertainty", category: "哲学", theme: "留白",
            title: "给未知", subtitle: "留一点位置",
            excerpt: "允许一件事暂时没有结论，也是一种认真。", minutes: 4,
            markdown: """
            很多决定刚刚开始时，就让人觉得应该立刻找出答案。可是，有些答案要等我们经历一点、试过一点，才会慢慢清晰。

            ## 把判断留到稍后

            古希腊怀疑主义中的「悬置判断」，可以理解为在理由尚未充分时，对一个判断暂时保持开放。把这个想法用在一天的生活里，可以问问自己：我认识到了多少？还有什么仍然需要了解？

            > 我可以先记下这个问题，等多看见一点，再决定怎样回答。

            ## 为问题留个位置

            - 写出目前已知的一件事实。
            - 写下仍然缺少的一项信息。
            - 约一个复盘时间，留意在此之前可以尝试什么。

            例如，考虑一次生活上的改变时，可以先试行一周，再看看真实感受和想象有多接近。短而可逆的尝试，本身就能给你一些答案。

            ## 写给自己

            最近哪个问题可以先放一放？我愿意花一点时间观察什么？
            """
        )
    ]
}
