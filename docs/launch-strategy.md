# Scale Runner — Launch Strategy

**Written 2026-08-12. Budget: $0. Channels: personal network, direct outreach, short-form video. Goal: downloads + real daily users.**

---

## 0. The timeline reality check (read this first)

You said "launch within the week." Neither app is submitted yet, so **that is not
achievable as stated** — but a good outcome still is, if you split "submit" from
"launch."

What the stores actually take for a *first* submission:

| | Typical | Worst case |
|---|---|---|
| Apple App Review (new app) | 2–5 days | 1–2 weeks if rejected once |
| Google Play (new app, review) | up to 7 days | longer with sensitive permissions |

A rejection **restarts the clock on both platforms**, and first submissions are
the most expensive scenario there is — new app, new account, new IAP all route
you into manual review lanes.

One Play-specific thing worth confirming in the console this week: the
12-testers-for-14-continuous-days closed testing gate applies to **personal**
developer accounts created after Nov 2023. Yours is an organization account
(C1GNUS STUD1O / CYGNUS INNOVATIONS LLC), which is exempt — but verify Play
Console isn't showing you that requirement before you assume it. If it is, your
launch is 3 weeks out, not 1, and everything below shifts right.

### So here's the reframe

**This week = submit + build the audience. Next week = launch.**

That's not a delay, it's the correct sequence. Launching an app with zero
audience on day one is how you get 40 downloads and a dead chart position. The
review window is free runway to build a list of people who install on day one —
and a burst of day-one installs is the single biggest free ranking signal either
store gives you.

### Blockers that must close before submission

- **iOS IAP** — the RevenueCat/Apple bundle-ID credential incident. If it's
  still open, you can submit the app but the $14.99 unlock won't validate.
  Check the incident URL directly, not the status summary page.
- **Rewards/progression system** — unbuilt, and it was tester complaint #3.
  *Do not build it before launch.* Ship without it; it's your first post-launch
  update, which gives you a reason to re-engage users in week 3.
- **On-device verification** — Google sign-in on Android and invite links
  opening the app have never been confirmed on real hardware. A broken sign-in
  on day one costs you more than a week of delay does.
- **Launch flags** — flip `kPubliclyLaunched` in `lib/widgets/streak_sheets.dart`
  and swap the two beta URLs in `web_hosting/hostinger/invite/index.html` to
  store URLs, then re-upload that one file.

---

## 1. Positioning

The single most expensive mistake available to you is competing with Simply
Piano, Flowkey, and Skoove. Those are venture-funded "learn piano from zero"
apps with millions in paid acquisition. You will lose that fight on any budget,
and lose it worst at $0.

**Scale Runner is not a learn-piano app. It's a practice tool for people who
already play.**

> **Scale Runner turns scale practice into a game you can score.**
> Plug in your MIDI keyboard, pick your scales, and get graded on timing —
> the boring part of practice, made measurable.

Why this positioning wins for you:

- **The competition is nobody.** The gamified-practice giants ignore scales
  because scales aren't where beginners are. The serious-practice tools
  (metronomes, Tenuto) aren't gamified. You sit in the gap.
- **MIDI requirement is a filter, not a flaw.** It means everyone who installs
  owns a keyboard and practices regularly. That's a small audience with
  extremely high intent — exactly what you want at $0 budget and a $14.99
  one-time price.
- **"Boring practice, made fun" is a story people repeat.** "Another piano
  app" is not.

### Who to actually target, in priority order

1. **Intermediate adult pianists** who already practice and hate scales. Largest
   reachable group, most likely to pay once.
2. **Grade-exam students** (ABRSM, RCM, Trinity). Scales are a *scored exam
   requirement* — this is the highest-intent search behavior in the whole niche.
   Teachers and parents look for exactly this.
3. **Piano teachers.** One teacher = 10–30 students. Highest leverage per email
   you send, and the audience your direct-outreach channel is built for.
4. **Jazz/theory students** drilling modes and voicings.

### Words to use and avoid

| Use | Avoid |
|---|---|
| practice, drill, reps, score, timing, accuracy | learn, lessons, course, beginner |
| your keyboard, MIDI, real keys | play-along, songs, tutorial |
| grade exams, scales, modes, voicings | master piano in 30 days |

---

## 2. App Store Optimization — do this before anything else

ASO is the only free channel that keeps paying you after launch week. Every
other tactic here is a one-time spike. Spend real time on this.

