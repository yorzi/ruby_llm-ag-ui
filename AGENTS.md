# AGENTS.md

## Docs

The documentation site lives in `docs/`: Jekyll with the jekyll-vitepress-theme, in four collections (`_getting_started`, `_core_features`, `_advanced`, `_reference`). Preview it with `docs/bin/serve.sh` and build it with `docs/bin/build.sh`.

- A public API change is not done until its docs page changes in the same commit. Record anything that breaks existing code in `docs/_reference/upgrading.md`.
- Write in the Rails guides voice: second person, present tense, short sentences, code first, and the problem before the mechanics. No em dashes, no hype, no "simply".
- Every guide opens with its title, its description, and "After reading this guide, you will know". Explain a concept before summarizing it in a table.
- Start with the shortest working example, then options, then integration and backend-specific notes. Document a shared API once.
- Give each standalone feature a discoverable guide, and feature new ones on the release's What's New page.
- Front-matter `description` is one sentence and feeds llms.txt and link previews. Never use `&`, `<`, or `>` in it.
- Cross-link with `{% link _collection/page.md %}`, never hard-coded URLs. Keep values that change between releases in `_config.yml` and read them as `site.*` variables.
- Never edit generated pages; regenerate them.
- Public methods and classes get doc comments; mark internal code as internal.
