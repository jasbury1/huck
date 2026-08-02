# Huck — Claude Code Context

## Project Overview

Huck is an iOS Hacker News client built with SwiftUI. It fetches stories and comments via the Algolia HN API and the Firebase HN API, and authenticates users against `news.ycombinator.com` using cookie-based login.

## Development Practice Priorities

### Priority 1: Modern Apple-Native development
The goal is to use modern, native Apple language features and frameworks since we are creating an app from scratch. That means we want to use only preferred modern frameworks for development such as SwiftUI rather than AppKit or UIKit. And we should use Swift, not Objective-C. Whenever an Apple API has been deprecated, we should find docs that suggest newer, better practices.
Idiomatic Swift is a very high priority. We want to conform to the best practices established within the Swift community. Suggest alternatives when we are 
straying from these best practices. Look for ways to incorporate clean, idiomatic design patterns when they fit a given problem.

Even though we are preferring SwiftUI, that does not mean it is a hard rule. If we can benefit from breaking that constraint and another tool (such as AppKit, Web views, etc.) is desirable, it is acceptable to deviate from SwiftUI. However, always confirm with the user before doing so. Areas where this might be desirable may include if an alternative framework makes the App more efficient (web views, for example, can sometimes be very efficient), or if Swift UI has not yet caught up to a feature that is offered by older Apple frameworks. SwiftUI is a relatively new technology, so it may have rough edges or it may be missing certain features. That being said, keep the core architecture of the App in SwiftUI, and find clean ways to integrate any other technology as needed.

### Priority 2: A beautifully designed iOS application 
We want our application to look beautiful and prioritize Apple ecosystem conventions and appearances. We are embracing the platform we are developing for, not fighting against it. We do not want to impose our own branding to the degree that it breaks conventions or makes the appearance deviate from norms that Apple suggests.
Design is not just limited to how a feature looks. It is also how it behaves.

### Priority 3: Efficiency
We want our app to be efficient. Pages should load quickly and feel responsive. Get creative: we should find ways to pre-load resources that are likely to be loaded anyways. 

Another aspect of efficiency is being respectful of resources. We don’t want to mis-use the APIs we are calling, for example. We should try to rate limit ourselves so that APIs are not abused, and we should try to cache results where it provides a benefit. 

### Priority 4: A clean architecture
Our app should look beautiful inside and out. Our code should follow an intuitive and organized structure so that a new developer can easily navigate the codebase.
Focus on best practices for software engineering with robust well-implemented code architecture. Don’t re-invent the wheel in multiple places. Have clean consistent contracts between different parts of the codebase. Make sure the responsibility for a given file/class/directory is clear, and that we separate concerns. Don’t over-engineer either — sometimes more code is not a good thing. 

## App Architecture

### APIs
There are multiple way to access Hacker News via API:
- The Algolia API
- The official HN Firebase API

Both have tradeoffs. The official firebase API is better for realtime data. This benefits pages such as the main stories pages where users might want to see up-to-the-second content. 
The Algolia API is better for historic data, and it also allows for advanced filtering and query capabilities. It also has a big efficiency advantage: we can grab entire comment threads at once, for example, rather than separate API calls for one comment ID at a time. You can also paginate using “created_at_i”. For all options, see https://hn.algolia.com/api
Sometimes we can get creative and mix APIs. For example, use Algolia to efficiently grab large collections of information at once, then supplement any missing latest content with the official API.
Always look for ways to be efficient — both for the end user through UI responsiveness, and for the server hosts by avoiding over-use of API requests

There is a third category: writing a custom API. None of the official APIs provide a way to interact such as upvoting, posting, or commenting. For this, we must reverse engineer the Hacker News REST interface and create our own API handler.