### iOS

**Title (30 char):** `Scale Runner: Piano Practice`

**Subtitle (30 char):** `MIDI scales, chords & timing`

**Keyword field (100 char, comma-separated, no spaces, never repeat a word
already in title/subtitle):**

```
scales,midi,keyboard,drill,metronome,theory,chords,arpeggio,musician,abrsm,grade,exam,jazz,modes
```

Rules that matter: Apple auto-combines your words into phrases, so never waste
characters on multi-word phrases or the word "app." Don't repeat words already
in your title or subtitle — they're already indexed.

### Android

Play indexes your **full description**, so write it for humans but make the
phrases "piano scales practice," "MIDI keyboard," and "practice scales with a
metronome" appear naturally 2–3 times. Keyword-stuffing gets suppressed.

**Short description (80 char):** `Drill piano scales & chords on your MIDI
keyboard. Scored on timing.`

### Screenshots — the highest-leverage asset you have

Most people decide from screenshots 1 and 2 without reading a word. Caption
every screenshot; a screenshot with no text overlay is a wasted slot.

1. **The score screen.** Lead with the payoff, not the setup. Caption:
   *"Every run, scored."*
2. **Keyboard + live note feedback.** Caption: *"Plug in your MIDI keyboard."*
3. **Scale/chord selection.** Caption: *"Every scale, every key."*
4. **Streaks.** Caption: *"Practice daily. Keep the streak."*
5. **Friends/leaderboard.** Caption: *"Race your practice buddies."*

Shoot these at the exact required pixel sizes, dark theme (your #171E28 brand
looks premium and is rare in this category — most piano apps are white and
childish). This is a real differentiator; lean into it.

### App preview video (iOS) / promo video (Android)

30 seconds, no voiceover needed: hands on a real keyboard, notes lighting up,
score climbing, streak flame. This is the same footage as your first TikTok —
shoot once, use twice.

---

## 3. The 14-day plan

### Days 1–2 (Wed 8/13 – Thu 8/14) — Ship the submission

- Close the iOS IAP blocker or accept shipping with the paywall inactive on iOS.
- On-device pass: Google sign-in, invite link opens app, purchase flow, a full
  practice run start to finish.
- Flip `kPubliclyLaunched`, swap invite-page URLs.
- Build ASO assets (screenshots, video, copy above).
- **Submit both stores.** Do not sit on this — every hour of delay is an hour
  of review clock not running.

### Days 2–7 — Build the day-one list while review runs

This is the whole game. Your objective is **a list of 100+ people who will
install on launch day**, because concentrated installs is what moves store
ranking, and ranking is the only free distribution either store gives you.

- **Landing page.** You already own `scalerunner.c1gnus.com` and it's live on
  Hostinger. Replace the bare redirect at `/` with a real page: hero line, the
  score screenshot, and one email field — "Get notified when Scale Runner
  launches." That's it. You're already paying for the hosting.
- **Existing beta testers.** Email every one. They already use it. Ask each for
  two things on launch day: install from the store, and leave a review. Give
  them free Pro codes as thanks — App Store Connect and Play both issue promo
  codes at no cost.
- **Personal network.** Every musician you know, every local teacher, your own
  teacher if you have one. Personal ask, not a mass blast.
- **Start posting video now, not at launch.** Post daily starting day 2. The
  point of pre-launch posting is that the algorithm needs 5–10 posts to figure
  out who to show you to. If your first post is on launch day, it reaches
  nobody. Every video ends with "launching next week — link in bio."
- **Teacher outreach.** 10 emails a day, every day. Template in §5.

### Day 8 (approx. Wed 8/20) — Launch day

- Email the list. One email, one link, morning Pacific.
- Post the launch video across all three platforms.
- Text your personal network individually. Twenty personal texts outperform one
  group post by an order of magnitude.
- Send promo codes to every teacher who replied.
- **Ask explicitly for reviews.** Store ratings are the compounding asset. Ten
  reviews in week one materially changes conversion on your listing.

### Days 9–14 — Sustain

- Keep posting daily. Launch day is a spike; the algorithm rewards consistency.
- Reply to every review, every comment, every email. At your size this is
  possible and it converts.
- Ship the **rewards/progression system** as v1.1. A visible update in week 2–3
  signals an alive app to both the stores and your users.

---

## 4. Short-form video — 10 hooks that fit this app

