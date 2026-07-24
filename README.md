# Blackjack Ensemble — a course

Short, hands-on lessons that take you from "I just cloned it" to confidently
pairing on Ted Young's `blackjack-ensemble-blue`: where code lives, why the
tests are shaped the way they are, and how to drive changes red→green→refactor.

The lessons are self-contained static HTML (one shared stylesheet, no build
step) — served as a website via Cloudflare Pages.

## Structure

- [`index.html`](index.html) — course home / table of contents
- [`lessons/`](lessons/) — the lessons, in order
- [`reference/`](reference/) — reference cards (IntelliJ shortcuts, repo map)
- [`assets/course.css`](assets/course.css) — shared stylesheet
- [`learning-records/`](learning-records/) — records of what has been learned

## Viewing locally

Open `index.html` in a browser, or serve the folder:

```bash
python3 -m http.server 8000
# then visit http://localhost:8000
```

## Deployment

Deployed as a static site on Cloudflare Pages. Run `./deploy.sh` to publish
(requires an authenticated wrangler: `npx wrangler login`).
