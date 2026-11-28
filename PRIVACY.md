# Huck Privacy Policy

_Effective November 27, 2026_

Huck is an independent Hacker News reader for iPhone and iPad. It isn't
affiliated with Y Combinator or Hacker News.

**The short version:** Huck doesn't collect, store, or sell any of your data.
There are no Huck servers, accounts, analytics, advertising, or tracking. What
Huck keeps, it keeps on your device.

## What stays on your device

Huck saves the following on your device so the app works the way you left it:

- Your settings, such as the theme and feed filters.
- Stories you've hidden, upvoted, or favorited, and the comments you've upvoted.
- Your recently viewed stories.
- Your collections.
- The users you've blocked.
- Cached stories, comments, and thumbnails, so pages load quickly.

None of this is sent to the developer. Deleting Huck deletes it.

If iCloud sync is turned on in your build of Huck, your collections are also
stored in your own iCloud account so they appear on your other devices. Apple
handles that data under [Apple's Privacy Policy](https://www.apple.com/legal/privacy/);
the developer can't see it.

## Who Huck talks to

To show you Hacker News, Huck connects directly to these services. Each one
receives your device's IP address and the requests Huck makes, as any website
you visit would:

- **Hacker News** (`news.ycombinator.com`) — signing in, voting, favoriting,
  flagging, posting, and commenting.
- **The Hacker News API** (`hacker-news.firebaseio.com`) — stories and
  comments.
- **Algolia's Hacker News search** (`hn.algolia.com`) — search, user pages, and
  comment threads.

These are run by Y Combinator and Algolia under their own terms and privacy
policies, including [Y Combinator's](https://www.ycombinator.com/legal/).

To show a thumbnail beside a story, Huck fetches the linked page's preview
image from that page's website. If the site has none, Huck asks Google's
favicon service for the site's icon, which tells Google the site's domain.

Links you open are shown in Apple's in-app Safari browser, which follows
Safari's privacy settings.

## Signing in

When you sign in, your username and password are sent only to Hacker News,
over an encrypted connection. Huck never stores your password. Hacker News
returns a sign-in cookie, which Huck keeps on your device to keep you signed
in, and removes when you log out.

## Reporting and blocking

Flagging a story or comment sends the flag to Hacker News under your account.
If you choose to report something by email instead, Huck opens your Mail app
with a message to Hacker News' moderators, and nothing is sent unless you send
it.

Blocking a user only affects what Huck shows you on your device. Hacker News
isn't told.

## Your Hacker News account

Your account, and everything you post with it, belongs to Hacker News, not
Huck. To change or delete your account, see the
[Hacker News FAQ](https://news.ycombinator.com/newsfaq.html) or email
hn@ycombinator.com.

## Changes

If this policy changes, the new version will be posted here with a new
effective date. Its full history is in this repository.

## Contact

Questions about this policy can be asked by
[opening an issue on GitHub](https://github.com/jasbury1/huck/issues).