Format: 15–30 seconds, hands + keyboard + screen, no face required, trending
audio. Post the same clip to TikTok, Reels, and Shorts.

1. "I made an app that scores your scale practice. Here's my C major." — screen
   shows the score. Pure demo, best first post.
2. "Rating my own scales out of 100" — play deliberately badly, then well.
3. "POV: your metronome can finally tell you you're wrong."
4. "How fast can you actually play a chromatic scale?" — challenge format,
   invites duets.
5. "Grade 5 scales, scored" — targets exam students directly.
6. "The most boring part of piano, gamified."
7. "I practiced scales every day for a week. Here's the streak."
8. "Guess my score before it shows up." — comment bait, drives engagement.
9. "Every mode of the major scale in 30 seconds."
10. "Piano teachers: this grades scales so you don't have to." — teacher-targeted.

Two rules: the app must be visible in the **first second** (no logo intros), and
your bio link goes to the landing page, never straight to the store.

---

## 5. Direct outreach templates

### Piano teacher email

> Subject: Free practice tool for your students (scales)
>
> Hi [Name] — I'm a [pianist/developer] and I built an app called Scale Runner
> because I hated practicing scales.
>
> It connects to a MIDI keyboard and scores each scale run on timing and
> accuracy, so students get instant feedback instead of guessing whether they
> played it evenly. Streaks keep them coming back between lessons.
>
> It launches [date]. I'd like to give you and your students free lifetime
> access — no strings, I just want feedback from people who teach this every
> day. Reply and I'll send codes.
>
> — Channing

Send 10/day. Find them via local music school sites, Google "piano lessons
[city]," and YouTube piano educators under 50k subs (the big ones won't reply;
smaller creators often will).

### Beta tester email

> Subject: Scale Runner is launching — one favor
>
> You've been testing Scale Runner for a while and your feedback shaped what
> shipped. It goes live on [date].
>
> Two asks, both 30 seconds: install it from the store on launch day (the store
> version, even if you have the beta — day-one installs matter a lot for
> ranking), and leave a review if you've gotten anything out of it.
>
> Your Pro unlock code is attached — that's yours permanently.
>
> Thanks for putting up with the broken builds.

**Important detail:** beta testers must **delete and reinstall**, not update in
place, because iOS caches the app-site-association at install time.

---

## 6. What NOT to do

- **Don't buy ads.** At $0–100, paid acquisition in a niche this small produces
  noise, not signal. Your acquisition cost would exceed $14.99 immediately.
- **Don't delay launch to build the rewards system.** Ship, then update.
- **Don't chase Product Hunt.** It's a developer/SaaS audience; pianists aren't
  there. It costs a full day of prep for downloads that don't retain.
- **Don't go free-with-ads to boost installs.** $14.99 one-time on a
  high-intent niche audience is the right model. Cheap installs from the wrong
  people tank your retention metrics, which is what the stores actually rank on.
- **Don't spread across six platforms.** Three video platforms from one clip,
  plus email, plus outreach. That's it.

---

## 7. What to measure

Track weekly in a plain spreadsheet. Vanity metrics will lie to you; these won't.

| Metric | Week 1 target | Why |
|---|---|---|
| Installs | 100–300 | Realistic for $0 budget in a niche |
| Day-7 retention | >20% | The number that predicts whether this works at all |
| Store reviews | 10+ | Compounds into listing conversion forever |
| Pro conversion | 2–5% | Normal for one-time unlock |
| Email list | 150+ | Your only owned channel |

**Retention is the one that matters.** 100 installs with 30% D7 retention is a
real product worth pushing on. 1,000 installs with 3% retention is a leaky
bucket, and pouring marketing into it wastes the effort. If retention is weak
after week one, stop marketing and fix the product — the rewards system is
almost certainly the fix.

---

## Sources

- [Google Play's 12 Testers, 14 Days Requirement Explained (2026)](https://ontest.app/blog/google-play-12-testers-14-days-requirement-explained)
- [App Store Review Times 2026: Apple vs Google Play vs Chrome](https://extensionbooster.net/blog/260725-app-store-review-times-2026-apple-google-play-chrome-compared/)
- [App Store Review Time for Mobile Apps in 2026](https://www.lowcode.agency/blog/app-store-review-time)
- [9 best piano learning apps in 2026](https://www.skoove.com/blog/best-piano-apps/)
